scriptname ERC_PlayerCombat extends ReferenceAlias hidden
; ============================================================================
;  ELDEN RING COMBAT (ERC) — Player Combat Feel
; ----------------------------------------------------------------------------
;  Translates the *feel* of ELDEN RING player combat into Skyrim AE (1.6.1170):
;    - Guard break + 4-tier hit reactions (flinch -> knockdown)
;    - Equip-load-scaled roll speed, for lists without a dodge framework
;
;  THE ROLL IS USUALLY NOT ERC'S JOB. In JOJ the roll comes from TK Dodge RE +
;  I-Frame Generator + OAR animation packs, which are already installed and
;  already give ER-style rolls with real animations and i-frames. ERC detects
;  TK Dodge RE and defers to it (see m_deferDodge).
;
;  ERC's own roll does NOT invent animation events. Skyrim discards an animation
;  event that no behaviour graph defines, and `Actor.PlayAnimation` is a Papyrus
;  error on actors ("is an Actor, and PlayAnimation should not be used"). Both
;  made earlier builds look enabled but roll nothing, so ERC now drives the
;  TK Dodge clips that ARE in this install's behaviour graph
;  (TKDodgeForward/Back/Left/Right) through Debug.SendAnimationEvent.
;
;  HIT-STOP IS NOT HERE. Skyrim's TimeScale global scales *game time* (the
;  clock and AI scheduling), not animation playback, so dipping it produced no
;  visible freeze. In JOJ, Precision owns hit-stop (MCM -> Precision -> Hitstop)
;  and does it properly by scaling each actor's animation deltaTime. ERC
;  deliberately does not fight it.
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
;  REQUIRES ERC.dll (settings store + TK Dodge detection).
;
;  Why polling: the official SKSE plugin API has no simple "raise a Papyrus
;  event" call (that needs BSScript/VM internals), so Papyrus drives the timing.
;  See docs/SKSE-API-NOTES.md.
; ============================================================================

; --- Cached settings (mirrors of the plugin's values) -----------------------
float m_rollStaminaCost   = 12.0
bool  m_enableRolls       = true
bool  m_enableGuardBreak  = false
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

; Real animation events from this install's behaviour graph. The vanilla stagger
; events are Stagger_Small / StaggerForward / Stagger_Large (verified against the
; animation data file that ships with the TK Dodge behaviour mod); there is no
; knockdown event in vanilla, so Knockdown reuses the large stagger.
;
; These are OFF by default (bEnableGuardBreak): the engine and BFCO already apply
; their own hit reactions, and firing a second stagger on top of them stacks.
string m_animFlinch       = "Stagger_Small"
string m_animStagger      = "StaggerForward"
string m_animLargeStagger = "Stagger_Large"
string m_animKnockdown    = "Stagger_Large"

; TK Dodge's own animation events. They exist whenever TK Dodge's animation
; packs / Nemesis-Pandora behaviour is installed, which is true in JOJ.
string m_rollEventForward = "TKDodgeForward"
string m_rollEventBack    = "TKDodgeBack"
string m_rollEventLeft    = "TKDodgeLeft"
string m_rollEventRight   = "TKDodgeRight"

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

; Dodge input. Default is V (scan code 47), NOT Left Alt. TK Dodge RE already
; polls Left Alt (its DodgeHotkey, scan code 56); if ERC polled the same key the
; two would both fire and you would roll twice. Tap to roll, hold to sprint.
; Keyboard only (Papyrus Input has no gamepad query); controller users need the
; DLL input hook ([HOOK-1] in docs/BUILD.md).
int   m_dodgeKeyCode      = 47
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
	if (!IsPlayerAlias())
		return
	endif
	RefreshSettings()
	RegisterForMenu("Mod Config")
	RegisterForSingleUpdate(UPDATE_INTERVAL)
endEvent

; Fired by the game when a save is loaded, so new MCM values take effect.
event OnPlayerLoadGame()
	if (!IsPlayerAlias())
		return
	endif
	RefreshSettings()
	RegisterForMenu("Mod Config")
	RegisterForSingleUpdate(UPDATE_INTERVAL)
endEvent

; "Mod Config" is SkyUI's MCM. Re-reading on close is what makes the Defer Dodge
; toggle take effect without loading a save, since ownership of the roll cannot
; change while the menu is open anyway.
event OnMenuOpenCloseEvent(string asMenuName, bool abOpening)
	if (asMenuName != "Mod Config" || abOpening)
		return
	endif
	if (!IsPlayerAlias())
		return
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
;  (Hit-stop used to live here)
; ============================================================================
;  It dipped Skyrim's TimeScale global for a few frames. That global scales game
;  TIME (clock, AI scheduling, timers), not animation playback, so the dip was
;  applied and restored correctly yet produced no visible freeze -- the feature
;  looked broken because it was. Skyrim's own Slow Time effect does not use it
;  either, and Precision implements hit-stop by scaling each actor's animation
;  deltaTime in a hook, which is the mechanism a real fix needs.
;
;  JOJ ships Precision with hitstop already enabled (0.07 s against NPCs,
;  0.035 s otherwise, 0.1x slowdown, plus camera shake), so ERC defers to it.
;  See MCM -> Precision -> Hitstop.

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

	m_enableRolls       = ERC_PlayerCombat.ERC_GetBool("EnableRolls")
	m_enableGuardBreak  = ERC_PlayerCombat.ERC_GetBool("EnableGuardBreak")
	m_enableLockOnRolls = ERC_PlayerCombat.ERC_GetBool("EnableLockOnRolls")

	m_animFlinch        = ERC_PlayerCombat.ERC_GetString("AnimFlinch")
	m_animStagger       = ERC_PlayerCombat.ERC_GetString("AnimStagger")
	m_animLargeStagger  = ERC_PlayerCombat.ERC_GetString("AnimLargeStagger")
	m_animKnockdown     = ERC_PlayerCombat.ERC_GetString("AnimKnockdown")

	m_rollEventForward  = ERC_PlayerCombat.ERC_GetString("RollEventForward")
	m_rollEventBack     = ERC_PlayerCombat.ERC_GetString("RollEventBack")
	m_rollEventLeft     = ERC_PlayerCombat.ERC_GetString("RollEventLeft")
	m_rollEventRight    = ERC_PlayerCombat.ERC_GetString("RollEventRight")

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
		Debug.Trace("ERC: TK Dodge RE present - deferring the roll (ERC owns stagger only)")
	else
		Debug.Trace("ERC: running ERC's own roll on scan code " + m_dodgeKeyCode)
	endif
endFunction

; ============================================================================
;  DODGE ROLLS
; ============================================================================

; Tap detection in Papyrus: poll the dodge key and split tap (roll) from hold
; (sprint). This means dodge rolls work with no version-specific input hook.
; Direction comes from WASD, since Papyrus cannot read the camera's bearing
; without TDM; that is enough to pick the matching TK Dodge clip.
function PollDodgeTap()
	bool  down = Input.IsKeyPressed(m_dodgeKeyCode)
	float now  = Utility.GetCurrentRealTime()

	if (down && !m_keyWasDown)
		m_keyDownTime = now            ; key went down
	else
		if (!down && m_keyWasDown)
			; Key released: a short press is a dodge tap; a long hold was a sprint.
			if ((now - m_keyDownTime) < m_sprintHoldSeconds)
				DoRoll(GetDodgeDirection())
			endif
		endif
	endif

	m_keyWasDown = down
endFunction

; Wasd scan codes: W 0x11 (17), S 0x1F (31), A 0x1E (30), D 0x20 (32).
; 0 = forward, 1 = back, 2 = left, 3 = right.
int function GetDodgeDirection()
	if (!m_enableLockOnRolls)
		return 0
	endif
	if (Input.IsKeyPressed(31))
		return 1
	endif
	if (Input.IsKeyPressed(30))
		return 2
	endif
	if (Input.IsKeyPressed(32))
		return 3
	endif
	return 0
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

	int    tier     = GetEquipLoadTier(player)
	float  duration = RollDurationForTier(tier)
	string animName = RollEventForDir(aiDirection)

	; Stamina gate: not enough stamina to roll -> do nothing (ER behaviour).
	if (player.GetActorValue("Stamina") < m_rollStaminaCost)
		return
	endif

	if (animName == "")
		Debug.Trace("ERC: no roll animation event configured for direction " + aiDirection as string)
		return
	endif

	; Debug.SendAnimationEvent, NOT Actor.PlayAnimation: the latter is a Papyrus
	; error on actors and never played anything. The event name has to exist in
	; the loaded behaviour graph; TKDodge* do, because TK Dodge's animation packs
	; are installed (verified in its animation data: TKDodgeForward/Back/Left/
	; Right). A name no behaviour defines is discarded silently.
	Debug.SendAnimationEvent(player, animName)
	player.DamageActorValue("Stamina", m_rollStaminaCost)

	m_midRoll     = true
	m_rollEndTime = Utility.GetCurrentRealTime() + duration

	; ERC still reports the window to the plugin for diagnostics / future hooks.
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

; Heavier load rolls slower via a longer per-tier duration, which is how long
; ERC keeps the roll locked out before the next one.
; Direction: 0 forward, 1 back, 2 left, 3 right.
string function RollEventForDir(int aiDirection)
	if (aiDirection == 1)
		return m_rollEventBack
	elseif (aiDirection == 2)
		return m_rollEventLeft
	elseif (aiDirection == 3)
		return m_rollEventRight
	endif
	return m_rollEventForward
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
	; Hit-stop is Precision's job now (see the note where ERC's used to live).
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
		; Same fix as the roll: SendAnimationEvent, not PlayAnimation, which
		; raises "is an Actor, and PlayAnimation should not be used" and played
		; nothing on the player.
		Debug.SendAnimationEvent(GetActorReference(), animName)
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
; ERC defers the roll to it and ERC only contributes the stagger reactions.
bool function ERC_HasTKDodge() global native

; Reports that a roll started, with the duration ERC allows before another roll.
; Nothing consumes the window yet: real i-frames need a damage hook, which this
; plugin does not install (TK Dodge RE + I-Frame Generator provide them in JOJ).
function ERC_RollStarted(float afDurationSeconds) global native
; Re-reads both ini files (plugin defaults + MCM Helper user settings).
function ERC_ReloadSettings() global native
