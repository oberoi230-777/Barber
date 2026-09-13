"""Static regression tests for the PowerShell scripts.

The suite runs under `Set-StrictMode -Version Latest`, where reading a
missing property (e.g. `$system.bios` on a system without BIOS entries)
throws PropertyNotFoundStrict. All optional properties of
ConvertFrom-Json output MUST therefore go through the
Get-ObjectProperty helper in Tools/ps-common.ps1.

These tests parse the actual .ps1 sources and fail if a hardened
function ever regresses to direct risky access.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read_ps1(name):
    return (ROOT / name).read_text(encoding="utf-8-sig")


def function_body(source, func_name):
    """Extract the raw body of a top-level `function Name { ... }`."""
    match = re.search(r"(?m)^function\s+%s\s*\{" % re.escape(func_name), source)
    assert match, f"function {func_name} not found"
    depth = 0
    in_single = in_double = False
    i = match.end() - 1  # at the opening brace
    start = i
    while i < len(source):
        ch = source[i]
        if in_single:
            if ch == "'":
                if i + 1 < len(source) and source[i + 1] == "'":
                    i += 1
                else:
                    in_single = False
        elif in_double:
            if ch == "`":
                i += 1  # skip escaped char
            elif ch == '"':
                if i + 1 < len(source) and source[i + 1] == '"':
                    i += 1
                else:
                    in_double = False
        else:
            if ch == "'":
                in_single = True
            elif ch == '"':
                in_double = True
            elif ch == "#":
                while i < len(source) and source[i] != "\n":
                    i += 1
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return source[start + 1:i]
        i += 1
    raise AssertionError(f"unbalanced braces in function {func_name}")


def test_helper_exists_and_covers_all_cases():
    ps_common = read_ps1("Tools/ps-common.ps1")
    body = function_body(ps_common, "Get-ObjectProperty")
    # Must handle: $null input, dictionaries, and PSObject property lookup.
    assert "IDictionary" in body
    assert "PSObject.Properties" in body
    assert "Default" in body


def test_bios_check_has_no_direct_property_access():
    body = function_body(read_ps1("Tools/ps-common.ps1"), "Test-BiosFiles")
    for risky in ["$system.bios", "$system.folder"]:
        assert risky not in body, f"Test-BiosFiles uses strict-unsafe {risky}"
    assert "Get-ObjectProperty" in body


def test_portable_folders_has_no_direct_property_access():
    body = function_body(read_ps1("Tools/ps-common.ps1"), "Ensure-PortableFolders")
    assert "$system.folder" not in body
    assert "Get-ObjectProperty" in body


def test_version_info_has_no_direct_property_access():
    body = function_body(read_ps1("Tools/ps-common.ps1"), "Get-VersionInfo")
    assert "$parsed.version" not in body
    assert "$parsed.retroarchStable" not in body
    assert "Get-ObjectProperty" in body


def test_organizer_extension_map_has_no_direct_property_access():
    body = function_body(read_ps1("Tools/organize-roms.ps1"), "Get-ExtensionMap")
    for risky in ["$system.extensions", "$system.folder"]:
        assert risky not in body, f"Get-ExtensionMap uses strict-unsafe {risky}"
    assert "Get-ObjectProperty" in body


def test_archive_metadata_parsing_has_no_direct_property_access():
    download = read_ps1("Tools/download-roms.ps1")
    meta_body = function_body(download, "Get-ArchiveItemFiles")
    for risky in ["$metadata.files", "$file.source", "$file.name", "$file.size"]:
        assert risky not in meta_body, f"Get-ArchiveItemFiles uses strict-unsafe {risky}"
    assert "Get-ObjectProperty" in meta_body

    search_body = function_body(download, "Find-ArchiveRomCandidates")
    for risky in ["$search.response", "$doc.identifier"]:
        assert risky not in search_body, (
            f"Find-ArchiveRomCandidates uses strict-unsafe {risky}"
        )
    assert "Get-ObjectProperty" in search_body


def test_strict_mode_still_enabled():
    assert "Set-StrictMode -Version Latest" in read_ps1("Tools/ps-common.ps1")


def test_launch_bat_validates_python_before_use():
    # `where` alone accepts the broken Windows Store stub, so LAUNCH.bat
    # must probe that the candidate REALLY runs before using it.
    text = (ROOT / "LAUNCH.bat").read_text(encoding="utf-8-sig")
    assert "--version >nul" in text
    assert "if not defined PYCMD" in text
    assert "App execution aliases" in text  # Store-stub guidance


def test_launch_bat_never_closes_silently_on_error():
    text = (ROOT / "LAUNCH.bat").read_text(encoding="utf-8-sig")
    assert "EXITCODE" in text
    assert "launcher.log" in text
    fail_idx = text.find("stopped with an error")
    assert fail_idx != -1
    assert "pause" in text[fail_idx:]
    assert text.rstrip().endswith("exit /b %EXITCODE%")
