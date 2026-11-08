import numpy as np

from labia.core import Preferences
from labia.stream import LocalAgreement, Session, diff, hold_last_word


def words(*items):
    return [(i * 0.5, i * 0.5 + 0.4, w) for i, w in enumerate(items)]


def test_agreement_commits_only_what_two_passes_share():
    a = LocalAgreement()
    assert a.update(words(" Hola", " mun")) == []
    assert [w[2] for w in a.update(words(" Hola", " mundo", " cómo"))] == [" Hola"]
    assert [w[2] for w in a.update(words(" Hola", " mundo", " cómo", " estás"))] == [" mundo", " cómo"]
    assert a.text == " Hola mundo cómo"


def test_agreement_survives_one_garbage_pass():
    a = LocalAgreement()
    a.update(words(" familia", " Parra."))
    a.update([(0.0, 0.9, " Parlo")])  # Whisper's occasional bad pass
    a.update(words(" familia", " Parra", " Su"))
    assert a.text == " familia Parra"


def test_agreement_drops_repeated_overlap_after_trim():
    a = LocalAgreement()
    a.update(words(" uno", " dos")); a.update(words(" uno", " dos"))
    # Next pass starts again at "dos" with a slightly earlier timestamp.
    again = [(0.45, 0.9, " dos"), (1.0, 1.4, " tres")]
    a.update(again); a.update(again)
    assert a.text == " uno dos tres"


def test_diff_and_hold():
    assert diff("Hola mundo", "Hola mundo, cómo") == (0, ", cómo")
    assert diff("Hola de velo", "Hola develop") == (5, "velop")
    assert hold_last_word("Hola mundo cómo") == "Hola mundo"
    assert hold_last_word("Hola") == ""


def fake_model(passes):
    """Returns each scripted hypothesis in turn (times relative to the buffer)."""
    it = iter(passes)
    return lambda samples, prompt, **careful: next(it)


def test_session_types_progressively_and_sends_on_keyword():
    passes = [
        words(" Revisa", " el"),
        words(" Revisa", " el", " build,"),
        words(" Revisa", " el", " build,", " Claude."),
        words(" Revisa", " el", " build,", " Claude."),
    ]
    s = Session(fake_model(passes), Preferences(vocabulary=[]))
    s.feed(np.zeros(16000, np.float32))
    screen = ""

    def apply(back, add):
        nonlocal screen
        screen = screen[: len(screen) - back] + add

    apply(*s.step()); assert screen == ""
    apply(*s.step()); assert screen == "Revisa"           # "el" is held back
    apply(*s.step()); assert screen == "Revisa el"
    back, add, send = s.finish()
    apply(back, add)
    assert screen == "Revisa el build" and send           # keyword removed, comma dropped, Enter


def test_session_cleaning_can_retract():
    passes = [words(" a", " de", " velo", " ya"), words(" a", " de", " velo", " ya"), words(" a", " de", " velo", " ya")]
    s = Session(fake_model(passes), Preferences(vocabulary=[], send_on_keyword=False))
    s.feed(np.zeros(16000, np.float32))
    s.step(); s.step()
    back, add, send = s.finish()
    assert s.typed == "a develop ya " and not send


def test_hotkey_to_gesture():
    import pytest

    e = pytest.importorskip("evdev").ecodes  # Linux only
    from labia import core
    from labia.hotkey import to_gesture

    h = e.KEY_RIGHTALT
    assert to_gesture(h, 1, h) == core.KEY_DOWN
    assert to_gesture(h, 0, h) == core.KEY_UP
    assert to_gesture(h, 2, h) is None  # auto-repeat
    assert to_gesture(e.KEY_ESC, 1, h) == core.ESCAPE
    assert to_gesture(e.KEY_A, 1, h) == core.OTHER_KEY
    assert to_gesture(e.KEY_A, 0, h) is None


def test_careful_pass_corrects_typed_words():
    draft = words(" Abre", " el", " pul", " request", " ya")
    passes = [draft, draft, words(" Abre", " el", " pull", " request", " ya"), words(" Abre", " el", " pull", " request", " ya.")]
    s = Session(fake_model(passes), Preferences(vocabulary=[], send_on_keyword=False))
    s.feed(np.zeros(16000, np.float32))
    s.step(); s.step()
    assert s.typed == "Abre el pul request"
    s.feed(np.zeros(3 * 16000, np.float32))
    s.step()  # 3 s of new audio: careful pass
    assert s.typed == "Abre el pull request"
    s.finish()
    assert s.typed == "Abre el pull request ya. "


def test_careful_pass_ignores_garbage_and_final_pass_drops_silence():
    draft = words(" Uno", " dos", " tres", " cuatro")
    passes = [draft, draft, words(" Gracias."), []]
    s = Session(fake_model(passes), Preferences(vocabulary=[], send_on_keyword=False))
    s.feed(np.zeros(16000, np.float32))
    s.step(); s.step()
    s.feed(np.zeros(3 * 16000, np.float32))
    s.step()
    assert s.typed == "Uno dos tres"  # one-word pass did not wipe the draft
    back, add, _ = s.finish()  # VAD found no speech
    assert s.typed == "" and back == len("Uno dos tres")
