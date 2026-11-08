# Labia Linux · plan

Versión de Labia para Linux (KDE Plasma en Wayland, GPU NVIDIA). La diferencia con macOS: **transcribe en tiempo real**, escribe las palabras mientras hablas en vez de esperar a que sueltes la tecla.

Regla: todo vive en `linux/`. No se toca nada de `Sources/`, `Tests/`, `Package.swift` ni los `plan.md`/`state.md` de la raíz (son de macOS).

## Decisiones

| Tema | Decisión | Por qué |
|---|---|---|
| Lenguaje | Python 3, venv en `linux/.venv` | faster-whisper y CUDA sin compilar nada |
| Motor | faster-whisper `large-v3-turbo`, CUDA float16 (CPU int8 de respaldo) | Mismo modelo que macOS; ya probado en la GPU |
| Streaming | LocalAgreement: una palabra se escribe cuando la pasada nueva coincide con alguna de las dos anteriores (sin puntuación ni mayúsculas) | Whisper suelta pasadas basura de vez en cuando; contra una sola pasada se perdían palabras |
| Prompt | Ninguno en las pasadas; el vocabulario se aplica sobre el texto (`core.clean`) | Con prompt, Whisper entraba en bucle en audio corto: 32 errores contra 6 sin él |
| Paso | Pasada cada 0.5 s; la ventana se recorta cuando pasa de 10 s | La pasada cuesta ~0.5 s sin importar la ventana (Whisper rellena a 30 s); 10 s da el peor caso más bajo |
| Última palabra | Se retiene hasta el final | La limpieza o la palabra de envío pueden cambiarla |
| Correcciones | Diff contra lo ya escrito: retrocesos + texto nuevo | Ya escrito en pantalla no se puede "reemplazar" de otra forma |
| Núcleo | `core.py` es port de `LabiaCore` con las mismas pruebas | Mismo comportamiento que macOS |
| Escribir texto | Teclas por uinput (permiso `uaccess` ya existe); texto por `wl-copy --sensitive` en clipboard y primary + Shift+Insert | Acentos con cualquier distribución; Shift+Insert pega en terminales (primary) y en navegadores/VS Code (clipboard); Klipper ignora lo sensible |
| Atajo | evdev leyendo los teclados (grupo `input`); Alt derecho igual que macOS. Esc no se traga: también llega a la app | Wayland no deja leer teclas globales de otra forma; tragar Esc exigiría agarrar el teclado entero |
| Micrófono | sounddevice, 16 kHz mono | Ya instalado |

## Módulos (`linux/labia/`)

- `core.py`: gestos, limpieza de texto, palabra de envío, ajustes, historial.
- `stream.py`: `LocalAgreement`, `diff`, `Session` (lógica pura; el modelo se pasa desde fuera).
- `engine.py`: carga del modelo y precarga de las libs CUDA de pip.
- `simulate.py`: pasa un WAV como si fuera en vivo e imprime cada pasada.
- `typer.py`: escribe en la app activa. `hotkey.py`: atajo con evdev. `app.py`: bucle en vivo (micrófono con sounddevice + hilo de dictado). `__main__.py`: `python -m labia [--simulate wav]`.
- `labia.service`: servicio de systemd de usuario.

## Fases

1. Núcleo en Python + pruebas.
2. Streaming + simulación con un WAV real en la GPU.
3. Escribir texto en la app activa con acentos (Konsole, VS Code, Brave, Firefox).
4. Micrófono + atajo: el flujo completo en vivo.
5. Ajuste fino: que la pasada baje de 0.5 s y que no se pierdan palabras.
6. Arranque (servicio de systemd de usuario), README de Linux, commit en una rama `feature/linux`.

## Fuera por ahora

Interfaz gráfica, X11, GNOME, empaquetado (AUR/Flatpak).
