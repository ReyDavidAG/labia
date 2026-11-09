# Cambios

## 0.5.0 · sin publicar

- macOS: los dictados de más de 30 s se cortan en las pausas y cada tramo se transcribe por separado. Antes, en dictados de más de un minuto sólo llegaban las primeras frases.

## 0.4.0 · 2026-11-08

Primera versión para Windows 11, en [`windows/`](windows/README.md): el mismo paquete de Python de Linux con atajo, escritura y cápsula propios de Windows.

- Escribe en tiempo real y se corrige sola, como en Linux.
- Se dicta manteniendo AltGr (Alt derecho), con un gancho de teclado de bajo nivel.
- La cápsula flotante no quita el foco y deja pasar los clics.
- Corregido: en un dictado largo, la corrección final podía borrar lo escrito y pegar el portapapeles anterior. Windows ahora espera a que la app lea cada pegado; macOS restaura el portapapeles y da Enter cuando la app ya leyó; Linux espera 0.6 s antes de restaurar.

## 0.3.0 · 2026-11-08

Primera versión para Linux, en [`linux/`](linux/README.md) (KDE Plasma en Wayland, GPU NVIDIA).

- Escribe en tiempo real: las palabras aparecen mientras hablas.
- Se corrige solo: cada 3 s, una pasada cuidadosa reescribe lo que ya escribió.
- La pasada final cubre toda la grabación con detector de voz. Sin voz no escribe nada.
- La cápsula flotante de macOS, con el volumen real del micrófono y los mismos estados.
- Alt derecho solo sirve para dictar, y AltGr con otra tecla sigue funcionando.

## 0.2.0 · 2026-11-05

- Palabra de envío: terminar el dictado con «Claude» pega el texto y presiona Enter. Dicha sola envía lo que ya estaba escrito. Configurable en Ajustes › General.
- `Labia --login-item on|off` activa o quita el arranque al iniciar sesión desde Terminal.

## 0.1.0 · 2026-11-04

Primera versión.

- Dictado con ⌥ derecho: mantener, doble toque para manos libres, esc para cancelar.
- Whisper large-v3-turbo local vía WhisperKit, con vocabulario propio.
- Corrección segura con el vocabulario, reemplazos y filtro de alucinaciones de silencio.
- Cápsula flotante con el volumen real del micrófono y sus estados.
- Pegado automático que restaura el portapapeles.
- Menú en la barra, ajustes, historial local y ventana de bienvenida.
