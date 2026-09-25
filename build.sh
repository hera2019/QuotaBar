#!/bin/bash
# Builds build/QuotaBar.app and a shareable build/QuotaBar.zip
set -euo pipefail
cd "$(dirname "$0")"

# Universal binary: runs on Apple silicon and Intel.
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/QuotaBar"

APP=build/QuotaBar.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/QuotaBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
xattr -cr "$APP"
codesign --force --sign - "$APP"

# Zip without resource forks / extended attributes (no ._ files for other Macs).
ditto -c -k --norsrc --noextattr --noacl --keepParent "$APP" build/QuotaBar.zip
echo "Done: $APP"
