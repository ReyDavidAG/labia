"""The live loop: hotkey thread drives the GestureMachine, a worker thread streams mic audio into a Session."""
import os
import queue
import subprocess
import sys
import threading
import time
from pathlib import Path

import numpy as np
import sounddevice as sd

from . import audio, core, engine

if sys.platform == "win32":
    from . import hotkey_windows as hotkey
else:
    from . import hotkey
from .simulate import STEP
from .stream import SAMPLE_RATE, Session


class PillClient:
    """Talks to the pill, a separate process: pill.py (GTK, system Python) or pill_windows.py (tkinter).

    Silent no-op if it can't run.
    """

    def __init__(self):
        import ctypes.util
        import os
        import subprocess
        from pathlib import Path

        self.proc, self.lock = None, threading.Lock()
        if sys.platform == "win32":
            self.proc = subprocess.Popen([sys.executable, str(Path(__file__).with_name("pill_windows.py"))],
                                         stdin=subprocess.PIPE, text=True, encoding="utf-8",
                                         creationflags=subprocess.CREATE_NO_WINDOW)
            return
        lib = ctypes.util.find_library("gtk4-layer-shell")
        if not lib:
            print("sin cápsula: instala gtk4-layer-shell (sudo pacman -S gtk4-layer-shell)")
            return
        # gtk4-layer-shell must load before libwayland-client, hence the preload.
        self.proc = subprocess.Popen(["/usr/bin/python3", str(Path(__file__).with_name("pill.py"))],
                                     stdin=subprocess.PIPE, text=True, env={**os.environ, "LD_PRELOAD": lib})

    def send(self, **msg):
        import json

        with self.lock:
            if not self.proc:
                return
            try:
                self.proc.stdin.write(json.dumps(msg) + "\n")
                self.proc.stdin.flush()
            except (BrokenPipeError, ValueError):
                self.proc = None

    def close(self):
        with self.lock:
            if self.proc:
                self.proc.terminate()
                self.proc = None


def level(chunk):
    """Mic chunk -> 0..1 for the waveform, same curve as the macOS Recorder."""
    rms = float(np.sqrt(np.mean(chunk * chunk))) if len(chunk) else 0.0
    return 0.0 if rms <= 0 else min(1.0, max(0.0, (20 * np.log10(rms) + 52) / 38))


class Dictation(threading.Thread):
    """One dictation: record, transcribe every STEP seconds, type as words get confirmed."""

    def __init__(self, transcribe, prefs, typer, pill, after=None):
        super().__init__(daemon=True)
        self.pill = pill
        self.after = after  # previous dictation, maybe still on its last pass: let it finish typing first
        self.session = Session(transcribe, prefs)
        self.prefs, self.typer = prefs, typer
        self.audio = queue.Queue()
        self.outcome = None  # "finish", "cancel", "short" or "chord", set by the hotkey thread
        self.done = threading.Event()

    def stop(self, outcome):
        self.outcome = outcome
        self.done.set()

    def _drain(self):
        chunks = []
        while not self.audio.empty():
            chunks.append(self.audio.get_nowait())
        if chunks:
            self.session.feed(np.concatenate(chunks))
        return sum(map(len, chunks))

    def run(self):
        s, t0, stream, began = self.session, time.monotonic(), None, False
        def on_audio(data, *_):
            self.audio.put(data[:, 0].copy())
            self.pill.send(level=level(data[:, 0]))

        try:
            # Inside the try: if the mic can't open (unplugged, busy), the pill must say so instead of
            # staying on «listening» forever.
            stream = sd.InputStream(samplerate=SAMPLE_RATE, channels=1, dtype="float32", blocksize=800,
                                    device=audio.resolve_device(self.prefs.input_device), callback=on_audio)
            stream.start()  # record from the keypress, even while the previous dictation finishes
            if self.after:
                self.after.join()
            self.typer.begin()
            began = True
            while not self.done.wait(STEP):
                if time.monotonic() - t0 > self.prefs.max_recording_seconds:
                    self.outcome = "finish"
                    break
                if self._drain() and self.prefs.auto_type:
                    self.typer.apply(*s.step())
            stream.close()
            self._drain()
            if self.outcome in ("cancel", "short", "chord") or s.samples < SAMPLE_RATE * 0.3:
                self.typer.apply(len(s.typed), "")
                self.pill.send(state={"cancel": "cancelled", "chord": "hide"}.get(self.outcome, "short"))
                print("cancelada")
                return
            self.pill.send(state="transcribing")
            back, add, send = s.finish()
            if self.prefs.auto_type:
                self.typer.apply(back, add)
                if send:
                    self.typer.enter()
            text = s.typed.strip()
            if text:
                core.add_history(text, s.samples / SAMPLE_RATE)
                self.pill.send(state="done", words=len(text.split()))
            else:
                self.pill.send(state="silent")
            print(f"{s.samples / SAMPLE_RATE:.1f}s: {text!r}{' ⏎' if send else ''}")
        except Exception as err:
            self.pill.send(state="failed", text=str(err)[:60])
            raise
        finally:
            if stream:
                stream.close()  # no-op if already closed
            if began:  # the typer is shared: don't restore the clipboard under a previous dictation still typing
                self.typer.end()


PACKAGE_ROOT = Path(__file__).resolve().parent.parent  # the folder holding the labia package: cwd for child processes


def open_window(tab="general"):
    """The settings window, a separate process like the pill (tkinter wants its own main thread)."""
    subprocess.Popen([sys.executable, "-m", "labia.settings_windows", "--tab", tab], cwd=PACKAGE_ROOT,
                     creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))


def relaunch():
    """A new Labia that waits for this one to exit (single-instance mutex) before taking over."""
    subprocess.Popen([sys.executable, "-m", "labia", "--reiniciar"], cwd=PACKAGE_ROOT,
                     creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))


class NullTray:
    """Linux has no tray icon (yet): same calls, nothing happens."""

    def set_status(self, text, paused=None):
        pass

    def notify(self, title, text):
        pass

    def close(self):
        pass


def settings_stamp():
    try:
        return (core.CONFIG_DIR / "settings.json").stat().st_mtime_ns
    except OSError:
        return None


def run(open_settings=False, restarting=False):
    windows = sys.platform == "win32"
    if windows:
        from . import tray_windows, win32
        from .typer_windows import Typer

        # Before loading the model: a second copy must not take the keyboard. Opened again from Start, it shows
        # the running one's settings instead of doing nothing.
        if not win32.claim_single_instance(wait=15 if restarting else 0):
            if open_settings:
                tray_windows.post_to_running("settings")
            raise SystemExit("Labia ya está abierta.")
    else:
        from .typer import Typer  # needs uinput and wl-copy; keep --simulate usable without them

    quitting, paused, restart = threading.Event(), threading.Event(), threading.Event()
    ready, pill, tray = threading.Event(), None, None

    def shutdown_now():
        """Quit while the model still loads: no dictation can be running, nothing to wait for."""
        tray.close()
        if restart.is_set():
            relaunch()
        os._exit(0)

    def on_command(command):  # tray thread
        if command in ("settings", "history"):
            open_window("history" if command == "history" else "general")
        elif command == "pause":
            (paused.clear if paused.is_set() else paused.set)()
            tray.set_status(status(), paused=paused.is_set())
        elif command in ("restart", "quit"):
            if command == "restart":
                restart.set()
            quitting.set()
            if not ready.is_set():
                shutdown_now()

    prefs, stamp = core.Preferences.load(), settings_stamp()
    label = getattr(hotkey, "LABELS", {}).get(prefs.hotkey, prefs.hotkey)

    def status():
        if not ready.is_set():
            return "Cargando modelo…"
        return "En pausa" if paused.is_set() else f"Lista · mantén {label} y habla"

    tray = tray_windows.Tray(on_command) if windows else NullTray()
    tray.set_status(status())
    if open_settings:
        open_window()
    print("cargando modelo…")
    transcribe = engine.transcriber(engine.load(prefs.model), prefs.language)
    typer = Typer()
    pill = PillClient()
    gestures, current = core.GestureMachine(), None
    ready.set()
    tray.set_status(status())
    print(f"listo: mantén {prefs.hotkey} y habla (doble toque = manos libres, esc cancela)")
    for event, t in hotkey.events(prefs.hotkey):
        if quitting.is_set():
            break
        if paused.is_set():
            if gestures.is_recording and current:
                current.stop("cancel")
            gestures.reset()
            continue
        action = gestures.handle(event, t)
        if action == core.START:
            if (new := settings_stamp()) != stamp:  # saved from the settings window; hotkey and model need a restart
                prefs, stamp = core.Preferences.load(), new
            if not (current and current.is_alive()):
                audio.refresh()  # no stream open now: pick up a mic plugged in since the last dictation
            pill.send(state="listening")
            current = Dictation(transcribe, prefs, typer, pill, after=current)
            current.start()
        elif action == core.LOCK:
            pill.send(state="locked")
            print("manos libres")
        elif action in (core.STOP, core.CANCEL, core.TOO_SHORT, core.CHORD) and current:
            current.stop({core.STOP: "finish", core.CANCEL: "cancel", core.TOO_SHORT: "short"}.get(action, "chord"))
            # no join: this loop also forwards the keyboard, it must never wait on Whisper

    # Quit or restart: a dictation still typing may be holding Ctrl down for a paste, let it finish.
    if current and current.is_alive():
        if gestures.is_recording:
            current.stop("cancel")
        current.join(10)
    pill.close()
    tray.close()
    if restart.is_set():
        relaunch()