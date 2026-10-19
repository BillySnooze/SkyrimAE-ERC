# ============================================================================
#  validate-psc.ps1 — structural sanity check for Papyrus (.psc) sources
# ----------------------------------------------------------------------------
#  There is no Papyrus compiler outside the Creation Kit, so this performs the
#  checks that do not need one:
#    * duplicate event/function names (a hard Papyrus compile error)
#    * unbalanced Event/EndEvent and Function/EndFunction blocks
#    * known-invalid / non-Skyrim API patterns (Fallout 4 / C# style syntax)
#    * C-style `native <type> Name()` declarations (invalid Papyrus)
#
#  It is NOT a substitute for compiling in the Creation Kit.
#
#  Usage:  powershell -File tools\validate-psc.ps1 -Path data\scripts\source\ERC_PlayerCombat.psc
# ============================================================================
param(
    [Parameter(Mandatory = $true)][string]$Path
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "[psc] File not found: $Path" -ForegroundColor Red
    exit 2
}

# Strip comments (Papyrus uses ';') so commented text never trips a check.
$code = foreach ($line in Get-Content -LiteralPath $Path) {
    $t = $line
    $idx = $t.IndexOf(';')
    if ($idx -ge 0) { $t = $t.Substring(0, $idx) }
    $t
}

$errors = New-Object System.Collections.Generic.List[string]

# --- 1. Duplicate declarations ---------------------------------------------
$decls = @{}
foreach ($l in $code) {
    if ($l -match '^\s*(?:(?<ret>[A-Za-z_]\w*)\s+)?[Ff]unction\s+(?<name>[A-Za-z_]\w*)\s*\(') {
        $n = $matches['name']
        if ($decls.ContainsKey($n)) { $errors.Add("duplicate declaration: '$n' (function)") }
        else { $decls[$n] = 'function' }
    }
    elseif ($l -match '^\s*[Ee]vent\s+(?<name>[A-Za-z_]\w*)\s*\(') {
        $n = $matches['name']
        if ($decls.ContainsKey($n)) { $errors.Add("duplicate declaration: '$n' (event vs $($decls[$n]))") }
        else { $decls[$n] = 'event' }
    }
}

# --- 2. Block balance -------------------------------------------------------
$eventOpen   = ($code | Where-Object { $_ -match '^\s*[Ee]vent\s+\w+\s*\(' }).Count
$eventClose  = ($code | Where-Object { $_ -match '^\s*[Ee]ndEvent\b' }).Count
$funcOpen    = ($code | Where-Object { $_ -match '^\s*(?:[A-Za-z_]\w*\s+)?[Ff]unction\s+\w+\s*\(' }).Count
$funcNative  = ($code | Where-Object { $_ -match '^\s*(?:[A-Za-z_]\w*\s+)?[Ff]unction\s+\w+\s*\(.*\)\s+native\s*$' }).Count
$funcClose   = ($code | Where-Object { $_ -match '^\s*[Ee]ndFunction\b' }).Count

if ($eventOpen -ne $eventClose) {
    $errors.Add("unbalanced blocks: $eventOpen Event vs $eventClose EndEvent")
}
if (($funcOpen - $funcNative) -ne $funcClose) {
    $errors.Add("unbalanced blocks: $($funcOpen - $funcNative) body Function vs $funcClose EndFunction ($funcNative native)")
}

# --- 3. Known-invalid / non-Skyrim API patterns -----------------------------
$badPatterns = @(
    @{ p = '\w+\s*\(\s*\)\s*:\s*(int|float|bool|string)\b'; m = 'C#-style ": type" return annotation (Papyrus puts the type before Function)' },
    @{ p = '^\s*native\s+(int|float|bool|string|void)\s+\w+\s*\('; m = 'C-style native declaration (use: <type> Function Name(...) native)' },
    @{ p = '\bGetStamina\s*\(';        m = 'GetStamina is a Fallout 4 API; Skyrim uses GetActorValue("Stamina")' },
    @{ p = '\bSetStamina\s*\(';        m = 'SetStamina is a Fallout 4 API; Skyrim uses DamageActorValue/RestoreActorValue' },
    @{ p = '\bGetAnimationObject\s*\('; m = 'GetAnimationObject does not exist in Skyrim; use Actor.PlayAnimation' },
    @{ p = '^\s*[Ee]vent\s+OnDamage\s*\('; m = 'OnDamage is a Fallout 4 event; Skyrim uses OnHit' },
    @{ p = '\bGetUIGlobal\s*\(';       m = 'GetUIGlobal is not a Skyrim Papyrus function' },
    @{ p = '\bHasNativeFunction\s*\('; m = 'HasNativeFunction is not a Skyrim Papyrus function' }
)

$lineNo = 0
foreach ($l in $code) {
    $lineNo++
    foreach ($bp in $badPatterns) {
        if ($l -match $bp.p) { $errors.Add("line $lineNo`: $($bp.m)") }
    }
}

# --- Report -----------------------------------------------------------------
Write-Host ""
Write-Host "[psc] $Path" -ForegroundColor Cyan
Write-Host "      events=$eventOpen/$eventClose  functions=$($funcOpen - $funcNative) body + $funcNative native / $funcClose endFunction"
Write-Host "      declared members: $($decls.Count)"

if ($errors.Count -gt 0) {
    Write-Host "[psc] FAILED:" -ForegroundColor Red
    foreach ($e in $errors) { Write-Host "      - $e" -ForegroundColor Red }
    exit 1
}

Write-Host "[psc] STRUCTURE OK" -ForegroundColor Green
exit 0
