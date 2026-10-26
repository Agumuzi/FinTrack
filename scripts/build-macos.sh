#!/bin/bash
# Build the application from the public source tree; never launches a ledger.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
configuration="${1:-Release}"
case "$configuration" in Debug|Release) ;; *) echo 'Usage: scripts/build-macos.sh [Debug|Release]' >&2; exit 2;; esac
command -v xcodegen >/dev/null || { echo 'Install XcodeGen before building.' >&2; exit 1; }
python3 scripts/verify-keychain-helper.py
xcodegen generate --spec Project/project.yml --project Project
xcodebuild build -project Project/FinTrack.xcodeproj -scheme FinTrack \
  -configuration "$configuration" -destination 'generic/platform=macOS' \
  -derivedDataPath "${FINTRACK_DERIVED_DATA_PATH:-$root/.build/app}" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=YES
