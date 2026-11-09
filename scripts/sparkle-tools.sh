#!/bin/bash
# CI: baja las herramientas de Sparkle (generate_appcast, sign_update) de la misma versión que Package.swift
# y deja SPARKLE_BIN en $GITHUB_ENV.
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(grep -o 'Sparkle.git", exact: "[0-9.]*"' Package.swift | grep -o '[0-9][0-9.]*')
dir=${RUNNER_TEMP:-$(mktemp -d)}/sparkle-$version
mkdir -p "$dir"
curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" | tar -xJ -C "$dir"
echo "SPARKLE_BIN=$dir/bin" >> "${GITHUB_ENV:-/dev/stdout}"
