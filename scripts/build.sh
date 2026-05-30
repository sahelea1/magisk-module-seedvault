#!/usr/bin/env bash
#
# Build the Seedvault APK from source and place it inside the Magisk module.
#
# Usage:   scripts/build.sh [seedvault-git-ref]
# Example: scripts/build.sh 16-5.8
#
# Requirements: git, curl, unzip, a JDK (17+). If ANDROID_SDK_ROOT is not set,
# the Android command-line tools + platform 36 + build-tools are downloaded into
# .build/android-sdk automatically.
#
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SEEDVAULT_REF="${1:-16-5.8}"
SEEDVAULT_REPO="https://github.com/seedvault-app/seedvault.git"
WORK="$REPO_ROOT/.build"
SRC="$WORK/seedvault"
DEST="$REPO_ROOT/module/system/priv-app/Seedvault/Seedvault.apk"
CLT_VER="14742923"

mkdir -p "$WORK"

# --- Android SDK ------------------------------------------------------------
if [ -z "${ANDROID_SDK_ROOT:-}" ]; then
  export ANDROID_SDK_ROOT="$WORK/android-sdk"
fi
export ANDROID_HOME="$ANDROID_SDK_ROOT"
SDKM="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$SDKM" ]; then
  echo ">> Installing Android command-line tools into $ANDROID_SDK_ROOT"
  mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
  zip="commandlinetools-linux-${CLT_VER}_latest.zip"
  curl -sSL -o "$WORK/$zip" "https://dl.google.com/android/repository/$zip"
  rm -rf "$WORK/cmdline-tools"
  unzip -q "$WORK/$zip" -d "$WORK"
  rm -rf "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  mv "$WORK/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
fi
yes | "$SDKM" --licenses >/dev/null 2>&1 || true
"$SDKM" "platform-tools" "platforms;android-36" "build-tools;36.0.0" >/dev/null

# --- Seedvault source -------------------------------------------------------
if [ ! -d "$SRC/.git" ]; then
  echo ">> Cloning Seedvault @ $SEEDVAULT_REF"
  git clone --depth 1 --branch "$SEEDVAULT_REF" "$SEEDVAULT_REPO" "$SRC"
else
  echo ">> Reusing existing clone at $SRC"
fi

# --- Build ------------------------------------------------------------------
echo "sdk.dir=$ANDROID_SDK_ROOT" > "$SRC/local.properties"
echo ">> Building :app:assembleRelease (this can take several minutes)"
( cd "$SRC" && ./gradlew :app:assembleRelease --no-daemon -x lint -x lintVitalRelease )

APK="$(find "$SRC/app/build/outputs/apk/release" -name '*.apk' | head -n1)"
if [ -z "$APK" ]; then
  echo "!! Build produced no APK" >&2
  exit 1
fi

mkdir -p "$(dirname "$DEST")"
cp "$APK" "$DEST"
echo ">> Seedvault APK copied to: $DEST"
ls -la "$DEST"
