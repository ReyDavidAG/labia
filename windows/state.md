# Labia Windows · state

Última actualización: 2026-11-08

| Fase | Estado |
|---|---|
| Plan | ✅ `windows/plan.md` |
| 1. Paquete compartido + pruebas | ✅ 21 pruebas pasan en Windows (1 saltada: la de evdev) |
| 2. Simulación en la GPU | ✅ `device: cuda`, 0.33 s por pasada (mediana), por debajo de los 0.5 s del paso |
| 3. Escribir texto | ✅ Windows Terminal y Notepad con prueba automática; Claude Code en vivo |
| 4. Atajo AltGr + flujo en vivo | ✅ dictados en vivo en Claude Code: 7 s y 112 s (este destapó el bug del pegado); ya corregido, 102 s y 45 s completos |
| 5. Cápsula | ✅ los seis estados, `docs/img/windows-states.png` |
| 6. Arranque, README, release | ✅ v0.4.0 |

## Hallazgos de la prueba en Windows

- **Se perdía el dictado largo.** La pasada final de un dictado de 112 s reescribió unos 800 caracteres: `SendInput` mandó todos los retrocesos de golpe, y a los 0.12 s se restauró el portapapeles, antes de que la terminal llegara al Ctrl+V. Se pegó el portapapeles viejo en lugar del dictado. Ahora `win32.DelayedClipboard` usa render diferido (`SetClipboardData(CF_UNICODETEXT, NULL)` y `WM_RENDERFORMAT`): Windows avisa cuando la app lee el texto y hasta entonces no se toca el portapapeles. Reproducido y corregido con una prueba que escribe en Windows Terminal.
- **Una «v» suelta en Notepad**, 9 de cada 15 correcciones: la app revisa si Ctrl está presionado cuando procesa la V, no cuando llegó, y Ctrl ya se había soltado. Ahora Ctrl se suelta hasta que la app lee el pegado: 0 de 15. Mandar el *scan code* no ayudó.
- **Windows Terminal recorta los espacios del final de un pegado** (`trimPaste`): esos espacios se escriben como teclas.
- Los pegados van en pedazos de 400 caracteres para que Claude Code no los colapse en «[Pasted text]».
- `nvidia-cublas-cu12==12.9.3.13` sólo existe para Linux; en Windows va la 12.9.2.10 (marcador en `requirements.txt`).
- Windows no trae voz en español para SAPI: para `--simulate` sin micrófono, la voz en inglés leyendo español sirve para probar la GPU, no la calidad.

## Lo que falta probar

- AltGr+Q sigue dando @ y no se quedan Ctrl ni Alt pegados (prueba 4 de `windows/README.md`).
- VS Code y Brave (prueba 5); la palabra «Claude» al final.
- La cápsula con escala de 125 % y 150 % (aquí está en 100 %).
- Que Win+V no guarde los pedazos (prueba 7).

## Micrófono interno de esta laptop

Hoy no funciona en Windows: el **Intel SST OED** falla con código 10 y el registro dice «Initialize DSP Firmware. Failed to load FW. FW not ready, 0xef000000» en cada arranque desde el 2026-11-01, más «Library is not supported in BIOS» para las librerías de Realtek. Se probó con un micrófono externo (el del control DualSense).

- BIOS E15K1IMS.315 (el más reciente de MSI). ME 16.1.25; MSI ofrece 16.1.42.
- SST activo: 10.29.0.12389 (Windows Update). MSI publica 10.29.0.8365, que también está en el equipo.
- Ya instalado el Realtek Audio 6.0.9481.1 de MSI. En este modelo el códec Realtek se conecta a través del DSP de Intel (`HDXSSTMSI.inf`), así que no aparece mientras el DSP no arranque.
- Pasos que siguen: regresar el SST a 10.29.0.8365; si no, actualizar el ME a 16.1.42 suspendiendo BitLocker antes. Ver también «Diagnóstico del ME» en `linux/state.md`.

## Decisiones tomadas

- **No se movió `linux/`.** El código de Windows vive en el mismo paquete `linux/labia/`, y `app.py` elige `hotkey`/`typer`/pill según `sys.platform`. Mover la carpeta habría roto la instalación de Linux (el `.venv` y `labia.service` apuntan a `linux/`). Renombrarla a algo neutral (`git mv linux python`) se puede hacer al final con un solo commit.
- `core.Passthrough` (antes en `hotkey.py`) quedó en `core.py` para que la usen el atajo de Linux y el de Windows. Sus pruebas ya no dependen de evdev.
- `evdev` sólo se instala en Linux (marcador en `requirements.txt`). La prueba de `to_gesture` de Linux se salta si no hay evdev.
- La cápsula de Windows usa tkinter, que viene con Python.
- La misma idea del pegado en las otras plataformas: macOS usa datos diferidos del portapapeles (`NSPasteboardItemDataProvider`) para restaurar y dar Enter cuando la app ya leyó, compilado por el CI pero sin probar en una Mac. Linux espera 0.6 s antes de restaurar, sin probar: `wl-copy` no avisa cuándo se lee y `--paste-once` lo gastaría Klipper.

## Dónde quedó todo (2026-11-08)

- `main` = v0.4.0: primera versión de Windows. Release en GitHub sin marcar como «Latest», para que la 0.2.0 siga siendo la descarga de macOS.
- `feature/mac-long-audio`: arreglo de dictados largos en macOS, sin probar (ver «Pendientes» en `plan.md`).
