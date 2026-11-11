# Labia · plan

Dictado en español para macOS: mantienes ⌥ derecho, hablas, sueltas y el texto se pega donde está el cursor. Todo local con Whisper large-v3-turbo (WhisperKit) y un vocabulario propio para el spanglish de desarrollo.

Propuesta aprobada: `propuesta/index.html` (publicada como artifact).

## Decisiones

| Tema | Decisión | Por qué |
|---|---|---|
| Motor | WhisperKit, `large-v3-v20240930_turbo` | En la prueba del 2026-11-04 tuvo 0 términos mal escritos con vocabulario (Apple 15, Parakeet 9) |
| Vocabulario | `promptTokens` de Whisper | Sin él, 5 errores; con él, 0 |
| Atajo | ⌥ derecho; mantener, doble toque = manos libres, esc cancela | fn lo usa macOS; ⌥ solo no escribe nada |
| Enter | Sólo si la última palabra dictada es la palabra de envío («Claude», con sus variantes `cloud` y `clod`); se quita del texto | El usuario lo pidió para dictarle a Claude Code sin tocar el teclado; «Claude» no aparece al final de un prompt por accidente |
| Captura de teclas | `CGEventTap` activo | Necesario para tragarse esc mientras graba; usa el mismo permiso de Accesibilidad que el pegado |
| Pegado | Portapapeles + ⌘V simulado, luego restaura | Funciona en Terminal, navegador y apps nativas |
| Empaque | SwiftPM + `scripts/bundle.sh` arma `Labia.app` | Sin proyecto de Xcode que mantener a mano |
| Firma | Ad hoc en releases; identidad local estable en desarrollo | Los permisos de macOS se amarran a la firma |
| Plataforma | macOS 14+, Apple Silicon | Requisito de WhisperKit con Neural Engine |

## Módulos

- `LabiaCore` (puro, con pruebas): `GestureMachine` (mantener / doble toque / corto / esc / acorde), `TextCleaner` (reemplazos, alucinaciones de silencio, espacios), `Settings` codificables, `HistoryStore`.
- `Labia` (app): `HotkeyTap`, `Recorder`, `Transcriber`, `Paster`, `Overlay` + `PillView`, `MenuContent`, `SettingsView`, `OnboardingView`, `AppModel`.

## Fases

1. Núcleo puro y sus pruebas.
2. Transcriber con modo `--transcribe archivo.wav` para probar sin micrófono.
3. Atajo, grabación, pegado y cápsula: el flujo completo.
4. Menú, ajustes, historial, bienvenida y arranque al iniciar sesión.
5. Ícono, `bundle.sh`, README (es/en), CI, release v0.1.0.

## Fuera de v0.1

Streaming, Parakeet, vocabulario por app, comandos de voz, cask de Homebrew, notarización.

## Palabra de envío (2026-11-05)

Rama `feature/send-keyword`.

- `SendKeyword.split` en `LabiaCore`: compara la última palabra sin mayúsculas, acentos ni puntuación; quita también la coma o el signo que la precede.
- Decir sólo la palabra presiona Enter sin pegar nada: envía lo que ya estaba escrito.
- `Paster.paste(…, thenReturn:)` presiona Return 150 ms después de ⌘V; la terminal descarta el Enter si llega mientras procesa el pegado.
- Con envío no se agrega el espacio final. Sin pegado automático o sin Accesibilidad nunca envía.
- Ajustes › General: interruptor y la lista de palabras separadas por comas. Activo por defecto.

## Labia 2.0 en macOS: diseño nuevo y ventanas que responden (2026-11-10)

Rama `feature/mac-app-redesign`. Propuesta aprobada por el usuario en su totalidad: `propuesta/v2/index.html`.

Problema de fondo: las ventanas no recibían clics ni teclas. Se pensó que era por ser app sólo de barra de menú (`LSUIElement`) en macOS 26; la causa real fue el monitor global de clics instalado antes de `NSApplication` (ver `state.md`). `AppWindows` se queda para que la app aparezca en el Dock y en ⌘⇥ con una ventana abierta.

Pasos, cada uno se prueba solo antes del siguiente:

1. **Ventanas que responden.** `AppWindows`: con la bienvenida o Ajustes abiertos, política de activación `.regular` (Dock, ⌘⇥, foco y clics); al cerrar la última, `.accessory`. Prueba: la ventana queda al frente y como app activa.
2. **Marca.** `Theme`: violeta `#7560f3 → #3e2ccc`, lima `#dcff5f`, índigo `#21106a`; mosaicos de icono por sección y la burbuja con la onda.
3. **Bienvenida en cinco pasos.** Marca a la izquierda, un paso a la vez: cómo se usa, micrófono, Accesibilidad, modelo, prueba. Arranca en el primer paso pendiente.
4. **Ajustes con barra lateral.** Ventana propia (`NavigationSplitView`): Resumen, Atajo y escritura, Vocabulario (medidor de costo), Reemplazos (tabla), Historial (búsqueda), Modelo, Permisos, Actualizaciones. ⌘, la abre.
5. **Menú de la barra.** Estado con el icono, último dictado para copiar, Historial, Pausar, Ajustes, Actualizaciones, Salir.
6. **Capturas, README y release 2.0.0** por git flow.

Los contadores del Resumen salen del historial real (últimos 50), sin números inventados.
