"""Type into the focused app on Windows: text through the clipboard + Ctrl+V, keys through SendInput."""
import time

from . import win32

PASTE_TIMEOUT = 3.0  # an app that never reads the paste (no text field focused) must not hang the dictation
CHUNK = 400  # Claude Code folds a long paste into «[Pasted text #1]»: paste long text in pieces


class Typer:
    def __init__(self):
        self.saved = None
        self.clipboard = win32.DelayedClipboard()

    def begin(self):
        """Remember the user's clipboard to put it back at the end."""
        self.saved = win32.get_text()

    def apply(self, back, text):
        if back:
            win32.send_keys([(win32.VK_BACK, d) for _ in range(back) for d in (True, False)])
        for i in range(0, len(text), CHUNK):
            piece = text[i : i + CHUNK]
            body = piece.rstrip(" ")
            if body and not self._paste(body):
                return
            # Windows Terminal trims trailing spaces off a paste (trimPaste): type those as keys.
            win32.send_keys([(win32.VK_SPACE, d) for _ in range(len(piece) - len(body)) for d in (True, False)])

    def _paste(self, text):
        read = self.clipboard.put(text)
        if read is None:
            return False
        # The app gets to our Ctrl+V late if it is still working through backspaces. Until it reads the
        # clipboard: keep the clipboard as is (or the wrong text is pasted), and keep Ctrl down, because
        # some apps (Notepad) check whether Ctrl is down when they handle the V, not when it was sent,
        # and type a bare «v».
        win32.send_keys([(win32.VK_CONTROL, True), (win32.VK_V, True), (win32.VK_V, False)])
        try:
            read.wait(PASTE_TIMEOUT)
        finally:
            win32.send_keys([(win32.VK_CONTROL, False)])
        return True

    def enter(self):
        time.sleep(0.15)  # terminals drop a Return that lands while they still process the paste
        win32.tap(win32.VK_RETURN)

    def end(self):
        if self.saved is not None:
            win32.set_text(self.saved, private=False)
        self.saved = None
