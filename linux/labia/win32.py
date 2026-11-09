"""ctypes plumbing for Windows: synthetic keys (SendInput) and the clipboard. No pywin32 needed."""
import ctypes
import time
from ctypes import wintypes as w

user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

LABIA_TAG = 0x1AB1A  # dwExtraInfo on our own SendInput events, so the hook lets them through

KEYEVENTF_EXTENDEDKEY, KEYEVENTF_KEYUP = 0x1, 0x2
VK_BACK, VK_RETURN, VK_CONTROL, VK_ESCAPE, VK_SPACE, VK_V = 0x08, 0x0D, 0x11, 0x1B, 0x20, 0x56
VK_LCONTROL, VK_RCONTROL, VK_RMENU, VK_RWIN = 0xA2, 0xA3, 0xA5, 0x5C
EXTENDED = {VK_RMENU, VK_RCONTROL, VK_RWIN, 0x2D, 0x2E, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28}

ULONG_PTR = ctypes.c_size_t


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [("wVk", w.WORD), ("wScan", w.WORD), ("dwFlags", w.DWORD), ("time", w.DWORD), ("dwExtraInfo", ULONG_PTR)]


class MOUSEINPUT(ctypes.Structure):  # only here so the union has the right size; SendInput checks cbSize
    _fields_ = [("dx", w.LONG), ("dy", w.LONG), ("mouseData", w.DWORD), ("dwFlags", w.DWORD),
                ("time", w.DWORD), ("dwExtraInfo", ULONG_PTR)]


class HARDWAREINPUT(ctypes.Structure):
    _fields_ = [("uMsg", w.DWORD), ("wParamL", w.WORD), ("wParamH", w.WORD)]


class _U(ctypes.Union):
    _fields_ = [("mi", MOUSEINPUT), ("ki", KEYBDINPUT), ("hi", HARDWAREINPUT)]


class INPUT(ctypes.Structure):
    _fields_ = [("type", w.DWORD), ("u", _U)]


user32.SendInput.argtypes = [w.UINT, ctypes.POINTER(INPUT), ctypes.c_int]


def send_keys(events):
    """events: [(vk, down, scan=0, extended=None)]. Tagged so our hook ignores them."""
    inputs = []
    for vk, down, *rest in events:
        scan = rest[0] if rest else 0
        ext = rest[1] if len(rest) > 1 and rest[1] is not None else vk in EXTENDED
        flags = (0 if down else KEYEVENTF_KEYUP) | (KEYEVENTF_EXTENDEDKEY if ext else 0)
        inputs.append(INPUT(type=1, u=_U(ki=KEYBDINPUT(vk, scan, flags, 0, LABIA_TAG))))
    arr = (INPUT * len(inputs))(*inputs)
    user32.SendInput(len(inputs), arr, ctypes.sizeof(INPUT))


def tap(vk, *mods):
    send_keys([(m, True) for m in mods] + [(vk, True), (vk, False)] + [(m, False) for m in reversed(mods)])


# --- single instance -------------------------------------------------------------

ERROR_ALREADY_EXISTS = 183
kernel32.CreateMutexW.argtypes, kernel32.CreateMutexW.restype = [w.LPVOID, w.BOOL, w.LPCWSTR], w.HANDLE
kernel32.CloseHandle.argtypes = [w.HANDLE]
_mutexes = {}  # held until the process exits; Windows frees them even on a crash or kill


def claim_single_instance(name="Local\\Labia", wait=0.0):
    """True if no other copy holds `name` in this session; with `wait`, keep trying that many seconds.

    Two Labias would both hook the keyboard: the newer one swallows AltGr, so the older one can miss the key-up
    and stay recording with no way to stop it.
    """
    end = time.monotonic() + wait
    while True:
        h = kernel32.CreateMutexW(None, False, name)
        if h and ctypes.get_last_error() != ERROR_ALREADY_EXISTS:
            _mutexes[name] = h
            return True
        if h:
            kernel32.CloseHandle(h)  # our handle would keep the other copy's mutex alive after it exits
        if time.monotonic() >= end:
            return False
        time.sleep(0.25)


# --- clipboard -----------------------------------------------------------------

CF_UNICODETEXT, GMEM_MOVEABLE = 13, 0x2
kernel32.GlobalAlloc.argtypes, kernel32.GlobalAlloc.restype = [w.UINT, ctypes.c_size_t], w.HGLOBAL
kernel32.GlobalLock.argtypes, kernel32.GlobalLock.restype = [w.HGLOBAL], w.LPVOID
kernel32.GlobalUnlock.argtypes = [w.HGLOBAL]
user32.GetClipboardData.argtypes, user32.GetClipboardData.restype = [w.UINT], w.HANDLE
user32.SetClipboardData.argtypes, user32.SetClipboardData.restype = [w.UINT, w.HANDLE], w.HANDLE
user32.OpenClipboard.argtypes = [w.HWND]
user32.RegisterClipboardFormatW.argtypes, user32.RegisterClipboardFormatW.restype = [w.LPCWSTR], w.UINT

# Keep dictation chunks out of Win+V history, cloud clipboard and clipboard managers.
PRIVATE_FORMATS = [user32.RegisterClipboardFormatW(n) for n in
                   ("ExcludeClipboardContentFromMonitorProcessing", "CanIncludeInClipboardHistory",
                    "CanUploadToCloudClipboard")]


def _open():
    for _ in range(50):  # another app may hold it for a moment
        if user32.OpenClipboard(None):
            return True
        time.sleep(0.01)
    return False


def _global(data: bytes):
    h = kernel32.GlobalAlloc(GMEM_MOVEABLE, len(data))
    ctypes.memmove(kernel32.GlobalLock(h), data, len(data))
    kernel32.GlobalUnlock(h)
    return h


def get_text():
    """Clipboard text, or None if there is none (images and files are not saved)."""
    # ponytail: only text is restored after dictating; save every format if losing an image bothers
    if not _open():
        return None
    try:
        h = user32.GetClipboardData(CF_UNICODETEXT)
        if not h:
            return None
        p = kernel32.GlobalLock(h)
        try:
            return ctypes.wstring_at(p)
        finally:
            kernel32.GlobalUnlock(h)
    finally:
        user32.CloseClipboard()


def _private():
    for fmt in PRIVATE_FORMATS:
        user32.SetClipboardData(fmt, _global(b"\0\0\0\0"))  # DWORD 0 = "no"


def set_text(text, private=True):
    if not _open():
        return False
    try:
        user32.EmptyClipboard()
        user32.SetClipboardData(CF_UNICODETEXT, _global((text + "\0").encode("utf-16-le")))
        if private:
            _private()
        return True
    finally:
        user32.CloseClipboard()


# --- delayed rendering: know when the app actually read what we pasted -----------
#
# Apps read the clipboard whenever they get to our Ctrl+V, which can be seconds later (a terminal working
# through 800 backspaces). Changing or restoring the clipboard before then pastes the wrong text. With
# delayed rendering the clipboard only announces the text; Windows asks our window for it (WM_RENDERFORMAT)
# at the moment the app reads it, and that is our signal.

WM_DESTROY, WM_RENDERFORMAT, WM_RENDERALLFORMATS = 0x0002, 0x0305, 0x0306
HWND_MESSAGE = w.HWND(-3)
WNDPROC = ctypes.WINFUNCTYPE(ctypes.c_ssize_t, w.HWND, w.UINT, w.WPARAM, w.LPARAM)


class WNDCLASSW(ctypes.Structure):
    _fields_ = [("style", w.UINT), ("lpfnWndProc", WNDPROC), ("cbClsExtra", ctypes.c_int), ("cbWndExtra", ctypes.c_int),
                ("hInstance", w.HINSTANCE), ("hIcon", w.HICON), ("hCursor", w.HANDLE), ("hbrBackground", w.HBRUSH),
                ("lpszMenuName", w.LPCWSTR), ("lpszClassName", w.LPCWSTR)]


user32.DefWindowProcW.argtypes = [w.HWND, w.UINT, w.WPARAM, w.LPARAM]
user32.DefWindowProcW.restype = ctypes.c_ssize_t
user32.RegisterClassW.argtypes = [ctypes.POINTER(WNDCLASSW)]
user32.CreateWindowExW.argtypes = [w.DWORD, w.LPCWSTR, w.LPCWSTR, w.DWORD, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                                   ctypes.c_int, w.HWND, w.HMENU, w.HINSTANCE, w.LPVOID]
user32.CreateWindowExW.restype = w.HWND
user32.GetClipboardOwner.restype = w.HWND


class DelayedClipboard:
    """put(text) -> threading.Event set once an app has read the text."""

    def __init__(self):
        import threading

        self.text, self.read, self.hwnd = "", threading.Event(), None
        ready = threading.Event()
        threading.Thread(target=self._loop, args=(ready,), daemon=True).start()
        ready.wait(5)

    def _render(self):
        user32.SetClipboardData(CF_UNICODETEXT, _global((self.text + "\0").encode("utf-16-le")))

    def _proc(self, hwnd, msg, wparam, lparam):
        if msg == WM_RENDERFORMAT and wparam == CF_UNICODETEXT:
            self._render()  # the clipboard is already open by whoever asked: no OpenClipboard here
            self.read.set()
            return 0
        if msg == WM_RENDERALLFORMATS:  # we are going away: leave the text behind for good
            if user32.OpenClipboard(hwnd):
                if user32.GetClipboardOwner() == hwnd:
                    self._render()
                user32.CloseClipboard()
            return 0
        return user32.DefWindowProcW(hwnd, msg, wparam, lparam)

    def _loop(self, ready):
        self._wndproc = WNDPROC(self._proc)  # keep a reference: ctypes callbacks die with their Python object
        cls = WNDCLASSW(lpfnWndProc=self._wndproc, lpszClassName="LabiaClipboard")
        user32.RegisterClassW(ctypes.byref(cls))
        self.hwnd = user32.CreateWindowExW(0, "LabiaClipboard", "Labia", 0, 0, 0, 0, 0, HWND_MESSAGE, None, None, None)
        ready.set()
        msg = w.MSG()
        while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))

    def put(self, text):
        """Announce `text` on the clipboard without handing it over yet. None if the clipboard is busy."""
        self.text = text
        self.read.clear()
        for _ in range(50):
            if user32.OpenClipboard(self.hwnd):
                break
            time.sleep(0.01)
        else:
            return None
        try:
            user32.EmptyClipboard()  # makes our window the owner, the one Windows asks to render
            user32.SetClipboardData(CF_UNICODETEXT, None)
            _private()
        finally:
            user32.CloseClipboard()
        return self.read
