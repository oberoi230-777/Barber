param(
    [ValidateSet("Menu", "Cores", "RetroArch", "Python", "Check", "Backup")]
    [string]$Action = "Menu",
    [switch]$NonInteractive = $false
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot "ps-common.ps1")

function Update-CoreSet {
    Write-Section "Updating Emulator Cores"
    $summary = Install-RetroArchCores -RootPath $RepoRoot -Force
    Write-InfoLine ("Downloaded: {0}  Skipped: {1}  Failed: {2}" -f $summary.Downloaded, $summary.Skipped, $summary.Failed)
}

function Update-RetroArchInstall {
    Write-Section "Updating RetroArch"
    Install-RetroArchPortable -RootPath $RepoRoot -Force | Out-Null
    Configure-RetroArch -RootPath $RepoRoot
}

function Update-PythonDependencies {
    Write-Section "Updating Python Dependencies"
    $pythonInfo = Find-PythonCommand
    if (-not $pythonInfo) {
        Write-WarnLine "Python is not installed, so pygame could not be updated."
        return
    }

    if (Ensure-PythonPackage -PythonCommand $pythonInfo.Command -PackageName "pygame" -ModuleName "pygame" -UseUserScope -FallbackPackages @("pygame-ce")) {
        Write-OkLine "pygame is installed and ready."
    }
    else {
        Write-FailLine "pygame installation failed."
    }
}

function Show-SystemCheck {
    Write-Section "System Check"
    $audit = Get-RetroGamingAudit -RootPath $RepoRoot

    Write-InfoLine ("RetroArch installed: {0}" -f $audit.RetroArchInstalled)
    Write-InfoLine ("Launcher present: {0}" -f $audit.LauncherExists)
    Write-InfoLine ("Core count: {0}" -f $audit.CoreCount)
    Write-InfoLine ("ROM count: {0}" -f $audit.RomCount)

    $paths = Get-PortablePathInfo -RootPath $RepoRoot
    foreach ($pair in @(
        @{ Label = "LAUNCH.bat"; Path = $paths.LaunchBat },
        @{ Label = "SETUP.bat"; Path = $paths.SetupBat },
        @{ Label = "download-roms.ps1"; Path = $paths.DownloadRomsScript },
        @{ Label = "organize-roms.ps1"; Path = $paths.OrganizeRomsScript },
        @{ Label = "test-controller.ps1"; Path = $paths.TestControllerScript }
    )) {
        if (Test-Path -LiteralPath $pair.Path) {
            Write-OkLine ("{0} found." -f $pair.Label)
        }
        else {
            Write-WarnLine ("{0} missing." -f $pair.Label)
        }
    }
}

function Create-Backup {
    Write-Section "Creating Backup"

    $backupRoot = Ensure-Directory -Path (Join-Path $RepoRoot "Backups")
    $backupName = "Backup_{0}" -f (Get-Date -Format "yyyy-MM-dd_HH-mm-ss")
    $backupPath = Join-Path $backupRoot $backupName
    Ensure-Directory -Path $backupPath | Out-Null

    foreach ($folderName in @("Configs", "Save States", "Screenshots", "Launcher")) {
        $sourcePath = Join-Path $RepoRoot $folderName
        if (Test-Path -LiteralPath $sourcePath) {
            Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $backupPath $folderName) -Recurse -Force
            Write-OkLine ("Backed up {0}" -f $folderName)
        }
    }

    Write-OkLine ("Backup created at {0}" -f $backupPath)
}

function Show-Menu {
    try {
        Clear-Host
    }
    catch {
    }

    Write-Banner -Title "SYSTEM UPDATE TOOL" -Subtitle "Maintain RetroArch, cores, and support files"
    Write-Host "  1. Update emulator cores"
    Write-Host "  2. Reinstall RetroArch"
    Write-Host "  3. Update Python dependencies"
    Write-Host "  4. Run a system check"
    Write-Host "  5. Create a backup"
    Write-Host ""
    Write-Host "  0. Exit"
    Write-Host ""
}

switch ($Action) {
    "Cores" { Update-CoreSet; return }
    "RetroArch" { Update-RetroArchInstall; return }
    "Python" { Update-PythonDependencies; return }
    "Check" { Show-SystemCheck; return }
    "Backup" { Create-Backup; return }
}

if ($NonInteractive) {
    Show-SystemCheck
    return
}

do {
    Show-Menu
    $choice = Read-Host "Select option"
    switch ($choice) {
        "1" { Update-CoreSet }
        "2" { Update-RetroArchInstall }
        "3" { Update-PythonDependencies }
        "4" { Show-SystemCheck }
        "5" { Create-Backup }
        "0" { break }
        default { Write-WarnLine "Unknown menu choice." }
    }

    if ($choice -ne "0") {
        Pause-IfInteractive -Prompt "Press Enter to continue" -NonInteractive:$NonInteractive
    }
} while ($true)
