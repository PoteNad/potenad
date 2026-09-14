#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

if [ "$#" -ne 1 ]; then
  printf 'Usage: %s VERSION\n' "$0" >&2
  exit 64
fi
VERSION="$1"
DIST="$PWD/dist"
STAGE="$DIST/staging"
APP="$STAGE/PoteNad.app"
ARCHIVE_NAME="PoteNad-$VERSION-macOS.zip"
DISK_IMAGE_NAME="PoteNad-$VERSION-macOS.dmg"
ARCHIVE="$DIST/$ARCHIVE_NAME"
DISK_IMAGE="$DIST/$DISK_IMAGE_NAME"

POTENAD_SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
export POTENAD_SDK_VERSION
if [ "${POTENAD_SDK_VERSION%%.*}" -lt 26 ]; then
  printf 'Releases require the macOS 26 SDK or newer (found %s).\n' "$POTENAD_SDK_VERSION" >&2
  exit 1
fi

rm -rf "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for ARCH in arm64 x86_64; do
  swift build -c release --arch "$ARCH" --scratch-path ".build-release-$ARCH"
done
lipo -create \
  .build-release-arm64/release/PoteNad \
  .build-release-x86_64/release/PoteNad \
  -output "$APP/Contents/MacOS/PoteNad"
for ARCH in arm64 x86_64; do
  BUILT_SDK="$(xcrun vtool -arch "$ARCH" -show-build "$APP/Contents/MacOS/PoteNad" | awk '$1 == "sdk" { print $2; exit }')"
  if [ "${BUILT_SDK%%.*}" -lt 26 ]; then
    printf 'The %s executable was linked against macOS SDK %s.\n' "$ARCH" "$BUILT_SDK" >&2
    exit 1
  fi
done
printf 'Linked against macOS SDK %s\n' "$POTENAD_SDK_VERSION"

xcrun actool Assets/PoteNad.icon \
  --compile "$APP/Contents/Resources" \
  --platform macosx \
  --minimum-deployment-target 13.0 \
  --app-icon PoteNad \
  --output-partial-info-plist "$DIST/PoteNad-icon-info.plist" >/dev/null
cp Assets/PoteNad.icns "$APP/Contents/Resources/PoteNad.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${GITHUB_RUN_NUMBER:-2}" "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

rm -f "$ARCHIVE" "$DISK_IMAGE" "$DIST/PoteNad-macOS.zip" "$DIST/PoteNad-macOS.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
cp "$ARCHIVE" "$DIST/PoteNad-macOS.zip"
(cd "$DIST" && shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256")
hdiutil create -volname PoteNad -srcfolder "$STAGE" -ov -format UDZO "$DISK_IMAGE"
cp "$DISK_IMAGE" "$DIST/PoteNad-macOS.dmg"
(cd "$DIST" && shasum -a 256 "$DISK_IMAGE_NAME" > "$DISK_IMAGE_NAME.sha256")
printf 'Created %s and %s\n' "$ARCHIVE" "$DISK_IMAGE"
