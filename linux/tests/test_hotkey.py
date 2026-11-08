from evdev import ecodes as e

from labia.hotkey import Passthrough

ALT, Q = e.KEY_RIGHTALT, e.KEY_Q


def test_hotkey_alone_never_reaches_apps():
    g = Passthrough(ALT)
    assert g.filter(ALT, 1) == []
    assert g.filter(ALT, 2) == []
    assert g.filter(ALT, 0) == []


def test_chord_passes_hotkey_through():
    g = Passthrough(ALT)
    assert g.filter(ALT, 1) == []
    assert g.filter(Q, 1) == [(ALT, 1), (Q, 1)]
    assert g.filter(Q, 0) == [(Q, 0)]
    assert g.filter(ALT, 0) == [(ALT, 0)]
    assert g.filter(Q, 1) == [(Q, 1)]  # state reset after release
