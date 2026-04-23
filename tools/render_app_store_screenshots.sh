#!/bin/zsh
set -euo pipefail

ROOT="/Users/castao/Desktop/KeyboardSoundApp"
SCREEN_DIR="$ROOT/docs/app-store/screenshots"
OUT_DIR="$SCREEN_DIR/rendered"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

mkdir -p "$OUT_DIR"

for html in \
  "$SCREEN_DIR/shot-01.html" \
  "$SCREEN_DIR/shot-02.html" \
  "$SCREEN_DIR/shot-03.html" \
  "$SCREEN_DIR/shot-04.html" \
  "$SCREEN_DIR/shot-05.html"
do
  name="$(basename "$html" .html).png"
  "$CHROME" \
    --headless=new \
    --disable-gpu \
    --hide-scrollbars \
    --force-device-scale-factor=1 \
    --window-size=1440,900 \
    --screenshot="$OUT_DIR/$name" \
    "file://$html"
done

echo "Rendered screenshots to:"
echo "$OUT_DIR"
