Set-StrictMode -Version Latest

$script:DefaultRetroArchUrls = @(
    "https://buildbot.libretro.com/stable/1.22.2/windows/x86_64/RetroArch.7z",
    "https://buildbot.libretro.com/stable/1.22.2/windows-msvc2010/x86_64/RetroArch.7z",
    "https://buildbot.libretro.com/stable/1.22.2/windows/x86_64/RetroArch-Win64-setup.exe",
    "https://buildbot.libretro.com/nightly/windows/x86_64/RetroArch.7z",
    "https://buildbot.libretro.com/nightly/windows/x86_64/RetroArch-Win64-setup.exe"
)
$script:DefaultCoreDefinitions = @(
    @{ Name = "fceumm"; Desc = "Nintendo (NES)" },
    @{ Name = "snes9x"; Desc = "Super Nintendo" },
    @{ Name = "gambatte"; Desc = "Game Boy / Game Boy Color" },
    @{ Name = "mgba"; Desc = "Game Boy Advance" },
    @{ Name = "genesis_plus_gx"; Desc = "Sega Genesis / Master System / Game Gear" },
    @{ Name = "pcsx_rearmed"; Desc = "PlayStation 1" },
    @{ Name = "mupen64plus_next"; Desc = "Nintendo 64" },
    @{ Name = "mame2003_plus"; Desc = "Arcade (MAME)" },
    @{ Name = "fbneo"; Desc = "Neo Geo / Arcade" },
    @{ Name = "stella"; Desc = "Atari 2600" },
    @{ Name = "flycast"; Desc = "Sega Dreamcast" },
    @{ Name = "ppsspp"; Desc = "PlayStation Portable" }
)

function Write-StatusLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    Write-Host $Message -ForegroundColor $Color
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

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    return $Path
}

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

function Get-TempPath {
    param([Parameter(Mandatory = $true)][string]$Name)

    return Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath $Name
}

function Get-RetroArchDownloadUrls {
    $urls = [System.Collections.Generic.List[string]]::new()

    try {
        Set-DownloadSecurityProtocol
        $response = Invoke-WebRequest -Uri "https://www.retroarch.com/?page=platforms" -UseBasicParsing -ErrorAction Stop
        $content = $response.Content

        $stableVersion = $null
        if ($content -match 'current stable version is:\s*([0-9.]+)') {
            $stableVersion = $Matches[1]
        }

        if (-not $stableVersion -and $content -match 'buildbot\.libretro\.com/stable/([0-9.]+)/windows/x86_64/RetroArch\.7z') {
            $stableVersion = $Matches[1]
        }

        if ($stableVersion) {
            $urls.Add(("https://buildbot.libretro.com/stable/{0}/windows/x86_64/RetroArch.7z" -f $stableVersion))
            $urls.Add(("https://buildbot.libretro.com/stable/{0}/windows-msvc2010/x86_64/RetroArch.7z" -f $stableVersion))
            $urls.Add(("https://buildbot.libretro.com/stable/{0}/windows/x86_64/RetroArch-Win64-setup.exe" -f $stableVersion))
            $urls.Add(("https://buildbot.libretro.com/stable/{0}/windows-msvc2010/x86_64/RetroArch-MSVC10-Win64-setup.exe" -f $stableVersion))
        }
    }
    catch {
    }

    foreach ($url in $script:DefaultRetroArchUrls) {
        if (-not $urls.Contains($url)) {
            $urls.Add($url)
        }
    }

    return $urls.ToArray()
}

function Invoke-DownloadFile {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [int]$TimeoutSec = 60
    )

    Set-DownloadSecurityProtocol
    Ensure-Directory -Path (Split-Path -Parent $OutFile) | Out-Null

    $command = Get-Command Invoke-WebRequest -ErrorAction Stop
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
}

function Expand-ArchiveToPath {
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    Ensure-Directory -Path $DestinationPath | Out-Null

    $extension = [IO.Path]::GetExtension($ArchivePath).ToLowerInvariant()
    switch ($extension) {
        ".zip" {
            Expand-Archive -Path $ArchivePath -DestinationPath $DestinationPath -Force
            return
        }
        ".7z" {
            $pythonInfo = Find-PythonCommand
            if ($pythonInfo) {
                if (-not (Ensure-PythonPackage -PythonCommand $pythonInfo.Command -PackageName "py7zr" -ModuleName "py7zr" -UseUserScope)) {
                    throw "A .7z archive was downloaded, but py7zr could not be installed automatically."
                }

                & $pythonInfo.Command -c "import py7zr; archive = py7zr.SevenZipFile(r'$ArchivePath', mode='r'); archive.extractall(path=r'$DestinationPath'); archive.close()"
                if ($LASTEXITCODE -eq 0) {
                    return
                }
            }

            $tarCommand = Get-Command tar.exe -ErrorAction SilentlyContinue
            if (-not $tarCommand) {
                $tarCommand = Get-Command tar -ErrorAction SilentlyContinue
            }

            if ($tarCommand) {
                & $tarCommand.Source -xf $ArchivePath -C $DestinationPath
                if ($LASTEXITCODE -eq 0) {
                    return
                }
            }

            throw ("Could not extract {0}. Install Python with py7zr support or 7-Zip and retry." -f $ArchivePath)
        }
        default {
            throw ("Unsupported archive type: {0}" -f $extension)
        }
    }
}

function Find-PythonCommand {
    $candidates = @("python", "python3", "py")
    foreach ($candidate in $candidates) {
        try {
            $versionOutput = (& $candidate --version 2>&1 | Out-String).Trim()
            if ($versionOutput -match "Python\s+(\d+\.\d+(?:\.\d+)?)") {
                return [pscustomobject]@{
                    Command = $candidate
                    Version = $Matches[1]
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
        $upgradeArgs = @("-m", "pip", "install", "--upgrade", "pip")
        $installArgs = @("-m", "pip", "install", $candidatePackage)
        if ($UseUserScope) {
            $upgradeArgs += "--user"
            $installArgs += "--user"
        }

        & $PythonCommand @upgradeArgs *> $null
        & $PythonCommand @installArgs

        if (Test-PythonModule -PythonCommand $PythonCommand -ModuleName $ModuleName) {
            return $true
        }
    }

    return $false
}

function Install-RetroArchPortable {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [switch]$Force,
        [string[]]$DownloadUrls = $script:DefaultRetroArchUrls
    )

    $emulatorsRoot = Ensure-Directory -Path (Join-Path $RootPath "Emulators")
    $targetPath = Join-Path $emulatorsRoot "RetroArch"
    $targetExe = Join-Path $targetPath "retroarch.exe"

    if ((-not $Force) -and (Test-Path -LiteralPath $targetExe)) {
        Write-OkLine ("RetroArch already present at {0}" -f $targetPath)
        return $targetPath
    }

    $resolvedDownloadUrls = @($DownloadUrls) + (Get-RetroArchDownloadUrls)
    $tempArchiveBase = Get-TempPath -Name ("retroarch-{0}" -f ([guid]::NewGuid().ToString("N")))
    $tempArchivePath = $null
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
                Invoke-DownloadFile -Uri $downloadUrl -OutFile $tempArchivePath -TimeoutSec 300
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

        throw "RetroArch could not be installed from any configured source."
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
        [switch]$Force
    )

    $retroArchRoot = Join-Path $RootPath "Emulators\RetroArch"
    $retroArchExe = Join-Path $retroArchRoot "retroarch.exe"
    if (-not (Test-Path -LiteralPath $retroArchExe)) {
        Write-WarnLine "RetroArch is not installed, so core download was skipped."
        return [pscustomobject]@{ Downloaded = 0; Skipped = 0; Failed = 0 }
    }

    $coresPath = Ensure-Directory -Path (Join-Path $retroArchRoot "cores")
    $downloaded = 0
    $skipped = 0
    $failed = 0

    foreach ($core in $script:DefaultCoreDefinitions) {
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
            Invoke-DownloadFile -Uri $downloadUrl -OutFile $tempZip -TimeoutSec 90
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
        }
        finally {
            Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
        }
    }

    return [pscustomobject]@{
        Downloaded = $downloaded
        Skipped    = $skipped
        Failed     = $failed
    }
}

function Configure-RetroArch {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $retroArchRoot = Join-Path $RootPath "Emulators\RetroArch"
    if (-not (Test-Path -LiteralPath $retroArchRoot)) {
        Write-WarnLine "RetroArch configuration skipped because the installation folder is missing."
        return
    }

    $configSource = Join-Path $RootPath "Configs\retroarch.cfg"
    $configTarget = Join-Path $retroArchRoot "retroarch.cfg"
    if (Test-Path -LiteralPath $configSource) {
        Copy-Item -LiteralPath $configSource -Destination $configTarget -Force
        Write-OkLine "Applied RetroArch configuration."
    }

    $autoConfigSource = Join-Path $RootPath "Configs\autoconfig"
    $autoConfigTarget = Join-Path $retroArchRoot "autoconfig"
    if (Test-Path -LiteralPath $autoConfigSource) {
        Ensure-Directory -Path $autoConfigTarget | Out-Null
        Copy-Item -Path (Join-Path $autoConfigSource "*") -Destination $autoConfigTarget -Recurse -Force
        Write-OkLine "Copied controller autoconfig profiles."
    }

    $systemPath = Ensure-Directory -Path (Join-Path $retroArchRoot "system")
    Write-OkLine ("BIOS folder ready at {0}" -f $systemPath)
}

function Get-RetroGamingAudit {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $retroArchExe = Join-Path $RootPath "Emulators\RetroArch\retroarch.exe"
    $coresPath = Join-Path $RootPath "Emulators\RetroArch\cores"
    $romsPath = Join-Path $RootPath "ROMs"

    $coreCount = 0
    if (Test-Path -LiteralPath $coresPath) {
        $coreCount = (Get-ChildItem -Path $coresPath -Filter "*.dll" -File -ErrorAction SilentlyContinue | Measure-Object).Count
    }

    $romCount = 0
    if (Test-Path -LiteralPath $romsPath) {
        $romCount = (Get-ChildItem -Path $romsPath -File -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
    }

    return [pscustomobject]@{
        RetroArchInstalled = (Test-Path -LiteralPath $retroArchExe)
        CoreCount          = $coreCount
        RomCount           = $romCount
        LauncherExists     = (Test-Path -LiteralPath (Join-Path $RootPath "Launcher\launcher.py"))
    }
}

function Get-PortablePathInfo {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    return [pscustomobject]@{
        LaunchBat           = Join-Path $RootPath "LAUNCH.bat"
        SetupBat            = Join-Path $RootPath "SETUP.bat"
        DownloadRomsBat     = Join-Path $RootPath "Tools\download-roms.bat"
        OrganizeRomsScript  = Join-Path $RootPath "Tools\organize-roms.ps1"
        TestControllerBat   = Join-Path $RootPath "Tools\test-controller.bat"
        UpdateSystemBat     = Join-Path $RootPath "Tools\update-system.bat"
        LauncherScript      = Join-Path $RootPath "Launcher\launcher.py"
        DownloadRomsScript  = Join-Path $RootPath "Tools\download-roms.ps1"
        TestControllerScript = Join-Path $RootPath "Tools\test-controller.ps1"
        UpdateSystemScript  = Join-Path $RootPath "Tools\update-system.ps1"
    }
}
