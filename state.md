# Labia · state

Última actualización: 2026-11-08

| Fase | Estado |
|---|---|
| Propuesta | ✅ aprobada |
| 1. Núcleo puro y pruebas | ✅ 21 pruebas |
| 2. Transcriber + `--transcribe` | ✅ probado con las 7 grabaciones |
| 3. Flujo completo | ✅ probado por el usuario con el atajo real |
| 4. Menú, ajustes, bienvenida | ✅ revisado con capturas |
| 5. Empaque, README, CI, release | ✅ v0.1.0 |
| 6. Palabra de envío «Claude» | ✅ v0.2.0 |
| 7. Versión Linux (`linux/`, ver `linux/state.md`) | ✅ v0.3.0 |

## Hallazgos

- WhisperKit 0.18 (repo `WhisperKit`) devolvía texto vacío con `promptTokens`; `argmax-oss-swift` 1.1.1 lo corrige.
- Decodificador en GPU: 11 s por frase. Se queda en Neural Engine.
- Costo del vocabulario: ~25 ms por token (A/B repetido: 1.5 s sin vocabulario, 3.1 s con 19 palabras). La lista inicial bajó a 9 palabras.
- La primera carga del modelo en una app nueva tarda ~190 s (especialización para el chip); después 3–7 s.
- `Settings` choca con la escena de SwiftUI: el tipo del núcleo se llama `Preferences`.
