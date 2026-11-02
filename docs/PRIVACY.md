# Data & Privacy

## Local ledger

FinTrack manages its financial ledger inside the current user's macOS Application Support directory.

SQLite may also use `-wal` and `-shm` files. The ledger, uploaded images, and preferences are separate from the app bundle and source directory. SwiftData manages the local records. FinTrack does not provide a feature for uploading the ledger to a FinTrack server, and this macOS build does not enable CloudKit ledger synchronization.

The app ships with no preloaded sample ledger. Users enter their own accounts, transactions, plans, and custom images. The fictional ledger shown on the website is for demonstration only.

## Network access

Exchange-rate queries contact the provider selected by the user. That provider may receive network-request information needed for the query, such as an IP address, currencies, and dates. Custom API keys are stored in the local Keychain. They are not transferred with full ledger backups and must be reconfigured after restoration.

Software updates use FinTrack's official signed manifest and GitHub Releases. GitHub downloads, Issues, and the product site are also subject to GitHub's terms and privacy policies. The site includes no analytics scripts, advertisements, or third-party fonts; its appearance preference is stored only in the browser.

## Backups and restoration

Use the native full-backup feature to preserve the ledger, supported preferences, and uploaded images. Restoration requires confirmation and a safe copy of the current ledger because it replaces existing data. CSV files are for data interchange, **not a substitute for full backups**.

Reimporting native CSV records with stable IDs skips records already present. Legacy CSV files without stable IDs create new records on every import: verify them first, because FinTrack does not automatically merge entries merely because their dates and amounts match.

Category renaming, base-currency conversion, and full restoration create local recovery journals before making changes. If interrupted, FinTrack restores the pre-operation state when the ledger next opens and suspends automatic posting until the user has checked the result. Journals also contain financial data, remain locally alongside the ledger, and exclude API keys; they are removed after successful completion. Corrupted journals stop further writes and preserve the original files rather than substituting an empty ledger.

Backup archives, CSVs, and databases may contain complete financial information. FinTrack does **not** provide application-level encryption. Use protected storage and consider macOS disk encryption and system backups. Never upload financial files or screenshots containing personal data to a public repository.

## Protecting personal information when reporting issues

Prefer fictional values when reproducing bugs. Remove names, account numbers, real balances, and personal paths from screenshots. Do not submit API keys, native ledgers, or full backups. For security-related bugs, use the repository's private vulnerability reporting channel.

## Selected-amount conversion and system permissions

Selected-amount conversion runs only when enabled by the user. Its global shortcut and optional selection-triggered display access selected text through macOS Accessibility. If shortcut-based reading fails, FinTrack may attempt a copy operation and restore the prior clipboard. Automatic selection reading does not simulate copying. After a successful conversion, the app copies the result only if no other operation changed the clipboard in the meantime.

Password fields are not read. Some applications do not support selected-text access. Selected text is not logged or uploaded; exchange-rate requests contain only the required currencies. The feature can be disabled in Settings.

macOS authorization is required for notifications. Login launch can be managed either in FinTrack or macOS Login Items. In Dock-only mode, closing the window leaves the app running and clicking its Dock icon reopens it; ⌘Q always quits. With other icon arrangements, the **Keep Running After Closing Window** preference controls the behavior.

Scheduled daily posting occurs at 09:00 system local time. Missed items are caught up after wake or the next launch. A single automatic catch-up processes no more than 24 installments; beyond that, the batch stops entirely. Back up first, then use the history-review feature to confirm the next unpaid date against actual records.

## First-launch permissions guide

The first main window opens an empty ledger without manual creation. A unified guide explains notifications, background operation, login launch, and Accessibility access for selected text. You can defer it and reopen it from General settings. Notifications share one system authorization for financial and software-update reminders; when automatic checks find a new version, clicking the notification opens the in-app update prompt.

Background operation is an app preference; basic bookkeeping does not depend on these optional permissions. System authorizations are not included in ledger backups and are not transferred to other devices. First launch does not request access to the entire Documents folder; importing and backup operations select file locations only when the user initiates them.
