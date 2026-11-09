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
| 8. Versión Windows (`windows/`, ver `windows/state.md`) | ✅ v0.4.0 |
| 9. Ícono 1.0 «Dicho y escrito» (`propuesta/logos.html`) | 🧪 en `develop`; falta verlo en una Mac |
| 10. Windows como app: menú Inicio, ícono junto al reloj, ajustes (`windows/app/`) | 🧪 en `feature/windows-app`; ver `windows/app/state.md` |

## Para probar en macOS (desde `develop`)

1. `swift test && scripts/bundle.sh && open build/Labia.app`: el ícono nuevo en el Dock, Finder y Ajustes del Sistema. El `.icns` se generó en Windows desde el SVG; si algo se ve mal, `scripts/make-icon.sh` lo regenera con `icon.swift` (el CI ya comprobó que ese script dibuja el mismo diseño).
2. Pegado con «Restaurar portapapeles» activo: copia algo, dicta y revisa que el texto quede pegado y luego regrese lo que habías copiado. Ahora se restaura cuando la app lee el pegado (datos diferidos de `NSPasteboard`), no a los 600 ms fijos.
3. Terminar con «Claude» en la terminal: el Enter llega después del pegado.
4. Con «Restaurar portapapeles» apagado, el texto dictado se queda en el portapapeles aunque cierres Labia.
5. Pendiente aparte: `feature/mac-long-audio` (dictados de más de 30 s), ver «Pendientes» en `windows/plan.md`.

## Hallazgos

- WhisperKit 0.18 (repo `WhisperKit`) devolvía texto vacío con `promptTokens`; `argmax-oss-swift` 1.1.1 lo corrige.
- Decodificador en GPU: 11 s por frase. Se queda en Neural Engine.
- Costo del vocabulario: ~25 ms por token (A/B repetido: 1.5 s sin vocabulario, 3.1 s con 19 palabras). La lista inicial bajó a 9 palabras.
- La primera carga del modelo en una app nueva tarda ~190 s (especialización para el chip); después 3–7 s.
- `Settings` choca con la escena de SwiftUI: el tipo del núcleo se llama `Preferences`.
