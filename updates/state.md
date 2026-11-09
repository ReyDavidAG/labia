# Actualizaciones automáticas · state

Última actualización: 2026-11-08

| # | Fase | Estado |
|---|---|---|
| 1 | Plan y state | ✅ `updates/plan.md`, con las decisiones del usuario |
| 2 | CI: pruebas de Python en Windows y Linux | ⏳ |
| 3 | `updater.py` y sus pruebas | ⏳ |
| 4 | Ayudante `update.py` + integración en Windows | ⏳ |
| 5 | Linux | ⏳ necesita la laptop con Linux |
| 6 | Certificado propio y firma en el CI | ⏳ necesita la Mac |
| 7 | Sparkle en la app de macOS | ⏳ necesita la Mac |
| 8 | `release.yml`, canal Desarrollo, `RELEASING.md` | ⏳ |
| 9 | Release 1.1.0 e instalarla a mano una vez | ⏳ |
| 10 | Prueba de punta a punta con 1.1.1 | ⏳ |

## Punto de partida (1.0.0)

- Windows: `setup.ps1` deja una copia de git de `main` en `%LOCALAPPDATA%\Programs\Labia`. Volver a correrlo ya actualiza, pero a mano.
- Linux: copia de git en `~/labia` con `labia.service`.
- macOS: `Labia-1.0.0.zip` del release, firma ad hoc (`bundle.sh`, `LABIA_SIGN_IDENTITY` vacía = `-`). El CI arma el `.zip` en cada push a `main` y `develop`, pero el release se crea a mano con `gh release create`.
- El CI (`ci.yml`) sólo corre `swift test`: las pruebas de Python no corren en GitHub.

## Para la sesión en la Mac (fases 6 y 7)

1. Crear el certificado: Acceso a Llaveros → Asistente de certificados → Crear un certificado → nombre «Labia», tipo «Firma de código». Exportarlo como `.p12` con contraseña.
2. Subir los secretos: `base64 -i Labia.p12 | gh secret set MAC_CERT_P12` y `gh secret set MAC_CERT_PASSWORD`.
3. Firmar dos compilaciones seguidas con `LABIA_SIGN_IDENTITY=Labia scripts/bundle.sh` y comprobar que Accesibilidad no se pierde entre ellas.
4. Sparkle: `generate_keys` (guarda la privada en el llavero), `gh secret set SPARKLE_ED_PRIVATE_KEY`, la pública en `Resources/Info.plist`.

## Hallazgos

## Ideas
