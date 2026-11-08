# Labia para Windows

> **Estado: escrito, sin probar.** El código está en la rama `feature/windows` y falta probarlo en una máquina con Windows. Ver `windows/state.md`.

Es la misma app que en Linux: un solo paquete de Python en `linux/labia/` que elige los módulos según la plataforma. Escribe en tiempo real mientras hablas, se corrige cada 3 s y muestra la cápsula flotante. Los gestos son los mismos (mantener AltGr, doble toque, Esc, terminar con «Claude»).

| Pieza | Linux | Windows |
|---|---|---|
| Atajo | `hotkey.py`: evdev con grab | `hotkey_windows.py`: gancho `WH_KEYBOARD_LL` |
| Escribir texto | `typer.py`: uinput + wl-copy | `typer_windows.py` + `win32.py`: `SendInput` + portapapeles |
| Cápsula | `pill.py`: GTK 4 + layer-shell | `pill_windows.py`: tkinter + estilos Win32 |
| Todo lo demás | `core.py`, `stream.py`, `engine.py`, `app.py` | igual |

## Instalar y probar

Requiere Python 3.12 o posterior de python.org (trae tkinter) y una GPU NVIDIA con su driver al día.

```powershell
git clone https://github.com/ReyDavidAG/labia.git
cd labia
git checkout feature/windows
cd linux
py -m venv .venv
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python -m pytest -q
.venv\Scripts\python -m labia          # la primera vez baja el modelo (1.6 GB)
```

Para que arranque al iniciar sesión, sin ventana de consola: crea un acceso directo en `shell:startup` con destino `<ruta>\labia\linux\.venv\Scripts\pythonw.exe -m labia` e «Iniciar en» `<ruta>\labia\linux`.

Los ajustes van en `%APPDATA%\Labia\settings.json` (las mismas claves que en Linux) y el historial en `%APPDATA%\Labia\history.json`.

## Lista de pruebas

1. `pytest` pasa.
2. Al arrancar dice `listo` y usa la GPU. Si CTranslate2 no encuentra `cublas64_12.dll` o `cudnn*.dll`, revisa `engine._preload_cuda_libs`.
3. Mantener AltGr y hablar en Notepad: el texto **aparece mientras hablas**, con acentos y ñ.
4. AltGr+Q sigue escribiendo **@**, y AltGr solo no deja Ctrl ni Alt pegados (prueba Ctrl+C y Alt+Tab justo después de dictar).
5. Lo mismo en VS Code, Brave y Windows Terminal. La palabra «Claude» al final da Enter.
6. La cápsula sale abajo al centro del monitor donde está el mouse, no le quita el foco a la app y deja pasar los clics. Se ve nítida con escala de 125 % y 150 %.
7. Después de dictar, Win+V no muestra los pedazos dictados y el portapapeles anterior regresa.
8. Un dictado de más de 1 minuto sale completo.

## Puntos que hay que verificar

- **AltGr.** Con distribución Español/Latinoamérica, Windows manda un Ctrl izquierdo falso (scan code `0x21D`) junto con AltGr. El gancho lo trata igual que AltGr: lo traga o lo deja pasar junto con él. Si se queda Ctrl «pegado», revisa `hotkey_windows._hook_thread`.
- **Apps como administrador.** Windows no deja que una app normal mande teclas a una que corre como administrador (UIPI). Ahí no se escribe nada a menos que Labia también corra como administrador.
- **Portapapeles.** Solo se restaura texto. Si antes de dictar había una imagen copiada, se pierde.
