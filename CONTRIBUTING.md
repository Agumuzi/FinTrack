# Contributing to FinTrack

Thank you for helping improve FinTrack. Original source code that the maintainer has the rights to license is published under the [MIT License](LICENSE), including permission for commercial use. The logo, app icons, and original visual assets are covered separately by the [Brand & Visual Assets notice](ASSETS-LICENSE.md). Third-party assets and platform components follow their respective terms; see [Third-party notices](docs/THIRD_PARTY_NOTICES.md). Please read the relevant documentation before contributing.

By submitting code or artwork, you represent that you have the right to provide it and agree that code contributions may be distributed under the project's MIT license. MIT allows commercial use, while contributors retain their own copyrights; opening a pull request does not automatically transfer ownership. Relicensing contributions under different terms may require permission from the relevant rights holders.

## Reporting issues

Use [GitHub Issues](https://github.com/Agumuzi/FinTrack/issues) and include the application version, macOS version, device architecture, steps to reproduce, expected behavior, and actual behavior. Screenshots can help with UI issues; for calculation bugs, provide the smallest useful example with fictional values.

**Never upload** an actual ledger, native backup, bank or account details, API keys, or credentials appearing in logs. Redact personal information from screenshots. For security or privacy vulnerabilities, use [private vulnerability reporting](https://github.com/Agumuzi/FinTrack/security/advisories/new), not a public issue.

## Proposing changes

Discuss the scope of major features or interface redesigns in an issue first. Keep changes focused; do not combine unrelated code formatting and business-logic changes.

1. Follow the [build guide](docs/BUILDING.md) to verify compilation.
2. Test with an isolated fictional ledger, including saving, quitting/relaunching, and relevant calculations.
3. Explain compatibility and migration effects when modifying models, the Bundle Identifier, or persistence settings. Database deletion is not an acceptable default repair strategy.
4. Describe the issue, changes, test results, and validation gaps in the pull request. Provide provenance and licensing evidence for new artwork.

Installers are distributed through Releases. Do not commit local caches, real financial records, signing materials, or copied installers.
