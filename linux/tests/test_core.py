# Same cases as Tests/LabiaCoreTests (Swift), so both versions behave alike.
import json

from labia.core import (
    CANCEL, CHORD, ESCAPE, IDLE, KEY_DOWN, KEY_UP, LOCK, LOCKED, OTHER_KEY, SEND_DEFAULTS, START, STOP, TICK,
    TOO_SHORT, GestureMachine, MAX_PROMPT_CHARS, Preferences, add_history, clean, split_send,
)


def test_hold_and_release():
    m = GestureMachine()
    assert m.handle(KEY_DOWN, 0) == START and m.is_recording
    assert m.handle(KEY_UP, 1.2) == STOP and m.phase == IDLE


def test_short_tap_cancels_after_window():
    m = GestureMachine()
    m.handle(KEY_DOWN, 0)
    assert m.handle(KEY_UP, 0.1) is None
    assert m.handle(TICK, 0.3) is None
    assert m.handle(TICK, 0.5) == TOO_SHORT and not m.is_recording


def test_double_tap_locks_and_next_press_stops():
    m = GestureMachine()
    m.handle(KEY_DOWN, 0); m.handle(KEY_UP, 0.1)
    assert m.handle(KEY_DOWN, 0.3) == LOCK
    assert m.handle(KEY_UP, 0.35) is None
    assert m.handle(TICK, 10) is None
    assert m.handle(KEY_DOWN, 12) == STOP
    assert m.handle(KEY_UP, 12.1) is None and m.phase == IDLE


def test_late_second_press_starts_again():
    m = GestureMachine()
    m.handle(KEY_DOWN, 0); m.handle(KEY_UP, 0.1)
    assert m.handle(KEY_DOWN, 1) == START


def test_escape_cancels_in_every_recording_phase():
    a = GestureMachine(); a.handle(KEY_DOWN, 0)
    assert a.handle(ESCAPE) == CANCEL
    b = GestureMachine(); b.handle(KEY_DOWN, 0); b.handle(KEY_UP, 0.1); b.handle(KEY_DOWN, 0.2)
    assert b.handle(ESCAPE) == CANCEL
    assert GestureMachine().handle(ESCAPE) is None


def test_chord_and_typing_while_locked():
    m = GestureMachine(); m.handle(KEY_DOWN, 0)
    assert m.handle(OTHER_KEY) == CHORD
    assert m.handle(KEY_UP, 0.5) is None
    l = GestureMachine(); l.handle(KEY_DOWN, 0); l.handle(KEY_UP, 0.1); l.handle(KEY_DOWN, 0.2)
    assert l.handle(OTHER_KEY) is None and l.phase == LOCKED


def test_send_keyword():
    k = SEND_DEFAULTS
    assert split_send("Revisa el build. Claude.", k) == ("Revisa el build.", True)
    assert split_send("Revisa el build, cloud", k) == ("Revisa el build", True)
    assert split_send("Sube el PR ¡Clod!", k) == ("Sube el PR", True)
    assert split_send('ya configuraste la palabra "Claude"', k) == ("ya configuraste la palabra", True)
    assert split_send("Claude.", k) == ("", True)
    assert split_send("Pregúntale a Claude por el build.", k) == ("Pregúntale a Claude por el build.", False)
    assert split_send("Usa Cloudflare", k) == ("Usa Cloudflare", False)
    assert split_send("Hola Claude", []) == ("Hola Claude", False)
    assert split_send("Hola Claude", [" "]) == ("Hola Claude", False)


def test_cleaner():
    assert clean("  Corre  el build ,  y  sube el release . ") == "Corre el build, y sube el release."
    assert clean(" Subtítulos realizados por la comunidad de Amara.org") == ""
    assert clean("¡Gracias por ver!") == ""
    assert clean("Haz el commit. Gracias por ver.") == "Haz el commit."
    assert clean("<|startoftranscript|><|es|> Hola<|endoftext|>") == "Hola"
    reps = [{"from": "de velo", "to": "develop"}, {"from": "lint", "to": "lint"}]
    assert clean("Hago el push a De Velo.", reps) == "Hago el push a develop."
    assert clean("Un vestido develop", [{"from": "velo", "to": "X"}]) == "Un vestido develop"
    assert clean("primera nueva línea segunda punto y coma", Preferences().replacements) == "primera\nsegunda;"
    assert clean("el precio", [{"from": "precio", "to": "$1 USD"}]) == "el $1 USD"
    assert clean("hola", [{"from": " ", "to": "x"}]) == "hola"


def test_vocabulary():
    v = ["useApiQuery", "staleTime", "Vercel", "pull request", "front"]
    assert clean("Usa el hook Use API Query con el stale time.", vocabulary=v) == "Usa el hook useApiQuery con el staleTime."
    assert clean("sube el release a vercel", vocabulary=v) == "sube el release a Vercel"
    assert clean("Revisa el Pull Request", vocabulary=v) == "Revisa el pull request"
    assert clean("Front primero.", vocabulary=["front", "staleTime"]) == "Front primero."
    assert clean("stale. Time", vocabulary=["front", "staleTime"]) == "stale. Time"


def test_preferences(tmp_path):
    s = Preferences(vocabulary=["commit", " ", "useApiQuery"])
    assert s.prompt == "Vocabulario: commit, useApiQuery."
    s.vocabulary = ["palabralarga"] * 200
    assert len(s.prompt) <= MAX_PROMPT_CHARS + 1
    s.vocabulary = []
    assert s.prompt is None
    f = tmp_path / "settings.json"
    f.write_text(json.dumps({"hotkey": "KEY_RIGHTCTRL", "language": 3}))
    back = Preferences.load(f)
    assert back.hotkey == "KEY_RIGHTCTRL" and back.language == "es" and back.vocabulary == Preferences().vocabulary
    back.save(f)
    assert Preferences.load(f) == back


def test_history(tmp_path):
    f = tmp_path / "h.json"
    for i in range(60):
        entries = add_history(f"frase {i}", 1, f)
    assert len(entries) == 50 and entries[0]["text"] == "frase 59"
    assert json.loads(f.read_text())[0]["text"] == "frase 59"
