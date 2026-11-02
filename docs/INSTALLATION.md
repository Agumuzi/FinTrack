# Installation and Updates

## Download and verify

Download `FinTrack-v1.5.3-macOS.dmg` and `SHA256.txt` from the [latest official release](https://github.com/Agumuzi/FinTrack/releases/latest). FinTrack requires macOS 15.0 or later; the distribution supports both Apple Silicon and Intel architectures.

Run this command in the download directory:

```sh
shasum -a 256 FinTrack-v1.5.3-macOS.dmg
```

Compare the resulting digest against the DMG entry in `SHA256.txt`. When it matches, open the DMG and drag `FinTrack` to the `Applications` folder shown in the same window. The disk image contains only the app and the Applications shortcut.

## First launch

The published application uses a fixed **local signing identity**, not an Apple Developer ID signature, and is **not notarized by Apple**. macOS may block an app downloaded from the internet on first launch. After verifying the source and checksum, follow [Apple's official instructions](https://support.apple.com/en-us/102445): attempt to open the app, then use **System Settings → Privacy & Security → Open Anyway** if that option is offered. Prompts vary by macOS version and device-management policies.

You do **not** need to disable system-wide security protections. If macOS reports that the app is damaged or contains malware, stop and investigate the source instead of bypassing the warning.

## Getting started

FinTrack creates an empty ledger automatically on first use. It does not preload any sample records. The **Startup & Permissions** guide offers notifications, background operation, launch at login, and selected-amount conversion. You can enable these features selectively or choose **Set Up Later**, then reopen the guide from **Settings → General**. System permissions include shortcuts to their corresponding macOS settings.

Enter a small number of transactions, quit and reopen the app, and check that amounts and records persist. Create a native full backup and store it safely. Before importing large amounts of data, verify restore behavior using an independent copy.

All records in website screenshots are fictional and are not distributed with the app.

## Secure updating

1. Make and safeguard a full backup in your existing version, then quit FinTrack completely.
2. Download the target version's DMG and matching `SHA256.txt` from [GitHub Releases](https://github.com/Agumuzi/FinTrack/releases). Verify the digest, then open the DMG.
3. Drag the new `FinTrack` into the `Applications` folder in the DMG, choose to replace the existing app, then launch and check both the version and your existing transactions.

The ledger resides independently on your Mac. Replacing the `.app` normally retains the existing ledger and settings. Do not manually delete the ledger directory or move SQLite files while the app is running. Keychain API keys are not exported with native ledger backups.

Users coming from v1.0 must manually replace the app as described above. Starting with v1.1, FinTrack includes an official signed update feed. In **Settings → About FinTrack**, use **Check Now** to check for a new release, download a package verified with an Ed25519-signed manifest and SHA256 digest, and separately confirm installation and relaunch.

Automatic checks are optional. With system notifications enabled, a detected version triggers a notification that opens the in-app update prompt when clicked; users can download or cancel. Manual checks open the prompt directly. Installation is separately confirmed after download and verification. The app directory must be writable by the current user; otherwise, replace the app manually from Releases. Make a full backup before either method.

If an in-app download fails or times out, use the manual Releases procedure. Verify that the DMG matches the checksum file from the **same release** before replacing the app.

In-app updates support DMGs beginning with v1.4.2. ZIP files included with Releases are retained for compatibility with older automatic updaters; choose the DMG for manual installation.

v1.2.1 fixed the update download mechanism. An older application's downloader is not repaired just because a newer package exists. If v1.2 or earlier times out, perform a one-time manual replacement using the procedure above.

For downgrades, use a full backup created with the corresponding earlier version before upgrading. Older versions are not guaranteed to open ledgers written by newer versions. Avoid force quitting during category merges and restores, which involve multiple local storage components.

Physical Intel testing, physical macOS 15 testing, complete VoiceOver testing, and prolonged real-world financial use remain outstanding.

## Custom display fonts

Open **Settings → Appearance & Language → Display Font → Choose Font** to select an installed font using the native macOS font panel. Use Font Book to manage installed fonts, or choose **Restore System Font**.

Body text supports 10–32 pt and explanatory text supports 8–28 pt, with direct entry and step controls. Body and explanatory sizes are independent; the font card can reset them to 16 pt and 12 pt respectively. Interface scaling is separate: 100% is the baseline, ⌘+ / ⌘− adjust in 10% steps from 50% to 150%, and ⌘0 resets to 100%. Backups retain font choices. If a selected font is unavailable on another Mac, the system font is used instead.

The official application accesses the system Keychain through an independently signed helper whose identity remains stable across routine updates. When migrating old keys to this helper, macOS may require authorization once; selecting **Always Allow** lets later ordinary updates reuse that authorization. Fixing the main app's signing identity alone cannot preserve every legacy Keychain entry.

The helper checks the official signature of its caller, and the app also verifies the helper's signature. It is not available to arbitrary programs. Background exchange-rate refreshes do not intentionally trigger password dialogs; if authorization is needed, open the relevant provider's settings. API keys are in the local Keychain, not the ledger backup or installer. FinTrack never saves the login Keychain password.

## Unresponsive installation confirmation in v1.4.2 / v1.4.3

In these two versions, the confirmation window can prevent the old process from exiting. Quit the old app, download the v1.4.4 or newer DMG, drag FinTrack into Applications in Finder, and choose to replace it. The ledger is outside the app bundle; still create a full backup before upgrading. v1.4.4 fixed the exit, duplicate-operation, and post-install launch-confirmation flows used by subsequent updates.

## Backup limits and legacy loans in v1.4.8

v1.4.8 continues to read supported legacy full backups and standardizes the per-backup safety limit at **256 MiB**. Restore backups larger than **100 MiB**, or newer backups containing large backup-history metadata, using v1.4.8 or later. When a backup exceeds the supported limit, the ledger is not changed. Quit FinTrack and preserve an offline copy of the entire ledger directory, separate preferences, and bank images before planning a restore; do not delete the original store. CSV is not a full-backup substitute.

Legacy loans without stored fixed repayment dates also lack the original contract time zone. Select the contract's time zone in loan details, review each installment date, and confirm before continuing. Existing fixed schedules and paid receipts retain their original values, and other ledger features remain available.
