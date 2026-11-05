<p align="center"><img src="docs/icon.png" width="128" alt="Ícono de Labia"></p>

<h1 align="center">Labia</h1>

<p align="center"><b>Mantén ⌥ y habla. Suelta y se pega.</b><br>
Dictado en español para macOS, en cualquier app y sin internet.</p>

<p align="center"><a href="#english">English below</a></p>

<p align="center"><img src="docs/img/hero.png" alt="Un dictado pegado en Claude Code dentro de la terminal, con la cápsula de Labia diciendo Pegado · 20 palabras"></p>

---

Labia vive en la barra de menú. Mantienes **⌥ derecho**, dices lo que quieres escribir y al soltar el texto aparece donde está el cursor: la terminal, el navegador, Slack, VS Code o un chat con una IA.

- **Local.** Transcribe con [Whisper large-v3-turbo](https://huggingface.co/argmaxinc/whisperkit-coreml) vía [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) en el Neural Engine de tu Mac. El audio nunca sale de tu equipo ni se guarda en disco.
- **Entiende tu spanglish.** Le das tu vocabulario (`commit`, `pull request`, `useApiQuery`, `Vercel`) y lo escribe bien, con sus mayúsculas.
- **Envía sólo si se lo pides.** Termina el dictado diciendo «Claude» y Labia quita la palabra, pega y da Enter. Sin ella, sólo pega y tú revisas. Se apaga o se cambia la palabra en Ajustes.

## Gestos

| Gesto | Qué hace |
|---|---|
| Mantener ⌥ derecho | Graba mientras lo sostienes; al soltar transcribe y pega |
| Doble toque ⌥ | Manos libres: sigue grabando hasta el siguiente toque (máximo 5 min) |
| esc mientras grabas | Cancela sin transcribir |
| ⌥ + otra tecla | Se ignora: puedes seguir usando ⌥ para acentos y atajos |

Una cápsula abajo al centro de la pantalla te dice en qué va: escuchando (con el volumen real del micrófono), transcribiendo, pegado y cuántas palabras.

<p align="center"><img src="docs/img/states.png" alt="Estados de la cápsula: escuchando, manos libres, transcribiendo, pegado, sin voz y cancelado"></p>

## Instalar

Requiere macOS 14 o posterior y una Mac con Apple Silicon (M1 o más nueva).

1. Descarga `Labia-x.y.z.zip` de [Releases](../../releases) y mueve `Labia.app` a Aplicaciones.
2. La app no está notarizada por Apple. La primera vez ábrela con clic derecho → **Abrir**, o en Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Labia.app
   ```
3. La ventana de bienvenida te pide tres cosas:
   - **Micrófono**, para oírte.
   - **Accesibilidad**, para detectar el atajo en cualquier app y pegar con ⌘V.
   - **Descargar el modelo**: 1.5 GB, una sola vez. La primera carga tarda alrededor de un minuto mientras macOS lo prepara para tu chip.

<p align="center"><img src="docs/img/welcome.png" width="420" alt="Ventana de bienvenida con los tres pasos completos y un cuadro para probar"></p>

### Compilar desde el código

```bash
git clone https://github.com/ReyDavidAG/labia.git && cd labia
swift test                 # pruebas del núcleo
scripts/bundle.sh          # arma build/Labia.app (firma ad hoc)
open build/Labia.app
```

Los permisos de macOS se amarran a la firma. Con firma ad hoc, cada compilación nueva pierde el permiso de Accesibilidad. Si tienes una identidad de firma, úsala y el permiso se conserva:

```bash
LABIA_SIGN_IDENTITY="Apple Development: Tu Nombre (XXXXXXXXXX)" scripts/bundle.sh
```

Para probar el motor sin micrófono: `build/Labia.app/Contents/MacOS/Labia --transcribe audio.wav`. Las capturas de este README se regeneran con `--screenshots docs/img`. Para activar o quitar el arranque al iniciar sesión desde Terminal: `/Applications/Labia.app/Contents/MacOS/Labia --login-item on` (u `off`).

## Vocabulario: precisión contra velocidad

Whisper recibe tu lista como contexto antes de cada dictado. En una prueba con 7 frases de desarrollo dichas en español:

| Configuración | Términos mal escritos | Tiempo por frase (M2) |
|---|---|---|
| Sin vocabulario | 5 (`de velo`, `Use API Query`, `style time`, `link`, `Aversel`) | ≈ 1.5 s |
| Con 19 palabras (~58 tokens) | 0 | ≈ 3 s |

Cada token del vocabulario cuesta unos 25 ms, porque Whisper lo procesa antes de empezar a escribir. La lista inicial trae 9 palabras (≈ +0.6 s): agrega sólo las que te fallen. **Ajustes → Vocabulario** muestra cuánto cuesta tu lista. Además, después de transcribir Labia une las palabras que Whisper separó (`Use API Query` → `useApiQuery`) y corrige mayúsculas de marcas (`vercel` → `Vercel`), siempre que las letras coincidan exactamente.

<p align="center"><img src="docs/img/settings-vocabulary.png" width="480" alt="Ajustes de vocabulario con palabras como pull request, Vercel y useApiQuery, y el costo estimado por dictado"> <img src="docs/img/settings-history.png" width="480" alt="Historial con los últimos dictados, la app donde se pegaron y cuántas palabras tenían"></p>

Para lo demás están los **Reemplazos**, que traen `nueva línea` → salto de línea y `punto y coma` → `;`.

## Privacidad

- El audio se procesa en memoria y se descarta al terminar.
- El historial guarda sólo el texto de los últimos 50 dictados, en `~/Library/Application Support/Labia/history.json`. Se borra desde Ajustes.
- La única conexión de red es la descarga del modelo desde Hugging Face.
- Lo que pega marca el portapapeles como transitorio, y tu contenido anterior se restaura al terminar.

## Cómo funciona

```
CGEventTap (atajo) → AVAudioEngine 16 kHz → WhisperKit turbo + vocabulario
  → limpieza (alucinaciones de silencio, vocabulario, reemplazos)
  → portapapeles + ⌘V simulado → restaurar portapapeles → historial
```

- `Sources/LabiaCore`: lógica pura con pruebas: los gestos como máquina de estados, la limpieza del texto, las preferencias y el historial.
- `Sources/Labia`: la app (SwiftUI + AppKit).

## Problemas comunes

- **No hace nada al mantener ⌥.** Revisa Ajustes del Sistema → Privacidad y seguridad → Accesibilidad. Si actualizaste la app y Labia ya aparece activado, quítalo con `−` y vuelve a agregarlo.
- **Escribe "No te oí".** El micrófono no captó voz. Revisa la entrada en Ajustes del Sistema → Sonido.
- **El primer dictado del día tarda.** El modelo se libera de la memoria tras 30 minutos sin uso. Puedes cambiarlo en Ajustes → Modelo.
- **fn abre los emojis.** macOS usa esa tecla. Elige ⌥ o ⌘ derecho, o cambia en Ajustes del Sistema → Teclado qué hace la tecla 🌐.

## Licencia

[MIT](LICENSE). Usa WhisperKit (MIT) y los modelos Whisper de OpenAI (MIT).

---

## English

**Labia** is a push-to-talk dictation app for macOS, tuned for Spanish speakers who mix English tech terms. Hold **right ⌥**, speak, and release: the text is pasted wherever your cursor is.

- Fully local. It uses Whisper large-v3-turbo through WhisperKit on the Apple Neural Engine. Audio never leaves your Mac.
- A custom vocabulary fixes code-switched terms. On an M2 a sentence takes about 1.5 s, plus ~25 ms per vocabulary token.
- Double-tap ⌥ for hands-free mode and press esc to cancel. It presses Enter only when you end the dictation with the send keyword («Claude» by default; change or turn it off in Settings).
- Requires macOS 14+ on Apple Silicon. Download it from [Releases](../../releases), or build it with `scripts/bundle.sh`. The app is not notarized, so run `xattr -dr com.apple.quarantine /Applications/Labia.app` after installing.

The UI is in Spanish. Set **Ajustes → Modelo → Idioma** to English to dictate in English.
