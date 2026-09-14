#!/usr/bin/env python3
"""
Portable Retro Gaming Launcher v3.0
A full-featured portable retro gaming frontend: 50+ systems, dual-player
joysticks, categories, favorites, recents, playlists, free-games catalog,
4K UI, text-mode fallback, CLI automation, search, and health checks.

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
PLAYLISTS_JSON = CONFIG_PATH / "playlists.json"
SETTINGS_JSON = CONFIG_PATH / "launcher-settings.json"
CATALOG_JSON = CONFIG_PATH / "free-games-catalog.json"
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
            return str(json.load(f).get("version", "3.0.0"))
    except (OSError, ValueError):
        return "3.0.0"


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
    "mednafen_pce": "mednafen_pce_fast",
    "pce_fast": "mednafen_pce_fast",
    "beetle_pce_fast": "mednafen_pce_fast",
    "beetle_vb": "mednafen_vb",
    "beetle_ngp": "mednafen_ngp",
    "beetle_wswan": "mednafen_wswan",
    "beetle_saturn": "mednafen_saturn",
    "vb": "mednafen_vb",
    "ngp": "mednafen_ngp",
    "wswan": "mednafen_wswan",
    "saturn": "mednafen_saturn",
    "vice": "vice_x64",
    "x64": "vice_x64",
    "dosbox": "dosbox_pure",
    "dosbox-pure": "dosbox_pure",
    "uae": "puae",
    "fsuae": "puae",
    "chip8": "emux_chip8",
    "pico8": "retro8",
    "tic-80": "tic80",
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
        category: str = "Other",
        era: str = "",
        players: int = 1,
    ):
        self.name = name
        self.folder = folder
        self.extensions = [str(e).lower().lstrip(".") for e in extensions]
        self.emulator = emulator
        self.core = core
        self.icon = icon
        self.bios = bios or []
        self.description = description
        self.category = category or "Other"
        self.era = era or ""
        self.players = int(players) if players else 1
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
    {"name": "Nintendo Entertainment System", "folder": "NES", "extensions": ["nes", "unf", "unif", "fds", "zip", "7z"], "core": "fceumm", "emulator": "retroarch -L fceumm", "icon": "NES", "category": "Nintendo", "era": "8-bit", "players": 2, "description": "NES / Famicom (1983). Full 2-player support."},
    {"name": "Super Nintendo", "folder": "SNES", "extensions": ["smc", "sfc", "fig", "swc", "bs", "zip", "7z"], "core": "snes9x", "emulator": "retroarch -L snes9x", "icon": "SNES", "category": "Nintendo", "era": "16-bit", "players": 2, "description": "SNES / Super Famicom (1990). Multi-tap friendly."},
    {"name": "Nintendo 64", "folder": "N64", "extensions": ["n64", "z64", "v64", "zip", "7z"], "core": "mupen64plus_next", "emulator": "retroarch -L mupen64plus_next", "icon": "N64", "category": "Nintendo", "era": "64-bit", "players": 4, "description": "Nintendo 64 (1996). Up to 4 controllers."},
    {"name": "Game Boy / Game Boy Color", "folder": "GameBoy", "extensions": ["gb", "gbc", "zip", "7z"], "core": "gambatte", "emulator": "retroarch -L gambatte", "icon": "GB", "category": "Nintendo", "era": "Handheld", "players": 1, "description": "Game Boy (1989) and Game Boy Color (1998)."},
    {"name": "Game Boy Advance", "folder": "GBA", "extensions": ["gba", "agb", "mb", "zip", "7z"], "core": "mgba", "emulator": "retroarch -L mgba", "icon": "GBA", "bios": ["gba_bios.bin"], "category": "Nintendo", "era": "Handheld", "players": 1, "description": "Game Boy Advance (2001)."},
    {"name": "Nintendo DS", "folder": "NDS", "extensions": ["nds", "dsi", "zip", "7z"], "core": "desmume", "emulator": "retroarch -L desmume", "icon": "NDS", "bios": ["bios7.bin", "bios9.bin", "firmware.bin"], "category": "Nintendo", "era": "Handheld", "players": 1, "description": "Nintendo DS (2004). Touch via mouse/pointer."},
    {"name": "Virtual Boy", "folder": "VirtualBoy", "extensions": ["vb", "vboy", "zip", "7z"], "core": "mednafen_vb", "emulator": "retroarch -L mednafen_vb", "icon": "VB", "category": "Nintendo", "era": "32-bit", "players": 1, "description": "Virtual Boy (1995). Red/black 3D display."},
    {"name": "Pokemon Mini", "folder": "PokemonMini", "extensions": ["min", "zip", "7z"], "core": "pokemini", "emulator": "retroarch -L pokemini", "icon": "PM", "category": "Nintendo", "era": "Handheld", "players": 1, "description": "Pokemon Mini (2001)."},
    {"name": "Game & Watch", "folder": "GameAndWatch", "extensions": ["mgw", "zip", "7z"], "core": "gw", "emulator": "retroarch -L gw", "icon": "GW", "category": "Nintendo", "era": "Handheld", "players": 1, "description": "Nintendo Game & Watch handhelds."},
    {"name": "Sega Genesis / Mega Drive", "folder": "Genesis", "extensions": ["md", "gen", "smd", "bin", "zip", "7z"], "core": "genesis_plus_gx", "emulator": "retroarch -L genesis_plus_gx", "icon": "GEN", "category": "Sega", "era": "16-bit", "players": 2, "description": "Genesis / Mega Drive (1988). Full 2-player."},
    {"name": "Sega Master System", "folder": "MasterSystem", "extensions": ["sms", "zip", "7z"], "core": "genesis_plus_gx", "emulator": "retroarch -L genesis_plus_gx", "icon": "SMS", "category": "Sega", "era": "8-bit", "players": 2, "description": "Master System (1985)."},
    {"name": "Sega Game Gear", "folder": "GameGear", "extensions": ["gg", "zip", "7z"], "core": "genesis_plus_gx", "emulator": "retroarch -L genesis_plus_gx", "icon": "GG", "category": "Sega", "era": "Handheld", "players": 1, "description": "Game Gear (1990)."},
    {"name": "Sega SG-1000", "folder": "SG1000", "extensions": ["sg", "zip", "7z"], "core": "genesis_plus_gx", "emulator": "retroarch -L genesis_plus_gx", "icon": "SG1", "category": "Sega", "era": "8-bit", "players": 2, "description": "SG-1000 (1983)."},
    {"name": "Sega 32X", "folder": "Sega32X", "extensions": ["32x", "zip", "7z"], "core": "picodrive", "emulator": "retroarch -L picodrive", "icon": "32X", "category": "Sega", "era": "32-bit", "players": 2, "description": "Genesis 32X add-on (1994)."},
    {"name": "Sega CD / Mega-CD", "folder": "SegaCD", "extensions": ["cue", "chd", "iso", "m3u", "bin"], "core": "genesis_plus_gx", "emulator": "retroarch -L genesis_plus_gx", "icon": "SCD", "bios": ["bios_CD_U.bin", "bios_CD_E.bin", "bios_CD_J.bin"], "category": "Sega", "era": "16-bit", "players": 2, "description": "Sega CD / Mega-CD (1991). Requires region BIOS."},
    {"name": "Sega Saturn", "folder": "Saturn", "extensions": ["cue", "chd", "iso", "m3u", "bin"], "core": "mednafen_saturn", "emulator": "retroarch -L mednafen_saturn", "icon": "SAT", "bios": ["sega_101.bin", "mpr-17933.bin"], "category": "Sega", "era": "32-bit", "players": 2, "description": "Sega Saturn (1994)."},
    {"name": "Sega Dreamcast", "folder": "Dreamcast", "extensions": ["cdi", "gdi", "chd", "m3u"], "core": "flycast", "emulator": "retroarch -L flycast", "icon": "DC", "bios": ["dc_boot.bin", "dc_flash.bin"], "category": "Sega", "era": "128-bit", "players": 4, "description": "Dreamcast (1998). Up to 4 controllers."},
    {"name": "PlayStation", "folder": "PlayStation", "extensions": ["cue", "m3u", "chd", "pbp", "iso", "bin"], "core": "pcsx_rearmed", "emulator": "retroarch -L pcsx_rearmed", "icon": "PS1", "bios": ["scph1001.bin"], "category": "Sony", "era": "32-bit", "players": 2, "description": "PlayStation 1 (1994). DualShock analog supported."},
    {"name": "PlayStation Portable", "folder": "PSP", "extensions": ["iso", "cso", "pbp", "chd"], "core": "ppsspp", "emulator": "retroarch -L ppsspp", "icon": "PSP", "category": "Sony", "era": "Handheld", "players": 1, "description": "PSP (2004)."},
    {"name": "PC Engine / TurboGrafx-16", "folder": "PCEngine", "extensions": ["pce", "sgx", "cue", "chd", "zip", "7z"], "core": "mednafen_pce_fast", "emulator": "retroarch -L mednafen_pce_fast", "icon": "PCE", "category": "NEC", "era": "16-bit", "players": 5, "description": "PC Engine / TurboGrafx-16 (1987). Multi-tap up to 5."},
    {"name": "PC Engine CD / TurboGrafx-CD", "folder": "PCEngineCD", "extensions": ["cue", "chd", "iso", "m3u"], "core": "mednafen_pce_fast", "emulator": "retroarch -L mednafen_pce_fast", "icon": "PCCD", "bios": ["syscard3.pce"], "category": "NEC", "era": "16-bit", "players": 5, "description": "PC Engine CD-ROM\u00b2 / TurboGrafx-CD."},
    {"name": "Neo Geo AES/MVS", "folder": "NeoGeo", "extensions": ["zip", "7z"], "core": "fbneo", "emulator": "retroarch -L fbneo", "icon": "NEO", "bios": ["neogeo.zip"], "category": "SNK", "era": "Arcade", "players": 2, "description": "Neo Geo AES/MVS. Requires neogeo.zip BIOS set."},
    {"name": "Neo Geo CD", "folder": "NeoGeoCD", "extensions": ["cue", "chd", "iso", "m3u"], "core": "neocd", "emulator": "retroarch -L neocd", "icon": "NCD", "bios": ["neocd.bin", "000-lo.lo"], "category": "SNK", "era": "32-bit", "players": 2, "description": "Neo Geo CD (1994)."},
    {"name": "Neo Geo Pocket / Color", "folder": "NeoGeoPocket", "extensions": ["ngp", "ngc", "npc", "zip", "7z"], "core": "mednafen_ngp", "emulator": "retroarch -L mednafen_ngp", "icon": "NGP", "category": "SNK", "era": "Handheld", "players": 1, "description": "Neo Geo Pocket / Color (1998)."},
    {"name": "Arcade (MAME 2003-Plus)", "folder": "Arcade", "extensions": ["zip", "7z"], "core": "mame2003_plus", "emulator": "retroarch -L mame2003_plus", "icon": "ARC", "category": "Arcade", "era": "Arcade", "players": 4, "description": "Classic arcade (MAME 0.78 romset compatible)."},
    {"name": "Arcade (FinalBurn Neo)", "folder": "FBNeo", "extensions": ["zip", "7z"], "core": "fbneo", "emulator": "retroarch -L fbneo", "icon": "FBN", "category": "Arcade", "era": "Arcade", "players": 4, "description": "FinalBurn Neo arcade sets (CPS1/2/3, Neo Geo, etc.)."},
    {"name": "Atari 2600", "folder": "Atari2600", "extensions": ["a26", "bin", "zip", "7z"], "core": "stella", "emulator": "retroarch -L stella", "icon": "A26", "category": "Atari", "era": "8-bit", "players": 2, "description": "Atari 2600 / VCS (1977). Full 2-player joysticks."},
    {"name": "Atari 5200", "folder": "Atari5200", "extensions": ["a52", "bin", "zip", "7z"], "core": "a5200", "emulator": "retroarch -L a5200", "icon": "A52", "bios": ["5200.rom"], "category": "Atari", "era": "8-bit", "players": 4, "description": "Atari 5200 SuperSystem (1982)."},
    {"name": "Atari 7800", "folder": "Atari7800", "extensions": ["a78", "bin", "zip", "7z"], "core": "prosystem", "emulator": "retroarch -L prosystem", "icon": "A78", "bios": ["7800 BIOS (U).rom"], "category": "Atari", "era": "8-bit", "players": 2, "description": "Atari 7800 ProSystem (1986)."},
    {"name": "Atari Lynx", "folder": "AtariLynx", "extensions": ["lnx", "lyx", "zip", "7z"], "core": "handy", "emulator": "retroarch -L handy", "icon": "LYNX", "bios": ["lynxboot.img"], "category": "Atari", "era": "Handheld", "players": 1, "description": "Atari Lynx (1989)."},
    {"name": "Atari Jaguar", "folder": "AtariJaguar", "extensions": ["j64", "jag", "rom", "abs", "cof", "zip", "7z"], "core": "virtualjaguar", "emulator": "retroarch -L virtualjaguar", "icon": "JAG", "category": "Atari", "era": "64-bit", "players": 2, "description": "Atari Jaguar (1993)."},
    {"name": "ColecoVision", "folder": "ColecoVision", "extensions": ["col", "cv", "bin", "rom", "zip", "7z"], "core": "gearcoleco", "emulator": "retroarch -L gearcoleco", "icon": "COL", "bios": ["coleco.rom"], "category": "Classic", "era": "8-bit", "players": 2, "description": "ColecoVision (1982)."},
    {"name": "Intellivision", "folder": "Intellivision", "extensions": ["int", "bin", "rom", "zip", "7z"], "core": "freeintv", "emulator": "retroarch -L freeintv", "icon": "INTV", "bios": ["exec.bin", "grom.bin"], "category": "Classic", "era": "8-bit", "players": 2, "description": "Mattel Intellivision (1979)."},
    {"name": "Magnavox Odyssey 2", "folder": "Odyssey2", "extensions": ["bin", "rom", "zip", "7z"], "core": "o2em", "emulator": "retroarch -L o2em", "icon": "O2", "bios": ["o2rom.bin"], "category": "Classic", "era": "8-bit", "players": 2, "description": "Magnavox Odyssey\u00b2 / Videopac (1978)."},
    {"name": "Vectrex", "folder": "Vectrex", "extensions": ["vec", "bin", "gam", "zip", "7z"], "core": "vecx", "emulator": "retroarch -L vecx", "icon": "VEC", "category": "Classic", "era": "8-bit", "players": 2, "description": "GCE Vectrex vector console (1982)."},
    {"name": "WonderSwan / Color", "folder": "WonderSwan", "extensions": ["ws", "wsc", "pc2", "zip", "7z"], "core": "mednafen_wswan", "emulator": "retroarch -L mednafen_wswan", "icon": "WS", "category": "Bandai", "era": "Handheld", "players": 1, "description": "Bandai WonderSwan / Color (1999)."},
    {"name": "Watara Supervision", "folder": "Supervision", "extensions": ["sv", "bin", "zip", "7z"], "core": "potator", "emulator": "retroarch -L potator", "icon": "SV", "category": "Classic", "era": "Handheld", "players": 1, "description": "Watara Supervision (1992)."},
    {"name": "Fairchild Channel F", "folder": "ChannelF", "extensions": ["bin", "chf", "zip", "7z"], "core": "freechaf", "emulator": "retroarch -L freechaf", "icon": "CHF", "category": "Classic", "era": "8-bit", "players": 2, "description": "Fairchild Channel F (1976)."},
    {"name": "MSX / MSX2", "folder": "MSX", "extensions": ["rom", "mx1", "mx2", "dsk", "cas", "zip", "7z"], "core": "bluemsx", "emulator": "retroarch -L bluemsx", "icon": "MSX", "category": "Computer", "era": "8-bit", "players": 2, "description": "MSX / MSX2 home computers."},
    {"name": "ZX Spectrum", "folder": "ZXSpectrum", "extensions": ["tzx", "tap", "z80", "rzx", "scl", "trd", "zip", "7z"], "core": "fuse", "emulator": "retroarch -L fuse", "icon": "ZX", "category": "Computer", "era": "8-bit", "players": 1, "description": "Sinclair ZX Spectrum (1982)."},
    {"name": "Commodore 64", "folder": "C64", "extensions": ["d64", "t64", "prg", "crt", "tap", "g64", "zip", "7z"], "core": "vice_x64", "emulator": "retroarch -L vice_x64", "icon": "C64", "category": "Computer", "era": "8-bit", "players": 2, "description": "Commodore 64 (1982). Joystick ports 1 & 2."},
    {"name": "Commodore Amiga", "folder": "Amiga", "extensions": ["adf", "adz", "ipf", "hdf", "lha", "zip", "7z"], "core": "puae", "emulator": "retroarch -L puae", "icon": "AMI", "bios": ["kick34005.A500", "kick40068.A1200"], "category": "Computer", "era": "16-bit", "players": 2, "description": "Commodore Amiga. Kickstart ROM recommended."},
    {"name": "DOS / PC", "folder": "DOS", "extensions": ["exe", "com", "bat", "iso", "cue", "chd", "zip", "7z", "dosz"], "core": "dosbox_pure", "emulator": "retroarch -L dosbox_pure", "icon": "DOS", "category": "Computer", "era": "PC", "players": 2, "description": "MS-DOS / early PC games (DOSBox Pure)."},
    {"name": "ScummVM (Adventure)", "folder": "ScummVM", "extensions": ["scummvm", "svm"], "core": "scummvm", "emulator": "retroarch -L scummvm", "icon": "SCU", "category": "Computer", "era": "PC", "players": 1, "description": "Classic point-and-click adventures via ScummVM."},
    {"name": "Amstrad CPC", "folder": "AmstradCPC", "extensions": ["dsk", "sna", "cdt", "voc", "zip", "7z"], "core": "cap32", "emulator": "retroarch -L cap32", "icon": "CPC", "category": "Computer", "era": "8-bit", "players": 2, "description": "Amstrad CPC (1984)."},
    {"name": "Atari ST", "folder": "AtariST", "extensions": ["st", "msa", "stx", "dim", "ipf", "zip", "7z"], "core": "hatari", "emulator": "retroarch -L hatari", "icon": "AST", "bios": ["tos.img"], "category": "Computer", "era": "16-bit", "players": 1, "description": "Atari ST (1985)."},
    {"name": "3DO Interactive Multiplayer", "folder": "3DO", "extensions": ["iso", "cue", "chd", "bin"], "core": "opera", "emulator": "retroarch -L opera", "icon": "3DO", "bios": ["panafz1.bin"], "category": "Classic", "era": "32-bit", "players": 2, "description": "3DO (1993)."},
    {"name": "Arcadia 2001", "folder": "Arcadia2001", "extensions": ["bin", "zip", "7z"], "core": "mame2003_plus", "emulator": "retroarch -L mame2003_plus", "icon": "A2K", "category": "Classic", "era": "8-bit", "players": 2, "description": "Emerson Arcadia 2001 (1982)."},
    {"name": "TIC-80 Fantasy Console", "folder": "TIC80", "extensions": ["tic"], "core": "tic80", "emulator": "retroarch -L tic80", "icon": "TIC", "category": "Fantasy", "era": "Modern", "players": 4, "description": "TIC-80 fantasy console. Huge free cart library."},
    {"name": "PICO-8 Fantasy Console", "folder": "PICO8", "extensions": ["p8", "png"], "core": "retro8", "emulator": "retroarch -L retro8", "icon": "P8", "category": "Fantasy", "era": "Modern", "players": 2, "description": "PICO-8 style carts via Retro8 (open carts)."},
    {"name": "WASM-4 Fantasy Console", "folder": "WASM4", "extensions": ["wasm"], "core": "wasm4", "emulator": "retroarch -L wasm4", "icon": "W4", "category": "Fantasy", "era": "Modern", "players": 4, "description": "WASM-4 fantasy console (open source carts)."},
    {"name": "LowRes NX", "folder": "LowResNX", "extensions": ["nx"], "core": "lowresnx", "emulator": "retroarch -L lowresnx", "icon": "LRNX", "category": "Fantasy", "era": "Modern", "players": 2, "description": "LowRes NX fantasy console."},
    {"name": "Chip-8 / SuperChip", "folder": "CHIP8", "extensions": ["ch8", "c8", "sc8", "zip", "7z"], "core": "emux_chip8", "emulator": "retroarch -L emux_chip8", "icon": "C8", "category": "Fantasy", "era": "Classic", "players": 1, "description": "CHIP-8 interpreter demos and games."},
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
                    category=str(entry.get("category", "Other")),
                    era=str(entry.get("era", "")),
                    players=int(entry.get("players", 1) or 1),
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


def load_json_dict(path: Path) -> Dict:
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_json_dict(path: Path, data: Dict) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
    except OSError as exc:
        log.warning("Could not save %s: %s", path, exc)


def load_settings() -> Dict:
    defaults = {
        "show_empty_systems": True,
        "default_view": "systems",
        "confirm_launch": False,
        "theme": "dark",
        "sort_systems": "name",  # name | category | games
        "netplay_nick": "Player1",
    }
    data = load_json_dict(SETTINGS_JSON)
    defaults.update({k: v for k, v in data.items() if v is not None})
    return defaults


def catalog_stats() -> Dict:
    """Summarize the free-games catalog (for UI + health)."""
    try:
        with open(CATALOG_JSON, "r", encoding="utf-8") as f:
            cat = json.load(f)
        systems = cat.get("systems", {}) if isinstance(cat, dict) else {}
        entries = 0
        for node in systems.values():
            entries += len(node.get("entries", []) or [])
        return {
            "systems": len(systems),
            "entries": entries,
            "version": cat.get("version", "?") if isinstance(cat, dict) else "?",
        }
    except (OSError, ValueError):
        return {"systems": 0, "entries": 0, "version": "missing"}




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
    cat = catalog_stats()
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
        "system_count": len(systems),
        "systems_with_games": sum(1 for c in counts.values() if c),
        "catalog_systems": cat["systems"],
        "catalog_entries": cat["entries"],
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
    print("Systems:           %d (%d with games)" % (
        report.get("system_count", 0), report.get("systems_with_games", 0)))
    print("Cores installed:   %d" % report["core_count"])
    print("Games found:       %d" % report["total_games"])
    print("Free-game catalog: %d systems / %d curated entries" % (
        report.get("catalog_systems", 0), report.get("catalog_entries", 0)))
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
                mp = " %dP" % system.players if system.players > 1 else ""
                print(
                    "  %2d. %-32s (%d games)%s%s"
                    % (idx + 1, system.name, len(system.games), mp, marker)
                )
            print("   R. Rescan    H. Health    M. Multiplayer only    A. All")
            print("   G. Catalog stats    Q. Quit")
            choice = input("Select system: ").strip().lower()
            if choice in ("q", "quit", "exit"):
                return 0
            if choice == "r":
                scan_all_systems(systems)
                continue
            if choice in ("h", "c"):
                print_health(health_check(systems))
                continue
            if choice == "m":
                systems = [s for s in load_systems() if s.players >= 2]
                scan_all_systems(systems, verbose=False)
                print("Showing %d multiplayer systems." % len(systems))
                continue
            if choice == "a":
                systems = load_systems()
                scan_all_systems(systems, verbose=False)
                continue
            if choice == "g":
                cat = catalog_stats()
                print("Free-games catalog v%s: %d systems, %d curated entries" % (
                    cat["version"], cat["systems"], cat["entries"]))
                print("Edit Configs/free-games-catalog.json to expand forever.")
                print("Run Tools/download-roms to fetch legal homebrew.")
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

        self.settings = load_settings()

        # UI state
        self.current_view = "systems"  # systems | games | help | recents | categories
        self.view_before_help = "systems"
        self.selected_system_idx = 0
        self.selected_game_idx = 0
        self.system_scroll = 0
        self.game_scroll = 0
        self.search_query = ""
        self.system_filter = ""  # type-to-filter on systems list
        self.show_favorites_only = False
        self.show_empty_systems = bool(self.settings.get("show_empty_systems", True))
        self.category_filter = "All"  # All | Nintendo | Sega | ...
        self.selected_category_idx = 0
        self.selected_recent_idx = 0
        self.recent_scroll = 0
        self.toast_message = ""
        self.toast_until = 0
        self.toast_color = COLOR_WARNING
        self.running = False
        self.two_player_hint_shown = False

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
        # Drop stale references then re-init every connected pad (hotplug safe).
        for old in list(getattr(self, "controllers", []) or []):
            try:
                old.quit()
            except (pygame.error, AttributeError):
                pass
        self.controllers = []
        count = pygame.joystick.get_count()
        for i in range(count):
            try:
                controller = pygame.joystick.Joystick(i)
                controller.init()
                self.controllers.append(controller)
                naxes = controller.get_numaxes() if hasattr(controller, "get_numaxes") else 0
                nbtns = controller.get_numbuttons() if hasattr(controller, "get_numbuttons") else 0
                log.info(
                    "Controller P%d: %s (%d axes, %d buttons)",
                    i + 1, controller.get_name(), naxes, nbtns,
                )
            except pygame.error as exc:
                log.warning("Could not init joystick %d: %s", i, exc)
        if len(self.controllers) >= 2:
            log.info("Dual-player ready: %d controllers connected.", len(self.controllers))

    def refresh_controllers(self) -> None:
        before = len(self.controllers)
        self.setup_controllers()
        after = len(self.controllers)
        if after != before:
            if after >= 2:
                self.show_toast(
                    "2-player ready: %d controllers connected" % after,
                    COLOR_SUCCESS, 3500,
                )
            elif after == 1:
                self.show_toast("1 controller connected (plug in a 2nd for 2P)", COLOR_WARNING, 3500)
            else:
                self.show_toast("All controllers disconnected - keyboard mode", COLOR_TEXT_DIM, 2500)

    def controller_summary(self) -> str:
        n = len(self.controllers)
        if n >= 2:
            names = []
            for i, c in enumerate(self.controllers[:4]):
                try:
                    names.append("P%d:%s" % (i + 1, (c.get_name() or "Pad")[:18]))
                except pygame.error:
                    names.append("P%d" % (i + 1))
            return "2P OK | " + " + ".join(names)
        if n == 1:
            try:
                name = self.controllers[0].get_name()
            except pygame.error:
                name = "Pad"
            return "1 controller (%s) - plug 2nd for 2P" % name[:22]
        return "Keyboard mode (P1 WASD/Arrows, P2 IJKL)"

    # -- toast notifications ------------------------------------------
    def show_toast(
        self, message: str, color=COLOR_WARNING, duration_ms: int = 4000
    ) -> None:
        self.toast_message = safe_text(message)
        self.toast_color = color
        self.toast_until = pygame.time.get_ticks() + duration_ms
        log.warning("TOAST: %s", message)

    # -- filtering ----------------------------------------------------
    def all_categories(self) -> List[str]:
        cats = sorted({s.category for s in self.systems if s.category})
        return ["All", "Multiplayer", "Favorites", "Recents"] + cats

    def visible_systems(self) -> List[GameSystem]:
        systems = list(self.systems)
        if self.category_filter and self.category_filter not in ("All", "Favorites", "Recents", "Multiplayer"):
            systems = [s for s in systems if s.category == self.category_filter]
        elif self.category_filter == "Multiplayer":
            systems = [s for s in systems if s.players >= 2]
        if not self.show_empty_systems:
            systems = [s for s in systems if s.games]
        if self.system_filter:
            q = self.system_filter.lower()
            systems = [
                s for s in systems
                if q in s.name.lower() or q in s.folder.lower() or q in (s.category or "").lower()
            ]
        sort_mode = self.settings.get("sort_systems", "name")
        if sort_mode == "games":
            systems.sort(key=lambda s: (-len(s.games), s.name.lower()))
        elif sort_mode == "category":
            systems.sort(key=lambda s: (s.category.lower(), s.name.lower()))
        else:
            systems.sort(key=lambda s: s.name.lower())
        return systems

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

    def recent_entries(self) -> List[Tuple[GameSystem, Dict]]:
        """Resolve recent keys to live (system, game) pairs."""
        folder_map = {s.folder.lower(): s for s in self.systems}
        out: List[Tuple[GameSystem, Dict]] = []
        for key in self.recent:
            if "/" not in key:
                continue
            folder, name = key.split("/", 1)
            system = folder_map.get(folder.lower())
            if not system:
                continue
            if not system.games:
                system.scan_games(ROMS_PATH)
            for game in system.games:
                if game["name"] == name:
                    out.append((system, game))
                    break
        return out

    def fav_key(self, system: GameSystem, game: Dict) -> str:
        return "%s/%s" % (system.folder, game["name"])

    # -- navigation ---------------------------------------------------
    def _systems_list(self) -> List[GameSystem]:
        systems = self.visible_systems()
        return systems if systems else list(self.systems)

    def navigate_up(self) -> None:
        if self.current_view == "systems":
            systems = self._systems_list()
            if systems:
                self.selected_system_idx = (self.selected_system_idx - 1) % len(systems)
        elif self.current_view == "games":
            systems = self._systems_list()
            if not systems:
                return
            idx = min(self.selected_system_idx, len(systems) - 1)
            games = self.visible_games(systems[idx])
            if games:
                self.selected_game_idx = (self.selected_game_idx - 1) % len(games)
        elif self.current_view == "recents":
            entries = self.recent_entries()
            if entries:
                self.selected_recent_idx = (self.selected_recent_idx - 1) % len(entries)
        elif self.current_view == "categories":
            cats = self.all_categories()
            self.selected_category_idx = (self.selected_category_idx - 1) % len(cats)

    def navigate_down(self) -> None:
        if self.current_view == "systems":
            systems = self._systems_list()
            if systems:
                self.selected_system_idx = (self.selected_system_idx + 1) % len(systems)
        elif self.current_view == "games":
            systems = self._systems_list()
            if not systems:
                return
            idx = min(self.selected_system_idx, len(systems) - 1)
            games = self.visible_games(systems[idx])
            if games:
                self.selected_game_idx = (self.selected_game_idx + 1) % len(games)
        elif self.current_view == "recents":
            entries = self.recent_entries()
            if entries:
                self.selected_recent_idx = (self.selected_recent_idx + 1) % len(entries)
        elif self.current_view == "categories":
            cats = self.all_categories()
            self.selected_category_idx = (self.selected_category_idx + 1) % len(cats)

    def page_move(self, direction: int) -> None:
        if self.current_view == "systems":
            systems = self._systems_list()
            if systems:
                self.selected_system_idx = (self.selected_system_idx + direction * 5) % len(systems)
        elif self.current_view == "games":
            systems = self._systems_list()
            if not systems:
                return
            idx = min(self.selected_system_idx, len(systems) - 1)
            games = self.visible_games(systems[idx])
            if games:
                self.selected_game_idx = (self.selected_game_idx + direction * 5) % len(games)
        elif self.current_view == "recents":
            entries = self.recent_entries()
            if entries:
                self.selected_recent_idx = (self.selected_recent_idx + direction * 5) % len(entries)

    def select_item(self) -> None:
        if self.current_view == "systems":
            systems = self._systems_list()
            if not systems:
                self.show_toast("No systems match the current filter")
                return
            self.selected_system_idx %= len(systems)
            system = systems[self.selected_system_idx]
            # Keep absolute index into self.systems for launch path consistency
            try:
                self._active_system_folder = system.folder
            except Exception:
                pass
            if system.games:
                self.current_view = "games"
                self.selected_game_idx = 0
                self.game_scroll = 0
                self.search_query = ""
                if system.players >= 2 and len(self.controllers) < 2 and not self.two_player_hint_shown:
                    self.show_toast(
                        "%s supports %d players - connect pads or use P2 keys (IJKL)" % (
                            system.short_name, system.players),
                        COLOR_ACCENT_HOVER, 4500,
                    )
                    self.two_player_hint_shown = True
            else:
                self.show_toast(
                    "No games for %s - add ROMs to ROMs/%s or run download-roms"
                    % (system.name, system.folder)
                )
        elif self.current_view == "games":
            self.launch_selected_game()
        elif self.current_view == "recents":
            entries = self.recent_entries()
            if not entries:
                self.show_toast("No recent games yet")
                return
            self.selected_recent_idx %= len(entries)
            system, game = entries[self.selected_recent_idx]
            self._launch_pair(system, game)
        elif self.current_view == "categories":
            cats = self.all_categories()
            self.selected_category_idx %= len(cats)
            choice = cats[self.selected_category_idx]
            if choice == "Recents":
                self.current_view = "recents"
                self.selected_recent_idx = 0
            elif choice == "Favorites":
                self.category_filter = "All"
                self.show_favorites_only = True
                # Jump to first system that has favorites
                self.current_view = "systems"
                self.selected_system_idx = 0
                self.show_toast("Open a system, then press V for favorites-only", COLOR_SUCCESS, 3000)
            else:
                self.category_filter = choice
                self.current_view = "systems"
                self.selected_system_idx = 0
                self.system_scroll = 0
                self.show_toast("Category: %s" % choice, COLOR_SUCCESS, 2000)

    def go_back(self) -> None:
        if self.current_view == "games":
            self.current_view = "systems"
            self.search_query = ""
            self.show_favorites_only = False
        elif self.current_view == "help":
            self.current_view = getattr(self, "view_before_help", "systems")
        elif self.current_view in ("recents", "categories"):
            self.current_view = "systems"
        elif self.current_view == "systems":
            if self.category_filter != "All" or self.system_filter:
                self.category_filter = "All"
                self.system_filter = ""
                self.show_toast("Filters cleared", COLOR_TEXT_DIM, 1500)
            else:
                self.running = False

    def current_system(self) -> Optional[GameSystem]:
        systems = self._systems_list()
        if not systems:
            return None
        # Prefer folder sticky selection when filters change under us.
        folder = getattr(self, "_active_system_folder", None)
        if folder:
            for s in systems:
                if s.folder == folder:
                    return s
        idx = self.selected_system_idx % len(systems)
        return systems[idx]

    def toggle_help(self) -> None:
        if self.current_view == "help":
            self.current_view = self.view_before_help
        else:
            self.view_before_help = self.current_view
            self.current_view = "help"

    def toggle_favorite(self) -> None:
        if self.current_view != "games":
            return
        system = self.current_system()
        if system is None:
            return
        games = self.visible_games(system)
        if not games:
            return
        key = self.fav_key(system, games[self.selected_game_idx % len(games)])
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
        self.show_toast(
            "Library rescanned: %d games across %d systems" % (total, len(self.systems)),
            COLOR_SUCCESS, 2500,
        )
        self.refresh_controllers()

    def cycle_category(self, direction: int = 1) -> None:
        cats = [c for c in self.all_categories() if c not in ("Favorites", "Recents")]
        if not cats:
            return
        try:
            idx = cats.index(self.category_filter)
        except ValueError:
            idx = 0
        self.category_filter = cats[(idx + direction) % len(cats)]
        self.selected_system_idx = 0
        self.system_scroll = 0
        self.show_toast("Category: %s" % self.category_filter, COLOR_SUCCESS, 1800)

    def toggle_empty_systems(self) -> None:
        self.show_empty_systems = not self.show_empty_systems
        self.settings["show_empty_systems"] = self.show_empty_systems
        save_json_dict(SETTINGS_JSON, self.settings)
        self.selected_system_idx = 0
        self.show_toast(
            "Empty systems: %s" % ("shown" if self.show_empty_systems else "hidden"),
            COLOR_TEXT_DIM, 2000,
        )

    # -- launching ----------------------------------------------------
    def _launch_pair(self, system: GameSystem, game: Dict) -> None:
        assert pygame is not None
        try:
            cmd = build_launch_command(system, game["path"])
        except (FileNotFoundError, RuntimeError) as exc:
            self.show_toast(str(exc), COLOR_ERROR, duration_ms=7000)
            return
        log.info("Launching: %s (%s) players=%s pads=%d",
                 game["name"], system.folder, system.players, len(self.controllers))
        # Multi-controller tip right before launch.
        if system.players >= 2 and len(self.controllers) >= 2:
            self.show_toast("Launching 2P: %s" % game["name"], COLOR_SUCCESS, 1500)
        try:
            pygame.display.iconify()
            # Give pads a moment; RetroArch will pick them up via joypad indexes 0..N
            subprocess.run(cmd, cwd=str(RETROARCH_PATH))
        except OSError as exc:
            self.show_toast("Failed to launch: %s" % exc, COLOR_ERROR, 7000)
        finally:
            self.restore_display()
            self.refresh_controllers()
            key = self.fav_key(system, game)
            if key in self.recent:
                self.recent.remove(key)
            self.recent.insert(0, key)
            self.recent = self.recent[:50]
            save_json_list(RECENT_JSON, self.recent)

    def launch_selected_game(self) -> None:
        system = self.current_system()
        if system is None:
            return
        games = self.visible_games(system)
        if not games:
            return
        game = games[self.selected_game_idx % len(games)]
        self._launch_pair(system, game)

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
        mods = pygame.key.get_mods()
        if event.key == pygame.K_F11:
            self.toggle_fullscreen()
        elif event.key == pygame.K_F1 or (
            event.key == pygame.K_h and mods & pygame.KMOD_CTRL
        ):
            self.toggle_help()
        elif event.key == pygame.K_F2:
            self.current_view = "recents"
            self.selected_recent_idx = 0
        elif event.key == pygame.K_F3:
            self.current_view = "categories"
            self.selected_category_idx = 0
        elif event.key == pygame.K_F5 and self.current_view == "games":
            self.toggle_favorite()
        elif event.key == pygame.K_F6 and self.current_view == "games":
            self.show_favorites_only = not self.show_favorites_only
            self.selected_game_idx = 0
            self.game_scroll = 0
        elif event.key == pygame.K_F7:
            self.toggle_empty_systems()
        elif event.key == pygame.K_TAB and self.current_view == "systems":
            direction = -1 if mods & pygame.KMOD_SHIFT else 1
            self.cycle_category(direction)
        elif event.key == pygame.K_ESCAPE:
            if self.search_query:
                self.search_query = ""
            elif self.system_filter:
                self.system_filter = ""
            else:
                self.go_back()
        elif event.key == pygame.K_RETURN or event.key == pygame.K_KP_ENTER:
            self.select_item()
        elif event.key == pygame.K_UP:
            self.navigate_up()
        elif event.key == pygame.K_DOWN:
            self.navigate_down()
        elif event.key == pygame.K_LEFT and self.current_view == "systems":
            self.cycle_category(-1)
        elif event.key == pygame.K_RIGHT and self.current_view == "systems":
            self.cycle_category(1)
        elif event.key == pygame.K_PAGEUP:
            self.page_move(-1)
        elif event.key == pygame.K_PAGEDOWN:
            self.page_move(1)
        elif event.key == pygame.K_HOME:
            self.selected_game_idx = 0
            self.selected_system_idx = 0
            self.selected_recent_idx = 0
        elif event.key == pygame.K_END:
            if self.current_view == "games":
                system = self.current_system()
                if system:
                    games = self.visible_games(system)
                    self.selected_game_idx = max(0, len(games) - 1)
            elif self.current_view == "recents":
                self.selected_recent_idx = max(0, len(self.recent_entries()) - 1)
            else:
                systems = self._systems_list()
                self.selected_system_idx = max(0, len(systems) - 1)
        elif event.key == pygame.K_r and self.current_view == "systems" and not (mods & pygame.KMOD_CTRL):
            self.rescan()
        elif event.key == pygame.K_f and self.current_view == "games":
            self.toggle_favorite()
        elif event.key == pygame.K_v and self.current_view == "games":
            self.show_favorites_only = not self.show_favorites_only
            self.selected_game_idx = 0
        elif event.key == pygame.K_c and self.current_view == "systems":
            self.current_view = "categories"
            self.selected_category_idx = 0
        elif event.key == pygame.K_e and self.current_view == "systems":
            self.toggle_empty_systems()
        elif event.key == pygame.K_BACKSPACE:
            if self.current_view == "games" and self.search_query:
                self.search_query = self.search_query[:-1]
                self.selected_game_idx = 0
            elif self.current_view == "systems" and self.system_filter:
                self.system_filter = self.system_filter[:-1]
                self.selected_system_idx = 0
            else:
                self.go_back()
        elif event.unicode and event.unicode.isprintable() and not (mods & pygame.KMOD_CTRL):
            if self.current_view == "games":
                self.search_query += event.unicode
                self.selected_game_idx = 0
            elif self.current_view == "systems":
                self.system_filter += event.unicode
                self.selected_system_idx = 0

    def handle_joybutton(self, button: int) -> None:
        # Xbox layout (any connected pad can drive the launcher):
        # 0=A select, 1=B back, 2=X fav-filter / categories, 3=Y favorite,
        # 4=LB prev category, 5=RB next category,
        # 6=Back/Select recents, 7=Start rescan, 9=Start alt.
        if button == 0:
            self.select_item()
        elif button == 1:
            self.go_back()
        elif button == 2:
            if self.current_view == "games":
                self.show_favorites_only = not self.show_favorites_only
                self.selected_game_idx = 0
                self.game_scroll = 0
            else:
                self.current_view = "categories"
                self.selected_category_idx = 0
        elif button == 3:
            if self.current_view == "games":
                self.toggle_favorite()
            else:
                self.current_view = "recents"
                self.selected_recent_idx = 0
        elif button == 4:
            self.cycle_category(-1)
        elif button == 5:
            self.cycle_category(1)
        elif button in (6, 8):
            self.current_view = "recents"
            self.selected_recent_idx = 0
        elif button in (7, 9):
            if self.current_view == "systems":
                self.rescan()
            else:
                self.select_item()

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
                    # Left stick
                    axis_y = controller.get_axis(1) if controller.get_numaxes() > 1 else 0.0
                    axis_x = controller.get_axis(0) if controller.get_numaxes() > 0 else 0.0
                    # D-pad hat (if present)
                    hat_y = 0
                    hat_x = 0
                    if controller.get_numhats() > 0:
                        hat = controller.get_hat(0)
                        hat_x, hat_y = hat[0], hat[1]
                except pygame.error:
                    continue
                if axis_y < -0.55 or hat_y > 0:
                    self.navigate_up()
                    moved = True
                    break
                if axis_y > 0.55 or hat_y < 0:
                    self.navigate_down()
                    moved = True
                    break
                if self.current_view == "systems" and (axis_x < -0.7 or hat_x < 0):
                    self.cycle_category(-1)
                    moved = True
                    break
                if self.current_view == "systems" and (axis_x > 0.7 or hat_x > 0):
                    self.cycle_category(1)
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
        # Controller multi-player status
        status_text = self.controller_summary()
        if len(self.controllers) >= 2:
            status_color = COLOR_SUCCESS
        elif len(self.controllers) == 1:
            status_color = COLOR_WARNING
        else:
            status_color = COLOR_TEXT_DIM
        # RetroArch status dot.
        dot_color = COLOR_SUCCESS if find_retroarch_exe() else COLOR_ERROR
        pygame.draw.circle(
            self.screen, dot_color, (self.screen_width - 18, header_h // 2), 8
        )
        status = self.font_small.render(status_text, True, status_color)
        self.screen.blit(
            status,
            (self.screen_width - status.get_width() - 36,
             (header_h - status.get_height()) // 2),
        )
        # Category chip
        if self.category_filter and self.category_filter != "All":
            chip = self.font_small.render(
                "[%s]" % self.category_filter, True, COLOR_ACCENT_HOVER
            )
            self.screen.blit(chip, (title.get_width() + 40, (header_h - chip.get_height()) // 2))

    def _list_layout(self) -> Tuple[int, int, int, int]:
        panel_w = int(self.screen_width * 0.84)
        panel_x = (self.screen_width - panel_w) // 2
        start_y = int(self.screen_height * 0.14)
        item_h = max(56, int(68 * self.scale))
        return panel_x, panel_w, start_y, item_h

    def draw_systems_view(self) -> None:
        systems = self._systems_list()
        if systems:
            self.selected_system_idx %= len(systems)
        else:
            self.selected_system_idx = 0

        panel_x, panel_w, start_y, item_h = self._list_layout()
        title = self.font_large.render("Select System", True, COLOR_TEXT)
        self.screen.blit(title, (panel_x, start_y))
        filter_bits = []
        if self.category_filter and self.category_filter != "All":
            filter_bits.append("cat=%s" % self.category_filter)
        if self.system_filter:
            filter_bits.append("filter='%s'" % self.system_filter)
        if not self.show_empty_systems:
            filter_bits.append("hide-empty")
        hint_main = "Up/Down Enter | Left/Right or Tab category | type to filter | R rescan | C categories | F2 recents | F1 help"
        if filter_bits:
            hint_main = "Active: " + ", ".join(filter_bits) + "  |  ESC clears"
        hint = self.font_small.render(hint_main, True, COLOR_TEXT_DIM)
        self.screen.blit(hint, (panel_x, start_y + int(52 * self.scale)))
        list_y = start_y + int(92 * self.scale)

        visible = max(1, (self.screen_height - list_y - 90) // item_h)
        if self.selected_system_idx < self.system_scroll:
            self.system_scroll = self.selected_system_idx
        elif self.selected_system_idx >= self.system_scroll + visible:
            self.system_scroll = self.selected_system_idx - visible + 1

        total_games = sum(len(s.games) for s in self.systems)
        count_label = self.font_small.render(
            "%d shown / %d systems - %d games" % (len(systems), len(self.systems), total_games),
            True,
            COLOR_TEXT_DIM,
        )
        self.screen.blit(count_label, (panel_x + panel_w - count_label.get_width(), start_y + 8))

        if not systems:
            empty = self.font_medium.render(
                "No systems match - press ESC to clear filters or E to show empty",
                True, COLOR_TEXT_DIM,
            )
            self.screen.blit(empty, (panel_x, list_y + 20))
            return

        for row, idx in enumerate(
            range(self.system_scroll, min(len(systems), self.system_scroll + visible))
        ):
            system = systems[idx]
            y = list_y + row * item_h
            selected = idx == self.selected_system_idx
            rect = pygame.Rect(panel_x, y, panel_w, item_h - 8)
            pygame.draw.rect(
                self.screen, COLOR_ACCENT if selected else COLOR_PANEL, rect, border_radius=10
            )
            badge = "[%s]" % system.short_name
            mp = "  %dP" % system.players if system.players and system.players > 1 else ""
            name = self.font_medium.render(
                "%s %s%s" % (badge, safe_text(system.name), mp), True, COLOR_TEXT
            )
            self.screen.blit(name, (panel_x + 16, y + 8))
            detail_parts = ["%d games" % len(system.games)]
            if system.category:
                detail_parts.append(system.category)
            if system.era:
                detail_parts.append(system.era)
            if system.core_name() and resolve_core_path(system.core_name()) is None:
                detail_parts.append("core missing!")
            missing_bios = [
                b for b in system.bios if not (RETROARCH_PATH / "system" / b).exists()
            ]
            if missing_bios and system.bios:
                detail_parts.append("BIOS: %s?" % ", ".join(missing_bios[:2]))
            detail_color = COLOR_WARNING if ("core missing" in " ".join(detail_parts) or "BIOS" in " ".join(detail_parts)) else COLOR_TEXT_DIM
            detail = self.font_small.render(
                "   ".join(detail_parts), True, detail_color
            )
            self.screen.blit(detail, (panel_x + 16, y + int(36 * self.scale)))

        if len(systems) > visible:
            self.draw_scrollbar(panel_x + panel_w + 8, list_y, visible, len(systems), self.system_scroll)

    def draw_games_view(self) -> None:
        system = self.current_system()
        if system is None:
            empty = self.font_medium.render("No system selected", True, COLOR_TEXT_DIM)
            self.screen.blit(empty, (40, 120))
            return
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
            "  Up/Down or D-pad/stick ... Navigate (any connected pad)",
            "  Enter or A ............... Select / Launch",
            "  ESC or B ................. Back / Exit",
            "  Left/Right or LB/RB ...... Cycle category filter",
            "  Tab / Shift+Tab .......... Cycle category",
            "  Type letters ............. Live filter (systems or games)",
            "  PageUp/PageDown .......... Jump 5 items",
            "  F11 ...................... Toggle fullscreen",
            "  F1 ....................... This help screen",
            "  F2 ....................... Recent games",
            "  F3 / C ................... Categories browser",
            "  F7 / E ................... Toggle empty systems",
            "  R (systems view) ......... Rescan ROM library",
            "",
            "GAME LIST",
            "  F5 / F / Y ............... Toggle favorite (*)",
            "  F6 / V / X ............... Show favorites only",
            "",
            "2-PLAYER JOYSTICKS",
            "  Plug in 2+ pads .......... Auto-assigned P1, P2, P3, P4",
            "  In-game P1 keyboard ...... Arrows + Z/X/A/S + Enter",
            "  In-game P2 keyboard ...... IJKL + F/G/R/T + B",
            "  Hotkeys .................. Hold Select/Back + Start = Quit",
            "",
            "IN GAME (RetroArch)",
            "  F1 ....................... RetroArch menu",
            "  F2 / F4 .................. Quick save / load",
            "  F8 ....................... Screenshot",
            "  Hold Space ............... Fast forward",
            "  R (with rewind on) ....... Rewind",
            "  ESC ...................... Quit to launcher",
            "",
            "ADD FREE GAMES",
            "  Tools/download-roms ...... Legal homebrew catalog (50+ systems)",
            "  Edit free-games-catalog.json to expand forever",
        ]
        y = start_y + int(50 * self.scale)
        line_h = max(18, int(22 * self.scale))
        for line in lines:
            color = COLOR_ACCENT_HOVER if line.isupper() and line else COLOR_TEXT_DIM
            if line and not line.startswith(" ") and not line.isupper():
                color = COLOR_TEXT
            rendered = self.font_small.render(line or " ", True, color)
            self.screen.blit(rendered, (panel_x + 10, y))
            y += line_h
            if y > self.screen_height - 70:
                break

    def draw_recents_view(self) -> None:
        panel_x, panel_w, start_y, item_h = self._list_layout()
        title = self.font_large.render("Recent Games", True, COLOR_TEXT)
        self.screen.blit(title, (panel_x, start_y))
        entries = self.recent_entries()
        hint = self.font_small.render(
            "Enter launches  |  ESC back  |  %d recent" % len(entries),
            True, COLOR_TEXT_DIM,
        )
        self.screen.blit(hint, (panel_x, start_y + int(52 * self.scale)))
        list_y = start_y + int(92 * self.scale)
        if not entries:
            empty = self.font_medium.render(
                "No recent games yet - launch something!", True, COLOR_TEXT_DIM
            )
            self.screen.blit(empty, (panel_x, list_y + 20))
            return
        self.selected_recent_idx %= len(entries)
        visible = max(1, (self.screen_height - list_y - 90) // item_h)
        if self.selected_recent_idx < self.recent_scroll:
            self.recent_scroll = self.selected_recent_idx
        elif self.selected_recent_idx >= self.recent_scroll + visible:
            self.recent_scroll = self.selected_recent_idx - visible + 1
        for row, idx in enumerate(
            range(self.recent_scroll, min(len(entries), self.recent_scroll + visible))
        ):
            system, game = entries[idx]
            y = list_y + row * item_h
            selected = idx == self.selected_recent_idx
            rect = pygame.Rect(panel_x, y, panel_w, item_h - 8)
            pygame.draw.rect(
                self.screen, COLOR_ACCENT if selected else COLOR_PANEL, rect, border_radius=10
            )
            star = "* " if self.fav_key(system, game) in self.favorites else ""
            label = "%s[%s] %s" % (star, system.short_name, safe_text(game["name"]))
            name = self.font_medium.render(label[:90], True, COLOR_TEXT)
            self.screen.blit(name, (panel_x + 16, y + 8))
            meta = self.font_small.render(
                "%s  |  %s  |  %dP" % (system.name, game["ext"].upper(), system.players),
                True, COLOR_TEXT_DIM,
            )
            self.screen.blit(meta, (panel_x + 16, y + int(36 * self.scale)))

    def draw_categories_view(self) -> None:
        panel_x, panel_w, start_y, item_h = self._list_layout()
        title = self.font_large.render("Categories", True, COLOR_TEXT)
        self.screen.blit(title, (panel_x, start_y))
        cats = self.all_categories()
        hint = self.font_small.render(
            "Enter applies filter  |  ESC back", True, COLOR_TEXT_DIM
        )
        self.screen.blit(hint, (panel_x, start_y + int(52 * self.scale)))
        list_y = start_y + int(92 * self.scale)
        self.selected_category_idx %= len(cats)
        visible = max(1, (self.screen_height - list_y - 90) // item_h)
        scroll = max(0, self.selected_category_idx - visible + 1) if self.selected_category_idx >= visible else 0
        for row, idx in enumerate(range(scroll, min(len(cats), scroll + visible))):
            cat = cats[idx]
            y = list_y + row * item_h
            selected = idx == self.selected_category_idx
            rect = pygame.Rect(panel_x, y, panel_w, item_h - 8)
            pygame.draw.rect(
                self.screen, COLOR_ACCENT if selected else COLOR_PANEL, rect, border_radius=10
            )
            if cat == "All":
                count = len(self.systems)
            elif cat == "Multiplayer":
                count = sum(1 for s in self.systems if s.players >= 2)
            elif cat == "Favorites":
                count = len(self.favorites)
            elif cat == "Recents":
                count = len(self.recent_entries())
            else:
                count = sum(1 for s in self.systems if s.category == cat)
            label = self.font_medium.render(
                "%s (%d)" % (cat, count), True, COLOR_TEXT
            )
            self.screen.blit(label, (panel_x + 16, y + (item_h - 8 - label.get_height()) // 2))

    def draw_footer(self) -> None:
        footer_h = 56
        footer_y = self.screen_height - footer_h
        pygame.draw.rect(
            self.screen, COLOR_PANEL, (0, footer_y, self.screen_width, footer_h)
        )
        if self.current_view == "systems":
            controls = "Enter Select | Tab Category | R Rescan | C Cats | F2 Recents | E Empty | F1 Help | ESC Exit"
        elif self.current_view == "games":
            controls = "Type to search | Enter Launch | F Favorite | V Fav-only | ESC Back"
        elif self.current_view == "recents":
            controls = "Enter Launch recent | ESC Back"
        elif self.current_view == "categories":
            controls = "Enter Apply category | ESC Back"
        else:
            controls = "F1 or ESC to close help"
        rendered = self.font_small.render(controls, True, COLOR_TEXT_DIM)
        rect = rendered.get_rect(center=(self.screen_width // 2, footer_y + footer_h // 2))
        now = pygame.time.get_ticks()
        if self.toast_message and now < self.toast_until:
            toast = self.font_small.render(self.toast_message, True, self.toast_color)
            toast_rect = toast.get_rect(
                center=(self.screen_width // 2, footer_y + footer_h // 2)
            )
            self.screen.blit(toast, toast_rect)
        else:
            self.screen.blit(rendered, rect)

    def run(self) -> int:
        assert pygame is not None
        self.running = True
        if len(self.controllers) >= 2:
            self.show_toast(
                "Dual-player ready: %d controllers" % len(self.controllers),
                COLOR_SUCCESS, 3500,
            )
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
            elif self.current_view == "recents":
                self.draw_recents_view()
            elif self.current_view == "categories":
                self.draw_categories_view()
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
    check("systems load", len(systems) >= 40, "(%d systems)" % len(systems))
    check(
        "N64 core fixed",
        any(s.folder == "N64" and s.core_name() == "mupen64plus_next" for s in systems),
    )
    check(
        "multiplayer systems present",
        sum(1 for s in systems if s.players >= 2) >= 15,
        "(%d 2P+ systems)" % sum(1 for s in systems if s.players >= 2),
    )
    check(
        "categories present",
        len({s.category for s in systems}) >= 5,
        "(%d cats)" % len({s.category for s in systems}),
    )
    cat = catalog_stats()
    check("free-games catalog", cat["entries"] >= 50, "(%d entries / %d systems)" % (cat["entries"], cat["systems"]))

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
    parser.add_argument("--catalog", action="store_true", help="Show free-games catalog stats")
    parser.add_argument("--list-systems", action="store_true", help="List all configured systems")
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

    if getattr(args, "catalog", False):
        cat = catalog_stats()
        print("Free-games catalog v%s" % cat["version"])
        print("  Systems covered: %d" % cat["systems"])
        print("  Curated entries: %d" % cat["entries"])
        print("  File: %s" % CATALOG_JSON)
        print("  Update anytime by editing the JSON — no code changes needed.")
        print("  Download: Tools/download-roms.bat -System All")
        return 0

    if getattr(args, "list_systems", False):
        print("%-16s %-8s %-6s %-12s %s" % ("FOLDER", "CORE", "PLAYERS", "CATEGORY", "NAME"))
        for s in systems:
            print("%-16s %-8s %-6s %-12s %s" % (
                s.folder, (s.core_name() or "?")[:8], s.players, (s.category or "")[:12], s.name))
        print("Total: %d systems" % len(systems))
        return 0

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
