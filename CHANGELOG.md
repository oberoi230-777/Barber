# Changelog

## v2.0.2 (2026-09-13) — LAUNCH.bat no longer closes silently

- FIXED: `LAUNCH.bat` flashed a console window and vanished when Python was
  broken or only the Windows Store stub was installed (`where python`
  finds the stub, which then exits instantly). The script now probes every
  candidate with `--version` (must exit 0) so the stub is skipped, shows a
  dedicated "Python Not Found" screen with Store-stub guidance, and —
  most importantly — NEVER closes silently on failure: any crash now
  shows the exit code, the Python version, the last 20 log lines, and a
  pause. The `.bat` exit code is also propagated to callers.
- ADDED: the launcher refuses to run on Python < 3.9 with a clear message
  (exit code 2) instead of a cryptic traceback.
- ADDED: regression tests (CLI subprocess smoke test + LAUNCH.bat static
  checks) and a "window closes instantly" troubleshooting section.

## v2.0.1 (2026-09-13) — Strict-mode crash fix

- FIXED: `Test-BiosFiles : The property 'bios' cannot be found on this
  object` crash during `SETUP` / `diagnose` / system-check. Under
  `Set-StrictMode -Version Latest`, reading an optional JSON property that
  a system doesn't define (most systems have no `bios` key) is a fatal
  error. Added a `Get-ObjectProperty` helper (null/dictionary/PSObject
  safe) and routed every optional `ConvertFrom-Json` property through it:
  `Test-BiosFiles`, `Get-VersionInfo`, `Ensure-PortableFolders`,
  organizer `Get-ExtensionMap`, and both archive.org JSON parsers in the
  ROM downloader.
- ADDED: `tests/test_ps_static.py` — 7 regression tests that parse the
  actual `.ps1` sources and fail if any hardened function regresses to
  direct strict-unsafe property access.

## v2.0.0 (2026-09-13) — "Fully working & super automated"

### Launcher (`Launcher/launcher.py`) — rebuilt
- FIXED: systems list had **no scrolling** — with 14+ systems the bottom
  entries were unreachable. Both lists now scroll with scrollbars.
- FIXED: emoji icons rendered as tofu boxes (default pygame font has no
  emoji). Icons are now text badges (`[NES]`, `[SNES]`, …) with an emoji
  stripper for any custom text.
- FIXED: scanner only matched lowercase extensions in the top folder. It is
  now **recursive + case-insensitive** and supports `.zip`/`.7z` for
  cartridge systems.
- FIXED: `.bin` track files listed alongside their `.cue`/`.gdi` (double
  entries). Companion files are now hidden and launch via the descriptor.
- FIXED: N64 core mismatch (`mupen64plus` configured, `mupen64plus_next`
  downloaded) — games failed to launch. Fixed everywhere + alias map added.
- FIXED: missing RetroArch/cores failed silently (console-only message).
  The GUI now shows on-screen toasts + a status dot.
- FIXED: display restore after quitting a game lost fullscreen state.
- FIXED: no controller hotplug (pads connected after start were ignored).
- ADDED: **text-mode UI** (`--text`) + automatic GUI→text fallback, so the
  launcher never hard-crashes (missing pygame/display).
- ADDED: automatic `pygame-ce` install attempt when pygame is missing.
- ADDED: type-to-search, favorites (F5/Y, persisted), favorites-only
  filter (F6/X), rescan (R), help screen (F1), PageUp/PageDown/Home/End.
- ADDED: CLI automation: `--scan`, `--check`, `--launch System/Game`,
  `--self-test`, `--fullscreen`/`--windowed`, `--version`.
- ADDED: file logging (`Logs/launcher.log`), recent-plays tracking,
  per-system BIOS warnings, missing-core badges.
- ADDED: cross-platform RetroArch detection (Windows/macOS/Linux/PATH).

### Configs
- `systems.json`: fixed N64 core, added **Nintendo DS** system, added
  `zip`/`7z` extensions, explicit `core` field, per-system `bios` lists,
  text-safe icons.
- `retroarch.cfg`: removed all contradictory duplicate keys, removed the
  hardcoded 3840×2160 viewport (broke 1080p), kept fully portable paths.
- `core-options.cfg`: refreshed for current cores, added NDS (DeSmuME)
  section — and it is now **actually installed** (v1.x never copied it!).
- `autoconfig/`: fixed **Xbox button conflicts** (Start/Back shared
  indexes with triggers), cleaned PS4 profile, reorganized into
  `dinput/` + `xinput/` subfolders (required by RetroArch), added generic
  XInput and Switch Pro profiles.
- `BIOS-INFO.txt`: removed incorrect/truncated MD5 hashes (now points at
  RetroArch's built-in verifier), added one-command auto-check.

### Setup & automation (PowerShell)
- `SETUP.ps1`: **unattended mode** (`-Unattended`, `-InstallPython`,
  `-IncludeSampleRoms`), automatic Python install via winget, internet +
  disk-space preflight checks, full logging (`Logs/setup-*.log`), BIOS
  report, final health summary.
- `SETUP.bat`: forwards arguments, `pwsh` fallback, no more forced pause
  on success.
- `LAUNCH.bat`: forwards CLI args to the launcher, warns when setup is
  pending instead of failing cryptically.
- `ps-common.ps1`: download **retries**, 7-Zip auto-install via winget,
  safe `.7z` extraction (no more broken inline quoting), stable-version
  auto-detection from the buildbot listing (no more fragile homepage
  scraping), `desmume` core added, core options + autoconfig tree +
  folder structure now fully installed, new `Repair-Installation` /
  `Get-RetroGamingAudit` / `Test-BiosFiles` automation APIs.
- `update-system.ps1`: FIXED — RetroArch reinstall **no longer wipes your
  cores/BIOS/playlists** (preserved + merged). Added `All` action and BIOS
  to backups.
- `download-roms.ps1`: replaced **fake/broken archive.org URLs** with
  verified items + live metadata auto-discovery + live search fallback,
  dynamic menu, `-System All`, case-insensitive names, `-ListOnly` preview.
- `organize-roms.ps1`: now driven by `systems.json` (single source of
  truth), cue/gdi/m3u companion handling, `neogeo.zip`→BIOS routing,
  `-DryRun` preview, name-collision protection, recursive stats.
- `organize-roms.bat`: **created** (was missing — the tool couldn't be
  double-clicked).
- `test-controller.ps1`: added `-TextOnly` mode + rumble test (R key).
- `diagnose.ps1` (+`.bat`): **new** one-click health check + auto-repair
  (`-Fix`), JSON output (`-Json`), runs the launcher self-test.

### Cross-platform
- NEW `setup.sh` / `launch.sh` for Linux/macOS: package-manager RetroArch
  install, buildbot `.so`/`.dylib` cores, translated config, unattended
  `--yes` mode.

### Quality gates
- NEW `tests/test_launcher.py` (17 tests incl. regression tests for the
  N64 core mismatch, Xbox button collision, config duplicates).
- NEW GitHub Actions CI: pytest on 3 Python versions, headless GUI smoke
  test, JSON validation, shell syntax check, Windows PowerShell parser +
  PSScriptAnalyzer checks.
- NEW `.gitignore` (binaries, ROMs, saves, logs excluded); removed
  accidentally committed `__pycache__`.

### Docs
- Rewrote `README.md`, `QUICK-START.txt`, `TROUBLESHOOTING.md` for v2.0;
  removed hardcoded drive letters; documented every tool flag and the
  Linux/macOS flow.
