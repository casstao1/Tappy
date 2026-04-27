#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_APP_PATH="$SCRIPT_DIR/Tappy.app"

if [[ -d "$WORKSPACE_APP_PATH" ]]; then
  APP_PATH="$WORKSPACE_APP_PATH"
else
  echo "Tappy.app was not found at:"
  echo "  $WORKSPACE_APP_PATH"
  echo
  echo "Run 'Rebuild Tappy.command' first."
  exit 1
fi

open -na "$APP_PATH"
