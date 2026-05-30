#!/sbin/sh
# Seedvault Backup Magisk module - install-time setup
# SPDX-License-Identifier: Apache-2.0

SEEDVAULT_APK="$MODPATH/system/priv-app/Seedvault/Seedvault.apk"

ui_print " "
ui_print "- Seedvault Backup module"
ui_print "  Replaces Google Backup with the Seedvault encrypted backup app."
ui_print " "

# --- Sanity: the Seedvault APK must be bundled -------------------------------
if [ ! -f "$SEEDVAULT_APK" ]; then
  ui_print "! Seedvault.apk is missing from this package."
  ui_print "! Build it with scripts/build.sh and repackage."
  abort  "! Aborting to avoid installing a broken module."
fi

# --- Android version check --------------------------------------------------
# This package follows Seedvault's "16-x.y" branch which targets Android 16
# (API 36). Seedvault is tightly coupled to the OS version, so refuse clearly
# incompatible systems instead of risking a boot loop.
ui_print "- Detected Android API level: $API"
if [ "$API" -lt 34 ]; then
  abort "! This module needs Android 14+ (API 34+). Aborting."
fi
if [ "$API" -ne 36 ]; then
  ui_print "  "
  ui_print "! WARNING: this build targets Android 16 (API 36)."
  ui_print "! You are on API $API. It may still work, but for best results"
  ui_print "! use the Seedvault branch matching your Android version."
  ui_print "  "
fi

# --- Permissions ------------------------------------------------------------
ui_print "- Setting permissions"
set_perm_recursive "$MODPATH/system" 0 0 0755 0644

ui_print " "
ui_print "- Installed:"
ui_print "    /system/priv-app/Seedvault/Seedvault.apk"
ui_print "    /system/etc/permissions/  (privileged permission allowlist)"
ui_print "    /system/etc/sysconfig/    (backup-transport allowlist)"
ui_print "    /system/etc/default-permissions/"
ui_print " "
ui_print "- After reboot, Seedvault becomes the active backup transport,"
ui_print "  replacing Google Backup. Open Settings > System > Backup (or the"
ui_print "  Seedvault app) to choose storage and set your recovery code."
ui_print " "
ui_print "- Removing this module restores the previous backup transport."
ui_print " "
