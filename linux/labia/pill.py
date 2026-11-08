"""Floating recording pill, like the macOS one: bottom center, above everything, click-through, never takes focus.

Runs as its own process under the system Python (GTK 4 + gtk4-layer-shell via PyGObject, not in the venv),
preloaded with libgtk4-layer-shell. Reads one JSON message per line on stdin:
  {"state": "listening" | "locked" | "transcribing" | "short" | "cancelled" | "silent" | "hide"}
  {"state": "done", "words": 12}    {"state": "failed", "text": "..."}    {"level": 0.0..1.0}
"""
import json
import sys
import threading
import time
from collections import deque

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Gtk4LayerShell", "1.0")
import cairo  # noqa: E402
from gi.repository import Gdk, Gio, GLib, Gtk  # noqa: E402
from gi.repository import Gtk4LayerShell as Layer  # noqa: E402

BARS = 24
HIDE_AFTER = {"done": 0.9, "short": 0.8, "cancelled": 0.8, "silent": 0.8, "failed": 1.8}

CSS = b"""
window { background: transparent; }
.pill {
  background: rgba(20, 20, 26, 0.92); border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 22px; min-height: 44px; padding: 0 16px; margin: 14px 16px 12px;
  box-shadow: 0 8px 14px rgba(0, 0, 0, 0.35);
  color: white; font-size: 13px; font-weight: 500;
}
.dot { color: rgb(230, 71, 77); font-size: 12px; animation: pulse 1.2s ease-out infinite; }
@keyframes pulse { from { opacity: 1; } to { opacity: 0.35; } }
.dim { color: rgba(255, 255, 255, 0.6); }
.time { font-family: monospace; font-size: 12px; }
.check { color: rgb(77, 194, 138); font-weight: 700; }
.warn { color: rgb(240, 184, 71); }
"""


class Pill(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="dev.labia.Pill", flags=Gio.ApplicationFlags.NON_UNIQUE)
        self.levels = deque([0.0] * BARS, maxlen=BARS)
        self.started = None
        self.hide_id = None
        self.time = None

    def do_activate(self):
        css = Gtk.CssProvider()
        css.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        self.win = Gtk.Window(application=self)
        Layer.init_for_window(self.win)
        Layer.set_namespace(self.win, "labia")
        Layer.set_layer(self.win, Layer.Layer.OVERLAY)
        Layer.set_anchor(self.win, Layer.Edge.BOTTOM, True)
        Layer.set_keyboard_mode(self.win, Layer.KeyboardMode.NONE)  # never steal focus from the app we type into

        self.box = Gtk.Box(spacing=10, valign=Gtk.Align.CENTER)
        self.box.add_css_class("pill")
        self.win.set_child(self.box)
        self.win.connect("realize", lambda w: w.get_surface().set_input_region(cairo.Region()))  # click-through
        self.hold()  # stay alive while hidden
        GLib.timeout_add(250, self._tick)
        threading.Thread(target=self._read, daemon=True).start()

    # --- input ---------------------------------------------------------------

    def _read(self):
        for line in sys.stdin:
            try:
                msg = json.loads(line)
            except ValueError:
                continue
            GLib.idle_add(self._handle, msg)
        GLib.idle_add(self.quit)

    def _handle(self, msg):
        if "level" in msg:
            self.levels.append(float(msg["level"]))
            if hasattr(self, "wave"):
                self.wave.queue_draw()
        if "state" in msg:
            self._show(msg)
        return False

    # --- states --------------------------------------------------------------

    def _label(self, text, *classes):
        label = Gtk.Label(label=text)
        for c in classes:
            label.add_css_class(c)
        self.box.append(label)
        return label

    def _show(self, msg):
        state = msg["state"]
        if self.hide_id:
            GLib.source_remove(self.hide_id)
            self.hide_id = None
        if state == "hide":
            self.win.set_visible(False)
            return
        while child := self.box.get_first_child():
            self.box.remove(child)
        if hasattr(self, "wave"):
            del self.wave
        self.time = None

        if state in ("listening", "locked"):
            if self.started is None:
                self.started = time.monotonic()
                self.levels.extend([0.0] * BARS)
            self._label("🔒" if state == "locked" else "●", "dot")
            self.wave = Gtk.DrawingArea(content_width=(18 if state == "locked" else BARS) * 5, content_height=24)
            self.wave.set_draw_func(self._draw_wave)
            self.box.append(self.wave)
            self.time = self._label("", "dim", "time")
            if state == "locked":
                self._label("toca ⌥", "dim")
            self._tick()
        else:
            self.started = None
            if state == "transcribing":
                spinner = Gtk.Spinner(spinning=True)
                self.box.append(spinner)
                self._label("Transcribiendo…", "dim")
            elif state == "done":
                n = msg.get("words", 0)
                self._label("✓", "check")
                self._label("Pegado")
                self._label(f"· {n} {'palabra' if n == 1 else 'palabras'}", "dim")
            elif state == "short":
                self._label("✕ Muy corto", "dim")
            elif state == "cancelled":
                self._label("✕ Cancelado", "dim")
            elif state == "silent":
                self._label("No te oí", "dim")
            elif state == "failed":
                self._label("⚠", "warn")
                self._label(msg.get("text", "Error"))
        self.win.set_visible(True)
        if state in HIDE_AFTER:
            self.hide_id = GLib.timeout_add(int(HIDE_AFTER[state] * 1000), self._hide)

    def _hide(self):
        self.win.set_visible(False)
        self.hide_id = None
        return False

    def _tick(self):
        if self.time is not None and self.started is not None:
            s = int(time.monotonic() - self.started)
            self.time.set_label(f"{s // 60}:{s % 60:02d}")
        return True

    def _draw_wave(self, area, cr, width, height):
        bars = width // 5
        for i, v in enumerate(list(self.levels)[-bars:]):
            h = max(3, v * 24)
            cr.set_source_rgba(1, 1, 1, 0.55 + v * 0.45)
            x, y, r = i * 5, (height - h) / 2, 1.5
            cr.new_sub_path()
            cr.arc(x + r, y + r, r, 3.1416, 0)
            cr.arc(x + r, y + h - r, r, 0, 3.1416)
            cr.close_path()
            cr.fill()


if __name__ == "__main__":
    Pill().run([])
