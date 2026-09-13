#!/usr/bin/env bash
# Portable Retro Gaming Suite - Linux/macOS setup
# Usage: ./setup.sh [--yes] [--skip-retroarch] [--skip-cores] [--skip-python-deps]
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSUME_YES=0
SKIP_RA=0
SKIP_CORES=0
SKIP_PYDEPS=0

for arg in "$@"; do
  case "$arg" in
    --yes|-y) ASSUME_YES=1 ;;
    --skip-retroarch) SKIP_RA=1 ;;
    --skip-cores) SKIP_CORES=1 ;;
    --skip-python-deps) SKIP_PYDEPS=1 ;;
    --help|-h)
      echo "Usage: ./setup.sh [--yes] [--skip-retroarch] [--skip-cores] [--skip-python-deps]"
      exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

info()  { echo "[INFO] $*"; }
ok()    { echo "[OK] $*"; }
warn()  { echo "[WARN] $*" >&2; }
fail()  { echo "[FAIL] $*" >&2; }

ask_yes() {
  if [ "$ASSUME_YES" -eq 1 ]; then return 0; fi
  read -r -p "$1 [y/N] " reply
  case "$reply" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

OS="$(uname -s)"
info "Portable Retro Gaming Suite setup ($OS)"
info "Root: $ROOT"

# --- 1. Python -------------------------------------------------------------
PYTHON=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1; then PYTHON="$candidate"; break; fi
done
if [ -z "$PYTHON" ]; then
  fail "Python 3 not found. Install Python 3.9+ first (https://www.python.org/downloads/)."
  exit 1
fi
PYVER="$("$PYTHON" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
ok "Found $PYTHON ($PYVER)"

if [ "$SKIP_PYDEPS" -eq 0 ]; then
  info "Installing pygame-ce (user site)..."
  if "$PYTHON" -m pip install --user --upgrade pygame-ce; then
    ok "pygame-ce installed."
  else
    fail "pip install failed. Try: $PYTHON -m pip install --user pygame-ce"
    exit 1
  fi
fi

# --- 2. Folder structure ----------------------------------------------------
info "Creating portable folders..."
mkdir -p "$ROOT/Emulators/RetroArch"/{cores,system,config,logs,playlists} \
         "$ROOT/ROMs" "$ROOT/Save States" "$ROOT/Screenshots" "$ROOT/Backups" "$ROOT/Logs"
export SUITE_ROOT="$ROOT"
if [ -f "$ROOT/Configs/systems.json" ]; then
  "$PYTHON" - <<'EOF'
import json, os
root = os.environ.get("SUITE_ROOT", ".")
try:
    with open(os.path.join(root, "Configs", "systems.json"), encoding="utf-8") as f:
        systems = json.load(f)
    for entry in systems:
        folder = entry.get("folder")
        if folder:
            os.makedirs(os.path.join(root, "ROMs", folder), exist_ok=True)
    print(f"Created {len(systems)} ROM folders.")
except Exception as exc:
    print(f"WARNING: could not read systems.json: {exc}")
EOF
fi
ok "Folders ready."

# --- 3. RetroArch ------------------------------------------------------------
RA_BIN=""
if [ -x "$ROOT/Emulators/RetroArch/retroarch" ]; then
  RA_BIN="$ROOT/Emulators/RetroArch/retroarch"
elif command -v retroarch >/dev/null 2>&1; then
  RA_BIN="$(command -v retroarch)"
fi

if [ "$SKIP_RA" -eq 0 ] && [ -z "$RA_BIN" ]; then
  info "RetroArch not found. Attempting package-manager install..."
  INSTALLED=0
  if command -v apt-get >/dev/null 2>&1; then
    if ask_yes "Install RetroArch via apt (requires sudo)?"; then
      sudo apt-get update && sudo apt-get install -y retroarch && INSTALLED=1
    fi
  elif command -v dnf >/dev/null 2>&1; then
    if ask_yes "Install RetroArch via dnf (requires sudo)?"; then
      sudo dnf install -y retroarch && INSTALLED=1
    fi
  elif command -v pacman >/dev/null 2>&1; then
    if ask_yes "Install RetroArch via pacman (requires sudo)?"; then
      sudo pacman -S --noconfirm retroarch && INSTALLED=1
    fi
  elif command -v zypper >/dev/null 2>&1; then
    if ask_yes "Install RetroArch via zypper (requires sudo)?"; then
      sudo zypper install -y retroarch && INSTALLED=1
    fi
  elif command -v brew >/dev/null 2>&1; then
    if ask_yes "Install RetroArch via Homebrew?"; then
      brew install --cask retroarch && INSTALLED=1
    fi
  else
    warn "No supported package manager found."
  fi
  if command -v retroarch >/dev/null 2>&1; then
    RA_BIN="$(command -v retroarch)"
    INSTALLED=1
  fi
  if [ "$INSTALLED" -eq 0 ]; then
    warn "RetroArch was not installed."
    warn "Install it manually: https://retroarch.com/?page=platforms (or 'flatpak install flathub org.libretro.RetroArch')"
  fi
fi

if [ -n "$RA_BIN" ]; then
  ok "RetroArch: $RA_BIN"
  # Link the system binary into the portable tree so the launcher finds it.
  if [ ! -e "$ROOT/Emulators/RetroArch/retroarch" ]; then
    ln -s "$RA_BIN" "$ROOT/Emulators/RetroArch/retroarch" 2>/dev/null || cp "$RA_BIN" "$ROOT/Emulators/RetroArch/retroarch" 2>/dev/null || true
  fi
else
  warn "RetroArch missing - games cannot launch until it is installed."
fi

# --- 4. Linux/macOS RetroArch config (translated from the master cfg) --------
if [ -f "$ROOT/Configs/retroarch.cfg" ]; then
  info "Generating platform RetroArch config..."
  sed -e 's/^video_driver = "d3d11"/video_driver = "gl"/' \
      -e 's/^audio_driver = "wasapi"/audio_driver = "alsa"/' \
      -e 's/^input_driver = "dinput"/input_driver = "udev"/' \
      -e 's/^input_joypad_driver = "dinput"/input_joypad_driver = "udev"/' \
      -e 's/\.\.\\\\ROMs/..\/ROMs/' \
      -e 's/\.\.\\\\Save States/..\/Save States/' \
      -e 's/\.\.\\\\Screenshots/..\/Screenshots/' \
      -e 's/database\\\\rdb/database\/rdb/' \
      -e 's/database\\\\cursors/database\/cursors/' \
      "$ROOT/Configs/retroarch.cfg" > "$ROOT/Emulators/RetroArch/retroarch.cfg"
  if [ "$OS" = "Darwin" ]; then
    sed -i '' -e 's/^video_driver = "gl"/video_driver = "metal"/' \
              -e 's/^audio_driver = "alsa"/audio_driver = "coreaudio"/' \
              -e 's/^input_driver = "udev"/input_driver = "cocoa"/' \
              -e 's/^input_joypad_driver = "udev"/input_joypad_driver = "hid"/' \
              "$ROOT/Emulators/RetroArch/retroarch.cfg"
  fi
  ok "RetroArch config written."
fi

if [ -f "$ROOT/Configs/core-options.cfg" ]; then
  cp "$ROOT/Configs/core-options.cfg" "$ROOT/Emulators/RetroArch/config/retroarch-core-options.cfg"
  ok "Core options installed."
fi

# --- 5. Cores (.so builds from the libretro buildbot) ------------------------
if [ "$SKIP_CORES" -eq 0 ]; then
  CORES="fceumm snes9x mupen64plus_next gambatte mgba desmume genesis_plus_gx pcsx_rearmed mame2003_plus fbneo stella flycast ppsspp"
  if [ "$OS" = "Darwin" ]; then
    PLATFORM="apple/osx/universal"
    EXT="dylib"
  else
    PLATFORM="linux/x86_64"
    EXT="so"
  fi
  DOWNLOADER=""
  if command -v curl >/dev/null 2>&1; then DOWNLOADER="curl"; elif command -v wget >/dev/null 2>&1; then DOWNLOADER="wget"; fi
  if [ -z "$DOWNLOADER" ]; then
    warn "Neither curl nor wget found - skipping core downloads."
  else
    info "Downloading cores ($PLATFORM)..."
    for core in $CORES; do
      dest="$ROOT/Emulators/RetroArch/cores/${core}_libretro.$EXT"
      if [ -f "$dest" ]; then ok "$core already present"; continue; fi
      url="https://buildbot.libretro.com/nightly/$PLATFORM/latest/${core}_libretro.${EXT}.zip"
      tmp="$(mktemp -t "${core}.XXXXXX.zip")"
      if [ "$DOWNLOADER" = "curl" ]; then
        curl -sSL --retry 3 --max-time 120 -o "$tmp" "$url" || true
      else
        wget -q --tries=3 --timeout=120 -O "$tmp" "$url" || true
      fi
      if [ -s "$tmp" ]; then
        if "$PYTHON" -m zipfile -e "$tmp" "$ROOT/Emulators/RetroArch/cores/" 2>/dev/null; then
          if [ -f "$dest" ]; then ok "Installed $core"; else warn "Extracted but $core file missing"; fi
        else
          warn "Failed to extract $core (download may have failed)"
        fi
      else
        warn "Failed to download $core"
      fi
      rm -f "$tmp"
    done
  fi
fi

# --- 6. Validate --------------------------------------------------------------
info "Running launcher self-test..."
if "$PYTHON" "$ROOT/Launcher/launcher.py" --self-test; then
  ok "Self-test passed."
else
  warn "Self-test reported failures - see output above."
fi

info "Health check:"
"$PYTHON" "$ROOT/Launcher/launcher.py" --check || true

echo ""
ok "Setup finished. Launch with: ./launch.sh"
if [ "$ASSUME_YES" -eq 0 ] && ask_yes "Launch the gaming system now?"; then
  exec "$ROOT/launch.sh"
fi
