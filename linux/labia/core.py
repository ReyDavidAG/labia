"""Port of LabiaCore (Sources/LabiaCore): pure logic, no I/O besides JSON files."""
import json
import locale
import os
import re
import unicodedata
import uuid
from dataclasses import asdict, dataclass, field, fields
from datetime import datetime, timezone
from pathlib import Path

# Swift's [\p{L}\p{N}] == "word char except underscore" in Python's re.
ALNUM = r"[^\W_]"


# --- GestureMachine -------------------------------------------------------

KEY_DOWN, KEY_UP, ESCAPE, OTHER_KEY, TICK = "keyDown", "keyUp", "escape", "otherKey", "tick"
START, STOP, LOCK, CANCEL, TOO_SHORT, CHORD = "start", "stop", "lock", "cancel", "tooShort", "chord"
IDLE, HOLDING, TAP_PENDING, LOCKED = "idle", "holding", "tapPending", "locked"


class GestureMachine:
    """Hold = record, double tap = hands-free until next press, esc = cancel, hotkey+other key = chord."""

    def __init__(self, min_hold=0.3, double_tap_window=0.35):
        self.min_hold = min_hold
        self.double_tap_window = double_tap_window
        self.phase, self.mark = IDLE, 0.0  # mark = hold start or tap deadline

    @property
    def is_recording(self):
        return self.phase != IDLE

    def handle(self, event, t=0.0):
        p = self.phase
        if p == IDLE and event == KEY_DOWN:
            self.phase, self.mark = HOLDING, t
            return START
        if p == HOLDING and event == KEY_UP:
            if t - self.mark < self.min_hold:
                self.phase, self.mark = TAP_PENDING, t + self.double_tap_window
                return None
            self.phase = IDLE
            return STOP
        if p == TAP_PENDING and event == KEY_DOWN:
            if t <= self.mark:
                self.phase = LOCKED
                return LOCK
            self.phase, self.mark = HOLDING, t
            return START
        if p == TAP_PENDING and event == TICK and t > self.mark:
            self.phase = IDLE
            return TOO_SHORT
        if p == LOCKED and event == KEY_DOWN:
            self.phase = IDLE
            return STOP
        if p != IDLE and event == ESCAPE:
            self.phase = IDLE
            return CANCEL
        if p in (HOLDING, TAP_PENDING) and event == OTHER_KEY:
            self.phase = IDLE
            return CHORD
        return None

    def reset(self):
        self.phase = IDLE


class Passthrough:
    """Which key events reach the apps: the hotkey only if it turns into a chord (AltGr+Q = @).

    Held alone, apps would see it as a modifier: Right Alt + our paste shortcut is not a paste.
    Codes are whatever the platform uses (evdev codes, Windows virtual keys).
    """

    def __init__(self, hotkey):
        self.hotkey, self.held, self.forwarded = hotkey, False, False

    def filter(self, code, value):
        """Return the (code, value) key events to re-emit for one incoming event. value: 1 down, 0 up, 2 repeat."""
        if code == self.hotkey:
            if value == 1:
                self.held, self.forwarded = True, False
                return []
            out = [(code, value)] if self.forwarded else []
            if value == 0:
                self.held = self.forwarded = False
            return out
        if value == 1 and self.held and not self.forwarded:
            self.forwarded = True
            return [(self.hotkey, 1), (code, value)]
        return [(code, value)]


# --- SendKeyword ----------------------------------------------------------

SEND_DEFAULTS = ["Claude", "cloud", "clod"]


def fold(word):
    """Lowercase, no accents, letters and digits only."""
    s = unicodedata.normalize("NFKD", word.casefold())
    return "".join(c for c in s if c.isalnum())


def split_send(text, keywords):
    """('Revisa el build, Claude.') -> ('Revisa el build', True)."""
    keys = {k for k in map(fold, keywords) if k}
    m = re.search(ALNUM + r"+[\W_]*$", text)
    if not keys or not m or fold(m.group()) not in keys:
        return text, False
    rest = re.sub(r'[\s,;:¡¿«“"(-]+$', "", text[: m.start()])
    return rest.strip(), True


# --- TextCleaner ----------------------------------------------------------

# Whisper invents these when the audio is silence or noise.
HALLUCINATIONS = [
    "subtítulos realizados por la comunidad de amara.org",
    "subtítulos por la comunidad de amara.org",
    "subtitulado por la comunidad de amara.org",
    "gracias por ver el video",
    "gracias por ver",
    "¡gracias por ver!",
    "suscríbete al canal",
    "no olvides suscribirte",
    "[música]",
    "(música)",
    "[blank_audio]",
    "[ruido]",
    "...",
]


def _key(s):
    return "".join(c for c in s.lower() if c.isalnum())


def clean(raw, replacements=(), vocabulary=()):
    text = re.sub(r"<\|[^|]*\|>", "", raw)
    text = strip_hallucinations(text)
    text = apply_vocabulary(text, vocabulary)
    for r in replacements:
        if r["from"].strip():
            text = replace(r, text)
    return tidy(text)


def apply_vocabulary(text, vocabulary):
    """Join split terms (Use API Query -> useApiQuery) and fix brand case (vercel -> Vercel)."""
    terms = [t.strip() for t in vocabulary if len(_key(t)) >= 3]
    if not terms:
        return text
    by_key = {}
    for t in terms:
        by_key.setdefault(_key(t), t)
    words = [m.span() for m in re.finditer(ALNUM + "+", text)]
    edits, i = [], 0
    while i < len(words):
        for n in range(min(4, len(words) - i), 0, -1):
            a, b = words[i][0], words[i + n - 1][1]
            original = text[a:b]
            if n > 1 and re.search(r"[^\w \-]|_", original):
                continue
            term = by_key.get(_key(original))
            if term is None or term == original or (n == 1 and term == term.lower()):
                continue
            edits.append((a, b, term))
            i += n
            break
        else:
            i += 1
    for a, b, term in reversed(edits):
        text = text[:a] + term + text[b:]
    return text


def strip_hallucinations(text):
    out = text.strip()
    changed = True
    while changed and out:
        changed = False
        lower = out.lower()
        for h in HALLUCINATIONS:
            if lower in (h, h + "."):
                return ""
            for cand in (h + ".", h):
                if lower.endswith(" " + cand):
                    out = out[: -len(cand)].strip(" \t")
                    changed = True
                    break
            if changed:
                break
    return out


def replace(r, text):
    pattern = r"(?<![^\W_])" + re.escape(r["from"].strip()) + r"(?![^\W_])"
    to = r["to"].replace("\\n", "\n")
    return re.sub(pattern, lambda _: to, text, flags=re.IGNORECASE)


def tidy(text):
    for pattern, repl in [
        (r"[ \t]+", " "),
        (r" *\n *", "\n"),
        (r" +([,.;:!?)\]])", r"\1"),
        (r"([(\[¿¡]) +", r"\1"),
    ]:
        text = re.sub(pattern, repl, text)
    return text.strip(" \t")


# --- Preferences ----------------------------------------------------------

if os.name == "nt":
    CONFIG_DIR = DATA_DIR = Path(os.environ.get("APPDATA", Path.home() / "AppData/Roaming")) / "Labia"
else:
    CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "labia"
    DATA_DIR = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "labia"
MAX_PROMPT_CHARS = 600


@dataclass
class Preferences:
    hotkey: str = "KEY_RIGHTALT"
    auto_type: bool = True
    trailing_space: bool = True
    send_on_keyword: bool = True
    send_keywords: list = field(default_factory=lambda: list(SEND_DEFAULTS))
    language: str = "es"
    model: str = "large-v3-turbo"
    vocabulary: list = field(default_factory=lambda: [
        "develop", "pull request", "deploy", "endpoint", "lint", "cron", "GitHub", "Vercel", "Supabase",
    ])
    replacements: list = field(default_factory=lambda: [
        {"from": "nueva línea", "to": "\\n"},
        {"from": "punto y coma", "to": ";"},
        {"from": "de velo", "to": "develop"},
    ])
    max_recording_seconds: int = 300
    input_device: str = ""  # microphone name; empty = the system default

    @property
    def prompt(self):
        words = [w.strip() for w in self.vocabulary if w.strip()]
        if not words:
            return None
        out = "Vocabulario:"
        for w in words:
            nxt = out + (" " if out.endswith(":") else ", ") + w
            if len(nxt) > MAX_PROMPT_CHARS:
                break
            out = nxt
        return out + "."

    @classmethod
    def load(cls, path=CONFIG_DIR / "settings.json"):
        """Missing or broken keys keep their defaults."""
        data = read_json(path, {})
        if not isinstance(data, dict):
            data = {}
        p = cls()
        for f in fields(cls):
            if f.name in data and type(data[f.name]) is type(getattr(p, f.name)):
                setattr(p, f.name, data[f.name])
        return p

    def save(self, path=CONFIG_DIR / "settings.json"):
        write_json(path, asdict(self), indent=2)


def read_json(path, default):
    """JSON from a UTF-8 file, or `default` if missing or broken.

    Files written before 0.5 used the locale encoding (cp1252 on Windows): read those too, so the history survives.
    """
    try:
        raw = Path(path).read_bytes()
    except OSError:
        return default
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        text = raw.decode(locale.getpreferredencoding(False), errors="replace")
    try:
        return json.loads(text)
    except ValueError:
        return default


def write_json(path, data, indent=1):
    """Write UTF-8 through a temp file, so a crash mid-write never leaves half a file."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=indent), encoding="utf-8")
    tmp.replace(path)


def parse_list(text):
    """Settings window text box -> list: one item per line, trimmed, no blanks or repeats."""
    out = []
    for line in text.splitlines():
        line = line.strip()
        if line and line not in out:
            out.append(line)
    return out


def parse_keywords(text):
    """'Claude, cloud, clod' -> ['Claude', 'cloud', 'clod'] (commas or new lines)."""
    return parse_list(re.sub(r"[,;]", "\n", text))


# --- History --------------------------------------------------------------

HISTORY_LIMIT = 50


def load_history(path=DATA_DIR / "history.json"):
    entries = read_json(path, [])
    return [e for e in entries if isinstance(e, dict) and isinstance(e.get("text"), str)] if isinstance(entries, list) else []


def add_history(text, seconds, path=DATA_DIR / "history.json"):
    entries = load_history(path)
    entries.insert(0, {
        "id": str(uuid.uuid4()),
        "text": text,
        "date": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "seconds": round(seconds, 2),
    })
    write_json(path, entries[:HISTORY_LIMIT])
    return entries[:HISTORY_LIMIT]


def clear_history(path=DATA_DIR / "history.json"):
    write_json(path, [])
