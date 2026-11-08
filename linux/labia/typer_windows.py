"""Type into the focused app on Windows: text through the clipboard + Ctrl+V, keys through SendInput."""
import time

from . import win32

PASTE_SETTLE = 0.12  # the app reads the clipboard asynchronously after Ctrl+V; don't change it before


class Typer:
    def __init__(self):
        self.saved = None

    def begin(self):
        """Remember the user's clipboard to put it back at the end."""
        self.saved = win32.get_text()

    def apply(self, back, text):
        if back:
            win32.send_keys([(win32.VK_BACK, d) for _ in range(back) for d in (True, False)])
        if text and win32.set_text(text):
            win32.tap(win32.VK_V, win32.VK_CONTROL)
            time.sleep(PASTE_SETTLE)

    def enter(self):
        time.sleep(0.15)  # terminals drop a Return that lands while they still process the paste
        win32.tap(win32.VK_RETURN)

    def end(self):
        if self.saved is not None:
            win32.set_text(self.saved, private=False)
        self.saved = None
