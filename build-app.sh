#!/bin/sh
# Builds Daisy.app in an ignored, Spotlight-excluded build directory.
# Requires macOS with the Xcode command line tools (xcode-select --install).
set -eu
cd "$(dirname "$0")"

TEAM_ID="${TEAM_ID:-Q478GZN2AV}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

APP_ICON_SOURCE="daisy.png"
MENU_ICON_SOURCE="Sources/DaisyTranslator/Resources/Icons/daisy.png"
ICON_COMPILER="../leafiy-ui/scripts/compile-macos-app-icon.sh"
[ -f "$APP_ICON_SOURCE" ] || { echo "error: $APP_ICON_SOURCE not found"; exit 1; }
[ -f "$MENU_ICON_SOURCE" ] || { echo "error: $MENU_ICON_SOURCE not found"; exit 1; }
[ -x "$ICON_COMPILER" ] || { echo "error: shared icon compiler not found: $ICON_COMPILER"; exit 1; }

# Native build for this Mac's CPU by default (works on Intel and Apple
# Silicon alike). UNIVERSAL=1 sh build-app.sh builds one app for both.
ARCH_FLAGS=""
if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCH_FLAGS="--arch arm64 --arch x86_64"
fi

SCRATCH_PATH="${SCRATCH_PATH:-"${TMPDIR%/}/leafiy-swift-builds/daisy"}"
swift build -c release $ARCH_FLAGS --scratch-path "$SCRATCH_PATH"
BIN_DIR=$(swift build -c release $ARCH_FLAGS --scratch-path "$SCRATCH_PATH" --show-bin-path)
BUILD_ROOT="${BUILD_ROOT:-"$PWD/build.noindex"}"
APP_OUTPUT_DIR="${APP_OUTPUT_DIR:-"$BUILD_ROOT/app"}"
mkdir -p "$BUILD_ROOT"

compile_app_icon_assets() { # $1 = source png, $2 = destination resources dir
    "$ICON_COMPILER" "$1" "$2" "${TMPDIR%/}/leafiy-icon-builds/daisy"
}

APP="$APP_OUTPUT_DIR/Daisy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp "$BIN_DIR/daisytranslator" "$APP/Contents/MacOS/Daisy"
printf 'APPL????' > "$APP/Contents/PkgInfo"
compile_app_icon_assets "$APP_ICON_SOURCE" "$APP/Contents/Resources"
cp "$MENU_ICON_SOURCE" "$APP/Contents/Resources/daisy.png"
if [ -d "$BIN_DIR/DaisyTranslator_DaisyTranslator.bundle" ]; then
    cp -R "$BIN_DIR/DaisyTranslator_DaisyTranslator.bundle" "$APP/Contents/Resources/"
    rm -f "$APP/Contents/Resources/DaisyTranslator_DaisyTranslator.bundle/Daisy.icns" \
        "$APP/Contents/Resources/DaisyTranslator_DaisyTranslator.bundle/daisy-app-icon.png" \
        "$APP/Contents/Resources/DaisyTranslator_DaisyTranslator.bundle/daisy-menubar-template.png" \
        "$APP/Contents/Resources/DaisyTranslator_DaisyTranslator.bundle/daisy-source.webp"
fi
if [ -d "$BIN_DIR/LeafiyUI_LeafiyUI.bundle" ]; then
    cp -R "$BIN_DIR/LeafiyUI_LeafiyUI.bundle" "$APP/Contents/Resources/"
fi

[ -f "$APP/Contents/Resources/AppIcon.icns" ] || { echo "error: AppIcon.icns is missing"; exit 1; }
[ -f "$APP/Contents/Resources/Assets.car" ] || { echo "error: Assets.car is missing"; exit 1; }
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$APP/Contents/Info.plist")" = "AppIcon" ] || { echo "error: CFBundleIconName must be AppIcon"; exit 1; }
cmp -s "$MENU_ICON_SOURCE" "$APP/Contents/Resources/daisy.png" || { echo "error: menu bar icon does not match $MENU_ICON_SOURCE"; exit 1; }

if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning \
        | sed -n "s/.*\"\(Developer ID Application: .*($TEAM_ID)\)\".*/\1/p" \
        | head -n 1)
fi

if [ -n "$SIGN_IDENTITY" ]; then
    # Hardened runtime + secure timestamp are required for notarized distribution.
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    echo "warning: Developer ID Application certificate for team $TEAM_ID not found; using ad-hoc signature"
    codesign --force --sign - "$APP"
fi

echo "Done: $APP"
