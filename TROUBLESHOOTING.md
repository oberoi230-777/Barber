# 🔧 Troubleshooting Guide

Common issues and solutions for the Portable Retro Gaming Suite

---

## 🔴 Setup Issues

### Python Not Found

**Problem:** "Python not found" error when running LAUNCH.bat

**Solutions:**
1. Download Python from [python.org/downloads](https://www.python.org/downloads/)
2. During installation, **CHECK** "Add Python to PATH"
3. Restart your computer
4. Run SETUP.bat again

**Verify Python is installed:**
```powershell
python --version
```

### pygame Installation Fails

**Problem:** pygame fails to install during setup

**Solutions:**
1. Open Command Prompt as Administrator
2. Run: `python -m pip install --upgrade pip`
3. Run: `python -m pip install pygame`
4. If still fails, try: `python -m pip install pygame --user`

### RetroArch Download Fails

**Problem:** RetroArch fails to download or extract

**Manual Solution:**
1. Download RetroArch manually: [retroarch.com](https://www.retroarch.com/?page=platforms)
2. Choose "Windows 7/8/10/11 (64-bit)"
3. Extract to: `F:\RetroGaming\Emulators\RetroArch\`
4. Run SETUP.bat again (it will skip download)

---

## 🎮 Controller Issues

### Controller Not Detected

**Problem:** Controller doesn't work in games

**Solutions:**

1. **Connect Before Launching**
   - Plug in controller BEFORE running LAUNCH.bat
   - For wireless: pair through Windows Bluetooth settings first

2. **Test Controller**
   ```
   Run: Tools\test-controller.bat
   ```
   - This shows if Windows detects your controller
   - You should see button presses and analog stick movement

3. **Windows Game Controller Settings**
   - Press `Win + R`, type `joy.cpl`, press Enter
   - Your controller should appear in the list
   - Click "Properties" to test buttons

4. **Check USB Port**
   - Try a different USB port (preferably USB 3.0)
   - For wireless controllers, ensure receiver is plugged in

### PS4/PS5 Controller Issues

**Problem:** PlayStation controller doesn't work

**Solutions:**

1. **Use USB Cable First**
   - Connect with USB cable (not Bluetooth initially)
   - This works more reliably

2. **Install DS4Windows** (for wireless)
   - Download from [ds4windows.com](https://ds4windows.com)
   - Extract and run DS4Windows.exe
   - Follow setup wizard
   - Keep DS4Windows running in background

3. **Bluetooth Pairing**
   - Hold PS + Share buttons until light flashes
   - Add Bluetooth device in Windows
   - Select "Wireless Controller"

### Xbox Controller Issues

**Problem:** Xbox controller not responding

**Solutions:**

1. **Xbox One/Series Controllers**
   - Wired: Use USB-C cable
   - Wireless: Requires Xbox Wireless Adapter for Windows
   - Alternative: Use USB cable

2. **Xbox 360 Controllers**
   - May need Xbox 360 controller driver
   - Download from Microsoft website
   - Wireless requires Xbox 360 wireless receiver

3. **Update Controller Firmware**
   - Open Xbox Accessories app from Microsoft Store
   - Connect controller
   - Update if available

---

## 🎯 Game Issues

### No Games Showing in Launcher

**Problem:** Launcher shows "0 games" for all systems

**Solutions:**

1. **Add ROM Files**
   - Copy ROM files to correct folders:
     - NES games → `ROMs\NES\`
     - SNES games → `ROMs\SNES\`
     - etc.

2. **Download Sample ROMs**
   ```
   Run: Tools\download-roms.bat
   ```

3. **Check File Extensions**
   - Verify ROM files have correct extensions
   - Examples: `.nes`, `.smc`, `.md`, `.gba`
   - See README.md for full list

4. **Restart Launcher**
   - Close and reopen LAUNCH.bat
   - Launcher scans for games at startup

### Game Won't Load

**Problem:** Selected game doesn't start or shows error

**Solutions:**

1. **Check BIOS Files** (PlayStation, Dreamcast, Neo Geo)
   - See `Configs\BIOS-INFO.txt` for required files
   - Place BIOS in: `Emulators\RetroArch\system\`

2. **Verify ROM File**
   - File might be corrupted
   - Try different ROM dump
   - Check file size (0 bytes = bad file)

3. **RetroArch Core Missing**
   - Run SETUP.bat again to download cores
   - Or download from RetroArch menu (F1 → Online Updater)

4. **Check RetroArch Logs**
   - Location: `Emulators\RetroArch\logs\`
   - Look for error messages

### Black Screen When Loading Game

**Problem:** Game loads but screen stays black

**Solutions:**

1. **Wait 10-15 Seconds**
   - Some games take time to initialize
   - Especially PS1 and N64 games

2. **BIOS Missing**
   - Check if system requires BIOS (see BIOS-INFO.txt)

3. **Wrong Core**
   - Press F1 → Information → Core Information
   - Verify correct core is loaded

4. **Video Driver Issue**
   - Press F1 → Settings → Drivers → Video
   - Try different driver (d3d11, gl, vulkan)

---

## 💻 Display Issues

### Launcher Window Too Small/Large

**Problem:** UI doesn't fit screen properly

**Solutions:**

1. **Change Display Scaling**
   - Windows Settings → Display → Scale
   - Try 100% or 125% scaling

2. **Press F11**
   - Toggles fullscreen mode

3. **Adjust Resolution**
   - The launcher auto-detects display size
   - For 4K: Should open fullscreen
   - For 1080p: Opens windowed

### Game Has Wrong Aspect Ratio

**Problem:** Game looks stretched or squashed

**Solutions:**

1. **In-Game Menu** (Press F1)
   - Settings → Video
   - Aspect Ratio → "Core Provided" or "4:3"

2. **Integer Scaling**
   - Settings → Video → Integer Scale → ON
   - Gives pixel-perfect scaling

3. **Fullscreen Mode**
   - Settings → Video → Fullscreen → ON

### Screen Tearing

**Problem:** Horizontal lines during gameplay

**Solutions:**

1. **Enable VSync**
   - Press F1 → Settings → Video
   - VSync → ON

2. **Check Monitor Refresh Rate**
   - Windows Display Settings
   - Set to highest available (60Hz minimum)

---

## 🐌 Performance Issues

### Slow/Laggy Gameplay

**Problem:** Games run slow or choppy

**Solutions:**

1. **Use USB 3.0 Port**
   - Blue USB ports = USB 3.0 (faster)
   - Black USB ports = USB 2.0 (slower)
   - USB 3.0 is 10x faster!

2. **Close Other Programs**
   - Chrome, Discord, etc. use resources
   - Close unnecessary applications

3. **Disable Shaders**
   - Press F1 → Quick Menu
   - Shaders → Remove

4. **Reduce Internal Resolution** (N64, PS1, PSP)
   - Press F1 → Quick Menu → Core Options
   - Look for "Internal Resolution"
   - Set to 1x or 2x

5. **Check System Requirements**
   - Older PCs may struggle with N64, PSP, Dreamcast
   - Try simpler systems (NES, SNES, Genesis)

### Input Lag

**Problem:** Controller feels delayed

**Solutions:**

1. **Wired Connection**
   - Use USB cable instead of Bluetooth
   - Reduces latency

2. **Run-Ahead Feature**
   - Press F1 → Settings → Latency
   - Run-Ahead → Enable
   - Frames → 1 or 2

3. **Reduce Audio Latency**
   - Press F1 → Settings → Audio
   - Audio Latency → 32 or 64ms

---

## 📁 File Issues

### Can't Find Save Files

**Problem:** Where are my game saves?

**Location:** `Save States\` folder

**Solutions:**

1. **Save States** (recommended)
   - Press F2 during game to quick save
   - Press F4 to quick load
   - Works with all games

2. **In-Game Saves** (native)
   - Save using game's own save feature
   - Files saved to `Save States\` automatically

3. **Export Saves**
   - Copy entire `Save States\` folder
   - Backup to another location

### USB Drive Not Working on Another PC

**Problem:** System doesn't work when plugged into different computer

**Solutions:**

1. **Drive Letter Changed**
   - Normal behavior - scripts handle this automatically
   - Just run LAUNCH.bat from new drive letter

2. **Python Not Installed on New PC**
   - Install Python on that computer
   - Or make Python portable (advanced)

3. **Antivirus Blocking**
   - Some antivirus software blocks USB executables
   - Add exception for your USB drive

---

## 🔒 Security Issues

### Antivirus Warns About Files

**Problem:** Antivirus flags RetroArch or scripts

**Reason:** Emulators and PowerShell scripts are sometimes flagged as false positives

**Solutions:**

1. **Verify Files Are Safe**
   - All files from official sources
   - RetroArch: libretro.com (open source)
   - Scripts: Created by this tool

2. **Add Exclusion**
   - Add entire `RetroGaming\` folder to antivirus exclusions
   - Or specifically: `Emulators\RetroArch\`

3. **Disable Real-Time Scanning Temporarily**
   - Only when running setup/games
   - Re-enable after use

### Windows SmartScreen Warning

**Problem:** "Windows protected your PC" message

**Solution:**
1. Click "More info"
2. Click "Run anyway"
3. This appears for unsigned applications (normal)

---

## 🌐 Download Issues

### Sample ROM Download Fails

**Problem:** download-roms.bat can't download games

**Solutions:**

1. **Check Internet Connection**
   - Verify you're connected
   - Try opening a website

2. **Firewall Blocking**
   - Temporarily disable firewall
   - Or add exception for PowerShell

3. **Manual Download**
   - Visit archive.org directly
   - Search for "homebrew [system name]"
   - Download and place in ROM folders

### Core Download Fails During Setup

**Problem:** Emulator cores fail to download

**Solutions:**

1. **Download from RetroArch**
   - Run `Emulators\RetroArch\retroarch.exe`
   - Online Updater → Core Downloader
   - Select cores manually

2. **Check Network**
   - buildbot.libretro.com might be slow
   - Try again later

3. **Manual Core Installation**
   - Download from buildbot.libretro.com
   - Extract `.dll` files to `Emulators\RetroArch\cores\`

---

## 🆘 Still Having Issues?

### General Debugging Steps

1. **Run SETUP.bat Again**
   - Fixes most configuration issues
   - Re-downloads missing components

2. **Check README.md**
   - Comprehensive documentation
   - System requirements
   - Supported formats

3. **Reset Configuration**
   - Delete: `Emulators\RetroArch\retroarch.cfg`
   - Run SETUP.bat to recreate
   - Warning: Resets all RetroArch settings

4. **Clean Reinstall**
   - Delete `Emulators\RetroArch\` folder
   - Keep `ROMs\` and `Save States\`
   - Run SETUP.bat

### Log Files

Check these locations for error details:

- **Launcher Errors:** Run from command line to see output
  ```
  cd Launcher
  python launcher.py
  ```

- **RetroArch Logs:** `Emulators\RetroArch\logs\`

- **Setup Errors:** PowerShell shows errors during SETUP.bat

---

## 📝 Reporting Issues

If you need additional help:

1. **What to Include:**
   - Windows version
   - Error message (exact text or screenshot)
   - What you were trying to do
   - Steps to reproduce

2. **Useful Info:**
   - Output of: `python --version`
   - USB drive type (USB 2.0 / 3.0)
   - Controller model

---

**Most issues are solved by:**
- ✅ Running SETUP.bat as Administrator
- ✅ Using USB 3.0 port
- ✅ Installing Python correctly (with PATH)
- ✅ Adding BIOS files for PS1/Dreamcast
- ✅ Connecting controller before launching

Happy Gaming! 🎮
