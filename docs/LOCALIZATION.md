# Localization module

The v1.5 candidate has integrated the reviewed KeyFreeze2 English and Simplified Chinese resources. It remains a local acceptance candidate, pending final review and release authorization. English is the String Catalog source language. `Resources/Localizable.xcstrings` is the sole compiled translation authority; JSON packs are interchange artifacts.

`LocalizationController` owns selection, effective language, system preference matching, and refresh notifications. `app_language=system` remains a selection rather than a detected language. First-run policy runs before the old initialization marker is created. Existing installations with no language key retain Chinese; explicit old values remain intact. Unsupported selections fall back to English without erasing the saved value. Traditional Chinese is not silently mapped to Simplified Chinese.

`L10n.text` resolves stable keys; `L10n.format` accepts typed `CVarArg` parameters and native String Catalog plurals. A locked snapshot allows worker-side error descriptions without reading standard preferences. Existing `UIStringKey` / `UIStringCatalogKeyResolver` mappings remain supported. Missing semantic keys log once and display a visible diagnostic during development. Missing target translations fall back to the compiled English resource.

Views with localized strings observe the same controller. The main window, command scene, independent menu host, and settings selector share it. Language changes clear `DateHelper` caches. They never replace a view with `.id(language)`, recreate a model container, or execute financial posting. Pending notification plans can be refreshed using their existing occurrence IDs; delivered messages and operation-message snapshots can retain their creation language.

`LocalizationRelease.json` controls selectable languages independently of draft `.lproj` resources. Its English/Chinese list is generated after resource validation. The release generator below refuses incomplete resources. Russian catalog payloads are retained for later review. A new verified locale requires resource import, manifest generation and a rebuild, with no language-selector Swift change. RTL and every future grammatical system are not claimed as already validated.

`LocalizationLegacyAliases.json` maps explicitly identified built-in legacy identities to stable resource keys. `L10n.builtIn` is only used for those identities, never arbitrary user names. Chinese enum values, sort preference bytes, CSV aliases, and receipt markers remain compatibility data. `MacLegacyCategoryIdentity` permanently recognizes the old Chinese Loan/Deposit aliases independently of current translations, without rewriting stored names. Workspace navigation accepts old Chinese and stable English IDs; writes retain old preference bytes to support rollback. Record sorting follows the same policy. Financial display precision/grouping and explicit date formats remain independent of the UI language.

The key suffixes introduced during extraction identify frozen copy sites; never regenerate a key when editing translations. Keep context-specific financial meanings separate. Preserve existing stale catalog records and draft Russian translations.

## Resource workflow

```bash
python3 scripts/localization-pack.py export --locale en --native-name English --output /tmp/en.base.json
python3 scripts/localization-pack.py assemble --base /tmp/en.base.json --output /tmp/en.complete.json /path/to/translated-batch-01.json /path/to/translated-batch-02.json
python3 scripts/localization-pack.py validate /tmp/en.complete.json
python3 scripts/localization-pack.py import /tmp/en.complete.json
python3 scripts/localization-pack.py coverage --locale en
python3 scripts/localization-pack.py coverage --locale zh-Hans
python3 scripts/localization-pack.py release-manifest --language en=English --language 'zh-Hans=简体中文' --output Resources/LocalizationRelease.json
```

The original empty-key catalog sentinel is preserved and excluded from translation work; all other empty values are rejected.

Import rejects duplicate/unknown/missing keys, unreviewed or empty values, unsafe format conversions, parameter mismatches and invalid native variants. Positional reordering and target plural categories are supported. Validation finishes before mutation, backups go to `Local/Localization/Backups`, and writes use atomic replacement. Repeated identical imports do not create another change or backup. Never place backup catalogs inside `Resources`.

Release requires completed English/Chinese resources, a successful generated manifest, isolated accounting/CSV/backup regressions and visual/accessibility verification of actual translations. A successful build alone is insufficient. Private validation commands and fixtures are excluded from the public application target.


KeyFreeze2’s 3,321 keys are retained without renaming or deletion. Additional `menu.native.*` keys cover AppKit-generated menu titles that were outside the original source extraction. Native menu updates change titles only, preserving selectors, shortcuts and delegates. Restore confirmation reads its token and prompt from shared language resources (`RESTORE` in English, `恢复账本` in Simplified Chinese). Switching language invalidates a previously entered token rather than replacing it automatically. Clear-ledger confirmation remains `DELETE`.

Settings rows use shared constrained label/control columns with vertical fallbacks. Native table headers resolve the same localization resources as SwiftUI columns and measure localized header widths. Leading icons are centered against the full wrapped text block.

Writing and terminology follow [LOCALIZATION_STYLE.md](LOCALIZATION_STYLE.md). Target-language idioms and established terms take precedence over literal Chinese phrasing. The v1.5 deposit interest overview adds scoped `deposit.earnings.*` keys without renaming any KeyFreeze2 entry.
