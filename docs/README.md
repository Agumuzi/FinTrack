# FinTrack Documentation

This directory helps both people using FinTrack and developers or AI coding assistants reviewing and maintaining its source code. Start with the documentation relevant to your task before exploring the corresponding source modules.

## Users and security

| Document | Contents |
| --- | --- |
| [README](../README.md) | Features, downloads, and current version |
| [Installation](INSTALLATION.md) | Downloads, verification, first launch, and updates |
| [Data & Privacy](PRIVACY.md) | Local ledgers, backups, exchange-rate providers, and sensitive data |
| [Screenshots](SCREENSHOTS.md) | Official screenshots and fictional sample data |
| [Security policy](../SECURITY.md) | Private vulnerability reporting |
| [Code of conduct](../CODE_OF_CONDUCT.md) | Expectations for contributions and discussions |

## Development and releases

| Document | Contents |
| --- | --- |
| [Architecture](ARCHITECTURE.md) | SwiftUI / SwiftData, directory responsibilities, and persistence models |
| [Building](BUILDING.md) | XcodeGen, Universal builds, output paths, and key-helper constraints |
| [Changelog](../CHANGELOG.md) | Published version history |
| [Contributing](../CONTRIBUTING.md) | Bug reports, pull requests, and data protection |
| [Third-party notices](THIRD_PARTY_NOTICES.md) | Asset sources and component licensing |

## Where to start for common tasks

- **Transactions, accounts, reports, budgets, deposits, and loan calculations:** `ARCHITECTURE.md` → `Sources/Shared/` → the relevant modules under `Sources/Core/Finance/` or `Sources/Features/`.
- **SwiftData models, migration, or backups:** `PRIVACY.md` → `ARCHITECTURE.md` → `Sources/Shared/Models/` → `Sources/Core/Persistence/`. Never treat deletion of a real user's ledger as a default fix.
- **Exchange rates, menu bar, and quick conversion:** `ARCHITECTURE.md` → `Sources/Core/Exchange/` → `Sources/Features/Exchange/`.
- **UI, localization, and accessibility:** `Sources/Components/`, `Sources/Features/`, and `Resources/Localizable.xcstrings`. Check both appearances, layout, and keyboard behavior.
- **Application packaging and installation:** `BUILDING.md` → `INSTALLATION.md` → `scripts/build-macos.sh` → `.github/workflows/build.yml`.
- **Website and downloads:** `website/` → `scripts/check-site.py` → `.github/workflows/pages.yml`.

## Limits of automated validation

- `.github/workflows/build.yml` validates app builds, signatures, resources, and the stable Keychain helper on GitHub's macOS runners.
- `tests/FinanceSmoke.swift` is a standalone, lightweight **financial calculation smoke test** that compiles against two real calculation source files. It does not require a real ledger or launch the app. Its coverage is limited to selected precision and deposit-interest settlement edge cases.
- `pages.yml` checks website JavaScript, language switching, and static assets.
- These checks **do not replace** full SwiftData, UI, or real-environment end-to-end testing. A more complete suite should use a dedicated test target with fictional, isolated ledgers.

> **Critical boundary:** `Resources/FinTrackKeychainHelper` is an independently signed program with a fixed identity. Routine application refactoring must not re-sign it. See [BUILDING.md](BUILDING.md). Never commit live financial records, signing material, actual API keys, or local caches.
