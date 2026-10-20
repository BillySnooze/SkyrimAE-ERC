# ============================================================================
#  mcp-client.ps1 -- talk to a stdio MCP server without the IDE
# ----------------------------------------------------------------------------
#  Cursor has skyrimck / housecarl configured in .cursor/mcp.json, but those
#  namespaces are only injected into an agent turn after the IDE has connected
#  them. This script speaks the same JSON-RPC 2.0 over stdio directly, so the
#  servers can be used from a normal shell step (and from tools\build.ps1).
#
#  Usage:
#    powershell -File tools\mcp\mcp-client.ps1 -Server <exe> -List
#    powershell -File tools\mcp\mcp-client.ps1 -Server <exe> -Tool name -ParamsJson '{}'
# ============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Server,
    [string[]]$ServerArgs = @(),
    [string]$Tool = '',
    [string]$ParamsJson = '{}',
    [string]$ParamsFile = '',
    [switch]$List,
    [switch]$Schema,
    [string]$Match = '',
    [int]$TimeoutSec = 120,
    [string]$EnvJson = ''
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$Env = @{}
if ($EnvJson) {
    foreach ($p in ($EnvJson | ConvertFrom-Json).PSObject.Properties) { $Env[$p.Name] = $p.Value }
}

if (-not (Test-Path $Server)) { Write-Host "ERROR: server not found: $Server"; exit 1 }

$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = $Server
$psi.Arguments = ($ServerArgs -join ' ')
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.StandardOutputEncoding = [Text.Encoding]::UTF8
foreach ($k in $Env.Keys) { $psi.EnvironmentVariables[$k] = $Env[$k] }

$proc = [Diagnostics.Process]::Start($psi)
$stdin = $proc.StandardInput
$stdout = $proc.StandardOutput

$nextId = 0
function Send($obj) {
    $line = ($obj | ConvertTo-Json -Depth 20 -Compress)
    $stdin.WriteLine($line)
    $stdin.Flush()
}

function ReadResponse([int]$wantedId, [int]$timeoutSec) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    $pending = $null
    while ((Get-Date) -lt $deadline) {
        # One outstanding read at a time: re-issuing ReadLineAsync on a stream
        # with a pending read throws.
        if ($null -eq $pending) { $pending = $stdout.ReadLineAsync() }
        if (-not $pending.Wait(250)) { continue }
        $line = $pending.Result
        $pending = $null
        if ($null -eq $line) { break }
        if ($line.Trim() -eq '') { continue }
        # Some servers still use LSP-style framing; skip the headers.
        if ($line -like 'Content-Length:*') { continue }
        try { $msg = $line | ConvertFrom-Json } catch { continue }
        if ($null -ne $msg.id -and [int]$msg.id -eq $wantedId) { return $msg }
    }
    return $null
}

try {
    $nextId++
    Send @{ jsonrpc = '2.0'; id = $nextId
            method = 'initialize'
            params = @{ protocolVersion = '2024-11-05'
                        capabilities = @{}
                        clientInfo = @{ name = 'erc-build'; version = '1.0' } } }
    $init = ReadResponse $nextId $TimeoutSec
    if ($null -eq $init) { Write-Host 'ERROR: no initialize response'; exit 1 }
    Send @{ jsonrpc = '2.0'; method = 'notifications/initialized' }

    if ($List -or $Tool -eq '') {
        $nextId++
        Send @{ jsonrpc = '2.0'; id = $nextId; method = 'tools/list'; params = @{} }
        $resp = ReadResponse $nextId $TimeoutSec
        if ($null -eq $resp) { Write-Host 'ERROR: no tools/list response'; exit 1 }
        if ($Schema) {
            foreach ($t in $resp.result.tools) {
                if ($Match -and $t.name -notmatch $Match) { continue }
                Write-Host "### $($t.name)"
                Write-Host ($t.inputSchema | ConvertTo-Json -Depth 20)
            }
            exit 0
        }
        foreach ($t in $resp.result.tools) {
            Write-Host ("{0}  --  {1}" -f $t.name, ($t.description -replace '\s+', ' '))
        }
        exit 0
    }

    $nextId++
    if ($ParamsFile) { $ParamsJson = Get-Content -Raw -Path $ParamsFile }
    Send @{ jsonrpc = '2.0'; id = $nextId
            method = 'tools/call'
            params = @{ name = $Tool; arguments = ($ParamsJson | ConvertFrom-Json) } }
    $resp = ReadResponse $nextId $TimeoutSec
    if ($null -eq $resp) { Write-Host 'ERROR: no tools/call response'; exit 1 }
    if ($resp.error) { Write-Host "ERROR: $($resp.error | ConvertTo-Json -Depth 10)"; exit 1 }
    foreach ($c in $resp.result.content) {
        if ($c.type -eq 'text') { Write-Host $c.text } else { Write-Host ($c | ConvertTo-Json -Depth 10) }
    }
    exit 0
}
finally {
    try { $stdin.Close() } catch {}
    try { if (-not $proc.HasExited) { $proc.Kill() } } catch {}
}
