#!/bin/bash
# Собирает build/CtrlAlt-<версия>.dmg: приложение и ярлык «Программы» для перетаскивания.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
VERSION="$(cat VERSION)"

STAGE=build/dmg
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R build/CtrlAlt.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="build/CtrlAlt-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "CtrlAlt" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "$DMG"
