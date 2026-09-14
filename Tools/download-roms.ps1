param(
    [string]$System = "",
    [switch]$NonInteractive = $false,
    [switch]$Overwrite = $false,
    [switch]$ListOnly = $false,
    [int]$MaxFiles = 8,
    [switch]$RefreshCatalog = $false,
    [string]$Query = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ROMsDir = Join-Path $RepoRoot "ROMs"
$CatalogPath = Join-Path $RepoRoot "Configs\free-games-catalog.json"

. (Join-Path $PSScriptRoot "ps-common.ps1")

# ---------------------------------------------------------------------------
# Catalog-driven legal free/homebrew ROM sources.
# The catalog is the single source of truth and is designed to be updated
# without touching this script (drop-in JSON updates / future-safe).
# ---------------------------------------------------------------------------

function Get-GamesCatalog {
    if (-not (Test-Path -LiteralPath $CatalogPath)) {
        Write-WarnLine "free-games-catalog.json missing - falling back to built-in mini sources."
        return $null
    }
    try {
        $raw = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return $raw
    }
    catch {
        Write-WarnLine ("Could not parse free-games-catalog.json: {0}" -f $_.Exception.Message)
        return $null
    }
}

function Get-RomSourcesFromCatalog {
    param($Catalog)

    $result = [ordered]@{}
    if (-not $Catalog) { return $result }

    $systemsNode = Get-ObjectProperty -InputObject $Catalog -Name "systems" -Default $null
    if (-not $systemsNode) { return $result }

    foreach ($prop in $systemsNode.PSObject.Properties) {
        $systemName = $prop.Name
        $node = $prop.Value
        $extensions = @(Get-ObjectProperty -InputObject $node -Name "extensions" -Default @())
        $defaultKeywords = [string](Get-ObjectProperty -InputObject $node -Name "search_keywords" -Default "")
        $entries = @(Get-ObjectProperty -InputObject $node -Name "entries" -Default @())
        $sources = @()

        foreach ($entry in $entries) {
            $entryName = [string](Get-ObjectProperty -InputObject $entry -Name "name" -Default "Untitled")
            $item = [string](Get-ObjectProperty -InputObject $entry -Name "item" -Default "")
            $files = @(Get-ObjectProperty -InputObject $entry -Name "files" -Default @())
            $keywords = [string](Get-ObjectProperty -InputObject $entry -Name "search_keywords" -Default "")
            if (-not $keywords) { $keywords = $defaultKeywords }
            $doSearch = $false
            $searchFlag = Get-ObjectProperty -InputObject $entry -Name "search" -Default $null
            if ($searchFlag -eq $true) { $doSearch = $true }
            if (-not $item) { $doSearch = $true }

            $sources += @{
                Name           = $entryName
                Item           = $item
                Files          = $files
                Extensions     = $extensions
                SearchKeywords = $keywords
                AlwaysSearch   = $doSearch
                License        = [string](Get-ObjectProperty -InputObject $entry -Name "license" -Default "homebrew")
                Players        = [int](Get-ObjectProperty -InputObject $entry -Name "players" -Default 1)
            }
        }

        # Always append a live catch-all search so the catalog stays future-proof
        # even when curated entries go stale.
        if ($defaultKeywords) {
            $sources += @{
                Name           = ("{0} live homebrew search" -f $systemName)
                Item           = ""
                Files          = @()
                Extensions     = $extensions
                SearchKeywords = $defaultKeywords
                AlwaysSearch   = $true
                License        = "homebrew"
                Players        = 2
            }
        }

        $result[$systemName] = $sources
    }
    return $result
}

function Get-LegacyFallbackSources {
    return [ordered]@{
        "NES" = @(
            @{ Name = "Eyra the Crow Maiden"; Item = "eyra-nesdemo"; Files = @("eyrademo.nes"); Extensions = @(".nes"); SearchKeywords = "nes homebrew"; AlwaysSearch = $false }
        )
        "SNES" = @(
            @{ Name = "Dottie Dreads Nough"; Item = "dottie-dreads-nough-snesforever.com.br"; Files = @("Dottie Dreads Nough - [snesforever.com.br].sfc"); Extensions = @(".sfc", ".smc"); SearchKeywords = "snes homebrew"; AlwaysSearch = $false }
        )
        "GameBoy" = @(
            @{ Name = "Damuel"; Item = "damuel-project"; Files = @("Damuel.gb"); Extensions = @(".gb", ".gbc"); SearchKeywords = "gameboy homebrew"; AlwaysSearch = $false }
        )
        "GBA" = @(
            @{ Name = "GBA homebrew"; Item = ""; Files = @(); Extensions = @(".gba"); SearchKeywords = "(gba OR `"game boy advance`") AND homebrew"; AlwaysSearch = $true }
        )
        "Genesis" = @(
            @{ Name = "Genesis homebrew"; Item = ""; Files = @(); Extensions = @(".md", ".gen"); SearchKeywords = "(genesis OR `"mega drive`") AND homebrew"; AlwaysSearch = $true }
        )
        "Atari2600" = @(
            @{ Name = "Atari 2600 homebrew"; Item = ""; Files = @(); Extensions = @(".a26", ".bin"); SearchKeywords = "`"atari 2600`" AND homebrew"; AlwaysSearch = $true }
        )
    }
}

function Get-RomSources {
    $catalog = Get-GamesCatalog
    $fromCatalog = Get-RomSourcesFromCatalog -Catalog $catalog
    if ($fromCatalog.Count -gt 0) {
        return $fromCatalog
    }
    return (Get-LegacyFallbackSources)
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
            if ($lower -match "_(files\.xml|meta\.(xml|sqlite))$" -or $lower -match "\.(torrent|png|jpe?g|gif|txt|pdf|xml|mp3|mp4|mkv)$") { continue }
            $sizeValue = Get-ObjectProperty -InputObject $file -Name "size" -Default 0
            if ($sizeValue -and [long]$sizeValue -gt 128MB) { continue }
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
        [int]$MaxItems = 8,
        [int]$MaxFiles = 4
    )

    $results = @()
    try {
        Set-DownloadSecurityProtocol
        $query = "collection:(open_source_software OR softwarelibrary OR freeware) AND mediatype:software AND ({0})" -f $Keywords
        $url = "https://archive.org/advancedsearch.php?q={0}&fl[]=identifier&fl[]=title&rows=25&output=json" -f [uri]::EscapeDataString($query)
        $command = Get-Command Invoke-WebRequest -ErrorAction Stop
        $params = @{ Uri = $url; ErrorAction = "Stop" }
        if ($command.Parameters.ContainsKey("TimeoutSec")) { $params.TimeoutSec = 45 }
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
            if ($results.Count -ge $MaxItems) { break }
            $probed++
            if ($probed -gt 15) { break }
            $identifier = [string](Get-ObjectProperty -InputObject $doc -Name "identifier" -Default "")
            if (-not $identifier) { continue }
            $files = Get-ArchiveItemFiles -ItemId $identifier -Extensions $Extensions
            if ($files.Count -gt 0) {
                $results += [pscustomobject]@{
                    Item  = $identifier
                    Title = [string](Get-ObjectProperty -InputObject $doc -Name "title" -Default $identifier)
                    Files = @($files | Select-Object -First $MaxFiles)
                }
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
    Write-Banner -Title "FREE GAMES DOWNLOAD TOOL v3" -Subtitle "Legal homebrew / public-domain / freeware ONLY"
    $systems = @($Sources.Keys)
    Write-Host ("  Catalog systems: {0}   |   Max files/source: {1}" -f $systems.Count, $MaxFiles)
    Write-Host ""
    for ($i = 0; $i -lt $systems.Count; $i++) {
        $romDir = Join-Path $ROMsDir $systems[$i]
        $count = 0
        if (Test-Path -LiteralPath $romDir) {
            $count = (Get-ChildItem -Path $romDir -File -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
        }
        $srcCount = @($Sources[$systems[$i]]).Count
        Write-Host ("  {0,2}. {1,-18} {2,4} ROMs on disk   ({3} catalog sources)" -f ($i + 1), $systems[$i], $count, $srcCount)
    }
    Write-Host ""
    Write-Host ("  {0}. Download sample pack (popular systems)" -f ($systems.Count + 1))
    Write-Host ("  {0}. Download EVERYTHING the catalog can find" -f ($systems.Count + 2))
    Write-Host ("  {0}. Show legal source guidance" -f ($systems.Count + 3))
    Write-Host ("  {0}. List catalog summary" -f ($systems.Count + 4))
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
        [int]$MaxDownloads = 8
    )

    $sources = Get-RomSources
    if (-not $sources.Contains($SystemName)) {
        Write-WarnLine ("No configured download sources exist for {0}." -f $SystemName)
        Write-InfoLine "Browse https://archive.org or https://itch.io for legal homebrew titles."
        Write-InfoLine ("Available: {0}" -f (($sources.Keys) -join ", "))
        return
    }

    $systemDir = Ensure-Directory -Path (Join-Path $ROMsDir $SystemName)
    $downloaded = 0
    $skipped = 0
    $failed = 0
    $seenUrls = New-Object "System.Collections.Generic.HashSet[string]"

    Write-Section ("Downloading free games for {0}" -f $SystemName)

    foreach ($source in $sources[$SystemName]) {
        if ($downloaded -ge ($MaxDownloads * 3)) {
            Write-InfoLine "Reached safety cap for this system run."
            break
        }

        Write-InfoLine ("Source: {0}  [{1}]" -f $source.Name, $source.License)

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

        $needsSearch = ($wantedFiles.Count -eq 0) -or ($source.AlwaysSearch -eq $true)
        if ($needsSearch -and $source.SearchKeywords) {
            Write-InfoLine ("Searching archive.org: {0}" -f $source.SearchKeywords)
            $candidates = Find-ArchiveRomCandidates -Keywords $source.SearchKeywords -Extensions @($source.Extensions) -MaxFiles $MaxDownloads -MaxItems 6
            foreach ($candidate in $candidates) {
                if (-not $sourceItem) { $sourceItem = $candidate.Item }
                Write-InfoLine ("Found: https://archive.org/details/{0}" -f $candidate.Item)
                foreach ($auto in $candidate.Files) {
                    # Qualify with item id so different items don't collide.
                    $qualified = "{0}::{1}" -f $candidate.Item, $auto
                    if ($wantedFiles.Count -ge $MaxDownloads) { break }
                    if (-not $wantedFiles.Contains($qualified) -and -not $wantedFiles.Contains($auto)) {
                        $wantedFiles.Add($qualified)
                    }
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
            }
            continue
        }

        foreach ($fileEntry in $wantedFiles) {
            $itemId = $sourceItem
            $fileName = $fileEntry
            if ($fileEntry -match "^(?<item>[^:]+)::(?<file>.+)$") {
                $itemId = $Matches["item"]
                $fileName = $Matches["file"]
            }
            if (-not $itemId) { continue }

            # Flatten nested archive paths to a safe filename.
            $safeName = ($fileName -replace "[\\/]", "_")
            $targetPath = Join-Path $systemDir $safeName
            $fileUrl = "https://archive.org/download/{0}/{1}" -f $itemId, ([uri]::EscapeDataString($fileName).Replace("%2F", "/"))

            if (-not $seenUrls.Add($fileUrl)) { continue }

            if ((-not $OverwriteExisting) -and (Test-Path -LiteralPath $targetPath)) {
                Write-OkLine ("Skipping existing file {0}" -f $safeName)
                $skipped++
                continue
            }

            if ($PreviewOnly) {
                Write-InfoLine ("Would download: {0}" -f $fileUrl)
                continue
            }

            try {
                Write-InfoLine ("Downloading {0}" -f $safeName)
                Invoke-DownloadFile -Uri $fileUrl -OutFile $targetPath -TimeoutSec 180 -Retries 3
                Write-OkLine ("Saved {0}" -f $targetPath)
                $downloaded++
            }
            catch {
                Write-WarnLine ("Could not download {0}: {1}" -f $safeName, $_.Exception.Message)
                Remove-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
                $failed++
            }
        }
    }

    Write-InfoLine ("Downloaded: {0}  Skipped: {1}  Failed: {2}" -f $downloaded, $skipped, $failed)
    Write-InfoLine ("Library folder: {0}" -f $systemDir)
}

function Download-SamplePack {
    param(
        [switch]$OverwriteExisting,
        [switch]$PreviewOnly
    )

    $popular = @("NES", "SNES", "GameBoy", "GBA", "Genesis", "Atari2600", "C64", "DOS", "TIC80", "CHIP8", "MSX", "ZXSpectrum")
    $sources = Get-RomSources
    foreach ($systemName in $popular) {
        if ($sources.Contains($systemName)) {
            Download-SystemRoms -SystemName $systemName -OverwriteExisting:$OverwriteExisting -PreviewOnly:$PreviewOnly -MaxDownloads $MaxFiles
        }
    }
}

function Download-Everything {
    param(
        [switch]$OverwriteExisting,
        [switch]$PreviewOnly
    )

    $sources = Get-RomSources
    foreach ($systemName in @($sources.Keys)) {
        Download-SystemRoms -SystemName $systemName -OverwriteExisting:$OverwriteExisting -PreviewOnly:$PreviewOnly -MaxDownloads ([Math]::Max(3, [int]($MaxFiles / 2)))
    }
}

function Show-CatalogSummary {
    $sources = Get-RomSources
    Write-Section "Catalog Summary"
    $totalSources = 0
    foreach ($key in $sources.Keys) {
        $count = @($sources[$key]).Count
        $totalSources += $count
        Write-Host ("  {0,-18} {1,3} sources" -f $key, $count)
    }
    Write-Host ""
    Write-Host ("  Systems: {0}    Sources: {1}" -f $sources.Count, $totalSources)
    Write-Host ("  Catalog file: {0}" -f $CatalogPath)
    Write-Host ""
    Write-Host "  To update the game list in the future, just edit or replace:"
    Write-Host "    Configs/free-games-catalog.json"
    Write-Host "  No code changes required. Live archive.org search fills gaps."
    Write-Host ""
    Pause-IfInteractive -Prompt "Press Enter to return" -NonInteractive:$NonInteractive
}

function Show-LegalGuide {
    Write-Section "Legal ROM Guidance"
    Write-Host "This tool ONLY targets legal sources:"
    Write-Host "  - Homebrew games (fan-made, freely distributed)"
    Write-Host "  - Public-domain / open-source releases"
    Write-Host "  - Freeware and legitimate shareware"
    Write-Host "  - Dumps YOU made from media you own"
    Write-Host ""
    Write-Host "Recommended places to browse:"
    Write-Host "  - https://archive.org          (search '<system> homebrew')"
    Write-Host "  - https://itch.io              (filter: free + homebrew/retro)"
    Write-Host "  - https://www.romhacking.net   (translations & homebrew)"
    Write-Host "  - https://pdroms.de            (public domain ROMs)"
    Write-Host "  - https://www.smspower.org     (Master System homebrew)"
    Write-Host "  - https://www.atariage.com     (Atari homebrew)"
    Write-Host "  - https://tic80.com            (TIC-80 fantasy console carts)"
    Write-Host "  - https://wasm4.org            (WASM-4 carts)"
    Write-Host ""
    Write-Host "Do NOT download commercial ROMs you do not have rights to."
    Write-Host "Owning a cartridge does not automatically make a random"
    Write-Host "internet download legal - dump your own or buy digital re-releases."
    Write-Host ""
    Pause-IfInteractive -Prompt "Press Enter to return to the menu" -NonInteractive:$NonInteractive
}

# --- Entry -----------------------------------------------------------------

Start-SetupLog -RootPath $RepoRoot -Name "download-roms" | Out-Null

if ($Query) {
    Write-Section ("Live search: {0}" -f $Query)
    $hits = Find-ArchiveRomCandidates -Keywords $Query -MaxItems 10 -MaxFiles 5
    if ($hits.Count -eq 0) {
        Write-WarnLine "No results."
        exit 1
    }
    foreach ($hit in $hits) {
        Write-Host ("  {0}" -f $hit.Title)
        Write-Host ("    https://archive.org/details/{0}" -f $hit.Item)
        foreach ($f in $hit.Files) { Write-Host ("      - {0}" -f $f) }
    }
    return
}

if ($System -ne "") {
    if ($System.ToLowerInvariant() -eq "all") {
        Download-SamplePack -OverwriteExisting:$Overwrite -PreviewOnly:$ListOnly
    }
    elseif ($System.ToLowerInvariant() -eq "everything") {
        Download-Everything -OverwriteExisting:$Overwrite -PreviewOnly:$ListOnly
    }
    else {
        $sources = Get-RomSources
        $matched = @($sources.Keys | Where-Object { $_.ToLowerInvariant() -eq $System.ToLowerInvariant() })
        if ($matched.Count -gt 0) {
            Download-SystemRoms -SystemName $matched[0] -OverwriteExisting:$Overwrite -PreviewOnly:$ListOnly -MaxDownloads $MaxFiles
        }
        else {
            Write-WarnLine ("Unknown system '{0}'. Available: {1}, All, Everything" -f $System, (($sources.Keys) -join ", "))
            exit 1
        }
    }
    return
}

if ($NonInteractive) {
    Write-WarnLine "Provide -System <name|All|Everything> when running non-interactively."
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
        Download-Everything -OverwriteExisting:$Overwrite -PreviewOnly:$ListOnly
        Pause-IfInteractive -Prompt "Press Enter to continue" -NonInteractive:$NonInteractive
    }
    elseif ($asNumber -eq ($systems.Count + 3)) {
        Show-LegalGuide
    }
    elseif ($asNumber -eq ($systems.Count + 4)) {
        Show-CatalogSummary
    }
    else {
        Write-WarnLine "Unknown menu choice."
    }
} while ($true)
