# Labia Windows como app · state

Última actualización: 2026-11-08

| Fase | Estado |
|---|---|
| 1. Plan y state | ✅ `windows/app/plan.md` |
| 2. UTF-8 e `input_device` en el núcleo | ✅ 3 pruebas nuevas; el historial real (cp1252) se lee bien |
| 3. Micrófono elegido | ✅ `audio.py` + 2 pruebas; grabado real con el DualSense y con un nombre que ya no existe (usa el predeterminado) |
| 4. Ícono junto al reloj | ✅ estado, Pausar, Reiniciar, Salir; mensajes entre procesos probados |
| 5. Ventana de ajustes | ✅ cinco pestañas revisadas con capturas; guardar y «¿guardar cambios?» probados |
| 6. `.ico`, accesos directos, `install.ps1` | ✅ instalado en esta laptop: menú Inicio e inicio de sesión |
| 7. README, CHANGELOG | ✅ `windows/README.md` (sección «Usarla»), `docs/img/windows-settings.png` |
| 8. Instalador de un comando (`windows/setup.ps1`) | ✅ instalar, actualizar y desinstalar probados en una carpeta aparte desde `develop` |

## Instalador de un comando

- `irm … -OutFile $env:TEMP\labia-setup.ps1; powershell -ExecutionPolicy Bypass -File …`: se baja a un archivo y se corre con `-File`. `irm | iex` no sirve: PowerShell 5.1 necesita el BOM para leer los acentos de un `.ps1`, y con BOM `Invoke-Expression` falla en la primera línea.
- El README apunta a `main`: funciona en cuanto esta versión llegue a `main`. Antes, agregar `-Rama develop`.
- Instalación nueva: 93 s con las dependencias y el modelo ya en caché.
- Actualizar respeta «Abrir al iniciar sesión»: sólo una instalación nueva lo activa; `-SinInicio` lo quita.
- `-Desinstalar` sólo borra la carpeta si contiene `linux\labia\app.py`, y nunca `%APPDATA%\Labia`.

Pruebas: 26 pasan, 1 saltada (la de evdev). `python -m pytest -q` en `linux/`.

## Probado en esta laptop (2026-11-08)

- Abrir desde el acceso del menú Inicio: ícono junto al reloj y ventana de ajustes.
- Abrirla otra vez desde Inicio: no se duplica; la que corre abre (o trae al frente) sus ajustes.
- Reiniciar por mensaje: la vieja sale y la nueva (`--reiniciar`) espera el mutex y toma el teclado.
- Salir por mensaje con el modelo cargado y mientras carga: no quedan procesos ni ícono.
- Grabar 1.5 s con el micrófono elegido y con uno que ya no existe.
- Ventana de ajustes: sin cambios no pregunta al cerrar; con cambios detecta cuáles piden reiniciar (atajo).

## Hallazgos

- **Los ajustes y el historial usaban la codificación por defecto** (`read_text()` sin `encoding`, cp1252 en Windows). «ñ» y acentos funcionaban de casualidad; un emoji o «→» en el vocabulario lanzaba `UnicodeEncodeError` al guardar. Ahora UTF-8 con respaldo a la codificación local al leer.
- **El mutex de una sola copia no se liberaba para reiniciar**: `CreateMutexW` devuelve un identificador aunque el mutex ya exista, y ese identificador lo mantiene vivo después de que la otra copia sale. Ahora se cierra cuando la otra copia lo tiene.
- **MME recorta los nombres de micrófono a 31 caracteres** («Headset Microphone (3- DualSens»). Se guarda el nombre de MME (el que se abre) y se muestra el más largo que da otra API para el mismo micrófono.
- **PortAudio sólo ve los micrófonos que había al arrancar.** Refrescar cuesta ~13 ms; se hace al empezar un dictado, sólo si no hay otro con el micrófono abierto.
- `FindWindowW` desde PowerShell (`Add-Type`) no encontró las ventanas, desde Python sí: era la prueba, no Labia.
- Con un entorno virtual, `sys.executable` es el `pythonw.exe` del `.venv` (aunque el proceso real sea el Python base): sirve para lanzar la ventana de ajustes y el reinicio.

## Pruebas a mano

Las 1 a 3 las probó el usuario antes de la 1.0.0 (2026-11-08). Faltan de la 4 a la 7.

1. Clic derecho en el ícono: el menú se cierra al hacer clic afuera; Pausar queda con palomita y el tooltip dice «En pausa».
2. En pausa, AltGr no graba y AltGr+Q sigue dando @.
3. Salir desde el menú durante un dictado largo: termina de escribir antes de cerrar y no deja Ctrl presionado.
4. Cambiar el atajo a Ctrl derecho → Guardar → Reiniciar Labia: el tooltip dice «mantén Ctrl derecho».
5. Elegir el micrófono del DualSense, desconectar el cable y dictar: usa el predeterminado (o muestra ⚠ si no hay ninguno).
6. Escala de pantalla al 125 % y 150 %: ventana de ajustes e ícono nítidos.
7. Reiniciar Explorer (Administrador de tareas → Explorador de Windows → Reiniciar): el ícono vuelve.

## Ideas

- Instalador `.exe` (Inno Setup): copiar el repositorio, crear el `.venv` y bajar las dependencias en la instalación, en vez de empaquetar varios GB de CUDA.
- Nivel del micrófono en vivo en la pestaña General, para probar el elegido.
- Cerrar la ventana de ajustes cuando Labia sale (hoy queda abierta; sigue sirviendo para editar).
- Notificación de Windows cuando el micrófono elegido no está y se usa el predeterminado.
- Ícono y ventana para Linux (GTK, `StatusNotifierItem`).
