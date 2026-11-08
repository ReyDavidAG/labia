"""Floating recording pill on Windows, same look and protocol as pill.py (Linux) and PillView.swift (macOS).

Bottom center of the work area of the monitor under the cursor, topmost, click-through, never activated,
not in the taskbar. tkinter (ships with Python) for drawing, ctypes for the window styles.
Reads one JSON message per line on stdin; see pill.py for the messages.
"""
import ctypes
import json
import math
import queue
import sys
import threading
import time
import tkinter as tk
import tkinter.font as tkfont
from collections import deque
from ctypes import wintypes as w

try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)  # per-monitor: crisp text instead of a blurry bitmap
except (AttributeError, OSError):
    pass

user32 = ctypes.windll.user32
user32.GetWindowLongPtrW.restype = ctypes.c_ssize_t
user32.GetWindowLongPtrW.argtypes = [w.HWND, ctypes.c_int]
user32.SetWindowLongPtrW.argtypes = [w.HWND, ctypes.c_int, ctypes.c_ssize_t]
user32.SetWindowPos.argtypes = [w.HWND, w.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, w.UINT]
GWL_EXSTYLE, SW_HIDE, SW_SHOWNOACTIVATE, HWND_TOPMOST = -20, 0, 4, -1
WS_EX = 0x8 | 0x20 | 0x80 | 0x80000 | 0x08000000  # TOPMOST TRANSPARENT TOOLWINDOW LAYERED NOACTIVATE
SWP_NOACTIVATE, SWP_SHOWWINDOW = 0x10, 0x40

BARS = 24
HIDE_AFTER = {"done": 0.9, "short": 0.8, "cancelled": 0.8, "silent": 0.8, "failed": 1.8}
KEY = "#010203"  # transparent color key
BG, BORDER, WHITE, DIM = "#14141a", "#2a2a31", "#ffffff", "#9a9aa0"
RED, GREEN, AMBER = "#e6474d", "#4dc28a", "#f0b847"


class MONITORINFO(ctypes.Structure):
    _fields_ = [("cbSize", w.DWORD), ("rcMonitor", w.RECT), ("rcWork", w.RECT), ("dwFlags", w.DWORD)]


def work_area():
    pt = w.POINT()
    user32.GetCursorPos(ctypes.byref(pt))
    mon = user32.MonitorFromPoint(pt, 2)  # nearest
    info = MONITORINFO(cbSize=ctypes.sizeof(MONITORINFO))
    user32.GetMonitorInfoW(mon, ctypes.byref(info))
    return info.rcWork


class Pill:
    def __init__(self):
        self.root = tk.Tk()
        self.root.overrideredirect(True)
        self.root.configure(bg=KEY)
        self.root.attributes("-transparentcolor", KEY)
        self.s = self.root.winfo_fpixels("1i") / 96  # DPI scale
        self.W, self.H = int(460 * self.s), int(68 * self.s)
        self.canvas = tk.Canvas(self.root, width=self.W, height=self.H, bg=KEY, highlightthickness=0)
        self.canvas.pack()
        self.font = tkfont.Font(family="Segoe UI", size=10, weight="normal")
        self.bold = tkfont.Font(family="Segoe UI", size=10, weight="bold")
        self.mono = tkfont.Font(family="Consolas", size=9)
        self.root.update_idletasks()
        self.hwnd = user32.GetParent(self.root.winfo_id())
        style = user32.GetWindowLongPtrW(self.hwnd, GWL_EXSTYLE)
        user32.SetWindowLongPtrW(self.hwnd, GWL_EXSTYLE, style | WS_EX)
        user32.ShowWindow(self.hwnd, SW_HIDE)

        self.state, self.msg, self.visible = "hide", {}, False
        self.levels = deque([0.0] * BARS, maxlen=BARS)
        self.started, self.hide_at = None, None
        self.inbox = queue.Queue()
        threading.Thread(target=self._read, daemon=True).start()
        self.root.after(33, self._tick)

    def _read(self):
        sys.stdin.reconfigure(encoding="utf-8")  # the app writes UTF-8; Windows' default would be cp1252
        for line in sys.stdin:
            try:
                self.inbox.put(json.loads(line))
            except ValueError:
                pass
        self.inbox.put(None)

    # --- state ---------------------------------------------------------------

    def _handle(self, msg):
        if "level" in msg:
            self.levels.append(float(msg["level"]))
        state = msg.get("state")
        if not state:
            return
        self.state, self.msg = state, msg
        if state in ("listening", "locked"):
            if self.started is None:
                self.started = time.monotonic()
                self.levels.extend([0.0] * BARS)
        else:
            self.started = None
        self.hide_at = time.monotonic() + HIDE_AFTER[state] if state in HIDE_AFTER else None
        self._show(state != "hide")

    def _show(self, on):
        if on and not self.visible:
            r = work_area()
            x = (r.left + r.right - self.W) // 2
            user32.SetWindowPos(self.hwnd, HWND_TOPMOST, x, r.bottom - self.H, self.W, self.H,
                                SWP_NOACTIVATE | SWP_SHOWWINDOW)
            user32.ShowWindow(self.hwnd, SW_SHOWNOACTIVATE)
        elif not on and self.visible:
            user32.ShowWindow(self.hwnd, SW_HIDE)
        self.visible = on

    def _tick(self):
        while True:
            try:
                msg = self.inbox.get_nowait()
            except queue.Empty:
                break
            if msg is None:
                self.root.destroy()
                return
            self._handle(msg)
        if self.hide_at and time.monotonic() > self.hide_at:
            self.hide_at, self.state = None, "hide"
            self._show(False)
        if self.visible:
            self._draw()
        self.root.after(33, self._tick)

    # --- drawing -------------------------------------------------------------

    def _parts(self):
        """[(width, draw(x, cy))] for the current state."""
        s, st, parts = self.s, self.state, []

        def text(t, color=WHITE, font=None):
            f = font or self.font
            parts.append((f.measure(t), lambda x, cy: self.canvas.create_text(x, cy, text=t, fill=color, font=f, anchor="w")))

        if st in ("listening", "locked"):
            if st == "locked":
                text("🔒", DIM)
            else:
                pulse = 0.5 + 0.5 * math.cos(time.monotonic() * 2 * math.pi / 1.2)
                color = RED if pulse > 0.35 else "#8a2e33"
                r = 5 * s
                parts.append((2 * r, lambda x, cy, c=color: self.canvas.create_oval(x, cy - r, x + 2 * r, cy + r, fill=c, outline="")))
            n = 18 if st == "locked" else BARS
            levels = list(self.levels)[-n:]

            def bars(x, cy):
                for i, v in enumerate(levels):
                    h = max(3, v * 24) * s
                    gray = int(140 + v * 115)
                    self.canvas.create_line(x + i * 5 * s + 1.5 * s, cy - h / 2, x + i * 5 * s + 1.5 * s, cy + h / 2,
                                            width=3 * s, capstyle="round", fill=f"#{gray:02x}{gray:02x}{gray:02x}")
            parts.append((n * 5 * s, bars))
            secs = int(time.monotonic() - (self.started or time.monotonic()))
            text(f"{secs // 60}:{secs % 60:02d}", DIM, self.mono)
            if st == "locked":
                text("toca AltGr", DIM)
        elif st == "transcribing":
            r = 7 * s
            a = (time.monotonic() * 360) % 360
            parts.append((2 * r, lambda x, cy: self.canvas.create_arc(x, cy - r, x + 2 * r, cy + r, start=-a, extent=270,
                                                                        style="arc", outline=WHITE, width=2 * s)))
            text("Transcribiendo…", DIM)
        elif st == "done":
            n = self.msg.get("words", 0)
            text("✓", GREEN, self.bold)
            text("Pegado")
            text(f"· {n} {'palabra' if n == 1 else 'palabras'}", DIM)
        elif st == "short":
            text("✕ Muy corto", DIM)
        elif st == "cancelled":
            text("✕ Cancelado", DIM)
        elif st == "silent":
            text("No te oí", DIM)
        elif st == "failed":
            text("⚠", AMBER)
            text(self.msg.get("text", "Error"))
        return parts

    def _draw(self):
        c, s = self.canvas, self.s
        c.delete("all")
        parts = self._parts()
        gap, pad, h = 10 * s, 16 * s, 44 * s
        width = sum(p[0] for p in parts) + gap * max(0, len(parts) - 1) + 2 * pad
        x0, y0 = (self.W - width) / 2, self.H - h - 12 * s
        x1, y1, r = x0 + width, y0 + h, h / 2
        for fill, inset in ((BORDER, 0), (BG, 1)):  # 1 px border, then the body
            c.create_oval(x0 + inset, y0 + inset, x0 + 2 * r - inset, y1 - inset, fill=fill, outline="")
            c.create_oval(x1 - 2 * r + inset, y0 + inset, x1 - inset, y1 - inset, fill=fill, outline="")
            c.create_rectangle(x0 + r, y0 + inset, x1 - r, y1 - inset, fill=fill, outline="")
        x, cy = x0 + pad, y0 + h / 2
        for wdt, draw in parts:
            draw(x, cy)
            x += wdt + gap


if __name__ == "__main__":
    Pill().root.mainloop()
