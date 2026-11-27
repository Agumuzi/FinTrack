# Source Architecture

FinTrack uses SwiftUI, SwiftData, AppKit, and Apple system SDKs. The macOS application target is `FinTrack`, configured in `Project/project.yml`.

```text
Sources/
  App/          Application entry point, windows, and lifecycle
  Core/         Bookkeeping rules, exchange rates, persistence, preferences, and system services
  Features/     Feature-specific views, state, and services
  Components/   Reusable controls, design primitives, and image handling
  Shared/       Shared data models and general calculation rules
Resources/      App icons, localization, and currency flag assets
Project/        XcodeGen build specification
scripts/        Public build tools and website validation
docs/           Build, installation, and data documentation
website/        Static product website
.github/        Build and GitHub Pages workflows
```

`Features/` covers overview, transactions, deposits, loans, recurring entries, statistics, settings, exchange rates, menu bar, quick entry, and data management. `Shared/` maintains a single set of models and business rules rather than duplicated implementations.

The eight SwiftData models are `Account`, `Transaction`, `Category`, `Goal`, `FinancialProfile`, `RecurringTransaction`, `DepositRecord`, and `LoanRule`. See [Data & Privacy](PRIVACY.md) for local storage and user-data handling.

The build directly references `Sources/` and `Resources/`, and XcodeGen generates file references recursively. New files usually do not need to be added to a manually maintained file list. When changing resources, also verify loading behavior and the applicable license.

## Goal and posting rules

The overview, goal management, and reminders select the active financial profile with liquidity state first and share the same calendar-day snapshot. Absolute goals compare current net worth with the saved target. Growth goals compare net worth minus the stored creation baseline with the saved growth target. The progress display clamps to 0–100%. Pausing and manual completion govern goal status and reminders. Upgrading changes the computed progress of older absolute goals while retaining their stored targets, dates, and baselines.

A recurring batch validates up to 24 dates, requests exactly those dated FX snapshots, and saves the receipts and cursor in one SwiftData transaction. Manual confirmation covers the displayed batch. An automatic run processes up to three batches per eligible rule under the existing authorization and resumes from the committed cursor. New monthly and yearly rules store their day anchor in the existing plan identifier. Short months use their last day. Existing plan identifiers keep their prior calendar progression. Native backups and the full CSV snapshot carry that identifier. Earlier FinTrack builds treat newly anchored plans as legacy plans that need review.

New amounts entering two-decimal posting paths must be representable without rounding. Historical snapshots and the six-decimal FX storage rule retain their existing precision. Support for currency-specific minor units would require a coordinated accounting, import, export, and compatibility change.

Ordinary transaction deletion stores a tombstone. Undo applies to the last deletion in the records view and checks the active container, restore generation, book currency, and transaction revision. Native backups retain the tombstone. System receipts remain protected.

The menu bar controller keeps saved entry preferences independent from AppKit’s open, minimized, and closed main-window state. It requests regular activation before an explicit main-window open, and the menu-only preference takes effect after the window closes.

The public macOS build gate runs deterministic synthetic checks against the production goal, recurring schedule, deposit, and precision rules. The private SwiftData regression target verifies receipt identity, batch saves, and restore behavior using synthetic ledgers.
