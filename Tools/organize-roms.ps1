param(
    [string]$SourceFolder = "",
    [switch]$MoveFiles = $false,
    [switch]$NonInteractive = $false
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ROMsDir = Join-Path $RepoRoot "ROMs"

. (Join-Path $PSScriptRoot "ps-common.ps1")

$ExtensionMap = [ordered]@{
    "NES"          = @(".nes", ".unf", ".unif")
    "SNES"         = @(".smc", ".sfc", ".fig", ".swc")
    "N64"          = @(".n64", ".z64", ".v64")
    "GameBoy"      = @(".gb", ".gbc")
    "GBA"          = @(".gba")
    "Genesis"      = @(".md", ".gen", ".smd")
    "MasterSystem" = @(".sms")
    "GameGear"     = @(".gg")
    "PlayStation"  = @(".cue", ".chd", ".pbp")
    "Arcade"       = @(".zip")
    "Atari2600"    = @(".a26")
    "Dreamcast"    = @(".cdi", ".gdi")
    "PSP"          = @(".iso", ".cso")
}

function Get-SystemForFile {
    param([Parameter(Mandatory = $true)][IO.FileInfo]$File)

    $extension = $File.Extension.ToLowerInvariant()
    if ($extension -eq ".bin") {
        $cuePath = [IO.Path]::ChangeExtension($File.FullName, ".cue")
        if (Test-Path -LiteralPath $cuePath) {
            return "PlayStation"
        }

        return "Genesis"
    }

    foreach ($systemName in $ExtensionMap.Keys) {
        if ($ExtensionMap[$systemName] -contains $extension) {
            return $systemName
        }
    }

    return $null
}

function Show-Statistics {
    Write-Section "Current ROM Library"

    $totalGames = 0
    $totalSizeBytes = 0

    foreach ($systemName in $ExtensionMap.Keys) {
        $systemDir = Join-Path $ROMsDir $systemName
        if (-not (Test-Path -LiteralPath $systemDir)) {
            continue
        }

        $files = Get-ChildItem -Path $systemDir -File -ErrorAction SilentlyContinue
        if (-not $files) {
            continue
        }

        $count = ($files | Measure-Object).Count
        $sizeBytes = ($files | Measure-Object -Property Length -Sum).Sum
        $sizeMb = [Math]::Round(($sizeBytes / 1MB), 2)

        Write-InfoLine ("{0}: {1} file(s), {2} MB" -f $systemName, $count, $sizeMb)
        $totalGames += $count
        $totalSizeBytes += $sizeBytes
    }

    $totalSizeGb = [Math]::Round(($totalSizeBytes / 1GB), 2)
    Write-Host ""
    Write-OkLine ("Total ROMs: {0}" -f $totalGames)
    Write-OkLine ("Total size: {0} GB" -f $totalSizeGb)
}

function Organize-Roms {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [switch]$MoveMode
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw ("Source folder does not exist: {0}" -f $SourcePath)
    }

    Ensure-Directory -Path $ROMsDir | Out-Null
    $resolvedSource = (Resolve-Path -LiteralPath $SourcePath).Path
    $resolvedLibrary = (Resolve-Path -LiteralPath $ROMsDir).Path

    if ($resolvedSource.StartsWith($resolvedLibrary, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Choose a source folder outside the ROM library to avoid copying files onto themselves."
    }

    $files = Get-ChildItem -Path $resolvedSource -File -Recurse -ErrorAction SilentlyContinue
    $copied = 0
    $moved = 0
    $skipped = 0

    Write-Section ("Organizing files from {0}" -f $resolvedSource)

    foreach ($file in $files) {
        $systemName = Get-SystemForFile -File $file
        if (-not $systemName) {
            Write-WarnLine ("Unknown extension for {0}" -f $file.Name)
            $skipped++
            continue
        }

        $destinationDir = Ensure-Directory -Path (Join-Path $ROMsDir $systemName)
        $destinationPath = Join-Path $destinationDir $file.Name

        if (Test-Path -LiteralPath $destinationPath) {
            Write-WarnLine ("Skipping existing file {0}" -f $file.Name)
            $skipped++
            continue
        }

        if ($MoveMode) {
            Move-Item -LiteralPath $file.FullName -Destination $destinationPath
            Write-OkLine ("Moved {0} to {1}" -f $file.Name, $systemName)
            $moved++
        }
        else {
            Copy-Item -LiteralPath $file.FullName -Destination $destinationPath
            Write-OkLine ("Copied {0} to {1}" -f $file.Name, $systemName)
            $copied++
        }
    }

    Write-Host ""
    Write-InfoLine ("Copied: {0}  Moved: {1}  Skipped: {2}" -f $copied, $moved, $skipped)
}

try {
    Clear-Host
}
catch {
}

Write-Banner -Title "ROM ORGANIZATION TOOL" -Subtitle "Sort ROM files into the right system folders"

if ([string]::IsNullOrWhiteSpace($SourceFolder)) {
    Show-Statistics
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\organize-roms.ps1 -SourceFolder C:\Downloads\ROMs"
    Write-Host "  .\organize-roms.ps1 -SourceFolder C:\Drops\NewGames -MoveFiles"
    Write-Host ""

    if (-not (Test-InteractiveRun -NonInteractive:$NonInteractive)) {
        Write-WarnLine "Provide -SourceFolder when running non-interactively."
        return
    }

    $SourceFolder = Read-Host "Enter the folder that contains ROM files"
    if ([string]::IsNullOrWhiteSpace($SourceFolder)) {
        return
    }
}

Organize-Roms -SourcePath $SourceFolder -MoveMode:$MoveFiles
Show-Statistics
Pause-IfInteractive -Prompt "Press Enter to exit" -NonInteractive:$NonInteractive
