#!/bin/zsh
set -euo pipefail

ROOT="/Users/castao/Desktop/KeyboardSoundApp"
DERIVED_DATA="/tmp/TappyStableDerivedData"
CONFIGURATION="${1:-Debug}"
DEST_PARENT="/Applications"

if [[ ! -w "$DEST_PARENT" ]]; then
  DEST_PARENT="$HOME/Applications"
  mkdir -p "$DEST_PARENT"
fi

DEST_APP="$DEST_PARENT/Tappy.app"
BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/Tappy.app"

echo "Building Tappy ($CONFIGURATION)..."
xcodebuild \
  -project "$ROOT/Tappy.xcodeproj" \
  -scheme Tappy \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  build

echo "Installing stable app at $DEST_APP..."
pkill -x Tappy 2>/dev/null || true
rm -rf "$DEST_APP"
ditto "$BUILT_APP" "$DEST_APP"
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true

echo "Opening stable app..."
open "$DEST_APP"

cat <<EOF

Stable Tappy is running from:
$DEST_APP

If Input Monitoring still looks stuck:
1. Quit Tappy.
2. Run: $ROOT/reset-tappy-permissions.command
3. Reopen Tappy from $DEST_APP and grant Input Monitoring again.

This is more representative than running from Xcode/DerivedData.
TestFlight is still the best final validation before resubmission.
EOF
