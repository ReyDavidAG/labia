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
| 9. Ícono 1.0 «Dicho y escrito» (`propuesta/logos.html`) | ✅ regenerado en la Mac con los 10 tamaños |
| 10. Windows como app: menú Inicio, ícono junto al reloj, ajustes (`windows/app/`) | ✅ v1.0.0; ver `windows/app/state.md` |
| 11. Tiempo real en macOS | ✅ simulación con el modelo real y prueba en vivo del usuario en Claude Code (2026-11-08) |
| 12. Release 1.0.0 | ✅ v1.0.0, con las pruebas manuales de «Antes de la 1.0» hechas por el usuario |

## Antes de la 1.0 (pruebas manuales) · ✅ probadas por el usuario el 2026-11-08

Windows (`windows/app/state.md`, «Lo que falta probar»):

1. Clic derecho en el ícono junto al reloj: el menú se cierra al hacer clic afuera.
2. Pausar: el tooltip dice «En pausa», AltGr no graba y AltGr+Q sigue dando @. Reanudar y dictar.
3. Salir desde el menú a mitad de un dictado largo: termina de escribir y no deja Ctrl presionado.

macOS (desde `release/1.0.0`: `swift test && scripts/bundle.sh && open build/Labia.app`):

4. Dictar en VS Code y en el navegador.
5. Esc a media frase: borra lo que ya había escrito.
6. Un dictado de más de 1 minuto: llega completo.

Si algo falla, el arreglo va en `release/1.0.0` (o en un `fix/*` que salga de ahí) antes de unir a `main`.

## Para probar en macOS (desde `develop`)

1. `swift test && scripts/bundle.sh && open build/Labia.app`: el ícono nuevo en el Dock, Finder y Ajustes del Sistema. El `.icns` se generó en Windows desde el SVG; si algo se ve mal, `scripts/make-icon.sh` lo regenera con `icon.swift` (el CI ya comprobó que ese script dibuja el mismo diseño).
2. Pegado con «Restaurar portapapeles» activo: copia algo, dicta y revisa que el texto quede pegado y luego regrese lo que habías copiado. Ahora se restaura cuando la app lee el pegado (datos diferidos de `NSPasteboard`), no a los 600 ms fijos.
3. Terminar con «Claude» en la terminal: el Enter llega después del pegado.
4. Con «Restaurar portapapeles» apagado, el texto dictado se queda en el portapapeles aunque cierres Labia.
5. Pendiente aparte: `feature/mac-long-audio` (dictados de más de 30 s), ver «Pendientes» en `windows/plan.md`.

## Tiempo real en macOS (2026-11-08)

- `LiveSession` (LabiaCore) es el port de `linux/labia/stream.py` con las mismas pruebas; `LiveDictation` (app) es el `Dictation` de `app.py` y escribe como `typer_windows.py`: retrocesos, pegados de ≤400 caracteres que esperan a que la app lea (datos diferidos) y los espacios del final como teclas.
- Pasadas sin prompt (bucles en audio corto); la rápida sin fallback de temperatura y la cuidadosa con 5. La pasada final es la de siempre: vocabulario como prompt + cortes en pausas.
- Medido con `Labia --simulate` en la M2 (voz de `say -v Paulina`, 4 s y 44 s): mediana 0.66–0.74 s por pasada, máximo 1.13 s; el texto va 1–2 s detrás de la voz.
- Las teclas que manda Labia llevan `eventSourceUserData` = `Paster.syntheticMark`: sin eso el atajo las tomaba como «⌥ + otra tecla» y cancelaba el dictado. Salen de una fuente `.privateState` para que no se les sume el ⌥ que se está manteniendo.
- La pasada cuidadosa no cambia palabras que sólo difieren en mayúsculas: «Revisa» → «revisa» borraba y reescribía todo lo que seguía.
- Con silencio, la pasada se salta si la anterior no cambió nada y no quedan palabras por confirmar (`LocalAgreement.pending`): en una pausa de 4 s se ahorran 4 de 8 pasadas y nada se escribe más tarde.
- Probado en vivo por el usuario dictando en Claude Code: funciona. Falta revisar VS Code y el navegador, esc a media frase y un dictado de más de 1 min.

## Hallazgos

- WhisperKit 0.18 (repo `WhisperKit`) devolvía texto vacío con `promptTokens`; `argmax-oss-swift` 1.1.1 lo corrige.
- Decodificador en GPU: 11 s por frase. Se queda en Neural Engine.
- Costo del vocabulario: ~25 ms por token (A/B repetido: 1.5 s sin vocabulario, 3.1 s con 19 palabras). La lista inicial bajó a 9 palabras.
- La primera carga del modelo en una app nueva tarda ~190 s (especialización para el chip); después 3–7 s.
- `Settings` choca con la escena de SwiftUI: el tipo del núcleo se llama `Preferences`.
