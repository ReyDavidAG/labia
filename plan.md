# Labia · plan

Dictado en español para macOS: mantienes ⌥ derecho, hablas, sueltas y el texto se pega donde está el cursor. Todo local con Whisper large-v3-turbo (WhisperKit) y un vocabulario propio para el spanglish de desarrollo.

Propuesta aprobada: `propuesta/index.html` (publicada como artifact).

## Decisiones

| Tema | Decisión | Por qué |
|---|---|---|
| Motor | WhisperKit, `large-v3-v20240930_turbo` | En la prueba del 2026-11-04 tuvo 0 términos mal escritos con vocabulario (Apple 15, Parakeet 9) |
| Vocabulario | `promptTokens` de Whisper | Sin él, 5 errores; con él, 0 |
| Atajo | ⌥ derecho; mantener, doble toque = manos libres, esc cancela | fn lo usa macOS; ⌥ solo no escribe nada |
| Enter | Nunca se envía solo | El usuario revisa antes de mandar |
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
