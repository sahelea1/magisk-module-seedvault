# Seedvault Backup — Magisk Module

A Magisk module that installs [**Seedvault**](https://github.com/seedvault-app/seedvault),
the open-source encrypted backup app for Android, as a privileged system app and
makes it the **active backup transport in place of Google Backup**.

Seedvault is normally something that has to be *compiled into a ROM* — it
"can not be installed as a regular app" because it needs to be a privileged
system app with the `android.permission.BACKUP` privilege and a backup-transport
allowlist entry. This module performs exactly that ROM integration at runtime
using Magisk's systemless overlay, so you can use Seedvault on a rooted stock
device without rebuilding your ROM.

- ✅ Installs Seedvault as a privileged system app (`/system/priv-app`)
- ✅ Ships the official privileged-permission, sysconfig and default-permission
  allowlists, so the app gets its permissions and **the device still boots**
- ✅ On boot, selects Seedvault as the active backup transport — replacing Google
  Backup
- ✅ On **uninstall**, restores the previously active transport (Google Backup),
  so removing the module cleanly reverses the change

> **Android version:** this package follows Seedvault's `16-5.8` branch, which
> targets **Android 16 (API 36)**. Seedvault is tightly coupled to the OS
> version — use the branch/build matching your Android version (see
> [Rebuilding](#rebuilding-for-another-android-version)).

---

## How it works

| Concern | Mechanism |
| --- | --- |
| Make Seedvault a privileged system app | APK placed at `/system/priv-app/Seedvault/Seedvault.apk` |
| Grant its privileged permissions (without a bootloop) | `system/etc/permissions/permissions_com.stevesoltys.seedvault.xml` |
| Register it as an allowed backup transport + hidden-API access | `system/etc/sysconfig/allowlist_com.stevesoltys.seedvault.xml` |
| Pre-grant runtime perms (notifications, media location) | `system/etc/default-permissions/default-permissions_com.stevesoltys.seedvault.xml` |
| Replace Google Backup with Seedvault | `service.sh` runs `bmgr transport com.stevesoltys.seedvault.transport.ConfigurableBackupTransport` at every boot |
| Re-enable Google Backup on removal | `uninstall.sh` drops a one-shot script into `/data/adb/service.d` that restores the saved transport |

The three permission/allowlist XML files and their install locations mirror
Seedvault's own [`Android.bp`](https://github.com/seedvault-app/seedvault/blob/android16/Android.bp)
ROM-integration manifest, so the device boots normally and the app behaves the
same as on a ROM that ships Seedvault.

### About the previous transport

The first time `service.sh` runs after install, it records the currently active
backup transport (typically Google's
`com.google.android.gms/.backup.BackupTransportService`) into
`/data/adb/seedvault-magisk/previous_transport`. That file lives outside the
module directory so it survives module removal, letting `uninstall.sh` restore
the exact transport you had before. If nothing was selected before, it defaults
to the Google transport.

### Signing note

The bundled APK is signed with the **public AOSP platform test key** (the same
key Seedvault's release build uses). On a stock device the platform signature
won't match, so Seedvault is granted its permissions via the **privileged-app
allowlist** rather than via a platform-signature match. All backup-transport
functionality relies on `signature|privileged` permissions, which the allowlist
covers — so app backup/restore works. A few purely cosmetic, signature-only
extras (e.g. `MANAGE_DOCUMENTS` storage-root browsing) are optional and simply
stay ungranted.

---

## Installation

1. Download or build the flashable zip (see below).
2. In the **Magisk app → Modules → Install from storage**, pick the zip.
3. **Reboot.**
4. Open **Settings → System → Backup** (or launch the *Seedvault* app) and set
   up your backup storage and **recovery code**. Seedvault is already the active
   transport; you only need to choose where backups go and save your 12-word
   recovery key.

> Backups only start once you have completed Seedvault's setup (storage +
> recovery code). Selecting the transport — which this module does — is the part
> that normally requires ROM integration.

### Storage options (incl. WebDAV)

When you set up Seedvault, the storage picker offers:

- **WebDAV** — back up to any WebDAV server (Nextcloud, ownCloud, mailbox.org,
  a self-hosted server, etc.). Pick *WebDAV*, then enter the server **URL**,
  **username** and **password**. This needs no extra setup from this module:
  the bundled Seedvault build already ships the WebDAV backend, and the app
  holds the `INTERNET` / `ACCESS_NETWORK_STATE` permissions it requires.
- **USB flash drive** — removable storage; Seedvault backs up automatically when
  it is plugged in.
- **Internal storage / SD card** and other Storage Access Framework providers
  (e.g. a DAVx5-mounted share) that expose a documents root.

WebDAV is the recommended option for off-device, network backups.

### Uninstall

Remove the module in the Magisk app and **reboot**. On that reboot the previous
transport (Google Backup) is restored automatically and the module's state in
`/data/adb/seedvault-magisk` is cleaned up.

---

## Building

Everything is reproducible from source. Requirements: `git`, `curl`, `unzip`,
and a JDK 17+. The Android SDK is fetched automatically if `ANDROID_SDK_ROOT`
is not set.

```bash
# 1. Build the Seedvault APK and place it inside module/
scripts/build.sh 16-5.8

# 2. Run the test suite (static + functional, no device needed)
tests/validate.sh
tests/test_scripts.sh

# 3. Package the flashable Magisk zip
scripts/package.sh
# -> seedvault-magisk-16-5.8.zip
```

The repository already includes a pre-built `module/system/priv-app/Seedvault/Seedvault.apk`
(built from Seedvault tag `16-5.8`), so you can package and flash without
building. `scripts/build.sh` reproduces that exact artifact.

### Rebuilding for another Android version

Pick the Seedvault tag/branch matching your Android version (e.g. `15-5.8` for
Android 15) and rebuild:

```bash
scripts/build.sh 15-5.8
# then bump `version`/`versionCode` in module/module.prop and repackage
```

The `compileSdk`/`build-tools` versions are driven by Seedvault's own Gradle
config; `scripts/build.sh` installs whatever `platforms;android-36` /
`build-tools;36.0.0` the `16-x` branch needs. For other branches adjust the SDK
packages in `scripts/build.sh` accordingly.

---

## Testing

Because no Android device is available in CI, the scripts are exercised with
mocked Android tools:

- **`tests/validate.sh`** — static checks: module layout, `module.prop` fields,
  XML well-formedness, shell-script syntax, and (when present) the bundled APK's
  package name and signature.
- **`tests/test_scripts.sh`** — functional checks: it mocks `bmgr`, `pm`,
  `getprop` and `log`, then drives `service.sh` and `uninstall.sh` end-to-end to
  prove that (1) the transport switches to Seedvault, (2) the previous transport
  is saved and not clobbered on re-run, (3) uninstall drops a restore script
  targeting the saved transport, and (4) that restore script re-enables Google
  Backup and cleans up after itself.

---

## Repository layout

```
module/                         # contents of the flashable zip
├── module.prop
├── customize.sh                # install-time: checks + permissions
├── service.sh                  # each boot: select Seedvault transport
├── uninstall.sh                # on removal: schedule transport restore
├── META-INF/.../update-binary  # standard Magisk installer
└── system/
    ├── priv-app/Seedvault/Seedvault.apk
    └── etc/{permissions,sysconfig,default-permissions}/*.xml
scripts/
├── build.sh                    # build APK from Seedvault source
└── package.sh                  # zip the module
tests/
├── validate.sh                 # static checks
└── test_scripts.sh             # functional checks (mocked Android tools)
```

---

## Caveats

- **Reboot required** after install and after uninstall.
- You must complete Seedvault setup (storage + recovery code) for backups to run.
- Match the Seedvault build to your Android version. A mismatched build is
  refused for clearly incompatible systems (API < 34) and warned about otherwise.
- This integrates the *app backup* transport. Seedvault's separate file/storage
  backup is part of the same app and available once set up.

## Licensing

Module scripts: Apache-2.0 (see `LICENSE`). Seedvault and its permission XML
files are © The Calyx Institute / Steve Soltys, also Apache-2.0, from
<https://github.com/seedvault-app/seedvault>.
