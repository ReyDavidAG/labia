# Labia para Linux

Dictado en español con **transcripción en tiempo real**: mantienes ⌥ derecho (Alt derecho), hablas y el texto va apareciendo mientras hablas en la app donde está el cursor. Todo local, con Whisper large-v3-turbo en la GPU.

Probado en KDE Plasma (Wayland) con GPU NVIDIA. La versión de macOS está en la raíz del repo y no depende de esta carpeta.

## Uso

| Gesto | Qué hace |
|---|---|
| Mantener Alt derecho | Graba mientras lo mantienes; el texto aparece mientras hablas |
| Doble toque | Manos libres hasta el siguiente toque |
| Esc | Cancela y borra lo que se escribió |
| Terminar con «Claude» | Quita la palabra y presiona Enter |

## Instalación

```sh
sudo pacman -S --needed wl-clipboard portaudio
sudo usermod -aG input $USER        # para leer el atajo; cierra sesión y vuelve a entrar
cd ~/labia/linux
python -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python -m labia            # la primera vez baja el modelo (1.6 GB)
```

Para que arranque con la sesión:

```sh
mkdir -p ~/.config/systemd/user && cp labia.service ~/.config/systemd/user/
systemctl --user enable --now labia
journalctl --user -u labia -f        # ver lo que dicta
```

Ajustes en `~/.config/labia/settings.json`: crea el archivo solo con las claves que quieras cambiar (ver `Preferences` en `labia/core.py`). El historial queda en `~/.local/share/labia/history.json`.

## Cómo funciona

- Cada 0.5 s Whisper transcribe el audio acumulado. Una palabra se escribe cuando aparece igual en esa pasada y en alguna de las dos anteriores (LocalAgreement). Así casi nunca hay que borrar.
- La última palabra se retiene hasta soltar la tecla, porque la limpieza o la palabra de envío pueden cambiarla.
- Las teclas (Retroceso, Enter, Shift+Insert) salen de un teclado virtual uinput. El texto pasa por el portapapeles y Shift+Insert, porque es la única forma de que los acentos y la ñ salgan bien con cualquier distribución de teclado. Al terminar se restaura tu portapapeles.

## Pruebas

```sh
.venv/bin/python -m pytest -q
.venv/bin/python -m labia --simulate audio.wav   # 16 kHz mono; muestra cada pasada como si fuera en vivo
```
