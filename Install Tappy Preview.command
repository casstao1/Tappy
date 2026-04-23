#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_PATH="$SCRIPT_DIR/Tappy.xcodeproj"
DERIVED_DATA_PATH="$SCRIPT_DIR/.preview-build"
INSTALL_DIR="$HOME/Applications"
INSTALL_PATH="$INSTALL_DIR/Tappy Preview.app"
BUILT_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/Tappy.app"

mkdir -p "$INSTALL_DIR"

echo "Building Tappy Release preview..."
xcodebuild build \
  -project "$PROJECT_PATH" \
  -scheme Tappy \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH"

if [[ ! -d "$BUILT_APP_PATH" ]]; then
  echo "Built app was not found at:"
  echo "  $BUILT_APP_PATH"
  exit 1
fi

if pgrep -x "Tappy" >/dev/null 2>&1; then
  echo "Closing running Tappy instances..."
  killall Tappy >/dev/null 2>&1 || true
  sleep 1
fi

echo "Installing preview app to:"
echo "  $INSTALL_PATH"
ditto "$BUILT_APP_PATH" "$INSTALL_PATH"

echo "Opening installed preview..."
open -na "$INSTALL_PATH"

echo
echo "Use this installed copy for Input Monitoring testing:"
echo "  $INSTALL_PATH"
