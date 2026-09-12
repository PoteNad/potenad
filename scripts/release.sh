#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

if [ "$#" -ne 1 ]; then
  printf 'Usage: %s VERSION\n' "$0" >&2
  exit 64
fi
if [ -z "${SIGNING_IDENTITY:-}" ] || [ -z "${NOTARY_PROFILE:-}" ]; then
  printf 'SIGNING_IDENTITY and NOTARY_PROFILE are required.\n' >&2
  exit 64
fi

VERSION="$1"
DIST="$PWD/dist"
STAGE="$DIST/staging"
APP="$STAGE/PoteNad.app"
ARCHIVE="$DIST/PoteNad-$VERSION-macOS.zip"
DISK_IMAGE="$DIST/PoteNad-$VERSION-macOS.dmg"

rm -rf "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for ARCH in arm64 x86_64; do
  swift build -c release --arch "$ARCH" --scratch-path ".build-release-$ARCH"
done
lipo -create \
  .build-release-arm64/release/PoteNad \
  .build-release-x86_64/release/PoteNad \
  -output "$APP/Contents/MacOS/PoteNad"

if ! xcrun actool Assets/PoteNad.icon \
  --compile "$APP/Contents/Resources" \
  --platform macosx \
  --minimum-deployment-target 13.0 \
  --app-icon PoteNad \
  --output-partial-info-plist "$DIST/PoteNad-icon-info.plist" >/dev/null; then
  rm -f "$APP/Contents/Resources/Assets.car"
fi
cp Assets/PoteNad.icns "$APP/Contents/Resources/PoteNad.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${GITHUB_RUN_NUMBER:-2}" "$APP/Contents/Info.plist"

codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

rm -f "$ARCHIVE" "$DISK_IMAGE" "$DIST/PoteNad-macOS.zip" "$DIST/PoteNad-macOS.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

rm -f "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
cp "$ARCHIVE" "$DIST/PoteNad-macOS.zip"
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
hdiutil create -volname PoteNad -srcfolder "$STAGE" -ov -format UDZO "$DISK_IMAGE"
xcrun notarytool submit "$DISK_IMAGE" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DISK_IMAGE"
xcrun stapler validate "$DISK_IMAGE"
cp "$DISK_IMAGE" "$DIST/PoteNad-macOS.dmg"
shasum -a 256 "$DISK_IMAGE" > "$DISK_IMAGE.sha256"
printf 'Created %s and %s\n' "$ARCHIVE" "$DISK_IMAGE"
