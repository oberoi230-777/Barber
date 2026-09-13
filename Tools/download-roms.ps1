param(
    [string]$System = "",
    [switch]$Interactive = $true,
    [switch]$NonInteractive = $false,
    [switch]$Overwrite = $false
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ROMsDir = Join-Path $RepoRoot "ROMs"

. (Join-Path $PSScriptRoot "ps-common.ps1")

function Get-RomSources {
    return [ordered]@{
        "NES" = @(
            @{
                Name  = "NES homebrew collection"
                Url   = "https://archive.org/download/nes-homebrew-collection"
                Files = @("Action53.nes", "Blade_Buster.nes", "Concentration_Room.nes", "Driar.nes", "Lan_Master.nes")
            }
        )
        "SNES" = @(
            @{
                Name  = "SNES homebrew collection"
                Url   = "https://archive.org/download/snes-homebrew-collection"
                Files = @("Uwol.sfc", "Skipp.sfc")
            }
        )
        "Genesis" = @(
            @{
                Name  = "Genesis homebrew collection"
                Url   = "https://archive.org/download/genesis-homebrew-collection"
                Files = @("Demons_of_Asteborg_Demo.bin", "Tanglewood.bin")
            }
        )
        "GBA" = @(
            @{
                Name  = "GBA homebrew collection"
                Url   = "https://archive.org/download/gba-homebrew-collection"
                Files = @("Anguna.gba", "Powder.gba", "Tetris.gba")
            }
        )
        "Atari2600" = @(
            @{
                Name  = "Atari 2600 public domain archive"
                Url   = "https://archive.org/download/Atari_2600_TOSEC_2012_04_23"
                Files = @()
                Note  = "No direct file list is bundled for this source. Browse the page manually if you want more titles."
            }
        )
    }
}

function Show-Menu {
    $sources = Get-RomSources
    try {
        Clear-Host
    }
    catch {
    }

    Write-Banner -Title "ROM DOWNLOAD TOOL" -Subtitle "Legal homebrew and public-domain sources only"
    $index = 1
    foreach ($systemName in $sources.Keys) {
        Write-Host ("  {0}. {1}" -f $index, $systemName)
        $index++
    }
    Write-Host ("  {0}. Download a sample pack for all systems" -f $index)
    Write-Host ("  {0}. Show legal source guidance" -f ($index + 1))
    Write-Host ""
    Write-Host "  0. Exit"
    Write-Host ""
}

function Download-SystemRoms {
    param(
        [Parameter(Mandatory = $true)][string]$SystemName,
        [switch]$OverwriteExisting
    )

    $sources = Get-RomSources
    if (-not $sources.Contains($SystemName)) {
        Write-WarnLine ("No configured download sources exist for {0}." -f $SystemName)
        return
    }

    $systemDir = Ensure-Directory -Path (Join-Path $ROMsDir $SystemName)
    $downloaded = 0
    $skipped = 0
    $failed = 0

    Write-Section ("Downloading {0}" -f $SystemName)

    foreach ($source in $sources[$SystemName]) {
        Write-InfoLine ("Source: {0}" -f $source.Name)

        if ($source.Files.Count -eq 0) {
            Write-InfoLine ("Browse manually: {0}" -f $source.Url)
            Write-WarnLine $source.Note
            continue
        }

        foreach ($fileName in $source.Files) {
            $targetPath = Join-Path $systemDir $fileName
            if ((-not $OverwriteExisting) -and (Test-Path -LiteralPath $targetPath)) {
                Write-OkLine ("Skipping existing file {0}" -f $fileName)
                $skipped++
                continue
            }

            $fileUrl = "{0}/{1}" -f $source.Url.TrimEnd("/"), $fileName
            try {
                Write-InfoLine ("Downloading {0}" -f $fileName)
                Invoke-DownloadFile -Uri $fileUrl -OutFile $targetPath -TimeoutSec 120
                Write-OkLine ("Saved {0}" -f $targetPath)
                $downloaded++
            }
            catch {
                Write-WarnLine ("Could not download {0}: {1}" -f $fileName, $_.Exception.Message)
                Remove-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
                $failed++
            }
        }
    }

    Write-InfoLine ("Downloaded: {0}  Skipped: {1}  Failed: {2}" -f $downloaded, $skipped, $failed)
}

function Download-SamplePack {
    foreach ($systemName in @("NES", "SNES", "Genesis", "GBA")) {
        Download-SystemRoms -SystemName $systemName -OverwriteExisting:$Overwrite
    }
}

function Show-LegalGuide {
    Write-Section "Legal ROM Guidance"
    Write-Host "Allowed sources:"
    Write-Host "  - Homebrew games"
    Write-Host "  - Public-domain releases"
    Write-Host "  - Dumps made from media you own"
    Write-Host ""
    Write-Host "Recommended places to browse:"
    Write-Host "  - https://archive.org"
    Write-Host "  - https://itch.io"
    Write-Host "  - https://www.romhacking.net"
    Write-Host "  - https://pdroms.de"
    Write-Host ""
    Write-Host "Do not download commercial ROMs you do not have rights to."
    Write-Host ""
    Pause-IfInteractive -Prompt "Press Enter to return to the menu" -NonInteractive:$NonInteractive
}

if (-not $Interactive) {
    if ([string]::IsNullOrWhiteSpace($System)) {
        Write-WarnLine "Provide -System <name> when running non-interactively."
    }
    else {
        Download-SystemRoms -SystemName $System -OverwriteExisting:$Overwrite
    }
    return
}

do {
    Show-Menu
    $choice = Read-Host "Select option"
    switch ($choice) {
        "1" { Download-SystemRoms -SystemName "NES" -OverwriteExisting:$Overwrite }
        "2" { Download-SystemRoms -SystemName "SNES" -OverwriteExisting:$Overwrite }
        "3" { Download-SystemRoms -SystemName "Genesis" -OverwriteExisting:$Overwrite }
        "4" { Download-SystemRoms -SystemName "GBA" -OverwriteExisting:$Overwrite }
        "5" { Download-SystemRoms -SystemName "Atari2600" -OverwriteExisting:$Overwrite }
        "6" { Download-SamplePack }
        "7" { Show-LegalGuide }
        "0" { break }
        default { Write-WarnLine "Unknown menu choice." }
    }

    if ($choice -ne "0" -and $choice -ne "7") {
        Pause-IfInteractive -Prompt "Press Enter to continue" -NonInteractive:$NonInteractive
    }
} while ($true)
