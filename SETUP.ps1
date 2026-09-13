param(
    [switch]$SkipPython = $false,
    [switch]$SkipRetroArch = $false,
    [switch]$SkipCoreDownloads = $false,
    [switch]$QuickSetup = $false,
    [switch]$NonInteractive = $false
)

$ErrorActionPreference = "Stop"
$USBRoot = $PSScriptRoot

. (Join-Path $PSScriptRoot "Tools\ps-common.ps1")

try {
    Clear-Host
}
catch {
}

Write-Banner -Title "PORTABLE RETRO GAMING SUITE SETUP" -Subtitle ("USB root: {0}" -f $USBRoot)

$pathInfo = Get-PortablePathInfo -RootPath $USBRoot
$retroArchReady = Test-Path -LiteralPath (Join-Path $USBRoot "Emulators\RetroArch\retroarch.exe")
$pythonInfo = $null

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).
    IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-WarnLine "Administrator rights are recommended for the smoothest setup."
}

Write-Section "Step 1 - Python"

if ($SkipPython) {
    Write-InfoLine "Skipping Python checks."
}
else {
    $pythonInfo = Find-PythonCommand
    if (-not $pythonInfo) {
        Write-FailLine "Python was not found in PATH."
        Write-InfoLine "Download Python from https://www.python.org/downloads/"
        if (Read-YesNo -Prompt "Open the Python download page now?" -Default $false -NonInteractive:$NonInteractive) {
            Start-Process "https://www.python.org/downloads/"
        }
        throw "Python is required for the launcher and controller tools."
    }

    Write-OkLine ("Found Python {0} via '{1}'." -f $pythonInfo.Version, $pythonInfo.Command)

    if (Ensure-PythonPackage -PythonCommand $pythonInfo.Command -PackageName "pygame" -ModuleName "pygame" -UseUserScope -FallbackPackages @("pygame-ce")) {
        Write-OkLine "pygame is available."
    }
    else {
        throw "pygame could not be installed automatically."
    }
}

Write-Section "Step 2 - RetroArch"

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
}

Write-Section "Step 3 - Emulator Cores"

if ($SkipCoreDownloads) {
    Write-InfoLine "Skipping core downloads."
}
else {
    $coreSummary = Install-RetroArchCores -RootPath $USBRoot
    Write-InfoLine ("Downloaded: {0}  Skipped: {1}  Failed: {2}" -f $coreSummary.Downloaded, $coreSummary.Skipped, $coreSummary.Failed)
}

Write-Section "Step 4 - Configuration"
Configure-RetroArch -RootPath $USBRoot

Write-Section "Step 5 - Validation"

if (Test-Path -LiteralPath $pathInfo.LauncherScript) {
    Write-OkLine "Launcher script is present."
}
else {
    Write-FailLine "Launcher script is missing."
}

foreach ($check in @(
    @{ Label = "LAUNCH.bat"; Path = $pathInfo.LaunchBat },
    @{ Label = "SETUP.bat"; Path = $pathInfo.SetupBat },
    @{ Label = "download-roms.bat"; Path = $pathInfo.DownloadRomsBat },
    @{ Label = "test-controller.bat"; Path = $pathInfo.TestControllerBat },
    @{ Label = "update-system.bat"; Path = $pathInfo.UpdateSystemBat }
)) {
    if (Test-Path -LiteralPath $check.Path) {
        Write-OkLine ("{0} is ready." -f $check.Label)
    }
    else {
        Write-WarnLine ("{0} is missing." -f $check.Label)
    }
}

if ((-not $QuickSetup) -and (Test-Path -LiteralPath $pathInfo.DownloadRomsScript)) {
    Write-Section "Step 6 - Sample ROMs"
    if (Read-YesNo -Prompt "Download a small legal NES sample set now?" -Default $false -NonInteractive:$NonInteractive) {
        & $pathInfo.DownloadRomsScript -System "NES" -Interactive:$false -NonInteractive
    }
    else {
        Write-InfoLine "Skipped sample ROM download."
    }
}

Write-Section "Setup Summary"

$audit = Get-RetroGamingAudit -RootPath $USBRoot
Write-InfoLine ("RetroArch installed: {0}" -f $audit.RetroArchInstalled)
Write-InfoLine ("Core count: {0}" -f $audit.CoreCount)
Write-InfoLine ("ROM count: {0}" -f $audit.RomCount)
Write-InfoLine ("Launcher present: {0}" -f $audit.LauncherExists)
Write-Host ""
Write-OkLine "Setup finished."

if (Read-YesNo -Prompt "Launch the gaming system now?" -Default $false -NonInteractive:$NonInteractive) {
    if (Test-Path -LiteralPath $pathInfo.LaunchBat) {
        & $pathInfo.LaunchBat
    }
    else {
        Write-WarnLine "LAUNCH.bat was not found, so the launcher was not started."
    }
}

Pause-IfInteractive -Prompt "Press Enter to exit setup" -NonInteractive:$NonInteractive
