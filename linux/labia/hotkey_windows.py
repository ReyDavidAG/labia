"""Hotkey on Windows: a low-level keyboard hook turns keys into GestureMachine events.

Same idea as the evdev grab on Linux: the hotkey used alone never reaches the apps (otherwise Right Alt
held + our Ctrl+V is not a paste), and hotkey + another key is replayed so AltGr+Q still types @.
On Spanish layouts Right Alt is AltGr, and Windows sends a fake Left Ctrl (scan code 0x21D) with it:
that one follows the hotkey's fate.
"""
import ctypes
import queue
import threading
import time
from ctypes import wintypes as w

from . import core, win32

WH_KEYBOARD_LL, HC_ACTION = 13, 0
WM_KEYDOWN, WM_KEYUP, WM_SYSKEYDOWN, WM_SYSKEYUP = 0x100, 0x101, 0x104, 0x105
LLKHF_EXTENDED, LLKHF_INJECTED = 0x01, 0x10
ALTGR_FAKE_CTRL_SCAN = 0x21D
HOTKEYS = {"KEY_RIGHTALT": win32.VK_RMENU, "KEY_RIGHTCTRL": win32.VK_RCONTROL, "KEY_RIGHTMETA": win32.VK_RWIN}


class KBDLLHOOKSTRUCT(ctypes.Structure):
    _fields_ = [("vkCode", w.DWORD), ("scanCode", w.DWORD), ("flags", w.DWORD), ("time", w.DWORD),
                ("dwExtraInfo", ctypes.c_size_t)]


HOOKPROC = ctypes.WINFUNCTYPE(ctypes.c_ssize_t, ctypes.c_int, w.WPARAM, w.LPARAM)
user32 = win32.user32
user32.SetWindowsHookExW.argtypes = [ctypes.c_int, HOOKPROC, w.HINSTANCE, w.DWORD]
user32.SetWindowsHookExW.restype = w.HHOOK
user32.CallNextHookEx.argtypes = [w.HHOOK, ctypes.c_int, w.WPARAM, w.LPARAM]
user32.CallNextHookEx.restype = ctypes.c_ssize_t


def to_gesture(vk, value, hotkey):
    """(virtual key, value) -> gesture event or None. value: 1 down, 0 up, 2 auto-repeat."""
    if value == 2:
        return None
    if vk == hotkey:
        return core.KEY_DOWN if value else core.KEY_UP
    if value == 1:
        return core.ESCAPE if vk == win32.VK_ESCAPE else core.OTHER_KEY
    return None


def _hook_thread(hotkey, out, ready):
    gate, pressed = core.Passthrough(hotkey), set()

    def proc(n, wparam, lparam):
        # Windows unhooks us if this takes longer than ~1 s: only queue work here, never wait.
        if n == HC_ACTION:
            k = ctypes.cast(lparam, ctypes.POINTER(KBDLLHOOKSTRUCT)).contents
            if not k.flags & LLKHF_INJECTED:
                down = wparam in (WM_KEYDOWN, WM_SYSKEYDOWN)
                if k.vkCode == win32.VK_LCONTROL and k.scanCode == ALTGR_FAKE_CTRL_SCAN and hotkey == win32.VK_RMENU:
                    return 0 if gate.forwarded else 1  # AltGr's fake Ctrl goes wherever Right Alt goes
                vk = k.vkCode
                value = (2 if vk in pressed else 1) if down else 0
                (pressed.add if down else pressed.discard)(vk)
                out.put((vk, value))
                events = gate.filter(vk, value)
                if events != [(vk, value)]:
                    # Swallow it and replay in order (a SendInput from here would land after this key).
                    if events:
                        ext = bool(k.flags & LLKHF_EXTENDED)
                        win32.send_keys([(c, v != 0, k.scanCode if c == vk else 0, ext if c == vk else None)
                                         for c, v in events])
                    return 1
        return user32.CallNextHookEx(None, n, wparam, lparam)

    callback = HOOKPROC(proc)  # keep a reference: ctypes callbacks die with their Python object
    hook = user32.SetWindowsHookExW(WH_KEYBOARD_LL, callback, None, 0)
    ready.put(bool(hook))
    msg = w.MSG()
    while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:  # the hook only runs while we pump messages
        user32.TranslateMessage(ctypes.byref(msg))
        user32.DispatchMessageW(ctypes.byref(msg))


def events(hotkey_name, tick=0.1):
    """Yield (gesture event, time) forever; TICK every `tick` seconds of silence."""
    hotkey = HOTKEYS.get(hotkey_name)
    if hotkey is None:
        raise SystemExit(f"Atajo no soportado en Windows: {hotkey_name} (usa {', '.join(HOTKEYS)})")
    out, ready = queue.Queue(), queue.Queue()
    threading.Thread(target=_hook_thread, args=(hotkey, out, ready), daemon=True).start()
    if not ready.get():
        raise SystemExit("No se pudo instalar el gancho de teclado.")
    while True:
        try:
            vk, value = out.get(timeout=tick)
            if g := to_gesture(vk, value, hotkey):
                yield g, time.monotonic()
        except queue.Empty:
            pass
        yield core.TICK, time.monotonic()
