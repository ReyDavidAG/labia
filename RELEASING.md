# Publicar una versión

Labia sigue git flow: `main` sólo cambia con versiones y cada versión es un tag `vX.Y.Z`. Semver: una corrección es un parche (1.0.1), una función nueva es menor (1.1.0).

Al subir el tag, [`release.yml`](.github/workflows/release.yml) hace lo demás:

1. Corre las pruebas: `pytest` en Windows y Linux, `swift test` en macOS.
2. Arma `Labia.app` firmada con el certificado propio «Labia» y su `.zip`.
3. Genera `appcast.xml`, el feed de Sparkle, firmado con EdDSA. Si la app de Mac no cambió desde la versión que tenía el feed anterior (`Sources/`, `Resources/`, `Package.*`, `scripts/bundle.sh`), el feed sigue en esa versión: las Macs no se reinstalan por un cambio de Windows.
4. Crea el release con la sección del `CHANGELOG.md` como notas, sube el `.zip`, `appcast.xml` y `SHA256SUMS`, y lo marca como «Latest».

En cuanto el release existe, cada plataforma se actualiza sola en las siguientes horas: macOS con Sparkle desde `releases/latest/download/appcast.xml`, y Windows y Linux con git desde el tag.

## Pasos

```bash
git switch develop && git pull
git switch -c release/1.1.0
# CHANGELOG.md: «## Sin publicar» → «## 1.1.0 · AAAA-MM-DD»
git commit -am "Prepare release 1.1.0"
git switch main && git pull && git merge --no-ff release/1.1.0 -m "Release 1.1.0"
git tag v1.1.0 && git push origin main v1.1.0
git switch develop && git merge --no-ff release/1.1.0 && git push origin develop
git branch -d release/1.1.0
```

Una corrección urgente sale de `main` con `hotfix/1.1.1` y sigue los mismos pasos.

Si `release.yml` falla, el tag ya está en GitHub pero el release no: corrige, borra el tag (`git push origin :v1.1.0 && git tag -d v1.1.0`) y vuelve a etiquetar. Si el release ya existía (creado a mano), el workflow sólo le sube los archivos y actualiza las notas.

## Canal Desarrollo

[`dev-build.yml`](.github/workflows/dev-build.yml) rehace el release preliminar `desarrollo` con cada push a `develop` que cambie la app de Mac. Las Macs con el canal Desarrollo en Ajustes lo siguen; su versión se ve como `1.1.0-dev.a1b2c3d`. Windows y Linux en Desarrollo siguen la punta de `develop` con git.

## Secretos (una sola vez)

| Secreto | Qué es |
|---|---|
| `MAC_CERT_P12`, `MAC_CERT_PASSWORD` | El certificado propio «Labia» en base64 y su contraseña. macOS liga el permiso de Accesibilidad al certificado: si cambia, todos tienen que volver a darlo |
| `SPARKLE_ED_PRIVATE_KEY` | La llave privada EdDSA. Sin ella no se puede publicar una actualización que las Macs acepten. Su pública está en `Resources/SparklePublicKey` |

Se crean con `scripts/setup-signing.sh`, en la Mac del autor. El certificado y la llave quedan también en su llavero: ése es el respaldo. **No los pierdas**: con una llave de Sparkle nueva, las Macs instaladas ya no aceptarían actualizaciones y habría que reinstalar a mano.
