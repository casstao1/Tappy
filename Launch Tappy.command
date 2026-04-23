#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALLED_APP_PATH="$HOME/Applications/Tappy Preview.app"
WORKSPACE_APP_PATH="$SCRIPT_DIR/Tappy.app"

if [[ -d "$INSTALLED_APP_PATH" ]]; then
  APP_PATH="$INSTALLED_APP_PATH"
elif [[ -d "$WORKSPACE_APP_PATH" ]]; then
  APP_PATH="$WORKSPACE_APP_PATH"
else
  echo "Tappy.app was not found at:"
  echo "  $INSTALLED_APP_PATH"
  echo "or"
  echo "  $WORKSPACE_APP_PATH"
  echo
  echo "Run 'Install Tappy Preview.command' first."
  exit 1
fi

open -na "$APP_PATH"
