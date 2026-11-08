"""ctypes plumbing for Windows: synthetic keys (SendInput) and the clipboard. No pywin32 needed."""
import ctypes
import time
from ctypes import wintypes as w

user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

LABIA_TAG = 0x1AB1A  # dwExtraInfo on our own SendInput events, so the hook lets them through

KEYEVENTF_EXTENDEDKEY, KEYEVENTF_KEYUP = 0x1, 0x2
VK_BACK, VK_RETURN, VK_CONTROL, VK_ESCAPE, VK_V = 0x08, 0x0D, 0x11, 0x1B, 0x56
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


def set_text(text, private=True):
    if not _open():
        return False
    try:
        user32.EmptyClipboard()
        user32.SetClipboardData(CF_UNICODETEXT, _global((text + "\0").encode("utf-16-le")))
        if private:
            for fmt in PRIVATE_FORMATS:
                user32.SetClipboardData(fmt, _global(b"\0\0\0\0"))  # DWORD 0 = "no"
        return True
    finally:
        user32.CloseClipboard()
