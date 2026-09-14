# 🎮 Portable Retro Gaming Suite v3.0

A complete portable retro gaming system that runs from a USB drive on any
Windows PC, TV box — and Linux/macOS too. **50+ systems**, dual-player
joysticks, a huge updatable free-games catalog, netplay-ready, and built to
stay future-proof.

## ✨ Features

- 🕹️ **53 systems** — NES through Dreamcast, plus computers (C64, Amiga, DOS,
  ZX Spectrum, MSX…), arcade, and fantasy consoles (TIC-80, PICO-8, WASM-4)
- 👥 **Dual-player joysticks first-class** — up to 8 pads; P1–P4 joypad indexes
  pre-wired; any pad can drive the launcher; P2 keyboard cluster (IJKL) when
  you only have one keyboard
- 📦 **Free-games catalog** — 150+ curated legal homebrew / public-domain /
  freeware entries across every system, with live archive.org discovery
- 🔄 **Future-safe & updatable** — add systems via `Configs/systems.json`,
  add free games via `Configs/free-games-catalog.json`, no code changes
- 🎯 **Plug & Play** — no installation required, runs directly from USB
- 🤖 **Super automated** — one-command unattended setup installs Python,
  RetroArch, 45 cores, configs, and sample games
- 🩺 **Self-healing** — `diagnose` tool finds and auto-repairs problems
- 🎮 **Controller profiles** — Xbox 360/One/Series, DualShock/DualSense,
  Switch Pro, 8BitDo, generic XInput + DirectInput fallbacks
- 📺 **4K-ready UI** — categories, type-to-filter, favorites, recents,
  multiplayer filter, fullscreen toggle, contextual help
- 🌐 **Netplay + RetroAchievements ready** — toggles pre-wired in config
- ⏪ **Rewind** enabled by default (hold R in-game)
- ⌨️ **Text-mode fallback** — works over SSH / without pygame
- 🐧 **Cross-platform** — Windows (`SETUP.bat`) + Linux/macOS (`setup.sh`)
- 💾 **Portable** — take your games anywhere; drive letters don't matter

## 🚀 Quick Start (Windows)

### Step 1: Initial Setup (first time only)

1. Copy this entire folder to your USB drive
2. Run `SETUP.bat` (right-click → *Run as administrator* recommended)
3. Answer the prompts — or run zero-click setup:
   ```
   SETUP.bat -Unattended -IncludeSampleRoms
   ```
   This auto-installs Python (via winget), RetroArch, all cores, and free
   sample games with no questions asked.

### Step 2: Launch Games

1. Run `LAUNCH.bat` from your USB drive
2. Select a system and game (type to filter, Tab = category, F2 = recents)
3. Plug in **two controllers** for 2-player — the header shows `2P OK`
4. Play!

### Step 3: Fill the library with free games

```
Tools\download-roms.bat -System All
Tools\download-roms.bat -System Everything -MaxFiles 5
Tools\download-roms.bat -System NES
```

## 🐧 Quick Start (Linux / macOS)

```bash
./setup.sh            # interactive (installs deps, RetroArch, cores)
./setup.sh --yes      # unattended
./launch.sh           # play!
./launch.sh --text    # terminal UI (great for SSH / handhelds)
```

## 🎮 Controls

### In the Launcher

| Input | Action |
|---|---|
| Up/Down, D-Pad, Left stick | Navigate (any connected pad) |
| Enter / A button | Select / Launch |
| ESC / B button | Back / Exit |
| Left/Right, LB/RB, Tab | Cycle category filter |
| Type letters | Live filter (systems or games) |
| F2 / Y (systems) | Recent games |
| F3 / C / X (systems) | Categories browser |
| F5 / Y (games) | Toggle favorite (★) |
| F6 / V / X (games) | Show favorites only |
| F7 / E | Toggle empty systems |
| R (systems view) / Start | Rescan ROM library |
| F1 | Help screen |
| F11 | Toggle fullscreen |

### 2-Player (in-game)

| Player | Controller | Keyboard fallback |
|---|---|---|
| P1 | First pad (index 0) | Arrows + Z/X/A/S + Enter |
| P2 | Second pad (index 1) | **I J K L** + F/G/R/T + B |
| P3 / P4 | Third / fourth pad | — |

Hotkeys: hold **Select/Back** + **Start** = quit to launcher.

### In Game (RetroArch defaults)

- **F1**: RetroArch menu · **F2**: quick save · **F4**: quick load
- **F8**: screenshot · **Hold Space**: fast forward · **R**: rewind
- **ESC**: quit to launcher

## 📁 Folder Structure

```
RetroGaming/
├── SETUP.bat / setup.sh      # First-time setup (Windows / Linux-macOS)
├── LAUNCH.bat / launch.sh    # Launch the game system
├── version.json              # Suite version + pinned RetroArch stable
├── Emulators/RetroArch/      # Portable RetroArch (auto-downloaded)
├── ROMs/                     # Your game collection (one folder per system)
├── Save States/              # Saves + save states (auto-configured)
├── Screenshots/              # Screenshots (auto-configured)
├── Backups/                  # Backups from the update tool
├── Logs/                     # Setup/launcher/diagnose logs
├── Configs/
│   ├── systems.json          # ← ADD SYSTEMS HERE (future-safe)
│   ├── free-games-catalog.json  # ← ADD FREE GAMES HERE (future-safe)
│   ├── retroarch.cfg         # Master RA config (P1–P4 wired)
│   ├── core-options.cfg      # Per-core tweaks
│   └── autoconfig/           # Controller profiles (dinput + xinput)
├── Launcher/                 # Game launcher (Python + pygame)
└── Tools/                    # ROM + maintenance utilities
```

## 🛠️ Tools

| Tool | What it does |
|---|---|
| `Tools/diagnose.bat` | **Start here for any problem.** Health check + one-click auto-repair (`-Fix`), JSON output (`-Json`) |
| `Tools/download-roms.bat` | Download free legal homebrew from the catalog (`-System All\|Everything\|NES`, `-Overwrite`, `-ListOnly`, `-Query "nes homebrew"`, `-MaxFiles 8`) |
| `Tools/organize-roms.bat` | Sort a messy folder into `ROMs/<system>/` (reads `systems.json`, handles cue/gdi companions, `-DryRun` preview, `-MoveFiles`) |
| `Tools/test-controller.bat` | Visual gamepad tester (`-TextOnly` for terminals, R = rumble test) — verify **two pads** before 2P night |
| `Tools/update-system.bat` | Update cores / reinstall RetroArch (**keeps** cores, BIOS, saves) / backups (`-Action All -NonInteractive` for cron-safe runs) |

All `.bat` launchers forward arguments to their `.ps1` script.

### Launcher CLI (automation-friendly)

```
python Launcher/launcher.py --check            # health check (exit 0 = ready)
python Launcher/launcher.py --scan             # library summary
python Launcher/launcher.py --list-systems     # all 53 systems
python Launcher/launcher.py --catalog          # free-games catalog stats
python Launcher/launcher.py --launch NES/Zelda # launch directly (name or index)
python Launcher/launcher.py --text             # terminal UI
python Launcher/launcher.py --self-test        # built-in self tests (used by CI)
```

## 📥 Adding More Games (future-safe)

**Method 1 — catalog download (legal homebrew):**
```
Tools\download-roms.bat -System All
```
Sources live in `Configs/free-games-catalog.json` and auto-discover new
archive.org files at runtime. To add more forever, just edit that JSON.

**Method 2 — manual:** copy ROM files into the matching `ROMs/<system>/`
folder (zipped ROMs work for cartridge systems). Press **R** to rescan.

**Method 3 — organize a dump:** point `Tools/organize-roms.bat` at any messy
folder and it files everything into the right system folders.

**Method 4 — add a whole new system:** append an entry to
`Configs/systems.json` (name, folder, extensions, core). Drop the core name
into `Tools/ps-common.ps1` / `setup.sh` if it is brand new, run setup/update,
done. No launcher code changes required.

## 📋 BIOS Files (some systems only)

| System | File(s) | Location |
|---|---|---|
| PlayStation | `scph1001.bin` | `Emulators/RetroArch/system/` |
| Dreamcast | `dc_boot.bin`, `dc_flash.bin` | `Emulators/RetroArch/system/` |
| Nintendo DS | `bios7.bin`, `bios9.bin`, `firmware.bin` | `Emulators/RetroArch/system/` |
| Neo Geo | `neogeo.zip` (keep zipped!) | `Emulators/RetroArch/system/` |
| Sega CD | `bios_CD_U.bin` / `_E` / `_J` | `Emulators/RetroArch/system/` |
| Saturn | `sega_101.bin`, `mpr-17933.bin` | `Emulators/RetroArch/system/` |
| GBA | `gba_bios.bin` (optional) | `Emulators/RetroArch/system/` |
| + more | see `Configs/systems.json` `bios` fields | same folder |

Run `Tools/diagnose.bat` to see exactly which ones you're missing.
You must own the original hardware to legally use BIOS files.

## 🔧 Troubleshooting

**First step for ANY problem:** run `Tools/diagnose.bat` — it detects the
issue and usually fixes it with one keypress. Logs land in `Logs/`.

**Two controllers not working in-game?**
1. Run `Tools/test-controller.bat` — confirm both pads light up
2. In the launcher header you should see `2P OK | P1:… + P2:…`
3. Prefer XInput mode on Windows (Xbox pads, 8BitDo X mode, DS4Windows)
4. In RetroArch quick menu → Controls → Port 1/2 Devices should be retropad

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for the full guide and
[QUICK-START.txt](QUICK-START.txt) for a printable cheat sheet.

## ⚖️ Legal Notice

This suite includes only free, open-source emulators. ROM files are NOT included.

**Legal ways to obtain ROMs:**
- ✅ Dump from your own cartridges/discs
- ✅ Public domain/homebrew games (use `Tools/download-roms`)
- ✅ Legally distributed ROMs (archive.org, itch.io, pdroms.de)
- ❌ Do NOT download copyrighted games you don't own

## 📜 Credits

Built with RetroArch (libretro team), libretro cores, Python & pygame-ce.
See [CHANGELOG.md](CHANGELOG.md) for what's new in v3.0.

---

**Enjoy your portable retro gaming experience! 🎮✨**
