#!/usr/bin/env bash
# Launch VR Viewer. Default: editor.  ./run.sh play  → run main scene.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

MODE=editor
if [[ "${1:-}" == "play" ]]; then MODE=play; shift; fi
if [[ "${1:-}" == "editor" ]]; then MODE=editor; shift; fi

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
  echo "VR Viewer needs Godot 4.7."
  echo "Drop a Godot 4.7 binary next to project.godot, or put godot on PATH."
  exit 1
fi
if [[ ! -f "$ROOT/project.godot" ]]; then
  echo "project.godot missing."
  exit 1
fi

echo "Using:  $GODOT"
echo "Project: $ROOT"
echo "Mode:   $MODE"
if [[ "$MODE" == "play" ]]; then
  exec "$GODOT" --path "$ROOT" "$@"
else
  exec "$GODOT" -e --path "$ROOT" "$@"
fi
