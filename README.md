# 🎮 Portable Retro Gaming Suite

A complete portable retro gaming system that runs from USB drive on any Windows PC or TV box!

## ✨ Features

- 🕹️ **800+ Games Support** - Multiple emulators for various retro systems
- 🎯 **Plug & Play** - No installation required, runs directly from USB
- 🎮 **Controller Support** - Xbox, PlayStation, USB/Wireless joysticks
- 📺 **4K Display Support** - Optimized UI for modern displays
- 🚀 **Easy Setup** - Automated scripts download everything you need
- 💾 **Portable** - Take your games anywhere

## 🎯 Supported Systems

- Nintendo: NES, SNES, N64, Game Boy, GBA, DS
- Sega: Genesis/Mega Drive, Master System, Game Gear, Dreamcast
- Sony: PlayStation 1
- Arcade: MAME, Neo Geo, Capcom Play System
- And many more!

## 🚀 Quick Start

### Step 1: Initial Setup (First Time Only)

1. Copy this entire folder to your USB drive
2. Run `SETUP.bat` as Administrator
3. Wait for emulators and initial ROMs to download
4. Done! Your gaming system is ready

### Step 2: Launch Games

1. Run `LAUNCH.bat` from your USB drive
2. Select a system and game
3. Play!

## 🎮 Controller Setup

### Supported Controllers
- ✅ Xbox One/Series controllers (Wired/Wireless)
- ✅ PlayStation 4/5 controllers (DS4Windows included)
- ✅ Generic USB controllers
- ✅ Wireless dongles
- ✅ Keyboard (fallback)

### Default Controls
- **Arrow Keys/D-Pad**: Navigate
- **Enter/A Button**: Select
- **ESC/B Button**: Back
- **F11**: Toggle Fullscreen
- **Alt+F4**: Exit emulator

## 📁 Folder Structure

```
RetroGaming/
├── SETUP.bat              # First-time setup script
├── LAUNCH.bat             # Launch the game system
├── Emulators/             # Portable emulators (auto-downloaded)
├── ROMs/                  # Your game collection
│   ├── NES/
│   ├── SNES/
│   ├── Genesis/
│   └── ... (organized by system)
├── Configs/               # Emulator configurations
├── Launcher/              # Game launcher UI
└── Tools/                 # ROM management tools
```

## 📥 Adding More Games

### Method 1: Automatic Download (Legal ROMs)
```powershell
.\Tools\download-roms.bat
```

### Method 2: Manual Addition
1. Copy ROM files to appropriate folder in `ROMs/`
2. Launch system - games auto-detected

## 🔧 Troubleshooting

### Controller Not Working
1. Connect controller before launching
2. Check Windows Game Controller settings
3. Run `Tools\test-controller.bat`

### Game Won't Load
- Verify ROM file is in correct folder
- Check file extension matches system
- Some games require BIOS files (see BIOS section)

### Display Issues
- Press F11 for fullscreen
- Right-click launcher → Display Settings
- Adjust scaling in Windows display settings

## 📋 BIOS Files (Required for some systems)

Some systems require BIOS files for legal emulation:
- PlayStation 1: `scph1001.bin`
- Sega Dreamcast: `dc_boot.bin`, `dc_flash.bin`

Place BIOS files in: `Emulators/RetroArch/system/`

**Note**: You must own the original hardware to legally use BIOS files.

## ⚖️ Legal Notice

This suite includes only free, open-source emulators. ROM files are NOT included.

**Legal Ways to Obtain ROMs:**
- ✅ Dump from your own cartridges/discs
- ✅ Public domain/homebrew games
- ✅ Legally distributed ROMs (archive.org)
- ❌ Do NOT download copyrighted games you don't own

## 🛠️ Advanced Configuration

### Customize Emulator Settings
Edit files in `Configs/` folder to adjust performance, video filters, etc.

### Add Custom Emulators
1. Copy portable emulator to `Emulators/`
2. Add configuration to `Configs/systems.json`

## 🎯 Performance Tips

1. **USB Drive**: Use USB 3.0+ for best performance
2. **4K Displays**: Enable GPU scaling in configs
3. **Wireless Controllers**: Reduce input lag in Bluetooth settings
4. **Shaders**: Disable for older PCs, enable for CRT effects

## 💡 Tips & Tricks

- Press **F1** in RetroArch for quick menu
- Save states: **F2** (save), **F4** (load)
- Fast forward: **Hold Space**
- Screenshot: **F8**

## 🆘 Support & Updates

Check `Tools\update-system.bat` for updates to emulators and launcher.

## 📜 Credits

Built with:
- RetroArch (libretro team)
- Various standalone emulators
- Python & Pygame for launcher
- Community ROM databases

---

**Enjoy your portable retro gaming experience! 🎮✨**
