#!/bin/sh
# Builds Daisy.app next to this script.
# Requires macOS with the Xcode command line tools (xcode-select --install).
set -eu
cd "$(dirname "$0")"

# All Leafiy apps build against the sibling leafiy-ui checkout; a stale one
# causes confusing "cannot find X in scope" compile errors.
UI_DIR="../leafiy-ui"
[ -d "$UI_DIR" ] || { echo "error: $UI_DIR not found — clone leafiy-ui next to this repo" >&2; exit 1; }
if git -C "$UI_DIR" fetch --quiet origin main 2>/dev/null; then
    if ! git -C "$UI_DIR" merge-base --is-ancestor "$(git -C "$UI_DIR" rev-parse origin/main)" "$(git -C "$UI_DIR" rev-parse HEAD)"; then
        echo "error: $UI_DIR is behind origin/main — run: git -C $UI_DIR pull" >&2
        exit 1
    fi
fi

TEAM_ID="${TEAM_ID:-Q478GZN2AV}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

[ -f daisy.png ] || { echo "error: daisy.png not found"; exit 1; }

# Native build for this Mac's CPU by default (works on Intel and Apple
# Silicon alike). UNIVERSAL=1 sh build-app.sh builds one app for both.
ARCH_FLAGS=""
if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCH_FLAGS="--arch arm64 --arch x86_64"
fi

swift build -c release $ARCH_FLAGS
BIN_DIR=$(swift build -c release $ARCH_FLAGS --show-bin-path)

make_icns() { # $1 = source png, $2 = destination .icns path
    src="$1"
    dest="$2"
    iconset="Daisy.iconset"
    rm -rf "$iconset"
    mkdir -p "$iconset"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$src" --out "$iconset/icon_${size}x${size}.png" >/dev/null
        sips -z "$((size * 2))" "$((size * 2))" "$src" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$iconset" -o "$dest"
    rm -rf "$iconset"
}

APP=Daisy.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp "$BIN_DIR/daisytranslator" "$APP/Contents/MacOS/Daisy"
printf 'APPL????' > "$APP/Contents/PkgInfo"
make_icns daisy.png "$APP/Contents/Resources/Daisy.icns"
if [ -d "$BIN_DIR/DaisyTranslator_DaisyTranslator.bundle" ]; then
    cp -R "$BIN_DIR/DaisyTranslator_DaisyTranslator.bundle" "$APP/Contents/Resources/"
    rm -f "$APP/Contents/Resources/DaisyTranslator_DaisyTranslator.bundle/Daisy.icns" \
        "$APP/Contents/Resources/DaisyTranslator_DaisyTranslator.bundle/daisy-app-icon.png" \
        "$APP/Contents/Resources/DaisyTranslator_DaisyTranslator.bundle/daisy-menubar-template.png" \
        "$APP/Contents/Resources/DaisyTranslator_DaisyTranslator.bundle/daisy-source.webp"
fi

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

echo "Done: $(pwd)/$APP"
