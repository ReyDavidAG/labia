# Cambios

## 1.0.0 · 2026-11-08

Primera versión estable: en macOS, Linux y Windows Labia escribe en tiempo real mientras hablas y se corrige sola. En macOS y Windows se instala y se usa como una app, con ajustes e historial. Estrena el ícono «Dicho y escrito».

### macOS

- Escribe en tiempo real, como Linux y Windows: las palabras aparecen mientras hablas, una pasada cuidadosa cada 3 s corrige lo ya escrito y al soltar la pasada final con tu vocabulario deja el texto definitivo. En una M2 cada pasada tarda unos 0.7 s. Se apaga en Ajustes › General › «Escribir mientras hablas».
- Esc borra lo que el dictado en vivo ya había escrito.
- En las pausas no gasta el Neural Engine: si sólo llega silencio y no hay nada por confirmar, se salta la pasada.
- Los dictados de más de 30 s se cortan en las pausas y cada tramo se transcribe por separado. Antes, en dictados de más de un minuto sólo llegaban las primeras frases.
- Ícono nuevo «Dicho y escrito», regenerado en la Mac con todos los tamaños.

### Windows

Labia en Windows ya es una app ([`windows/app/plan.md`](windows/app/plan.md)).

- Se instala con un solo comando de PowerShell (`windows/setup.ps1`): Git y Python si faltan, dependencias, modelo, menú Inicio e inicio de sesión. Correrlo otra vez la actualiza; `-Desinstalar` la quita.
- Aparece al buscar «Labia» en el menú Inicio, con el ícono «Dicho y escrito». `windows\install.ps1` crea los accesos directos.
- Ícono junto al reloj con su estado y un menú: Ajustes, Historial, Pausar, Reiniciar y Salir.
- Ventana de ajustes con las pestañas de macOS: General, Vocabulario, Reemplazos, Historial y Modelo. Los cambios se usan desde el siguiente dictado.
- Se elige el micrófono, y se busca en cada dictado: el que conectes con Labia abierta también sirve. Si no está, usa el predeterminado.
- Nunca corren dos Labias: abrirla otra vez muestra los ajustes de la que ya corre.
- Corregido: si el micrófono no abría, la cápsula se quedaba en «escuchando» para siempre. Ahora muestra el error.
- Corregido: los ajustes y el historial se guardaban con la codificación de Windows, y un emoji o «→» los rompía. Ahora van en UTF-8; los archivos anteriores se siguen leyendo.

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
