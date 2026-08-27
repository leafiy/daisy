#!/bin/sh
# Releases Daisy: two notarized DMGs, the leafiy.com update feed, GitHub source
# and release, optional Gitea mirror. The flow, every environment knob, and the
# usage lines live in ../leafiy-ui/scripts/macos-app-release-common.sh
# (ADR-0012); this file only declares the app.
#   sh release.sh --prepare [v1.2.3]   sh release.sh [v1.2.3]   PUSH_SOURCE=0 PUBLISH_TO_LEAFIY=0 PUBLISH_TO_GITHUB=0 sh release.sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"

APP_SLUG="daisy"
APP_EXECUTABLE_PRODUCT="daisytranslator"
APP_ICON_SOURCE="daisy.png"
MENU_ICON_SOURCE="Sources/DaisyTranslator/Resources/Icons/daisy.png"
# Icon sources shipped in the target resources are not needed at run time.
APP_RESOURCE_PRUNE="DaisyTranslator_DaisyTranslator.bundle/Daisy.icns DaisyTranslator_DaisyTranslator.bundle/daisy-app-icon.png DaisyTranslator_DaisyTranslator.bundle/daisy-menubar-template.png DaisyTranslator_DaisyTranslator.bundle/daisy-source.webp"
GITEA_RELEASE_SUMMARY="Native macOS translation helper for menu bar and clipboard workflows."
RELEASE_COMMON="../leafiy-ui/scripts/macos-app-release-common.sh"
[ -r "$RELEASE_COMMON" ] || { echo "error: shared release flow not found: $RELEASE_COMMON"; exit 1; }
. "$RELEASE_COMMON"
leafiy_release_main "$@"
