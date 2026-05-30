#!/usr/bin/env bash
#
# Package the module/ directory into a flashable Magisk zip.
# Usage: scripts/package.sh [output.zip]
#
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOD="$REPO_ROOT/module"
VER="$(sed -n 's/^version=//p' "$MOD/module.prop" | head -n1)"
OUT="${1:-$REPO_ROOT/seedvault-magisk-${VER}.zip}"

APK="$MOD/system/priv-app/Seedvault/Seedvault.apk"
if [ ! -f "$APK" ]; then
  echo "!! $APK is missing. Run scripts/build.sh first." >&2
  exit 1
fi

rm -f "$OUT"
# Zip the CONTENTS of module/ (not the module/ folder itself) at the zip root,
# which is what Magisk expects.
( cd "$MOD" && zip -r9 "$OUT" . -x '.*' >/dev/null )
echo ">> Created $OUT"
unzip -l "$OUT"
