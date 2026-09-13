#!/usr/bin/env bash
# Portable Retro Gaming Suite - Linux/macOS launcher
# Usage: ./launch.sh [--text] [--check] [--scan] [--launch NES/Game] ...
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PYTHON=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1; then PYTHON="$candidate"; break; fi
done
if [ -z "$PYTHON" ]; then
  echo "[FAIL] Python 3 not found. Install Python 3.9+ first." >&2
  exit 1
fi

if [ ! -f "$ROOT/Launcher/launcher.py" ]; then
  echo "[FAIL] Launcher script not found in $ROOT/Launcher." >&2
  exit 1
fi

if [ ! -e "$ROOT/Emulators/RetroArch/retroarch" ] && ! command -v retroarch >/dev/null 2>&1; then
  echo "[WARN] RetroArch is not installed. Run ./setup.sh first for automatic installation."
  echo "[WARN] Continuing to browse (games will not launch until setup). Press Ctrl+C to stop."
  sleep 3
fi

cd "$ROOT/Launcher"
exec "$PYTHON" launcher.py "$@"
