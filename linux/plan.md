# Labia Linux · plan

Versión de Labia para Linux (KDE Plasma en Wayland, GPU NVIDIA). La diferencia con macOS: **transcribe en tiempo real**, escribe las palabras mientras hablas en vez de esperar a que sueltes la tecla.

Regla: todo vive en `linux/`. No se toca nada de `Sources/`, `Tests/`, `Package.swift` ni los `plan.md`/`state.md` de la raíz (son de macOS).

## Decisiones

| Tema | Decisión | Por qué |
|---|---|---|
| Lenguaje | Python 3, venv en `linux/.venv` | faster-whisper y CUDA sin compilar nada |
| Motor | faster-whisper `large-v3-turbo`, CUDA float16 (CPU int8 de respaldo) | Mismo modelo que macOS; ya probado en la GPU |
| Streaming | LocalAgreement-2 (whisper_streaming): una palabra se escribe cuando dos pasadas seguidas coinciden | Evita escribir y borrar a cada rato |
| Paso | Pasada cada 0.5 s; la ventana de audio se recorta a 15 s ya confirmados | Latencia baja sin que Whisper procese audio viejo |
| Última palabra | Se retiene hasta el final | La limpieza o la palabra de envío pueden cambiarla |
| Correcciones | Diff contra lo ya escrito: retrocesos + texto nuevo | Ya escrito en pantalla no se puede "reemplazar" de otra forma |
| Núcleo | `core.py` es port de `LabiaCore` con las mismas pruebas | Mismo comportamiento que macOS |
| Escribir texto | Por decidir en fase 3: `org_kde_kwin_fake_input` (KWin lo expone) o portapapeles (`ext_data_control`) + Ctrl+V | Acentos y ñ deben salir bien en Konsole, VS Code, Brave y Firefox |
| Atajo | evdev (ya instalado) leyendo el teclado; ⌥ derecho igual que macOS | Wayland no deja leer teclas globales de otra forma |
| Micrófono | sounddevice, 16 kHz mono | Ya instalado |

## Módulos (`linux/labia/`)

- `core.py`: gestos, limpieza de texto, palabra de envío, ajustes, historial.
- `stream.py`: `LocalAgreement`, `diff`, `Session` (lógica pura; el modelo se pasa desde fuera).
- `engine.py`: carga del modelo y precarga de las libs CUDA de pip.
- `simulate.py`: pasa un WAV como si fuera en vivo e imprime cada pasada.
- Por hacer: `typer.py` (escribir en la app activa), `hotkey.py`, `recorder.py`, `__main__.py`.

## Fases

1. Núcleo en Python + pruebas.
2. Streaming + simulación con un WAV real en la GPU.
3. Escribir texto en la app activa con acentos (Konsole, VS Code, Brave, Firefox).
4. Micrófono + atajo: el flujo completo en vivo.
5. Ajuste fino: que la pasada baje de 0.5 s y que no se pierdan palabras.
6. Arranque (servicio de systemd de usuario), README de Linux, commit en una rama `feature/linux`.

## Fuera por ahora

Interfaz gráfica, X11, GNOME, empaquetado (AUR/Flatpak).
