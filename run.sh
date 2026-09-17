#!/usr/bin/env bash
# Launch VR Viewer with a local Godot binary or an installed one.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

pick() {
  local c
  for c in "$@"; do
    if [[ -x "$c" ]]; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

GODOT=""
# Portable next to project
if GODOT="$(pick \
  "$ROOT/Godot_v4.7-stable_linux.x86_64" \
  "$ROOT/Godot_v4.7-stable_macos.universal" \
  "$ROOT/Godot" \
  2>/dev/null)"; then
  :
elif command -v godot4 >/dev/null 2>&1; then
  GODOT="$(command -v godot4)"
elif command -v godot >/dev/null 2>&1; then
  GODOT="$(command -v godot)"
fi

if [[ -z "${GODOT}" ]]; then
  echo "VR Viewer needs Godot 4.7."
  echo "Drop a Godot 4.7 binary next to project.godot, or install Godot and ensure \`godot\` is on PATH."
  echo "Download: https://godotengine.org/download/"
  exit 1
fi

if [[ ! -f "$ROOT/project.godot" ]]; then
  echo "project.godot missing — use the full project folder."
  exit 1
fi

echo "Using: $GODOT"
echo "Project: $ROOT"
exec "$GODOT" --path "$ROOT" "$@"
