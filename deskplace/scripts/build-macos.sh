#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DeskPlace"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/mac/Info.plist" 2>/dev/null || echo '0.1.0')"
BUILD="$ROOT/dist"
APP="$BUILD/$APP_NAME.app"
STAGE="$BUILD/dmg-stage"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script builds a macOS app and DMG; run it on a Mac." >&2
  exit 1
fi

rm -rf "$APP" "$STAGE" "$BUILD/$APP_NAME-$VERSION-arm64.dmg" "$BUILD/$APP_NAME-$VERSION-arm64.pkg"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/app" "$STAGE"

SDK_PATH="$(xcrun --sdk macosx26.5 --show-sdk-path)"
swiftc -O -sdk "$SDK_PATH" -target arm64-apple-macosx13.0 \
  -framework AppKit -framework WebKit -framework ServiceManagement \
  "$ROOT/mac/DeskPlace.swift" -o "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/mac/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp -R "$ROOT/src/." "$APP/Contents/Resources/app/"
codesign --force --deep --sign - "$APP"

# Keep the app bundle intact for both the DMG and component package. A root
# package can flatten or relocate bundle contents depending on installer metadata.
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
pkgbuild --component "$APP" --install-location "/Applications" \
  --identifier com.deskplace.app --version "$VERSION" "$BUILD/$APP_NAME-$VERSION-arm64.pkg"
if hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO \
  "$BUILD/$APP_NAME-$VERSION-arm64.dmg"; then
  echo "Created: $BUILD/$APP_NAME-$VERSION-arm64.dmg"
else
  echo "DMG creation was blocked by the current environment; the installable package is ready:"
  echo "$BUILD/$APP_NAME-$VERSION-arm64.pkg"
fi
rm -rf "$STAGE"
