#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

version=${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}
version=${version:-0.0.0}
build=$(git rev-list --count HEAD 2>/dev/null || echo 1)
identity=${LABIA_SIGN_IDENTITY:--}

swift build -c release --arch arm64
bin=$(swift build -c release --arch arm64 --show-bin-path)

app=build/Labia.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Labia" "$app/Contents/MacOS/Labia"
cp -R "$bin"/*.bundle "$app/Contents/Resources/" 2>/dev/null || true
cp Resources/AppIcon.icns "$app/Contents/Resources/"
sed -e "s/__VERSION__/$version/" -e "s/__BUILD__/$build/" Resources/Info.plist > "$app/Contents/Info.plist"

codesign --force --deep --options runtime --entitlements Resources/Labia.entitlements --sign "$identity" "$app"
codesign --verify --strict "$app"
echo "$app ($version, firma: $identity)"

if [[ "${1:-}" == "--zip" ]]; then
	mkdir -p dist
	ditto -c -k --keepParent "$app" "dist/Labia-$version.zip"
	echo "dist/Labia-$version.zip"
fi
