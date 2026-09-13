param(
    [switch]$SkipPython = $false,
    [switch]$SkipRetroArch = $false,
    [switch]$SkipCoreDownloads = $false,
    [switch]$QuickSetup = $false,
    [switch]$NonInteractive = $false,
    [switch]$Unattended = $false,
    [switch]$InstallPython = $false,
    [switch]$IncludeSampleRoms = $false
)

$ErrorActionPreference = "Stop"
$USBRoot = $PSScriptRoot

. (Join-Path $PSScriptRoot "Tools\ps-common.ps1")

if ($Unattended) {
    $NonInteractive = $true
    $InstallPython = $true
}

Clear-ScreenSafe
$logPath = Start-SetupLog -RootPath $USBRoot -Name "setup"

$versionInfo = Get-VersionInfo -RootPath $USBRoot
Write-Banner -Title ("PORTABLE RETRO GAMING SUITE SETUP v{0}" -f $versionInfo.Version) -Subtitle ("USB root: {0}" -f $USBRoot)
if ($logPath) {
    Write-InfoLine ("Log file: {0}" -f $logPath)
}

$pathInfo = Get-PortablePathInfo -RootPath $USBRoot
$pythonInfo = $null

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).
    IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-WarnLine "Administrator rights are recommended for the smoothest setup."
}

# --- Preflight: internet + disk space -------------------------------------
Write-Section "Preflight Checks"

$online = Test-InternetConnection
if ($online) {
    Write-OkLine "Internet connection detected."
}
else {
    Write-FailLine "No internet connection detected. Downloads will fail."
    if (-not (Read-YesNo -Prompt "Continue offline anyway?" -Default $false -NonInteractive:$NonInteractive)) {
        throw "Setup aborted: internet access is required to download RetroArch and cores."
    }
}

$freeGB = Get-FreeDiskSpaceGB -Path $USBRoot
if ($freeGB -ge 0) {
    Write-InfoLine ("Free disk space: {0} GB" -f $freeGB)
    if ($freeGB -lt 1) {
        Write-WarnLine "Less than 1 GB free. RetroArch + cores need roughly 1-2 GB."
    }
}
else {
    Write-WarnLine "Could not determine free disk space."
}

Ensure-PortableFolders -RootPath $USBRoot

# --- Step 1: Python --------------------------------------------------------
Write-Section "Step 1 - Python"

if ($SkipPython) {
    Write-InfoLine "Skipping Python checks."
}
else {
    $pythonInfo = Find-PythonCommand
    if (-not $pythonInfo) {
        Write-FailLine "Python was not found in PATH."
        $doAutoInstall = $InstallPython
        if (-not $doAutoInstall) {
            $doAutoInstall = Read-YesNo -Prompt "Install Python automatically via winget?" -Default $true -NonInteractive:$NonInteractive
        }
        if ($doAutoInstall) {
            if (Install-PythonViaWinget) {
                $pythonInfo = Find-PythonCommand
            }
        }
        if (-not $pythonInfo) {
            Write-InfoLine "Download Python from https://www.python.org/downloads/"
            Write-InfoLine "IMPORTANT: check 'Add Python to PATH' during installation."
            if (Read-YesNo -Prompt "Open the Python download page now?" -Default $false -NonInteractive:$NonInteractive) {
                Start-Process "https://www.python.org/downloads/"
            }
            throw "Python is required for the launcher and controller tools."
        }
    }

    Write-OkLine ("Found Python {0} via '{1}'." -f $pythonInfo.Version, $pythonInfo.Command)
    if ($pythonInfo.Major -lt 3 -or ($pythonInfo.Major -eq 3 -and $pythonInfo.Minor -lt 9)) {
        Write-WarnLine "Python 3.9+ is recommended. Some features may misbehave on older versions."
    }

    if (Ensure-PythonPackage -PythonCommand $pythonInfo.Command -PackageName "pygame-ce" -ModuleName "pygame" -FallbackPackages @("pygame")) {
        Write-OkLine "pygame is available."
    }
    else {
        throw "pygame could not be installed automatically. Try: python -m pip install pygame-ce"
    }
}

# --- Step 2: RetroArch -----------------------------------------------------
Write-Section "Step 2 - RetroArch"

$retroArchReady = Test-Path -LiteralPath $pathInfo.RetroArchExe

if ($SkipRetroArch) {
    Write-InfoLine "Skipping RetroArch installation."
}
else {
    $forceRetroArch = $false
    if ($retroArchReady) {
        $forceRetroArch = Read-YesNo -Prompt "RetroArch is already installed. Reinstall it?" -Default $false -NonInteractive:$NonInteractive
    }

    $retroArchPath = Install-RetroArchPortable -RootPath $USBRoot -Force:$forceRetroArch
    $retroArchReady = Test-Path -LiteralPath (Join-Path $retroArchPath "retroarch.exe")
    if (-not $retroArchReady) {
        throw "RetroArch installation did not produce retroarch.exe."
    }
}

# --- Step 3: Cores ---------------------------------------------------------
Write-Section "Step 3 - Emulator Cores"

if ($SkipCoreDownloads) {
    Write-InfoLine "Skipping core downloads."
}
elseif (-not $retroArchReady) {
    Write-WarnLine "RetroArch is missing, skipping core downloads."
}
else {
    $coreSummary = Install-RetroArchCores -RootPath $USBRoot
    Write-InfoLine ("Downloaded: {0}  Skipped: {1}  Failed: {2}" -f $coreSummary.Downloaded, $coreSummary.Skipped, $coreSummary.Failed)
    if ($coreSummary.Failed -gt 0) {
        Write-WarnLine ("Failed cores: {0}" -f ($coreSummary.FailedNames -join ", "))
        Write-InfoLine "Re-run SETUP or Tools\update-system.bat to retry failed cores."
    }
}

# --- Step 4: Configuration -------------------------------------------------
Write-Section "Step 4 - Configuration"
Configure-RetroArch -RootPath $USBRoot

# --- Step 5: Validation ----------------------------------------------------
Write-Section "Step 5 - Validation"

$audit = Get-RetroGamingAudit -RootPath $USBRoot

$scriptChecks = @(
    @{ Label = "LAUNCH.bat"; Path = $pathInfo.LaunchBat },
    @{ Label = "SETUP.bat"; Path = $pathInfo.SetupBat },
    @{ Label = "launcher.py"; Path = $pathInfo.LauncherScript },
    @{ Label = "download-roms.bat"; Path = $pathInfo.DownloadRomsBat },
    @{ Label = "organize-roms.bat"; Path = $pathInfo.OrganizeRomsBat },
    @{ Label = "test-controller.bat"; Path = $pathInfo.TestControllerBat },
    @{ Label = "update-system.bat"; Path = $pathInfo.UpdateSystemBat },
    @{ Label = "diagnose.bat"; Path = $pathInfo.DiagnoseBat }
)
foreach ($check in $scriptChecks) {
    if (Test-Path -LiteralPath $check.Path) {
        Write-OkLine ("{0} is ready." -f $check.Label)
    }
    else {
        Write-WarnLine ("{0} is missing." -f $check.Label)
    }
}

Write-InfoLine ("RetroArch installed: {0}" -f $audit.RetroArchInstalled)
Write-InfoLine ("Core count: {0}" -f $audit.CoreCount)
Write-InfoLine ("ROM count: {0}" -f $audit.RomCount)
if ($audit.MissingBios.Count -gt 0) {
    Write-WarnLine "Missing BIOS files (only needed for those systems):"
    foreach ($bios in $audit.MissingBios) {
        Write-InfoLine ("  - {0}" -f $bios)
    }
}
else {
    Write-OkLine "All configured BIOS files are present."
}

# --- Step 6: Sample ROMs (optional) ----------------------------------------
if ((-not $QuickSetup) -and (Test-Path -LiteralPath $pathInfo.DownloadRomsScript)) {
    Write-Section "Step 6 - Sample ROMs"
    $wantSamples = $IncludeSampleRoms
    if (-not $wantSamples -and -not $NonInteractive) {
        $wantSamples = Read-YesNo -Prompt "Download a small legal sample game pack now?" -Default $false
    }
    if ($wantSamples) {
        & $pathInfo.DownloadRomsScript -System "All" -NonInteractive
    }
    else {
        Write-InfoLine "Skipped sample ROM download."
    }
}

# --- Summary ---------------------------------------------------------------
Write-Section "Setup Summary"

$audit = Get-RetroGamingAudit -RootPath $USBRoot
Write-InfoLine ("RetroArch installed: {0}" -f $audit.RetroArchInstalled)
Write-InfoLine ("Core count: {0}" -f $audit.CoreCount)
Write-InfoLine ("ROM count: {0}" -f $audit.RomCount)
Write-InfoLine ("Launcher present: {0}" -f $audit.LauncherExists)
if ($logPath) {
    Write-InfoLine ("Full log: {0}" -f $logPath)
}
Write-Host ""
Write-OkLine "Setup finished."

if ($audit.RetroArchInstalled -and $audit.CoreCount -eq 0) {
    Write-WarnLine "No cores were installed. Run Tools\update-system.bat (option 1) to retry."
}

if (Read-YesNo -Prompt "Launch the gaming system now?" -Default $false -NonInteractive:$NonInteractive) {
    if (Test-Path -LiteralPath $pathInfo.LaunchBat) {
        & $pathInfo.LaunchBat
    }
    else {
        Write-WarnLine "LAUNCH.bat was not found, so the launcher was not started."
    }
}

Pause-IfInteractive -Prompt "Press Enter to exit setup" -NonInteractive:$NonInteractive
