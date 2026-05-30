#!/usr/bin/env bash
#
# Static validation of the module package: layout, module.prop, XML files,
# shell-script syntax, and (if present) the bundled Seedvault APK.
#
# SPDX-License-Identifier: Apache-2.0
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOD="$REPO_ROOT/module"
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

echo "== module layout =="
for f in \
  module.prop \
  customize.sh service.sh uninstall.sh \
  META-INF/com/google/android/update-binary \
  META-INF/com/google/android/updater-script \
  system/etc/permissions/permissions_com.stevesoltys.seedvault.xml \
  system/etc/sysconfig/allowlist_com.stevesoltys.seedvault.xml \
  system/etc/default-permissions/default-permissions_com.stevesoltys.seedvault.xml
do
  check "exists: $f" "[ -f '$MOD/$f' ]"
done

echo "== module.prop =="
for key in id name version versionCode author description; do
  check "module.prop has $key" "grep -q '^$key=' '$MOD/module.prop'"
done
check "versionCode is an integer" "grep -qE '^versionCode=[0-9]+\$' '$MOD/module.prop'"

echo "== XML well-formedness =="
while IFS= read -r -d '' xml; do
  check "valid XML: ${xml#"$MOD"/}" "xmllint --noout '$xml'"
done < <(find "$MOD/system/etc" -name '*.xml' -print0)

echo "== privapp allowlist references the right package/service =="
check "privapp-permissions for seedvault" \
  "grep -q 'privapp-permissions package=\"com.stevesoltys.seedvault\"' '$MOD/system/etc/permissions/permissions_com.stevesoltys.seedvault.xml'"
check "backup-transport whitelisted service present" \
  "grep -q 'backup-transport-whitelisted-service' '$MOD/system/etc/sysconfig/allowlist_com.stevesoltys.seedvault.xml'"

echo "== shell script syntax =="
for s in customize.sh service.sh uninstall.sh; do
  check "sh -n $s" "sh -n '$MOD/$s'"
done
check "update-binary syntax" "sh -n '$MOD/META-INF/com/google/android/update-binary'"

echo "== transport id consistency =="
check "service.sh uses the Seedvault transport id" \
  "grep -q 'com.stevesoltys.seedvault.transport.ConfigurableBackupTransport' '$MOD/service.sh'"

echo "== bundled APK (optional, present after scripts/build.sh) =="
APK="$MOD/system/priv-app/Seedvault/Seedvault.apk"
if [ -f "$APK" ]; then
  ok "Seedvault.apk present ($(du -h "$APK" | cut -f1))"
  AAPT2="$(ls "${ANDROID_SDK_ROOT:-/opt/android-sdk}"/build-tools/*/aapt2 2>/dev/null | tail -n1)"
  if [ -n "$AAPT2" ]; then
    PKG="$("$AAPT2" dump packagename "$APK" 2>/dev/null)"
    check "APK package is com.stevesoltys.seedvault" "[ '$PKG' = 'com.stevesoltys.seedvault' ]"
  fi
  APKSIGNER="$(ls "${ANDROID_SDK_ROOT:-/opt/android-sdk}"/build-tools/*/apksigner 2>/dev/null | tail -n1)"
  if [ -n "$APKSIGNER" ]; then
    check "APK signature verifies" "'$APKSIGNER' verify '$APK' >/dev/null 2>&1"
  fi
  if [ -n "$AAPT2" ]; then
    # grep -c reads the whole stream (no SIGPIPE under 'set -o pipefail')
    WEBDAV_HITS="$("$AAPT2" dump resources "$APK" 2>/dev/null | grep -c 'layout/fragment_webdav_config')"
    check "APK includes the WebDAV storage backend" "[ '${WEBDAV_HITS:-0}' -gt 0 ]"
  fi
else
  echo "  SKIP: APK not built yet (run scripts/build.sh)"
fi

echo
echo "Static results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
