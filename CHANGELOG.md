# Cambios

## 0.3.1 · sin publicar

- macOS: los dictados de más de 30 s se cortan en las pausas y cada tramo se transcribe por separado. Antes, en dictados de más de un minuto sólo llegaban las primeras frases.

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
