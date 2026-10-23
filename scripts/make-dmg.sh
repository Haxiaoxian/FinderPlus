#!/bin/sh
# Builds FinderPlus and packages it as a DMG.
#
#   scripts/make-dmg.sh            arm64, ad-hoc signed (no Apple developer account needed)
#   scripts/make-dmg.sh universal  arm64 + x86_64 (phase 2)
#
# With DEVELOPMENT_TEAM set in Config/Local.xcconfig the regular Team-signed build is used instead.
set -eu
cd "$(dirname "$0")/.."

ARCHS_VALUE="arm64"; SUFFIX="arm64"
if [ "${1:-}" = "universal" ]; then ARCHS_VALUE="arm64 x86_64"; SUFFIX="universal"; fi

SIGNING="CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= FP_ENTITLEMENTS_VARIANT=-AdHoc"
if [ -f Config/Local.xcconfig ] && grep -Eq '^DEVELOPMENT_TEAM *= *[A-Z0-9]{10}' Config/Local.xcconfig; then
    SIGNING=""
fi

command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
xcodegen generate
# shellcheck disable=SC2086
xcodebuild -project FinderPlus.xcodeproj -scheme FinderPlus -configuration Release \
    -destination 'generic/platform=macOS' ARCHS="$ARCHS_VALUE" ONLY_ACTIVE_ARCH=NO \
    -derivedDataPath build $SIGNING build

APP="build/Build/Products/Release/FinderPlus.app"
codesign --verify --deep --strict "$APP"
echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/FinderPlus")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp docs/INSTALL.md "$STAGE/安装说明 Install.md"
mkdir -p dist
DMG="dist/FinderPlus-$VERSION-$SUFFIX.dmg"
rm -f "$DMG"
hdiutil create -volname "FinderPlus $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
echo "Created $DMG"
