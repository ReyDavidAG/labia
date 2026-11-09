"""Labia's shortcuts: Start menu (so «Labia» shows up in Windows search) and Startup (open at sign-in).

    python -m labia.shortcuts_windows instalar [--inicio]   # Start menu; --inicio also opens Labia at sign-in
    python -m labia.shortcuts_windows quitar                # removes both

Shortcuts are written by WScript.Shell through PowerShell (no pywin32). Paths travel in environment variables,
never inside the script text, so a path with quotes or $ can't change what runs.
"""
import argparse
import ctypes
import os
import subprocess
import sys
from ctypes import wintypes as w
from pathlib import Path

PACKAGE = Path(__file__).resolve().parent
ICON = PACKAGE / "labia.ico"
NAME = "Labia.lnk"
CSIDL_PROGRAMS, CSIDL_STARTUP = 2, 7

_PS = """$s = (New-Object -ComObject WScript.Shell).CreateShortcut($env:LABIA_LNK)
$s.TargetPath = $env:LABIA_TARGET
$s.Arguments = $env:LABIA_ARGS
$s.WorkingDirectory = $env:LABIA_DIR
$s.IconLocation = $env:LABIA_ICON
$s.Description = 'Dictado en español: mantén AltGr y habla'
$s.Save()"""


def _folder(csidl):
    buf = ctypes.create_unicode_buffer(w.MAX_PATH)
    ctypes.windll.shell32.SHGetFolderPathW(None, csidl, None, 0, buf)
    return Path(buf.value)


def start_menu_shortcut():
    return _folder(CSIDL_PROGRAMS) / NAME


def startup_shortcut():
    return _folder(CSIDL_STARTUP) / NAME


def pythonw():
    """pythonw.exe next to the running interpreter (the venv's), so Labia opens without a console."""
    exe = Path(sys.executable)
    candidate = exe.with_name("pythonw.exe")
    return candidate if candidate.exists() else exe


def create(lnk, args):
    env = {**os.environ, "LABIA_LNK": str(lnk), "LABIA_TARGET": str(pythonw()), "LABIA_ARGS": args,
           "LABIA_DIR": str(PACKAGE.parent), "LABIA_ICON": str(ICON)}
    lnk.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", _PS], env=env, check=True,
                   capture_output=True, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))


def remove(lnk):
    lnk.unlink(missing_ok=True)


def startup_enabled():
    return startup_shortcut().exists()


def set_startup(on):
    """Open Labia at sign-in (no window: it only shows its tray icon)."""
    if on:
        create(startup_shortcut(), "-m labia")
    else:
        remove(startup_shortcut())


def install(startup=False):
    create(start_menu_shortcut(), "-m labia --abrir")  # from Start it opens the settings window
    if startup:
        set_startup(True)


def uninstall():
    remove(start_menu_shortcut())
    remove(startup_shortcut())


def main():
    p = argparse.ArgumentParser(prog="labia.shortcuts_windows", description="Accesos directos de Labia.")
    sub = p.add_subparsers(dest="cmd", required=True)
    i = sub.add_parser("instalar", help="Labia en el menú Inicio")
    i.add_argument("--inicio", action="store_true", help="y abrirla al iniciar sesión")
    sub.add_parser("quitar", help="borra los accesos directos")
    args = p.parse_args()
    if args.cmd == "instalar":
        install(args.inicio)
        print(f"Menú Inicio: {start_menu_shortcut()}")
        if args.inicio:
            print(f"Inicio de sesión: {startup_shortcut()}")
    else:
        uninstall()
        print("Accesos directos borrados.")


if __name__ == "__main__":
    main()
