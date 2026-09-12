#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release
APP="$PWD/build/PoteNad.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PoteNad "$APP/Contents/MacOS/PoteNad"
if ! xcrun actool Assets/PoteNad.icon \
  --compile "$APP/Contents/Resources" \
  --platform macosx \
  --minimum-deployment-target 13.0 \
  --app-icon PoteNad \
  --output-partial-info-plist "$PWD/build/PoteNad-icon-info.plist" >/dev/null; then
  rm -f "$APP/Contents/Resources/Assets.car"
fi
cp Assets/PoteNad.icns "$APP/Contents/Resources/PoteNad.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp Info.plist "$APP/Contents/Info.plist"
if [ -n "${POTENAD_VERSION:-}" ]; then
  plutil -replace CFBundleShortVersionString -string "$POTENAD_VERSION" "$APP/Contents/Info.plist"
fi
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
