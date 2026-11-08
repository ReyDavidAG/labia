# Labia Windows · plan

Versión de Labia para Windows 11, en la misma laptop que la de Linux (MSI Cyborg 15 A12VF: i7 de 12.ª gen, RTX 4060 Laptop de 8 GB, micrófono interno que en Windows **sí** funciona). La meta es la misma experiencia que en Linux 0.3.0: escritura en tiempo real, correcciones cada 3 s y la cápsula flotante de macOS.

## Para retomar en una sesión nueva

1. `git clone https://github.com/ReyDavidAG/labia.git && cd labia && git checkout feature/windows` (el código ya está escrito; falta probarlo)
2. Lee, en este orden: `state.md` (raíz, macOS), `linux/plan.md`, `linux/state.md`, `linux/README.md`, este archivo y `windows/state.md`.
3. Las reglas del repo están en `CONTRIBUTING.md`: ramas `main`/`develop`/`feature/*`, commits de una línea en inglés y en imperativo, interfaz en español y código en inglés.
4. Sigue la «Lista de pruebas» de `windows/README.md`. Las decisiones que se tomaron al escribir el código están en `windows/state.md`.

## Punto de partida: reutilizar el paquete de Linux

`linux/labia/` es Python y casi todo es independiente de la plataforma:

| Módulo | ¿Sirve en Windows? |
|---|---|
| `core.py` (gestos, limpieza, palabra de envío, ajustes, historial) | Sí, tal cual. Hay que revisar las rutas: `XDG_*` → `%APPDATA%\Labia` |
| `stream.py` (LocalAgreement, borrador + corrección + pasada final) | Sí, tal cual |
| `engine.py` (faster-whisper) | Sí, pero `_preload_cuda_libs` solo funciona en Linux. En Windows hay que usar `os.add_dll_directory` con `site-packages/nvidia/cublas/bin` y `cudnn/bin` |
| `simulate.py`, pruebas en `linux/tests/` | Sí |
| `hotkey.py` (evdev), `typer.py` (uinput + wl-copy), `pill.py` (GTK + layer-shell) | No. Hay que escribir la versión de Windows |
| `app.py` | Sí, si escoge los módulos de plataforma según `sys.platform` |

**Decisión (2026-11-08): por ahora no se mueve `linux/`, ver `windows/state.md`.** La opción original era mover `linux/` a una carpeta común (por ejemplo `python/`, con `git mv` para conservar el historial) y poner los módulos de cada plataforma como `hotkey_linux.py` / `hotkey_windows.py`. La otra opción es copiar el paquete a `windows/`, pero entonces habría dos núcleos que mantener. Recomiendo la carpeta común.

## Piezas propias de Windows

| Tema | Propuesta | Cuidado con |
|---|---|---|
| Atajo | Gancho de teclado de bajo nivel (`SetWindowsHookExW(WH_KEYBOARD_LL)` con ctypes, sin dependencias). Devolver 1 se traga la tecla: es el equivalente al grab de evdev, y es más fácil | Con distribución Español/Latinoamérica, Alt derecho es **AltGr** y Windows manda también un **LCtrl falso** (scan code 0x21D, con la marca `LLKHF_INJECTED` apagada). Hay que tragar los dos cuando Alt derecho se usa solo, y dejar pasar los dos cuando es acorde (AltGr+Q = @). El gancho debe correr en un hilo con bucle de mensajes y responder rápido, porque Windows lo desconecta si tarda más de ~1 s (`LowLevelHooksTimeout`) |
| Escribir texto | Portapapeles + `SendInput` de Ctrl+V. Retroceso con `SendInput` para las correcciones. Al terminar, restaurar el portapapeles | Marcar el contenido con los formatos `ExcludeClipboardContentFromMonitorProcessing` y `CanIncludeInClipboardHistory = 0` para que no se llene el historial de Win+V. Por UIPI, si la app de destino corre como administrador, Labia no puede escribir en ella a menos que también corra como administrador |
| Cápsula | Ventana sin borde, abajo al centro del área de trabajo del monitor donde está el cursor. Estilos `WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT | WS_EX_LAYERED | WS_EX_TOOLWINDOW`: flota, deja pasar los clics, no quita el foco y no sale en la barra de tareas | Mismos estados y tiempos que `linux/labia/pill.py` y `Sources/Labia/PillView.swift`. Se puede hacer con tkinter (viene con Python) más esos estilos vía ctypes, o con PySide6 si tkinter se ve mal con DPI alto |
| Micrófono | `sounddevice` (WASAPI), 16 kHz mono | El interno funciona en Windows. Para elegir otro, el dispositivo predeterminado de Windows |
| Arranque | Acceso directo a `pythonw -m labia` en `shell:startup`, o el Programador de tareas | — |
| GPU | `pip install faster-whisper nvidia-cublas-cu12 nvidia-cudnn-cu12` (mismas versiones que `linux/requirements.txt`) | Si CTranslate2 no encuentra las DLL, ver la nota de `engine.py` en la tabla anterior |

## Fases

1. Rama `feature/windows`, carpeta común y `python -m pytest` pasando en Windows.
2. `--simulate` con un WAV en la GPU (CUDA en Windows).
3. Escribir texto con acentos y ñ en Notepad, VS Code, Brave y Windows Terminal.
4. Atajo con AltGr bien manejado: el flujo completo en vivo, con el texto apareciendo mientras se mantiene la tecla.
5. Cápsula.
6. Arranque con la sesión, README de Windows con capturas, CHANGELOG y release.

## Pendientes de otras plataformas (no olvidar)

- **macOS 0.3.1**: la rama `feature/mac-long-audio` (commit `f86ee9a`) activa `chunkingStrategy = .vad` para dictados de más de 30 s. Antes solo llegaban las primeras frases. Falta probarlo en la Mac (`swift test && scripts/bundle.sh`, más un dictado de más de 1 minuto) y luego hacer merge y tag `v0.3.1`.
- **macOS**: portar la escritura en tiempo real y las correcciones de Linux (`linux/labia/stream.py`) a Swift.
- **Micrófono interno en Linux**: el Intel ME está en modo Recovery (`linux/state.md`, sección «Diagnóstico del ME»). Pasos a seguir desde Windows: desactivar el **Inicio rápido**, apagar Windows por completo y probar SOF en Linux. Si no se arregla, actualizar el BIOS y el ME desde el soporte de MSI para el MS-15K1, **suspendiendo BitLocker antes** (el disco C: está cifrado).
