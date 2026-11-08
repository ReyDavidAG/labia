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

## Prueba en vivo, 2026-11-08 (tras reiniciar)

- Grupo `input` activo, teclado legible, `wl-copy` instalado. El modelo carga y Labia queda «listo».
- **Bloqueo: no hay micrófono.** Al empezar a dictar falla con `PortAudioError -9999` porque PipeWire no tiene fuente predeterminada. El ALC256 solo expone el jack de micrófono (`Pin 0x03a19030: [Jack] Mic at Ext Left`), marcado «not available» porque no hay nada conectado. El micrófono interno no aparece en ALSA y la webcam no tiene audio.
- Grabar forzando `pw-record --target 54` sí abre, pero da −70 dB (nada).
- Causa del micrófono interno: Cyborg 15 A12VF (Alder Lake, ALC256), con NHLT, así que el micrófono interno es DMIC y necesita SOF. El 2026-07-27 el usuario creó `/etc/modprobe.d/disable-sof.conf` (`dsp_driver=1`) porque con SOF no salía ninguna tarjeta de audio. También creó `alc256-fix.conf` (`model=alc256-easus`) para las bocinas. Ahora hay `sof-firmware 2026.09.2` y kernel 7.3.
- Plan elegido por el usuario: arreglar el interno. Mover `disable-sof.conf` a `.bak`, reiniciar y probar bocinas + micrófono. Si se rompe el audio, regresar el archivo y reiniciar.
- Otra opción: que el usuario conecte un micrófono (jack, USB o Bluetooth) o revisar el micrófono interno. Si al conectarlo PipeWire lo pone como predeterminado, el código no necesita cambios.

### Intento 1 con SOF (2026-11-08 11:41)

- `disable-sof.conf` → `.bak` y reinicio: SOF carga y detecta 2 DMIC en NHLT, pero el DSP no arranca: `cl_dsp_init: timeout`, `CSE_IPC_RESET_PHASE_1, waiting for: CSE_CSR`, `-110`. La tarjeta Intel no aparece: sin bocinas (Dummy Output) y sin micrófono. Es el mismo fallo de julio.
- El ME está vivo (`mei_me`, `/dev/mei0`). Usó IPC3 (`intel/sof/sof-adl.ri`, ABI 3:22 contra kernel 3:23).
- Siguiente: (a) apagado completo, no reinicio, por si el CSE quedó trabado; (b) `options snd_sof_pci ipc_type=1` (IPC4, `intel/sof-ipc4/adl`). Si nada sirve, regresar `disable-sof.conf` y usar un micrófono externo.

## Siguiente paso

Cuando el usuario corra los comandos de arriba: `.venv/bin/python -m labia`, dictar en Konsole, VS Code y Brave (acentos, ñ, «Claude» al final, Esc), revisar que el portapapeles se restaura. Luego habilitar `labia.service` y subir la rama.

### Intento 2: IPC4 + apagado completo (2026-11-08 11:47)

- `sof-ipc4.conf` (`ipc_type=1`) y apagado total. Carga `sof-ipc4/adl/sof-adl.ri`, pero falla igual: `CSE_IPC_RESET_PHASE_1, waiting for: CSE_CSR`, `-110`.
- Conclusión: la ROM del DSP no pasa de la validación del CSE (Intel ME) con ningún firmware. No es IPC3/IPC4 ni el estado del ME tras reinicio. Probable causa: BIOS/ME de MSI.
- Decisión pendiente: revertir a `disable-sof.conf` (bocinas sí, mic interno no) y usar micrófono externo.

### Diagnóstico del ME (2026-11-08)

- `/sys/class/mei/mei0/fw_status` HFSTS1 = `0x90000642` → working_state=2 **Recovery**, bit 10 **Bringup Loader Failure**, error_code 0 (decodificado con la tabla de coreboot intelmetool; ojo: es para ME viejo, en CSME 16 podría variar).
- `fw_ver`: 16.1.25.2049 / 2049 / 2053 (versiones distintas entre particiones).
- El ME es el que verifica la firma del firmware del DSP: si está en Recovery, el DSP no arranca (mismo síntoma que Libreboot con ME apagado, chromebook-linux-audio#453).
- Equipo: MSI Cyborg 15 A12VF (MS-15K1), BIOS E15K1IMS.315 (2024-09-19). Dual boot con Windows (C: con BitLocker).
- Siguiente: probar el mic en Windows; apagar Fast Startup; actualizar BIOS/ME de MSI (suspender BitLocker antes).

### Precisión estilo Apple (2026-11-08)

- Inspirado en SpeechAnalyzer (resultados volátiles → finales por tramo de audio, WWDC25 #277).
- Pasada rápida cada 0.5 s (borrador, beam 1). Cada 3 s de audio nuevo, pasada cuidadosa (beam 5 + VAD) que reescribe las palabras ya confirmadas de la ventana; se ignora si trae < 60 % de las palabras (pasada basura).
- Al soltar: pasada cuidadosa sobre TODA la grabación con VAD de Silero → sin voz no escribe nada (adiós «Gracias.» / «Suscríbete al canal»).
- Pendiente: `hotwords` con el vocabulario (equivalente a `contextualStrings`); medir costo de las pasadas cuidadosas con grabaciones reales.
- Teclado: Labia toma los teclados (evdev grab) y reenvía todo menos Alt derecho solo, para que el pegado funcione mientras se mantiene. El bucle de teclas ya no espera a Whisper.
