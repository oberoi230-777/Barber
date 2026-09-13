"""Smoke + integration tests for the Retro Gaming Suite launcher.

Run:  python -m pytest tests/ -v
Also runs headless (no display required).
"""
import json
import re
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "Launcher"))

import launcher  # noqa: E402


@pytest.fixture()
def systems():
    return launcher.load_systems(ROOT / "Configs" / "systems.json")


def test_systems_json_valid():
    data = json.loads((ROOT / "Configs" / "systems.json").read_text(encoding="utf-8"))
    assert isinstance(data, list) and len(data) >= 10
    for entry in data:
        assert entry["folder"], entry
        assert entry["extensions"], entry
        assert entry.get("core") or entry.get("emulator"), entry


def test_version_json_valid():
    data = json.loads((ROOT / "version.json").read_text(encoding="utf-8"))
    assert re.match(r"\d+\.\d+\.\d+", data["version"])
    assert data["retroarchStable"]


def test_n64_uses_next_core(systems):
    n64 = next(s for s in systems if s.folder == "N64")
    assert n64.core_name() == "mupen64plus_next"


def test_all_cores_have_ps1_download_definitions(systems):
    """Regression test: every core in systems.json must be downloadable by
    Install-RetroArchCores (catches the old mupen64plus vs mupen64plus_next
    mismatch class of bugs)."""
    ps_common = (ROOT / "Tools" / "ps-common.ps1").read_text(encoding="utf-8")
    defined = set(re.findall(r'Name\s*=\s*"([a-z0-9_]+)"', ps_common))
    for system in systems:
        core = launcher.CORE_ALIASES.get(system.core_name().lower(), system.core_name())
        assert core in defined, f"core '{core}' ({system.folder}) has no ps-common definition"


def test_all_cores_have_setup_sh_definitions(systems):
    setup_sh = (ROOT / "setup.sh").read_text(encoding="utf-8")
    for system in systems:
        core = launcher.CORE_ALIASES.get(system.core_name().lower(), system.core_name())
        assert core in setup_sh, f"core '{core}' ({system.folder}) missing from setup.sh"


def test_scan_recursive_case_insensitive(tmp_path, systems):
    nes_dir = tmp_path / "NES" / "Sub Folder"
    nes_dir.mkdir(parents=True)
    (tmp_path / "NES" / "Game One.NES").write_bytes(b"x" * 16)
    (nes_dir / "Game Two.nes").write_bytes(b"y" * 32)
    (tmp_path / "NES" / "notes.txt").write_bytes(b"ignore")
    nes = next(s for s in systems if s.folder == "NES")
    assert nes.scan_games(tmp_path) == 2


def test_scan_hides_companion_bins(tmp_path, systems):
    psx = tmp_path / "PlayStation"
    psx.mkdir(parents=True)
    (psx / "Disc.cue").write_text("dummy")
    (psx / "Disc.bin").write_bytes(b"z" * 64)
    system = next(s for s in systems if s.folder == "PlayStation")
    assert system.scan_games(tmp_path) == 1
    assert system.games[0]["name"] == "Disc"


def test_scan_supports_archives(tmp_path, systems):
    snes_dir = tmp_path / "SNES"
    snes_dir.mkdir(parents=True)
    (snes_dir / "Game.zip").write_bytes(b"PK\x03\x04")
    system = next(s for s in systems if s.folder == "SNES")
    assert system.scan_games(tmp_path) == 1


def test_core_aliases():
    assert launcher.CORE_ALIASES["mupen64plus"] == "mupen64plus_next"
    assert launcher.resolve_core_path("mupen64plus") is None or True  # no crash w/o cores


def test_parse_launch_target():
    assert launcher.parse_launch_target("NES/Zelda") == ("NES", "Zelda")
    assert launcher.parse_launch_target(r"SNES\Mario") == ("SNES", "Mario")
    assert launcher.parse_launch_target("Zelda") == ("", "Zelda")


def test_safe_text_strips_emoji():
    assert launcher.safe_text("Hello \U0001F3AE World") == "Hello World"
    assert launcher.safe_text("RETRO GAMING") == "RETRO GAMING"


def test_build_launch_command_requires_retroarch(systems, tmp_path, monkeypatch):
    monkeypatch.setattr(launcher, "RETROARCH_PATH", tmp_path / "missing")
    monkeypatch.setattr(launcher, "find_retroarch_exe", lambda: None)
    nes = next(s for s in systems if s.folder == "NES")
    with pytest.raises(FileNotFoundError):
        launcher.build_launch_command(nes, str(tmp_path / "game.nes"))


def test_health_check_runs(systems):
    report = launcher.health_check(systems)
    assert isinstance(report["total_games"], int)
    assert "missing_cores" in report and "missing_bios" in report


def test_self_test_passes():
    assert launcher.run_self_test() == 0


def test_retroarch_cfg_has_no_duplicates():
    """The master config must not contain contradictory duplicate keys."""
    keys = []
    for line in (ROOT / "Configs" / "retroarch.cfg").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        keys.append(line.split("=", 1)[0].strip())
    dupes = sorted({k for k in keys if keys.count(k) > 1})
    assert dupes == [], f"duplicate keys in retroarch.cfg: {dupes}"


def test_xbox_autoconfig_has_unique_buttons():
    """Regression test: Start/Back must not share indexes with triggers."""
    text = (ROOT / "Configs" / "autoconfig" / "dinput" / "Xbox_Controller.cfg").read_text(encoding="utf-8")
    # Hotkey/modifier bindings intentionally share indexes with gameplay
    # buttons (hold Select + Start = exit). Only gameplay buttons must be unique.
    modifiers = {"input_enable_hotkey_btn", "input_exit_emulator_btn",
                 "input_menu_toggle_btn", "input_save_state_btn", "input_load_state_btn"}
    btn = {}
    for line in text.splitlines():
        m = re.match(r'\s*(input_\w+_btn)\s*=\s*"(\d+)"', line)
        if m and m.group(1) not in modifiers:
            btn.setdefault(m.group(2), []).append(m.group(1))
    collisions = {k: v for k, v in btn.items() if len(v) > 1}
    assert collisions == {}, f"gameplay button index collisions: {collisions}"


def test_tools_exist():
    for name in ["ps-common.ps1", "download-roms.ps1", "organize-roms.ps1",
                 "test-controller.ps1", "update-system.ps1", "diagnose.ps1",
                 "download-roms.bat", "organize-roms.bat", "test-controller.bat",
                 "update-system.bat", "diagnose.bat"]:
        assert (ROOT / "Tools" / name).exists(), f"missing Tools/{name}"
