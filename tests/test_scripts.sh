#!/usr/bin/env bash
#
# Functional + static tests for the Seedvault Magisk module scripts.
# Runs entirely on the host: no device or root required. It mocks the Android
# tools (bmgr, pm, getprop, log) and drives service.sh / uninstall.sh through a
# sandboxed copy with the /data/adb paths redirected into a temp dir.
#
# SPDX-License-Identifier: Apache-2.0
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOD="$REPO_ROOT/module"
SEEDVAULT_TRANSPORT="com.stevesoltys.seedvault.transport.ConfigurableBackupTransport"
GOOGLE_TRANSPORT="com.google.android.gms/.backup.BackupTransportService"

PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

# --------------------------------------------------------------------------
# Mock Android tools
# --------------------------------------------------------------------------
BIN="$SANDBOX/bin"; mkdir -p "$BIN"
export BMGR_STATE="$SANDBOX/bmgr_current"
echo "$GOOGLE_TRANSPORT" > "$BMGR_STATE"   # device starts on Google Backup

cat > "$BIN/getprop" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "sys.boot_completed" ] && echo 1 || echo ""
EOF

cat > "$BIN/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "$BIN/log" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "$BIN/pm" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "list" ] && [ "$2" = "packages" ]; then
  echo "package:com.android.settings"
  [ -n "${SEEDVAULT_ABSENT:-}" ] || echo "package:com.stevesoltys.seedvault"
fi
EOF

cat > "$BIN/bmgr" <<'EOF'
#!/usr/bin/env bash
STATE="${BMGR_STATE:?}"
case "${1:-}" in
  list)
    cur="$(cat "$STATE" 2>/dev/null)"
    for t in "com.google.android.gms/.backup.BackupTransportService" \
             "com.stevesoltys.seedvault.transport.ConfigurableBackupTransport"; do
      if [ "$t" = "$cur" ]; then printf '  * %s\n' "$t"; else printf '    %s\n' "$t"; fi
    done
    ;;
  transport) echo "$2" > "$STATE" ;;
  enable)    : ;;
esac
EOF
chmod +x "$BIN"/*
export PATH="$BIN:$PATH"

# Sandboxed copies of the scripts with /data/adb redirected into the sandbox.
mkdir -p "$SANDBOX/scripts"
sed "s#/data/adb#$SANDBOX/data/adb#g" "$MOD/service.sh"   > "$SANDBOX/scripts/service.sh"
sed "s#/data/adb#$SANDBOX/data/adb#g" "$MOD/uninstall.sh" > "$SANDBOX/scripts/uninstall.sh"
chmod +x "$SANDBOX/scripts/"*.sh
STATE_DIR="$SANDBOX/data/adb/seedvault-magisk"
RESTORE="$SANDBOX/data/adb/service.d/seedvault_restore_transport.sh"

echo "== 1. service.sh switches the active transport to Seedvault =="
bash "$SANDBOX/scripts/service.sh"
check "active transport is now Seedvault" '[ "$(cat "$BMGR_STATE")" = "$SEEDVAULT_TRANSPORT" ]'
check "previous transport saved as Google" '[ "$(cat "$STATE_DIR/previous_transport" 2>/dev/null)" = "$GOOGLE_TRANSPORT" ]'

echo "== 2. re-running service.sh is idempotent (keeps saved previous) =="
bash "$SANDBOX/scripts/service.sh"
check "previous transport still Google (not overwritten)" '[ "$(cat "$STATE_DIR/previous_transport")" = "$GOOGLE_TRANSPORT" ]'
check "active transport still Seedvault" '[ "$(cat "$BMGR_STATE")" = "$SEEDVAULT_TRANSPORT" ]'

echo "== 3. uninstall.sh drops a one-shot restore script =="
bash "$SANDBOX/scripts/uninstall.sh"
check "restore script created" '[ -x "$RESTORE" ]'
check "restore script targets the saved Google transport" 'grep -q "$GOOGLE_TRANSPORT" "$RESTORE"'

echo "== 4. the restore script re-enables Google Backup =="
echo "$SEEDVAULT_TRANSPORT" > "$BMGR_STATE"   # currently on Seedvault
bash "$RESTORE"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ "$(cat "$BMGR_STATE")" = "$GOOGLE_TRANSPORT" ] && break
  /bin/sleep 0.3
done
check "active transport restored to Google" '[ "$(cat "$BMGR_STATE")" = "$GOOGLE_TRANSPORT" ]'
check "restore script removed itself" '[ ! -f "$RESTORE" ]'
check "state dir cleaned up" '[ ! -d "$STATE_DIR" ]'

echo "== 5. service.sh handles Seedvault not yet installed =="
echo "$GOOGLE_TRANSPORT" > "$BMGR_STATE"
rm -rf "$STATE_DIR"
SEEDVAULT_ABSENT=1 bash "$SANDBOX/scripts/service.sh"
check "transport untouched when package missing" '[ "$(cat "$BMGR_STATE")" = "$GOOGLE_TRANSPORT" ]'

echo
echo "Functional results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
