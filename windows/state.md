# Labia Windows · state

Última actualización: 2026-11-08

| Fase | Estado |
|---|---|
| Plan | ✅ `windows/plan.md` |
| 1. Paquete compartido + pruebas | 🧪 código listo en `feature/windows`; 22 pruebas pasan en Linux, falta correrlas en Windows |
| 2. Simulación en la GPU | 🧪 `engine.py` agrega las carpetas `nvidia/*/bin` con `os.add_dll_directory`; falta probar |
| 3. Escribir texto | 🧪 `typer_windows.py` + `win32.py` (SendInput, portapapeles privado); falta probar |
| 4. Atajo AltGr + flujo en vivo | 🧪 `hotkey_windows.py` (WH_KEYBOARD_LL, Ctrl falso 0x21D); falta probar |
| 5. Cápsula | 🧪 `pill_windows.py` (tkinter + WS_EX_NOACTIVATE/TRANSPARENT/TOPMOST); falta probar |
| 6. Arranque, README, release | 🧪 `windows/README.md` con la lista de pruebas; faltan capturas, CHANGELOG y release |

## Decisiones tomadas

- **No se movió `linux/`.** El código de Windows vive en el mismo paquete `linux/labia/`, y `app.py` elige `hotkey`/`typer`/pill según `sys.platform`. Mover la carpeta habría roto la instalación de Linux (el `.venv` y `labia.service` apuntan a `linux/`). Renombrarla a algo neutral (`git mv linux python`) se puede hacer al final con un solo commit.
- `core.Passthrough` (antes en `hotkey.py`) quedó en `core.py` para que la usen el atajo de Linux y el de Windows. Sus pruebas ya no dependen de evdev.
- `evdev` solo se instala en Linux (marcador en `requirements.txt`). La prueba de `to_gesture` de Linux se salta si no hay evdev.
- La cápsula de Windows usa tkinter, que viene con Python. Si se ve mal con DPI alto, la alternativa es PySide6.

## Para retomar en Windows

Sigue la «Lista de pruebas» de `windows/README.md` en orden. Lo más delicado está en «Puntos que hay que verificar»: AltGr con su Ctrl falso y las apps que corren como administrador.

## Dónde quedó todo (2026-11-08)

- `main` = v0.3.0: primera versión de Linux. Tags: v0.1.0, v0.2.0, v0.3.0. Release en GitHub creado (no marcado como «Latest», para que la 0.2.0 siga siendo la descarga de macOS).
- `develop` = `main` + el plan de Windows.
- `feature/windows` = esta implementación.
- `feature/mac-long-audio`: arreglo de dictados largos en macOS, sin probar (ver «Pendientes» en `plan.md`).
