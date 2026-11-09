#!/bin/bash
# Una sola vez, en la Mac del autor (updates/plan.md, fases 6 y 7). Deja listo lo que el CI necesita para
# publicar versiones que se actualizan solas:
#   1. Certificado de firma de código propio «Labia» (autofirmado, 20 años) en el llavero de inicio de sesión,
#      y su .p12 en los secretos MAC_CERT_P12 / MAC_CERT_PASSWORD. macOS liga Accesibilidad a este certificado.
#   2. Llave EdDSA de Sparkle: la privada en el llavero y en el secreto SPARKLE_ED_PRIVATE_KEY, la pública en
#      Resources/SparklePublicKey (va en el repo).
# Si el certificado o la llave ya existen, los reutiliza. Necesita `gh` con sesión en la cuenta dueña del repo.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=ReyDavidAG/labia
login=~/Library/Keychains/login.keychain-db
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
umask 077

if security find-certificate -c Labia "$login" >/dev/null 2>&1; then
	echo "1. Ya hay un certificado «Labia» en el llavero: no se crea otro (los secretos quedan como están)."
else
	echo "1. Creando el certificado «Labia»…"
	cat > "$work/cert.cnf" <<'CNF'
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = Labia
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CNF
	openssl req -x509 -newkey rsa:2048 -sha256 -days 7300 -nodes -keyout "$work/labia.key" -out "$work/labia.crt" -config "$work/cert.cnf" 2>/dev/null
	password=$(openssl rand -hex 16)
	openssl pkcs12 -export -legacy -inkey "$work/labia.key" -in "$work/labia.crt" -name Labia -out "$work/Labia.p12" -passout "pass:$password" 2>/dev/null ||
		openssl pkcs12 -export -inkey "$work/labia.key" -in "$work/labia.crt" -name Labia -out "$work/Labia.p12" -passout "pass:$password"
	security import "$work/Labia.p12" -k "$login" -P "$password" -T /usr/bin/codesign
	security add-generic-password -U -a labia -s "Labia · contraseña del .p12" -w "$password" "$login"
	base64 -i "$work/Labia.p12" | gh secret set MAC_CERT_P12 -R "$repo"
	printf '%s' "$password" | gh secret set MAC_CERT_PASSWORD -R "$repo"
	echo "   Listo: en el llavero y en los secretos de GitHub."
fi

echo "2. Llave de Sparkle…"
eval "$(RUNNER_TEMP="$work" GITHUB_ENV=/dev/stdout scripts/sparkle-tools.sh | sed 's/^/export /')"
"$SPARKLE_BIN/generate_keys" --account labia >/dev/null
public=$("$SPARKLE_BIN/generate_keys" --account labia -p)
printf '%s\n' "$public" > Resources/SparklePublicKey
"$SPARKLE_BIN/generate_keys" --account labia -x "$work/sparkle.key" >/dev/null
gh secret set SPARKLE_ED_PRIVATE_KEY -R "$repo" < "$work/sparkle.key"
echo "   Pública en Resources/SparklePublicKey: $public"

echo
echo "Hecho. Para tu copia local: LABIA_SIGN_IDENTITY=Labia scripts/bundle.sh"
echo "Respaldo: el certificado y la llave de Sparkle viven en tu llavero (Acceso a Llaveros → «Labia» y «Private key for signing Sparkle updates»)."
gh secret list -R "$repo"
