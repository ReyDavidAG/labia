"""Type into the focused app on KDE Wayland.

Keys (Backspace, Return, Shift+Insert) go through a uinput virtual keyboard, so they work on any layout.
Text goes through the clipboard: wl-copy sets both clipboard and primary selection, then Shift+Insert
pastes. Konsole and Alacritty paste the primary selection on Shift+Insert, browsers and VS Code the
clipboard, so setting both covers all of them. `--sensitive` keeps Klipper from saving every chunk.
"""
import subprocess
import time

from evdev import UInput
from evdev import ecodes as e

KEYS = [e.KEY_BACKSPACE, e.KEY_ENTER, e.KEY_LEFTSHIFT, e.KEY_INSERT]
PASTE_SETTLE = 0.12  # the app reads the clipboard asynchronously after Shift+Insert; don't change it before


def _copy(text, primary=False):
    cmd = ["wl-copy", "--sensitive"] + (["--primary"] if primary else [])
    subprocess.run(cmd, input=text.encode(), check=True)


def _paste_clipboard():
    r = subprocess.run(["wl-paste", "--no-newline"], capture_output=True)
    return r.stdout if r.returncode == 0 else None


class Typer:
    def __init__(self):
        self.ui = UInput({e.EV_KEY: KEYS}, name="labia-keyboard")
        time.sleep(0.5)  # give libinput/KWin time to pick up the new device
        self.saved = None

    def _tap(self, key, *mods):
        for m in mods:
            self.ui.write(e.EV_KEY, m, 1)
        self.ui.write(e.EV_KEY, key, 1)
        self.ui.syn()
        self.ui.write(e.EV_KEY, key, 0)
        for m in mods:
            self.ui.write(e.EV_KEY, m, 0)
        self.ui.syn()
        time.sleep(0.004)

    def begin(self):
        """Remember the user's clipboard to put it back at the end."""
        self.saved = _paste_clipboard()

    def apply(self, back, text):
        for _ in range(back):
            self._tap(e.KEY_BACKSPACE)
        if text:
            _copy(text)
            _copy(text, primary=True)
            self._tap(e.KEY_INSERT, e.KEY_LEFTSHIFT)
            time.sleep(PASTE_SETTLE)

    def enter(self):
        time.sleep(0.15)  # terminals drop a Return that lands while they still process the paste
        self._tap(e.KEY_ENTER)

    def end(self):
        if self.saved:
            subprocess.run(["wl-copy"], input=self.saved)
        self.saved = None
