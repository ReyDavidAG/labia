# Labia Linux · state

Última actualización: 2026-11-08. **Actualizar este archivo al terminar cada paso** para retomar si se corta la sesión.

Rama: `feature/linux` (sale de `develop`). **Sin subir a GitHub todavía**: falta iniciar sesión (no hay `gh` ni llave SSH en este equipo).

| Fase | Estado |
|---|---|
| 1. Núcleo + pruebas | ✅ 18 pruebas pasan (`.venv/bin/python -m pytest -q`) |
| 2. Streaming + simulación | ✅ |
| 3. Escribir texto | 🧪 código listo (`typer.py`), falta probar en vivo: necesita `wl-clipboard` |
| 4. Micrófono + atajo | 🧪 código listo (`app.py`, `hotkey.py`), falta probar en vivo: necesita el grupo `input` |
| 5. Ajuste fino | ✅ en simulación: 6 errores de 117 palabras (antes 32) |
| 6. Arranque, README | ✅ `labia.service`, `README.md`, `requirements.txt`; falta habilitarlo tras la prueba en vivo |

## Bloqueado por el usuario (necesita sudo)

```sh
sudo pacman -S --needed wl-clipboard github-cli
sudo usermod -aG input davidag   # y cerrar sesión / volver a entrar
gh auth login                    # para subir la rama
```

## Datos del equipo

- KDE Plasma en Wayland, distribución de teclado `us`. Apps: Konsole, VS Code, Brave, Firefox, Alacritty.
- `/dev/uinput` accesible sin root (regla udev `uaccess`, persiste).
- `/dev/input/event*`: grupo `input`, el usuario no está en él.
- Modelo en `~/.cache/huggingface/hub` (1.6 GB). Carga en CUDA ~58 s la primera vez.
- `faster_whisper.decode_audio` falla con la versión de `av` instalada; no importa porque siempre le pasamos arrays.

## Ajuste fino (fase 5), 2026-11-08

Clip de 45 s de Wikipedia grabada (`Es-Violeta Parra-article.ogg` de Wikimedia Commons, `ffmpeg -ss 30 -t 45 -ac 1 -ar 16000`). Referencia: transcripción completa del mismo clip. Scripts de medición en el scratchpad de la sesión (no en el repo).

| Variante | Errores / 117 |
|---|---|
| Original (2 pasadas seguidas, vocabulario + contexto como prompt) | 32 |
| Sin prompt | 17 |
| Sin prompt + coincidencia con cualquiera de las 2 pasadas anteriores + sin puntuación + filtro por inicio de palabra | **6** |

- Causa: Whisper alterna pasadas buenas con basura (una sola palabra, o frase inventada con tiempos en 0). El prompt lo empeora (bucles «de la investigación de la investigación…»).
- Pasada: ~0.5 s de mediana con la GPU caliente sin importar la ventana; ventana de 10 s → máximo 0.62 s.
- Pendiente menor: a veces queda un punto a media frase («artistas. posteriores») y minúsculas tras punto.
- Riesgo: sin prompt el spanglish (develop, deploy…) depende solo de `core.clean`. Probar dictando en vivo.

## Siguiente paso

Cuando el usuario corra los comandos de arriba: `.venv/bin/python -m labia`, dictar en Konsole, VS Code y Brave (acentos, ñ, «Claude» al final, Esc), revisar que el portapapeles se restaura. Luego habilitar `labia.service` y subir la rama.
