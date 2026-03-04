#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_FILE="$ROOT_DIR/DaVinci_Image_AI_CleanRoom.lua"
TARGET_FILE="${1:-~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/DaVinci Banana_v000/DaVinci Banana/DaVinci Banana.lua}"

if [[ ! -f "$SRC_FILE" ]]; then
  echo "Missing source file: $SRC_FILE" >&2
  exit 1
fi

cp "$SRC_FILE" "$TARGET_FILE"
echo "Deployed:"
echo "  source: $SRC_FILE"
echo "  target: $TARGET_FILE"
