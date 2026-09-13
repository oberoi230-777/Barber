param(
    [ValidateSet("Menu", "Cores", "RetroArch", "Python", "Check", "Backup", "All")]
    [string]$Action = "Menu",
    [switch]$NonInteractive = $false
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot "ps-common.ps1")

function Update-CoreSet {
    param([switch]$ForceUpdate = $false)

    Write-Section "Updating Emulator Cores"
    $summary = Install-RetroArchCores -RootPath $RepoRoot -Force:$ForceUpdate
    Write-InfoLine ("Downloaded: {0}  Skipped: {1}  Failed: {2}" -f $summary.Downloaded, $summary.Skipped, $summary.Failed)
    if ($summary.Failed -gt 0) {
        Write-WarnLine ("Failed cores: {0}" -f ($summary.FailedNames -join ", "))
    }
}

function Update-RetroArchInstall {
    Write-Section "Updating RetroArch"

    # Preserve user data across the reinstall (cores, BIOS, playlists, configs).
    # A full wipe here used to delete downloaded cores - that bug is fixed.
    $retroArchRoot = Join-Path $RepoRoot "Emulators\RetroArch"
    $preserveRoot = Get-TempPath -Name ("retroarch-keep-{0}" -f ([guid]::NewGuid().ToString("N")))
    $preserved = @()
    if (Test-Path -LiteralPath $retroArchRoot) {
        Ensure-Directory -Path $preserveRoot | Out-Null
        foreach ($name in @("cores", "system", "playlists", "config", "cheats", "thumbnails", "saves")) {
            $source = Join-Path $retroArchRoot $name
            if (Test-Path -LiteralPath $source) {
                try {
                    Move-Item -LiteralPath $source -Destination (Join-Path $preserveRoot $name)
                    $preserved += $name
                }
                catch {
                    Write-WarnLine ("Could not preserve {0}: {1}" -f $name, $_.Exception.Message)
                }
            }
        }
        if ($preserved.Count -gt 0) {
            Write-InfoLine ("Preserved across reinstall: {0}" -f ($preserved -join ", "))
        }
    }

    try {
        Install-RetroArchPortable -RootPath $RepoRoot -Force | Out-Null
    }
    finally {
        foreach ($name in $preserved) {
            $staged = Join-Path $preserveRoot $name
            $target = Join-Path $retroArchRoot $name
            if (Test-Path -LiteralPath $staged) {
                # Merge: keep freshly installed files, restore user files on top.
                if ($name -eq "cores") {
                    Ensure-Directory -Path $target | Out-Null
                    Copy-Item -Path (Join-Path $staged "*") -Destination $target -Recurse -Force
                }
                elseif (-not (Test-Path -LiteralPath $target)) {
                    Move-Item -LiteralPath $staged -Destination $target
                }
                else {
                    Copy-Item -Path (Join-Path $staged "*") -Destination $target -Recurse -Force
                }
            }
        }
        Remove-Item -LiteralPath $preserveRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Configure-RetroArch -RootPath $RepoRoot
    # Top up any cores missing from the fresh install.
    Update-CoreSet
}

function Update-PythonDependencies {
    Write-Section "Updating Python Dependencies"
    $pythonInfo = Find-PythonCommand
    if (-not $pythonInfo) {
        Write-WarnLine "Python is not installed, so pygame could not be updated."
        Write-InfoLine "Run SETUP.bat to install Python automatically."
        return
    }

    if (Ensure-PythonPackage -PythonCommand $pythonInfo.Command -PackageName "pygame-ce" -ModuleName "pygame" -FallbackPackages @("pygame")) {
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
    Write-InfoLine ("Python: {0} {1}" -f $audit.PythonCommand, $audit.PythonVersion)
    Write-InfoLine ("pygame installed: {0}" -f $audit.PygameInstalled)
    if ($audit.FreeDiskGB -ge 0) {
        Write-InfoLine ("Free disk space: {0} GB" -f $audit.FreeDiskGB)
    }
    if ($audit.MissingBios.Count -gt 0) {
        Write-WarnLine "Missing BIOS files:"
        foreach ($bios in $audit.MissingBios) {
            Write-InfoLine ("  - {0}" -f $bios)
        }
    }

    $paths = Get-PortablePathInfo -RootPath $RepoRoot
    foreach ($pair in @(
        @{ Label = "LAUNCH.bat"; Path = $paths.LaunchBat },
        @{ Label = "SETUP.bat"; Path = $paths.SetupBat },
        @{ Label = "download-roms.ps1"; Path = $paths.DownloadRomsScript },
        @{ Label = "organize-roms.ps1"; Path = $paths.OrganizeRomsScript },
        @{ Label = "test-controller.ps1"; Path = $paths.TestControllerScript },
        @{ Label = "diagnose.ps1"; Path = $paths.DiagnoseScript }
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

    # BIOS files are small and painful to re-collect: back them up too.
    $biosPath = Join-Path $RepoRoot "Emulators\RetroArch\system"
    if (Test-Path -LiteralPath $biosPath) {
        $biosFiles = @(Get-ChildItem -Path $biosPath -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "_BIOS-INFO.txt" })
        if ($biosFiles.Count -gt 0) {
            $biosBackup = Ensure-Directory -Path (Join-Path $backupPath "BIOS")
            foreach ($biosFile in $biosFiles) {
                Copy-Item -LiteralPath $biosFile.FullName -Destination (Join-Path $biosBackup $biosFile.Name) -Force
            }
            Write-OkLine ("Backed up {0} BIOS file(s)" -f $biosFiles.Count)
        }
    }

    Write-InfoLine "ROMs are NOT included in backups (they can be many GB)."
    Write-InfoLine "Copy the ROMs folder manually if you want to back it up."
    Write-OkLine ("Backup created at {0}" -f $backupPath)
}

function Update-All {
    Update-PythonDependencies
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot "Emulators\RetroArch\retroarch.exe"))) {
        Install-RetroArchPortable -RootPath $RepoRoot | Out-Null
        Configure-RetroArch -RootPath $RepoRoot
    }
    Update-CoreSet
    $audit = Repair-Installation -RootPath $RepoRoot -InstallMissingCores:$false
    Write-InfoLine ("Final state: RetroArch={0} Cores={1} ROMs={2}" -f $audit.RetroArchInstalled, $audit.CoreCount, $audit.RomCount)
}

function Show-Menu {
    Clear-ScreenSafe
    Write-Banner -Title "SYSTEM UPDATE TOOL" -Subtitle "Maintain RetroArch, cores, and support files"
    Write-Host "  1. Update emulator cores"
    Write-Host "  2. Reinstall RetroArch (keeps cores, BIOS, saves)"
    Write-Host "  3. Update Python dependencies"
    Write-Host "  4. Run a system check"
    Write-Host "  5. Create a backup"
    Write-Host "  6. Update everything (recommended)"
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
    "All" { Update-All; return }
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
        "6" { Update-All }
        "0" { break }
        default { Write-WarnLine "Unknown menu choice." }
    }

    if ($choice -ne "0") {
        Pause-IfInteractive -Prompt "Press Enter to continue" -NonInteractive:$NonInteractive
    }
} while ($true)
