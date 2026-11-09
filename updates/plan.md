# Actualizaciones automáticas · plan

Rama `feature/auto-update`, sale de `develop` después de la 1.0.0.

## Meta

Que Labia se mantenga al día sola en macOS, Windows y Linux a partir del repositorio público `github.com/ReyDavidAG/labia`, sin que nadie tenga que reinstalar. Una versión que sólo cambia Windows no reinicia la Mac, y al revés. Publicar una corrección (1.0.1, 1.1.0…) debe ser barato, porque no sabemos quién más la usa.

## Decisiones del usuario (2026-11-08)

| Tema | Decisión |
|---|---|
| Firma en macOS | **Certificado propio** (gratis) guardado en los secretos de GitHub. El CI firma siempre con él para que macOS conserve el permiso de Accesibilidad entre versiones |
| Al haber versión nueva | **Se actualiza sola, sin preguntar**: baja en segundo plano, espera a que no estés dictando, se reinicia y avisa. Se puede apagar en Ajustes |
| Canal | **Estable** por defecto (sólo releases publicados, lo que llega a `main`). **Desarrollo** opcional en Ajustes: sigue `develop`, pensado para el autor |

## Cómo se instala hoy y qué implica

| Plataforma | Instalación | Cómo se actualiza |
|---|---|---|
| Windows | `windows/setup.ps1`: copia de git en `%LOCALAPPDATA%\Programs\Labia` + `.venv` | Con git: avanzar la copia al tag nuevo, `pip install` si cambió `requirements.txt`, reiniciar |
| Linux | Copia de git en `~/labia` + `.venv` + servicio `labia.service` de systemd | Igual que Windows; reinicia con `systemctl --user restart labia` |
| macOS | `Labia.app` del `.zip` de cada release, firma ad hoc | **Sparkle 2**: el estándar en macOS. Baja el `.zip`, verifica su firma EdDSA, reemplaza la app y la reabre |

La 1.0.0 no trae actualizador: hay que instalar a mano, una sola vez, la primera versión que lo traiga (1.1.0). En Windows basta con volver a correr el comando de `setup.ps1`.

## Decisiones técnicas

| Tema | Decisión | Por qué |
|---|---|---|
| Qué es una versión | Un tag `vX.Y.Z` en `main` con su release en GitHub. Semver: corrección = parche (1.0.1), función nueva = menor (1.1.0) | Ya es el flujo de git flow del repo; `main` sólo cambia con releases |
| Canal Estable (Windows/Linux) | El tag `vX.Y.Z` más alto que esté en `origin/main` | Git ya está instalado (lo pide `setup.ps1`); sin API de GitHub ni límite de consultas |
| Canal Desarrollo (Windows/Linux) | La punta de `origin/develop` | Es lo que el autor ya prueba |
| «Sólo si me afecta» (Windows/Linux) | `git diff --name-only actual..nueva`: si no cambió nada de `linux/` ni `windows/`, la copia avanza en silencio, sin reiniciar ni avisar | El código que corre es idéntico: reiniciar sería ruido |
| «Sólo si me afecta» (macOS) | El CI sólo agrega la versión al feed de Sparkle (`appcast.xml`) si cambió algo de la app (`Sources/`, `Resources/`, `Package.*`, `scripts/bundle.sh`). Si no, el feed repite la última versión de Mac | Una versión sólo de Windows no debe reinstalar la Mac |
| Feed de Sparkle | Estable: `releases/latest/download/appcast.xml` (cada release lo sube). Desarrollo: release preliminar `desarrollo` que el CI rehace en cada push a `develop` que toque la Mac | URL fija sin servidor propio; GitHub sirve los archivos |
| Firma de las actualizaciones (macOS) | EdDSA de Sparkle: llave privada en el secreto `SPARKLE_ED_PRIVATE_KEY`, pública en `Info.plist` (`SUPublicEDKey`) | Aunque alguien suba un `.zip` falso, Sparkle no lo instala |
| Certificado propio (macOS) | Certificado de firma de código autofirmado «Labia», creado una vez en la Mac. `.p12` en base64 en `MAC_CERT_P12` + `MAC_CERT_PASSWORD`. El CI lo importa a un llavero temporal y exporta `LABIA_SIGN_IDENTITY` para `bundle.sh` | macOS liga el permiso de Accesibilidad al certificado, no a cada compilación |
| Cuándo se instala | Busca 2 min después de abrir y luego cada 6 h. Aplica cuando no hay dictado en curso y pasó al menos 1 min desde el último | Nunca cortar un dictado |
| Aplicar en Windows | Labia lanza `python -m labia.update --aplicar <destino>` y sale. El ayudante espera a que se libere el mutex, avanza la copia, corre `pip` si hace falta y reabre Labia con `--actualizada <anterior>` | Windows no deja reemplazar DLL en uso: `pip` no puede correr con Labia abierta |
| Aplicar en Linux | El ayudante corre fuera del servicio (`systemd-run --user`) y termina con `systemctl --user restart labia` | Si corre dentro del servicio, el reinicio lo mata a la mitad |
| Si sale mal | El ayudante guarda la versión anterior. Si `git`, `pip` o el arranque fallan (Labia no muestra su ícono o no dice «Lista» en 3 min), regresa a la anterior, la reabre y avisa | Una versión rota no debe dejar a nadie sin dictado |
| Copias de desarrollo | Sólo se actualiza sola una copia limpia (`git status` vacío), en `main` (Estable) o `develop` (Desarrollo) y sin commits propios. Si no, Ajustes dice «Copia de desarrollo: no se actualiza sola» | Nunca tocar el trabajo de quien programa (como la copia en OneDrive) |
| Avisos | Windows: notificación del ícono («Labia se actualizó a 1.0.1»). Linux: `notify-send`. macOS: la de Sparkle | Que se note que cambió |
| Ajustes | General: «Actualizar automáticamente» (activado) y «Canal: Estable / Desarrollo». Modelo → «Versión 1.0.1 (a1b2c3d)» y «Buscar actualizaciones». Menú del ícono: «Buscar actualizaciones» | Igual en las tres plataformas |
| Privacidad | Sólo se consulta `github.com/ReyDavidAG/labia`. Nada de estadísticas ni de identificar equipos | Labia promete que todo queda local |

## Publicar una versión (para que sea barato)

Un workflow nuevo `release.yml` corre al subir un tag `vX.Y.Z`:

1. Pruebas: `swift test` en macOS y `pytest` en Windows y Linux (hoy el CI sólo prueba macOS).
2. Compila `Labia.app` firmado con el certificado, arma el `.zip` y lo firma para Sparkle.
3. Genera `appcast.xml` (con la versión nueva de Mac o la anterior si no cambió) y `SHA256SUMS`.
4. Crea el release en GitHub con las notas de esa sección del `CHANGELOG.md` y lo marca como «Latest».

Con eso publicar es: rama `release/X.Y.Z` o `hotfix/X.Y.Z`, fecha en el CHANGELOG, merge a `main`, tag y push. Se documenta en `RELEASING.md`.

## Módulos

- `linux/labia/updater.py` (puro, con pruebas sobre repos de git temporales): estado de la copia, elegir el destino según el canal, ¿afecta a esta plataforma?, ¿se puede actualizar sola?
- `linux/labia/update.py`: el ayudante `--aplicar` (esperar, avanzar, `pip`, reabrir, regresar si falla).
- `app.py`: revisión periódica, aplicar sólo en reposo, aviso al arrancar con `--actualizada`.
- `tray_windows.py` / `settings_windows.py`: «Buscar actualizaciones», versión, canal, interruptor.
- `core.Preferences`: `auto_update` (bool) y `update_channel` («estable» / «desarrollo»).
- macOS: `Updater.swift` con Sparkle (`SPUStandardUpdaterController`), delegado que instala sólo en reposo, ajustes y menú.
- CI: `ci.yml` (pruebas de Python), `release.yml`, `dev-build.yml` (release preliminar `desarrollo`).

## Fases

| # | Fase | Dónde |
|---|---|---|
| 1 | Plan y state | Windows ✍️ |
| 2 | CI: pruebas de Python en Windows y Linux | Windows |
| 3 | `updater.py` y sus pruebas | Windows |
| 4 | Ayudante `update.py` con regreso a la versión anterior + integración en Windows (ícono, ajustes, aviso) | Windows |
| 5 | Linux: `systemd-run`, `notify-send`; probar en la laptop con Linux | Linux |
| 6 | Certificado propio en la Mac, secretos en GitHub, firma en el CI; comprobar que Accesibilidad sobrevive a dos compilaciones | Mac |
| 7 | Sparkle en la app, llaves EdDSA, `appcast.xml` en el CI, instalar en reposo, ajustes | Mac |
| 8 | `release.yml`, canal Desarrollo (`dev-build.yml`), `RELEASING.md` | Windows + Mac |
| 9 | Release 1.1.0 (la primera que se actualiza sola) e instalarla a mano una vez en cada equipo | Las tres |
| 10 | Prueba de punta a punta: publicar 1.1.1 sólo con un cambio de Windows y ver que Windows se actualiza y la Mac no | Las tres |

## Riesgos

- **El primer cambio de firma en la Mac** (de ad hoc a certificado) pide Accesibilidad una vez más. Después ya no.
- **Primera instalación en Mac**: sigue haciendo falta el `xattr` o clic derecho → Abrir, porque el certificado propio no está notarizado por Apple. Con Developer ID (99 USD/año) desaparecería; se puede cambiar después sin rehacer nada.
- **Sparkle con certificado propio**: Sparkle revisa la firma EdDSA y también compara la firma de código de la versión nueva con la instalada. Sin verificar todavía: que acepte el paso de ad hoc (1.1.0 instalada a mano) a certificado propio y las versiones siguientes. Comprobarlo en la fase 7 antes de publicar.
- **Dependencias pesadas**: si cambia `requirements.txt` (CUDA), la actualización baja cientos de MB. Se avisa antes de reiniciar y se hace en reposo.

## Fuera de este plan

- Notarizar con Apple (requiere Developer ID).
- Actualizaciones delta (sólo lo que cambió del `.app`).
- Paquetes de distribuciones de Linux (AUR, Flatpak).
