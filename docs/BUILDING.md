# Building FinTrack for macOS

## Requirements

- macOS. Minimum application runtime target: macOS 15.0.
- Xcode 27 series and command-line tools. The locally verified environment is Xcode 27.1; CI uses GitHub's Xcode 27 image.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), installable with Homebrew: `brew install xcodegen`.

The app uses Apple's system SDKs and has no third-party runtime packages to download. The Xcode project is generated from `Project/project.yml`; the generated `.xcodeproj` is not committed.

Xcode and the project's ad-hoc build do not require a paid Apple Developer membership. The build script invokes Xcode command-line tools, so the Xcode UI does not need to be opened. Official releases provide downloadable packages on GitHub Releases; manually installed versions replace the existing app.

## Release build

```sh
git clone https://github.com/Agumuzi/FinTrack.git
cd FinTrack
./scripts/build-macos.sh Release
```

Output: `.build/app/Build/Products/Release/FinTrack.app`. The default build includes arm64 and x86_64 and uses ad-hoc signing. A local build is **not** Developer ID signed or notarized. The script builds the app but does not launch it.

Set `FINTRACK_DERIVED_DATA_PATH` for a custom build directory. Source version settings are `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Project/project.yml`. For official installers, the corresponding GitHub Release tag is authoritative.

## Opening the project in Xcode

```sh
xcodegen generate --spec Project/project.yml --project Project
open Project/FinTrack.xcodeproj
```

Select the `FinTrack` scheme. A normal Debug Run uses an independent in-memory development ledger and simulated exchange rates; it does not access the production ledger, and this data does not survive process exit. A normally launched Release app uses the actual local store, so back up your ledger and never experiment against real everyday data.

The Bundle Identifier remains `dev.agumuzi.fintrack.macos`. Do not casually change the data models or storage paths: doing so may affect compatibility with existing ledgers.

## Product website

Website source is in `website/` and requires no installed dependencies. Preview it with any static web server, for example:

```sh
python3 -m http.server 8000 --directory website
```

Visit `http://localhost:8000/`. `scripts/check-site.py` validates local assets and anchors. GitHub Actions deploys merged changes to [GitHub Pages](https://agumuzi.github.io/FinTrack/). The site uses no front-end framework, third-party fonts, or analytics service.

## Independently signed Keychain helper

`Resources/FinTrackKeychainHelper` is a Universal signed executable with an independent component version. Its source is in `Sources/Core/Security/KeychainHelper/`, but it is not rebuilt as part of a routine main-app build. Normal releases reuse its **exact original bytes** to avoid repeated authorization prompts caused by changing executable fingerprints.

`scripts/verify-keychain-helper.py` verifies its source, both architecture signatures, and fixed digest. Builds and signing steps must not modify it. Security updates to this helper require a separate assessment of authorization migration; it must not be re-signed automatically with regular app versions.

The app and helper verify one another's fixed official identity. The helper accepts requests only through a private pipe from its parent application; API keys are not passed through arguments, logs, or temporary files. A redistributed fork must build and configure its **own identity**; it cannot use the official helper to access the official application's keys. Keep the production ledger, Bundle ID, and API-key service identifiers unchanged.

Build products and explicitly named validation copies require isolation parameters. Without them, the application refuses to open a ledger, protecting everyday data from accidental testing. For regular use, install the verified application in Applications.
