param(
    [switch]$Fix = $false,
    [switch]$NonInteractive = $false,
    [switch]$Json = $false
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot "ps-common.ps1")

Clear-ScreenSafe
$logPath = Start-SetupLog -RootPath $RepoRoot -Name "diagnose"

$versionInfo = Get-VersionInfo -RootPath $RepoRoot
if (-not $Json) {
    Write-Banner -Title "RETRO GAMING DIAGNOSTICS" -Subtitle ("Suite v{0} - {1}" -f $versionInfo.Version, $RepoRoot)
}

$paths = Get-PortablePathInfo -RootPath $RepoRoot
$issues = New-Object System.Collections.Generic.List[string]
$fixed = New-Object System.Collections.Generic.List[string]

function Add-Issue {
    param([string]$Message)
    $issues.Add($Message) | Out-Null
    if (-not $Json) { Write-FailLine $Message }
}

function Add-Healthy {
    param([string]$Message)
    if (-not $Json) { Write-OkLine $Message }
}

# --- 1. Python + pygame ------------------------------------------------------
$pythonInfo = Find-PythonCommand
$pygameOk = $false
if (-not $pythonInfo) {
    Add-Issue "Python is not installed or not on PATH."
    if (-not $Json) {
        Write-InfoLine "  Fix: run SETUP.bat (auto-installs Python) or install from https://www.python.org/downloads/"
    }
}
else {
    Add-Healthy ("Python {0} found via '{1}'." -f $pythonInfo.Version, $pythonInfo.Command)
    $pygameOk = Test-PythonModule -PythonCommand $pythonInfo.Command -ModuleName "pygame"
    if ($pygameOk) {
        Add-Healthy "pygame module is importable."
    }
    else {
        Add-Issue "pygame is not installed for Python."
        if ($Fix) {
            if (Ensure-PythonPackage -PythonCommand $pythonInfo.Command -PackageName "pygame-ce" -ModuleName "pygame" -FallbackPackages @("pygame")) {
                $fixed.Add("Installed pygame.") | Out-Null
                $pygameOk = $true
            }
        }
        elseif (-not $Json) {
            Write-InfoLine "  Fix: run Tools\diagnose.bat -Fix  or:  python -m pip install pygame-ce"
        }
    }
}

# --- 2. Folder structure -----------------------------------------------------
foreach ($folder in @("Emulators", "ROMs", "Save States", "Screenshots", "Logs")) {
    $full = Join-Path $RepoRoot $folder
    if (-not (Test-Path -LiteralPath $full)) {
        if ($Fix) {
            Ensure-Directory -Path $full | Out-Null
            $fixed.Add(("Created missing folder: {0}" -f $folder)) | Out-Null
        }
        else {
            Add-Issue ("Missing folder: {0}" -f $folder)
        }
    }
}
if ($Fix) { Ensure-PortableFolders -RootPath $RepoRoot | Out-Null }

# --- 3. RetroArch + cores ----------------------------------------------------
$audit = Get-RetroGamingAudit -RootPath $RepoRoot
if ($audit.RetroArchInstalled) {
    Add-Healthy "RetroArch is installed."
}
else {
    Add-Issue "RetroArch is not installed (no Emulators\RetroArch\retroarch.exe)."
    if ($Fix) {
        Install-RetroArchPortable -RootPath $RepoRoot | Out-Null
        Configure-RetroArch -RootPath $RepoRoot
        $audit = Get-RetroGamingAudit -RootPath $RepoRoot
        if ($audit.RetroArchInstalled) {
            $fixed.Add("Installed RetroArch.") | Out-Null
        }
    }
    elseif (-not $Json) {
        Write-InfoLine "  Fix: run SETUP.bat or Tools\diagnose.bat -Fix"
    }
}

if ($audit.RetroArchInstalled) {
    if ($audit.CoreCount -ge 10) {
        Add-Healthy ("Emulator cores installed: {0}." -f $audit.CoreCount)
    }
    else {
        Add-Issue ("Only {0} emulator core(s) installed (expected 13)." -f $audit.CoreCount)
        if ($Fix) {
            $missing = @()
            $coresPath = Join-Path $RepoRoot "Emulators\RetroArch\cores"
            foreach ($core in $script:DefaultCoreDefinitions) {
                if (-not (Test-Path -LiteralPath (Join-Path $coresPath ("{0}_libretro.dll" -f $core.Name)))) {
                    $missing += $core.Name
                }
            }
            if ($missing.Count -gt 0) {
                Install-RetroArchCores -RootPath $RepoRoot -OnlyCores $missing | Out-Null
                $fixed.Add(("Installed {0} missing core(s)." -f $missing.Count)) | Out-Null
            }
            $audit = Get-RetroGamingAudit -RootPath $RepoRoot
        }
        elseif (-not $Json) {
            Write-InfoLine "  Fix: run Tools\update-system.bat option 1, or diagnose with -Fix"
        }
    }
}

# --- 4. Config files ---------------------------------------------------------
foreach ($file in @("Configs\systems.json", "Configs\retroarch.cfg", "Configs\core-options.cfg")) {
    if (Test-Path -LiteralPath (Join-Path $RepoRoot $file)) {
        Add-Healthy ("{0} present." -f $file)
    }
    else {
        Add-Issue ("Missing config file: {0}" -f $file)
    }
}
if ($Fix) { Configure-RetroArch -RootPath $RepoRoot }

# --- 5. Launcher scripts -----------------------------------------------------
foreach ($pair in @(
    @{ Label = "LAUNCH.bat"; Path = $paths.LaunchBat },
    @{ Label = "Launcher\launcher.py"; Path = $paths.LauncherScript }
)) {
    if (Test-Path -LiteralPath $pair.Path) {
        Add-Healthy ("{0} present." -f $pair.Label)
    }
    else {
        Add-Issue ("Missing: {0}" -f $pair.Label)
    }
}

# --- 6. ROM library ----------------------------------------------------------
$audit = Get-RetroGamingAudit -RootPath $RepoRoot
if ($audit.RomCount -gt 0) {
    Add-Healthy ("ROM library contains {0} file(s)." -f $audit.RomCount)
}
else {
    if (-not $Json) { Write-WarnLine "ROM library is empty. Add ROMs or run Tools\download-roms.bat for free samples." }
}

# --- 7. BIOS -----------------------------------------------------------------
if ($audit.MissingBios.Count -eq 0) {
    Add-Healthy "All configured BIOS files are present."
}
else {
    if (-not $Json) {
        Write-WarnLine "Missing BIOS files (only matters for those systems):"
        foreach ($bios in $audit.MissingBios) {
            Write-InfoLine ("  - {0}" -f $bios)
        }
        Write-InfoLine "  See Configs\BIOS-INFO.txt for legal sources."
    }
}

# --- 8. Launcher self-test (deep check) --------------------------------------
$selfTest = "skipped"
if ($pythonInfo -and $pygameOk -and (Test-Path -LiteralPath $paths.LauncherScript)) {
    try {
        $output = & $pythonInfo.Command $paths.LauncherScript --self-test 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            Add-Healthy "Launcher self-test passed."
            $selfTest = "passed"
        }
        else {
            Add-Issue "Launcher self-test reported failures."
            $selfTest = "failed"
            if (-not $Json) { Write-InfoLine $output }
        }
    }
    catch {
        Add-Issue ("Launcher self-test could not run: {0}" -f $_.Exception.Message)
        $selfTest = "error"
    }
}

# --- Report ------------------------------------------------------------------
$report = [pscustomobject]@{
    Healthy           = ($issues.Count -eq 0)
    IssueCount        = $issues.Count
    Issues            = $issues.ToArray()
    Fixed             = $fixed.ToArray()
    RetroArchInstalled = $audit.RetroArchInstalled
    CoreCount         = $audit.CoreCount
    RomCount          = $audit.RomCount
    MissingBios       = $audit.MissingBios
    PythonVersion     = $audit.PythonVersion
    PygameInstalled   = $audit.PygameInstalled
    LauncherSelfTest  = $selfTest
    LogFile           = $logPath
}

if ($Json) {
    $report | ConvertTo-Json -Depth 4
    if ($issues.Count -eq 0) { exit 0 } else { exit 1 }
}

Write-Section "Diagnosis Summary"
Write-InfoLine ("RetroArch: {0} | Cores: {1} | ROMs: {2} | BIOS missing: {3}" -f $audit.RetroArchInstalled, $audit.CoreCount, $audit.RomCount, $audit.MissingBios.Count)
if ($fixed.Count -gt 0) {
    Write-Host ""
    Write-OkLine "Auto-repairs applied:"
    foreach ($item in $fixed) {
        Write-InfoLine ("  - {0}" -f $item)
    }
}
if ($logPath) {
    Write-InfoLine ("Full log: {0}" -f $logPath)
}
Write-Host ""
if ($issues.Count -eq 0) {
    Write-OkLine "No problems found. Ready to play!"
    Pause-IfInteractive -Prompt "Press Enter to exit" -NonInteractive:$NonInteractive
    exit 0
}

Write-FailLine ("Found {0} problem(s)." -f $issues.Count)
if (-not $Fix) {
    if (Read-YesNo -Prompt "Attempt automatic repair now?" -Default $true -NonInteractive:$NonInteractive) {
        & $PSCommandPath -Fix -NonInteractive:$NonInteractive -Json:$Json
        exit $LASTEXITCODE
    }
}
Pause-IfInteractive -Prompt "Press Enter to exit" -NonInteractive:$NonInteractive
exit 1
