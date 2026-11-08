"""Streaming transcription: type words as soon as two consecutive Whisper passes agree on them.

LocalAgreement-2, as in whisper_streaming (Macháček et al., 2023). Pure logic here; the model is passed in.
"""
from . import core

SAMPLE_RATE = 16_000
TRIM_SECONDS = 15  # keep Whisper's window short: cut audio already committed once the buffer passes this
PROMPT_TAIL = 200  # characters of committed text fed back as context


def _norm(word):
    return word.strip()


class LocalAgreement:
    def __init__(self):
        self.committed = []  # (start, end, text) in absolute seconds
        self.pending = []  # last hypothesis, minus what got committed

    @property
    def last_end(self):
        return self.committed[-1][1] if self.committed else 0.0

    def _fresh(self, words):
        new = [w for w in words if w[0] > self.last_end - 0.1]
        # The same words can come back at the start of a new pass: drop that overlap.
        if new and self.committed and abs(new[0][0] - self.last_end) < 1:
            for n in range(min(5, len(new), len(self.committed)), 0, -1):
                if [_norm(w[2]) for w in self.committed[-n:]] == [_norm(w[2]) for w in new[:n]]:
                    return new[n:]
        return new

    def update(self, words):
        """Feed a hypothesis; return the words newly committed."""
        new = self._fresh(words)
        agreed = []
        for a, b in zip(new, self.pending):
            if _norm(a[2]) != _norm(b[2]):
                break
            agreed.append(a)
        self.committed += agreed
        self.pending = new[len(agreed):]
        return agreed

    def finish(self, words):
        """Last pass: commit everything it heard."""
        new = self._fresh(words)
        self.committed += new
        self.pending = []
        return new

    @property
    def text(self):
        return "".join(w[2] for w in self.committed)


def diff(typed, target):
    """(backspaces, text to type) that turn `typed` into `target`."""
    k = 0
    for a, b in zip(typed, target):
        if a != b:
            break
        k += 1
    return len(typed) - k, target[k:]


def hold_last_word(text):
    """While still speaking, keep the last word back: cleaning or the send keyword may change it."""
    cut = text.rstrip().rfind(" ")
    return text[:cut] if cut > 0 else ""


class Session:
    """One dictation. `transcribe(samples, prompt) -> [(start, end, text)]` with times relative to samples."""

    def __init__(self, transcribe, prefs):
        self.transcribe = transcribe
        self.prefs = prefs
        self.agreement = LocalAgreement()
        self.audio = []  # float32 chunks
        self.samples = 0  # total samples received
        self.offset = 0  # samples already trimmed from the front
        self.typed = ""  # what is on screen right now

    def feed(self, chunk):
        self.audio.append(chunk)
        self.samples += len(chunk)

    def _buffer(self):
        import numpy as np

        buf = np.concatenate(self.audio) if self.audio else np.zeros(0, np.float32)
        self.audio = [buf]
        return buf

    def _hypothesis(self):
        buf = self._buffer()
        tail = self.agreement.text[-PROMPT_TAIL:].strip()
        prompt = " ".join(p for p in (self.prefs.prompt, tail) if p) or None
        start = self.offset / SAMPLE_RATE
        return [(s + start, e + start, t) for s, e, t in self.transcribe(buf, prompt)]

    def _trim(self):
        buf = self._buffer()
        if len(buf) / SAMPLE_RATE < TRIM_SECONDS or not self.agreement.committed:
            return
        cut = int(self.agreement.last_end * SAMPLE_RATE) - self.offset
        if cut > 0:
            self.audio = [buf[cut:]]
            self.offset += cut

    def _clean(self, raw):
        p = self.prefs
        return core.clean(raw, p.replacements, p.vocabulary)

    def step(self):
        """Mid-dictation pass. Returns (backspaces, text) to apply on screen."""
        self.agreement.update(self._hypothesis())
        self._trim()
        target = hold_last_word(self._clean(self.agreement.text))
        return self._apply(target)

    def finish(self):
        """Final pass. Returns (backspaces, text, send)."""
        self.agreement.finish(self._hypothesis())
        text, send = self._clean(self.agreement.text), False
        if self.prefs.send_on_keyword:
            text, send = core.split_send(text, self.prefs.send_keywords)
        if text and self.prefs.trailing_space and not send and not text.endswith("\n"):
            text += " "
        return (*self._apply(text), send)

    def _apply(self, target):
        back, add = diff(self.typed, target)
        self.typed = target
        return back, add
