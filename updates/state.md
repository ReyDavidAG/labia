# Actualizaciones automáticas · state

Última actualización: 2026-11-08

| # | Fase | Estado |
|---|---|---|
| 1 | Plan y state | ✅ `updates/plan.md`, con las decisiones del usuario |
| 2 | CI: pruebas de Python en Windows y Linux | ✅ trabajo `python` en `ci.yml` (Windows y Ubuntu) |
| 3 | `updater.py` y sus pruebas | ✅ 10 pruebas con repos de git reales |
| 4 | Ayudante `update.py` + integración en Windows | ✅ probado de punta a punta (abajo) |
| 5 | Linux | ⏳ código listo (`systemd-run`, `notify-send`), falta probarlo en la laptop con Linux |
| 6 | Certificado propio y firma en el CI | ⏳ necesita la Mac |
| 7 | Sparkle en la app de macOS | ⏳ necesita la Mac |
| 8 | `release.yml`, canal Desarrollo, `RELEASING.md` | ⏳ |
| 9 | Release 1.1.0 e instalarla a mano una vez | ⏳ |
| 10 | Prueba de punta a punta con 1.1.1 | ⏳ |

Pruebas: 36 pasan, 1 saltada (evdev). `python -m pytest -q` en `linux/`.

## Prueba de punta a punta en Windows (2026-11-08)

Un «GitHub» local (repo bare con `main` = esta rama, etiquetada v1.1.0) e instalación real con `setup.ps1 -Repo <bare> -Destino <carpeta>`. Cada versión se publicó con un commit + tag en el bare y se pidió «Buscar actualizaciones» por mensaje al ícono:

| Versión publicada | Qué cambiaba | Resultado |
|---|---|---|
| 1.1.1 | `linux/labia/` | ✅ se cerró, el ayudante avanzó y la nueva estuvo lista en 3 s |
| 1.1.2 | el arreglo del aviso (abajo) | ✅ la 1.1.1 se actualizó con su ayudante viejo; el aviso no se mostró (esperado, ver hallazgos) |
| 1.1.3 | sólo `Sources/` (macOS) | ✅ la copia avanzó **sin reiniciar** Labia (mismos procesos) |
| 1.1.4 | `linux/labia/` | ✅ actualizada en 3 s y el aviso «Labia se actualizó» se mostró |
| 1.1.5 | `app.py` que truena al importar | ✅ el ayudante vio que salió (código 1), regresó a la 1.1.4 en 1 s, la reabrió y se mostró «No se pudo actualizar» |

Después se desinstaló con `setup.ps1 -Desinstalar` y se dejó la Labia de desarrollo como estaba.

## Hallazgos

- **El aviso se perdía**: el ayudante lo escribía después de ver que la nueva estaba lista, y para entonces la nueva ya había revisado si había aviso. Ahora lo deja antes de abrirla, con el commit al que se actualizó; la nueva sólo lo muestra si es ese commit.
- **Una versión rota se reintentaría cada 6 h.** El ayudante guarda `failed_target` y la revisión automática la salta; «Buscar actualizaciones» o una versión más nueva sí la intentan.
- **`git describe` dice «0.1.0+68» en develop**: con git flow el tag queda en el merge de `main`, que develop nunca contiene (develop une la rama de release). `describe()` también acepta el segundo padre del merge (la rama de release).
- **En Linux, importar `sounddevice` inicia PortAudio** y sin servidor de audio falla (lo destapó el CI de Ubuntu). `audio.py` ya lo importa al usarlo; `app.py` lo sigue importando al inicio, que está bien porque sin audio no hay dictado.
- Una copia de desarrollo (esta, en OneDrive, rama `feature/auto-update`) queda bloqueada: «Copia de desarrollo (rama …): no se actualiza sola».
- `update.json` (estado, `ready`, aviso) y `update.log` viven en `%APPDATA%\Labia`.

## Para la sesión en la Mac (fases 6 y 7)

1. Crear el certificado: Acceso a Llaveros → Asistente de certificados → Crear un certificado → nombre «Labia», tipo «Firma de código». Exportarlo como `.p12` con contraseña.
2. Subir los secretos: `base64 -i Labia.p12 | gh secret set MAC_CERT_P12` y `gh secret set MAC_CERT_PASSWORD`.
3. Firmar dos compilaciones seguidas con `LABIA_SIGN_IDENTITY=Labia scripts/bundle.sh` y comprobar que Accesibilidad no se pierde entre ellas.
4. Sparkle: `generate_keys` (guarda la privada en el llavero), `gh secret set SPARKLE_ED_PRIVATE_KEY`, la pública en `Resources/Info.plist`.

## Para la laptop con Linux (fase 5)

1. `git switch feature/auto-update` en `~/labia`, `systemctl --user restart labia`.
2. La copia de desarrollo dirá que no se actualiza sola. Para probar de verdad, una instalación limpia aparte con un repo bare como en la prueba de Windows, y comprobar: `systemd-run` saca al ayudante del servicio, `systemctl --user restart labia` levanta la nueva, `notify-send` muestra el aviso y una versión rota regresa a la anterior.

## Ideas

- Avisar antes de una actualización que baja dependencias pesadas (cambia `requirements.txt`).
- Mostrar en Ajustes las notas de la versión nueva (el release de GitHub).
