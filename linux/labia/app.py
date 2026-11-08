"""The live loop: hotkey thread drives the GestureMachine, a worker thread streams mic audio into a Session."""
import queue
import threading
import time

import numpy as np
import sounddevice as sd

from . import core, engine, hotkey
from .simulate import STEP
from .stream import SAMPLE_RATE, Session


class Dictation(threading.Thread):
    """One dictation: record, transcribe every STEP seconds, type as words get confirmed."""

    def __init__(self, transcribe, prefs, typer):
        super().__init__(daemon=True)
        self.session = Session(transcribe, prefs)
        self.prefs, self.typer = prefs, typer
        self.audio = queue.Queue()
        self.outcome = None  # "finish" or "cancel", set by the hotkey thread
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
        s, t0 = self.session, time.monotonic()
        stream = sd.InputStream(samplerate=SAMPLE_RATE, channels=1, dtype="float32",
                                callback=lambda data, *_: self.audio.put(data[:, 0].copy()))
        self.typer.begin()
        try:
            with stream:
                while not self.done.wait(STEP):
                    if time.monotonic() - t0 > self.prefs.max_recording_seconds:
                        self.outcome = "finish"
                        break
                    if self._drain() and self.prefs.auto_type:
                        self.typer.apply(*s.step())
            self._drain()
            if self.outcome == "cancel" or s.samples < SAMPLE_RATE * 0.3:
                self.typer.apply(len(s.typed), "")
                print("cancelada")
                return
            back, add, send = s.finish()
            if self.prefs.auto_type:
                self.typer.apply(back, add)
                if send:
                    self.typer.enter()
            text = s.typed.strip()
            if text:
                core.add_history(text, s.samples / SAMPLE_RATE)
            print(f"{s.samples / SAMPLE_RATE:.1f}s: {text!r}{' ⏎' if send else ''}")
        finally:
            self.typer.end()


def run():
    from .typer import Typer  # needs uinput and wl-copy; keep --simulate usable without them

    prefs = core.Preferences.load()
    print("cargando modelo…")
    transcribe = engine.transcriber(engine.load(prefs.model), prefs.language)
    typer = Typer()
    gestures, current = core.GestureMachine(), None
    print(f"listo: mantén {prefs.hotkey} y habla (doble toque = manos libres, esc cancela)")
    for event, t in hotkey.events(prefs.hotkey):
        action = gestures.handle(event, t)
        if action == core.START:
            current = Dictation(transcribe, prefs, typer)
            current.start()
        elif action == core.LOCK:
            print("manos libres")
        elif action in (core.STOP, core.CANCEL, core.TOO_SHORT, core.CHORD) and current:
            current.stop("finish" if action == core.STOP else "cancel")
            current.join()  # ponytail: hotkeys are ignored while the last pass runs (~0.5 s)
            current = None
