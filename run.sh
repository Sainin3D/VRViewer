#!/usr/bin/env bash
# Default: run the app.  ./run.sh editor  → Godot editor.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

MODE=play
if [[ "${1:-}" == "editor" ]]; then MODE=editor; shift; fi
if [[ "${1:-}" == "play" ]]; then MODE=play; shift; fi

GODOT=""
for c in \
  "$ROOT/Godot_v4.7-stable_linux.x86_64" \
  "$ROOT/Godot_v4.7-stable_macos.universal" \
  "$ROOT/Godot" \
  "$ROOT/Godot_v4.7-stable_win64.exe"
do
  if [[ -e "$c" ]]; then GODOT="$c"; break; fi
done
if [[ -z "$GODOT" ]] && command -v godot4 >/dev/null 2>&1; then GODOT="$(command -v godot4)"; fi
if [[ -z "$GODOT" ]] && command -v godot >/dev/null 2>&1; then GODOT="$(command -v godot)"; fi

if [[ -z "$GODOT" ]]; then
  echo "VR Viewer needs Godot 4.7 next to project.godot, or on PATH."
  exit 1
fi
if [[ ! -f "$ROOT/project.godot" ]]; then
  echo "project.godot missing."
  exit 1
fi

echo "Using:  $GODOT"
echo "Project: $ROOT"
echo "Mode:   $MODE"
if [[ "$MODE" == "editor" ]]; then
  exec "$GODOT" -e --path "$ROOT" "$@"
else
  exec "$GODOT" --path "$ROOT" "$@"
fi
