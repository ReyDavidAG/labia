"""Labia's settings window on Windows: General, Vocabulario, Reemplazos, Historial and Modelo.

A separate process (tkinter wants its own main thread), opened from the tray icon or from Start:

    python -m labia.settings_windows [--tab general|vocabulario|reemplazos|historial|modelo]

It only edits settings.json and history.json. The running Labia re-reads settings.json when the next dictation
starts; hotkey, model and language need «Reiniciar Labia», which messages the running copy (tray_windows).
Texts follow Sources/Labia/SettingsView.swift so every platform reads the same.
"""
import argparse
import ctypes
import subprocess
import sys
import tkinter as tk
from dataclasses import replace
from datetime import datetime
from tkinter import messagebox, ttk

from . import audio, core, shortcuts_windows, tray_windows, update, updater, win32
from .hotkey_windows import LABELS

TITLE = "Labia · Ajustes"
APP_ID = "ReyDavidAG.Labia"  # groups the window under Labia's icon in the taskbar, not under Python's
TABS = ["general", "vocabulario", "reemplazos", "historial", "modelo"]
DEFAULT_MIC = "Predeterminado de Windows"
LANGUAGES = {"es": "Español", "en": "English"}
CHANNELS = {"estable": "Estable (versiones publicadas)", "desarrollo": "Desarrollo (sigue develop)"}
RESTART_FIELDS = ("hotkey", "model", "language")  # read once at start-up
PAD = 12


def focus_existing():
    """Bring an already open settings window to the front instead of opening a second one."""
    hwnd = win32.user32.FindWindowW(None, TITLE)
    if hwnd:
        win32.user32.ShowWindow(hwnd, 9)  # SW_RESTORE
        win32.user32.SetForegroundWindow(hwnd)
    return bool(hwnd)


def hint(parent, text, wrap=460):
    return ttk.Label(parent, text=text, style="Hint.TLabel", wraplength=wrap, justify="left")


class SettingsWindow:
    def __init__(self, root, tab):
        self.root = root
        self.saved = core.Preferences.load()
        self.saved_startup = shortcuts_windows.startup_enabled()
        root.title(TITLE)
        root.minsize(560, 520)
        try:
            root.iconbitmap(default=str(tray_windows.ICON))
        except tk.TclError:
            pass
        style = ttk.Style(root)
        style.configure("Hint.TLabel", foreground="#6b6b70")
        style.configure("Title.TLabel", font=("Segoe UI Semibold", 11))
        style.configure("TNotebook.Tab", padding=(12, 4))

        self.notebook = ttk.Notebook(root)
        self.notebook.pack(fill="both", expand=True, padx=PAD, pady=(PAD, 0))
        for name, build in zip(TABS, (self._general, self._vocabulary, self._replacements, self._history, self._model)):
            frame = ttk.Frame(self.notebook, padding=PAD)
            build(frame)
            self.notebook.add(frame, text=name.capitalize())
        self.notebook.select(TABS.index(tab) if tab in TABS else 0)

        bar = ttk.Frame(root, padding=PAD)
        bar.pack(fill="x")
        self.status = ttk.Label(bar, text="", style="Hint.TLabel")
        self.status.pack(side="left")
        ttk.Button(bar, text="Cerrar", command=self.close).pack(side="right")
        ttk.Button(bar, text="Guardar", command=self.save, default="active").pack(side="right", padx=(0, 6))
        ttk.Button(bar, text="Reiniciar Labia", command=self.restart_labia).pack(side="right", padx=(0, 6))
        root.protocol("WM_DELETE_WINDOW", self.close)
        root.bind("<Control-s>", lambda _: self.save())
        root.bind("<Escape>", lambda _: self.close())

    # --- tabs ---

    def _general(self, f):
        s = self.saved
        f.columnconfigure(1, weight=1)
        ttk.Label(f, text="Atajo").grid(row=0, column=0, sticky="w", pady=4, padx=(0, 16))
        self.hotkey = ttk.Combobox(f, state="readonly", values=list(LABELS.values()))
        self.hotkey.set(LABELS.get(s.hotkey, LABELS["KEY_RIGHTALT"]))
        self.hotkey.grid(row=0, column=1, sticky="ew", pady=4)
        hint(f, "Mantén para hablar · doble toque para manos libres · Esc cancela.").grid(
            row=1, column=1, sticky="w")

        ttk.Label(f, text="Micrófono").grid(row=2, column=0, sticky="w", pady=(12, 4), padx=(0, 16))
        self.mics = audio.input_devices()  # [(saved name, shown name)]
        shown = [DEFAULT_MIC] + [full for _, full in self.mics]
        if s.input_device and s.input_device not in (name for name, _ in self.mics):
            self.mics.append((s.input_device, f"{s.input_device} (no conectado)"))
            shown.append(self.mics[-1][1])
        self.mic = ttk.Combobox(f, state="readonly", values=shown)
        self.mic.set(next((full for name, full in self.mics if name == s.input_device), DEFAULT_MIC))
        self.mic.grid(row=2, column=1, sticky="ew", pady=(12, 4))
        hint(f, "Si el micrófono elegido no está conectado, Labia usa el predeterminado. El del DualSense sólo "
                "existe con el control conectado por cable.").grid(row=3, column=1, sticky="w")

        self.auto_type = tk.BooleanVar(value=s.auto_type)
        self.trailing = tk.BooleanVar(value=s.trailing_space)
        self.send = tk.BooleanVar(value=s.send_on_keyword)
        self.startup = tk.BooleanVar(value=self.saved_startup)
        checks = ttk.Frame(f)
        checks.grid(row=4, column=0, columnspan=2, sticky="w", pady=(16, 0))
        ttk.Checkbutton(checks, text="Escribir automáticamente donde está el cursor", variable=self.auto_type).pack(anchor="w", pady=2)
        ttk.Checkbutton(checks, text="Agregar un espacio al final", variable=self.trailing).pack(anchor="w", pady=2)
        ttk.Checkbutton(checks, text="Enviar al terminar con una palabra", variable=self.send,
                        command=self._sync_send).pack(anchor="w", pady=(2, 0))
        words = ttk.Frame(checks)
        words.pack(anchor="w", fill="x", padx=(24, 0))
        self.keywords = ttk.Entry(words, width=40)
        self.keywords.insert(0, ", ".join(s.send_keywords))
        self.keywords.pack(anchor="w", pady=4)
        hint(words, "Termina el dictado con la palabra y Labia la quita, pega y da Enter. Separa con comas.").pack(anchor="w")
        ttk.Checkbutton(checks, text="Abrir al iniciar sesión", variable=self.startup).pack(anchor="w", pady=(10, 2))
        self.auto_update = tk.BooleanVar(value=s.auto_update)
        ttk.Checkbutton(checks, text="Actualizar automáticamente", variable=self.auto_update).pack(anchor="w", pady=2)
        channel = ttk.Frame(checks)
        channel.pack(anchor="w", padx=(24, 0))
        ttk.Label(channel, text="Canal").pack(side="left", padx=(0, 8))
        self.channel = ttk.Combobox(channel, state="readonly", values=list(CHANNELS.values()), width=30)
        self.channel.set(CHANNELS.get(s.update_channel, CHANNELS[updater.STABLE]))
        self.channel.pack(side="left")
        self._sync_send()

    def _sync_send(self):
        self.keywords.configure(state="normal" if self.send.get() else "disabled")

    def _vocabulary(self, f):
        ttk.Label(f, text="Palabras que dices en inglés o con mayúsculas especiales", style="Title.TLabel").pack(anchor="w")
        box = ttk.Frame(f)
        box.pack(fill="both", expand=True, pady=8)
        self.vocab = tk.Text(box, height=12, wrap="none", font=("Segoe UI", 10), undo=True, relief="solid", borderwidth=1)
        scroll = ttk.Scrollbar(box, command=self.vocab.yview)
        self.vocab.configure(yscrollcommand=scroll.set)
        self.vocab.pack(side="left", fill="both", expand=True)
        scroll.pack(side="right", fill="y")
        self.vocab.insert("1.0", "\n".join(self.saved.vocabulary))
        self.vocab.bind("<<Modified>>", self._count_vocab)
        row = ttk.Frame(f)
        row.pack(fill="x")
        self.vocab_count = ttk.Label(row, style="Hint.TLabel")
        self.vocab_count.pack(side="left")
        ttk.Button(row, text="Restaurar lista inicial", command=self._reset_vocab).pack(side="right")
        hint(f, "Una por línea. Whisper usa esta lista como contexto: escribe bien esas palabras y respeta sus "
                "mayúsculas. Cada palabra agrega unos milisegundos, así que pon sólo las que te fallan.").pack(anchor="w", pady=(8, 0))
        self._count_vocab()

    def _count_vocab(self, _=None):
        self.vocab.edit_modified(False)
        n = len(core.parse_list(self.vocab.get("1.0", "end")))
        self.vocab_count.configure(text=f"{n} palabra{'s' if n != 1 else ''}")

    def _reset_vocab(self):
        self.vocab.delete("1.0", "end")
        self.vocab.insert("1.0", "\n".join(core.Preferences().vocabulary))
        self._count_vocab()

    def _replacements(self, f):
        ttk.Label(f, text="Se aplican después de transcribir, en orden y sin distinguir mayúsculas",
                  style="Title.TLabel").pack(anchor="w")
        self.repl = ttk.Treeview(f, columns=("from", "to"), show="headings", height=8, selectmode="browse")
        self.repl.heading("from", text="Dices")
        self.repl.heading("to", text="Se escribe")
        self.repl.pack(fill="both", expand=True, pady=8)
        for r in self.saved.replacements:
            self.repl.insert("", "end", values=(r.get("from", ""), r.get("to", "")))
        add = ttk.Frame(f)
        add.pack(fill="x")
        self.repl_from, self.repl_to = ttk.Entry(add, width=20), ttk.Entry(add, width=20)
        self.repl_from.pack(side="left")
        ttk.Label(add, text="→").pack(side="left", padx=6)
        self.repl_to.pack(side="left")
        ttk.Button(add, text="Agregar", command=self._add_repl).pack(side="left", padx=(8, 0))
        ttk.Button(add, text="Quitar", command=self._remove_repl).pack(side="right")
        self.repl_to.bind("<Return>", lambda _: self._add_repl())
        self.repl.bind("<Delete>", lambda _: self._remove_repl())
        hint(f, "Escribe \\n para un salto de línea. Sirven para comandos dictados como «nueva línea» o para lo "
                "que el vocabulario no alcance.").pack(anchor="w", pady=(8, 0))

    def _add_repl(self):
        src, dst = self.repl_from.get().strip(), self.repl_to.get()
        if not src:
            self.repl_from.focus_set()
            return
        self.repl.insert("", "end", values=(src, dst))
        self.repl_from.delete(0, "end")
        self.repl_to.delete(0, "end")
        self.repl_from.focus_set()

    def _remove_repl(self):
        for item in self.repl.selection():
            self.repl.delete(item)

    def _history(self, f):
        self.hist = ttk.Treeview(f, columns=("date", "text"), show="headings", height=10, selectmode="browse")
        self.hist.heading("date", text="Fecha")
        self.hist.heading("text", text="Texto")
        self.hist.column("date", width=120, stretch=False)
        self.hist.column("text", width=380)
        self.hist.pack(fill="both", expand=True)
        self.hist.bind("<Double-1>", lambda _: self._copy())
        self.hist.bind("<Control-c>", lambda _: self._copy())
        row = ttk.Frame(f)
        row.pack(fill="x", pady=(8, 0))
        ttk.Button(row, text="Copiar", command=self._copy).pack(side="left")
        ttk.Button(row, text="Actualizar", command=self._load_history).pack(side="left", padx=6)
        ttk.Button(row, text="Borrar historial", command=self._clear_history).pack(side="right")
        hint(f, f"Últimos {core.HISTORY_LIMIT}, sólo el texto y sólo en esta computadora. Doble clic copia.").pack(
            anchor="w", pady=(8, 0))
        self._load_history()

    def _load_history(self):
        self.hist.delete(*self.hist.get_children())
        self.history = core.load_history()
        for i, e in enumerate(self.history):
            self.hist.insert("", "end", iid=str(i), values=(_when(e.get("date", "")), e["text"].replace("\n", " ⏎ ")))
        if not self.history:
            label = LABELS.get(self.saved.hotkey, "AltGr")
            self.hist.insert("", "end", values=("", f"Sin dictados todavía. Mantén {label} en cualquier app y habla."))

    def _copy(self):
        sel = self.hist.selection()
        if sel and sel[0].isdigit():
            win32.set_text(self.history[int(sel[0])]["text"], private=False)
            self.flash("Copiado.")

    def _clear_history(self):
        if self.history and messagebox.askyesno(TITLE, "¿Borrar todo el historial? No se puede deshacer.", parent=self.root):
            core.clear_history()
            self._load_history()

    def _model(self, f):
        ttk.Label(f, text=f"Whisper {self.saved.model}", style="Title.TLabel").pack(anchor="w")
        hint(f, "1.6 GB en disco. Corre en la tarjeta de video si hay una NVIDIA y, si no, en el procesador. "
                "Todo se procesa en esta computadora: el audio nunca sale de ella.").pack(anchor="w", pady=(4, 16))
        row = ttk.Frame(f)
        row.pack(anchor="w")
        ttk.Label(row, text="Idioma").pack(side="left", padx=(0, 8))
        self.language = ttk.Combobox(row, state="readonly", values=list(LANGUAGES.values()), width=14)
        self.language.set(LANGUAGES.get(self.saved.language, self.saved.language))
        self.language.pack(side="left")
        hint(f, "El atajo, el modelo y el idioma se aplican al reiniciar Labia.").pack(anchor="w", pady=(16, 0))

        ttk.Separator(f).pack(fill="x", pady=16)
        root = updater.repo_root()
        ttk.Label(f, text=f"Labia {updater.describe(root) if root else ''}".strip(), style="Title.TLabel").pack(anchor="w")
        self.update_info = hint(f, "")
        self.update_info.pack(anchor="w", pady=(4, 8))
        ttk.Button(f, text="Buscar actualizaciones", command=self._check_updates).pack(anchor="w")
        self._show_update_state()

    def _show_update_state(self):
        st = update.state()
        lines = []
        if st.get("checked_at"):
            lines.append(f"Última revisión: {_when(st['checked_at'])}.")
        if st.get("reason"):
            lines.append(st["reason"] + ".")
        elif st.get("error"):
            lines.append(f"No se pudo revisar: {st['error']}")
        elif st.get("available"):
            lines.append(f"Hay una versión nueva: {st['available']}. Se instala cuando no estés dictando.")
        elif st.get("checked_at"):
            lines.append("Está al día.")
        lines.append("Las actualizaciones vienen de github.com/ReyDavidAG/labia.")
        self.update_info.configure(text=" ".join(lines))
        self.root.after(5000, self._show_update_state)  # Labia writes update.json as it checks

    def _check_updates(self):
        if tray_windows.post_to_running("update"):
            self.flash("Buscando… Labia te avisa con una notificación.", ms=6000)
        else:
            self.flash("Labia no está abierta: ábrela para buscar actualizaciones.", ms=6000)

    # --- save ---

    def collect(self):
        hotkey = next((k for k, v in LABELS.items() if v == self.hotkey.get()), self.saved.hotkey)
        mic = next((name for name, full in self.mics if full == self.mic.get()), "")
        language = next((k for k, v in LANGUAGES.items() if v == self.language.get()), self.saved.language)
        repl = [{"from": a, "to": b} for a, b in (self.repl.item(i, "values") for i in self.repl.get_children())]
        return replace(
            self.saved, hotkey=hotkey, input_device=mic, auto_type=self.auto_type.get(),
            trailing_space=self.trailing.get(), send_on_keyword=self.send.get(),
            send_keywords=core.parse_keywords(self.keywords.get()) or list(core.SEND_DEFAULTS),
            vocabulary=core.parse_list(self.vocab.get("1.0", "end")), replacements=repl, language=language,
            auto_update=self.auto_update.get(),
            update_channel=next((k for k, v in CHANNELS.items() if v == self.channel.get()), updater.STABLE))

    def dirty(self):
        return self.collect() != self.saved or self.startup.get() != self.saved_startup

    def save(self):
        new = self.collect()
        needs_restart = any(getattr(new, k) != getattr(self.saved, k) for k in RESTART_FIELDS)
        channel_changed = new.update_channel != self.saved.update_channel
        new.save()
        if channel_changed:
            tray_windows.post_to_running("update")  # move to the other channel now, not in 6 h
        if self.startup.get() != self.saved_startup:
            try:
                shortcuts_windows.set_startup(self.startup.get())
                self.saved_startup = self.startup.get()
            except (OSError, subprocess.CalledProcessError) as err:
                messagebox.showerror(TITLE, f"No se pudo cambiar el inicio de sesión:\n{err}", parent=self.root)
        self.saved = new
        self.keywords.delete(0, "end")
        self.keywords.insert(0, ", ".join(new.send_keywords))
        self.flash("Guardado. Reinicia Labia para aplicar el atajo o el idioma." if needs_restart
                   else "Guardado. Se usa desde el próximo dictado.", ms=6000)
        return True

    def restart_labia(self):
        if self.dirty() and messagebox.askyesno(TITLE, "¿Guardar los cambios antes de reiniciar?", parent=self.root):
            self.save()
        if tray_windows.post_to_running("restart"):
            self.flash("Reiniciando Labia…")
        else:  # not running: start it
            subprocess.Popen([str(shortcuts_windows.pythonw()), "-m", "labia"], cwd=shortcuts_windows.PACKAGE.parent)
            self.flash("Abriendo Labia…")

    def close(self):
        if self.dirty():
            answer = messagebox.askyesnocancel(TITLE, "¿Guardar los cambios?", parent=self.root)
            if answer is None or (answer and not self.save()):
                return
        self.root.destroy()

    def flash(self, text, ms=3000):
        self.status.configure(text=text)
        self.root.after(ms, lambda: self.status.configure(text="") if self.status.cget("text") == text else None)


def _when(iso):
    try:
        return datetime.fromisoformat(iso).astimezone().strftime("%d/%m %H:%M")
    except ValueError:
        return ""


def main():
    p = argparse.ArgumentParser(prog="labia.settings_windows")
    p.add_argument("--tab", default="general", choices=TABS + ["history"])
    args = p.parse_args()
    tab = "historial" if args.tab == "history" else args.tab
    if not win32.claim_single_instance("Local\\LabiaAjustes"):
        focus_existing()
        return
    ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(APP_ID)
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(1)  # crisp text; Tk scales its fonts to the system DPI
    except (AttributeError, OSError):
        pass
    root = tk.Tk()
    SettingsWindow(root, tab)
    root.update_idletasks()
    w, h = max(root.winfo_reqwidth(), 600), max(root.winfo_reqheight(), 560)
    root.geometry(f"{w}x{h}+{(root.winfo_screenwidth() - w) // 2}+{(root.winfo_screenheight() - h) // 3}")
    root.lift()
    root.focus_force()
    root.mainloop()


if __name__ == "__main__":
    sys.exit(main())
