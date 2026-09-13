param(
    [string]$System = "",
    [switch]$NonInteractive = $false,
    [switch]$Overwrite = $false,
    [switch]$ListOnly = $false,
    [int]$MaxFiles = 5
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ROMsDir = Join-Path $RepoRoot "ROMs"

. (Join-Path $PSScriptRoot "ps-common.ps1")

# Curated legal sources. Items marked Verified were confirmed to contain the
# listed files. For every source the script ALSO queries the archive.org
# metadata API at runtime, so downloads keep working even if file names change.
function Get-RomSources {
    return [ordered]@{
        "NES" = @(
            @{
                Name       = "Eyra the Crow Maiden (NES demo, open source)"
                Item       = "eyra-nesdemo"
                Files      = @("eyrademo.nes")
                Extensions = @(".nes")
            },
            @{
                Name       = "The Arm Wrestling Classic (NES homebrew)"
                Item       = "the-arm-wrestling-classic"
                Files      = @("The Arm Wrestling Classic.nes")
                Extensions = @(".nes")
            }
        )
        "SNES" = @(
            @{
                Name       = "Dottie Dreads Nough (SNES homebrew)"
                Item       = "dottie-dreads-nough-snesforever.com.br"
                Files      = @("Dottie Dreads Nough - [snesforever.com.br].sfc")
                Extensions = @(".sfc", ".smc")
            }
        )
        "GameBoy" = @(
            @{
                Name       = "Damuel (Game Boy, public domain)"
                Item       = "damuel-project"
                Files      = @("Damuel.gb")
                Extensions = @(".gb", ".gbc")
            }
        )
        "GBA" = @(
            @{
                Name           = "GBA homebrew (auto-discovered)"
                Item           = ""
                Files          = @()
                Extensions     = @(".gba")
                SearchKeywords = "(gba OR ""game boy advance"") AND homebrew"
            }
        )
        "Genesis" = @(
            @{
                Name           = "Genesis homebrew (auto-discovered)"
                Item           = ""
                Files          = @()
                Extensions     = @(".md", ".gen", ".bin", ".smd")
                SearchKeywords = "(genesis OR ""mega drive"") AND homebrew"
            }
        )
        "Atari2600" = @(
            @{
                Name           = "Atari 2600 homebrew (auto-discovered)"
                Item           = ""
                Files          = @()
                Extensions     = @(".a26", ".bin")
                SearchKeywords = """atari 2600"" AND homebrew"
            }
        )
    }
}

function Get-ArchiveItemFiles {
    param(
        [Parameter(Mandatory = $true)][string]$ItemId,
        [string[]]$Extensions = @()
    )

    $found = @()
    try {
        Set-DownloadSecurityProtocol
        $command = Get-Command Invoke-WebRequest -ErrorAction Stop
        $params = @{ Uri = "https://archive.org/metadata/{0}" -f $ItemId; ErrorAction = "Stop" }
        if ($command.Parameters.ContainsKey("TimeoutSec")) { $params.TimeoutSec = 30 }
        if ($command.Parameters.ContainsKey("UseBasicParsing")) { $params.UseBasicParsing = $true }
        $previousProgress = $global:ProgressPreference
        try {
            $global:ProgressPreference = "SilentlyContinue"
            $response = Invoke-WebRequest @params
        }
        finally {
            $global:ProgressPreference = $previousProgress
        }
        $metadata = $response.Content | ConvertFrom-Json
        $metaFiles = @(Get-ObjectProperty -InputObject $metadata -Name "files" -Default @())
        foreach ($file in $metaFiles) {
            $sourceKind = [string](Get-ObjectProperty -InputObject $file -Name "source" -Default "")
            if ($sourceKind -ne "original") { continue }
            $name = [string](Get-ObjectProperty -InputObject $file -Name "name" -Default "")
            if (-not $name) { continue }
            $lower = $name.ToLowerInvariant()
            # Skip metadata, torrents, images, and huge disc images.
            if ($lower -match "_(files\.xml|meta\.(xml|sqlite))$" -or $lower -match "\.(torrent|png|jpe?g|gif|txt|pdf|xml)$") { continue }
            $sizeValue = Get-ObjectProperty -InputObject $file -Name "size" -Default 0
            if ($sizeValue -and [long]$sizeValue -gt 64MB) { continue }
            if ($Extensions.Count -gt 0) {
                $ext = [IO.Path]::GetExtension($lower)
                if ($Extensions -notcontains $ext) { continue }
            }
            $found += $name
        }
    }
    catch {
        Write-LogLine -Message ("Metadata lookup failed for {0}: {1}" -f $ItemId, $_.Exception.Message)
    }
    return $found
}

function Find-ArchiveRomCandidates {
    param(
        [Parameter(Mandatory = $true)][string]$Keywords,
        [string[]]$Extensions = @(),
        [int]$MaxItems = 5,
        [int]$MaxFiles = 3
    )

    # Live archive.org search fallback: find open-source items whose file list
    # actually contains ROM files with the wanted extensions.
    $results = @()
    try {
        Set-DownloadSecurityProtocol
        $query = "collection:open_source_software AND mediatype:software AND ({0})" -f $Keywords
        $url = "https://archive.org/advancedsearch.php?q={0}&fl[]=identifier&rows=15&output=json" -f [uri]::EscapeDataString($query)
        $command = Get-Command Invoke-WebRequest -ErrorAction Stop
        $params = @{ Uri = $url; ErrorAction = "Stop" }
        if ($command.Parameters.ContainsKey("TimeoutSec")) { $params.TimeoutSec = 30 }
        if ($command.Parameters.ContainsKey("UseBasicParsing")) { $params.UseBasicParsing = $true }
        $previousProgress = $global:ProgressPreference
        try {
            $global:ProgressPreference = "SilentlyContinue"
            $response = Invoke-WebRequest @params
        }
        finally {
            $global:ProgressPreference = $previousProgress
        }
        $search = $response.Content | ConvertFrom-Json
        $responseNode = Get-ObjectProperty -InputObject $search -Name "response" -Default $null
        $docs = @(Get-ObjectProperty -InputObject $responseNode -Name "docs" -Default @())
        $probed = 0
        foreach ($doc in $docs) {
            if ($probed -ge $MaxItems) { break }
            $probed++
            $identifier = [string](Get-ObjectProperty -InputObject $doc -Name "identifier" -Default "")
            if (-not $identifier) { continue }
            $files = Get-ArchiveItemFiles -ItemId $identifier -Extensions $Extensions
            if ($files.Count -gt 0) {
                $results += [pscustomobject]@{
                    Item  = $identifier
                    Files = @($files | Select-Object -First $MaxFiles)
                }
                break
            }
        }
    }
    catch {
        Write-LogLine -Message ("Archive.org search failed: {0}" -f $_.Exception.Message)
    }
    return $results
}

function Show-Menu {
    param($Sources)

    Clear-ScreenSafe
    Write-Banner -Title "ROM DOWNLOAD TOOL" -Subtitle "Legal homebrew and public-domain sources only"
    $systems = @($Sources.Keys)
    for ($i = 0; $i -lt $systems.Count; $i++) {
        $romDir = Join-Path $ROMsDir $systems[$i]
        $count = 0
        if (Test-Path -LiteralPath $romDir) {
            $count = (Get-ChildItem -Path $romDir -File -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
        }
        Write-Host ("  {0}. {1} ({2} ROMs installed)" -f ($i + 1), $systems[$i], $count)
    }
    Write-Host ("  {0}. Download a sample pack for all systems" -f ($systems.Count + 1))
    Write-Host ("  {0}. Show legal source guidance" -f ($systems.Count + 2))
    Write-Host ""
    Write-Host "  0. Exit"
    Write-Host ""
    return $systems
}

function Download-SystemRoms {
    param(
        [Parameter(Mandatory = $true)][string]$SystemName,
        [switch]$OverwriteExisting,
        [switch]$PreviewOnly,
        [int]$MaxDownloads = 5
    )

    $sources = Get-RomSources
    if (-not $sources.Contains($SystemName)) {
        Write-WarnLine ("No configured download sources exist for {0}." -f $SystemName)
        Write-InfoLine "Browse https://archive.org or https://itch.io for legal homebrew titles."
        return
    }

    $systemDir = Ensure-Directory -Path (Join-Path $ROMsDir $SystemName)
    $downloaded = 0
    $skipped = 0
    $failed = 0

    Write-Section ("Downloading {0}" -f $SystemName)

    foreach ($source in $sources[$SystemName]) {
        Write-InfoLine ("Source: {0}" -f $source.Name)

        # Merge curated file names with live auto-discovery.
        $wantedFiles = New-Object System.Collections.Generic.List[string]
        foreach ($fixed in @($source.Files)) {
            if ($fixed -and -not $wantedFiles.Contains($fixed)) { $wantedFiles.Add($fixed) }
        }
        $sourceItem = [string]$source.Item
        if ($sourceItem) {
            $discovered = Get-ArchiveItemFiles -ItemId $sourceItem -Extensions @($source.Extensions)
            foreach ($auto in $discovered) {
                if ($wantedFiles.Count -ge $MaxDownloads) { break }
                if (-not $wantedFiles.Contains($auto)) { $wantedFiles.Add($auto) }
            }
        }

        # Live search fallback for systems without a curated item.
        if ($wantedFiles.Count -eq 0 -and $source.SearchKeywords) {
            Write-InfoLine "Searching archive.org for matching homebrew titles..."
            $candidates = Find-ArchiveRomCandidates -Keywords $source.SearchKeywords -Extensions @($source.Extensions) -MaxFiles $MaxDownloads
            foreach ($candidate in $candidates) {
                $sourceItem = $candidate.Item
                Write-InfoLine ("Found: https://archive.org/details/{0}" -f $sourceItem)
                foreach ($auto in $candidate.Files) {
                    if ($wantedFiles.Count -ge $MaxDownloads) { break }
                    if (-not $wantedFiles.Contains($auto)) { $wantedFiles.Add($auto) }
                }
            }
        }

        if ($wantedFiles.Count -eq 0) {
            if ($sourceItem) {
                Write-WarnLine ("No downloadable ROM files found in '{0}'." -f $sourceItem)
                Write-InfoLine ("Browse manually: https://archive.org/details/{0}" -f $sourceItem)
            }
            else {
                Write-WarnLine "No downloadable ROM files found via live search."
                Write-InfoLine "Browse manually: https://archive.org (search '<system> homebrew')"
            }
            continue
        }

        foreach ($fileName in $wantedFiles) {
            $targetPath = Join-Path $systemDir $fileName
            if ((-not $OverwriteExisting) -and (Test-Path -LiteralPath $targetPath)) {
                Write-OkLine ("Skipping existing file {0}" -f $fileName)
                $skipped++
                continue
            }

            $encodedName = [uri]::EscapeDataString($fileName).Replace("%2F", "/")
            $fileUrl = "https://archive.org/download/{0}/{1}" -f $sourceItem, $encodedName

            if ($PreviewOnly) {
                Write-InfoLine ("Would download: {0}" -f $fileUrl)
                continue
            }

            try {
                Write-InfoLine ("Downloading {0}" -f $fileName)
                Invoke-DownloadFile -Uri $fileUrl -OutFile $targetPath -TimeoutSec 180 -Retries 3
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
    param(
        [switch]$OverwriteExisting,
        [switch]$PreviewOnly
    )

    foreach ($systemName in @("NES", "SNES", "GameBoy", "GBA", "Genesis", "Atari2600")) {
        Download-SystemRoms -SystemName $systemName -OverwriteExisting:$OverwriteExisting -PreviewOnly:$PreviewOnly -MaxDownloads $MaxFiles
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
    Write-Host "  - https://archive.org (search '<system> homebrew')"
    Write-Host "  - https://itch.io (filter by console + free)"
    Write-Host "  - https://www.romhacking.net"
    Write-Host "  - https://pdroms.de"
    Write-Host ""
    Write-Host "Do not download commercial ROMs you do not have rights to."
    Write-Host ""
    Pause-IfInteractive -Prompt "Press Enter to return to the menu" -NonInteractive:$NonInteractive
}

# --- Entry -----------------------------------------------------------------

if ($System -ne "") {
    if ($System.ToLowerInvariant() -eq "all") {
        Download-SamplePack -OverwriteExisting:$Overwrite -PreviewOnly:$ListOnly
    }
    else {
        # Accept case-insensitive system names (nes, snes, gameboy, ...).
        $sources = Get-RomSources
        $matched = @($sources.Keys | Where-Object { $_.ToLowerInvariant() -eq $System.ToLowerInvariant() })
        if ($matched.Count -gt 0) {
            Download-SystemRoms -SystemName $matched[0] -OverwriteExisting:$Overwrite -PreviewOnly:$ListOnly -MaxDownloads $MaxFiles
        }
        else {
            Write-WarnLine ("Unknown system '{0}'. Available: {1}, All" -f $System, (($sources.Keys) -join ", "))
            exit 1
        }
    }
    return
}

if ($NonInteractive) {
    Write-WarnLine "Provide -System <name|All> when running non-interactively."
    Write-InfoLine ("Available systems: {0}" -f ((Get-RomSources).Keys -join ", "))
    return
}

do {
    $systems = Show-Menu -Sources (Get-RomSources)
    $choice = Read-Host "Select option"
    if ($choice -eq "0") { break }

    $asNumber = 0
    if (-not [int]::TryParse($choice, [ref]$asNumber)) {
        Write-WarnLine "Unknown menu choice."
        continue
    }

    if ($asNumber -ge 1 -and $asNumber -le $systems.Count) {
        Download-SystemRoms -SystemName $systems[$asNumber - 1] -OverwriteExisting:$Overwrite -PreviewOnly:$ListOnly -MaxDownloads $MaxFiles
        Pause-IfInteractive -Prompt "Press Enter to continue" -NonInteractive:$NonInteractive
    }
    elseif ($asNumber -eq ($systems.Count + 1)) {
        Download-SamplePack -OverwriteExisting:$Overwrite -PreviewOnly:$ListOnly
        Pause-IfInteractive -Prompt "Press Enter to continue" -NonInteractive:$NonInteractive
    }
    elseif ($asNumber -eq ($systems.Count + 2)) {
        Show-LegalGuide
    }
    else {
        Write-WarnLine "Unknown menu choice."
    }
} while ($true)
