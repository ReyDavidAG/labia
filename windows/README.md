# Labia para Windows

Probado en Windows 11 con una MSI Cyborg 15 A12VF (RTX 4060 Laptop). Es la misma app que en Linux: un solo paquete de Python en `linux/labia/` que elige los módulos según la plataforma. Escribe en tiempo real mientras hablas, se corrige cada 3 s y muestra la cápsula flotante. Los gestos son los mismos: mantener AltGr, doble toque para manos libres, Esc para cancelar y terminar con «Claude» para enviar.

<p align="center"><img src="../docs/img/windows-states.png" alt="La cápsula de Labia en Windows: escuchando con el volumen del micrófono, manos libres, transcribiendo, pegado con 18 palabras, sin voz y cancelado"></p>

| Pieza | Linux | Windows |
|---|---|---|
| Atajo | `hotkey.py`: evdev con grab | `hotkey_windows.py`: gancho `WH_KEYBOARD_LL` |
| Escribir texto | `typer.py`: uinput + wl-copy | `typer_windows.py` + `win32.py`: `SendInput` + portapapeles |
| Cápsula | `pill.py`: GTK 4 + layer-shell | `pill_windows.py`: tkinter + estilos Win32 |
| Todo lo demás | `core.py`, `stream.py`, `engine.py`, `app.py` | igual |

## Instalar

Requiere una GPU NVIDIA con su driver al día (sin GPU funciona en CPU, pero más lento), Git y Python 3.12 de python.org, que trae tkinter. El Python de la Microsoft Store no sirve.

```powershell
winget install Git.Git Python.Python.3.12
git clone https://github.com/ReyDavidAG/labia.git
cd labia\linux
py -3.12 -m venv .venv
.venv\Scripts\pip install -r requirements.txt pytest
.venv\Scripts\python -m pytest -q
.venv\Scripts\python -m labia          # la primera vez baja el modelo (1.6 GB)
```

Cuando dice `listo`, mantén **AltGr** (Alt derecho) en cualquier campo de texto y habla.

Para que arranque al iniciar sesión, sin ventana de consola: crea un acceso directo en `shell:startup` con destino `<ruta>\labia\linux\.venv\Scripts\pythonw.exe -m labia` e «Iniciar en» `<ruta>\labia\linux`.

Los ajustes van en `%APPDATA%\Labia\settings.json` (las mismas claves que en Linux) y el historial en `%APPDATA%\Labia\history.json`.

## Cómo escribe

Las palabras se pegan con el portapapeles y Ctrl+V, y las correcciones borran con Retroceso. Tres detalles evitan que se pierda texto:

- **Espera a que la app lea cada pegado.** Una corrección larga puede mandar cientos de retrocesos, y la app llega tarde al Ctrl+V. Labia usa el render diferido del portapapeles: Windows le avisa en el momento en que la app lee el texto, y hasta entonces no cambia el portapapeles ni suelta Ctrl.
- **Pega en pedazos de 400 caracteres**, para que Claude Code no colapse un dictado largo en «[Pasted text]».
- **Los espacios del final los escribe con teclas**, porque Windows Terminal los recorta al pegar.

Al terminar regresa lo que tenías en el portapapeles. Lo que pega va marcado para que el historial de Win+V y el portapapeles en la nube lo ignoren.

## Problemas comunes

- **No hace nada.** Revisa que la consola diga `listo`. Si el micrófono no capta nada, cámbialo en Configuración → Sistema → Sonido → Entrada: Labia usa el predeterminado.
- **No escribe en una app.** Windows no deja que una app normal mande teclas a una que corre como administrador. Ahí sólo funciona si Labia también corre como administrador.
- **Una imagen copiada desaparece.** Sólo se restaura el texto del portapapeles.
- **Avisa que no puede crear enlaces simbólicos al bajar el modelo.** Es sólo una advertencia de Hugging Face; el modelo se baja igual.
