# ============================================================================
#  build.ps1 -- build the full Elden Ring Combat mod
# ----------------------------------------------------------------------------
#  Produces:
#    data/scripts/ERC_PlayerCombat.pex     (Papyrus, via the Creation Kit compiler)
#    data/SKSE/Plugins/ERC.dll             (SKSE plugin, via MSVC + the SKSE SDK)
#    data/EldenRingCombat.esp              (quest + player alias, via houseCARL MCP)
#    data/SEQ/EldenRingCombat.seq          (so the start-game-enabled quest starts)
#
#  Prerequisites:
#    * Skyrim SE/AE 1.6.1170 install (Papyrus compiler + source scripts)
#    * Creation Kit (ships Papyrus Compiler\PapyrusCompiler.exe)
#    * SKSE 2.2.6 package (Data\Scripts\Source supplies Input.psc)
#    * Visual Studio 2022 (MSVC v143)
#    * SKSE SDK clone at .\skse-sdk (https://github.com/Ez0n3/SKSE64AE-Plugins)
#
#  Usage:
#    powershell -ExecutionPolicy Bypass -File tools\build.ps1
#    powershell ... -File tools\build.ps1 -SkipSdkBuild   # SDK libs already built
# ============================================================================
[CmdletBinding()]
param(
    [string]$GamePath    = 'F:\SteamLibrary\steamapps\common\Skyrim Special Edition',
    [string]$SdkPath     = '',
    [string]$SkseScripts = '',
    [string]$VsDevCmd    = 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat',
    [string]$MsBuild     = 'C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe',
    [string]$Mo2Path     = 'F:\Modlists\JOJ',
    [switch]$SkipSdkBuild,
    [switch]$SkipEsp
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if (-not $SdkPath)     { $SdkPath     = Join-Path $root 'skse-sdk' }
if (-not $SkseScripts) { $SkseScripts = Join-Path $root 'skse64_2_02_06_gog\Data\Scripts\Source' }

function Fail($msg) { Write-Host "[build] ERROR: $msg" -ForegroundColor Red; exit 1 }
function Step($msg) { Write-Host "[build] $msg" -ForegroundColor Cyan }

# --- preflight --------------------------------------------------------------
if (-not (Test-Path $VsDevCmd)) { Fail "VsDevCmd.bat not found: $VsDevCmd" }
if (-not (Test-Path $SdkPath))  { Fail "SKSE SDK not found: $SdkPath" }

$papyrus = Join-Path $GamePath 'Papyrus Compiler\PapyrusCompiler.exe'
if (-not (Test-Path $papyrus)) { Fail "PapyrusCompiler.exe not found: $papyrus" }

$flags       = Join-Path $GamePath 'Data\Source\Scripts\TESV_Papyrus_Flags.flg'
$gameScripts = Join-Path $GamePath 'Data\Source\Scripts'
if (-not (Test-Path $flags)) { Fail "TESV_Papyrus_Flags.flg not found: $flags" }

if (-not (Test-Path $SkseScripts)) {
    Fail ("SKSE source scripts not found: {0} (needed for Input.psc; pass -SkseScripts)" -f $SkseScripts)
}

$outBuild = Join-Path $root 'build'
$outObj   = Join-Path $outBuild 'obj'
$outPex   = Join-Path $outBuild 'Scripts'
$outDll   = Join-Path $root 'data\SKSE\Plugins'

# MCM Helper's public base scripts, needed only to compile ERC_MCM.psc (which
# extends MCM_ConfigBase). The running copies come from MCMHelper.bsa.
$mcmVendor = Join-Path $PSScriptRoot 'vendor\mcm-helper'
if (-not (Test-Path (Join-Path $mcmVendor 'MCM_ConfigBase.psc'))) {
    Fail "MCM Helper public scripts missing from $mcmVendor (see its README)"
}
foreach ($d in @($outBuild, $outObj, $outPex, $outDll)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force $d | Out-Null }
}

# --- 1. Papyrus -------------------------------------------------------------
Step 'Compiling Papyrus...'
$src = Join-Path $root 'data\scripts\source'

# Global natives must be called through their script (ERC_PlayerCombat.X); the
# rewrite is idempotent and --check style, so a hand-written bare call fails
# rather than compiling into a runtime "unbound native" error.
& py (Join-Path $PSScriptRoot 'qualify-natives.py') 2>&1 | ForEach-Object { Write-Host "        $_" }
if ($LASTEXITCODE -ne 0) { Fail 'native call qualification failed' }

$pexArgs = @(
    "-f=$flags"
    "-i=$src;$mcmVendor;$SkseScripts;$gameScripts"
    "-o=$outPex"
)
Push-Location $src
try {
    # The compiler takes exactly one file per invocation.
    foreach ($script in @('ERC_PlayerCombat.psc', 'ERC_MCM.psc')) {
        Write-Host "        $script"
        & $papyrus $script @pexArgs 2>&1 | ForEach-Object { Write-Host "        $_" }
        if ($LASTEXITCODE -ne 0) { Fail "Papyrus compilation failed: $script" }
    }
}
finally { Pop-Location }

foreach ($name in @('ERC_PlayerCombat', 'ERC_MCM')) {
    $builtPex = Join-Path $outPex "$name.pex"
    if (-not (Test-Path $builtPex)) { Fail "$name.pex was not produced" }
    Copy-Item $builtPex (Join-Path $root "data\scripts\$name.pex") -Force
}
Step 'Papyrus OK -> data\scripts\ERC_PlayerCombat.pex, ERC_MCM.pex'

# --- 1b. MCM menu -----------------------------------------------------------
# MCM Helper skips a config it cannot read without logging anything, which makes
# a schema slip look exactly like "the mod does nothing". Catch it here.
Step 'Validating the MCM menu...'
& py (Join-Path $PSScriptRoot 'validate-mcm.py') 2>&1 | ForEach-Object { Write-Host "        $_" }
if ($LASTEXITCODE -ne 0) { Fail 'MCM config validation failed' }

# --- 2. SKSE SDK static libraries ------------------------------------------
$libDir  = Join-Path $SdkPath 'skse64_plugins\ez_skse64ae_plugin_example\Builds\Release'
$mainLib = Join-Path $libDir 'skse64_0x01064920.lib'

if (-not $SkipSdkBuild -and -not (Test-Path $mainLib)) {
    Step 'Building SKSE SDK static libraries (one-off, this takes a few minutes)...'
    if (-not (Test-Path $MsBuild)) { Fail "MSBuild not found: $MsBuild" }
    $sln = Join-Path $SdkPath 'skse64_plugins\ez_skse64ae_plugin_example\ez_skse64ae_plugin_example.sln'
    & $MsBuild $sln /p:Configuration=Release /p:Platform=x64 /t:Build /m /v:m /nologo 2>&1 |
        Select-Object -Last 5 | ForEach-Object { Write-Host "        $_" }
    if (-not (Test-Path $mainLib)) { Fail "SDK build did not produce $mainLib" }
}

$libs = @('skse64_0x01064920.lib', 'common_vc14.lib', 'skse64_common.lib') |
        ForEach-Object { Join-Path $libDir $_ }
foreach ($l in $libs) {
    if (-not (Test-Path $l)) { Fail "missing SDK library: $l (omit -SkipSdkBuild)" }
}

# --- 3. ERC.dll -------------------------------------------------------------
# A temporary batch file keeps the MSVC quoting simple.
Step 'Building ERC.dll...'
$bat = Join-Path $outBuild 'build-dll.bat'
$libArgs = ($libs | ForEach-Object { '"{0}"' -f $_ }) -join ' '
$clLine = 'cl /nologo /std:c++17 /EHsc /O2 /LD /D_CRT_SECURE_NO_WARNINGS /FI"common/IPrefix.h" ' +
          ('/I "{0}\plugin\include" /I "{1}" /I "{1}\skse64" /I "{1}\skse64\skse64" /I "{1}\skse64\skse64_common" ' -f $root, $SdkPath) +
          ('"{0}\plugin\src\ERCMain.cpp" "{0}\plugin\src\ERCPlugin.cpp" "{0}\plugin\src\ERCNatives.cpp" ' -f $root) +
          ('/Fo:"{0}\\" /Fe:"{1}\ERC.dll" ' -f $outObj, $outDll) +
          ('/link /MACHINE:X64 /LTCG {0}' -f $libArgs)

$lines = @(
    '@echo off'
    ('call "{0}" -arch=x64 -no_logo >nul 2>&1' -f $VsDevCmd)
    $clLine
)
   Set-Content -Path $bat -Value $lines -Encoding ASCII

   # Delete the previous DLL first: cl does not remove its output on failure, so
   # a stale binary would otherwise survive a failed compile and get shipped as
   # though the build had succeeded (that is exactly how a missing native can
   # reach the game and abort OnInit).
   $dll = Join-Path $outDll 'ERC.dll'
   Remove-Item $dll -Force -ErrorAction SilentlyContinue

   $dllOut = cmd /c "`"$bat`"" 2>&1
   $dllCode = $LASTEXITCODE
   $dllOut | Where-Object { $_ -notmatch '^\s*$' } | ForEach-Object { Write-Host "        $_" }
   if ($dllCode -ne 0) { Fail "ERC.dll compilation failed (cl exit $dllCode)" }

   # Link intermediates are not part of the shipped mod.
   foreach ($junk in @('ERC.lib', 'ERC.exp')) {
       Remove-Item (Join-Path $outDll $junk) -Force -ErrorAction SilentlyContinue
   }

   if (-not (Test-Path $dll)) { Fail 'ERC.dll was not produced' }

# --- 4. EldenRingCombat.esp -------------------------------------------------
# The quest record is what attaches ERC_PlayerCombat to the player alias; no
# SKSE/Papyrus API can do that at runtime. Authoring goes through the houseCARL
# MCP server and is verified by two independent parsers (see build_esp.ps1).
$esp = Join-Path $root 'data\EldenRingCombat.esp'
if (-not $SkipEsp) {
    # Built by our own generator rather than the houseCARL MCP round trip: the
    # record layout is now pinned by xEdit-verified bytes, and the file has two
    # quests (player alias + MCM registration), which the generator keeps in
    # lockstep with the SEQ.
    Step 'Authoring EldenRingCombat.esp...'
    & py (Join-Path $PSScriptRoot 'esp\build_esp.py') 2>&1 | ForEach-Object { Write-Host "        $_" }
    if ($LASTEXITCODE -ne 0) { Fail 'ESP build failed' }
}
elseif (-not (Test-Path $esp)) {
    Fail 'data\EldenRingCombat.esp is missing (omit -SkipEsp to build it)'
}

# Regardless of which authoring path produced the file, repair the two defects
# that make a quest plugin silently dead (Start Game Enabled bit, GRUP size) and
# then prove it. Both are checked against vanilla records by the scripts, not
# taken on trust: a wrong Start Game Enabled bit leaves the mod "installed but
# dead", with no rolls, no hit-stop and no MCM entry, and nothing in any log.
Step 'Repairing/verifying the quest record...'
& py (Join-Path $PSScriptRoot 'esp\patch-quest-flags.py') $esp 2>&1 | ForEach-Object { Write-Host "        $_" }
if ($LASTEXITCODE -ne 0) { Fail 'quest record repair failed' }

& py (Join-Path $PSScriptRoot 'inspect-plugin.py') $esp 2>&1 | ForEach-Object { Write-Host "        $_" }
if ($LASTEXITCODE -ne 0) { Fail 'plugin structure check failed' }

# --- report -----------------------------------------------------------------
$shippedPex = Join-Path $root 'data\scripts\ERC_PlayerCombat.pex'
Step 'Done.'
Write-Host ''
Write-Host ('  data\scripts\ERC_PlayerCombat.pex   {0} bytes' -f (Get-Item $shippedPex).Length)
Write-Host ('  data\SKSE\Plugins\ERC.dll           {0} bytes' -f (Get-Item $dll).Length)
Write-Host ('  data\EldenRingCombat.esp            {0} bytes' -f (Get-Item $esp).Length)
$seq = Join-Path $root 'data\SEQ\EldenRingCombat.seq'
if (Test-Path $seq) {
    Write-Host ('  data\SEQ\EldenRingCombat.seq        {0} bytes' -f (Get-Item $seq).Length)
}
Write-Host ''
Write-Host '  Install: copy data\ into the game Data folder, or zip it as a mod'
Write-Host '  folder. See docs\BUILD.md.'
