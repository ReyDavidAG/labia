# Labia · state

Última actualización: 2026-11-04

| Fase | Estado |
|---|---|
| Propuesta | ✅ aprobada |
| 1. Núcleo puro y pruebas | ✅ 21 pruebas |
| 2. Transcriber + `--transcribe` | ✅ probado con las 7 grabaciones |
| 3. Flujo completo | ✅ compila y arranca; falta prueba real con el atajo |
| 4. Menú, ajustes, bienvenida | ✅ compila; falta revisión visual |
| 5. Empaque, README, CI, release | ⏳ bundle y README listos; repo y release pendientes |

## Hallazgos

- WhisperKit 0.18 (repo `WhisperKit`) devolvía texto vacío con `promptTokens`; `argmax-oss-swift` 1.1.1 lo corrige.
- Decodificador en GPU: 11 s por frase. Se queda en Neural Engine.
- Costo del vocabulario: ~22 ms por token. Sin vocabulario 1.1 s; con 18 palabras 1.4 s y 0 errores.
- La primera carga del modelo en una app nueva tarda ~190 s (especialización para el chip); después 3–7 s.
- `Settings` choca con la escena de SwiftUI: el tipo del núcleo se llama `Preferences`.
