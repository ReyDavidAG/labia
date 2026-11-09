"""Labia's icon next to the clock: status, a menu, and a hidden window other Labia processes can message.

Runs on its own thread with a message loop (Windows only delivers tray clicks to the thread that owns the window).
The window is a normal hidden top-level one, not message-only: FindWindowW and the «TaskbarCreated» broadcast
(Explorer restarted, the icon must be added again) only reach top-level windows.
"""
import ctypes
import threading
from ctypes import wintypes as w
from pathlib import Path

from . import win32

user32, kernel32 = win32.user32, win32.kernel32
shell32 = ctypes.WinDLL("shell32", use_last_error=True)

CLASS = "LabiaTray"
ICON = Path(__file__).with_name("labia.ico")
WM_TRAY = 0x8000  # WM_APP: tray clicks
# Commands other processes post to the hidden window (settings window, a second Labia launched from Start).
COMMANDS = {0x8001: "settings", 0x8002: "history", 0x8003: "restart"}
MESSAGE_OF = {v: k for k, v in COMMANDS.items()}
WM_CLOSE, WM_COMMAND, WM_LBUTTONUP, WM_RBUTTONUP = 0x0010, 0x0111, 0x0202, 0x0205
NIM_ADD, NIM_MODIFY, NIM_DELETE = 0, 1, 2
NIF_MESSAGE, NIF_ICON, NIF_TIP, NIF_INFO = 0x01, 0x02, 0x04, 0x10
MF_STRING, MF_GRAYED, MF_SEPARATOR, MF_CHECKED = 0x0, 0x1, 0x800, 0x8
TPM_RIGHTBUTTON, TPM_RETURNCMD, TPM_NONOTIFY = 0x2, 0x100, 0x80
IMAGE_ICON, LR_LOADFROMFILE, LR_DEFAULTSIZE = 1, 0x10, 0x40
IDI_APPLICATION = 32512
MENU = [(1, "Ajustes…", "settings"), (2, "Historial…", "history"), None, (3, "Pausar", "pause"),
        (4, "Reiniciar", "restart"), None, (5, "Salir", "quit")]


class NOTIFYICONDATAW(ctypes.Structure):
    _fields_ = [("cbSize", w.DWORD), ("hWnd", w.HWND), ("uID", w.UINT), ("uFlags", w.UINT),
                ("uCallbackMessage", w.UINT), ("hIcon", w.HICON), ("szTip", w.WCHAR * 128), ("dwState", w.DWORD),
                ("dwStateMask", w.DWORD), ("szInfo", w.WCHAR * 256), ("uVersion", w.UINT),
                ("szInfoTitle", w.WCHAR * 64), ("dwInfoFlags", w.DWORD), ("guidItem", ctypes.c_ubyte * 16),
                ("hBalloonIcon", w.HICON)]


shell32.Shell_NotifyIconW.argtypes = [w.DWORD, ctypes.POINTER(NOTIFYICONDATAW)]
user32.LoadImageW.argtypes = [w.HINSTANCE, w.LPCWSTR, w.UINT, ctypes.c_int, ctypes.c_int, w.UINT]
user32.LoadImageW.restype = w.HANDLE
user32.LoadIconW.argtypes, user32.LoadIconW.restype = [w.HINSTANCE, w.LPVOID], w.HICON
user32.RegisterWindowMessageW.argtypes, user32.RegisterWindowMessageW.restype = [w.LPCWSTR], w.UINT
user32.FindWindowW.argtypes, user32.FindWindowW.restype = [w.LPCWSTR, w.LPCWSTR], w.HWND
user32.PostMessageW.argtypes = [w.HWND, w.UINT, w.WPARAM, w.LPARAM]
user32.CreatePopupMenu.restype = w.HMENU
user32.AppendMenuW.argtypes = [w.HMENU, w.UINT, ctypes.c_size_t, w.LPCWSTR]
user32.TrackPopupMenu.argtypes = [w.HMENU, w.UINT, ctypes.c_int, ctypes.c_int, ctypes.c_int, w.HWND, w.LPVOID]
user32.DestroyMenu.argtypes = [w.HMENU]
user32.GetCursorPos.argtypes = [ctypes.POINTER(w.POINT)]
user32.SetForegroundWindow.argtypes = [w.HWND]
user32.DestroyWindow.argtypes = [w.HWND]


def post_to_running(command):
    """Ask the Labia already running to do `command` ('settings', 'history', 'restart'). False if none runs."""
    hwnd = user32.FindWindowW(CLASS, None)
    return bool(hwnd) and bool(user32.PostMessageW(hwnd, MESSAGE_OF[command], 0, 0))


class Tray:
    """on_command(name) runs on the tray thread with 'settings', 'history', 'pause', 'restart' or 'quit'."""

    def __init__(self, on_command):
        self.on_command = on_command
        self.hwnd, self.status, self.paused = None, "Labia", False
        self._taskbar_created = user32.RegisterWindowMessageW("TaskbarCreated")
        self._icon = None
        ready = threading.Event()
        threading.Thread(target=self._loop, args=(ready,), daemon=True, name="tray").start()
        ready.wait(5)

    # --- public, any thread ---

    def set_status(self, text, paused=None):
        self.status = text
        if paused is not None:
            self.paused = paused
        self._shell(NIM_MODIFY, NIF_TIP)

    def notify(self, title, text):
        """A Windows notification from the tray icon."""
        self._shell(NIM_MODIFY, NIF_INFO, title=title, info=text)

    def close(self):
        if self.hwnd:
            self._shell(NIM_DELETE, 0)
            user32.PostMessageW(self.hwnd, WM_CLOSE, 0, 0)

    # --- tray thread ---

    def _data(self, flags, title="", info=""):
        d = NOTIFYICONDATAW(cbSize=ctypes.sizeof(NOTIFYICONDATAW), hWnd=self.hwnd, uID=1, uFlags=flags,
                            uCallbackMessage=WM_TRAY, hIcon=self._icon)
        d.szTip = ("Labia · " + self.status)[:127]
        d.szInfoTitle, d.szInfo = title[:63], info[:255]
        return d

    def _shell(self, action, flags, **kw):
        if self.hwnd:
            shell32.Shell_NotifyIconW(action, ctypes.byref(self._data(flags, **kw)))

    def _menu(self):
        menu = user32.CreatePopupMenu()
        user32.AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, self.status)
        user32.AppendMenuW(menu, MF_SEPARATOR, 0, None)
        for item in MENU:
            if item is None:
                user32.AppendMenuW(menu, MF_SEPARATOR, 0, None)
                continue
            ident, label, command = item
            checked = MF_CHECKED if command == "pause" and self.paused else 0
            user32.AppendMenuW(menu, MF_STRING | checked, ident, label)
        pt = w.POINT()
        user32.GetCursorPos(ctypes.byref(pt))
        user32.SetForegroundWindow(self.hwnd)  # without it the menu doesn't close when you click elsewhere
        chosen = user32.TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_RETURNCMD | TPM_NONOTIFY, pt.x, pt.y, 0,
                                       self.hwnd, None)
        user32.DestroyMenu(menu)
        for item in MENU:
            if item and item[0] == chosen:
                self.on_command(item[2])

    def _proc(self, hwnd, msg, wparam, lparam):
        if msg == WM_TRAY:
            if lparam == WM_LBUTTONUP:
                self.on_command("settings")
            elif lparam == WM_RBUTTONUP:
                self._menu()
            return 0
        if msg in COMMANDS:
            self.on_command(COMMANDS[msg])
            return 0
        if msg == self._taskbar_created:  # Explorer restarted and forgot our icon
            self._shell(NIM_ADD, NIF_MESSAGE | NIF_ICON | NIF_TIP)
            return 0
        if msg == WM_CLOSE:
            user32.DestroyWindow(hwnd)
            user32.PostQuitMessage(0)
            return 0
        return user32.DefWindowProcW(hwnd, msg, wparam, lparam)

    def _loop(self, ready):
        self._wndproc = win32.WNDPROC(self._proc)  # keep a reference: ctypes callbacks die with their Python object
        user32.RegisterClassW(ctypes.byref(win32.WNDCLASSW(lpfnWndProc=self._wndproc, lpszClassName=CLASS)))
        self.hwnd = user32.CreateWindowExW(0, CLASS, "Labia", 0, 0, 0, 0, 0, None, None, None, None)
        self._icon = (user32.LoadImageW(None, str(ICON), IMAGE_ICON, 0, 0, LR_LOADFROMFILE | LR_DEFAULTSIZE)
                      or user32.LoadIconW(None, ctypes.c_void_p(IDI_APPLICATION)))
        self._shell(NIM_ADD, NIF_MESSAGE | NIF_ICON | NIF_TIP)
        ready.set()
        msg = w.MSG()
        while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))
