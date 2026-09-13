param(
    [string]$SourceFolder = "",
    [switch]$MoveFiles = $false,
    [switch]$NonInteractive = $false,
    [switch]$DryRun = $false,
    [switch]$StatsOnly = $false,
    [ValidateSet("Arcade", "NeoGeo")]
    [string]$DefaultZipSystem = "Arcade"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ROMsDir = Join-Path $RepoRoot "ROMs"
$BiosDir = Join-Path $RepoRoot "Emulators\RetroArch\system"

. (Join-Path $PSScriptRoot "ps-common.ps1")

# Systems.json is the single source of truth for extensions.
function Get-ExtensionMap {
    $map = [ordered]@{}
    $systems = Get-SystemsConfig -RootPath $RepoRoot
    if ($systems.Count -eq 0) {
        Write-WarnLine "systems.json unavailable, using built-in extension map."
        $systems = @(
            [pscustomobject]@{ folder = "NES"; extensions = @("nes", "unf", "unif", "zip", "7z") },
            [pscustomobject]@{ folder = "SNES"; extensions = @("smc", "sfc", "fig", "swc", "bs", "zip", "7z") },
            [pscustomobject]@{ folder = "N64"; extensions = @("n64", "z64", "v64", "zip", "7z") },
            [pscustomobject]@{ folder = "GameBoy"; extensions = @("gb", "gbc", "zip", "7z") },
            [pscustomobject]@{ folder = "GBA"; extensions = @("gba", "zip", "7z") },
            [pscustomobject]@{ folder = "NDS"; extensions = @("nds", "zip", "7z") },
            [pscustomobject]@{ folder = "Genesis"; extensions = @("md", "bin", "gen", "smd", "32x", "zip", "7z") },
            [pscustomobject]@{ folder = "MasterSystem"; extensions = @("sms", "sg", "zip", "7z") },
            [pscustomobject]@{ folder = "GameGear"; extensions = @("gg", "zip", "7z") },
            [pscustomobject]@{ folder = "PlayStation"; extensions = @("cue", "m3u", "chd", "pbp", "iso", "bin") },
            [pscustomobject]@{ folder = "Arcade"; extensions = @("zip", "7z") },
            [pscustomobject]@{ folder = "NeoGeo"; extensions = @("zip", "7z") },
            [pscustomobject]@{ folder = "Atari2600"; extensions = @("a26", "bin", "zip", "7z") },
            [pscustomobject]@{ folder = "Dreamcast"; extensions = @("cdi", "gdi", "chd", "m3u") },
            [pscustomobject]@{ folder = "PSP"; extensions = @("iso", "cso", "pbp", "chd") }
        )
    }
    foreach ($system in $systems) {
        $exts = @()
        $rawExts = @(Get-ObjectProperty -InputObject $system -Name "extensions" -Default @())
        foreach ($ext in $rawExts) {
            if ([string]::IsNullOrWhiteSpace([string]$ext)) { continue }
            $normalized = ("." + [string]$ext).ToLowerInvariant().Replace("..", ".")
            $exts += $normalized
        }
        $folderName = [string](Get-ObjectProperty -InputObject $system -Name "folder" -Default "")
        if (-not $folderName) { continue }
        $map[$folderName] = $exts
    }
    return $map
}

function Get-SystemForFile {
    param(
        [Parameter(Mandatory = $true)][IO.FileInfo]$File,
        [Parameter(Mandatory = $true)]$ExtensionMap
    )

    $extension = $File.Extension.ToLowerInvariant()
    $nameLower = $File.Name.ToLowerInvariant()

    # Neo Geo BIOS belongs in the RetroArch system folder, not ROMs.
    if ($nameLower -eq "neogeo.zip") {
        return "__BIOS__"
    }

    # ZIPs are ambiguous (MAME vs Neo Geo vs zipped cartridge ROMs).
    # Default is configurable; run once per source folder for mixed sets.
    if ($extension -eq ".zip" -or $extension -eq ".7z") {
        # Peeked decision: multi-disc PS1/Dreamcast rips are rarely zipped;
        # cartridge ROMs usually are. Without unzipping we route by flag.
        return $DefaultZipSystem
    }

    if ($extension -eq ".bin") {
        $directory = $File.DirectoryName
        $stem = [IO.Path]::GetFileNameWithoutExtension($File.Name)
        if (Test-Path -LiteralPath (Join-Path $directory ($stem + ".cue"))) {
            return "PlayStation"
        }
        if (Test-Path -LiteralPath (Join-Path $directory ($stem + ".gdi"))) {
            return "Dreamcast"
        }
        # Orphan .bin: Genesis ROMs and Atari ROMs both use it; Genesis wins
        # unless the file is tiny (Atari 2600 ROMs are <= 64 KB).
        if ($File.Length -le 64KB -and $ExtensionMap.Contains("Atari2600")) {
            return "Atari2600"
        }
        return "Genesis"
    }

    if ($extension -eq ".iso") {
        # PSP and PS1 both use .iso; folder hint wins when present.
        if ($File.DirectoryName -match "psp") { return "PSP" }
        return "PSP"
    }

    foreach ($systemName in $ExtensionMap.Keys) {
        if ($systemName -eq "NeoGeo") { continue }  # handled via DefaultZipSystem
        if ($ExtensionMap[$systemName] -contains $extension) {
            return $systemName
        }
    }

    return $null
}

function Get-CompanionFiles {
    param([Parameter(Mandatory = $true)][IO.FileInfo]$File)

    # Disc cues/gdi/m3u files need their track files copied alongside them.
    $companions = @()
    $extension = $File.Extension.ToLowerInvariant()
    if ($extension -notin @(".cue", ".gdi", ".m3u")) {
        return $companions
    }
    $directory = $File.DirectoryName
    $stem = [IO.Path]::GetFileNameWithoutExtension($File.Name)
    foreach ($candidate in Get-ChildItem -LiteralPath $directory -File -ErrorAction SilentlyContinue) {
        if ($candidate.FullName -eq $File.FullName) { continue }
        $candidateStem = [IO.Path]::GetFileNameWithoutExtension($candidate.Name)
        $candidateExt = $candidate.Extension.ToLowerInvariant()
        if ($extension -eq ".gdi") {
            # GDI track files (track01.bin, ...) live next to the .gdi.
            if ($candidateExt -in @(".bin", ".raw")) {
                $companions += $candidate
            }
        }
        elseif ($candidateStem -eq $stem -and $candidateExt -in @(".bin", ".img", ".wav", ".mp3", ".ogg")) {
            $companions += $candidate
        }
    }
    return $companions
}

function Show-Statistics {
    param([Parameter(Mandatory = $true)]$ExtensionMap)

    Write-Section "Current ROM Library"

    $totalGames = 0
    $totalSizeBytes = [long]0

    $folders = @($ExtensionMap.Keys)
    if (Test-Path -LiteralPath $ROMsDir) {
        foreach ($dir in Get-ChildItem -Path $ROMsDir -Directory -ErrorAction SilentlyContinue) {
            if ($folders -notcontains $dir.Name) { $folders += $dir.Name }
        }
    }

    foreach ($systemName in $folders) {
        $systemDir = Join-Path $ROMsDir $systemName
        if (-not (Test-Path -LiteralPath $systemDir)) { continue }

        $files = @(Get-ChildItem -Path $systemDir -File -Recurse -ErrorAction SilentlyContinue)
        if ($files.Count -eq 0) { continue }

        $sizeBytes = [long]($files | Measure-Object -Property Length -Sum).Sum
        $sizeMb = [Math]::Round(($sizeBytes / 1MB), 2)

        Write-InfoLine ("{0}: {1} file(s), {2} MB" -f $systemName, $files.Count, $sizeMb)
        $totalGames += $files.Count
        $totalSizeBytes += $sizeBytes
    }

    $totalSizeGb = [Math]::Round(($totalSizeBytes / 1GB), 2)
    Write-Host ""
    Write-OkLine ("Total ROMs: {0}" -f $totalGames)
    Write-OkLine ("Total size: {0} GB" -f $totalSizeGb)
}

function Copy-RomFile {
    param(
        [Parameter(Mandatory = $true)][IO.FileInfo]$File,
        [Parameter(Mandatory = $true)][string]$DestinationDir,
        [switch]$MoveMode,
        [switch]$Preview
    )

    $destinationPath = Join-Path $DestinationDir $File.Name
    if (Test-Path -LiteralPath $destinationPath) {
        $existing = Get-Item -LiteralPath $destinationPath
        if ($existing.Length -eq $File.Length) {
            return "skipped"
        }
        # Same name, different size: keep both with a numeric suffix.
        $base = [IO.Path]::GetFileNameWithoutExtension($File.Name)
        $ext = $File.Extension
        $counter = 2
        do {
            $destinationPath = Join-Path $DestinationDir ("{0} ({1}){2}" -f $base, $counter, $ext)
            $counter++
        } while (Test-Path -LiteralPath $destinationPath)
    }

    if ($Preview) {
        return "preview"
    }

    Ensure-Directory -Path $DestinationDir | Out-Null
    if ($MoveMode) {
        Move-Item -LiteralPath $File.FullName -Destination $destinationPath
        return "moved"
    }
    Copy-Item -LiteralPath $File.FullName -Destination $destinationPath
    return "copied"
}

function Organize-Roms {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)]$ExtensionMap,
        [switch]$MoveMode,
        [switch]$Preview
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

    $files = @(Get-ChildItem -Path $resolvedSource -File -Recurse -ErrorAction SilentlyContinue)
    $copied = 0
    $moved = 0
    $skipped = 0
    $unknown = 0

    if ($Preview) {
        Write-Section ("DRY RUN - organizing files from {0}" -f $resolvedSource)
    }
    else {
        Write-Section ("Organizing files from {0}" -f $resolvedSource)
    }

    $handled = @{}
    # Process disc descriptors first so companions travel with them.
    $ordered = @($files | Sort-Object {
        $priority = @(".cue", ".gdi", ".m3u").IndexOf($_.Extension.ToLowerInvariant())
        if ($priority -lt 0) { 99 } else { $priority }
    })

    foreach ($file in $ordered) {
        if ($handled.ContainsKey($file.FullName)) { continue }
        $handled[$file.FullName] = $true

        $systemName = Get-SystemForFile -File $file -ExtensionMap $ExtensionMap
        if (-not $systemName) {
            Write-WarnLine ("Unknown extension for {0}" -f $file.Name)
            $unknown++
            continue
        }

        if ($systemName -eq "__BIOS__") {
            $destinationDir = Ensure-Directory -Path $BiosDir
            $label = "BIOS folder"
        }
        else {
            $destinationDir = Join-Path $ROMsDir $systemName
            $label = $systemName
        }

        $queue = @($file) + @(Get-CompanionFiles -File $file)
        foreach ($item in $queue) {
            $handled[$item.FullName] = $true
            $result = Copy-RomFile -File $item -DestinationDir $destinationDir -MoveMode:$MoveMode -Preview:$Preview
            switch ($result) {
                "copied"  { Write-OkLine ("Copied {0} to {1}" -f $item.Name, $label); $copied++ }
                "moved"   { Write-OkLine ("Moved {0} to {1}" -f $item.Name, $label); $moved++ }
                "skipped" { Write-WarnLine ("Skipping existing file {0}" -f $item.Name); $skipped++ }
                "preview" { Write-InfoLine ("Would file {0} under {1}" -f $item.Name, $label); $copied++ }
            }
        }
    }

    Write-Host ""
    if ($Preview) {
        Write-InfoLine ("Would file: {0}  Skipped: {1}  Unknown: {2}" -f $copied, $skipped, $unknown)
    }
    else {
        Write-InfoLine ("Copied: {0}  Moved: {1}  Skipped: {2}  Unknown: {3}" -f $copied, $moved, $skipped, $unknown)
    }
}

Clear-ScreenSafe
Write-Banner -Title "ROM ORGANIZATION TOOL" -Subtitle "Sort ROM files into the right system folders"

$extensionMap = Get-ExtensionMap

if ($StatsOnly -or [string]::IsNullOrWhiteSpace($SourceFolder)) {
    Show-Statistics -ExtensionMap $extensionMap
    if ($StatsOnly) { return }

    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\organize-roms.ps1 -SourceFolder C:\Downloads\ROMs"
    Write-Host "  .\organize-roms.ps1 -SourceFolder C:\Drops\NewGames -MoveFiles"
    Write-Host "  .\organize-roms.ps1 -SourceFolder C:\NeoGeo -DefaultZipSystem NeoGeo"
    Write-Host "  .\organize-roms.ps1 -SourceFolder C:\ROMs -DryRun   (preview only)"
    Write-Host ""

    if (-not (Test-InteractiveRun -NonInteractive:$NonInteractive)) {
        Write-WarnLine "Provide -SourceFolder when running non-interactively."
        return
    }

    $SourceFolder = Read-Host "Enter the folder that contains ROM files (blank to exit)"
    if ([string]::IsNullOrWhiteSpace($SourceFolder)) {
        return
    }
}

Organize-Roms -SourcePath $SourceFolder -ExtensionMap $extensionMap -MoveMode:$MoveFiles -Preview:$DryRun
if (-not $DryRun) {
    Show-Statistics -ExtensionMap $extensionMap
}
Pause-IfInteractive -Prompt "Press Enter to exit" -NonInteractive:$NonInteractive
