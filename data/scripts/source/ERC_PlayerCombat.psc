scriptname ERC_PlayerCombat extends ReferenceAlias hidden
; ============================================================================
;  ELDEN RING COMBAT (ERC) — Player Combat Feel
; ----------------------------------------------------------------------------
;  Translates the *feel* of ELDEN RING player combat into Skyrim AE (1.6.1170):
;    - Hit-stop on impact (handled natively by ERC.dll)
;    - Guard break + 4-tier hit reactions (flinch -> knockdown)
;    - Equip-load-scaled roll speed, for lists without a dodge framework
;
;  THE ROLL IS USUALLY NOT ERC'S JOB. In JOJ the roll comes from TK Dodge RE +
;  I-Frame Generator + OAR animation packs, which are already installed and
;  already give ER-style rolls with real animations and i-frames. ERC detects
;  TK Dodge RE and defers to it (see m_deferDodge), because running both bills
;  the same roll twice and ERC's animation events exist in no behaviour graph.
;  ERC's own roll is the fallback for lists that have no dodge framework.
;
;  DAMAGE IS UNTOUCHED. This mod never changes weapon damage, scaling, or any of
;  Skyrim's combat numbers — it only reshapes timing, movement and reactions.
;
;  ATTACHMENT: this script is a quest ReferenceAlias script. Create a
;  start-game-enabled quest in the Creation Kit with one alias forced to the
;  Player reference, and attach ERC_PlayerCombat to that alias. See docs/BUILD.md
;  (Part A). Skyrim has no way to attach a script to the player without such a
;  plugin, and the SKSE plugin API cannot do it either.
;
;  REQUIRES ERC.dll (settings, i-frames, hit-stop).
;
;  Why polling: the official SKSE plugin API has no simple "raise a Papyrus
;  event" call (that needs BSScript/VM internals), so Papyrus drives the timing.
;  See docs/SKSE-API-NOTES.md.
; ============================================================================

; --- Cached settings (mirrors of the plugin's values) -----------------------
float m_rollStaminaCost   = 12.0
float m_hitStopSeconds    = 0.06
float m_hitStopScale      = 0.15
bool  m_enableRolls       = true
bool  m_enableHitStop     = true
bool  m_enableGuardBreak  = true
bool  m_enableLockOnRolls = true

; --- Dodge ownership --------------------------------------------------------
; JOJ's roll comes from TK Dodge RE (script-free SKSE plugin: roll clip, stamina
; cost, and — with I-Frame Generator — the invincibility window). It polls its
; own hotkey, which defaults to the same scan code ERC used, so if both run the
; player rolls twice and pays stamina twice. Deferring means ERC leaves the roll
; entirely to TK Dodge and contributes only what TK Dodge does not do: hit-stop
; and the 4-tier stagger reactions.
;
; The setting is a preference; m_tkdodgePresent is what the DLL actually found.
; ERC only defers when both are true, so a machine without TK Dodge still gets
; a working (if animation-less) roll instead of nothing.
bool  m_deferDodgeToTKdodge = true
bool  m_tkdodgePresent      = false
bool  m_deferDodge          = false

string m_animFlinch       = "HitReaction_Flinch"
string m_animStagger      = "HitReaction_Stagger"
string m_animLargeStagger = "HitReaction_LargeStagger"
string m_animKnockdown    = "HitReaction_Knockdown"

string m_rollLight        = "ERC_Roll_Light_Front"
string m_rollMedium       = "ERC_Roll_Medium_Front"
string m_rollHeavy        = "ERC_Roll_Heavy_Front"

float m_rollDurationLight  = 0.62
float m_rollDurationMedium = 0.78
float m_rollDurationHeavy  = 1.05

; Equip-load thresholds are a RATIO of carried weight to max carry weight
; (ELDEN RING: <=0.30 light, <=0.70 medium, above that heavy). Read from the
; actor values InventoryWeight / CarryWeight rather than summing per-item
; GetWeight() calls: SKSE does add Form.GetWeight(), but the ratio is what ER
; actually tiers, and the actor values never drift from the game's own
; accounting.
float m_equipLoadLightCut  = 0.30
float m_equipLoadMediumCut = 0.70

; Power attacks knock the player down only when health is below this fraction,
; so a full-health heavy hit staggers instead of flattening you.
float m_knockdownHealthFraction = 0.35

; Dodge input. Default is Left Alt (scan code 56): tap to roll, hold to sprint —
; the tap/hold split is what distinguishes a roll from Skyrim's native sprint.
; Keyboard only (Papyrus Input has no gamepad query); controller users need the
; DLL input hook ([HOOK-1] in docs/BUILD.md).
int   m_dodgeKeyCode      = 56
float m_sprintHoldSeconds = 0.25

; --- Internal state ---------------------------------------------------------
bool  m_midRoll     = false
float m_rollEndTime = 0.0
bool  m_keyWasDown  = false
float m_keyDownTime = 0.0

; How often we poll the dodge key (seconds). Small enough to catch a tap,
; large enough to keep Papyrus cost negligible.
float UPDATE_INTERVAL = 0.03

; ============================================================================
;  HIT-STOP STATE
; ============================================================================
;  Skyrim's timescale is NOT an INI setting -- it is the global variable
;  `TimeScale` in Skyrim.esm (FormID 0x0000003A, default 20.0, i.e. 20 game
;  minutes per real minute). That is what the console's `set timescale` writes,
;  and it is why Utility.SetINIFloat("fTimeScale:Gameplay", ...) does nothing:
;  there is no such game setting in Skyrim.esm. Verified by parsing the ESM
;  (GLOB 0x3A, EDID "TimeScale", FLTV 20.0).
;
;  So hit-stop is a GlobalVariable.SetValue() dip. That needs no addresses and
;  no runtime hook -- it is stable Papyrus.
;
;  Why the timing is polled in REAL time at ~frame rate: every Papyrus timer
;  (RegisterForSingleUpdate/Wait) counts *scaled* game time, so a delay
;  registered around a timescale dip is stretched by the very dip it is timing.
;  Utility.GetCurrentRealTime() is wall clock and ignores timescale and VM
;  freezes, so the deadline is absolute. HITSTOP_POLL is tiny on purpose: it
;  means "next frame", giving a frame-accurate restore without arithmetic that
;  depends on when the engine applies the dip.
int   TIME_SCALE_FORM = 0x0000003A
float HITSTOP_POLL    = 0.001

GlobalVariable m_timeScaleGlobal
bool  m_hitStopActive  = false
float m_savedTimeScale = 20.0     ; Skyrim's default; overwritten when we dip
float m_hitStopEndReal = 0.0

; ============================================================================
;  LIFECYCLE
; ============================================================================

event OnInit()
	if (!IsPlayerAlias())
		return
	endif
	RefreshSettings()
	RegisterForMenu("Mod Config")
	RegisterForSingleUpdate(UPDATE_INTERVAL)
endEvent

; Fired by the game when a save is loaded, so new MCM values take effect.
; Also restores a dip left behind by a save taken mid-hit-stop: script state and
; global values both persist in the save, so both halves of the restore survive.
event OnPlayerLoadGame()
	if (!IsPlayerAlias())
		return
	endif
	if (m_hitStopActive)
		EndHitStop()
	endif
	RefreshSettings()
	RegisterForMenu("Mod Config")
	RegisterForSingleUpdate(UPDATE_INTERVAL)
endEvent

; "Mod Config" is SkyUI's MCM. Re-reading on close is what makes the Defer Dodge
; toggle take effect without loading a save, since ownership of the roll cannot
; change while the menu is open anyway. Also a watchdog for hit-stop: Papyrus
; timers pause in menu mode, so a dip could otherwise outlive its deadline.
event OnMenuOpenCloseEvent(string asMenuName, bool abOpening)
	if (asMenuName != "Mod Config" || abOpening)
		return
	endif
	if (!IsPlayerAlias())
		return
	endif
	if (m_hitStopActive)
		EndHitStop()
	endif
	RefreshSettings()
endEvent

; Guard: this alias must actually point at the player. If it does not, every
; event below stands down rather than acting on some other actor.
bool function IsPlayerAlias()
	Actor ref = GetActorReference()
	return (ref != none) && (ref == Game.GetPlayer())
endFunction

event OnUpdate()
	if (!IsPlayerAlias())
		return
	endif

	; Hit-stop owns the loop while it is running: poll at ~frame rate in real
	; time and restore the moment the deadline passes.
	if (m_hitStopActive)
		if (Utility.GetCurrentRealTime() < m_hitStopEndReal)
			RegisterForSingleUpdate(HITSTOP_POLL)
			return
		endif
		EndHitStop()
	endif

	if (m_deferDodge)
		; TK Dodge RE owns the key; ERC must not poll it or it drains twice.
		ResetDodgeInput()
	else
		PollDodgeTap()
	endif

	if (m_midRoll && Utility.GetCurrentRealTime() >= m_rollEndTime)
		m_midRoll = false
	endif

	RegisterForSingleUpdate(UPDATE_INTERVAL)
endEvent

; ============================================================================
;  HIT-STOP
; ============================================================================

; Resolve Skyrim's TimeScale global once. GetFormFromFile is lazy on purpose:
; calling it from OnInit can race world load, and this is only needed on the
; first impact anyway.
GlobalVariable function GetTimeScaleGlobal()
	if (m_timeScaleGlobal == none)
		m_timeScaleGlobal = Game.GetFormFromFile(TIME_SCALE_FORM, "Skyrim.esm") as GlobalVariable
		if (m_timeScaleGlobal == none)
			Debug.Trace("ERC: could not resolve Skyrim.esm TimeScale (0x3A) - hit-stop disabled")
		endif
	endif
	return m_timeScaleGlobal
endFunction

; Dip the world's timescale for afSeconds of REAL time, then restore.
; A dip already in progress is left alone, so a flurry of hits produces one
; freeze rather than stacking into a long one.
function ApplyHitStop(float afSeconds)
	if (!m_enableHitStop || afSeconds <= 0.0 || m_hitStopActive)
		return
	endif

	GlobalVariable ts = GetTimeScaleGlobal()
	if (ts == none)
		return
	endif

	float prior = ts.GetValue()
	if (prior <= 0.0)
		; A non-positive timescale means something else is already messing with
		; it (or the form is not the one we think); do not multiply garbage.
		Debug.Trace("ERC: TimeScale is " + prior + " - skipping hit-stop")
		return
	endif

	m_savedTimeScale = prior
	m_hitStopActive  = true
	m_hitStopEndReal = Utility.GetCurrentRealTime() + afSeconds

	float scale = m_hitStopScale
	if (scale < 0.05)
		scale = 0.05
	elseif (scale > 1.0)
		scale = 1.0
	endif

	ts.SetValue(prior * scale)
	RegisterForSingleUpdate(HITSTOP_POLL)
endFunction

; Restore whatever timescale preceded the dip. Idempotent, so it is safe to call
; on load and on menu close as a watchdog against a stranded dip.
function EndHitStop()
	if (m_savedTimeScale > 0.0)
		GlobalVariable ts = GetTimeScaleGlobal()
		if (ts != none)
			ts.SetValue(m_savedTimeScale)
		endif
	endif
	m_hitStopActive  = false
	m_hitStopEndReal = 0.0
endFunction

; Drop any in-flight tap state. Called every update while deferring, so that
; re-enabling ERC's own roll mid-game cannot fire a tap recorded minutes ago.
function ResetDodgeInput()
	m_keyWasDown  = false
	m_keyDownTime = 0.0
	m_midRoll     = false
endFunction

; Read every tunable from the plugin (which merges its ini and MCM Helper's).
function RefreshSettings()
	; The DLL caches its settings from load time. MCM Helper writes changes to
	; Data\MCM\Settings\EldenRingCombat.ini, so without this re-read every MCM
	; slider would look inert until the game was restarted.
	ERC_PlayerCombat.ERC_ReloadSettings()
	m_rollStaminaCost   = ERC_PlayerCombat.ERC_GetFloat("RollStaminaCost")
	m_hitStopSeconds    = ERC_PlayerCombat.ERC_GetFloat("HitStopSeconds")
	m_hitStopScale      = ERC_PlayerCombat.ERC_GetFloat("HitStopScale")

	m_enableRolls       = ERC_PlayerCombat.ERC_GetBool("EnableRolls")
	m_enableHitStop     = ERC_PlayerCombat.ERC_GetBool("EnableHitStop")
	m_enableGuardBreak  = ERC_PlayerCombat.ERC_GetBool("EnableGuardBreak")
	m_enableLockOnRolls = ERC_PlayerCombat.ERC_GetBool("EnableLockOnRolls")

	m_animFlinch        = ERC_PlayerCombat.ERC_GetString("AnimFlinch")
	m_animStagger       = ERC_PlayerCombat.ERC_GetString("AnimStagger")
	m_animLargeStagger  = ERC_PlayerCombat.ERC_GetString("AnimLargeStagger")
	m_animKnockdown     = ERC_PlayerCombat.ERC_GetString("AnimKnockdown")

	m_rollLight         = ERC_PlayerCombat.ERC_GetString("RollLightFront")
	m_rollMedium        = ERC_PlayerCombat.ERC_GetString("RollMediumFront")
	m_rollHeavy         = ERC_PlayerCombat.ERC_GetString("RollHeavyFront")

	m_rollDurationLight  = ERC_PlayerCombat.ERC_GetFloat("RollDurationLight")
	m_rollDurationMedium = ERC_PlayerCombat.ERC_GetFloat("RollDurationMedium")
	m_rollDurationHeavy  = ERC_PlayerCombat.ERC_GetFloat("RollDurationHeavy")

	m_equipLoadLightCut  = ERC_PlayerCombat.ERC_GetFloat("EquipLoadLightCut")
	m_equipLoadMediumCut = ERC_PlayerCombat.ERC_GetFloat("EquipLoadMediumCut")
	m_knockdownHealthFraction = ERC_PlayerCombat.ERC_GetFloat("KnockdownHealthFraction")

	m_dodgeKeyCode      = ERC_PlayerCombat.ERC_GetInt("DodgeKeyCode")
	m_sprintHoldSeconds = ERC_PlayerCombat.ERC_GetFloat("SprintHoldSeconds")

	; Who owns the roll this session.
	m_deferDodgeToTKdodge = ERC_PlayerCombat.ERC_GetBool("DeferDodgeToTKDodge")
	m_tkdodgePresent      = ERC_PlayerCombat.ERC_HasTKDodge()
	m_deferDodge          = m_deferDodgeToTKdodge && m_tkdodgePresent

	if (m_deferDodge)
		ResetDodgeInput()
		Debug.Trace("ERC: TK Dodge RE present - deferring the roll (hit-stop + stagger only)")
	else
		Debug.Trace("ERC: running ERC's own roll (no TK Dodge RE detected)")
	endif
endFunction

; ============================================================================
;  DODGE ROLLS
; ============================================================================

; Tap detection in Papyrus: poll the dodge key and split tap (roll) from hold
; (sprint). This means dodge rolls work with no version-specific input hook.
; Directional (lock-on) rolls need the target's bearing, which Papyrus cannot
; read without TDM — so rolls default to the front variant. The DLL's
; ERC_ConsumeDodgeTap() API exists for a future input hook that can supply it.
function PollDodgeTap()
	bool  down = Input.IsKeyPressed(m_dodgeKeyCode)
	float now  = Utility.GetCurrentRealTime()

	if (down && !m_keyWasDown)
		m_keyDownTime = now            ; key went down
	else
		if (!down && m_keyWasDown)
			; Key released: a short press is a dodge tap; a long hold was a sprint.
			if ((now - m_keyDownTime) < m_sprintHoldSeconds)
				DoRoll(0)
			endif
		endif
	endif

	m_keyWasDown = down
endFunction

function DoRoll(int aiDirection)
	if (m_deferDodge)
		; TK Dodge RE performs the roll, with its own animation, stamina cost and
		; i-frames. Doing it here as well would double both.
		return
	endif

	if (!m_enableRolls || m_midRoll)
		return
	endif

	Actor player = GetActorReference()

	int   tier     = GetEquipLoadTier(player)
	float duration = RollDurationForTier(tier)

	; Stamina gate: not enough stamina to roll -> do nothing (ER behaviour).
	if (player.GetActorValue("Stamina") < m_rollStaminaCost)
		return
	endif

	player.PlayAnimation(RollAnimForTierAndDir(tier, aiDirection))
	player.DamageActorValue("Stamina", m_rollStaminaCost)

	m_midRoll     = true
	m_rollEndTime = Utility.GetCurrentRealTime() + duration

	; Open the i-frame window in the plugin (fraction of `duration`).
	ERC_PlayerCombat.ERC_RollStarted(duration)
endFunction

; Map carried weight to an ER equip-load tier: 0 light, 1 medium, 2 heavy.
; Not a per-item GetWeight() sum: ER tiers the ratio, and InventoryWeight /
; CarryWeight is the same quantity the game itself maintains.
int function GetEquipLoadTier(Actor akActor)
	float maxCarry = akActor.GetActorValue("CarryWeight")
	if (maxCarry <= 0.0)
		return 1
	endif

	float ratio = akActor.GetActorValue("InventoryWeight") / maxCarry

	if (ratio <= m_equipLoadLightCut)
		return 0
	else
		if (ratio <= m_equipLoadMediumCut)
			return 1
		endif
	endif
	return 2
endFunction

float function RollDurationForTier(int aiTier)
	if (aiTier == 0)
		return m_rollDurationLight
	else
		if (aiTier == 1)
			return m_rollDurationMedium
		endif
	endif
	return m_rollDurationHeavy
endFunction

; Heavier load rolls slower via a longer per-tier duration, which also lengthens
; the i-frame window. Directional rolls are only requested while locked on.
string function RollAnimForTierAndDir(int aiTier, int aiDirection)
	string base
	if (aiTier == 0)
		base = m_rollLight
	else
		if (aiTier == 1)
			base = m_rollMedium
		else
			base = m_rollHeavy
		endif
	endif

	if (m_enableLockOnRolls && aiDirection > 0)
		string suffix
		if (aiDirection == 1)
			suffix = "_Back"
		else
			if (aiDirection == 2)
				suffix = "_Left"
			else
				suffix = "_Right"
			endif
		endif
		return base + suffix
	endif

	return base
endFunction

; ============================================================================
;  HIT REACTIONS  (stagger tiers)
; ============================================================================

; Skyrim's Papyrus exposes no weapon damage (Weapon has no GetDamage()), so the
; reaction tier is derived from what OnHit actually reports — attack type and
; whether the hit got through a block — plus the player's health fraction.
;   0 flinch          normal hit
;   1 stagger         bash or a hit that broke your block
;   2 large stagger   power attack or sneak attack
;   3 knockdown       power attack while below KnockdownHealthFraction
; Damage-scaled reactions are what the DLL path ([HOOK-2]) would add.
event OnHit(ObjectReference akAggressor, Form akSource, Projectile akProjectile, bool abPowerAttack, bool abSneakAttack, bool abBashAttack, bool abHitBlocked)
	if (!IsPlayerAlias())
		return
	endif
	; Ignore fall damage and other sourceless hits.
	if (akSource == none)
		return
	endif

	; Impact freeze first: it is independent of the stagger tier and stays on
	; when guard-break reactions are disabled.
	ApplyHitStop(m_hitStopSeconds)

	if (!m_enableGuardBreak)
		return
	endif

	PlayStaggerReaction(ReactionTierForHit(abPowerAttack, abSneakAttack, abBashAttack, abHitBlocked))
endEvent

int function ReactionTierForHit(bool abPowerAttack, bool abSneakAttack, bool abBashAttack, bool abHitBlocked)
	int tier = 0

	if (abBashAttack || abHitBlocked)
		tier = 1
	endif
	if (abSneakAttack || abPowerAttack)
		tier = 2
	endif
	if (abPowerAttack)
		if (GetActorReference().GetActorValuePercentage("Health") < m_knockdownHealthFraction)
			tier = 3
		endif
	endif

	return tier
endFunction

function PlayStaggerReaction(int aiTier)
	string animName
	if (aiTier <= 0)
		animName = m_animFlinch
	else
		if (aiTier == 1)
			animName = m_animStagger
		else
			if (aiTier == 2)
				animName = m_animLargeStagger
			else
				animName = m_animKnockdown
			endif
		endif
	endif

	if (animName != "")
		GetActorReference().PlayAnimation(animName)
	endif
endFunction

; ============================================================================
;  NATIVE FUNCTIONS (implemented by ERC.dll — see plugin/src/ERCNatives.cpp)
; ============================================================================
;  Native declarations use the form:  <type> function Name(params) global native
;  (return type first, `global native` last; no return type = void).
;
;  `global` is not optional here. SKSE registers every function in ERCNatives.cpp
;  through NativeFunctionN<StaticFunctionTag, ...>, and that template hands the
;  VM an isStatic flag taken from StaticFunctionTag — so the DLL's functions are
;  static, and a script function without `global` is a *member* function. The
;  VM refuses to bind a static native to a member declaration and logs
;  "Native static function ERC_X could find no matching static function"; every
;  call then throws at runtime. Calls therefore also have to be qualified with
;  the script name.
;
;  These are only ever called because ERC.dll is required — if the DLL is
;  missing, Papyrus throws on the first call, which is the intended hard failure.

float  function ERC_GetFloat(string akKey) global native
int    function ERC_GetInt(string akKey) global native
bool   function ERC_GetBool(string akKey) global native
string function ERC_GetString(string akKey) global native
function ERC_SetFloat(string akKey, float afValue) global native

; Returns the next queued dodge-tap direction, or -1 if none. Reserved for a
; DLL input hook that can also supply a direction (lock-on aware).
; Currently unused by the script, which polls the key directly instead.
int function ERC_ConsumeDodgeTap() global native

; True when TK Dodge RE is installed (ERC.dll looks for its ini). When it is,
; ERC defers the roll to it and only contributes hit-stop and stagger.
bool function ERC_HasTKDodge() global native

; Open the i-frame window for the first IframeFraction of afDurationSeconds.
function ERC_RollStarted(float afDurationSeconds) global native
; Re-reads both ini files (plugin defaults + MCM Helper user settings).
function ERC_ReloadSettings() global native
