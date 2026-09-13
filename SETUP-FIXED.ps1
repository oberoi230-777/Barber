# Compatibility shim (kept so older guides/links keep working).
# SETUP.ps1 already contains all fixes as of v2.0; this file simply forwards
# every argument to it.
#
#   .\SETUP-FIXED.ps1 -Unattended
# is identical to:
#   .\SETUP.ps1 -Unattended
param(
    [switch]$SkipPython = $false,
    [switch]$SkipRetroArch = $false,
    [switch]$SkipCoreDownloads = $false,
    [switch]$QuickSetup = $false,
    [switch]$NonInteractive = $false,
    [switch]$Unattended = $false,
    [switch]$InstallPython = $false,
    [switch]$IncludeSampleRoms = $false
)

$setupScript = Join-Path $PSScriptRoot "SETUP.ps1"

if (-not (Test-Path -LiteralPath $setupScript)) {
    throw "SETUP.ps1 was not found."
}

& $setupScript @PSBoundParameters
exit $LASTEXITCODE
