"""Streaming transcription: type words as soon as two consecutive Whisper passes agree on them.

LocalAgreement-2, as in whisper_streaming (Macháček et al., 2023). Pure logic here; the model is passed in.
"""
from . import core

SAMPLE_RATE = 16_000
TRIM_SECONDS = 10  # keep Whisper's window short: cut audio already committed once the buffer passes this


def _norm(word):
    return core.fold(word)  # "Parra." and "parra" are the same word


class LocalAgreement:
    """Commit the longest prefix a new pass shares with either of the two passes before it.

    Whisper on a growing buffer sometimes returns a garbage pass (one word, or an invented sentence);
    comparing only with the previous pass would lose the words that pass skipped.
    """

    def __init__(self):
        self.committed = []  # (start, end, text) in absolute seconds
        self.recent = []  # raw words of the last two passes

    @property
    def last_end(self):
        return self.committed[-1][1] if self.committed else 0.0

    def _fresh(self, words):
        if not self.committed:
            return words
        # Filter on the last word's start: Whisper stretches the end of the last word in the buffer.
        new = [w for w in words if w[0] > self.committed[-1][0] + 0.05]
        # The same words can come back at the start of a new pass: drop that overlap.
        for n in range(min(5, len(new), len(self.committed)), 0, -1):
            if [_norm(w[2]) for w in self.committed[-n:]] == [_norm(w[2]) for w in new[:n]]:
                return new[n:]
        return new

    def update(self, words):
        """Feed a hypothesis; return the words newly committed."""
        new, best = self._fresh(words), []
        for old in self.recent:
            agreed = []
            for a, b in zip(new, self._fresh(old)):
                if _norm(a[2]) != _norm(b[2]):
                    break
                agreed.append(a)
            best = max(best, agreed, key=len)
        self.committed += best
        self.recent = (self.recent + [words])[-2:]
        return best

    def finish(self, words):
        """Last pass: commit everything it heard."""
        new = self._fresh(words)
        self.committed += new
        self.recent = []
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
        start = self.offset / SAMPLE_RATE
        # No prompt: on short buffers it makes Whisper loop and drop words (measured 2026-11-08, see state.md).
        return [(s + start, e + start, t) for s, e, t in self.transcribe(buf, None)]

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
