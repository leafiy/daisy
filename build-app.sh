#!/bin/sh
# Builds Daisy.app in an ignored, Spotlight-excluded build directory.
# Requires macOS with the Xcode command line tools (xcode-select --install).
# The flow lives in ../leafiy-ui/scripts/macos-app-build-common.sh (ADR-0012);
# this file only declares the app. UNIVERSAL=1 builds one app for both CPUs.
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"

APP_SLUG="daisy"
APP_EXECUTABLE_PRODUCT="daisytranslator"
APP_ICON_SOURCE="daisy.png"
MENU_ICON_SOURCE="Sources/DaisyTranslator/Resources/Icons/daisy.png"
# Icon sources shipped in the target resources are not needed at run time.
APP_RESOURCE_PRUNE="DaisyTranslator_DaisyTranslator.bundle/Daisy.icns DaisyTranslator_DaisyTranslator.bundle/daisy-app-icon.png DaisyTranslator_DaisyTranslator.bundle/daisy-menubar-template.png DaisyTranslator_DaisyTranslator.bundle/daisy-source.webp"
BUILD_COMMON="../leafiy-ui/scripts/macos-app-build-common.sh"
[ -r "$BUILD_COMMON" ] || { echo "error: shared macOS build policy not found: $BUILD_COMMON"; exit 1; }
. "$BUILD_COMMON"
leafiy_build_app_main "$@"
