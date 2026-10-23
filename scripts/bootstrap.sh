#!/bin/sh
# Prepares a fresh checkout for development on macOS.
set -eu
cd "$(dirname "$0")/.."

if [ "$(uname -s)" != "Darwin" ]; then
    echo "FinderPlus builds on macOS only." >&2
    exit 1
fi

if ! xcode-select -p >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
    echo "Install Xcode 16 or newer from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app" >&2
    exit 1
fi
echo "Using $(xcodebuild -version | head -1) on $(uname -m)"

if ! command -v xcodegen >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        brew install xcodegen
    else
        echo "XcodeGen is required: https://github.com/yonaskolb/XcodeGen (brew install xcodegen)" >&2
        exit 1
    fi
fi

if [ ! -f Config/Local.xcconfig ]; then
    printf "Apple Developer Team ID (leave empty to fill in later): "
    read -r team || team=""
    sed "s/ABCDE12345/${team}/" Config/Local.xcconfig.example > Config/Local.xcconfig
    echo "Created Config/Local.xcconfig"
fi

xcodegen generate
echo "Done. Open FinderPlus.xcodeproj or run 'make run'."
