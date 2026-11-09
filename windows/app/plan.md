# Labia Windows como app · plan

Rama `feature/windows-app`, sale de `feature/windows-single-instance` (una sola Labia por sesión y error visible si no abre el micrófono).

## Problema

La versión 0.4.0 de Windows dicta bien, pero no es una app: es `pythonw -m labia` corriendo sin ventana.

- No aparece al buscar «Labia» en Inicio y no tiene ícono propio.
- No hay ajustes: hay que editar `%APPDATA%\Labia\settings.json` a mano.
- No hay forma de cerrarla ni de pausarla sin el Administrador de tareas.
- No hay cómo elegir el micrófono: usa el predeterminado de Windows.

## Meta

Que en Windows se use como la versión de macOS: la buscas en Inicio, la abres, la configuras y la cierras. Sin instalador por ahora (con CUDA serían varios GB); se instala desde el repositorio con un script.

## Decisiones

| Tema | Decisión | Por qué |
|---|---|---|
| Ícono junto al reloj | `Shell_NotifyIconW` con ctypes, en su propio hilo con bucle de mensajes (`tray_windows.py`) | Mismo estilo que el resto del port: sin pywin32 ni pystray |
| Menú | Estado (desactivado) · Ajustes… · Historial… · Pausar/Reanudar · Reiniciar · Salir. Clic izquierdo abre Ajustes | Igual que el menú de la barra en macOS, más Salir, que hoy no existe |
| Ventana de ajustes | tkinter en un **proceso aparte** (`settings_windows.py`), igual que la cápsula | tkinter quiere su propio hilo principal; si la ventana falla no tumba el dictado |
| Pestañas | General · Vocabulario · Reemplazos · Historial · Modelo, con los textos de `SettingsView.swift` | Una sola Labia en todas las plataformas |
| Cómo se aplican los cambios | La ventana guarda `settings.json`; Labia lo relee (por fecha de modificación) al empezar cada dictado | Sin IPC: el archivo ya es la fuente de verdad. Atajo, modelo e idioma piden reiniciar, con un botón «Reiniciar Labia» |
| Hablar entre procesos | La ventana oculta del ícono tiene la clase `LabiaTray`; otros procesos le mandan `WM_APP+1` (abrir ajustes), `WM_APP+2` (historial) o `WM_APP+3` (reiniciar) con `PostMessageW` | Mensajes de Windows: nada que mantener, no abre puertos |
| Abrirla dos veces | La segunda copia no se cierra en silencio: le pide a la que corre que abra Ajustes | Buscar «Labia» en Inicio con Labia ya abierta debe mostrar algo |
| Reiniciar | La copia vieja lanza la nueva con `--reiniciar`, que espera hasta 15 s a que se libere el mutex, y luego sale | El mutex de una sola copia se libera al salir |
| Salir | Deja de aceptar dictados, espera hasta 10 s al dictado en curso (puede tener Ctrl presionado mientras pega), quita el ícono y cierra la cápsula. Mientras carga el modelo sale de inmediato | No dejar Ctrl pegado ni íconos fantasma |
| Pausar | Ignora el atajo y cancela el dictado en curso. AltGr con otra tecla sigue funcionando | Para jugar o presentar sin cerrar Labia |
| Micrófono | Nuevo ajuste `input_device` (nombre; vacío = predeterminado de Windows). Si ya no existe, usa el predeterminado | Con el DualSense por Bluetooth su micrófono desaparece; no debe romper el dictado |
| Lista de micrófonos | Sólo los de la API predeterminada de PortAudio (MME), sin duplicados | sounddevice lista cada micrófono una vez por API (MME, DirectSound, WASAPI) |
| Iniciar con Windows | Casilla en General: crea o borra `Labia.lnk` en `shell:startup` | El usuario lo decide desde la app, como «Abrir al iniciar sesión» en macOS |
| Accesos directos | `windows/install.ps1` crea `Labia` en el menú Inicio (con `--abrir`, ícono y carpeta de trabajo); `-Inicio` agrega el de arranque; `-Quitar` borra los dos | Así aparece en la búsqueda de Inicio. Se puede repetir sin duplicar |
| Ícono | `linux/labia/labia.ico` (16 a 256 px) generado desde `docs/icon.png` con `windows/make_icon.py` | El logo «Dicho y escrito» de la 1.0 |
| Ícono en la barra de tareas | La ventana de ajustes fija su `AppUserModelID` (`ReyDavidAG.Labia`) y su ícono | Si no, Windows la agrupa como «Python» |
| Codificación | `settings.json` e `history.json` en UTF-8. Al leer, si no es UTF-8, se lee con la codificación de Windows (como se escribía antes) | Antes usaban la codificación por defecto (cp1252 en Windows): «ñ» funcionaba, un emoji o «→» rompía el archivo. El historial existente no se pierde |

## Módulos

- `core.py`: lectura y escritura en UTF-8 con respaldo; `input_device` en `Preferences`; `parse_list` y `parse_keywords` (texto de la ventana → listas), con pruebas.
- `audio.py`: `input_devices()` y `resolve_device(name)`, con pruebas (sounddevice simulado).
- `tray_windows.py`: el ícono, el menú, los mensajes entre procesos y `notify()` (globo de Windows).
- `settings_windows.py`: la ventana de ajustes.
- `shortcuts_windows.py`: crear y borrar accesos directos (`WScript.Shell` vía PowerShell, rutas por variables de entorno).
- `app.py`: estado para el ícono, pausa, salir limpio, releer ajustes, micrófono elegido.
- `__main__.py`: `--abrir`, `--reiniciar`.

## Fases

1. Plan y state.
2. UTF-8 y `input_device` en el núcleo, con pruebas.
3. Micrófono elegido (`audio.py`) en el dictado.
4. Ícono junto al reloj: estado, pausar, reiniciar, salir, una sola copia que abre Ajustes.
5. Ventana de ajustes con sus cinco pestañas.
6. Ícono `.ico`, accesos directos e `install.ps1`.
7. README de Windows, CHANGELOG y `state.md`.

## Fuera de esta rama

- Instalador `.exe` (Inno Setup o PyInstaller): con las DLL de CUDA pesa varios GB. Ver «Ideas» en `state.md`.
- Medir el costo del vocabulario como hace macOS (`promptCostLabel`).
- Liberar el modelo después de un rato sin dictar (macOS lo tiene).
- Portar el ícono y la ventana a Linux (GTK).
