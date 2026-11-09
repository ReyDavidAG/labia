#!/bin/bash
# Arma build/Labia.app. Variables:
#   VERSION              versión visible (por defecto, el tag vX.Y.Z más alto)
#   LABIA_SIGN_IDENTITY  certificado de firma (por defecto ad hoc, «-»); el CI usa el certificado propio «Labia»
#   SPARKLE_PUBLIC_KEY   llave pública EdDSA de Sparkle (por defecto, Resources/SparklePublicKey); sin ella no se actualiza sola
set -euo pipefail
cd "$(dirname "$0")/.."

# El vX.Y.Z más alto: `git describe` en develop no ve el tag (queda en el merge de main) y vería el tag «desarrollo».
version=${VERSION:-$(git tag --list 'v[0-9]*' --sort=-v:refname 2>/dev/null | head -1 | sed 's/^v//')}
version=${version:-0.0.0}
# Sparkle compara este número: la fecha del commit siempre crece, en main y en develop.
build=${BUILD:-$(git log -1 --format=%ct 2>/dev/null || date +%s)}
commit=$(git rev-parse --short HEAD 2>/dev/null || echo "")
identity=${LABIA_SIGN_IDENTITY:--}
key=${SPARKLE_PUBLIC_KEY:-$(cat Resources/SparklePublicKey 2>/dev/null || true)}
key=${key:-__SPARKLE_PUBLIC_KEY__}

swift build -c release --arch arm64
bin=$(swift build -c release --arch arm64 --show-bin-path)

app=build/Labia.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin/Labia" "$app/Contents/MacOS/Labia"
cp -R "$bin"/*.bundle "$app/Contents/Resources/" 2>/dev/null || true
ditto "$bin/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
sed -e "s/__VERSION__/$version/" -e "s/__BUILD__/$build/" -e "s/__COMMIT__/$commit/" -e "s|__SPARKLE_PUBLIC_KEY__|$key|" \
	Resources/Info.plist > "$app/Contents/Info.plist"

# Sparkle se firma de adentro hacia afuera (sparkle-project.org/documentation/sandboxing), sin --deep.
sign() { codesign --force --options runtime --sign "$identity" "$@"; }
fw="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$fw/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$fw/XPCServices/Downloader.xpc"
sign "$fw/Autoupdate"
sign "$fw/Updater.app"
sign "$app/Contents/Frameworks/Sparkle.framework"
sign --entitlements Resources/Labia.entitlements "$app"
codesign --verify --deep --strict "$app"
echo "$app ($version, build $build, firma: $identity)"

if [[ "${1:-}" == "--zip" ]]; then
	mkdir -p dist
	ditto -c -k --keepParent "$app" "dist/Labia-$version.zip"
	echo "dist/Labia-$version.zip"
fi
