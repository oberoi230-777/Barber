# 🔧 Troubleshooting Guide (v2.0)

> **Start here for EVERY problem:** run `Tools\diagnose.bat` (Windows) and
> accept the automatic repair. It detects missing Python/pygame, RetroArch,
> cores, configs, ROMs, and BIOS files — and usually fixes them with one
> keypress. Logs are saved in `Logs\`.

You can also run the launcher's own checks any time:

```
LAUNCH.bat --check        # health check (exit code 0 = ready to play)
LAUNCH.bat --self-test    # deep self-test of scanner/configs
```

---

## 🔴 Setup Issues

### Launcher Window Opens and Closes Instantly

**Problem:** double-clicking `LAUNCH.bat` flashes a console window that
immediately disappears.

**Cause (99% of cases):** Windows finds a `python` that isn't real —
usually the **Microsoft Store stub** (an App Execution Alias). The old
`LAUNCH.bat` accepted it, the stub exited instantly, and the window closed
before you could read anything.

**Fixes:**

1. Update to the latest scripts — `LAUNCH.bat` now probes that Python
   really runs, shows a "Python Not Found" screen for the stub case, and
   pauses with the error + log tail on ANY failure instead of closing.
2. Run `SETUP.bat` — it offers to install real Python via winget.
3. Or install Python manually from
   [python.org/downloads](https://www.python.org/downloads/) (check
   "Add Python to PATH").
4. Or disable the stub: Settings → Apps → Advanced app settings →
   App execution aliases → turn off the `python.exe` / `python3.exe`
   entries — then install real Python.
5. If the window still closes, open `Logs\launcher.log` and follow the
   section below matching the last error lines.

### Python Not Found

**Problem:** "Python not found" error when running LAUNCH.bat

**Automatic fix:** run `SETUP.bat` — it offers to install Python via winget.

**Manual fix:**

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

**Automatic fixes (try in order):**

1. Run `Tools\diagnose.bat` and accept the repair
2. Run `Tools\update-system.bat`, option 3 (Update Python dependencies)

**Manual fix:**

1. Open Command Prompt as Administrator
2. Run: `python -m pip install --upgrade pip`
3. Run: `python -m pip install pygame-ce`
4. If still fails, the launcher falls back to `--text` mode automatically —
   you can play without graphics via `LAUNCH.bat --text`

### RetroArch Download Fails

**Problem:** RetroArch fails to download or extract

SETUP retries each download 3× and tries multiple mirrors (latest stable
auto-detected, pinned stable, nightly fallback). If all fail:

1. Check your internet (`diagnose.bat` tests connectivity)
2. Check free space (needs ~1–2 GB) and that the USB drive isn't write-locked
3. Check the log in `Logs\setup-*.log` for the exact failed URL

**Manual Solution:**

1. Download RetroArch manually: [retroarch.com](https://www.retroarch.com/?page=platforms)
2. Choose "Windows 7/8/10/11 (64-bit)" → download the `.7z`
3. Extract so that `retroarch.exe` lands in `<USB>\Emulators\RetroArch\`
   (whatever your drive letter is — the scripts resolve it automatically)
4. Run SETUP.bat again (it will skip the download and install cores/configs)

### "Could not extract .7z"

The setup extracts `.7z` via 7-Zip → winget auto-install → py7zr → tar.
If all fail, install 7-Zip manually and re-run:

```powershell
winget install 7zip.7zip
```

---

## 🎮 Controller Issues

### Controller Not Detected

**Problem:** Controller doesn't work in games

**Solutions:**

1. **Connect BEFORE launching** — plug in / pair first, then run LAUNCH.bat
2. **Test the controller:**
   ```
   Run: Tools\test-controller.bat
   ```
   You should see values move. In a terminal/SSH session use:
   ```
   Tools\test-controller.bat -TextOnly -Seconds 15
   ```
   Press **R** in the window for a rumble test.
3. **Windows Game Controller settings** — press `Win + R`, type `joy.cpl`,
   press Enter. Your pad MUST appear here; if not, it's a Windows/driver
   issue, not a RetroArch issue.
4. Try a different USB port (USB 3.0 preferred). For wireless, re-pair in
   Windows Bluetooth settings.

### PS4/PS5 Controller Issues

1. **Use USB first** — Bluetooth via plain DirectInput is flaky. USB "just works".
2. **For wireless**, install [DS4Windows](https://ds4windows.com), keep it
   running — your pad then appears as XInput (covered by our XInput profile).
3. **Bluetooth pairing:** hold PS + Share until the light flashes, then add
   the "Wireless Controller" in Windows Bluetooth settings.

### Xbox Controller Issues

1. **Xbox One/Series:** USB-C cable always works. Wireless needs the Xbox
   Wireless Adapter for Windows (or Bluetooth on newer models).
2. **Xbox 360 wireless** needs the 360 wireless receiver + driver.
3. Update firmware via the Xbox Accessories app (Microsoft Store).

### Switch Pro / 8BitDo

- Pair in Windows Bluetooth settings first (8BitDo: use **X mode** for
  best compatibility — covered by our XInput profile).
- Test with `Tools\test-controller.bat`.

---

## 🎯 Game Issues

### No Games Showing in Launcher

**Problem:** Launcher shows "0 games" for all systems

**Solutions:**

1. **Add ROM files** to the right folders (`ROMs\NES\`, `ROMs\SNES\`, …).
   Zipped ROMs work for cartridge systems.
2. **Download samples:** run `Tools\download-roms.bat` → sample pack.
3. **Rescan:** press **R** in the launcher (systems view) — no restart needed.
4. **Check extensions:** `organize-roms` files anything it recognizes; run
   `Tools\organize-roms.bat -StatsOnly` to see what was detected.

### Game Won't Load

**Problem:** Selected game doesn't start or shows an error

**The launcher now tells you why** (on-screen toast + `Logs\launcher.log`).
Common causes:

1. **Missing core** — run `Tools\update-system.bat` → option 1, or
   `Tools\diagnose.bat` → repair.
2. **Missing BIOS** (PlayStation, Dreamcast, NDS, Neo Geo) — see
   `Configs\BIOS-INFO.txt`; `diagnose.bat` lists exactly what's missing.
3. **Corrupt ROM** — 0-byte files and bad dumps fail; try another dump.
4. **Check logs:** `Emulators\RetroArch\logs\` and `Logs\launcher.log`.

### Black Screen When Loading Game

1. Wait 10–15 seconds (PS1/N64 cores initialize slowly).
2. Missing BIOS is the #1 cause — check `diagnose.bat`.
3. Press F1 → Information → Core Information to verify the right core loaded.
4. Try another video driver: F1 → Settings → Drivers → Video
   (d3d11 → gl → vulkan).

### "Core not found for …"

Your `systems.json` names a core that isn't installed (v1.x had an N64
mismatch: `mupen64plus` vs `mupen64plus_next`). v2.0 ships the fixed config;
if you customized it, run the self-test to validate:

```
LAUNCH.bat --self-test
```

---

## 💻 Display Issues

### Launcher Window Too Small/Large

- Press **F11** to toggle fullscreen.
- The launcher auto-detects 4K and starts fullscreen there.
- Force a mode: `LAUNCH.bat --fullscreen` / `LAUNCH.bat --windowed`.
- Windows Settings → Display → Scale 100–125% works best.

### Game Has Wrong Aspect Ratio

1. In-game menu (F1) → Settings → Video → Aspect Ratio → "Core Provided".
2. Integer Scale → ON gives pixel-perfect scaling.
3. Our default config already sets core-provided aspect; if you changed it,
   re-run SETUP (your old config is backed up as `retroarch.cfg.previous`).

### Screen Tearing

1. Enable VSync: F1 → Settings → Video → VSync → ON (default in our config).
2. Set your monitor to its highest refresh rate (60 Hz minimum).

---

## 🐌 Performance Issues

### Slow/Laggy Gameplay

1. **Use a blue USB 3.0 port** — USB 2.0 is ~10× slower at loading.
2. Close Chrome/Discord/etc.
3. Disable shaders: F1 → Quick Menu → Shaders → Remove.
4. Lower internal resolution (N64/PS1/PSP/Dreamcast): F1 → Quick Menu →
   Core Options → Internal Resolution → 1x.
5. Older PCs: stick to NES/SNES/Genesis/GBA; N64/PSP/Dreamcast need muscle.

### Input Lag

1. Prefer USB cable over Bluetooth.
2. F1 → Settings → Latency → Run-Ahead → Enable, 1–2 frames.
3. F1 → Settings → Audio → Audio Latency → 32–64 ms.

---

## 📁 File Issues

### Can't Find Save Files

Saves live in **`Save States\`** (configured automatically):

- **Save states:** F2 quick-save / F4 quick-load in game (all systems).
- **In-game saves:** use the game's own save; files land in `Save States\`.
- **Backup:** run `Tools\update-system.bat` → option 5 (backs up configs,
  saves, screenshots, launcher, and BIOS).

### USB Drive Doesn't Work on Another PC

1. **Drive letter changed** — normal; all scripts/launchers resolve paths
   relative to themselves. Just run LAUNCH.bat from the new letter.
2. **Python missing on the new PC** — run SETUP.bat there (it can
   auto-install Python) or install Python with "Add to PATH".
3. **Antivirus blocking** — add an exclusion for your USB drive / the
   `Emulators\RetroArch\` folder (see below).

### ROM Organizer Put Files in the Wrong System

- `.zip` is ambiguous (MAME vs Neo Geo vs zipped cartridge ROMs). Run once
  per source folder with `-DefaultZipSystem`:
  ```
  Tools\organize-roms.bat -SourceFolder C:\NeoGeoDumps -DefaultZipSystem NeoGeo
  ```
- Orphan `.bin` files default to Genesis (tiny ≤64 KB ones go to Atari 2600);
  if a `.bin` sits next to its `.cue`/`.gdi`, it follows the disc system.
- Use `-DryRun` first to preview any batch.

---

## 🔒 Security Issues

### Antivirus Warns About Files

Emulators and PowerShell scripts are frequent false positives. Files come
from official sources (libretro buildbot, python.org, winget).

1. Add the whole suite folder (or at least `Emulators\RetroArch\`) to your
   antivirus exclusions.
2. Only disable real-time scanning temporarily during setup/games.

### Windows SmartScreen Warning

"Windows protected your PC" → More info → Run anyway. Normal for unsigned
open-source apps.

---

## 🌐 Download Issues

### Sample ROM Download Fails

1. Check internet (open any website).
2. The tool auto-discovers files via the archive.org API; if an item was
   removed it falls back to live search, then prints a manual browse link.
3. Preview without downloading: `Tools\download-roms.bat -System NES -ListOnly`.
4. Manual fallback: search "<system> homebrew" on archive.org / itch.io,
   drop files into `ROMs\<system>\`, press R in the launcher.

### Core Download Fails During Setup

1. `Tools\update-system.bat` → option 1 retries just the cores.
2. `Tools\diagnose.bat` → repair installs only the missing ones.
3. Manual: run `Emulators\RetroArch\retroarch.exe` → Online Updater →
   Core Downloader, or drop `.dll`s into `Emulators\RetroArch\cores\`.

---

## 🐧 Linux / macOS Issues

### `./setup.sh: Permission denied`

```bash
chmod +x setup.sh launch.sh
./setup.sh
```

### RetroArch Not Installed

`setup.sh` tries apt/dnf/pacman/zypper/Homebrew. Alternatives:

```bash
flatpak install flathub org.libretro.RetroArch
```

then re-run `./setup.sh` (it detects `retroarch` on PATH and links it).

### No Display / SSH Session

The launcher detects headless Linux and drops to text mode automatically.
Force it: `./launch.sh --text`.

### Controllers on Linux

- The setup uses `udev` joypad drivers. Add your user to the `input` group
  if pads aren't detected: `sudo usermod -aG input $USER` (log out/in).
- Test: `python3 Launcher/launcher.py --check` won't test pads; use the
  RetroArch GUI (Settings → Input) or `jstest` from `joystick` package.

---

## 🆘 Still Having Issues?

### One-Click Reset Ladder (try in order)

1. `Tools\diagnose.bat` → accept auto-repair.
2. `Tools\update-system.bat` → option 6 (update everything).
3. Delete `Emulators\RetroArch\retroarch.cfg` → re-run SETUP.bat
   (regenerates config; your saves/ROMs are untouched).
4. Clean reinstall: delete `Emulators\RetroArch\` (keep `ROMs\` and
   `Save States\`), re-run SETUP.bat.

### Log Files

- **Launcher:** `Logs\launcher.log`
- **Setup/diagnose:** `Logs\setup-*.log`, `Logs\diagnose-*.log`
- **RetroArch:** `Emulators\RetroArch\logs\`
- **Terminal output:** run the launcher manually to see everything:
  ```
  cd Launcher
  python launcher.py --check
  ```

### Reporting Issues

Include: Windows version, the exact error (or screenshot), what you were
doing, plus the outputs of `python --version` and `LAUNCH.bat --check`.

---

**Most issues are solved by:**

- ✅ Running `Tools\diagnose.bat` and accepting the repair
- ✅ Running SETUP.bat as Administrator
- ✅ Using a USB 3.0 port
- ✅ Installing Python with "Add to PATH" (or letting SETUP do it)
- ✅ Adding BIOS files for PS1/Dreamcast/NDS/Neo Geo
- ✅ Connecting the controller before launching

Happy Gaming! 🎮
