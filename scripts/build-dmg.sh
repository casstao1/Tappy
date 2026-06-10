#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Tappy"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-$ROOT_DIR/build/DerivedData}"
STAGING_DIR="${STAGING_DIR:-$ROOT_DIR/build/dmg-staging}"
DMG_PATH="${1:-$ROOT_DIR/build/Tappy.dmg}"
SIGN_APP="${SIGN_APP:-0}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-${DEVELOPMENT_TEAM:-}}"

rm -rf "$DERIVED_DATA_DIR" "$STAGING_DIR" "$DMG_PATH" "$DMG_PATH.sha256"
mkdir -p "$(dirname "$DMG_PATH")" "$STAGING_DIR"

if [[ "$SIGN_APP" == "1" || "$SIGN_APP" == "true" ]]; then
  if [[ -z "$APPLE_TEAM_ID" ]]; then
    echo "APPLE_TEAM_ID or DEVELOPMENT_TEAM is required when SIGN_APP=1" >&2
    exit 1
  fi

  signing_args=(
    CODE_SIGNING_ALLOWED=YES
    CODE_SIGNING_REQUIRED=YES
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
    CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY"
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID"
    ENABLE_HARDENED_RUNTIME=YES
    OTHER_CODE_SIGN_FLAGS="--timestamp"
  )
else
  signing_args=(
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGN_IDENTITY=""
  )
fi

xcodebuild \
  -project "$ROOT_DIR/Tappy.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  "${signing_args[@]}" \
  build

APP_PATH="$(find "$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION" -maxdepth 1 -type d -name "$APP_NAME.app" -print -quit)"

if [[ -z "$APP_PATH" ]]; then
  echo "Could not find $APP_NAME.app in $DERIVED_DATA_DIR/Build/Products/$CONFIGURATION" >&2
  exit 1
fi

if [[ "$SIGN_APP" == "1" || "$SIGN_APP" == "true" ]]; then
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
fi

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ "$SIGN_APP" == "1" || "$SIGN_APP" == "true" ]]; then
  codesign --force --sign "$CODE_SIGN_IDENTITY" --timestamp "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi

shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"

echo "Created $DMG_PATH"
echo "Created $DMG_PATH.sha256"
