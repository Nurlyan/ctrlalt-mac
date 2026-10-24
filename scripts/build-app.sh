#!/bin/bash
# Собирает build/CtrlAlt.app (release, arm64).
# Подпись: сертификат «CtrlAlt Local Signing» из связки ключей (см. scripts/make-signing-cert.sh),
# чтобы macOS сохраняла разрешения между версиями; без него — ad-hoc.
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

# Самоподписанный сертификат не доверенный, поэтому ищем его без -v (по SHA-1, не по имени).
IDENTITY="$(security find-identity -p codesigning 2>/dev/null | awk '/"CtrlAlt Local Signing"/ { print $2; exit }')"
if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" --identifier local.ctrlalt.CtrlAlt "$APP"
    SIGNED="CtrlAlt Local Signing"
else
    echo "Сертификат «CtrlAlt Local Signing» не найден — ad-hoc подпись (разрешения сбросятся после обновления)." >&2
    codesign --force --sign - --identifier local.ctrlalt.CtrlAlt "$APP"
    SIGNED="ad-hoc"
fi
codesign --verify "$APP"
echo "$APP ($VERSION, подпись: $SIGNED)"
