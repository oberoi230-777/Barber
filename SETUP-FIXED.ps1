param(
    [switch]$SkipPython = $false,
    [switch]$SkipRetroArch = $false,
    [switch]$SkipCoreDownloads = $false,
    [switch]$QuickSetup = $false,
    [switch]$NonInteractive = $false
)

$setupScript = Join-Path $PSScriptRoot "SETUP.ps1"

if (-not (Test-Path -LiteralPath $setupScript)) {
    throw "SETUP.ps1 was not found."
}

& $setupScript @PSBoundParameters
exit $LASTEXITCODE
