# ============================================================================
#  run-xedit.ps1 -- run an xEdit Pascal script headlessly
# ----------------------------------------------------------------------------
#  xEdit only loads plugins listed in a plugins.txt, so this harness writes a
#  throwaway one containing just the masters we need. It also pins the data
#  path, because this xEdit install was copied from another machine and its
#  saved settings point at paths that do not exist here.
#
#  Usage:
#    powershell -File tools\xedit\run-xedit.ps1 -Script ERC_Probe.pas
# ============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Script,
    [string]$XEditPath = 'F:\Modlists\JOJ\tools\SSEEdit\SSEEdit64.exe',
    [string]$DataPath  = 'F:\Modlists\JOJ\Stock Game\Data',
    [string[]]$Masters = @('Skyrim.esm'),
    [int]$TimeoutSec   = 180,
    [string]$Sentinel  = '',
    [string[]]$CleanBefore = @()
)

$ErrorActionPreference = 'Stop'
$root  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$build = Join-Path $root 'build'
if (-not (Test-Path $build)) { New-Item -ItemType Directory -Force $build | Out-Null }

$scriptPath = if (Test-Path $Script) { (Resolve-Path $Script).Path } else {
    Join-Path $PSScriptRoot $Script
}
if (-not (Test-Path $scriptPath)) { Write-Host "ERROR: script not found: $scriptPath"; exit 1 }
if (-not (Test-Path $XEditPath))  { Write-Host "ERROR: xEdit not found: $XEditPath"; exit 1 }
if (-not (Test-Path $DataPath))   { Write-Host "ERROR: data path not found: $DataPath"; exit 1 }

# plugins.txt: everything active, as xEdit expects.
# NOTE: with -File, PowerShell may hand an array over as a single
# "a","b" string, so split and trim defensively.
$masterList = @()
foreach ($m in $Masters) {
    foreach ($part in ($m -split ',')) {
        $clean = $part.Trim().Trim('"').Trim("'")
        if ($clean) { $masterList += $clean }
    }
}
$pluginsTxt = Join-Path $build 'xedit-plugins.txt'
($masterList | ForEach-Object { "*$_" }) | Set-Content -Path $pluginsTxt -Encoding ASCII

# xEdit's AddNewFileName refuses a name that already exists in the data path, so
# stale outputs have to go first.
foreach ($name in $CleanBefore) {
    $target = Join-Path $DataPath $name
    if (Test-Path $target) {
        Remove-Item $target -Force
        Write-Host "[xedit] removed stale: $target"
    }
}

Write-Host "[xedit] data    : $DataPath"
Write-Host "[xedit] plugins : $($Masters -join ', ')"
Write-Host "[xedit] script  : $(Split-Path -Leaf $scriptPath)"

$argsList = @(
    "-d:`"$DataPath`""
    "-p:`"$pluginsTxt`""
    "-script:`"$scriptPath`""
    '-autoexit'
)

# xEdit does not always honour -autoexit, so scripts drop a sentinel file when
# they are finished and this harness stops xEdit itself.
#
# The sentinel must be cleared BEFORE the process starts. Deleting it afterwards
# races the script: a fast script writes the sentinel in the milliseconds between
# Start-Process and the Remove-Item, the harness then deletes the only evidence it
# was waiting for, and sits until the timeout with a run that actually succeeded.
if ($Sentinel) {
    if (-not [IO.Path]::IsPathRooted($Sentinel)) { $Sentinel = Join-Path $root $Sentinel }
    Remove-Item $Sentinel -Force -ErrorAction SilentlyContinue
    Write-Host "[xedit] sentinel: $Sentinel"
}

$proc = Start-Process -FilePath $XEditPath -ArgumentList $argsList -PassThru

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$done = $false
while (-not $proc.HasExited -and (Get-Date) -lt $deadline) {
    if ($Sentinel -and (Test-Path $Sentinel)) { $done = $true; break }
    Start-Sleep -Milliseconds 400
}

if ($done) {
    # give xEdit a moment to flush its file handles, then close it
    Start-Sleep -Milliseconds 800
    try { if (-not $proc.HasExited) { $proc.Kill() } } catch {}
    Write-Host '[xedit] script finished (sentinel seen)'
    exit 0
}

if (-not $proc.HasExited) {
    Write-Host "[xedit] TIMEOUT after ${TimeoutSec}s -- killing (probably sitting on a dialog)" -ForegroundColor Red
    try { $proc.Kill() } catch {}
    exit 2
}

Write-Host "[xedit] exit code: $($proc.ExitCode)"
exit $proc.ExitCode
