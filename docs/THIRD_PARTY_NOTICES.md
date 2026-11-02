# Third-Party Components, Icons, and Asset Notices

This document records the provenance and reviewed permitted uses of resources included with FinTrack. It does not replace any third party's license terms or grant additional rights to third-party assets. Last asset review: **2026-10-23**. Project license status updated: **2026-11-02**.

## Project license

Original source code in this repository that the maintainer has the right to license is currently available under the [MIT License](../LICENSE). MIT permits use, modification, redistribution, and commercial use subject to its notice requirements. The corresponding copy included with the application is `Resources/Legal/LICENSE.txt`.

Original logos, app icons, promotional artwork, and screenshots are covered separately by the [Brand & Visual Assets notice](../ASSETS-LICENSE.md); publishing them in the repository does not grant independent reuse rights. Earlier releases distributed under different terms retain the rights they previously granted. An older MIT license text is archived in [Legacy MIT License](LEGACY_MIT_LICENSE.md).

Third-party assets and Apple platform components remain governed by their respective terms. This project does not relicense third-party trademarks, fonts, or system artwork.

## Platform components and code dependencies

The application uses Apple-provided system SDKs, including SwiftUI, SwiftData, AppKit, Foundation, Charts, Combine, CryptoKit, and Security. The app project does not declare runtime dependencies managed by Swift Package Manager, CocoaPods, or Carthage, and no separately bundled third-party source-code library or license has been identified.

Apple's applicable agreements govern its SDKs; no rights are granted to them by this document. Xcode and XcodeGen are build tools, not packaged runtime components, and their own terms still apply.

## System icons and fonts

FinTrack uses SF Symbols and system fonts through platform APIs. Apple fonts and the standalone SF Symbols library are not redistributed as app resources. Certain SF Symbols have additional restrictions on use, modification, and trademarks: for example, SF Symbols must not be used directly as an app icon, logo, or other trademark. See [Apple's Human Interface Guidelines for SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols) and the [SF Symbols website](https://developer.apple.com/sf-symbols/).

The product website uses a system-font stack. The presence of system icons and fonts in actual app screenshots does not grant permission to extract and reuse them separately.

## Country and regional flags in currency selection

- Files: `Resources/Flags/flag-*.png`.
- Sources: [Flagcdn](https://flagcdn.com/) / [Flagpedia](https://flagpedia.net/).
- Included flags: United States, Russia, China, European Union, United Kingdom, Japan, Switzerland, and Hong Kong.

Flagcdn describes these images as based on vector files from Wikimedia Commons. The intellectual-property section of [Flagpedia's terms](https://flagpedia.net/terms) states that its flag images are in the public domain and may be freely used. This statement concerns the flag images, not the site's other text, design, or code.

Original source URLs are recorded in `Resources/Flags/sources.json`. The flags identify currencies or regions and do not imply any official affiliation or endorsement.

## FinTrack icons and screenshots

FinTrack's original app icon and brand artwork are not licensed under the source-code MIT license and must not be extracted for use in unrelated projects without separate permission, except where law permits. Original interface source code is licensed under the current [MIT License](../LICENSE); prior releases retain the rights granted under their applicable terms.

Screenshots come from the actual application using a specially prepared fictional ledger. They do not represent real personal financial data. Apple system symbols, fonts, and other third-party content visible in screenshots remain subject to their owners' rights. Users supply bank images themselves and must have the necessary rights to use them.

For future assets, record the source and applicable license or evidence of permission. Publicly downloadable or viewable material is not automatically copyright-free or open source.

## GitHub mark

The GitHub mark is provided by [Primer Octicons](https://github.com/primer/octicons) under the MIT license. Copyright (c) 2026 GitHub Inc. The full license accompanies the app. The mark identifies GitHub links and does not imply endorsement.
