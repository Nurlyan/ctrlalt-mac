#!/bin/bash
# Собирает build/CtrlAlt.app (release, arm64, локальная ad-hoc подпись).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
swift build -c release --product CtrlAlt
BIN="$(swift build -c release --show-bin-path)/CtrlAlt"

APP=build/CtrlAlt.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CtrlAlt"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --identifier local.ctrlalt.CtrlAlt "$APP"
codesign --verify "$APP"
echo "$APP ($VERSION)"
