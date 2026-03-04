#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_FILE="$ROOT_DIR/DaVinci_Image_AI_CleanRoom.lua"
SNAP_DIR="$ROOT_DIR/.snapshots"
STAMP="$(date +%Y%m%d_%H%M%S)"
SNAP_FILE="$SNAP_DIR/DaVinci_Image_AI_CleanRoom_${STAMP}.lua"
MSG="${1:-savepoint ${STAMP}}"

if [[ ! -f "$SRC_FILE" ]]; then
  echo "Missing source file: $SRC_FILE" >&2
  exit 1
fi

mkdir -p "$SNAP_DIR"
cp "$SRC_FILE" "$SNAP_FILE"

git -C "$ROOT_DIR" add -A

if git -C "$ROOT_DIR" diff --cached --quiet; then
  echo "No changes to commit."
else
  git -C "$ROOT_DIR" commit -m "$MSG"
fi

echo "Snapshot saved: $SNAP_FILE"
