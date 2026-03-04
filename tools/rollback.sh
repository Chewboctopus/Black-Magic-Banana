#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_FILE="$ROOT_DIR/DaVinci_Image_AI_CleanRoom.lua"
REF="${1:-HEAD~1}"

git -C "$ROOT_DIR" rev-parse --verify "$REF" >/dev/null
git -C "$ROOT_DIR" checkout "$REF" -- "$SRC_FILE"

echo "Rolled back $SRC_FILE to $REF"
echo "Run ./tools/deploy.sh to push it into Resolve."
