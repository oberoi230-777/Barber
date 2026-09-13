# 🎮 Portable Retro Gaming Suite v2.0

A complete portable retro gaming system that runs from a USB drive on any
Windows PC, TV box — and now Linux/macOS too!

## ✨ Features

- 🕹️ **15 Systems** — NES, SNES, N64, Game Boy, GBA, NDS, Genesis, Master
  System, Game Gear, PlayStation, Arcade, Neo Geo, Atari 2600, Dreamcast, PSP
- 🎯 **Plug & Play** — no installation required, runs directly from USB
- 🤖 **Super automated** — one-command unattended setup installs Python,
  RetroArch, all 13 cores, configs, and sample games
- 🩺 **Self-healing** — `diagnose` tool finds and auto-repairs problems
- 🎮 **Controller support** — Xbox, PlayStation, Switch Pro, 8BitDo, XInput
- 📺 **4K-ready UI** — auto-scales, fullscreen toggle, type-to-search,
  favorites, contextual help
- ⌨️ **Text-mode fallback** — the launcher works even with no display/pygame
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
2. Select a system and game (type to search, F5 = favorite)
3. Play!

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
| Up/Down, D-Pad, Left stick | Navigate |
| Enter / A button | Select / Launch |
| ESC / B button | Back / Exit |
| Type letters | Live search filter |
| F5 / Y button | Toggle favorite (★) |
| F6 / X button | Show favorites only |
| R (systems view) / Start | Rescan ROM library |
| F1 | Help screen |
| F11 | Toggle fullscreen |

### In Game (RetroArch defaults)

- **F1**: RetroArch menu · **F2**: quick save · **F4**: quick load
- **F8**: screenshot · **Hold Space**: fast forward · **ESC**: quit to launcher

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
├── Configs/                  # Master configs (systems, cores, controllers)
├── Launcher/                 # Game launcher (Python + pygame)
└── Tools/                    # ROM + maintenance utilities
```

## 🛠️ Tools

| Tool | What it does |
|---|---|
| `Tools/diagnose.bat` | **Start here for any problem.** Health check + one-click auto-repair (`-Fix`), JSON output (`-Json`) |
| `Tools/download-roms.bat` | Download free legal homebrew (`-System All`, `-Overwrite`, `-ListOnly`) |
| `Tools/organize-roms.bat` | Sort a messy folder into `ROMs/<system>/` (reads `systems.json`, handles cue/gdi companions, `-DryRun` preview, `-MoveFiles`) |
| `Tools/test-controller.bat` | Visual gamepad tester (`-TextOnly` for terminals, R = rumble test) |
| `Tools/update-system.bat` | Update cores / reinstall RetroArch (**keeps** cores, BIOS, saves) / backups (`-Action All -NonInteractive` for cron-safe runs) |

All `.bat` launchers forward arguments to their `.ps1` script.

### Launcher CLI (automation-friendly)

```
python Launcher/launcher.py --check            # health check (exit 0 = ready)
python Launcher/launcher.py --scan             # library summary
python Launcher/launcher.py --launch NES/Zelda # launch directly (name or index)
python Launcher/launcher.py --text             # terminal UI
python Launcher/launcher.py --self-test        # built-in self tests (used by CI)
```

## 📥 Adding More Games

**Method 1 — automatic (legal homebrew):** run `Tools/download-roms.bat`,
pick a system (or All). Sources are verified + auto-discovered at runtime.

**Method 2 — manual:** copy ROM files into the matching `ROMs/<system>/`
folder (zipped ROMs work for cartridge systems). The launcher picks them up
on the next scan (press **R**).

**Method 3 — organize a dump:** point `Tools/organize-roms.bat` at any messy
folder and it files everything into the right system folders.

## 📋 BIOS Files (some systems only)

| System | File(s) | Location |
|---|---|---|
| PlayStation | `scph1001.bin` | `Emulators/RetroArch/system/` |
| Dreamcast | `dc_boot.bin`, `dc_flash.bin` | `Emulators/RetroArch/system/` |
| Nintendo DS | `bios7.bin`, `bios9.bin`, `firmware.bin` | `Emulators/RetroArch/system/` |
| Neo Geo | `neogeo.zip` (keep zipped!) | `Emulators/RetroArch/system/` |
| GBA | `gba_bios.bin` (optional) | `Emulators/RetroArch/system/` |

Run `Tools/diagnose.bat` to see exactly which ones you're missing.
You must own the original hardware to legally use BIOS files.

## 🔧 Troubleshooting

**First step for ANY problem:** run `Tools/diagnose.bat` — it detects the
issue and usually fixes it with one keypress. Logs land in `Logs/`.

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for the full guide and
[QUICK-START.txt](QUICK-START.txt) for a printable cheat sheet.

## ⚖️ Legal Notice

This suite includes only free, open-source emulators. ROM files are NOT included.

**Legal ways to obtain ROMs:**
- ✅ Dump from your own cartridges/discs
- ✅ Public domain/homebrew games
- ✅ Legally distributed ROMs (archive.org, itch.io)
- ❌ Do NOT download copyrighted games you don't own

## 📜 Credits

Built with RetroArch (libretro team), libretro cores, Python & pygame-ce.
See [CHANGELOG.md](CHANGELOG.md) for what's new in v2.0.

---

**Enjoy your portable retro gaming experience! 🎮✨**
