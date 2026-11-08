# Labia Linux · state

Última actualización: 2026-11-08. **Actualizar este archivo al terminar cada paso** para retomar si se corta la sesión.

| Fase | Estado |
|---|---|
| 1. Núcleo + pruebas | ✅ 16 pruebas pasan (`.venv/bin/python -m pytest -q`) |
| 2. Streaming + simulación | ✅ funciona en la GPU, con detalles para la fase 5 |
| 3. Escribir texto | ⏳ siguiente |
| 4. Micrófono + atajo | ⬜ |
| 5. Ajuste fino | ⬜ |
| 6. Arranque, README, rama | ⬜ (nada en git todavía; `linux/` está sin seguimiento) |

## Datos del equipo

- KDE Plasma en Wayland. Apps donde dictar: Konsole, VS Code, Brave, Firefox, Alacritty.
- KWin expone `org_kde_kwin_fake_input`, `ext_data_control_manager_v1`, `zwp_text_input_manager_v2/v3`. Klipper está corriendo.
- No hay `wtype`, `ydotool`, `xdotool` ni `wl-copy` instalados.
- Modelo descargado en `~/.cache/huggingface/hub` (1.6 GB). Carga en CUDA ~58 s la primera vez.

## Resultado de la simulación (fase 2)

Clip de 45 s de Wikipedia grabada (`Es-Violeta Parra-article.ogg`, desde el seg. 30, 16 kHz mono). El archivo estaba en /tmp y se borró con el reinicio; para recrearlo: bajarlo de Wikimedia Commons y `ffmpeg -ss 30 -t 45 -i violeta.ogg -ac 1 -ar 16000 clip.wav`.

- Pasada: mediana 0.55 s, máxima 2.2 s. **Se pasa del paso de 0.5 s**: hay que bajarla o subir el paso.
- Nunca hizo falta borrar (todas las pasadas fueron `-0`).
- Se pierden algunas palabras ("versionadas por diversos [artistas]", "rescate de la música chileno"). Revisar el recorte de 15 s y el filtro de solapamiento en `LocalAgreement._fresh`.

## Siguiente paso

Fase 3: probar `org_kde_kwin_fake_input` contra el portapapeles + Ctrl+V escribiendo "acción, niño, über" en Konsole y VS Code. Elegir el que funcione en todas.
