Set-StrictMode -Version Latest

# Shared helpers for the Portable Retro Gaming Suite (PowerShell 5.1 compatible).
# Provides logging, downloads with retry, 7z extraction, Python bootstrap,
# RetroArch install/configure, core downloads, and health/repair automation.

$script:PinnedStableVersion = "1.22.2"
$script:LogFile = ""
$script:DefaultCoreDefinitions = @(
    @{ Name = "fceumm"; Desc = "Nintendo (NES)" },
    @{ Name = "snes9x"; Desc = "Super Nintendo" },
    @{ Name = "mupen64plus_next"; Desc = "Nintendo 64" },
    @{ Name = "gambatte"; Desc = "Game Boy / Game Boy Color" },
    @{ Name = "mgba"; Desc = "Game Boy Advance" },
    @{ Name = "desmume"; Desc = "Nintendo DS" },
    @{ Name = "genesis_plus_gx"; Desc = "Sega Genesis / Master System / Game Gear" },
    @{ Name = "pcsx_rearmed"; Desc = "PlayStation 1" },
    @{ Name = "mame2003_plus"; Desc = "Arcade (MAME)" },
    @{ Name = "fbneo"; Desc = "Neo Geo / Arcade" },
    @{ Name = "stella"; Desc = "Atari 2600" },
    @{ Name = "flycast"; Desc = "Sega Dreamcast" },
    @{ Name = "ppsspp"; Desc = "PlayStation Portable" }
)

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

function Start-SetupLog {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [string]$Name = "setup"
    )

    try {
        $logsDir = Join-Path $RootPath "Logs"
        New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $script:LogFile = Join-Path $logsDir ("{0}-{1}.log" -f $Name, $stamp)
        $header = "=== {0} started {1} (user: {2}, PS: {3}) ===" -f $Name, (Get-Date), $env:USERNAME, $PSVersionTable.PSVersion
        Add-Content -LiteralPath $script:LogFile -Value $header -Encoding UTF8
    }
    catch {
        $script:LogFile = ""
    }

    return $script:LogFile
}

function Write-LogLine {
    param([Parameter(Mandatory = $true)][string]$Message)

    if ($script:LogFile) {
        try {
            Add-Content -LiteralPath $script:LogFile -Value ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message) -Encoding UTF8
        }
        catch {
        }
    }
}

function Get-SetupLogPath {
    return $script:LogFile
}

# ---------------------------------------------------------------------------
# Console output (always mirrored to the log file when active)
# ---------------------------------------------------------------------------

function Write-StatusLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    Write-Host $Message -ForegroundColor $Color
    Write-LogLine -Message $Message
}

function Write-InfoLine {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-StatusLine -Message $Message -Color Cyan
}

function Write-OkLine {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-StatusLine -Message ("[OK] {0}" -f $Message) -Color Green
}

function Write-WarnLine {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-StatusLine -Message ("[WARN] {0}" -f $Message) -Color Yellow
}

function Write-FailLine {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-StatusLine -Message ("[FAIL] {0}" -f $Message) -Color Red
}

function Write-Section {
    param([Parameter(Mandatory = $true)][string]$Title)

    Write-Host ""
    Write-InfoLine ("=" * 72)
    Write-InfoLine ("  {0}" -f $Title)
    Write-InfoLine ("=" * 72)
    Write-Host ""
}

function Write-Banner {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [string]$Subtitle = ""
    )

    Write-Host ""
    Write-StatusLine -Message ("+" + ("-" * 70) + "+") -Color Magenta
    Write-StatusLine -Message ("| {0,-68} |" -f $Title) -Color Magenta
    if ($Subtitle) {
        Write-StatusLine -Message ("| {0,-68} |" -f $Subtitle) -Color Magenta
    }
    Write-StatusLine -Message ("+" + ("-" * 70) + "+") -Color Magenta
    Write-Host ""
}

function Test-InteractiveRun {
    param([switch]$NonInteractive)

    if ($NonInteractive) {
        return $false
    }

    return [Environment]::UserInteractive
}

function Read-YesNo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [bool]$Default = $false,
        [switch]$NonInteractive
    )

    if (-not (Test-InteractiveRun -NonInteractive:$NonInteractive)) {
        return $Default
    }

    $suffix = if ($Default) { "[Y/n]" } else { "[y/N]" }
    $response = Read-Host ("{0} {1}" -f $Prompt, $suffix)

    if ([string]::IsNullOrWhiteSpace($response)) {
        return $Default
    }

    return $response.Trim().ToLowerInvariant() -in @("y", "yes")
}

function Pause-IfInteractive {
    param(
        [string]$Prompt = "Press Enter to continue",
        [switch]$NonInteractive
    )

    if (Test-InteractiveRun -NonInteractive:$NonInteractive) {
        Read-Host $Prompt | Out-Null
    }
}

function Clear-ScreenSafe {
    try {
        Clear-Host
    }
    catch {
    }
}

# ---------------------------------------------------------------------------
# Paths & configuration
# ---------------------------------------------------------------------------

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    return $Path
}

function Get-TempPath {
    param([Parameter(Mandatory = $true)][string]$Name)

    return Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath $Name
}

function Get-ObjectProperty {
    param(
        [Parameter(Mandatory = $false)][object]$InputObject = $null,
        [Parameter(Mandatory = $true)][string]$Name,
        $Default = $null
    )

    # StrictMode-safe property lookup for JSON-derived objects.
    # Direct access like $system.bios throws PropertyNotFoundStrict when the
    # key is absent (e.g. systems without BIOS entries), so every optional
    # property of ConvertFrom-Json output MUST go through this helper.
    # Present-but-null values also fall back to $Default.
    if ($null -eq $InputObject) {
        return $Default
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name) -and $null -ne $InputObject[$Name]) {
            return $InputObject[$Name]
        }
        return $Default
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property -and $null -ne $property.Value) {
        return $property.Value
    }
    return $Default
}

function Get-VersionInfo {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $info = [pscustomobject]@{
        Version = "2.0.0"
        RetroArchStable = $script:PinnedStableVersion
    }
    $versionFile = Join-Path $RootPath "version.json"
    if (Test-Path -LiteralPath $versionFile) {
        try {
            $parsed = Get-Content -LiteralPath $versionFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $versionValue = Get-ObjectProperty -InputObject $parsed -Name "version" -Default ""
            if ($versionValue) { $info.Version = [string]$versionValue }
            $stableValue = Get-ObjectProperty -InputObject $parsed -Name "retroarchStable" -Default ""
            if ($stableValue) { $info.RetroArchStable = [string]$stableValue }
        }
        catch {
        }
    }
    return $info
}

function Get-SystemsConfig {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $configFile = Join-Path $RootPath "Configs\systems.json"
    if (-not (Test-Path -LiteralPath $configFile)) {
        return @()
    }
    try {
        $parsed = Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
        return @($parsed)
    }
    catch {
        Write-WarnLine ("Could not parse systems.json: {0}" -f $_.Exception.Message)
        return @()
    }
}

function Get-PortablePathInfo {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    return [pscustomobject]@{
        LaunchBat            = Join-Path $RootPath "LAUNCH.bat"
        SetupBat             = Join-Path $RootPath "SETUP.bat"
        DownloadRomsBat      = Join-Path $RootPath "Tools\download-roms.bat"
        OrganizeRomsBat      = Join-Path $RootPath "Tools\organize-roms.bat"
        TestControllerBat    = Join-Path $RootPath "Tools\test-controller.bat"
        UpdateSystemBat      = Join-Path $RootPath "Tools\update-system.bat"
        DiagnoseBat          = Join-Path $RootPath "Tools\diagnose.bat"
        LauncherScript       = Join-Path $RootPath "Launcher\launcher.py"
        DownloadRomsScript   = Join-Path $RootPath "Tools\download-roms.ps1"
        OrganizeRomsScript   = Join-Path $RootPath "Tools\organize-roms.ps1"
        TestControllerScript = Join-Path $RootPath "Tools\test-controller.ps1"
        UpdateSystemScript   = Join-Path $RootPath "Tools\update-system.ps1"
        DiagnoseScript       = Join-Path $RootPath "Tools\diagnose.ps1"
        RetroArchExe         = Join-Path $RootPath "Emulators\RetroArch\retroarch.exe"
        LogsDir              = Join-Path $RootPath "Logs"
    }
}

function Get-FreeDiskSpaceGB {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $root = [IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path)
        $drive = Get-PSDrive -Name $root.TrimEnd('\', ':') -ErrorAction Stop
        if ($drive.Free -ne $null) {
            return [Math]::Round($drive.Free / 1GB, 2)
        }
    }
    catch {
    }
    return -1
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

function Set-DownloadSecurityProtocol {
    try {
        $protocol = [Net.SecurityProtocolType]::Tls12
        if ([Enum]::GetNames([Net.SecurityProtocolType]) -contains "Tls13") {
            $protocol = $protocol -bor [Net.SecurityProtocolType]::Tls13
        }
        [Net.ServicePointManager]::SecurityProtocol = $protocol
    }
    catch {
        Write-WarnLine "Could not update TLS settings. Downloads will use host defaults."
    }
}

function Test-InternetConnection {
    param([int]$TimeoutSec = 10)

    $probes = @(
        "https://buildbot.libretro.com/stable/",
        "https://www.retroarch.com/"
    )
    foreach ($url in $probes) {
        try {
            Set-DownloadSecurityProtocol
            $command = Get-Command Invoke-WebRequest -ErrorAction Stop
            $params = @{ Uri = $url; Method = "Head"; ErrorAction = "Stop" }
            if ($command.Parameters.ContainsKey("TimeoutSec")) { $params.TimeoutSec = $TimeoutSec }
            if ($command.Parameters.ContainsKey("UseBasicParsing")) { $params.UseBasicParsing = $true }
            $previousProgress = $global:ProgressPreference
            try {
                $global:ProgressPreference = "SilentlyContinue"
                Invoke-WebRequest @params | Out-Null
            }
            finally {
                $global:ProgressPreference = $previousProgress
            }
            return $true
        }
        catch {
        }
    }
    return $false
}

function Invoke-DownloadFile {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [int]$TimeoutSec = 120,
        [int]$Retries = 3
    )

    Set-DownloadSecurityProtocol
    Ensure-Directory -Path (Split-Path -Parent $OutFile) | Out-Null

    $command = Get-Command Invoke-WebRequest -ErrorAction Stop
    $attempt = 0
    $lastError = $null

    while ($attempt -lt $Retries) {
        $attempt++
        try {
            Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
            $params = @{
                Uri         = $Uri
                OutFile     = $OutFile
                ErrorAction = "Stop"
            }
            if ($TimeoutSec -gt 0 -and $command.Parameters.ContainsKey("TimeoutSec")) {
                $params.TimeoutSec = $TimeoutSec
            }
            if ($command.Parameters.ContainsKey("UseBasicParsing")) {
                $params.UseBasicParsing = $true
            }
            $previousProgress = $global:ProgressPreference
            try {
                $global:ProgressPreference = "SilentlyContinue"
                Invoke-WebRequest @params | Out-Null
            }
            finally {
                $global:ProgressPreference = $previousProgress
            }

            $downloaded = Get-Item -LiteralPath $OutFile -ErrorAction Stop
            if ($downloaded.Length -le 0) {
                throw "Download completed but the file is empty."
            }
            return $downloaded
        }
        catch {
            $lastError = $_
            Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
            if ($attempt -lt $Retries) {
                Write-WarnLine ("Download attempt {0}/{1} failed for {2}, retrying..." -f $attempt, $Retries, $Uri)
                Start-Sleep -Seconds (2 * $attempt)
            }
        }
    }

    throw ("Download failed after {0} attempts: {1} ({2})" -f $Retries, $Uri, $lastError.Exception.Message)
}

function Get-LatestStableVersion {
    param([int]$TimeoutSec = 15)

    # Parse the buildbot stable listing (plain HTML, no JavaScript needed).
    try {
        Set-DownloadSecurityProtocol
        $params = @{ Uri = "https://buildbot.libretro.com/stable/"; ErrorAction = "Stop" }
        $command = Get-Command Invoke-WebRequest -ErrorAction Stop
        if ($command.Parameters.ContainsKey("TimeoutSec")) { $params.TimeoutSec = $TimeoutSec }
        if ($command.Parameters.ContainsKey("UseBasicParsing")) { $params.UseBasicParsing = $true }
        $previousProgress = $global:ProgressPreference
        try {
            $global:ProgressPreference = "SilentlyContinue"
            $response = Invoke-WebRequest @params
        }
        finally {
            $global:ProgressPreference = $previousProgress
        }
        $matches = [regex]::Matches($response.Content, "stable/([0-9]+\.[0-9]+(?:\.[0-9]+)?)/")
        $versions = @()
        foreach ($match in $matches) {
            try {
                $versions += [version]$match.Groups[1].Value
            }
            catch {
            }
        }
        if ($versions.Count -gt 0) {
            $latest = ($versions | Sort-Object | Select-Object -Last 1).ToString()
            Write-LogLine -Message ("Detected latest stable RetroArch: {0}" -f $latest)
            return $latest
        }
    }
    catch {
        Write-LogLine -Message ("Stable version detection failed: {0}" -f $_.Exception.Message)
    }

    return ""
}

function Get-RetroArchDownloadUrls {
    param([string]$RootPath = "")

    $versions = New-Object System.Collections.Generic.List[string]

    $detected = Get-LatestStableVersion
    if ($detected) { $versions.Add($detected) }

    $pinned = $script:PinnedStableVersion
    if ($RootPath) {
        $pinned = (Get-VersionInfo -RootPath $RootPath).RetroArchStable
    }
    foreach ($candidate in @($pinned, $script:PinnedStableVersion, "1.21.0", "1.20.0")) {
        if ($candidate -and -not $versions.Contains($candidate)) {
            $versions.Add($candidate)
        }
    }

    $urls = New-Object System.Collections.Generic.List[string]
    foreach ($version in $versions) {
        $urls.Add(("https://buildbot.libretro.com/stable/{0}/windows/x86_64/RetroArch.7z" -f $version))
        $urls.Add(("https://buildbot.libretro.com/stable/{0}/windows/x86_64/RetroArch-Win64-setup.exe" -f $version))
    }
    # Last-resort fallbacks.
    $urls.Add("https://buildbot.libretro.com/stable/1.22.2/windows-msvc2010/x86_64/RetroArch.7z")
    $urls.Add("https://buildbot.libretro.com/nightly/windows/x86_64/RetroArch.7z")
    $urls.Add("https://buildbot.libretro.com/nightly/windows/x86_64/RetroArch-Win64-setup.exe")

    return $urls.ToArray()
}

# ---------------------------------------------------------------------------
# Archives (.zip and .7z extraction with multiple fallbacks)
# ---------------------------------------------------------------------------

function Find-SevenZipExe {
    $candidates = @(
        (Get-Command 7z.exe -ErrorAction SilentlyContinue),
        (Get-Command 7za.exe -ErrorAction SilentlyContinue)
    )
    foreach ($candidate in $candidates) {
        if ($candidate) { return $candidate.Source }
    }
    foreach ($fixed in @(
        "$env:ProgramFiles\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
        "$env:ProgramW6432\7-Zip\7z.exe"
    )) {
        if ($fixed -and (Test-Path -LiteralPath $fixed)) { return $fixed }
    }
    return ""
}

function Find-WingetCommand {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) { return $winget.Source }
    $localPath = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
    if (Test-Path -LiteralPath $localPath) { return $localPath }
    return ""
}

function Ensure-SevenZip {
    # Returns a 7z exe path, trying an automatic winget install as needed.
    $existing = Find-SevenZipExe
    if ($existing) { return $existing }

    $winget = Find-WingetCommand
    if (-not $winget) { return "" }

    Write-InfoLine "7-Zip not found. Installing automatically via winget..."
    try {
        $process = Start-Process -FilePath $winget -ArgumentList @(
            "install", "-e", "--id", "7zip.7zip",
            "--silent",
            "--accept-package-agreements",
            "--accept-source-agreements"
        ) -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -eq 0) {
            return Find-SevenZipExe
        }
        Write-WarnLine ("winget 7-Zip install exited with code {0}." -f $process.ExitCode)
    }
    catch {
        Write-WarnLine ("Automatic 7-Zip install failed: {0}" -f $_.Exception.Message)
    }
    return ""
}

function Expand-ArchiveToPath {
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    Ensure-Directory -Path $DestinationPath | Out-Null

    $extension = [IO.Path]::GetExtension($ArchivePath).ToLowerInvariant()

    if ($extension -eq ".zip") {
        try {
            Expand-Archive -Path $ArchivePath -DestinationPath $DestinationPath -Force
            return
        }
        catch {
            Write-WarnLine ("Expand-Archive failed, trying tar: {0}" -f $_.Exception.Message)
        }
        $tarCommand = Get-Command tar.exe -ErrorAction SilentlyContinue
        if (-not $tarCommand) { $tarCommand = Get-Command tar -ErrorAction SilentlyContinue }
        if ($tarCommand) {
            & $tarCommand.Source -xf $ArchivePath -C $DestinationPath
            if ($LASTEXITCODE -eq 0) { return }
            throw "Could not extract ZIP archive with Expand-Archive or tar."
        }
        throw "Could not extract ZIP archive (Expand-Archive failed and tar is unavailable)."
    }

    if ($extension -eq ".7z") {
        # 1) Native 7-Zip (fast path, handles large archives reliably).
        $sevenZip = Ensure-SevenZip
        if ($sevenZip) {
            & $sevenZip x $ArchivePath -o"$DestinationPath" -y | Out-Null
            if ($LASTEXITCODE -eq 0) { return }
            throw "7-Zip failed to extract $ArchivePath (exit code $LASTEXITCODE)."
        }

        # 2) py7zr via a temp script file (safe quoting for spaces/unicode).
        $pythonInfo = Find-PythonCommand
        if ($pythonInfo) {
            if (Ensure-PythonPackage -PythonCommand $pythonInfo.Command -PackageName "py7zr" -ModuleName "py7zr") {
                $pyScript = Get-TempPath -Name ("extract-{0}.py" -f ([guid]::NewGuid().ToString("N")))
                $pyCode = @'
import sys
import py7zr
archive_path, dest_path = sys.argv[1], sys.argv[2]
with py7zr.SevenZipFile(archive_path, mode="r") as archive:
    archive.extractall(path=dest_path)
'@
                try {
                    Set-Content -LiteralPath $pyScript -Value $pyCode -Encoding ASCII
                    & $pythonInfo.Command $pyScript $ArchivePath $DestinationPath
                    if ($LASTEXITCODE -eq 0) { return }
                    Write-WarnLine "py7zr extraction failed, trying remaining fallbacks."
                }
                finally {
                    Remove-Item -LiteralPath $pyScript -Force -ErrorAction SilentlyContinue
                }
            }
        }

        # 3) tar (some bsdtar builds can read 7z).
        $tarCommand = Get-Command tar.exe -ErrorAction SilentlyContinue
        if (-not $tarCommand) { $tarCommand = Get-Command tar -ErrorAction SilentlyContinue }
        if ($tarCommand) {
            & $tarCommand.Source -xf $ArchivePath -C $DestinationPath
            if ($LASTEXITCODE -eq 0) { return }
        }

        throw "Could not extract $ArchivePath. Install 7-Zip (`winget install 7zip.7zip`) or Python with py7zr and retry."
    }

    throw ("Unsupported archive type: {0}" -f $extension)
}

# ---------------------------------------------------------------------------
# Python bootstrap
# ---------------------------------------------------------------------------

function Find-PythonCommand {
    $candidates = @("python", "python3", "py")
    foreach ($candidate in $candidates) {
        try {
            $versionOutput = (& $candidate --version 2>&1 | Out-String).Trim()
            if ($versionOutput -match "Python\s+(\d+)\.(\d+)(?:\.(\d+))?") {
                return [pscustomobject]@{
                    Command = $candidate
                    Version = ("{0}.{1}.{2}" -f $Matches[1], $Matches[2], $(if ($Matches[3]) { $Matches[3] } else { "0" }))
                    Major   = [int]$Matches[1]
                    Minor   = [int]$Matches[2]
                }
            }
        }
        catch {
        }
    }

    return $null
}

function Test-PythonModule {
    param(
        [Parameter(Mandatory = $true)][string]$PythonCommand,
        [Parameter(Mandatory = $true)][string]$ModuleName
    )

    & $PythonCommand -c "import importlib.util, sys; sys.exit(0 if importlib.util.find_spec('$ModuleName') else 1)" *> $null
    return ($LASTEXITCODE -eq 0)
}

function Ensure-PythonPackage {
    param(
        [Parameter(Mandatory = $true)][string]$PythonCommand,
        [Parameter(Mandatory = $true)][string]$PackageName,
        [string]$ModuleName = $PackageName,
        [switch]$UseUserScope = $true,
        [string[]]$FallbackPackages = @()
    )

    if (Test-PythonModule -PythonCommand $PythonCommand -ModuleName $ModuleName) {
        return $true
    }

    $packagesToTry = @($PackageName) + $FallbackPackages

    foreach ($candidatePackage in $packagesToTry) {
        foreach ($userScope in @($true, $false)) {
            if ($userScope -and -not $UseUserScope) { continue }
            # Best-effort pip upgrade; never fail the install because of it.
            $upgradeArgs = @("-m", "pip", "install", "--upgrade", "pip")
            if ($userScope) { $upgradeArgs += "--user" }
            & $PythonCommand @upgradeArgs *> $null

            $installArgs = @("-m", "pip", "install", $candidatePackage)
            if ($userScope) { $installArgs += "--user" }
            & $PythonCommand @installArgs

            if (Test-PythonModule -PythonCommand $PythonCommand -ModuleName $ModuleName) {
                return $true
            }
        }
    }

    return $false
}

function Refresh-SessionPath {
    # Pick up machine/user PATH changes (e.g. after a winget install).
    try {
        $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
        $user = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($machine -or $user) {
            $env:Path = "$machine;$user"
        }
    }
    catch {
    }
}

function Install-PythonViaWinget {
    param([string]$VersionId = "Python.Python.3.12")

    $winget = Find-WingetCommand
    if (-not $winget) {
        Write-WarnLine "winget is not available, cannot auto-install Python."
        return $false
    }

    Write-InfoLine "Installing Python automatically via winget (this takes a few minutes)..."
    try {
        $process = Start-Process -FilePath $winget -ArgumentList @(
            "install", "-e", "--id", $VersionId,
            "--silent",
            "--accept-package-agreements",
            "--accept-source-agreements"
        ) -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -ne 0) {
            Write-WarnLine ("winget Python install exited with code {0}." -f $process.ExitCode)
            return $false
        }
    }
    catch {
        Write-WarnLine ("Automatic Python install failed: {0}" -f $_.Exception.Message)
        return $false
    }

    Refresh-SessionPath
    $found = Find-PythonCommand
    if ($found) {
        Write-OkLine ("Python {0} installed via '{1}'." -f $found.Version, $found.Command)
        return $true
    }

    Write-WarnLine "Python was installed but is not on PATH yet. Restart the terminal and re-run SETUP."
    return $false
}

# ---------------------------------------------------------------------------
# RetroArch installation
# ---------------------------------------------------------------------------

function Install-RetroArchPortable {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [switch]$Force,
        [string[]]$DownloadUrls = @()
    )

    $emulatorsRoot = Ensure-Directory -Path (Join-Path $RootPath "Emulators")
    $targetPath = Join-Path $emulatorsRoot "RetroArch"
    $targetExe = Join-Path $targetPath "retroarch.exe"

    if ((-not $Force) -and (Test-Path -LiteralPath $targetExe)) {
        Write-OkLine ("RetroArch already present at {0}" -f $targetPath)
        return $targetPath
    }

    if ($DownloadUrls.Count -eq 0) {
        $resolvedDownloadUrls = @(Get-RetroArchDownloadUrls -RootPath $RootPath)
    }
    else {
        $resolvedDownloadUrls = @($DownloadUrls)
    }

    $tempArchiveBase = Get-TempPath -Name ("retroarch-{0}" -f ([guid]::NewGuid().ToString("N")))
    $tempArchivePath = ""
    $tempExtract = Get-TempPath -Name ("retroarch-extract-{0}" -f ([guid]::NewGuid().ToString("N")))

    try {
        foreach ($downloadUrl in $resolvedDownloadUrls | Select-Object -Unique) {
            try {
                $archiveExtension = [IO.Path]::GetExtension(($downloadUrl -split '\?')[0])
                if ([string]::IsNullOrWhiteSpace($archiveExtension)) {
                    $archiveExtension = ".7z"
                }

                $tempArchivePath = "{0}{1}" -f $tempArchiveBase, $archiveExtension
                Write-InfoLine ("Downloading RetroArch from {0}" -f $downloadUrl)
                Invoke-DownloadFile -Uri $downloadUrl -OutFile $tempArchivePath -TimeoutSec 300 -Retries 3

                if ([IO.Path]::GetExtension($tempArchivePath).ToLowerInvariant() -eq ".exe") {
                    if (Test-Path -LiteralPath $targetPath) {
                        Remove-Item -LiteralPath $targetPath -Recurse -Force
                    }
                    Ensure-Directory -Path $targetPath | Out-Null
                    $installProcess = Start-Process -FilePath $tempArchivePath -ArgumentList "/S", "/D=$targetPath" -Wait -PassThru
                    if ($installProcess.ExitCode -ne 0) {
                        throw ("RetroArch installer exited with code {0}." -f $installProcess.ExitCode)
                    }
                    if (-not (Test-Path -LiteralPath $targetExe)) {
                        throw "RetroArch installer completed, but retroarch.exe was not found in the target folder."
                    }
                    Write-OkLine ("RetroArch installed at {0}" -f $targetPath)
                    return $targetPath
                }

                Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
                Expand-ArchiveToPath -ArchivePath $tempArchivePath -DestinationPath $tempExtract

                $candidateExe = Get-ChildItem -Path $tempExtract -Filter "retroarch.exe" -File -Recurse | Select-Object -First 1
                if (-not $candidateExe) {
                    throw "RetroArch archive did not contain retroarch.exe."
                }

                if (Test-Path -LiteralPath $targetPath) {
                    Remove-Item -LiteralPath $targetPath -Recurse -Force
                }

                $sourceDir = Split-Path -Parent $candidateExe.FullName
                if ([IO.Path]::GetFullPath($sourceDir) -eq [IO.Path]::GetFullPath($tempExtract)) {
                    Ensure-Directory -Path $targetPath | Out-Null
                    Copy-Item -Path (Join-Path $tempExtract "*") -Destination $targetPath -Recurse -Force
                }
                else {
                    Move-Item -Path $sourceDir -Destination $targetPath
                }

                if (Get-Command Unblock-File -ErrorAction SilentlyContinue) {
                    Get-ChildItem -Path $targetPath -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
                }

                Write-OkLine ("RetroArch installed at {0}" -f $targetPath)
                return $targetPath
            }
            catch {
                Write-WarnLine ("Could not install RetroArch from {0}: {1}" -f $downloadUrl, $_.Exception.Message)
                if ($tempArchivePath) {
                    Remove-Item -LiteralPath $tempArchivePath -Force -ErrorAction SilentlyContinue
                }
                Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $targetPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        throw "RetroArch could not be installed from any configured source. Check your internet connection and retry."
    }
    finally {
        if ($tempArchivePath) {
            Remove-Item -LiteralPath $tempArchivePath -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-RetroArchCores {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [switch]$Force,
        [string[]]$OnlyCores = @()
    )

    $retroArchRoot = Join-Path $RootPath "Emulators\RetroArch"
    $retroArchExe = Join-Path $retroArchRoot "retroarch.exe"
    if (-not (Test-Path -LiteralPath $retroArchExe)) {
        Write-WarnLine "RetroArch is not installed, so core download was skipped."
        return [pscustomobject]@{ Downloaded = 0; Skipped = 0; Failed = 0; FailedNames = @() }
    }

    $coresPath = Ensure-Directory -Path (Join-Path $retroArchRoot "cores")
    $downloaded = 0
    $skipped = 0
    $failed = 0
    $failedNames = New-Object System.Collections.Generic.List[string]

    $wanted = @($script:DefaultCoreDefinitions)
    if ($OnlyCores.Count -gt 0) {
        $lowered = @($OnlyCores | ForEach-Object { $_.ToLowerInvariant() })
        $wanted = @($wanted | Where-Object { $lowered -contains $_.Name.ToLowerInvariant() })
    }

    foreach ($core in $wanted) {
        $coreName = $core.Name
        $coreFile = "{0}_libretro.dll" -f $coreName
        $targetFile = Join-Path $coresPath $coreFile
        $downloadUrl = "https://buildbot.libretro.com/nightly/windows/x86_64/latest/{0}.zip" -f $coreFile

        if ((-not $Force) -and (Test-Path -LiteralPath $targetFile)) {
            Write-OkLine ("{0} core already present" -f $core.Desc)
            $skipped++
            continue
        }

        $tempZip = Get-TempPath -Name ("{0}-{1}.zip" -f $coreName, ([guid]::NewGuid().ToString("N")))
        try {
            Write-InfoLine ("Downloading {0}" -f $core.Desc)
            Invoke-DownloadFile -Uri $downloadUrl -OutFile $tempZip -TimeoutSec 120 -Retries 3
            Expand-ArchiveToPath -ArchivePath $tempZip -DestinationPath $coresPath

            if (-not (Test-Path -LiteralPath $targetFile)) {
                throw ("{0} did not extract correctly." -f $coreFile)
            }

            if (Get-Command Unblock-File -ErrorAction SilentlyContinue) {
                Unblock-File -Path $targetFile -ErrorAction SilentlyContinue
            }

            Write-OkLine ("Installed {0}" -f $core.Desc)
            $downloaded++
        }
        catch {
            Write-WarnLine ("Failed to install {0}: {1}" -f $core.Desc, $_.Exception.Message)
            $failed++
            $failedNames.Add($coreName)
        }
        finally {
            Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
        }
    }

    return [pscustomobject]@{
        Downloaded  = $downloaded
        Skipped     = $skipped
        Failed      = $failed
        FailedNames = $failedNames.ToArray()
    }
}

# ---------------------------------------------------------------------------
# Configuration & folder structure
# ---------------------------------------------------------------------------

function Ensure-PortableFolders {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    foreach ($folder in @("Emulators", "ROMs", "Save States", "Screenshots", "Backups", "Logs", "Configs", "Launcher", "Tools")) {
        Ensure-Directory -Path (Join-Path $RootPath $folder) | Out-Null
    }

    $systems = Get-SystemsConfig -RootPath $RootPath
    if ($systems.Count -eq 0) {
        foreach ($folder in @("NES", "SNES", "N64", "GameBoy", "GBA", "NDS", "Genesis", "MasterSystem", "GameGear", "PlayStation", "Arcade", "NeoGeo", "Atari2600", "Dreamcast", "PSP")) {
            Ensure-Directory -Path (Join-Path $RootPath ("ROMs\{0}" -f $folder)) | Out-Null
        }
    }
    else {
        foreach ($system in $systems) {
            $folderName = [string](Get-ObjectProperty -InputObject $system -Name "folder" -Default "")
            if ($folderName) {
                Ensure-Directory -Path (Join-Path $RootPath ("ROMs\{0}" -f $folderName)) | Out-Null
            }
        }
    }

    Write-OkLine "Portable folder structure is ready."
}

function Configure-RetroArch {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    Ensure-PortableFolders -RootPath $RootPath

    $retroArchRoot = Join-Path $RootPath "Emulators\RetroArch"
    if (-not (Test-Path -LiteralPath $retroArchRoot)) {
        Write-WarnLine "RetroArch configuration skipped because the installation folder is missing."
        return
    }

    foreach ($sub in @("system", "cores", "logs", "playlists", "config")) {
        Ensure-Directory -Path (Join-Path $retroArchRoot $sub) | Out-Null
    }

    # Main config (keep one backup of any user-modified file).
    $configSource = Join-Path $RootPath "Configs\retroarch.cfg"
    $configTarget = Join-Path $retroArchRoot "retroarch.cfg"
    if (Test-Path -LiteralPath $configSource) {
        if ((Test-Path -LiteralPath $configTarget)) {
            try {
                $existing = Get-FileHash -LiteralPath $configTarget -Algorithm SHA256 -ErrorAction Stop
                $incoming = Get-FileHash -LiteralPath $configSource -Algorithm SHA256 -ErrorAction Stop
                if ($existing.Hash -ne $incoming.Hash) {
                    Copy-Item -LiteralPath $configTarget -Destination ("{0}.previous" -f $configTarget) -Force
                }
            }
            catch {
            }
        }
        Copy-Item -LiteralPath $configSource -Destination $configTarget -Force
        Write-OkLine "Applied RetroArch configuration."
    }

    # Core options (previously never installed - now copied to both known locations).
    $coreOptionsSource = Join-Path $RootPath "Configs\core-options.cfg"
    if (Test-Path -LiteralPath $coreOptionsSource) {
        foreach ($dest in @(
            (Join-Path $retroArchRoot "config\retroarch-core-options.cfg"),
            (Join-Path $retroArchRoot "retroarch-core-options.cfg")
        )) {
            try {
                Ensure-Directory -Path (Split-Path -Parent $dest) | Out-Null
                Copy-Item -LiteralPath $coreOptionsSource -Destination $dest -Force
            }
            catch {
            }
        }
        Write-OkLine "Applied core options."
    }

    # Controller autoconfig profiles (RetroArch requires <driver>/ subfolders).
    $autoConfigSource = Join-Path $RootPath "Configs\autoconfig"
    $autoConfigTarget = Join-Path $retroArchRoot "autoconfig"
    if (Test-Path -LiteralPath $autoConfigSource) {
        Ensure-Directory -Path $autoConfigTarget | Out-Null
        Copy-Item -Path (Join-Path $autoConfigSource "*") -Destination $autoConfigTarget -Recurse -Force
        # Legacy flat files (v1.x) belong under dinput/.
        Get-ChildItem -Path $autoConfigTarget -Filter "*.cfg" -File -ErrorAction SilentlyContinue | ForEach-Object {
            $dinputDir = Ensure-Directory -Path (Join-Path $autoConfigTarget "dinput")
            Move-Item -LiteralPath $_.FullName -Destination (Join-Path $dinputDir $_.Name) -Force
        }
        Write-OkLine "Installed controller autoconfig profiles."
    }

    # BIOS folder + instructions copy for discoverability.
    $systemPath = Ensure-Directory -Path (Join-Path $retroArchRoot "system")
    $biosInfo = Join-Path $RootPath "Configs\BIOS-INFO.txt"
    if (Test-Path -LiteralPath $biosInfo) {
        Copy-Item -LiteralPath $biosInfo -Destination (Join-Path $systemPath "_BIOS-INFO.txt") -Force
    }
    Write-OkLine ("BIOS folder ready at {0}" -f $systemPath)
}

function Test-BiosFiles {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $biosDir = Join-Path $RootPath "Emulators\RetroArch\system"
    $missing = New-Object System.Collections.Generic.List[string]
    $present = New-Object System.Collections.Generic.List[string]

    $systems = Get-SystemsConfig -RootPath $RootPath
    foreach ($system in $systems) {
        $folderName = [string](Get-ObjectProperty -InputObject $system -Name "folder" -Default "")
        $biosFiles = @(Get-ObjectProperty -InputObject $system -Name "bios" -Default @())
        if ($biosFiles.Count -eq 0) { continue }
        foreach ($biosFile in $biosFiles) {
            $biosName = [string]$biosFile
            if ([string]::IsNullOrWhiteSpace($biosName)) { continue }
            $label = "{0}/{1}" -f $folderName, $biosName
            if (Test-Path -LiteralPath (Join-Path $biosDir $biosName)) {
                if (-not $present.Contains($label)) { $present.Add($label) }
            }
            else {
                if (-not $missing.Contains($label)) { $missing.Add($label) }
            }
        }
    }

    return [pscustomobject]@{
        Present = $present.ToArray()
        Missing = $missing.ToArray()
    }
}

# ---------------------------------------------------------------------------
# Health audit & self-repair
# ---------------------------------------------------------------------------

function Get-RetroGamingAudit {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $retroArchExe = Join-Path $RootPath "Emulators\RetroArch\retroarch.exe"
    $coresPath = Join-Path $RootPath "Emulators\RetroArch\cores"
    $romsPath = Join-Path $RootPath "ROMs"

    $coreCount = 0
    if (Test-Path -LiteralPath $coresPath) {
        $coreCount = (Get-ChildItem -Path $coresPath -Filter "*_libretro.dll" -File -ErrorAction SilentlyContinue | Measure-Object).Count
    }

    $romCount = 0
    $romsBySystem = @{}
    if (Test-Path -LiteralPath $romsPath) {
        foreach ($dir in Get-ChildItem -Path $romsPath -Directory -ErrorAction SilentlyContinue) {
            $count = (Get-ChildItem -Path $dir.FullName -File -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
            $romsBySystem[$dir.Name] = $count
            $romCount += $count
        }
    }

    $bios = Test-BiosFiles -RootPath $RootPath
    $pythonInfo = Find-PythonCommand

    return [pscustomobject]@{
        RetroArchInstalled = (Test-Path -LiteralPath $retroArchExe)
        CoreCount          = $coreCount
        RomCount           = $romCount
        RomsBySystem       = $romsBySystem
        LauncherExists     = (Test-Path -LiteralPath (Join-Path $RootPath "Launcher\launcher.py"))
        MissingBios        = $bios.Missing
        PresentBios        = $bios.Present
        PythonCommand      = $(if ($pythonInfo) { $pythonInfo.Command } else { "" })
        PythonVersion      = $(if ($pythonInfo) { $pythonInfo.Version } else { "" })
        PygameInstalled    = $(if ($pythonInfo) { Test-PythonModule -PythonCommand $pythonInfo.Command -ModuleName "pygame" } else { $false })
        FreeDiskGB         = (Get-FreeDiskSpaceGB -Path $RootPath)
    }
}

function Repair-Installation {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [switch]$InstallMissingCores = $true
    )

    Write-Section "Auto-Repair"
    Ensure-PortableFolders -RootPath $RootPath
    Configure-RetroArch -RootPath $RootPath

    $audit = Get-RetroGamingAudit -RootPath $RootPath
    if (-not $audit.RetroArchInstalled) {
        Write-WarnLine "RetroArch is missing. Installing now..."
        Install-RetroArchPortable -RootPath $RootPath | Out-Null
        Configure-RetroArch -RootPath $RootPath
        $audit = Get-RetroGamingAudit -RootPath $RootPath
    }

    if ($InstallMissingCores -and $audit.RetroArchInstalled) {
        $coresPath = Join-Path $RootPath "Emulators\RetroArch\cores"
        $missing = @()
        foreach ($core in $script:DefaultCoreDefinitions) {
            $dll = Join-Path $coresPath ("{0}_libretro.dll" -f $core.Name)
            if (-not (Test-Path -LiteralPath $dll)) {
                $missing += $core.Name
            }
        }
        if ($missing.Count -gt 0) {
            Write-InfoLine ("Repairing {0} missing core(s)..." -f $missing.Count)
            Install-RetroArchCores -RootPath $RootPath -OnlyCores $missing | Out-Null
        }
        else {
            Write-OkLine "All emulator cores are present."
        }
    }

    return (Get-RetroGamingAudit -RootPath $RootPath)
}
