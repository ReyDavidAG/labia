"""Streaming transcription: type words as soon as two consecutive Whisper passes agree on them.

LocalAgreement-2, as in whisper_streaming (Macháček et al., 2023). Pure logic here; the model is passed in.
"""
from . import core

SAMPLE_RATE = 16_000
TRIM_SECONDS = 10  # keep Whisper's window short: cut audio already committed once the buffer passes this
REFINE_SECONDS = 3  # every this much new audio, a careful pass (beam 5 + VAD) rewrites what is already typed
GARBAGE_RATIO = 0.6  # a refine pass with fewer words than this share of what it replaces is a bad pass: ignore it


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
    """One dictation. `transcribe(samples, prompt, beam=, vad=) -> [(start, end, text)]`, times relative to samples.

    Like Apple's SpeechTranscriber: fast passes type a draft, careful passes replace it for the same audio,
    and audio trimmed out of the window is final. On release, one careful pass over the whole recording.
    """

    def __init__(self, transcribe, prefs):
        self.transcribe = transcribe
        self.prefs = prefs
        self.agreement = LocalAgreement()
        self.audio = []  # float32 chunks of the current window
        self.full = []  # every chunk, for the final pass
        self.refined_at = 0  # self.samples at the last careful pass
        self.samples = 0  # total samples received
        self.offset = 0  # samples already trimmed from the front
        self.typed = ""  # what is on screen right now

    def feed(self, chunk):
        self.audio.append(chunk)
        self.full.append(chunk)
        self.samples += len(chunk)

    def _buffer(self):
        import numpy as np

        buf = np.concatenate(self.audio) if self.audio else np.zeros(0, np.float32)
        self.audio = [buf]
        return buf

    def _hypothesis(self, **careful):
        buf = self._buffer()
        start = self.offset / SAMPLE_RATE
        # No prompt: on short buffers it makes Whisper loop and drop words (measured 2026-11-08, see state.md).
        return [(s + start, e + start, t) for s, e, t in self.transcribe(buf, None, **careful)]

    def _refine(self):
        """Careful pass over the window: replace the committed words it covers (the micro-correction)."""
        start = self.offset / SAMPLE_RATE
        old = self.agreement.committed
        frozen = [w for w in old if w[0] < start]  # trimmed out of the window: final
        window = old[len(frozen):]
        if not window:
            return
        limit = window[-1][0] + 0.15  # up to the last committed word; the rest is still a draft
        new = [w for w in self._hypothesis(beam=5, vad=True) if w[0] <= limit]
        if len(new) >= GARBAGE_RATIO * len(window):
            self.agreement.committed = frozen + new

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
        if self.samples - self.refined_at >= REFINE_SECONDS * SAMPLE_RATE and self.agreement.committed:
            self.refined_at = self.samples
            self._refine()
        else:
            self.agreement.update(self._hypothesis())
        self._trim()
        target = hold_last_word(self._clean(self.agreement.text))
        return self._apply(target)

    def finish(self):
        """Final pass over the whole recording, careful. Returns (backspaces, text, send)."""
        import numpy as np

        full = np.concatenate(self.full) if self.full else np.zeros(0, np.float32)
        raw = "".join(t for _, _, t in self.transcribe(full, None, beam=5, vad=True))
        text, send = self._clean(raw), False
        if self.prefs.send_on_keyword:
            text, send = core.split_send(text, self.prefs.send_keywords)
        if text and self.prefs.trailing_space and not send and not text.endswith("\n"):
            text += " "
        return (*self._apply(text), send)

    def _apply(self, target):
        back, add = diff(self.typed, target)
        self.typed = target
        return back, add
