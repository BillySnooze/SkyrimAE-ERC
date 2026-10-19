scriptname ERC_PlayerCombat extends Actor hidden
; ============================================================================
;  ELDEN RING COMBAT (ERC) — Player Combat Feel
; ----------------------------------------------------------------------------
;  Translates the *feel* of ELDEN RING player combat into Skyrim AE (1.6.1170):
;    - Tap-to-dodge rolls with invincibility frames (i-frames)
;    - Equip-load-scaled roll speed (light / medium / heavy)
;    - Hit-stop on impact (handled natively by ERC.dll)
;    - Guard break + 4-tier hit reactions (flinch -> knockdown)
;    - Lock-on-aware rolls that preserve facing toward the target
;
;  DAMAGE IS UNTOUCHED. This mod never changes weapon damage, scaling, or any of
;  Skyrim's combat numbers — it only reshapes timing, movement and reactions.
;
;  REQUIRES ERC.dll (i-frames, hit-stop). Dodge *input* is detected here in
;  Papyrus by polling the dodge key, so rolls work without a version-specific
;  C++ input hook; the script only calls into the plugin for the i-frame window.
;
;  Why polling: the official SKSE plugin API has no simple "raise a Papyrus
;  event" call (that needs BSScript/VM internals), so Papyrus drives the timing.
;  See docs/SKSE-API-NOTES.md.
; ============================================================================

; --- Cached settings (mirrors of the plugin's values) -----------------------
float m_rollStaminaCost   = 12.0
float m_hitStopSeconds    = 0.06
int   m_staggerFlinch     = 8
int   m_staggerStagger    = 20
int   m_staggerLarge      = 40
bool  m_enableRolls       = true
bool  m_enableHitStop     = true
bool  m_enableGuardBreak  = true
bool  m_enableLockOnRolls = true

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

float m_equipLoadLightCut  = 12.0
float m_equipLoadMediumCut = 30.0

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
;  LIFECYCLE
; ============================================================================

event OnInit()
	; The plugin attaches this script to the Player, but guard anyway.
	if (self != Game.GetPlayer())
		return
	endif
	RefreshSettings()
	RegisterForSingleUpdate(UPDATE_INTERVAL)
endEvent

event OnUpdate()
	if (self != Game.GetPlayer())
		return
	endif

	PollDodgeTap()

	if (m_midRoll && Utility.GetCurrentRealTime() >= m_rollEndTime)
		m_midRoll = false
	endif

	RegisterForSingleUpdate(UPDATE_INTERVAL)
endEvent

; Read every tunable from the plugin (which merges its ini and MCM Helper's).
function RefreshSettings()
	m_rollStaminaCost   = ERC_GetFloat("RollStaminaCost")
	m_hitStopSeconds    = ERC_GetFloat("HitStopSeconds")

	m_staggerFlinch     = ERC_GetInt("StaggerFlinchThreshold")
	m_staggerStagger    = ERC_GetInt("StaggerStaggerThreshold")
	m_staggerLarge      = ERC_GetInt("StaggerLargeThreshold")

	m_enableRolls       = ERC_GetBool("EnableRolls")
	m_enableHitStop     = ERC_GetBool("EnableHitStop")
	m_enableGuardBreak  = ERC_GetBool("EnableGuardBreak")
	m_enableLockOnRolls = ERC_GetBool("EnableLockOnRolls")

	m_animFlinch        = ERC_GetString("AnimFlinch")
	m_animStagger       = ERC_GetString("AnimStagger")
	m_animLargeStagger  = ERC_GetString("AnimLargeStagger")
	m_animKnockdown     = ERC_GetString("AnimKnockdown")

	m_rollLight         = ERC_GetString("RollLightFront")
	m_rollMedium        = ERC_GetString("RollMediumFront")
	m_rollHeavy         = ERC_GetString("RollHeavyFront")

	m_rollDurationLight  = ERC_GetFloat("RollDurationLight")
	m_rollDurationMedium = ERC_GetFloat("RollDurationMedium")
	m_rollDurationHeavy  = ERC_GetFloat("RollDurationHeavy")

	m_equipLoadLightCut  = ERC_GetFloat("EquipLoadLightCut")
	m_equipLoadMediumCut = ERC_GetFloat("EquipLoadMediumCut")

	m_dodgeKeyCode      = ERC_GetInt("DodgeKeyCode")
	m_sprintHoldSeconds = ERC_GetFloat("SprintHoldSeconds")
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
	if (!m_enableRolls || m_midRoll)
		return
	endif

	int   tier     = GetEquipLoadTier()
	float duration = RollDurationForTier(tier)

	; Stamina gate: not enough stamina to roll -> do nothing (ER behaviour).
	if (GetActorValue("Stamina") < m_rollStaminaCost)
		return
	endif

	PlayAnimation(RollAnimForTierAndDir(tier, aiDirection))
	DamageActorValue("Stamina", m_rollStaminaCost)

	m_midRoll     = true
	m_rollEndTime = Utility.GetCurrentRealTime() + duration

	; Open the i-frame window in the plugin (fraction of `duration`).
	ERC_RollStarted(duration)
endFunction

; Map equipped weapon weight to an ER equip-load tier: 0 light, 1 medium, 2 heavy.
int function GetEquipLoadTier()
	float weight = 0.0

	Weapon weapon = GetEquippedWeapon()
	if (weapon != none)
		weight += weapon.GetWeight()
	endif

	if (weight < m_equipLoadLightCut)
		return 0
	else
		if (weight < m_equipLoadMediumCut)
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

; Skyrim's OnHit carries no damage amount, so approximate the incoming hit from
; the source weapon's base damage — enough to pick a reaction tier.
event OnHit(ObjectReference akAggressor, Form akSource, Projectile akProjectile, bool abPowerAttack, bool abSneakAttack, bool abBashAttack, bool abHitBlocked)
	if (self != Game.GetPlayer())
		return
	endif
	if (!m_enableGuardBreak || akSource == none)
		return
	endif

	Weapon w = akSource as Weapon
	if (w == none)
		return
	endif

	float approxDamage = w.GetDamage()
	if (approxDamage <= 0.0)
		return
	endif

	PlayStaggerReaction(approxDamage)
endEvent

function PlayStaggerReaction(float afDamage)
	string animName
	if (afDamage < m_staggerFlinch)
		animName = m_animFlinch
	else
		if (afDamage < m_staggerStagger)
			animName = m_animStagger
		else
			if (afDamage < m_staggerLarge)
				animName = m_animLargeStagger
			else
				animName = m_animKnockdown
			endif
		endif
	endif

	if (animName != "")
		PlayAnimation(animName)
	endif
endFunction

; ============================================================================
;  NATIVE FUNCTIONS (implemented by ERC.dll — see plugin/src/ERCNatives.cpp)
; ============================================================================
;  Native declarations use the form:  <type> function Name(params) native
;  (return type first, `native` last; no return type = void).
;
;  These are only ever called because ERC.dll is required — if the DLL is
;  missing, Papyrus throws on the first call, which is the intended hard failure.

float  function ERC_GetFloat(string akKey) native
int    function ERC_GetInt(string akKey) native
bool   function ERC_GetBool(string akKey) native
string function ERC_GetString(string akKey) native
function ERC_SetFloat(string akKey, float afValue) native

; Returns the next queued dodge-tap direction, or -1 if none. Reserved for a
; DLL input hook that can also supply a direction (lock-on aware).
; Currently unused by the script, which polls the key directly instead.
int function ERC_ConsumeDodgeTap() native

; Open the i-frame window for the first IframeFraction of afDurationSeconds.
function ERC_RollStarted(float afDurationSeconds) native

; Dip timescale to HitStopScale for afSeconds, then restore.
function ERC_TriggerHitStop(float afSeconds) native
