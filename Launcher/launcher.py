#!/usr/bin/env python3
"""
Portable Retro Gaming Launcher v2.0
A robust, automated game launcher with 4K support, controller navigation,
text-mode fallback, CLI automation, search, favorites, and health checks.

Runs headless-safe: if no display/pygame is available it falls back to a
terminal UI instead of crashing.

Usage:
    python launcher.py                  # graphical launcher (auto-fallback to text UI)
    python launcher.py --text           # terminal launcher
    python launcher.py --scan           # scan ROMs and print library summary
    python launcher.py --check          # health check (RetroArch/cores/ROMs/BIOS)
    python launcher.py --launch NES/MyGame  # launch a game directly
    python launcher.py --self-test      # run built-in self tests
"""

import argparse
import json
import logging
import os
import re
import subprocess
import sys
import unicodedata
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# Paths & logging (set up before anything else so failures are diagnosable)
# ---------------------------------------------------------------------------

BASE_PATH = Path(__file__).resolve().parent.parent
ROMS_PATH = BASE_PATH / "ROMs"
EMULATORS_PATH = BASE_PATH / "Emulators"
CONFIG_PATH = BASE_PATH / "Configs"
LOGS_PATH = BASE_PATH / "Logs"
RETROARCH_PATH = EMULATORS_PATH / "RetroArch"
SYSTEMS_JSON = CONFIG_PATH / "systems.json"
FAVORITES_JSON = CONFIG_PATH / "favorites.json"
RECENT_JSON = CONFIG_PATH / "recent.json"
VERSION_JSON = BASE_PATH / "version.json"

try:
    LOGS_PATH.mkdir(parents=True, exist_ok=True)
except OSError:
    pass

LOG_FILE = LOGS_PATH / "launcher.log"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE, encoding="utf-8"),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("launcher")


def get_version() -> str:
    try:
        with open(VERSION_JSON, "r", encoding="utf-8") as f:
            return str(json.load(f).get("version", "2.0.0"))
    except (OSError, ValueError):
        return "2.0.0"


VERSION = get_version()

# ---------------------------------------------------------------------------
# Optional pygame import with auto-install attempt.
# The launcher must NEVER hard-crash just because pygame is missing.
# ---------------------------------------------------------------------------

pygame = None  # type: ignore
PYGAME_ERROR = ""


def _try_import_pygame() -> bool:
    global pygame, PYGAME_ERROR
    os.environ.setdefault("PYGAME_HIDE_SUPPORT_PROMPT", "1")
    try:
        import pygame as _pg  # type: ignore

        pygame = _pg
        return True
    except ImportError as exc:
        PYGAME_ERROR = str(exc)
        return False


def ensure_pygame(auto_install: bool = True) -> bool:
    """Make sure pygame is importable, optionally auto-installing pygame-ce."""
    if _try_import_pygame():
        return True
    if not auto_install:
        return False
    # Super-automated: try to install pygame-ce on the fly (once).
    log.warning("pygame not found, attempting automatic install of pygame-ce...")
    print("pygame not found. Attempting automatic install (pygame-ce)...")
    try:
        subprocess.run(
            [sys.executable, "-m", "pip", "install", "--user", "pygame-ce"],
            check=False,
            timeout=300,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        log.error("Automatic pygame install failed: %s", exc)
        return False
    if _try_import_pygame():
        log.info("pygame-ce installed successfully.")
        return True
    log.error("pygame is still unavailable after auto-install attempt.")
    return False


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_EMOJI_RE = re.compile(
    "["
    "\U0001F000-\U0001FAFF"  # emoticons, symbols, pictographs
    "\U00002600-\U000027BF"  # misc symbols, dingbats
    "\U00002B00-\U00002BFF"
    "\U0000FE00-\U0000FE0F"  # variation selectors
    "\U0001F900-\U0001F9FF"
    "]+",
    flags=re.UNICODE,
)


def safe_text(text: str) -> str:
    """Strip emoji / glyphs the default pygame font cannot render.

    Prevents the 'tofu box' problem on systems without emoji fonts while
    keeping the text readable.
    """
    if not text:
        return ""
    cleaned = _EMOJI_RE.sub("", text)
    # Drop any remaining non-printable / unrenderable characters.
    cleaned = "".join(
        ch for ch in cleaned if ch == " " or unicodedata.category(ch)[0] != "C"
    )
    cleaned = re.sub(r"\s{2,}", " ", cleaned).strip()
    return cleaned or text.strip()


def format_size(num_bytes: int) -> str:
    size = float(num_bytes)
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024 or unit == "GB":
            if unit == "B":
                return "%d %s" % (int(size), unit)
            return "%.1f %s" % (size, unit)
        size /= 1024
    return "%.1f GB" % size


def find_retroarch_exe() -> Optional[Path]:
    """Locate the RetroArch executable (portable install first, then PATH)."""
    if os.name == "nt":
        candidates = [
            RETROARCH_PATH / "retroarch.exe",
            EMULATORS_PATH / "retroarch.exe",
        ]
    else:
        candidates = [
            RETROARCH_PATH / "retroarch",
            RETROARCH_PATH / "retroarch.exe",
            EMULATORS_PATH / "retroarch",
        ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    # Fall back to system PATH (Linux/macOS package installs).
    path_exe = shutil_which("retroarch")
    if path_exe:
        return Path(path_exe)
    return None


def shutil_which(cmd: str) -> Optional[str]:
    import shutil

    return shutil.which(cmd)


# Core name aliases: map legacy / shorthand names to real libretro core files.
CORE_ALIASES = {
    "mupen64plus": "mupen64plus_next",
    "mupen64plus-next": "mupen64plus_next",
    "mupen64plus_next": "mupen64plus_next",
    "snes9x_next": "snes9x",
    "genesisplusgx": "genesis_plus_gx",
    "genesis-plus-gx": "genesis_plus_gx",
    "picodrive": "picodrive",
    "pcsx-rearmed": "pcsx_rearmed",
    "mame": "mame2003_plus",
    "mame2003-plus": "mame2003_plus",
    "fbneo": "fbneo",
    "finalburnneo": "fbneo",
    "melonds": "melonds",
    "desmume": "desmume",
}


def resolve_core_path(core_name: str) -> Optional[Path]:
    """Resolve a configured core name to a real libretro core file."""
    raw = core_name.strip().strip("\"'")
    raw = CORE_ALIASES.get(raw.lower(), raw)
    cores_path = RETROARCH_PATH / "cores"

    suffix = ".dll" if os.name == "nt" else ".so"
    direct: List[Path] = []
    candidate = Path(raw)
    if candidate.suffix.lower() in (".dll", ".so", ".dylib"):
        if candidate.is_absolute() and candidate.exists():
            return candidate
        direct.extend(
            [
                RETROARCH_PATH / candidate,
                cores_path / candidate.name,
            ]
        )
    else:
        direct.extend(
            [
                cores_path / ("%s_libretro%s" % (raw, suffix)),
                cores_path / ("%s%s" % (raw, suffix)),
            ]
        )
    for path in direct:
        if path.exists():
            return path
    # Fuzzy: e.g. "snes9x" matches "snes9x_libretro.dll"
    if cores_path.exists():
        matches = sorted(cores_path.glob("%s*_libretro%s" % (raw, suffix)))
        if matches:
            return matches[0]
    return None


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------


class GameSystem:
    """Represents a gaming system/console."""

    # Disc-image stems: hide the raw track file when a cue/m3u/gdi exists.
    CUE_COMPANIONS = {".cue", ".m3u", ".gdi"}
    HIDDEN_COMPANIONS = {".bin", ".img"}

    ARCHIVE_EXTS = {".zip", ".7z"}

    def __init__(
        self,
        name: str,
        folder: str,
        extensions: List[str],
        emulator: str = "retroarch",
        core: str = "",
        icon: str = "",
        bios: Optional[List[str]] = None,
        description: str = "",
    ):
        self.name = name
        self.folder = folder
        self.extensions = [str(e).lower().lstrip(".") for e in extensions]
        self.emulator = emulator
        self.core = core
        self.icon = icon
        self.bios = bios or []
        self.description = description
        self.games: List[Dict] = []

    @property
    def short_name(self) -> str:
        text = safe_text(self.icon)
        return text if text else self.folder[:3].upper()

    def core_name(self) -> str:
        if self.core:
            return self.core
        # Legacy: parse "retroarch -L <core>" strings.
        parts = self.emulator.split()
        if "-L" in parts:
            idx = parts.index("-L") + 1
            if idx < len(parts):
                return parts[idx]
        return ""

    def scan_games(self, roms_path: Path) -> int:
        """Recursively scan for games (case-insensitive)."""
        self.games = []
        system_path = roms_path / self.folder
        if not system_path.exists():
            return 0

        wanted = set(self.extensions)
        found: List[Path] = []
        for rom_file in system_path.rglob("*"):
            if not rom_file.is_file():
                continue
            if rom_file.name.startswith("."):
                continue
            ext = rom_file.suffix.lower().lstrip(".")
            if ext in wanted:
                found.append(rom_file)

        # Hide companion track files when a cue/m3u/gdi with the same stem exists.
        cue_stems = {
            f.stem.lower()
            for f in found
            if f.suffix.lower() in self.CUE_COMPANIONS
        }
        visible = [
            f
            for f in found
            if not (
                f.suffix.lower() in self.HIDDEN_COMPANIONS
                and f.stem.lower() in cue_stems
            )
        ]

        for rom_file in visible:
            try:
                size = rom_file.stat().st_size
            except OSError:
                size = 0
            self.games.append(
                {
                    "name": rom_file.stem,
                    "path": str(rom_file),
                    "size": size,
                    "ext": rom_file.suffix.lower().lstrip("."),
                }
            )
        self.games.sort(key=lambda g: g["name"].lower())
        return len(self.games)


DEFAULT_SYSTEMS: List[Dict] = [
    {"name": "Nintendo Entertainment System", "folder": "NES",
     "extensions": ["nes", "unf", "unif", "zip", "7z"],
     "core": "fceumm", "emulator": "retroarch -L fceumm", "icon": "NES"},
    {"name": "Super Nintendo", "folder": "SNES",
     "extensions": ["smc", "sfc", "fig", "swc", "bs", "zip", "7z"],
     "core": "snes9x", "emulator": "retroarch -L snes9x", "icon": "SNES"},
    {"name": "Nintendo 64", "folder": "N64",
     "extensions": ["n64", "z64", "v64", "zip", "7z"],
     "core": "mupen64plus_next", "emulator": "retroarch -L mupen64plus_next",
     "icon": "N64"},
    {"name": "Game Boy / Game Boy Color", "folder": "GameBoy",
     "extensions": ["gb", "gbc", "zip", "7z"],
     "core": "gambatte", "emulator": "retroarch -L gambatte", "icon": "GB"},
    {"name": "Game Boy Advance", "folder": "GBA",
     "extensions": ["gba", "zip", "7z"],
     "core": "mgba", "emulator": "retroarch -L mgba", "icon": "GBA",
     "bios": ["gba_bios.bin"]},
    {"name": "Nintendo DS", "folder": "NDS",
     "extensions": ["nds", "zip", "7z"],
     "core": "desmume", "emulator": "retroarch -L desmume", "icon": "NDS",
     "bios": ["bios7.bin", "bios9.bin", "firmware.bin"]},
    {"name": "Sega Genesis / Mega Drive", "folder": "Genesis",
     "extensions": ["md", "bin", "gen", "smd", "32x", "zip", "7z"],
     "core": "genesis_plus_gx", "emulator": "retroarch -L genesis_plus_gx",
     "icon": "GEN"},
    {"name": "Sega Master System", "folder": "MasterSystem",
     "extensions": ["sms", "sg", "zip", "7z"],
     "core": "genesis_plus_gx", "emulator": "retroarch -L genesis_plus_gx",
     "icon": "SMS"},
    {"name": "Sega Game Gear", "folder": "GameGear",
     "extensions": ["gg", "zip", "7z"],
     "core": "genesis_plus_gx", "emulator": "retroarch -L genesis_plus_gx",
     "icon": "GG"},
    {"name": "PlayStation", "folder": "PlayStation",
     "extensions": ["cue", "m3u", "chd", "pbp", "iso", "bin"],
     "core": "pcsx_rearmed", "emulator": "retroarch -L pcsx_rearmed",
     "icon": "PS1", "bios": ["scph1001.bin"]},
    {"name": "Arcade (MAME)", "folder": "Arcade",
     "extensions": ["zip", "7z"],
     "core": "mame2003_plus", "emulator": "retroarch -L mame2003_plus",
     "icon": "ARC"},
    {"name": "Neo Geo", "folder": "NeoGeo",
     "extensions": ["zip", "7z"],
     "core": "fbneo", "emulator": "retroarch -L fbneo", "icon": "NEO",
     "bios": ["neogeo.zip"]},
    {"name": "Atari 2600", "folder": "Atari2600",
     "extensions": ["a26", "bin", "zip", "7z"],
     "core": "stella", "emulator": "retroarch -L stella", "icon": "A26"},
    {"name": "Sega Dreamcast", "folder": "Dreamcast",
     "extensions": ["cdi", "gdi", "chd", "m3u"],
     "core": "flycast", "emulator": "retroarch -L flycast", "icon": "DC",
     "bios": ["dc_boot.bin", "dc_flash.bin"]},
    {"name": "PlayStation Portable", "folder": "PSP",
     "extensions": ["iso", "cso", "pbp", "chd"],
     "core": "ppsspp", "emulator": "retroarch -L ppsspp", "icon": "PSP"},
]


def load_systems(config_path: Path = SYSTEMS_JSON) -> List[GameSystem]:
    """Load system configs, creating/sanitizing systems.json as needed."""
    systems_data: Optional[List[Dict]] = None
    if config_path.exists():
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                loaded = json.load(f)
            if isinstance(loaded, list) and loaded:
                systems_data = loaded
            else:
                log.warning("systems.json is empty/invalid, using defaults.")
        except (OSError, ValueError) as exc:
            log.warning("Could not parse systems.json (%s), using defaults.", exc)
    if systems_data is None:
        systems_data = DEFAULT_SYSTEMS
        try:
            config_path.parent.mkdir(parents=True, exist_ok=True)
            with open(config_path, "w", encoding="utf-8") as f:
                json.dump(systems_data, f, indent=2)
            log.info("Wrote default systems.json")
        except OSError as exc:
            log.warning("Could not write systems.json: %s", exc)

    systems: List[GameSystem] = []
    for entry in systems_data:
        try:
            systems.append(
                GameSystem(
                    name=str(entry.get("name", entry.get("folder", "Unknown"))),
                    folder=str(entry.get("folder", "Unknown")),
                    extensions=list(entry.get("extensions", [])),
                    emulator=str(entry.get("emulator", "retroarch")),
                    core=str(entry.get("core", "")),
                    icon=str(entry.get("icon", "")),
                    bios=list(entry.get("bios", []) or []),
                    description=str(entry.get("description", "")),
                )
            )
        except (AttributeError, TypeError) as exc:
            log.warning("Skipping invalid system entry %r: %s", entry, exc)
    return systems or [GameSystem(**d) for d in DEFAULT_SYSTEMS]


def ensure_rom_folders(systems: List[GameSystem]) -> None:
    ROMS_PATH.mkdir(parents=True, exist_ok=True)
    for system in systems:
        try:
            (ROMS_PATH / system.folder).mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            log.warning("Could not create ROM folder %s: %s", system.folder, exc)


def scan_all_systems(
    systems: List[GameSystem], verbose: bool = True
) -> Tuple[int, Dict[str, int]]:
    counts: Dict[str, int] = {}
    total = 0
    for system in systems:
        count = system.scan_games(ROMS_PATH)
        counts[system.folder] = count
        total += count
        if verbose and count:
            log.info("  %s: %d game(s)", system.name, count)
    if verbose:
        log.info("Total games found: %d", total)
    return total, counts


def load_json_list(path: Path) -> List[str]:
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return [str(x) for x in data] if isinstance(data, list) else []
    except (OSError, ValueError):
        return []


def save_json_list(path: Path, items: List[str]) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(items, f, indent=2)
    except OSError as exc:
        log.warning("Could not save %s: %s", path, exc)


# ---------------------------------------------------------------------------
# Health check (shared by --check, text UI, GUI status bar, and diagnose tool)
# ---------------------------------------------------------------------------


def health_check(systems: Optional[List[GameSystem]] = None) -> Dict:
    systems = systems if systems is not None else load_systems()
    ensure_rom_folders(systems)
    total, counts = scan_all_systems(systems, verbose=False)

    retro_exe = find_retroarch_exe()
    cores_dir = RETROARCH_PATH / "cores"
    core_files = (
        sorted(p.name for p in cores_dir.glob("*_libretro.*"))
        if cores_dir.exists()
        else []
    )

    missing_cores: List[str] = []
    for system in systems:
        core = system.core_name()
        if core and resolve_core_path(core) is None:
            missing_cores.append("%s (%s)" % (system.folder, core))

    bios_dir = RETROARCH_PATH / "system"
    missing_bios: List[str] = []
    for system in systems:
        for bios_file in system.bios:
            if not (bios_dir / bios_file).exists():
                missing_bios.append("%s/%s" % (system.folder, bios_file))

    ok = retro_exe is not None
    return {
        "version": VERSION,
        "python": sys.version.split()[0],
        "pygame": bool(pygame),
        "retroarch": str(retro_exe) if retro_exe else None,
        "cores_found": core_files,
        "core_count": len(core_files),
        "missing_cores": sorted(set(missing_cores)),
        "missing_bios": sorted(set(missing_bios)),
        "total_games": total,
        "games_by_system": counts,
        "roms_path": str(ROMS_PATH),
        "healthy": ok,
    }


def print_health(report: Dict) -> int:
    print("=" * 60)
    print("  Retro Gaming Suite v%s - Health Check" % report["version"])
    print("=" * 60)
    print("Python:            %s" % report["python"])
    print("pygame:            %s" % ("OK" if report["pygame"] else "MISSING"))
    print("RetroArch:         %s" % (report["retroarch"] or "NOT INSTALLED"))
    print("Cores installed:   %d" % report["core_count"])
    print("Games found:       %d" % report["total_games"])
    for folder, count in sorted(report["games_by_system"].items()):
        if count:
            print("    %-14s %d" % (folder, count))
    if report["missing_cores"]:
        print("Missing cores:")
        for item in report["missing_cores"]:
            print("    - %s" % item)
    if report["missing_bios"]:
        print("Missing BIOS files (only needed for those systems):")
        for item in report["missing_bios"]:
            print("    - %s" % item)
    print("=" * 60)
    if not report["healthy"]:
        print("STATUS: RetroArch is missing. Run SETUP.bat (Windows) or")
        print("        setup.sh (Linux/macOS) to install it automatically.")
        return 1
    if report["missing_cores"]:
        print("STATUS: Ready, but some cores are missing. Run SETUP again or")
        print("        Tools/update-system (Action: Cores) to fetch them.")
        return 2
    print("STATUS: Ready to play!")
    return 0


# ---------------------------------------------------------------------------
# Game launching (shared by GUI, text UI, and --launch)
# ---------------------------------------------------------------------------


def build_launch_command(system: GameSystem, rom_path: str) -> List[str]:
    """Build the RetroArch command for a ROM.

    Supports per-system emulator templates with a {rom} placeholder, e.g.
    "retroarch -L mgba -f {rom}", plus the legacy "retroarch -L <core>".
    """
    retro_exe = find_retroarch_exe()
    if retro_exe is None:
        raise FileNotFoundError(
            "RetroArch not found. Run SETUP to install it automatically."
        )

    template = (system.emulator or "retroarch").strip()
    # Custom absolute emulator command (non-retroarch standalone emulators).
    if "{rom}" in template:
        cmd = [part.replace("{rom}", rom_path) for part in template.split()]
        if not Path(cmd[0]).is_absolute():
            first = EMULATORS_PATH / "RetroArch" / cmd[0]
            if first.exists():
                cmd[0] = str(first)
        return cmd

    parts = template.split()
    # Drop a leading "retroarch"/"retroarch.exe" token; we resolved the exe.
    if parts and Path(parts[0]).name.lower().startswith("retroarch"):
        parts = parts[1:]

    # Resolve -L <core> to a real core file.
    if "-L" in parts:
        idx = parts.index("-L") + 1
        if idx < len(parts):
            resolved = resolve_core_path(parts[idx])
            if resolved is None:
                raise FileNotFoundError(
                    "Emulator core '%s' is not installed for %s. "
                    "Run SETUP or Tools/update-system to download it."
                    % (parts[idx], system.name)
                )
            parts[idx] = str(resolved)
    elif system.core_name():
        resolved = resolve_core_path(system.core_name())
        if resolved is None:
            raise FileNotFoundError(
                "Emulator core '%s' is not installed for %s."
                % (system.core_name(), system.name)
            )
        parts = ["-L", str(resolved)] + parts

    config_file = RETROARCH_PATH / "retroarch.cfg"
    if config_file.exists():
        parts = ["--config", str(config_file)] + parts

    return [str(retro_exe)] + parts + [rom_path]


def launch_rom(system: GameSystem, rom_path: str) -> int:
    cmd = build_launch_command(system, rom_path)
    log.info("Launching: %s", " ".join(cmd))
    print("Launching: %s" % Path(rom_path).name)
    try:
        completed = subprocess.run(cmd, cwd=str(RETROARCH_PATH))
        return completed.returncode
    except FileNotFoundError:
        raise
    except OSError as exc:
        raise RuntimeError("Failed to start emulator: %s" % exc)


def parse_launch_target(target: str) -> Tuple[str, str]:
    """Parse 'SystemFolder/Game name or index' launch targets."""
    target = target.strip().strip("\"'")
    parts = re.split(r"[\\/]", target, maxsplit=1)
    if len(parts) == 2:
        return parts[0].strip(), parts[1].strip()
    return "", target


def launch_by_target(
    systems: List[GameSystem], target: str
) -> int:
    folder, game = parse_launch_target(target)
    candidates = [
        s
        for s in systems
        if not folder or s.folder.lower() == folder.lower()
    ]
    if not candidates:
        print("Unknown system '%s'." % folder)
        print("Available systems: %s" % ", ".join(s.folder for s in systems))
        return 1
    for system in candidates:
        if not system.games:
            system.scan_games(ROMS_PATH)
        match = None
        if game.isdigit():
            idx = int(game)
            if 0 <= idx < len(system.games):
                match = system.games[idx]
        else:
            lowered = game.lower()
            for entry in system.games:
                if entry["name"].lower() == lowered:
                    match = entry
                    break
            if match is None:
                for entry in system.games:
                    if lowered in entry["name"].lower():
                        match = entry
                        break
        if match:
            try:
                return launch_rom(system, match["path"])
            except (FileNotFoundError, RuntimeError) as exc:
                print("ERROR: %s" % exc)
                return 1
    print("Game '%s' not found%s." % (game, " in %s" % folder if folder else ""))
    return 1


# ---------------------------------------------------------------------------
# Text-mode UI (terminal launcher incl. search, rescan, direct launch)
# ---------------------------------------------------------------------------


def run_text_ui(systems: List[GameSystem]) -> int:
    print("=" * 60)
    print("  Retro Gaming Suite v%s (text mode)" % VERSION)
    print("=" * 60)
    ensure_rom_folders(systems)
    scan_all_systems(systems, verbose=False)

    retro_exe = find_retroarch_exe()
    if retro_exe is None:
        print("WARNING: RetroArch is not installed. Games cannot launch yet.")
        print("Run SETUP.bat (Windows) or setup.sh (Linux/macOS) first.")
        print("")

    favorites = set(load_json_list(FAVORITES_JSON))

    def fav_key(system: GameSystem, game: Dict) -> str:
        return "%s/%s" % (system.folder, game["name"])

    current: Optional[GameSystem] = None
    while True:
        if current is None:
            print("\n--- Systems ---")
            for idx, system in enumerate(systems):
                marker = ""
                if system.core_name() and resolve_core_path(system.core_name()) is None:
                    marker = " [core missing]"
                print(
                    "  %2d. %-32s (%d games)%s"
                    % (idx + 1, system.name, len(system.games), marker)
                )
            print("   R. Rescan library    C. Health check    Q. Quit")
            choice = input("Select system: ").strip().lower()
            if choice in ("q", "quit", "exit"):
                return 0
            if choice == "r":
                scan_all_systems(systems)
                continue
            if choice == "c":
                print_health(health_check(systems))
                continue
            if not choice.isdigit() or not (1 <= int(choice) <= len(systems)):
                print("Invalid choice.")
                continue
            current = systems[int(choice) - 1]
            if not current.games:
                print("No games found for %s." % current.name)
                print("Copy ROMs into %s" % (ROMS_PATH / current.folder))
                current = None
        else:
            print("\n--- %s (%d games) ---" % (current.name, len(current.games)))
            names = [g["name"] for g in current.games]
            for idx, game in enumerate(current.games):
                star = "*" if fav_key(current, game) in favorites else " "
                print("  %s%3d. %s" % (star, idx + 1, game["name"][:70]))
            print("  S. Search    F. Toggle favorite    B. Back    Q. Quit")
            choice = input("Select game: ").strip().lower()
            if choice in ("q", "quit", "exit"):
                return 0
            if choice in ("b", "back"):
                current = None
                continue
            if choice == "s":
                query = input("Search: ").strip().lower()
                hits = [n for n in names if query in n.lower()]
                if not hits:
                    print("No matches.")
                else:
                    for n in hits[:20]:
                        print("    - %s" % n)
                continue
            if choice == "f":
                which = input("Favorite game number: ").strip()
                if which.isdigit() and 1 <= int(which) <= len(current.games):
                    key = fav_key(current, current.games[int(which) - 1])
                    if key in favorites:
                        favorites.discard(key)
                    else:
                        favorites.add(key)
                    save_json_list(FAVORITES_JSON, sorted(favorites))
                continue
            if not choice.isdigit() or not (1 <= int(choice) <= len(current.games)):
                print("Invalid choice.")
                continue
            game = current.games[int(choice) - 1]
            try:
                code = launch_rom(current, game["path"])
                if code != 0:
                    print("Emulator exited with code %d." % code)
            except (FileNotFoundError, RuntimeError) as exc:
                print("ERROR: %s" % exc)


# ---------------------------------------------------------------------------
# Graphical launcher (pygame)
# ---------------------------------------------------------------------------

COLOR_BG = (15, 15, 25)
COLOR_PANEL = (25, 25, 40)
COLOR_ACCENT = (88, 101, 242)
COLOR_ACCENT_HOVER = (115, 137, 255)
COLOR_TEXT = (255, 255, 255)
COLOR_TEXT_DIM = (150, 150, 160)
COLOR_SUCCESS = (67, 181, 129)
COLOR_WARNING = (250, 166, 26)
COLOR_ERROR = (240, 71, 71)

FPS = 60


class GameLauncherGUI:
    """Main graphical launcher."""

    def __init__(self, fullscreen: Optional[bool] = None):
        self.systems = load_systems()
        ensure_rom_folders(self.systems)
        scan_all_systems(self.systems)

        self.favorites = set(load_json_list(FAVORITES_JSON))
        self.recent: List[str] = load_json_list(RECENT_JSON)

        self.fullscreen_requested = fullscreen
        self.is_fullscreen = False
        self.setup_display(fullscreen)

        self.controllers: List = []
        self.setup_controllers()

        # UI state
        self.current_view = "systems"  # systems | games | help
        self.selected_system_idx = 0
        self.selected_game_idx = 0
        self.system_scroll = 0
        self.game_scroll = 0
        self.search_query = ""
        self.show_favorites_only = False
        self.toast_message = ""
        self.toast_until = 0
        self.toast_color = COLOR_WARNING
        self.running = False

        scale = max(0.6, self.screen_height / 1080)
        self.scale = scale
        self.font_huge = pygame.font.Font(None, int(64 * scale))
        self.font_large = pygame.font.Font(None, int(44 * scale))
        self.font_medium = pygame.font.Font(None, int(32 * scale))
        self.font_small = pygame.font.Font(None, int(22 * scale))

        self.clock = pygame.time.Clock()
        self.last_input_time = 0
        self.input_delay = 160

        # Startup warnings as on-screen toasts (never silent failures).
        if find_retroarch_exe() is None:
            self.show_toast(
                "RetroArch not installed - run SETUP to install automatically",
                COLOR_ERROR,
                duration_ms=8000,
            )
        elif sum(len(s.games) for s in self.systems) == 0:
            self.show_toast(
                "No ROMs found - copy games into ROMs/ or run download-roms",
                COLOR_WARNING,
                duration_ms=8000,
            )

    # -- display ------------------------------------------------------
    def setup_display(self, fullscreen: Optional[bool] = None) -> None:
        assert pygame is not None
        info = pygame.display.Info()
        want_fullscreen = fullscreen
        if want_fullscreen is None:
            want_fullscreen = bool(info.current_w and info.current_w >= 3840)
        flags = pygame.FULLSCREEN if want_fullscreen else pygame.RESIZABLE
        try:
            if want_fullscreen:
                self.screen = pygame.display.set_mode((0, 0), pygame.FULLSCREEN)
            else:
                size = (
                    min(1600, max(800, info.current_w - 100 if info.current_w else 1280)),
                    min(900, max(600, info.current_h - 100 if info.current_h else 800)),
                )
                self.screen = pygame.display.set_mode(size, pygame.RESIZABLE)
        except pygame.error:
            # Last resort: tiny windowed mode.
            self.screen = pygame.display.set_mode((800, 600))
            want_fullscreen = False
        self.is_fullscreen = bool(want_fullscreen)
        self.screen_width = self.screen.get_width()
        self.screen_height = self.screen.get_height()
        pygame.display.set_caption("Retro Gaming Suite v%s" % VERSION)

    def toggle_fullscreen(self) -> None:
        assert pygame is not None
        try:
            pygame.display.toggle_fullscreen()
            self.is_fullscreen = not self.is_fullscreen
        except (pygame.error, AttributeError):
            # Recreate the display with flipped flags.
            self.setup_display(fullscreen=not self.is_fullscreen)
            return
        self.screen_width = self.screen.get_width()
        self.screen_height = self.screen.get_height()

    def restore_display(self) -> None:
        assert pygame is not None
        try:
            flags = pygame.FULLSCREEN if self.is_fullscreen else pygame.RESIZABLE
            if self.is_fullscreen:
                self.screen = pygame.display.set_mode((0, 0), flags)
            else:
                self.screen = pygame.display.set_mode(
                    (self.screen_width, self.screen_height), flags
                )
        except pygame.error as exc:
            log.warning("Could not restore display: %s", exc)

    # -- controllers --------------------------------------------------
    def setup_controllers(self) -> None:
        assert pygame is not None
        try:
            pygame.joystick.init()
        except pygame.error:
            return
        self.controllers = []
        for i in range(pygame.joystick.get_count()):
            try:
                controller = pygame.joystick.Joystick(i)
                controller.init()
                self.controllers.append(controller)
                log.info("Controller detected: %s", controller.get_name())
            except pygame.error as exc:
                log.warning("Could not init joystick %d: %s", i, exc)

    def refresh_controllers(self) -> None:
        self.setup_controllers()

    # -- toast notifications ------------------------------------------
    def show_toast(
        self, message: str, color=COLOR_WARNING, duration_ms: int = 4000
    ) -> None:
        self.toast_message = safe_text(message)
        self.toast_color = color
        self.toast_until = pygame.time.get_ticks() + duration_ms
        log.warning("TOAST: %s", message)

    # -- filtering ----------------------------------------------------
    def visible_games(self, system: GameSystem) -> List[Dict]:
        games = system.games
        if self.show_favorites_only:
            games = [
                g
                for g in games
                if "%s/%s" % (system.folder, g["name"]) in self.favorites
            ]
        if self.search_query:
            query = self.search_query.lower()
            games = [g for g in games if query in g["name"].lower()]
        return games

    def fav_key(self, system: GameSystem, game: Dict) -> str:
        return "%s/%s" % (system.folder, game["name"])

    # -- navigation ---------------------------------------------------
    def navigate_up(self) -> None:
        if self.current_view == "systems":
            self.selected_system_idx = (self.selected_system_idx - 1) % len(self.systems)
        elif self.current_view == "games":
            games = self.visible_games(self.systems[self.selected_system_idx])
            if games:
                self.selected_game_idx = (self.selected_game_idx - 1) % len(games)

    def navigate_down(self) -> None:
        if self.current_view == "systems":
            self.selected_system_idx = (self.selected_system_idx + 1) % len(self.systems)
        elif self.current_view == "games":
            games = self.visible_games(self.systems[self.selected_system_idx])
            if games:
                self.selected_game_idx = (self.selected_game_idx + 1) % len(games)

    def page_move(self, direction: int) -> None:
        if self.current_view == "systems":
            self.selected_system_idx = (self.selected_system_idx + direction * 5) % len(
                self.systems
            )
        elif self.current_view == "games":
            games = self.visible_games(self.systems[self.selected_system_idx])
            if games:
                self.selected_game_idx = (self.selected_game_idx + direction * 5) % len(games)

    def select_item(self) -> None:
        if self.current_view == "systems":
            system = self.systems[self.selected_system_idx]
            if system.games:
                self.current_view = "games"
                self.selected_game_idx = 0
                self.game_scroll = 0
                self.search_query = ""
            else:
                self.show_toast(
                    "No games for %s - add ROMs to ROMs/%s"
                    % (system.name, system.folder)
                )
        elif self.current_view == "games":
            self.launch_selected_game()

    def go_back(self) -> None:
        if self.current_view == "games":
            self.current_view = "systems"
            self.search_query = ""
            self.show_favorites_only = False
        elif self.current_view == "help":
            self.current_view = self.view_before_help
        elif self.current_view == "systems":
            self.running = False

    def toggle_help(self) -> None:
        if self.current_view == "help":
            self.current_view = self.view_before_help
        else:
            self.view_before_help = self.current_view
            self.current_view = "help"

    def toggle_favorite(self) -> None:
        if self.current_view != "games":
            return
        system = self.systems[self.selected_system_idx]
        games = self.visible_games(system)
        if not games:
            return
        key = self.fav_key(system, games[self.selected_game_idx])
        if key in self.favorites:
            self.favorites.discard(key)
            self.show_toast("Removed from favorites", COLOR_TEXT_DIM, 2000)
        else:
            self.favorites.add(key)
            self.show_toast("Added to favorites", COLOR_SUCCESS, 2000)
        save_json_list(FAVORITES_JSON, sorted(self.favorites))

    def rescan(self) -> None:
        scan_all_systems(self.systems, verbose=False)
        total = sum(len(s.games) for s in self.systems)
        self.show_toast("Library rescanned: %d games" % total, COLOR_SUCCESS, 2500)

    # -- launching ----------------------------------------------------
    def launch_selected_game(self) -> None:
        assert pygame is not None
        system = self.systems[self.selected_system_idx]
        games = self.visible_games(system)
        if not games:
            return
        game = games[self.selected_game_idx]
        try:
            cmd = build_launch_command(system, game["path"])
        except (FileNotFoundError, RuntimeError) as exc:
            self.show_toast(str(exc), COLOR_ERROR, duration_ms=7000)
            return
        log.info("Launching: %s", game["name"])
        try:
            pygame.display.iconify()
            subprocess.run(cmd, cwd=str(RETROARCH_PATH))
        except OSError as exc:
            self.show_toast("Failed to launch: %s" % exc, COLOR_ERROR, 7000)
        finally:
            self.restore_display()
            # Record recent plays.
            key = self.fav_key(system, game)
            if key in self.recent:
                self.recent.remove(key)
            self.recent.insert(0, key)
            save_json_list(RECENT_JSON, self.recent[:20])

    # -- input --------------------------------------------------------
    def handle_events(self) -> None:
        assert pygame is not None
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                self.running = False
            elif event.type == pygame.VIDEORESIZE:
                if not self.is_fullscreen:
                    self.screen_width, self.screen_height = event.w, event.h
            elif event.type in (pygame.JOYDEVICEADDED, pygame.JOYDEVICEREMOVED):
                self.refresh_controllers()
            elif event.type == pygame.KEYDOWN:
                self.handle_keydown(event)
            elif event.type == pygame.JOYBUTTONDOWN:
                self.handle_joybutton(event.button)
            elif event.type == pygame.JOYHATMOTION:
                if event.value[1] > 0:
                    self.navigate_up()
                elif event.value[1] < 0:
                    self.navigate_down()
                elif event.value[0] != 0:
                    self.select_item() if event.value[0] > 0 else self.go_back()

    def handle_keydown(self, event) -> None:
        assert pygame is not None
        if event.key == pygame.K_F11:
            self.toggle_fullscreen()
        elif event.key == pygame.K_F1 or (
            event.key == pygame.K_h and pygame.key.get_mods() & pygame.KMOD_CTRL
        ):
            self.current_view = "help" if self.current_view != "help" else "systems"
        elif event.key == pygame.K_ESCAPE:
            if self.search_query:
                self.search_query = ""
            else:
                self.go_back()
        elif event.key == pygame.K_RETURN or event.key == pygame.K_KP_ENTER:
            self.select_item()
        elif event.key == pygame.K_UP:
            self.navigate_up()
        elif event.key == pygame.K_DOWN:
            self.navigate_down()
        elif event.key == pygame.K_PAGEUP:
            self.page_move(-1)
        elif event.key == pygame.K_PAGEDOWN:
            self.page_move(1)
        elif event.key == pygame.K_HOME:
            self.selected_game_idx = 0
            self.selected_system_idx = 0
        elif event.key == pygame.K_END:
            if self.current_view == "games":
                games = self.visible_games(self.systems[self.selected_system_idx])
                self.selected_game_idx = max(0, len(games) - 1)
            else:
                self.selected_system_idx = len(self.systems) - 1
        elif event.key == pygame.K_r and self.current_view == "systems":
            self.rescan()
        elif event.key == pygame.K_f and self.current_view == "games":
            self.toggle_favorite()
        elif event.key == pygame.K_v and self.current_view == "games":
            self.show_favorites_only = not self.show_favorites_only
            self.selected_game_idx = 0
        elif event.key == pygame.K_BACKSPACE:
            if self.current_view == "games" and self.search_query:
                self.search_query = self.search_query[:-1]
                self.selected_game_idx = 0
            else:
                self.go_back()
        elif self.current_view == "games" and event.unicode and event.unicode.isprintable():
            # Type-to-search.
            self.search_query += event.unicode
            self.selected_game_idx = 0

    def handle_joybutton(self, button: int) -> None:
        # Xbox layout: 0=A select, 1=B back, 2=X fav-filter, 3=Y favorite,
        # 9=start rescan on the systems view.
        if button == 0:
            self.select_item()
        elif button == 1:
            self.go_back()
        elif button == 2 and self.current_view == "games":
            self.show_favorites_only = not self.show_favorites_only
            self.selected_game_idx = 0
            self.game_scroll = 0
        elif button == 3 and self.current_view == "games":
            self.toggle_favorite()
        elif button == 9:
            if self.current_view == "systems":
                self.rescan()

    def handle_held_input(self) -> None:
        """Smooth scrolling for held directions (keyboard + analog sticks)."""
        assert pygame is not None
        now = pygame.time.get_ticks()
        if now - self.last_input_time < self.input_delay:
            return
        keys = pygame.key.get_pressed()
        moved = False
        if keys[pygame.K_UP]:
            self.navigate_up()
            moved = True
        elif keys[pygame.K_DOWN]:
            self.navigate_down()
            moved = True
        if not moved:
            for controller in self.controllers:
                try:
                    axis_y = (
                        controller.get_axis(1) if controller.get_numaxes() > 1 else 0
                    )
                except pygame.error:
                    continue
                if axis_y < -0.6:
                    self.navigate_up()
                    moved = True
                    break
                if axis_y > 0.6:
                    self.navigate_down()
                    moved = True
                    break
        if moved:
            self.last_input_time = now

    # -- drawing ------------------------------------------------------
    def draw_background(self) -> None:
        self.screen.fill(COLOR_BG)
        # Cheap gradient: a few translucent bands (fast even at 4K).
        bands = 24
        band_h = max(1, self.screen_height // bands)
        for i in range(bands):
            alpha = int(22 * (1 - i / bands))
            overlay = pygame.Surface((self.screen_width, band_h), pygame.SRCALPHA)
            overlay.fill((COLOR_ACCENT[0], COLOR_ACCENT[1], COLOR_ACCENT[2], alpha))
            self.screen.blit(overlay, (0, i * band_h))

    def draw_header(self) -> None:
        header_h = int(self.screen_height * 0.09)
        pygame.draw.rect(self.screen, COLOR_PANEL, (0, 0, self.screen_width, header_h))
        title = self.font_large.render(
            "RETRO GAMING  v%s" % VERSION, True, COLOR_ACCENT_HOVER
        )
        self.screen.blit(title, (20, (header_h - title.get_height()) // 2))
        if self.controllers:
            status_text = "%d controller(s)" % len(self.controllers)
            status_color = COLOR_SUCCESS
        else:
            status_text = "Keyboard mode"
            status_color = COLOR_TEXT_DIM
        # RetroArch status dot.
        dot_color = COLOR_SUCCESS if find_retroarch_exe() else COLOR_ERROR
        pygame.draw.circle(
            self.screen, dot_color, (self.screen_width - 220, header_h // 2), 8
        )
        status = self.font_small.render(status_text, True, status_color)
        self.screen.blit(
            status, (self.screen_width - 200, (header_h - status.get_height()) // 2)
        )

    def _list_layout(self) -> Tuple[int, int, int, int]:
        panel_w = int(self.screen_width * 0.84)
        panel_x = (self.screen_width - panel_w) // 2
        start_y = int(self.screen_height * 0.14)
        item_h = max(56, int(68 * self.scale))
        return panel_x, panel_w, start_y, item_h

    def draw_systems_view(self) -> None:
        panel_x, panel_w, start_y, item_h = self._list_layout()
        title = self.font_large.render("Select System", True, COLOR_TEXT)
        self.screen.blit(title, (panel_x, start_y))
        hint = self.font_small.render(
            "Type nothing here - Up/Down + Enter | PgUp/PgDn jump | R rescan | F1 help",
            True,
            COLOR_TEXT_DIM,
        )
        self.screen.blit(hint, (panel_x, start_y + int(52 * self.scale)))
        list_y = start_y + int(92 * self.scale)

        visible = max(1, (self.screen_height - list_y - 90) // item_h)
        # Keep selection visible (this was missing: long lists overflowed).
        if self.selected_system_idx < self.system_scroll:
            self.system_scroll = self.selected_system_idx
        elif self.selected_system_idx >= self.system_scroll + visible:
            self.system_scroll = self.selected_system_idx - visible + 1

        total_games = sum(len(s.games) for s in self.systems)
        count_label = self.font_small.render(
            "%d systems - %d games" % (len(self.systems), total_games),
            True,
            COLOR_TEXT_DIM,
        )
        self.screen.blit(count_label, (panel_x + panel_w - count_label.get_width(), start_y + 8))

        for row, idx in enumerate(
            range(self.system_scroll, min(len(self.systems), self.system_scroll + visible))
        ):
            system = self.systems[idx]
            y = list_y + row * item_h
            selected = idx == self.selected_system_idx
            rect = pygame.Rect(panel_x, y, panel_w, item_h - 8)
            pygame.draw.rect(
                self.screen, COLOR_ACCENT if selected else COLOR_PANEL, rect, border_radius=10
            )
            badge = "[%s]" % system.short_name
            name = self.font_medium.render(
                "%s %s" % (badge, safe_text(system.name)), True, COLOR_TEXT
            )
            self.screen.blit(name, (panel_x + 16, y + 8))
            detail_parts = ["%d games" % len(system.games)]
            if system.core_name() and resolve_core_path(system.core_name()) is None:
                detail_parts.append("core missing!")
            missing_bios = [
                b for b in system.bios if not (RETROARCH_PATH / "system" / b).exists()
            ]
            if missing_bios and system.bios:
                detail_parts.append("BIOS: %s?" % ", ".join(missing_bios[:2]))
            detail_color = COLOR_WARNING if len(detail_parts) > 1 else COLOR_TEXT_DIM
            detail = self.font_small.render(
                "   ".join(detail_parts), True, detail_color
            )
            self.screen.blit(detail, (panel_x + 16, y + int(36 * self.scale)))

        # Scrollbar.
        if len(self.systems) > visible:
            self.draw_scrollbar(panel_x + panel_w + 8, list_y, visible, len(self.systems), self.system_scroll)

    def draw_games_view(self) -> None:
        system = self.systems[self.selected_system_idx]
        games = self.visible_games(system)
        if games:
            self.selected_game_idx %= len(games)
        else:
            self.selected_game_idx = 0

        panel_x, panel_w, start_y, item_h = self._list_layout()
        title = self.font_large.render(safe_text(system.name), True, COLOR_TEXT)
        self.screen.blit(title, (panel_x, start_y))
        sub = "ESC back | type to search"
        if self.search_query:
            sub = "Search: '%s' (%d hits) - ESC clears" % (self.search_query, len(games))
        elif self.show_favorites_only:
            sub = "Favorites only (%d) - V shows all" % len(games)
        hint = self.font_small.render(sub, True, COLOR_TEXT_DIM)
        self.screen.blit(hint, (panel_x, start_y + int(52 * self.scale)))
        list_y = start_y + int(92 * self.scale)

        visible = max(1, (self.screen_height - list_y - 90) // item_h)
        if self.selected_game_idx < self.game_scroll:
            self.game_scroll = self.selected_game_idx
        elif self.selected_game_idx >= self.game_scroll + visible:
            self.game_scroll = self.selected_game_idx - visible + 1
        else:
            self.game_scroll = min(self.game_scroll, max(0, len(games) - visible))

        if not games:
            empty = self.font_medium.render(
                "No games match - add ROMs to ROMs/%s" % system.folder,
                True,
                COLOR_TEXT_DIM,
            )
            self.screen.blit(empty, (panel_x, list_y + 20))
            return

        for row, idx in enumerate(
            range(self.game_scroll, min(len(games), self.game_scroll + visible))
        ):
            game = games[idx]
            y = list_y + row * item_h
            selected = idx == self.selected_game_idx
            rect = pygame.Rect(panel_x, y, panel_w, item_h - 8)
            pygame.draw.rect(
                self.screen, COLOR_ACCENT if selected else COLOR_PANEL, rect, border_radius=10
            )
            star = "* " if self.fav_key(system, game) in self.favorites else ""
            label = safe_text(game["name"])
            max_chars = max(20, int(panel_w / (14 * self.scale)))
            if len(label) > max_chars:
                label = label[: max_chars - 3] + "..."
            name = self.font_medium.render(star + label, True, COLOR_TEXT)
            self.screen.blit(name, (panel_x + 16, y + 6))
            meta = self.font_small.render(
                "%s  -  %s" % (game["ext"].upper(), format_size(game["size"])),
                True,
                COLOR_TEXT_DIM,
            )
            self.screen.blit(meta, (panel_x + 16, y + int(36 * self.scale)))

        if len(games) > visible:
            self.draw_scrollbar(panel_x + panel_w + 8, list_y, visible, len(games), self.game_scroll)

    def draw_scrollbar(self, x: int, y: int, visible: int, total: int, offset: int) -> None:
        height = self.screen_height - y - 90
        pygame.draw.rect(self.screen, COLOR_PANEL, (x, y, 8, height), border_radius=4)
        if total <= 0:
            return
        thumb_h = max(20, int(height * visible / total))
        max_offset = max(1, total - visible)
        thumb_y = y + int((height - thumb_h) * min(1.0, offset / max_offset))
        pygame.draw.rect(
            self.screen, COLOR_ACCENT_HOVER, (x, thumb_y, 8, thumb_h), border_radius=4
        )

    def draw_help_view(self) -> None:
        panel_x, panel_w, start_y, _ = self._list_layout()
        title = self.font_large.render("Help & Controls", True, COLOR_TEXT)
        self.screen.blit(title, (panel_x, start_y))
        lines = [
            "LAUNCHER",
            "  Up/Down or D-pad ......... Navigate",
            "  Enter or A ............... Select / Launch",
            "  ESC or B ................. Back / Exit",
            "  PageUp/PageDown .......... Jump 5 items",
            "  F11 ...................... Toggle fullscreen",
            "  F1 ....................... This help screen",
            "",
            "GAME LIST",
            "  Type to search ............ Filter games live",
            "  F5 or Y .................. Toggle favorite (*)",
            "  F6 or X .................. Show favorites only",
            "  R (systems view) ......... Rescan ROM library",
            "",
            "IN GAME (RetroArch)",
            "  F1 ....................... RetroArch menu",
            "  F2 / F4 .................. Quick save / load",
            "  F8 ....................... Screenshot",
            "  Hold Space ............... Fast forward",
            "  ESC ...................... Quit to launcher",
        ]
        y = start_y + 70
        for line in lines:
            color = COLOR_ACCENT_HOVER if line.isupper() and line else COLOR_TEXT_DIM
            if line and not line.startswith(" ") and not line.isupper():
                color = COLOR_TEXT
            text = self.font_small.render(line or " ", True, color)
            self.screen.blit(text, (panel_x + 10, y))
            y += 28

    def draw_footer(self) -> None:
        footer_h = 56
        footer_y = self.screen_height - footer_h
        pygame.draw.rect(
            self.screen, COLOR_PANEL, (0, footer_y, self.screen_width, footer_h)
        )
        if self.current_view == "systems":
            controls = "Up/Down Navigate  |  Enter Select  |  R Rescan  |  F1 Help  |  ESC Exit"
        elif self.current_view == "games":
            controls = "Type to search  |  Enter Launch  |  F Favorite  |  V Fav-only  |  ESC Back"
        else:
            controls = "F1 or ESC to close help"
        text = self.font_small.render(controls, True, COLOR_TEXT_DIM)
        rect = text.get_rect(center=(self.screen_width // 2, footer_y + footer_h // 2))
        # Toast overrides footer controls while visible.
        now = pygame.time.get_ticks()
        if self.toast_message and now < self.toast_until:
            toast = self.font_small.render(self.toast_message, True, self.toast_color)
            toast_rect = toast.get_rect(
                center=(self.screen_width // 2, footer_y + footer_h // 2)
            )
            self.screen.blit(toast, toast_rect)
        else:
            self.screen.blit(text, rect)

    def run(self) -> int:
        assert pygame is not None
        self.running = True
        while self.running:
            self.handle_events()
            self.handle_held_input()
            self.draw_background()
            self.draw_header()
            if self.current_view == "systems":
                self.draw_systems_view()
            elif self.current_view == "games":
                self.draw_games_view()
            elif self.current_view == "help":
                self.draw_help_view()
            self.draw_footer()
            pygame.display.flip()
            self.clock.tick(FPS)
        pygame.quit()
        return 0


# ---------------------------------------------------------------------------
# Self test (used by CI and --self-test)
# ---------------------------------------------------------------------------


def run_self_test() -> int:
    import tempfile

    failures = 0

    def check(name: str, condition: bool, detail: str = "") -> None:
        nonlocal failures
        status = "PASS" if condition else "FAIL"
        print("[%s] %s %s" % (status, name, detail))
        if not condition:
            failures += 1

    # 1. systems.json loads and has sane entries.
    systems = load_systems()
    check("systems load", len(systems) >= 10, "(%d systems)" % len(systems))
    check(
        "N64 core fixed",
        any(s.folder == "N64" and s.core_name() == "mupen64plus_next" for s in systems),
    )

    # 2. Scanner: recursive, case-insensitive, companion filtering.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        nes = root / "NES"
        (nes / "Sub Folder").mkdir(parents=True)
        (nes / "Game One.NES").write_bytes(b"x" * 16)
        (nes / "Sub Folder" / "Game Two.nes").write_bytes(b"y" * 32)
        (nes / "notes.txt").write_bytes(b"ignore me")
        psx = root / "PlayStation"
        psx.mkdir()
        (psx / "Disc.cue").write_text("dummy")
        (psx / "Disc.bin").write_bytes(b"z" * 64)
        s_nes = next(s for s in systems if s.folder == "NES")
        count = s_nes.scan_games(root)
        check("recursive case-insensitive scan", count == 2, "(found %d)" % count)
        s_psx = next(s for s in systems if s.folder == "PlayStation")
        count_psx = s_psx.scan_games(root)
        names = [g["name"] for g in s_psx.games]
        check(
            "cue/bin companion filtering",
            count_psx == 1 and names == ["Disc"],
            "(found %r)" % (names,),
        )

    # 3. Core alias resolution.
    check(
        "core alias mupen64plus->next",
        CORE_ALIASES.get("mupen64plus") == "mupen64plus_next",
    )

    # 4. Launch target parsing.
    folder, game = parse_launch_target("NES/Zelda")
    check("launch target parse", folder == "NES" and game == "Zelda")

    # 5. safe_text strips emoji.
    check("safe_text strips emoji", safe_text("Hello \U0001F3AE World") == "Hello World")

    # 6. Health check runs without crashing.
    try:
        report = health_check(systems)
        check("health check runs", isinstance(report["total_games"], int))
    except Exception as exc:  # noqa: BLE001
        check("health check runs", False, "(%s)" % exc)

    print("Self-test: %s" % ("ALL PASS" if failures == 0 else "%d FAILURES" % failures))
    return 1 if failures else 0


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Portable Retro Gaming Launcher v%s" % VERSION
    )
    parser.add_argument("--version", action="store_true", help="Print version and exit")
    parser.add_argument("--text", action="store_true", help="Use terminal UI")
    parser.add_argument("--scan", action="store_true", help="Scan ROMs and print summary")
    parser.add_argument("--check", action="store_true", help="Run health check")
    parser.add_argument(
        "--launch", metavar="SYSTEM/GAME", help="Launch a game directly and exit"
    )
    parser.add_argument("--self-test", action="store_true", help="Run built-in self tests")
    parser.add_argument(
        "--no-auto-install",
        action="store_true",
        help="Do not attempt automatic pygame install",
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--fullscreen", action="store_true", help="Start fullscreen")
    group.add_argument("--windowed", action="store_true", help="Start windowed")
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    if sys.version_info < (3, 9):
        message = (
            "ERROR: Python 3.9 or newer is required (found %s).\n"
            "Install Python from https://www.python.org/downloads/ "
            "(check 'Add Python to PATH'),\n"
            "or run SETUP.bat, which can install Python automatically."
            % sys.version.split()[0]
        )
        log.error(message)
        print(message)
        return 2

    args = build_arg_parser().parse_args(argv)

    if args.version:
        print("Retro Gaming Launcher v%s" % VERSION)
        return 0

    if args.self_test:
        return run_self_test()

    systems = load_systems()
    ensure_rom_folders(systems)

    if args.scan:
        total, counts = scan_all_systems(systems)
        print("\nTotal: %d games" % total)
        for folder in sorted(counts):
            print("  %-14s %d" % (folder, counts[folder]))
        return 0

    if args.check:
        # NOTE: check pygame availability without installing (fast, non-intrusive).
        _try_import_pygame()
        return print_health(health_check(systems))

    if args.launch:
        scan_all_systems(systems, verbose=False)
        return launch_by_target(systems, args.launch)

    # Interactive modes.
    use_text = args.text
    if not use_text:
        if ensure_pygame(auto_install=not args.no_auto_install):
            try:
                if os.name != "nt" and not os.environ.get("DISPLAY") and not os.environ.get(
                    "WAYLAND_DISPLAY"
                ):
                    # Headless Linux/macOS: SDL would fail; go straight to text UI.
                    raise RuntimeError("no display detected")
                pygame.init()
                pygame.display.init()
                fullscreen = True if args.fullscreen else (False if args.windowed else None)
                gui = GameLauncherGUI(fullscreen=fullscreen)
                return gui.run()
            except Exception as exc:  # noqa: BLE001 - never crash, fall back
                log.warning("GUI unavailable (%s); falling back to text UI.", exc)
                print("Graphical mode unavailable (%s)." % exc)
                print("Falling back to text mode...\n")
        else:
            print("pygame unavailable (%s)." % (PYGAME_ERROR or "not installed"))
            print("Falling back to text mode...\n")

    try:
        return run_text_ui(systems)
    except KeyboardInterrupt:
        print("\nGoodbye!")
        return 0
    except Exception as exc:  # noqa: BLE001
        log.exception("Fatal error in text UI")
        print("ERROR: %s" % exc)
        print("See %s for details." % LOG_FILE)
        return 1


if __name__ == "__main__":
    sys.exit(main())
