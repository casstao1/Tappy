#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
PYTHON="/Users/castao/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"

cd "$ROOT_DIR"
"$PYTHON" "$SCRIPT_DIR/generate_scenes.py"
"$PYTHON" "$SCRIPT_DIR/build_audio.py"
swiftc "$SCRIPT_DIR/render_video.swift" \
  -o "$SCRIPT_DIR/render_video" \
  -framework AVFoundation \
  -framework CoreImage \
  -framework CoreMedia \
  -framework CoreVideo
"$SCRIPT_DIR/render_video" \
  "$SCRIPT_DIR/scenes" \
  "$SCRIPT_DIR/Tappy-Promo-Audio.wav" \
  "$SCRIPT_DIR/Tappy-Promo-Vertical.mp4"
