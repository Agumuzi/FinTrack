# Changelog

This document records published FinTrack versions. Installers and checksum files are available on [GitHub Releases](https://github.com/Agumuzi/FinTrack/releases).

## v1.5.2 — 2026-11-02

- Collapse deposit interest summaries by default; use the info control to show or hide more compact cards.
- Limit financial schedule entries to two lines and match the neighboring goal card height, with internal scrolling when needed.
- Remove repeated currency labels beneath the transaction summary amounts.

## v1.5.1 — 2026-11-02

- Refine the upcoming financial schedule and deposit interest summary layouts, with currency symbols, green received amounts, primary-color outstanding amounts, and a received-share ring on wide windows.
- Place currency preferences beside scheduled posting settings on wide windows.
- Keep exchange-rate history filters and automatic update controls on one row on wide layouts.
- Prevent custom exchange-rate source timestamps from splitting date digits across lines.

## v1.5 — 2026-11-02

- Introduced an English-first localization module with full support for English, Simplified Chinese, Follow System, and in-app language switching. Existing Russian resources are retained but are not yet selectable.
- Refined English terminology, table headings, chart dates, menus, and multilingual layouts; fixed overlapping and truncated labels and icon alignment. The default accent color now matches the product website.
- Made the ledger-restore confirmation phrase follow the interface language again: `RESTORE` in English and its localized confirmation phrase in Simplified Chinese.
- Added a compact deposit-interest overview showing outstanding interest, current-year earnings, and future-year projections by original currency and scheduled interest year. Income awaiting verification is not counted as received; partial receipts and final amount adjustments remain distinct.
- Preserved database structures, historical amounts and exchange-rate snapshots, CSV contracts, backup formats, and update trust. Existing Chinese storage identifiers were not changed.

## v1.4.8 — 2026-11-01

- Standardized size limits for full-backup creation, reading, history, and restore journals, with support for full backups up to 256 MiB. Older backups remain supported. Backups larger than 100 MiB must be restored using v1.4.8 or later.
- Preserved original financial precision and exchange-rate snapshots when editing only a deposit's name, notes, or reminder. Nonfinancial information can still be corrected on settled deposits.
- Made selective cleanup stop safely if file processing or restoration has not finished.
- Added a contract-time-zone review and installment-by-installment date verification for legacy loans without saved fixed repayment dates. Existing fixed schedules and paid receipts remain unchanged.
- Delayed update startup confirmation until the ledger is ready, retaining the previous application copy if the ledger cannot open.
- Standardized popover heights for menu-bar quick entry, exchange-rate lists, and currency conversion. Heights remain stable while navigating or expanding history and adapt to screen space and UI scaling.
- Limited single-type CSV exports to their corresponding models, and corrected consistency for pre-1970 fractional-second dates and whole-second loan receipt identifiers.

## v1.4.7 — 2026-10-29

- When using Dock-only mode, closing the main window keeps the application running; clicking the Dock icon reopens it. ⌘Q still quits normally.
- Strengthened amount, status, reminder, and loan-schedule validation for CSV and full backups. Fixed recognition of selected amounts with leading decimal points or unusual digit grouping without changing the precision of existing records.
- Stabilized loan payment matching across time-zone changes. Added interruption recovery protection for category renaming, base-currency conversion, and full restoration.
- Preserved unsaved drafts in goal, budget, and category editors during the current session. Prevented outdated editor content or conversion results from being saved after changes to the base currency or ledger.
- Corrected amount-field paste, undo, and redo behavior; automatic digit grouping no longer interferes with native text editing.
- Improved transaction headers, amounts and currencies, dates, financial details, and backup-history layouts under larger fonts and narrower windows. Simplified repeated explanations and added actions to empty states.
- Moved file I/O, export encoding, and key-service waits off the main thread with progress and timeout feedback. Fixed missing refreshes after switching exchange-rate sources and pending reminders that could not be updated.

Create a full backup before upgrading. API keys remain in the system Keychain and are not included in backups.

## v1.4.6 — 2026-10-26

- Batched menu-bar historical exchange-rate queries over date ranges according to provider capabilities, reused caches when switching ranges, and supported existing history caches.
- Kept card expansion, collapsing, and conversion inputs responsive while loading; reduced redundant chart drawing and background-response processing on the UI.
- Compared daily exchange rates using the actual provider publication date, correctly handling device time zones, weekends, and unpublished days. Saved and refreshed the display immediately after obtaining a missing comparison baseline.
- Kept actual quote dates and providers in historical charts without fabricating missing rates; preserved valid cached data on request failures.

## v1.4.5 — 2026-10-26

- Moved secret access to a separately signed helper whose identity stays unchanged across routine application updates, avoiding repeated Keychain password prompts tied to each build fingerprint. App and helper verify one another's signatures; API keys remain in the system Keychain.
- Prevented background rate refreshes from prompting for the Keychain password. The first migration to the helper may require one authorization; choose `Always Allow` for the relevant provider to retain access across routine updates.
- Explicitly restored the main window after updates rather than applying normal startup window-hiding preferences. Confirmed the new launch only after the main window appeared, preserving signed-download verification and failure recovery.

If upgrades from v1.4.2 or v1.4.3 remain on the installation confirmation screen, quit the old version and replace it once using this release's DMG. Create a full backup before upgrading.

## v1.4.4 — 2026-10-26

- Fixed the installer confirmation window preventing the app from quitting. Maintained a busy state during installation to prevent duplicate tasks and nested old-package directories. Cleared the rollback copy after confirmed startup and retained recovery paths if installation or launch failed.
- Separated font size from interface scaling. ⌘+ / ⌘− change overall scale in 10% steps between 50% and 150%; ⌘0 resets it to 100%. Independent font-size controls remain available.
- Fixed crowded fields, overlapping cards, and out-of-bounds buttons in enlarged menu-bar quick entry. Windows, popovers, and menus now calculate usable space according to scale.
- Corrected theme thumbnail and interface preview sizing to prevent distortion, overflow, and initial guide-window resizing flashes.
- Preserved one- and two-column layouts and draggable dividers in deposits, recurring items, and loans. Initial widths account for heading and font metrics; manual adjustments remain, and large fonts favor full headings and notes by using available detail space.
- Standardized large-font navigation, filters, currency codes, and field labels. Moved amount-format samples into options, put expenses first in account panels, and styled values with red/green and currency symbols.

**Upgrading from v1.4.2 or v1.4.3:** Installation is performed by the currently running old updater. If its confirmation page cannot exit, quit the old version and manually replace FinTrack using this DMG. Later updates use the corrected flow. Create a full backup first.

## v1.4.3 — 2026-10-26

- Reworked selected-amount conversion into a minimal cursor-following overlay that automatically displays and copies the result, closing when the pointer leaves. Bare numbers first require a source currency; only three-letter currency codes are accepted.
- Shared currency favorites, display precision, and providers between selected-amount conversion and the menu bar, prioritizing valid cached quotes. Used a system fallback if a custom provider was unavailable and unified rate-update feedback.
- Standardized startup permissions and settings around switches and green status indicators, removed duplicate permission entry points, and disabled corresponding application features immediately when toggled off.
- Fixed transaction table-header font and clipping behavior on click and long press; improved internal column resizing. A normal click opens details while selection mode retains multi-selection.
- Reflected the custom avatar in the sidebar and remembered the main window's size and position. Supported direct entry and stepwise changes for body/explanatory text sizes and a wider shortcut scaling range.

Create a full backup before upgrading. macOS manages notification and Accessibility authorizations: switching off related app features disables them, but revoking system authorization requires System Settings.

## v1.4.2 — 2026-10-26

- Started first launch with an empty ledger and unified startup/permissions guide, which can be deferred or reopened from General settings.
- Shared one notification authorization throughout the app and linked login launch and Accessibility permissions to System Settings. Background operation can be configured independently.
- Replaced separate update windows with a unified in-app dialog for version discovery, download, and installation confirmation, using existing typography, cards, and buttons.
- Sent a system notification when automatic update checks discover a version; clicking opens the update dialog. Manual checks still open the prompt directly.
- Updated the FinTrack wallet icon while preserving transparency. Introduced a warm Agumuzi-branded DMG background, drag instructions, and a centered arrow, adjusting window and icon proportions.
- Switched the primary distribution to a DMG containing FinTrack and an Applications shortcut; corrected the mounted volume icon and supported drag-and-replace installation.
- Added DMG verification and installation preparation to in-app updates while retaining compatibility with older update-package formats.

Create a full backup before upgrading. Notifications and Accessibility follow macOS authorization; basic bookkeeping works without optional permissions.

## v1.4.1 — 2026-10-25

- Added login launch, keep-running-after-window-close, and hover-help settings; supported ⌘0 for standard text size and ⌘+ / ⌘− for font adjustments.
- Connected macOS notifications and reminders for deposits, recurring transactions, budgets, and goals. Scheduled posting runs at 09:00 local system time, with missed items caught up after wake or the next launch.
- Added global selected-amount conversion shortcuts and optional selection-triggered display, with amount/currency ambiguity detection and provider information. Copying the result is a separate user action.
- Prioritized expenses in overview and transaction views, condensed overview amount cards, and added hover, expanded selection, and scroll-to-category behavior to pie charts.
- Improved table column-width handling within the window, with draggable internal widths. Single-click selection, double-click/details viewing, and clipping/stability refinements were included.
- Unified button pressed/hover feedback; reorganized General settings and accent colors. Split updating into download selection and installation confirmation, linked feedback to GitHub, and pointed the homepage link at the product website.

Selected-text access requires macOS Accessibility permission; notifications require user authorization. Some apps cannot provide selected text; automatic display defaults to off. Updates use the official signed feed. Ledger locations and existing financial records remain compatible. Create a full backup before upgrading.

## v1.4 — 2026-10-24

- Fixed amount entry and backspace behavior across thousands separators; grouping appears during entry while preserving the caret, and historical amount precision is unchanged unless edited.
- Fixed duplicate backup-history entries and accidental deletions after overwriting backups with the same name. File identity and digest are checked before deletion, and undeleted entries remain if part of a removal fails.
- Fixed lost loan principal/down-payment fields, cent-level installment remainders, future transactions affecting goal baselines, and financial validation for original-format CSVs. Loan balances decrease based on verified receipts.
- Improved multi-selection, dates, and amount-column widths in transactions and condensed forms/details. Standardized category icons and reference-count ordering; tuned settings breakpoints and color preview in both appearances.
- Made historical exchange-rate charts progressive, canceled stale requests when switching ranges, reused history caches, refined mirror order, and reduced repeated Keychain access.

Releases use a fixed local signing identity and are not notarized by Apple. The first update from an older signing identity may trigger Keychain authorization again; later versions retain this identity. Back up before upgrading. Any historical cent-level differences in old loans retain original receipts and prompt review.

## v1.3 — 2026-10-23

- Added installed macOS font selection with a reset to system font; displayed the MIT license and an in-app license summary.
- Standardized financial editor forms, currency and category selection, amount fields, dates, and reminder times. Icon and color pickers open in separate windows.
- Shared one icon library across categories, budgets, and goals. Legacy category emoji return to a default icon until manually reselected. Display names for system interest and repayment categories can be changed without breaking existing transaction links.
- Added one-/two-column layouts and separate widths for deposits, recurring entries, and loans, plus deposit duplication, quick creation, and compact details.
- Added transaction context-menu edit/delete, multi-select, and Select All. Command+A selects all filtered results and shows checkboxes in multi-select mode.
- Used manually configured expected interest consistently for scheduling and posting. Automatically generated deposit-interest transactions are marked pending review and can be confirmed or adjusted to the actual received amount. Missed schedules are processed after reopening the main window.
- Put the base currency first in the currency directory with drag-to-reorder. Added an automatic menu-bar rate source; historical charts use independent system daily data, keeping bookkeeping-rate policies separate.
- Required a scope preview before category-based deletion; preserved other data and anti-duplicate posting state. Fixed empty budget views, button hit targets, and calendar year rendering.

Create a full backup before upgrading. Existing ledgers and original currency amounts remain compatible. Expected postings are not bank-verified receipts; review them in deposit details. Check automatic posting preferences and category icons after the first upgrade.

## v1.2.1 — 2026-10-23

- Fixed excessive overhead and download timeouts from receiving update packages byte by byte; switched to a system download task writing directly to a temporary file.
- Added download progress and a separate verification phase, distinguishing network timeouts, disconnections, oversized files, and checksum failures.
- Retained the official signed manifest, public key, HTTPS redirect handling, size limits, and SHA256 verification; installation still requires user confirmation.

The downloader shipped in v1.2 and earlier cannot be fixed by merely publishing a new installer. If downloading times out in an older release, manually download, verify, and replace the app with v1.2.1 once. Later upgrades use the new downloader. Back up first.

[Downloads and release notes](https://github.com/Agumuzi/FinTrack/releases/tag/v1.2.1) · [Installation](docs/INSTALLATION.md)

## v1.2 — 2026-10-23

- Reduced repeated calculations in category maintenance, overview, and budgets to improve responsiveness with larger ledgers.
- Standardized transaction filters around category icons and names; categories follow income/expense type. Refined amount columns, narrow-window layouts, and bottom pagination.
- Unified date selection and keyboard focus. Goals support no deadline, year, year/month, or full dates while retaining precise amounts and distinguishing target dates from completion.
- Added clear success, warning, and error states for imports, exports, backups, and restores. Result messages can be dismissed with Done, Esc, or a click outside.
- Opened a built-in empty ledger on first launch while retaining the original app identifier and data locations for existing users, with recovery access if a ledger fails to open.
- Refined account cards at 900 pt and goal amounts and dark-mode control icons.

Create a full backup before upgrading, and use a backup made for the corresponding older version when rolling back. Existing loan schedule conventions and legacy CSV re-import rules without IDs remain unchanged. Avoid forced quits during category merges and restores; consistency after interrupted changes across storage areas still has limitations.

Full-model checks and 47 key UI regressions passed on isolated data, supplemented with import and long-operation validation. Some page transitions still pause briefly; this release does not claim every interaction completes within 250 ms.

Requirements: macOS 15.0+; Universal (Apple Silicon / Intel). Ad-hoc signed, not notarized by Apple. Physical Intel/macOS 15 testing, full VoiceOver, and extended real-world financial use remain unverified.

In-app update checks detect new versions. An older downloader timed out in the test environment, while a direct public download and independent checksum verification passed. Use Releases to update manually if necessary; actual installation, relaunch, and rollback still require user verification.

[Downloads and release notes](https://github.com/Agumuzi/FinTrack/releases/tag/v1.2) · [Installation](docs/INSTALLATION.md)

## v1.1 — 2026-10-20

- Registered income/expense categories during CSV import. Opening category management after upgrading backfills categories for older imported transactions; existing referenced categories can be renamed.
- Started fresh installs with an empty ledger, empty categories, and no watched currency pairs while retaining existing ledger, categories, and rate settings on upgrade.
- Included the official Ed25519-signed update feed. Starting in v1.1, **About FinTrack** can check for, download, verify, and confirm installation of later releases.
- Preserved existing ledger locations and app identifiers, so existing data needs no re-import. A full backup is recommended before upgrading.

Requirements: macOS 15.0+; Universal (Apple Silicon / Intel). The distribution is ad-hoc signed and not notarized by Apple.

[Downloads and release notes](https://github.com/Agumuzi/FinTrack/releases/tag/v1.1) · [Installation](docs/INSTALLATION.md)

## v1.0 — 2026-10-19

First official macOS release.

- Income/expense tracking, accounts and assets, budgets, and financial goals.
- Deposit, loan, and recurring transaction management.
- Category statistics, trends, and period comparisons.
- Multi-currency transactions, exchange-rate lookup and conversion, and stored bookkeeping-rate snapshots.
- Menu-bar shortcuts and light/dark appearances.
- Native full backup and restore, plus import/export for four CSV formats.

Requirements: macOS 15.0+; Universal (Apple Silicon / Intel). The current distribution is ad-hoc signed and not notarized by Apple. Physical Intel tests, full VoiceOver testing, and long-term real-world financial use have not yet been completed.

[Downloads and release notes](https://github.com/Agumuzi/FinTrack/releases/tag/v1.0) · [Installation](docs/INSTALLATION.md)
