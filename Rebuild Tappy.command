#!/bin/zsh
#
# Tappy — Rebuild & Launch
# Double-click this file to rebuild Tappy from source, reinstall the
# preview app at ~/Applications/Tappy Preview.app, and open a fresh
# instance so any Input Monitoring / entitlements changes take effect.
#

set -euo pipefail

APP_ROOT="/Users/castao/Desktop/KeyboardSoundApp"
PROJECT_PATH="$APP_ROOT/Tappy.xcodeproj"
DERIVED_DATA_PATH="$APP_ROOT/.preview-build"
INSTALL_DIR="$HOME/Applications"
INSTALL_PATH="$INSTALL_DIR/Tappy Preview.app"
BUILT_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/Tappy.app"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Tappy — Rebuild & Launch"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "!! Tappy project not found at:"
    echo "   $PROJECT_PATH"
    echo ""
    echo "   Open this file in a text editor and update APP_ROOT near the top."
    echo ""
    exit 1
fi

if pgrep -x "Tappy" >/dev/null 2>&1; then
    echo "Closing running Tappy instances..."
    killall Tappy >/dev/null 2>&1 || true
    sleep 1
fi

mkdir -p "$INSTALL_DIR"

echo "Building Tappy Release..."
xcodebuild build \
  -project "$PROJECT_PATH" \
  -scheme Tappy \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH"

if [[ ! -d "$BUILT_APP_PATH" ]]; then
    echo ""
    echo "!! Built app was not found at:"
    echo "   $BUILT_APP_PATH"
    echo ""
    exit 1
fi

echo ""
echo "Installing preview app to:"
echo "  $INSTALL_PATH"
ditto "$BUILT_APP_PATH" "$INSTALL_PATH"

echo ""
echo "Launching fresh Tappy Preview..."
open -na "$INSTALL_PATH"

echo ""
echo "✓ Tappy rebuilt and launched."
echo ""
echo "This Terminal window is safe to close."
