"""Applies an update to a git install of Labia, outside the running app, and rolls back if it goes wrong.

    python -m labia.update --objetivo <commit> --rama main --etiqueta 1.0.1 [--pip]

Labia starts this and exits (Windows can't replace DLLs in use, so pip can't run with Labia open). Steps:

1. Wait for the running Labia to let go of its single-instance mutex (Windows).
2. Move the copy to the new commit (updater.advance) and, if requirements.txt changed, run pip.
3. Start the new Labia and wait for it to say it is ready (update.json, written by app.py).
4. If any step fails, or it isn't ready in time: back to the previous commit (and its packages), start that
   one, and leave a notice so it tells the user.

Everything goes to update.log next to the settings. Imports stay light (no numpy, no sounddevice): pip may be
replacing exactly those.
"""
import argparse
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

from . import core, updater

STATE = core.DATA_DIR / "update.json"
LOG = core.DATA_DIR / "update.log"
READY_TIMEOUT = 300  # s: first start after a pip upgrade can be slow (CUDA libraries, model load)
WINDOWS = sys.platform == "win32"
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)


def log(msg):
    LOG.parent.mkdir(parents=True, exist_ok=True)
    lines = LOG.read_text(encoding="utf-8").splitlines()[-400:] if LOG.exists() else []
    lines.append(f"{datetime.now():%Y-%m-%d %H:%M:%S} {msg}")
    LOG.write_text("\n".join(lines) + "\n", encoding="utf-8")


def state():
    data = core.read_json(STATE, {})
    return data if isinstance(data, dict) else {}


def save_state(**changes):
    data = state()
    data.update(changes)
    core.write_json(STATE, data, indent=2)


def python():
    """The venv's interpreter, windowless on Windows."""
    exe = Path(sys.executable)
    w = exe.with_name("pythonw.exe")
    return str(w if WINDOWS and w.exists() else exe)


def under_systemd():
    return not WINDOWS and "INVOCATION_ID" in os.environ


def start_labia(cwd):
    """Start Labia the way it normally runs here. Returns the process to watch (None under systemd)."""
    if under_systemd():
        subprocess.run(["systemctl", "--user", "restart", "labia"], check=True)
        return None
    return subprocess.Popen([python(), "-m", "labia"], cwd=cwd, creationflags=NO_WINDOW)


def stop_labia(proc):
    if under_systemd():
        subprocess.run(["systemctl", "--user", "stop", "labia"])
    elif proc and proc.poll() is None:
        if WINDOWS:
            from . import tray_windows

            tray_windows.post_to_running("quit")
            try:
                proc.wait(15)
                return
            except subprocess.TimeoutExpired:
                pass
        proc.kill()


def pip_install(root):
    log("pip install -r linux/requirements.txt")
    r = subprocess.run([python(), "-m", "pip", "install", "--quiet", "--disable-pip-version-check", "-r",
                        str(root / updater.REQUIREMENTS)], capture_output=True, text=True, creationflags=NO_WINDOW)
    if r.returncode != 0:
        raise RuntimeError(f"pip falló: {(r.stderr or r.stdout).strip()[-300:]}")


def wait_ready(target, proc):
    """True once the new Labia reports it loaded `target`; False if it died or took too long."""
    end = time.monotonic() + READY_TIMEOUT
    while time.monotonic() < end:
        if state().get("ready") == target:
            return True
        if proc is not None and proc.poll() is not None:
            log(f"Labia salió al arrancar (código {proc.returncode})")
            return False
        time.sleep(1)
    log("Labia no estuvo lista a tiempo")
    return False


def wait_for_exit():
    """The old Labia is closing (it may be finishing a dictation): wait until its mutex is free."""
    if WINDOWS:
        from . import win32

        if not win32.claim_single_instance("Local\\Labia", wait=60):
            raise RuntimeError("Labia no se cerró")
        win32.release_single_instance("Local\\Labia")  # the new Labia must be able to take it


def apply(root, target, branch, label, needs_pip):
    cwd = root / "linux"
    previous = updater.describe(root)
    log(f"actualizar {previous} -> {label} ({target[:7]}, rama {branch}{', pip' if needs_pip else ''})")
    wait_for_exit()
    old = None
    try:
        old = updater.advance(root, updater.Update(target, label, branch))
        if needs_pip:
            pip_install(root)
        # The notice goes first: the new Labia reads it the moment it is ready, before we'd see that it is.
        save_state(ready=None, notice={"kind": "updated", "label": label, "previous": previous, "target": target})
        proc = start_labia(cwd)
        if wait_ready(target, proc):
            log(f"listo: {label}")
            return True
        stop_labia(proc)
        raise RuntimeError("la versión nueva no arrancó")
    except Exception as err:  # anything: the user must end up with a working Labia
        log(f"falló: {err}")
        if old:
            updater.roll_back(root, old)
            log(f"regresé a {previous}")
            if needs_pip:
                try:
                    pip_install(root)
                except Exception as pip_err:
                    log(f"pip al regresar: {pip_err}")
        save_state(notice={"kind": "failed", "label": label, "previous": previous, "error": str(err)[:200]})
        start_labia(cwd)
        return False


def main():
    p = argparse.ArgumentParser(prog="labia.update")
    p.add_argument("--objetivo", required=True)
    p.add_argument("--rama", required=True, choices=sorted(updater.BRANCH.values()))
    p.add_argument("--etiqueta", required=True)
    p.add_argument("--pip", action="store_true")
    args = p.parse_args()
    root = updater.repo_root()
    if root is None:
        log("no es una copia de git: nada que hacer")
        return 1
    return 0 if apply(root, args.objetivo, args.rama, args.etiqueta, args.pip) else 1


if __name__ == "__main__":
    sys.exit(main())
