# ============================================================================
#  build_esp.ps1 -- author data\EldenRingCombat.esp
# ----------------------------------------------------------------------------
#  The plugin is one quest with one alias that forces PlayerRef and carries a
#  VMAD entry attaching ERC_PlayerCombat to that alias. Nothing in the SKSE API
#  can attach a script at runtime, so this record is the only way the Papyrus
#  script runs at all, and it has to be authored as real plugin data.
#
#  Authoring is done by the houseCARL MCP server (Mutagen + the record rulebook:
#  it validates every write against the Skyrim schema before touching bytes and
#  re-reads the file after writing). Verification is done twice, by two
#  independent parsers:
#    * the skyrimck MCP server's esp_verify (esper)
#    * tools\esp\verify_esp.py (this repo's own byte reader)
#  Optionally xEdit re-reads it too (-XEditVerify), which is what the game's own
#  loader is closest to.
#
#  Usage:
#    powershell -ExecutionPolicy Bypass -File tools\esp\build_esp.ps1
#    powershell ... -File tools\esp\build_esp.ps1 -XEditVerify
#    powershell ... -File tools\esp\build_esp.ps1 -Offline   # python writer
# ============================================================================
[CmdletBinding()]
param(
    [string]$Patch      = 'EldenRingCombat',
    [string]$Mo2Path    = 'F:\Modlists\JOJ',
    [string]$DataPath   = '',
    [string]$Housecarl  = '',
    [string]$SkyrimCk   = '',
    [string]$Spec       = '',
    [switch]$Offline,
    [switch]$XEditVerify
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Fail($msg) { Write-Host "[esp] ERROR: $msg" -ForegroundColor Red; exit 1 }
function Step($msg) { Write-Host "[esp] $msg" -ForegroundColor Cyan }

if (-not $DataPath)  { $DataPath  = Join-Path $Mo2Path 'Stock Game\Data' }
if (-not $Spec)      { $Spec      = Join-Path $root 'tools\housecarl\params-create-quest.json' }

# The MCP servers are declared once, in .cursor\mcp.json, so this script reads
# its paths from there instead of carrying a second copy of them.
$mcpJson = Join-Path $root '.cursor\mcp.json'
function ServerPath($name) {
    if (-not (Test-Path $mcpJson)) { return '' }
    try {
        $cfg = Get-Content -Raw $mcpJson | ConvertFrom-Json
        $srv = $cfg.mcpServers.$name
        if ($srv -and $srv.command) { return [string]$srv.command }
    } catch { }
    return ''
}
if (-not $Housecarl) { $Housecarl = ServerPath 'housecarl' }
if (-not $SkyrimCk)  { $SkyrimCk  = ServerPath 'skyrimck' }

$repoEsp = Join-Path $root 'data\EldenRingCombat.esp'
$modDir  = Join-Path $Mo2Path ('mods\houseCARL - ' + $Patch)

# ---- offline path: the pure-python writer --------------------------------
if ($Offline) {
    Step 'offline: writing the plugin with tools\esp\build_esp.py'
    py (Join-Path $PSScriptRoot 'build_esp.py') | ForEach-Object { Write-Host "        $_" }
    if ($LASTEXITCODE -ne 0) { Fail 'build_esp.py failed' }
    Step 'offline: skipping .seq (write it from the Creation Kit)'
}
else {
    # ---- preflight -------------------------------------------------------
    foreach ($p in @($Housecarl, $SkyrimCk)) {
        if (-not $p)   { Fail 'no MCP server path (pass -Housecarl / -SkyrimCk, or edit .cursor\mcp.json)' }
        if (-not (Test-Path $p)) { Fail "MCP server not found: $p" }
    }
    if (-not (Test-Path $DataPath)) { Fail "game Data not found: $DataPath" }
    if (-not (Test-Path $Spec))     { Fail "record spec not found: $Spec" }

    $client = Join-Path $root 'tools\mcp\mcp-client.ps1'
    function Mcp($server, $tool, $paramsJson, $timeout) {
        if (-not $timeout) { $timeout = 180 }
        # Params go through a file: a JSON document with Windows paths does not
        # survive being quoted into a powershell -File argument list.
        $tmp = Join-Path $root ('build\mcp-' + $tool + '.json')
        New-Item -ItemType Directory -Force (Split-Path $tmp) | Out-Null
        Set-Content -Path $tmp -Value $paramsJson -Encoding UTF8
        $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $client,
                  '-Server', $server, '-Tool', $tool, '-ParamsFile', $tmp,
                  '-TimeoutSec', $timeout)
        $out = & powershell @args 2>&1
        $text = ($out | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { Fail "$tool failed:`n$text" }
        return $text
    }

    # houseCARL reads its MO2 instance from the environment, the same two
    # variables .cursor\mcp.json sets. Setting them here also means the child
    # process inherits them, so no JSON has to be quoted through a command line.
    if (-not $env:HouseCarl__Mo2InstanceDir) { $env:HouseCarl__Mo2InstanceDir = $Mo2Path }
    if (-not $env:HOUSECARL_DATA_DIR) {
        $env:HOUSECARL_DATA_DIR = Join-Path $env:LOCALAPPDATA 'houseCARL\data'
    }

    # houseCARL refuses a name already in Data (two plugins cannot share a
    # filename) and refuses a patch name a mod folder already holds, so the
    # previous build's outputs go first. Both paths are exactly what this script
    # writes, never anything else.
    if (Test-Path (Join-Path $DataPath "$Patch.esp")) {
        Remove-Item (Join-Path $DataPath "$Patch.esp") -Force
        Step "removed stale $Patch.esp from the game Data folder"
    }
    if (Test-Path $modDir) {
        Remove-Item $modDir -Recurse -Force
        Step "removed previous patch folder: $modDir"
    }

    # ---- author ----------------------------------------------------------
    Step "authoring $Patch.esp (houseCARL)"
    $specJson = Get-Content -Raw $Spec
    $create = Mcp $Housecarl 'housecarl_create' $specJson 240
    $create -split "`r?`n" | Where-Object { $_ -match '^(wrote|mod folder|masters|created|  Quest|  error)' } |
        ForEach-Object { Write-Host "        $_" }

    $built = Join-Path $modDir "$Patch.esp"
    if (-not (Test-Path $built)) {
        # Fall back to finding the newest copy anywhere houseCARL could have put it.
        $built = Get-ChildItem (Join-Path $Mo2Path 'mods') -Recurse -Filter "$Patch.esp" -File -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $built -or -not (Test-Path $built)) { Fail "houseCARL did not produce $Patch.esp" }
    Step "plugin written: $built"

    New-Item -ItemType Directory -Force (Split-Path $repoEsp) | Out-Null
    Copy-Item $built $repoEsp -Force

    # ---- .seq ------------------------------------------------------------
    # A Start Game Enabled quest in a non-master plugin only starts if the game
    # finds Data\SEQ\<plugin>.seq; the Creation Kit writes it on save, and
    # without it the quest (and so the alias script) silently never runs.
    Step 'writing the .seq (Start Game Enabled quest)'
    $seqParams = @{ source = $repoEsp; out_path = (Join-Path $root 'data') } | ConvertTo-Json -Compress
    $seq = Mcp $Housecarl 'housecarl_write_seq' $seqParams 120
    $seq -split "`r?`n" | Select-Object -First 6 | ForEach-Object { Write-Host "        $_" }
}

# ---- verify --------------------------------------------------------------
Step 'verifying the plugin'
$pythonOk = $true
py (Join-Path $PSScriptRoot 'verify_esp.py') 2>&1 | ForEach-Object { Write-Host "        $_" }
if ($LASTEXITCODE -ne 0) { $pythonOk = $false }

if (-not $Offline) {
    $verifyParams = @{ pluginPath = $repoEsp } | ConvertTo-Json -Compress
    $v = Mcp $SkyrimCk 'esp_verify' $verifyParams 120
    Write-Host "        skyrimck: $v"
    if ($v -notmatch '"ok":\s*true') { $pythonOk = $false }
}

if ($XEditVerify -and -not $Offline) {
    Step 'xEdit re-read (-XEditVerify)'
    Copy-Item $repoEsp (Join-Path $DataPath "$Patch.esp") -Force
    $runner = Join-Path $root 'tools\xedit\run-xedit.ps1'
    $done   = Join-Path $root 'build\esp-verify.done'
    $txt    = Join-Path $root 'build\esp-verify.txt'
    Remove-Item $done, $txt -Force -ErrorAction SilentlyContinue
    & powershell -NoProfile -ExecutionPolicy Bypass -File $runner `
        -Script (Join-Path $root 'tools\xedit\ERC_VerifyEsp.pas') `
        -Sentinel 'build\esp-verify.done' `
        -Masters 'Skyrim.esm,Update.esm,EldenRingCombat.esp' -TimeoutSec 200 |
        Select-Object -Last 1 | ForEach-Object { Write-Host "        $_" }
    if (Test-Path $txt) {
        Get-Content $txt | ForEach-Object { Write-Host "        $_" }
        if (-not (Select-String -Path $txt -Pattern 'script: ERC_PlayerCombat' -Quiet)) {
            $pythonOk = $false
        }
    } else {
        Write-Host '        xEdit produced no report' -ForegroundColor Yellow
        $pythonOk = $false
    }
    Remove-Item (Join-Path $DataPath "$Patch.esp") -Force -ErrorAction SilentlyContinue
}

if (-not $pythonOk) { Fail 'plugin verification failed' }

Step 'Done.'
Write-Host ('  data\EldenRingCombat.esp   {0} bytes' -f (Get-Item $repoEsp).Length)
$seqFile = Join-Path $root 'data\SEQ\EldenRingCombat.seq'
if (Test-Path $seqFile) {
    Write-Host ('  data\SEQ\EldenRingCombat.seq   {0} bytes' -f (Get-Item $seqFile).Length)
}
Write-Host ''
Write-Host '  Install: copy data\ over the game Data folder, or make it a mod folder'
Write-Host '  (see docs\BUILD.md, Part A).'
