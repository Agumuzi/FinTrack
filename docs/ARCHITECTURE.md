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
