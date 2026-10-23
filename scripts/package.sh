#!/bin/sh
# Builds a Release app and zips it into dist/. Pass "universal" to include Intel (phase 2).
# Notarization (needs a Developer ID certificate) is documented in docs/RELEASING.md.
set -eu
cd "$(dirname "$0")/.."
ARCHS_VALUE="arm64"
SUFFIX="arm64"
if [ "${1:-}" = "universal" ]; then
    ARCHS_VALUE="arm64 x86_64"
    SUFFIX="universal"
fi

xcodegen generate
xcodebuild -project FinderPlus.xcodeproj -scheme FinderPlus -configuration Release \
    -destination 'generic/platform=macOS' ARCHS="$ARCHS_VALUE" ONLY_ACTIVE_ARCH=NO -derivedDataPath build build

APP="build/Build/Products/Release/FinderPlus.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/FinderPlus-$VERSION-$SUFFIX.zip"
echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/FinderPlus")"
echo "Created dist/FinderPlus-$VERSION-$SUFFIX.zip"
