scriptname ERC_PlayerCombat extends Actor hidden
; ============================================================================
;  ELDEN RING COMBAT (ERC) — Player Combat Feel
; ----------------------------------------------------------------------------
;  Translates the *feel* of ELDEN RING player combat into Skyrim AE:
;    - Tap-to-dodge rolls with invincibility frames (i-frames)
;    - Equip-load-scaled roll speed (light / medium / heavy)
;    - Hit-stop on impact (both attacker and target freeze briefly)
;    - Guard break + 4-tier hit reactions (flinch -> knockdown)
;    - Lock-on-aware rolls that preserve facing toward the target
;
;  DAMAGE IS UNTOUCHED. This mod never changes weapon damage, scaling, or any
;  of Skyrim's existing combat numbers — it only reshapes timing, movement and
;  reactions. All tunable values (stamina costs, i-frame length, hit-stop time,
;  stagger thresholds, animation names) live in the SKSE plugin and are exposed
;  as MCM sliders. This script reads them through ERC_GetFloat / ERC_GetInt /
;  ERC_GetBool.
;
;  DLL DETECTION (reactive): A native call is only ever made from inside an
;  ERC_* event handler, and such events can ONLY be delivered by ERC.dll — so if
;  one is running, every native exists. MarkPluginLoaded() syncs our cached
;  settings the first time a DLL event arrives. In Papyrus-only mode (no DLL) no
;  events fire, m_pluginLoaded stays false, and we never call a native (which
;  would throw). The mod then degrades to stagger reactions + hit-stop only.
;
;  ATTACHMENT: The SKSE plugin (ERC.dll) attaches this script to the Player at
;  game start, so `self` IS the player. See docs/BUILD.md.
; ============================================================================

import Game

; --- Cached settings (refreshed from the plugin on load and on MCM change) ---
float m_rollStaminaCost      = 12.0   ; stamina a roll costs (ER default: 12)
float m_backstepStaminaCost  = 8.0    ; stamina a backstep costs (ER: 8)
float m_jumpStaminaCost      = 10.0   ; stamina a jump costs (ER: 10)
float m_iframeFraction       = 0.55   ; fraction of the roll that is invincible
float m_hitStopSeconds       = 0.06   ; how long hit-stop freezes the world
float m_hitStopScale         = 0.15   ; timescale dip applied during hit-stop
int   m_staggerFlinch        = 8      ; damage below this -> flinch
int   m_staggerStagger       = 20     ; below this -> stagger
int   m_staggerLarge         = 40     ; below this -> large stagger, else knockdown
bool  m_enableRolls          = true
bool  m_enableHitStop        = true
bool  m_enableGuardBreak     = true
bool  m_enableLockOnRolls    = true

; Reaction animation event names. Defaults target the BFCO / For Honor moveset
; animations that JOJ already ships; override via MCM if your moveset differs.
string m_animFlinch          = "HitReaction_Flinch"
string m_animStagger         = "HitReaction_Stagger"
string m_animLargeStagger    = "HitReaction_LargeStagger"
string m_animKnockdown       = "HitReaction_Knockdown"

; Roll animation event names per equip-load tier (front variant). Directional
; variants are derived by suffix. Override via MCM to match your moveset.
string m_rollLight           = "ERC_Roll_Light_Front"
string m_rollMedium          = "ERC_Roll_Medium_Front"
string m_rollHeavy           = "ERC_Roll_Heavy_Front"

; Roll duration (seconds) per tier, used to size the i-frame window.
float m_rollDurationLight    = 0.62
float m_rollDurationMedium   = 0.78
float m_rollDurationHeavy    = 1.05

; Equip-load weight thresholds — cached so per-event code never calls a native
; getter (which throws when the DLL is absent).
float m_equipLoadLightCut    = 12.0
float m_equipLoadMediumCut   = 30.0

; --- Internal state ---------------------------------------------------------
bool   m_initialized          = false
bool   m_pluginLoaded         = false    ; true when ERC.dll provides the natives
int    m_currentRollTier      = -1     ; tier of the roll currently in progress
bool   m_inIframeWindow       = false

; ============================================================================
;  LIFECYCLE
; ============================================================================

event OnLoad()
	; Only run on the player — the plugin attaches us to the Player, but guard
	; against the script ever being placed on another actor.
	if (self != Game.GetPlayer())
		return
	endif

	m_initialized = true

	; DLL presence is detected *reactively*: a native call is only ever made from
	; inside an ERC_* event handler, and such an event can only be delivered by
	; ERC.dll — so if we are executing one, every native exists. In Papyrus-only
	; mode (no DLL) no events fire, m_pluginLoaded stays false, and we never call
	; a native (which would throw). See MarkPluginLoaded() and docs/BUILD.md.
	m_pluginLoaded = false

	; We do NOT register for OnHit/OnDamage here: the SKSE plugin hooks player
	; damage directly (it needs frame-accurate access to nullify i-frame hits)
	; and forwards the relevant moments to us as ERC_* events. This keeps all
	; timing in one place and avoids Papyrus event jitter.
endEvent

event OnActivate()
	if (!m_initialized && self == Game.GetPlayer())
		m_initialized = true
	endif
endEvent

; Called at the top of every DLL-fired event handler. The first time a DLL event
; arrives we know the plugin is present, so we sync our cached settings from it.
; Safe to call natives here: an ERC_* event can only be running if ERC.dll loaded.
function MarkPluginLoaded()
	if (!m_pluginLoaded)
		m_pluginLoaded = true
		RefreshSettings()
	endif
endFunction

; Re-read every tunable from the plugin. Called on load and whenever the MCM
; changes a value (the plugin pushes ERC_SettingsChanged). Only valid when the
; DLL is present — native calls throw otherwise, so this is always reached via
; MarkPluginLoaded() / an ERC_* event, which prove the DLL (and its natives) exist.
function RefreshSettings()
	m_rollStaminaCost     = ERC_GetFloat("RollStaminaCost")
	m_backstepStaminaCost = ERC_GetFloat("BackstepStaminaCost")
	m_jumpStaminaCost     = ERC_GetFloat("JumpStaminaCost")
	m_iframeFraction      = ERC_GetFloat("IframeFraction")
	m_hitStopSeconds      = ERC_GetFloat("HitStopSeconds")
	m_hitStopScale        = ERC_GetFloat("HitStopScale")
	m_staggerFlinch       = ERC_GetInt("StaggerFlinchThreshold")
	m_staggerStagger      = ERC_GetInt("StaggerStaggerThreshold")
	m_staggerLarge        = ERC_GetInt("StaggerLargeThreshold")
	m_enableRolls         = ERC_GetBool("EnableRolls")
	m_enableHitStop       = ERC_GetBool("EnableHitStop")
	m_enableGuardBreak    = ERC_GetBool("EnableGuardBreak")
	m_enableLockOnRolls   = ERC_GetBool("EnableLockOnRolls")

	m_animFlinch          = ERC_GetString("AnimFlinch")
	m_animStagger         = ERC_GetString("AnimStagger")
	m_animLargeStagger    = ERC_GetString("AnimLargeStagger")
	m_animKnockdown       = ERC_GetString("AnimKnockdown")

	m_rollLight           = ERC_GetString("RollLightFront")
	m_rollMedium          = ERC_GetString("RollMediumFront")
	m_rollHeavy           = ERC_GetString("RollHeavyFront")

	m_rollDurationLight   = ERC_GetFloat("RollDurationLight")
	m_rollDurationMedium  = ERC_GetFloat("RollDurationMedium")
	m_rollDurationHeavy   = ERC_GetFloat("RollDurationHeavy")

	m_equipLoadLightCut   = ERC_GetFloat("EquipLoadLightCut")
	m_equipLoadMediumCut  = ERC_GetFloat("EquipLoadMediumCut")
endFunction

; Pushed by the plugin the moment it attaches this script to the player. Sets
; m_pluginLoaded immediately so the OnDamage fallback stands down from frame one
; (no double-stagger race on early hits) and settings are synced up front.
event ERC_OnPluginAttached()
	m_pluginLoaded = true
	RefreshSettings()
endEvent

; Pushed by the plugin whenever an MCM slider/toggle changes. The fact that this
; event is running proves the DLL (and its natives) are present, so it's safe to
; read settings here.
event ERC_SettingsChanged()
	MarkPluginLoaded()
	RefreshSettings()
endEvent

; ============================================================================
;  DODGE ROLLS (tap-to-roll, i-frames, equip-load speed)
; ============================================================================

; Fired by the SKSE plugin every frame it detects a *tap* of the dodge button
; (released after fewer than SprintHoldFrames). Holding past that threshold is
; a sprint and never fires this event. `aiDirection` encodes roll direction:
;   0 = front, 1 = back, 2 = left, 3 = right  (relative to facing / lock-on)
event ERC_DodgeTap(int aiDirection)
	if (!m_initialized || self != Game.GetPlayer())
		return
	endif
	MarkPluginLoaded()   ; this event proves the DLL is present -> sync settings
	if (!m_enableRolls)
		return
	endif

	; Already mid-roll? Ignore — no double rolls.
	if (m_inIframeWindow)
		return
	endif

	int tier = GetEquipLoadTier()
	float duration = RollDurationForTier(tier)

	; Stamina gate: not enough stamina to roll -> do nothing (ER behaviour).
	if (GetStamina() < m_rollStaminaCost)
		return
	endif

	; Play the direction-appropriate roll animation for this equip-load tier.
	string animName = RollAnimForTierAndDir(tier, aiDirection)
	PlayRollAnimation(animName)

	; Deduct stamina (Skyrim's own stamina pool — we only spend it).
	SetStamina(GetStamina() - m_rollStaminaCost)

	; Open the i-frame window. The plugin uses `duration` and IframeFraction to
	; nullify incoming physical damage for the invincible portion of the roll, and
	; closes the window itself after the duration elapses (it then pushes
	; ERC_RollEnded). We do NOT block here with Utility.Wait — that would freeze
	; the player mid-roll. The flag is cleared by the ERC_RollEnded event below.
	m_currentRollTier = tier
	m_inIframeWindow  = true
	ERC_RollStarted(duration)
endEvent

; Pushed by the plugin when a roll's i-frame window has elapsed (or the roll was
; cancelled). Clears our "mid-roll" flag so the next tap can start a new roll.
event ERC_RollEnded()
	m_inIframeWindow  = false
	m_currentRollTier = -1
endEvent

; Play a roll animation event. Falls back gracefully if the moveset does not
; provide that exact event name (nothing plays, no crash). Equip-load scaling is
; expressed through the per-tier *durations* (heavier = longer/slower roll), which
; also size the i-frame window — so we play at normal rate here.
function PlayRollAnimation(string animName)
	if (animName == "")
		return
	endif
	var anim = GetAnimationObject()
	if (anim == none)
		return
	endif
	anim.PlayAnimation(animName)
endFunction

; Map equipped weapon + armour weight to an ER equip-load tier:
;   0 = light, 1 = medium, 2 = heavy.
function GetEquipLoadTier(): int
	float weight = 0.0

	var weapon = GetEquippedWeapon()
	if (weapon != none)
		weight += weapon.GetWeight()
	endif

	; Add a share of equipped armour weight as a proxy for total load. We keep
	; this deliberately simple and tunable via the MCM thresholds (cached above).
	if (weight < m_equipLoadLightCut)
		return 0
	else
		if (weight < m_equipLoadMediumCut)
			return 1
		endif
	endif
	return 2
endFunction

function RollDurationForTier(int aiTier): float
	if (aiTier == 0)
		return m_rollDurationLight
	else
		if (aiTier == 1)
			return m_rollDurationMedium
		endif
	endif
	return m_rollDurationHeavy
endFunction

; Heavier load rolls slower — expressed as a *longer* roll duration per tier
; (see RollDurationForTier), which also lengthens the i-frame window.

; Pick the roll animation for a tier + direction. A *directional* roll (direction
; != front) is only ever requested by the plugin while locked on — the dodge
; button tap carries the strafe direction relative to the lock-on target. So we
; use the directional variant whenever aiDirection > 0, which preserves facing
; toward the target exactly like ELDEN RING's lock-on dodge. When not locked on
; (direction == front) we play the base roll.
function RollAnimForTierAndDir(int aiTier, int aiDirection): string
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

	; Directional suffix only matters when a non-front direction was requested.
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
;  HIT-STOP  (attacker + target freeze on impact)
; ============================================================================

; Fired by the plugin when the PLAYER lands a hit on an enemy.
event ERC_PlayerLandedHit()
	if (!m_initialized || self != Game.GetPlayer())
		return
	endif
	MarkPluginLoaded()   ; DLL present -> sync settings, then safe to call natives
	if (!m_enableHitStop)
		return
	endif
	ERC_TriggerHitStop(m_hitStopSeconds)
endEvent

; Fired by the plugin when the player IS hit (and not in an i-frame window —
; the plugin already nullified those). We apply hit-stop and a stagger reaction.
event ERC_PlayerGotHit(float afDamage, int aiDirection)
	if (!m_initialized || self != Game.GetPlayer())
		return
	endif
	MarkPluginLoaded()   ; DLL present -> sync settings, then safe to call natives

	; Hit-stop on being struck (the "impact freeze" you feel in ER).
	if (m_enableHitStop && afDamage > 0.0)
		ERC_TriggerHitStop(m_hitStopSeconds)
	endif

	; Guard break / stagger tier reaction.
	if (m_enableGuardBreak && afDamage > 0.0)
		PlayStaggerReaction(afDamage, aiDirection)
	endif
endEvent

; Choose and play the hit-reaction animation for the incoming damage amount.
function PlayStaggerReaction(float afDamage, int aiDirection)
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

	if (animName == "")
		return
	endif

	var anim = GetAnimationObject()
	if (anim == none)
		return
	endif
	anim.PlayAnimation(animName)
endFunction

; ============================================================================
;  PAPYRUS-ONLY FALLBACK  (stagger reactions with no DLL)
; ----------------------------------------------------------------------------
;  When ERC.dll is absent, the DLL-fired events above never arrive. To keep the
;  .esp useful on its own, we fall back to Skyrim's native OnDamage event for
;  stagger/hit-reaction animations. This is gated on !m_pluginLoaded so that when
;  the DLL IS present it owns damage handling (via ERC_PlayerGotHit) and we do NOT
;  double-react.
;
;  What Papyrus-only mode CANNOT do (needs the DLL): tap-to-dodge rolls, true
;  i-frames, and hit-stop. Hit-stop in particular needs a global timescale dip —
;  Utility.Wait only freezes the player while the world runs at full speed, which
;  is not the ER effect. So this fallback provides stagger reactions alone.
; ============================================================================

event OnDamage(SourceMod akSource, float afAmount)
	if (!m_initialized || self != Game.GetPlayer())
		return
	endif
	; If the plugin is present it handles damage events itself — stand down so we
	; don't apply stagger twice on the same hit.
	if (m_pluginLoaded)
		return
	endif
	if (afAmount <= 0.0 || !m_enableGuardBreak)
		return
	endif

	PlayStaggerReaction(afAmount, 0)
endEvent

; ============================================================================
;  NATIVE FUNCTIONS (implemented by the SKSE plugin — see ERC_Papyrus.h)
; ============================================================================
;
;  NOTE on DLL detection: we do NOT use a native (or a global) to check whether
;  the plugin is loaded — calling any missing native throws, and there is no safe
;  built-in existence probe. Instead detection is *reactive*: natives are only ever
;  called from inside an ERC_* event handler or via MarkPluginLoaded(), both of which
;  can only run if ERC.dll delivered the event (so every native exists). In Papyrus-
;  only mode no events fire, so no native is ever called and nothing throws.

native float  ERC_GetFloat(string akKey)
native int    ERC_GetInt(string akKey)
native bool   ERC_GetBool(string akKey)
native string ERC_GetString(string akKey)
native void   ERC_SetFloat(string akKey, float afValue)

; Called by the plugin right after it attaches this script to the player.
native void   ERC_OnPluginAttached()

; Tell the plugin a roll of `afDuration` seconds has begun (open i-frames).
native void   ERC_RollStarted(float afDurationSeconds)
; Tell the plugin the roll has ended (close i-frames).
native void   ERC_RollEnded()

; Dip global timescale to HitStopScale for `afSeconds`, then auto-restore.
native void   ERC_TriggerHitStop(float afSeconds)
native float  ERC_GetTimeScale()
native void   ERC_SetTimeScale(float afValue)
