#!/system/bin/sh
# Seedvault Backup Magisk module - boot service (runs at late_start each boot)
# Makes Seedvault the active Android backup transport, replacing Google Backup.
# SPDX-License-Identifier: Apache-2.0

MODDIR=${0%/*}

SEEDVAULT_PKG="com.stevesoltys.seedvault"
# Seedvault's transport id == ConfigurableBackupTransport::class.java.name
SEEDVAULT_TRANSPORT="com.stevesoltys.seedvault.transport.ConfigurableBackupTransport"
# Default Google cloud backup transport, used as a fallback for restore.
GOOGLE_TRANSPORT="com.google.android.gms/.backup.BackupTransportService"

# Persistent state, kept OUTSIDE the module dir so it survives module removal.
STATE_DIR="/data/adb/seedvault-magisk"
PREV_FILE="$STATE_DIR/previous_transport"

LOG_TAG="SeedvaultModule"
log_i() { log -t "$LOG_TAG" "$1"; }

# Return the currently active backup transport (the line marked with '*').
current_transport() {
  bmgr list transports 2>/dev/null | awk '/^[[:space:]]*\*/ {print $2}'
}

# 1) Wait until the system is fully booted so bmgr / pm are available.
i=0
while [ "$(getprop sys.boot_completed)" != "1" ]; do
  sleep 3
  i=$((i + 1))
  [ "$i" -gt 200 ] && { log_i "boot_completed never set, giving up"; exit 0; }
done
# Give PackageManager time to scan the priv-app and register the transport.
sleep 15

mkdir -p "$STATE_DIR"

# 2) Bail out cleanly if Seedvault is not installed (e.g. mount failed).
if ! pm list packages 2>/dev/null | grep -q "package:$SEEDVAULT_PKG"; then
  log_i "$SEEDVAULT_PKG not installed yet; skipping transport switch"
  exit 0
fi

# 2b) Keep Seedvault alive in the background: exempt it from battery
#     optimization / Doze so scheduled backups are not killed. The shipped
#     sysconfig allowlist already adds it to the power-save whitelist; we
#     reinforce that at runtime here for OEM battery managers (e.g. Motorola).
dumpsys deviceidle whitelist +"$SEEDVAULT_PKG" >/dev/null 2>&1
cmd appops set "$SEEDVAULT_PKG" RUN_ANY_IN_BACKGROUND allow >/dev/null 2>&1
cmd appops set "$SEEDVAULT_PKG" RUN_IN_BACKGROUND allow >/dev/null 2>&1

# 2c) Make sure the backup status/progress notification can actually show.
#     On Android 13+ POST_NOTIFICATIONS is a runtime permission; if it is not
#     granted, Seedvault's ongoing progress notification is silently dropped.
#     default-permissions pre-grants it, but that is unreliable for Magisk
#     system apps, so grant it explicitly here (no-op on older Android).
pm grant "$SEEDVAULT_PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1
cmd appops set "$SEEDVAULT_PKG" POST_NOTIFICATION allow >/dev/null 2>&1

# 3) Remember the transport that was active BEFORE we switch, exactly once,
#    so removing the module can restore it.
if [ ! -f "$PREV_FILE" ]; then
  CUR="$(current_transport)"
  if [ -n "$CUR" ] && [ "$CUR" != "$SEEDVAULT_TRANSPORT" ]; then
    echo "$CUR" > "$PREV_FILE"
    log_i "saved previous transport: $CUR"
  else
    # Nothing meaningful was selected; default to Google for restore.
    echo "$GOOGLE_TRANSPORT" > "$PREV_FILE"
    log_i "no prior transport; defaulting restore target to Google"
  fi
fi

# 4) Enable the backup framework and select Seedvault as the transport.
#    Retry a few times in case transport registration lags behind boot.
bmgr enable true >/dev/null 2>&1
attempt=0
while [ "$attempt" -lt 10 ]; do
  bmgr transport "$SEEDVAULT_TRANSPORT" >/dev/null 2>&1
  if [ "$(current_transport)" = "$SEEDVAULT_TRANSPORT" ]; then
    log_i "Seedvault is now the active backup transport"
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 6
done

log_i "could not select Seedvault transport after $attempt attempts"
exit 0
