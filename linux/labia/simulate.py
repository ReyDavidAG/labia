"""Stream a WAV file through a Session as if spoken live: `python -m labia --simulate audio.wav`."""
import time
import wave

import numpy as np

from . import engine
from .core import Preferences
from .stream import SAMPLE_RATE, Session

STEP = 0.5  # seconds of new audio between passes


def read_wav(path):
    with wave.open(path) as w:
        assert w.getframerate() == SAMPLE_RATE and w.getnchannels() == 1 and w.getsampwidth() == 2, "16 kHz mono 16-bit"
        return np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768


def run(path, model=None):
    prefs = Preferences()
    model = model or engine.load(prefs.model)
    s = Session(engine.transcriber(model, prefs.language), prefs)
    audio, screen, costs = read_wav(path), "", []
    n = int(STEP * SAMPLE_RATE)
    for i in range(0, len(audio), n):
        s.feed(audio[i : i + n])
        t = time.perf_counter()
        back, add = s.step()
        costs.append(time.perf_counter() - t)
        screen = screen[: len(screen) - back] + add
        print(f"{(i + n) / SAMPLE_RATE:6.1f}s  pass {costs[-1]:.2f}s  -{back:<3} +{add!r}")
    t = time.perf_counter()
    back, add, send = s.finish()
    screen = screen[: len(screen) - back] + add
    print(f"final  {time.perf_counter() - t:.2f}s  -{back} +{add!r} send={send}")
    print(f"\npasses: median {sorted(costs)[len(costs) // 2]:.2f}s, max {max(costs):.2f}s (must stay under {STEP}s to keep up)")
    print(f"\n{screen}")
    return screen
