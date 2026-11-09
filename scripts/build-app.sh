#!/bin/bash
# Builds build/Parchi.app. Needs only the Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME=Parchi
APP="build/$NAME.app"

if [ ! -f Resources/AppIcon.icns ]; then
    WORK="$(mktemp -d)"
    trap 'rm -rf "$WORK"' EXIT
    swift scripts/make-icon.swift "$WORK/icon.png"
    SET="$WORK/AppIcon.iconset"
    mkdir "$SET"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$WORK/icon.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z "$double" "$double" "$WORK/icon.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$SET" -o Resources/AppIcon.icns
fi

swift build -c release --product "$NAME"
BIN_DIR="$(swift build -c release --product "$NAME" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$NAME" "$APP/Contents/MacOS/$NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/THIRD_PARTY_NOTICES.txt "$APP/Contents/Resources/THIRD_PARTY_NOTICES.txt"
codesign --force --sign - --timestamp=none "$APP"

echo "Built $APP"
