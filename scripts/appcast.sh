#!/bin/bash
# CI: arma dist/appcast.xml, el feed de Sparkle, a partir de dist/Labia-*.zip (scripts/bundle.sh --zip).
#   scripts/appcast.sh estable      con TAG=vX.Y.Z: el feed que sube cada release (releases/latest/download/appcast.xml)
#   scripts/appcast.sh desarrollo   el feed del release preliminar «desarrollo», que sigue develop
# Necesita SPARKLE_ED_PRIVATE_KEY (la llave privada EdDSA) y SPARKLE_BIN (las herramientas de Sparkle).
#
# Una versión sólo de Windows o Linux no debe reinstalar la Mac: en Estable, si la app no cambió desde la versión
# que tiene el feed anterior, el feed nuevo es el mismo y sigue apuntando a ese .zip.
set -euo pipefail
cd "$(dirname "$0")/.."

repo=https://github.com/ReyDavidAG/labia
mac_paths=(Sources Resources Package.swift Package.resolved scripts/bundle.sh)
channel=${1:?estable o desarrollo}
: "${SPARKLE_ED_PRIVATE_KEY:?falta la llave privada de Sparkle}" "${SPARKLE_BIN:?faltan las herramientas de Sparkle}"
zip=$(ls dist/Labia-*.zip | head -1)
grep -q __SPARKLE_PUBLIC_KEY__ <(unzip -p "$zip" Labia.app/Contents/Info.plist) &&
	{ echo "la app no trae la llave pública (Resources/SparklePublicKey): no podría actualizarse" >&2; exit 1; }

case $channel in
estable)
	tag=${TAG:?falta TAG}
	prefix="$repo/releases/download/$tag/"
	name=$(basename "$zip")
	# Mientras corre este workflow, «latest» todavía es el release anterior.
	previous=$(curl -fsSL "${PREVIOUS_APPCAST:-$repo/releases/latest/download/appcast.xml}" 2>/dev/null || true)
	previous_tag=$(grep -o 'releases/download/v[^/"]*/' <<<"$previous" | head -1 | sed -e 's|releases/download/||' -e 's|/$||' || true)
	if [[ -n "$previous_tag" ]] && git rev-parse -q --verify "refs/tags/$previous_tag" >/dev/null &&
		git diff --quiet "$previous_tag" HEAD -- "${mac_paths[@]}"; then
		printf '%s\n' "$previous" > dist/appcast.xml
		echo "macOS no cambió desde $previous_tag: el feed sigue en esa versión"
		exit 0
	fi
	;;
desarrollo)
	prefix="$repo/releases/download/desarrollo/"
	name=Labia-desarrollo.zip
	cp "$zip" "dist/$name"
	;;
*)
	echo "canal desconocido: $channel" >&2
	exit 1
	;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/archives"
cp "$zip" "$work/archives/$name"
printf '%s' "$SPARKLE_ED_PRIVATE_KEY" > "$work/key"
"$SPARKLE_BIN/generate_appcast" --ed-key-file "$work/key" --download-url-prefix "$prefix" --link "$repo" \
	-o dist/appcast.xml "$work/archives"
echo "dist/appcast.xml → $prefix$name"
