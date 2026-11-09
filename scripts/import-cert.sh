#!/bin/bash
# CI: importa el certificado propio «Labia» a un llavero temporal y deja LABIA_SIGN_IDENTITY en $GITHUB_ENV.
# Entrada: MAC_CERT_P12 (el .p12 en base64) y MAC_CERT_PASSWORD. Sin ellas (un fork, un PR) no hace nada
# y bundle.sh firma ad hoc. Uso local para probar: KEYCHAIN_DIR=/tmp/x scripts/import-cert.sh
set -euo pipefail
if [[ -z "${MAC_CERT_P12:-}" ]]; then
	echo "sin MAC_CERT_P12: firma ad hoc"
	exit 0
fi
dir=${KEYCHAIN_DIR:-${RUNNER_TEMP:?}}
keychain="$dir/labia-signing.keychain-db"
password=$(uuidgen)
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
echo "$MAC_CERT_P12" | base64 --decode > "$dir/labia.p12"
security import "$dir/labia.p12" -k "$keychain" -P "${MAC_CERT_PASSWORD:-}" -T /usr/bin/codesign
rm -f "$dir/labia.p12"
security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')
# Autofirmado: no es «válido» para el sistema (sin -v), pero codesign firma con él igual.
identity=$(security find-identity -p codesigning "$keychain" | awk '/"Labia"/ { print $2; exit }')
[[ -n "$identity" ]] || { echo "el .p12 no trae un certificado «Labia» de firma de código" >&2; exit 1; }
echo "LABIA_SIGN_IDENTITY=$identity" >> "${GITHUB_ENV:-/dev/stdout}"
echo "KEYCHAIN_PATH=$keychain" >> "${GITHUB_ENV:-/dev/stdout}"
