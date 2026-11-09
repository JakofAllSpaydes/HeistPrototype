--!strict
-- GHS core loop prototype: every tunable number lives here.
-- Server and client logic read these at runtime; nothing hard-codes a value from this table.
-- Change a value, let Rojo sync, press Play. No other script needs to change.

local Config = {
	------------------------------------------------------------------ Waves
	WaveBudgetBase = 8, -- enemies in wave 1
	WaveBudgetPerWave = 2, -- extra enemies per wave after the first
	SpawnInterval = 0.4, -- seconds between drip spawns
	OpeningSurgePct = 25, -- % of the wave budget spawned fast at wave start
	OpeningSurgeIntervalMult = 0.3, -- SpawnInterval multiplier during the surge
	MaxActiveEnemies = 100, -- hard cap on alive enemies; the rest of the budget queues and backfills at once as they die
	IntermissionSec = 5, -- NEXT WAVE IN countdown
	IntroSec = 5.0, -- run start sequence length (START RUN pressed -> WAVE 1); also the GET READY hold
	SkipVoteFraction = 1, -- share of players that must vote (or have AUTO SKIP on) to end the intermission early; 1 = everyone
	SkipMinIntermissionSec = 1, -- the intermission always lasts at least this long, even with every vote in
	AutoSkipWaveSec = 10, -- with AUTO SKIP on, the next wave starts this long into the current one (once it has all spawned)

	------------------------------------------------------------------ Enemies (Brief 4: the roster, Enemies.lua reads these rows)
	-- One row per archetype. hp / dmg are wave-1 bases (scaled below), speed is walk speed, range is the melee
	-- reach for melee kinds and the hold distance for ranged kinds, cooldown is seconds between attacks, scale and
	-- color make the silhouette (no enemy uses job blue, door amber or the bag colors), cash is match cash per kill.
	-- attack picks the behaviour module in src/server/Enemies/.
	Enemies = {
		{
			id = "Henchman",
			name = "HENCHMAN",
			hp = 80,
			speed = 8, -- Round 14b: speed and damage cut a third across the roster (brief: 12 / 5)
			dmg = 3.4,
			range = 4,
			cooldown = 1.0,
			scale = 1.0,
			color = "8A8F99",
			cash = 15,
			attack = "melee",
		},
		{
			id = "Runner",
			name = "RUNNER",
			hp = 45,
			speed = 15, -- (brief: 22 / 4)
			dmg = 2.7,
			range = 4,
			cooldown = 0.7,
			scale = 0.85,
			color = "D8D2C4",
			cash = 12,
			attack = "melee",
			lean = true,
		},
		-- (Round 16: the Shooter archetype was cut; its unavoidable chip damage had no counterplay.)
		{
			id = "Marksman",
			name = "MARKSMAN",
			hp = 70,
			speed = 5.4, -- (brief: 8 / 15)
			dmg = 10,
			range = 90,
			cooldown = 3.0,
			scale = 1.0,
			color = "8A2A2A",
			cash = 25,
			attack = "marksman",
		},
		{
			id = "Boomer",
			name = "BOOMER",
			hp = 150,
			speed = 5.4, -- (brief: 8 / 12; the blast itself is BoomerDamage)
			dmg = 8,
			range = 8,
			cooldown = 0,
			scale = 1.2,
			color = "E88A2A",
			cash = 25,
			attack = "boomer",
			round = true,
		},
		{
			id = "Grenadier",
			name = "GRENADIER",
			hp = 90,
			speed = 6, -- (brief: 9 / 10)
			dmg = 6.7,
			range = 40,
			cooldown = 3.5,
			scale = 1.0,
			color = "6B7A3A",
			cash = 22,
			attack = "grenadier",
			backpack = true,
		},
		{
			id = "Heavy",
			name = "HEAVY",
			hp = 450,
			speed = 4, -- (brief: 6 / 20)
			dmg = 13,
			range = 5,
			cooldown = 1.6,
			scale = 1.4,
			color = "1A1A1E",
			cash = 60,
			attack = "heavy",
			wide = true,
			noElite = true,
		},
	},
	-- Scaling: FinalHp = BaseHp x (1 + HpWaveMult)^(wave - 1) x (1 + HpPerPlayerMult x (players - 1)) x hpMult;
	-- FinalDamage = BaseDamage x (1 + DamageWaveMult)^(wave - 1) x dmgMult (hpMult / dmgMult from the run's QueueDifficulties row). Player count never changes spawn counts.
	HpWaveMult = 0.12,
	DamageWaveMult = 0.06,
	HpPerPlayerMult = 0.5,
	RetargetInterval = 1.0, -- how often an enemy re-picks its target
	EnemyCollidesWithPlayers = false, -- false: enemies walk through players and each other, never body-block
	-- Round 19c: soft separation so a crowd stays a crowd instead of one stacked enemy (no physics, steering only).
	EnemySeparationRadius = 3.5, -- studs: neighbours closer than this push each other apart (0 = off)
	EnemySeparationPush = 4, -- studs the push moves an enemy's walk target at full strength
	EnemySeparationTickSec = 0.1, -- how often the pushes are recomputed
	EnemyStepHeight = 1.5, -- Round 19: enemies step up stairs and sills this high without jumping (scaled by size)
	EnemyStuckDetourSec = 1, -- PathfindingEnabled false only (Round 18d walk): no progress this long -> sidestep + jump
	EnemyStuckTeleportSec = 8, -- PathfindingEnabled false only: still stuck after this long -> a random spawn box

	------------------------------------------------------------------ Pathfinding (brief 7, EnemyPath.lua)
	PathfindingEnabled = true, -- false = the Round 18d straight MoveTo everywhere (A / B)
	DirectRange = 30, -- studs: within this and with a clear walk, enemies walk straight at the target (no path)
	RepathDistance = 12, -- re-plan when the target is this far from where the path was planned...
	RepathSec = 1.5, -- ...or this often, whichever first
	PathComputesPerSec = 40, -- server budget across all enemies (oldest request first); raise DirectRange first if pinned
	PathCacheSec = 1, -- a route is shared per (target zone, enemy zone) this long
	PathAgent = { -- agent sizes per archetype id (lower case); TITAN's wide agent keeps it out of narrow doorways
		default = { r = 2, h = 5 },
		heavy = { r = 3, h = 6 },
		titan = { r = 6, h = 12 },
	},
	PathStructureCost = 10, -- placeables are walkable but this expensive: round a barricade when a route exists
	PathGasCost = 5, -- the gassed vault room
	StuckSec = 2.5, -- no progress toward the next waypoint this long -> sidestep
	StuckTeleportSec = 6, -- still stuck -> a random point in the enemy's own spawn box
	PathFailDirectSec = 3, -- three failed computes in a row -> walk direct this long, then retry
	LadderClimbSec = 1.6, -- an enemy on the ladder link is lifted over this long
	-- Round 19 catch-up: an enemy farther than CatchUpDistance from its target for CatchUpSec moves up its own route
	-- to the first waypoint CatchUpLead studs (along the route) short of the target that no player can see.
	CatchUpDistance = 90,
	CatchUpSec = 6, -- 0 = off
	CatchUpLead = 80, -- Round 22: 60 -> 80 (enemies were landing too close after a catch-up warp)
	CatchUpMinPlayerDistance = 70, -- Round 22: 55 -> 70 (the landing waypoint is at least this far straight-line from every standing player)
	CatchUpMinGain = 20, -- ...and at least this far from where the enemy stood (no tiny hops)
	CatchUpCameraLift = 9, -- ...and hidden from a point this far above each player too (the third-person camera)
	-- Round 21 stragglers: more than this many studs above / below its target counts as far too (another floor)...
	CatchUpFloorDelta = 10,
	-- ...and an enemy still far / off-floor this long without a catch-up (no route: stuck outside the building, or
	-- nothing hidden on its route) warps to a hidden spawn point near the crew (0 = off). The boss never warps.
	StragglerWarpSec = 14,
	EnemyClimbAnimationId = "", -- [TBA] played while lifted (empty: none)
	SpawnRingRadius = 90, -- studs from room center
	SpawnPointCount = 8,
	-- Proximity-weighted spawning (GDD): each marker's chance scales by its distance to the nearest living player.
	NearRange = 60, -- within this: x NearWeightMult
	FarRange = 150, -- up to this: x1; beyond: x FarWeightMult
	NearWeightMult = 3.0,
	FarWeightMult = 0.25,
	-- Brief 7 spawn boxes (THE BANK; the arena's markers are boxes with zone "arena" and behave as before).
	SpawnNeverInCrewZone = true, -- no spawn from a box standing inside the crew's zone (boxes behind fences or windows stand outside every zone)
	ZoneDistanceMult = 0.5, -- x this per zone hop from the crew zone along the open graph (two zones back trickle)
	SpawnLosBuffer = 18, -- a spawn point in plain sight of a player and closer than this re-rolls once
	EliteLeastUsedBox = true, -- an elite spawns from the eligible box with the fewest spawns this wave (GDD)
	-- Marksman / Boomer / Grenadier / Heavy tuning.
	MarksmanAimSec = 1.5, -- the red laser paints the line this long, then the shot goes down the line
	MarksmanHitRadius = 2.2, -- studs from the laser line that still counts as "in the beam"
	BoomerPlaceableSearch = 40, -- a placeable this close is preferred over players
	BoomerFuseSec = 1.2, -- beeps rising and swelling once in range, then the blast
	BoomerDamage = 8, -- to players in the blast
	BoomerPlaceableMult = 4, -- x BoomerDamage to structures
	BoomerRadius = 8,
	-- A Boomer killed by damage leaves a bigger circle growing where it fell (the Grenadier look), then bursts.
	BoomerDeathRadiusMult = 1.3, -- x BoomerRadius
	BoomerDeathFuseSec = 0.6, -- the circle grows this long before the burst (faster than a shell, not instant)
	GrenadierRadius = 7, -- the red circle grows from 0 to this over GrenadierTelegraphSec, then bursts
	GrenadierTelegraphSec = 2.0,
	GrenadierFireSec = 3, -- the fire patch the shell leaves (the molotov field look)
	GrenadierFireDps = 6, -- to players standing in the patch
	TelegraphTransparency = 0.3, -- the red floor circles (Grenadier, volley): lower = more solid, reads better on a phone
	TelegraphRimTransparency = 0.6,
	HeavyPlaceableMult = 3, -- x damage when a Heavy stomps a placeable in its path
	HeavyKnockback = 12, -- studs a Heavy's melee hit throws the player back
	HeavyPlateHpPcts = { 0.66, 0.33 }, -- the two armor plates fly off at these HP shares
	-- Compressed test brackets: a row applies from WaveMin until the next row; weights are relative chances rolled
	-- per enemy at spawn time. At HeatShiftStars or more stars the active row shifts HeatBracketShift rows down.
	Composition = {
		{ WaveMin = 1, Henchman = 100, Runner = 0, Marksman = 0, Boomer = 0, Grenadier = 0, Heavy = 0 },
		{ WaveMin = 2, Henchman = 75, Runner = 25, Marksman = 0, Boomer = 0, Grenadier = 0, Heavy = 0 },
		{ WaveMin = 3, Henchman = 60, Runner = 22, Marksman = 0, Boomer = 0, Grenadier = 18, Heavy = 0 },
		{ WaveMin = 4, Henchman = 54, Runner = 22, Marksman = 0, Boomer = 7, Grenadier = 17, Heavy = 0 },
		{ WaveMin = 5, Henchman = 48, Runner = 20, Marksman = 0, Boomer = 8, Grenadier = 16, Heavy = 8 },
		{ WaveMin = 6, Henchman = 44, Runner = 18, Marksman = 8, Boomer = 8, Grenadier = 14, Heavy = 8 },
		{ WaveMin = 8, Henchman = 38, Runner = 18, Marksman = 10, Boomer = 10, Grenadier = 16, Heavy = 8 },
		{
			WaveMin = 12,
			Henchman = 34,
			Runner = 17,
			Marksman = 14,
			Boomer = 8,
			Grenadier = 13,
			Heavy = 10,
		},
	},
	------------------------------------------------------------------ Elites
	EliteHpMult = 2.5,
	EliteCashMult = 3,
	EliteScale = 1.15,
	-- Hit reaction: a flinch pop only (never movement or timing), re-triggered at most once per FlinchAnimRate.
	-- EnemyHitKnockback is the Round 13 shove along the shot; 0 keeps hits from moving enemies (the brief's rule).
	FlinchAnimRate = 0.5,
	EnemyHitKnockback = 0, -- studs/s added along the shot on a hit (0 = none)
	RagdollEnabled = true, -- false: every kill shrinks out as before
	ActiveRagdolls = 8, -- bodies on the floor at once; past this a kill shrinks out (performance cap)
	RagdollLifetime = 2.0, -- a body lies this long, then fades over RagdollFadeSec and is removed
	RagdollFadeSec = 0.5,
	RagdollImpulse = 40, -- studs/s along the killing shot
	RagdollLift = 14, -- studs/s upward, so the body hops before it drops
	RagdollSpin = 10, -- tumble
	RagdollHeadPop = true, -- a headshot kill knocks the head off the body
	-- How hard a kill throws the body. The gun sets the base (a shotgun blast or sniper round launches, an SMG
	-- round barely tips the body); damage past the enemy's remaining HP adds up to RagdollOverkillMax more, so a
	-- point-blank dump on a fresh enemy flies while a pistol finishing a sliver of HP flops. Explosions use their
	-- own outward throw from the blast center, strongest at the middle. Fire and turret ticks just tip the body.
	RagdollForceByArchetype = {
		Pistol = 1,
		SMG = 0.8,
		Rifle = 1.3,
		Shotgun = 2.8,
		Sniper = 2.4,
		LMG = 1.5,
		Explosive = 3,
		Elemental = 0.6,
	}, -- x RagdollImpulse / RagdollLift / RagdollSpin
	RagdollOverkillMax = 1.5, -- extra multiplier when the overkill damage reaches the enemy's max HP (scales up to it)
	RagdollVariance = 0.25, -- +/- random share on every throw so no two look alike
	RagdollBlastImpulse = 90, -- studs/s outward from an explosion (claymore, Splash upgrade kill), at the center
	RagdollBlastLift = 40, -- upward at the center; both fall off to RagdollBlastEdge at the blast radius
	RagdollBlastSpin = 25,
	RagdollBlastEdge = 0.35,
	RagdollTickForce = 0.4, -- fire fields, flame turret and turret shots: a slump, not a throw

	------------------------------------------------------------------ Combat
	StartingCash = 3000, -- Match Cash at run start (brief says 0; raised for testing)
	-- Kill cash is the archetype's `cash` row (Enemies) x the wave, elite and heat multipliers x CASH GAIN (CashWaveMult).
	HoldToFire = true, -- true: every weapon fires while LMB is held; false: Weapons.auto decides
	HeadshotMult = 1.5,
	CritDmgMult = 2, -- damage multiplier when a crit lands (Crit Chance upgrade)
	BaseCritChancePct = 0, -- crit chance before upgrades, in percentage points
	MaxOriginDriftStuds = 8, -- reject FireShot if origin is further than this from the head
	-- Point blank: enemies walk through players, so one standing in you is inside the ray's start and the ray
	-- misses it. A bullet first hits the nearest enemy within PointBlankRange that is within PointBlankAngle of the aim.
	PointBlankRange = 5,
	PointBlankAngle = 70, -- degrees
	MaxShotRange = 600,
	FireRateTolerance = 1.5, -- server accepts shots up to this multiple of the weapon fire rate
	RicochetRange = 22, -- studs a ricochet can jump to another enemy
	RicochetDmgRatio = 0.75, -- ricochet damage as a share of the original hit
	SplashRadius = 9, -- studs around a kill that Splash damages
	MultishotSpread = 4, -- extra cone (degrees) on the multishot bullet
	-- Other players' shots: the server sends every teammate the shot's end points, the client draws the same
	-- tracer from that gun's muzzle and plays the shot sound at the gun (3D, falls off over RemoteShotRange).
	RemoteTracers = true,
	RemoteShotVolume = 0.3,
	RemoteShotRange = 110, -- studs the teammate's shot sound carries
	ShotPitchByArchetype = { Sniper = 0.6, Shotgun = 0.7, SMG = 1.3, LMG = 0.85 }, -- anything else plays at 1
	HitSparks = 6, -- impact particles per bullet hit on an enemy (0 = none)
	HitFlashColor = "FFFFFF", -- Round 28f: an enemy's body flashes this colour on every hit (was the Theme red, "E8554D")...
	HitFlashSec = 0.08, -- ...for this long (each hit restarts it)
	KillSparks = 18, -- extra burst on a kill
	-- Damage falloff by archetype: full damage out to `start` studs, scaling down to `min` at `finish`,
	-- flat `min` beyond. The room is 200 studs across; the spawn ring is 90 out.
	-- Round 24v: Explosive / Elemental weapons (Weapons.lua holds each gun's own numbers; Run/SpecialFire.lua).
	ExplosiveEdgeDmg = 0.35, -- blast damage at the rim (full in the inner 60% of the radius)
	ProjectileMaxLife = 6, -- seconds before an unlanded projectile blows anyway
	LobMaxTargetStuds = 260, -- Round 24aa: lobbed rounds aim at the crosshair point when it is this close
	-- Round 25: a lob that can't reach the crosshair throws at the aim pitch + this loft (degrees), capped at
	-- LobFallbackMaxDeg (was always 45, which left a first-person view).
	LobFallbackLoftDeg = 10,
	LobFallbackMaxDeg = 28,
	GrenadeRollKeep = 0.75, -- horizontal speed kept per touch while a landed round rolls
	ClusterScatter = 14, -- studs/s the bomblets fly out sideways...
	ClusterScatterUp = 16, -- ...and up
	StreamMaxTargets = 6, -- enemies one flame / frost tick can hit
	StreamFalloff = 0.4, -- a stream does this much less at the end of its range
	FlameBurnDpsMult = 0.5, -- the flamethrower's burn: this x the gun's damage per second per stack...
	FlameBurnSec = 2.5, -- ...for this long
	CryoSprayPower = 0.6, -- the cryo sprayer's chill per tick (a CRYO proc's power; stacks to a freeze)
	PlasmaChargeColor = "5BFF9A",
	PlasmaBeamHitPad = 0.35, -- studs added to half the beam width (Round 24ag: the beam now tests real body parts, not the root)
	PlasmaBeamFadeSec = 0.35, -- the beam's fade on screen
	FalloffByArchetype = {
		Pistol = { start = 40, finish = 90, min = 0.55 },
		SMG = { start = 30, finish = 70, min = 0.4 },
		Rifle = { start = 60, finish = 130, min = 0.6 },
		Shotgun = { start = 15, finish = 45, min = 0.25 },
		Sniper = { start = 600, finish = 600, min = 1 }, -- never falls off
		LMG = { start = 50, finish = 120, min = 0.55 },
	},

	------------------------------------------------------------------ Player
	PlayerMaxHP = 100,
	PlayerWalkSpeed = 16,
	PlayerHPRegenPerSec = 1, -- base regen, scaled by the HP Regen upgrade
	MouseSensitivity = 0.0022, -- radians per mouse pixel
	TouchSensitivity = 0.009, -- radians per touch pixel (Round 24b: up from 0.006)
	TouchCameraStartX = 0.4, -- Round 24: a touch that begins right of this share of the screen width turns the camera (left = thumbstick)
	TouchHipSensitivityMult = 1.2, -- Round 28e: touch look out of ADS runs this much faster (ADS keeps AdsSensitivityMult)
	MobileTopbarHidden = true, -- Round 28e: phones hide Roblox's top bar row (only the small Roblox menu button stays; chat goes with it)
	-- Round 24 aim assist (touch / gamepad). The enemy nearest the crosshair inside the cone pulls the camera to its
	-- torso; hold the crosshair above AimAssistHeadBias of the way from torso to head (on screen) and it pulls to the head.
	AimAssistEnabled = true,
	-- Brief 11: the assist per device (share of the pull and the stickiness; 0 = off). Mouse keeps the faint Round
	-- 24aa value, touch the full one, the gamepad sits between (felt, never aiming for you).
	AimAssistScale = { touch = 1.0, gamepad = 0.75, mouse = 0.15 }, -- gamepad 0.6 -> 0.75 (Jack, checkpoint 1)
	AimAssistMouseCone = 0.6, -- the mouse's cone is this share of the full one
	AimAssistGamepadStickOnly = true, -- gamepad: the pull works only while the right stick moves or you fire (no drift onto targets)
	AimAssistConeDeg = 11, -- hip fire: enemies within this many degrees of the crosshair pull
	AimAssistAdsConeDeg = 15, -- ADS: a wider cone
	AimAssistRange = 180, -- studs
	AimAssistPull = 7, -- how fast the camera closes on the target (per second; higher = stronger) (Round 28e: was 6)
	AimAssistAdsPull = 12, -- (Round 28e: was 10)
	AimAssistGamepadHipConeDeg = 14, -- brief 11: hip fire on a pad (no ADS): the cone...
	AimAssistGamepadHipPull = 8, -- ...and the pull (x AimAssistScale.gamepad), near the ADS values
	AimAssistFiringMult = 1.4, -- pull multiplier while shooting
	AimAssistHeadBias = 0.55, -- 0 = torso centre, 1 = head centre: crosshair above this switches the pull to the head
	AimAssistFrictionDeg = 6, -- inside this cone look input slows down... (Round 28e: was 5)
	AimAssistFriction = 0.5, -- ...to this share of normal sensitivity on the target's centre (Round 28e: was 0.6)
	AimAssistAdsFrictionDeg = 7, -- Round 28e: ADS has its own, stickier slowdown: the cone...
	AimAssistAdsFriction = 0.35, -- ...and the share of sensitivity left on the target's centre
	AimAssistTrack = 0.7, -- Round 28e: share of the target's drift across the screen (your strafe, its run) the view follows (hip)...
	AimAssistAdsTrack = 0.9, -- ...and in ADS (1 = glued, 0 = off); keeps your offset, never drags the view onto a target
	AimAssistPullAwayMult = 0.15, -- Round 24g: look input moving off the target keeps only this share of the pull (and no friction)...
	AimAssistReleaseSec = 0.25, -- ...for this long after the last pull-away input...
	AimAssistReleaseDeg = 1.5, -- Round 28e: ...once the away input adds up past this many degrees (a twitch never does)...
	AimAssistReleaseDrain = 4, -- ...the build-up drains at this rate per second when you stop pulling away
	------------------------------------------------------------------ Input (brief 11: gamepad)
	-- The pad's bindings: button (Enum.KeyCode name) -> action, per context. GamepadMap.lua resolves them; Input.lua
	-- routes each action into the same path the keyboard / touch buttons use. `reload` on ButtonX is the tap; while a
	-- ProximityPrompt (or a downed teammate in reach) is up, X is the prompt instead (the prompt wins). Screens (A
	-- select, B back, LB / RB tabs, LT / RT page) are GamepadNav's and not listed here.
	GamepadMap = {
		run = {
			ButtonR2 = "fire", -- hold for auto; charge guns hold and release
			ButtonL2 = "ads", -- hold (InputAdsToggle default false)
			ButtonX = "reload", -- tap; hold = the active prompt (interact / revive / door / minigame / pickup); buys at an open dealer panel
			ButtonY = "swap",
			ButtonA = "jump", -- Roblox's own jump
			ButtonL1 = "ability1",
			ButtonR1 = "ability2",
			ButtonB = "ability3", -- checkpoint 1: off R3 (B does nothing else in a run; screens block combat)
			ButtonR3 = "cameraCycle", -- normal -> fully out over the shoulder -> first person -> normal
			ButtonL3 = "sprint",
			DPadUp = "upgrade", -- buys the upgrade pick (the 2 key); at the dealer break it teleports instead
			DPadLeft = "pause", -- vote to pause (the P key)
			DPadRight = "voteSkip", -- the dealer break or an intermission (the V key)
			ButtonSelect = "scoreboard", -- Create: a tap opens / closes it, a hold peeks (closes on release)
		},
		hub = {
			ButtonX = "interact", -- the prompt (board, shelf, props); Roblox's prompt takes it
			ButtonA = "jump",
			ButtonL3 = "sprint",
			-- Create is left to Roblox in the hub: its own UI selection toggle (GamepadNav starts it on PLAY)
		},
	},
	GamepadTapMaxSec = 0.3, -- Create: shorter than this is a tap (the scoreboard stays open), longer a peek
	GamepadTriggerPress = 0.25, -- LT / RT count as pressed past this depth (analog Position.Z)
	DeviceSwitchHoldSec = 0.75, -- glyph flip debounce: after a device switch, another needs this long
	-- The right stick look: a radial dead zone, a response curve (exponent: small pushes stay fine, the edge is fast),
	-- GamepadLookSpeed degrees / second at full tilt, ramping up to GamepadLookAccelMult after GamepadLookAccelSec
	-- held at the edge (past GamepadLookAccelEdge). ADS multiplies by GamepadAdsLookMult. Pitch runs at
	-- GamepadLookPitchShare of the yaw speed. Settings sensitivity 1..10 scales the speed by sens / 5.
	GamepadLookDeadZone = 0.18,
	GamepadLookCurve = 1.6,
	GamepadLookSpeed = 180,
	GamepadLookPitchShare = 0.7,
	GamepadLookAccelMult = 1.5,
	GamepadLookAccelSec = 0.5,
	GamepadLookAccelEdge = 0.92,
	GamepadAdsLookMult = 0.55,
	GamepadMoveDeadZone = 0.2, -- the left stick counts as real input (device switch) past this
	-- Brief 11 glyphs: the text a pad button reads as inside a line of text (Hint.lua). The HUD chips draw the face
	-- buttons as shapes (InputGlyphs); these are for the labels that stay text. Settings glyphs = auto picks
	-- PlayStation unless Roblox reports an Xbox pad.
	GlyphText = {
		playstation = {
			ButtonA = "✕",
			ButtonB = "○",
			ButtonX = "□",
			ButtonY = "△",
			ButtonL1 = "L1",
			ButtonR1 = "R1",
			ButtonL2 = "L2",
			ButtonR2 = "R2",
			ButtonL3 = "L3",
			ButtonR3 = "R3",
			DPadUp = "↑",
			DPadDown = "↓",
			DPadLeft = "←",
			DPadRight = "→",
			ButtonSelect = "CREATE",
			ButtonStart = "OPTIONS",
			Thumbstick1 = "L STICK",
			Thumbstick2 = "R STICK",
		},
		xbox = {
			ButtonA = "A",
			ButtonB = "B",
			ButtonX = "X",
			ButtonY = "Y",
			ButtonL1 = "LB",
			ButtonR1 = "RB",
			ButtonL2 = "LT",
			ButtonR2 = "RT",
			ButtonL3 = "LS",
			ButtonR3 = "RS",
			DPadUp = "↑",
			DPadDown = "↓",
			DPadLeft = "←",
			DPadRight = "→",
			ButtonSelect = "VIEW",
			ButtonStart = "MENU",
			Thumbstick1 = "L STICK",
			Thumbstick2 = "R STICK",
		},
	},
	-- Brief 11: a held direction in the pad minigames (Hotwire's wires, the Safe dial's D-pad mode) repeats after
	NavRepeatDelaySec = 0.35, -- this...
	NavRepeatSec = 0.18, -- ...every this long
	-- The face buttons' colours on the drawn chips (PlayStation shapes / Xbox letters).
	GlyphColors = {
		playstation = { ButtonA = "7DA9FF", ButtonB = "FF6B73", ButtonX = "E89BD0", ButtonY = "3FCCA6" },
		xbox = { ButtonA = "6CC24A", ButtonB = "E8554D", ButtonX = "4D9FE8", ButtonY = "E8C34D" },
	},
	-- Haptics (HapticService, gamepad only): per event { motor = "Small" | "Large", strength 0..1, sec }. HapticFire per
	-- gun kind (the HeldGun's GunKind attribute; `default` for the rest); auto guns buzz while the trigger is held.
	HapticsEnabled = true, -- the default for new profiles (settings INPUT: haptics on / off)
	HapticFire = {
		pistol = { motor = "Small", strength = 0.35, sec = 0.06 },
		shotgun = { motor = "Large", strength = 0.9, sec = 0.14 },
		sniper = { motor = "Large", strength = 0.8, sec = 0.12 },
		launcher = { motor = "Large", strength = 0.85, sec = 0.16 },
		default = { motor = "Small", strength = 0.3, sec = 0.05 }, -- smg / rifle / lmg: a buzz while the trigger is held
	},
	HapticHit = { motor = "Small", strength = 0.25, sec = 0.03 },
	HapticHeadshot = { motor = "Small", strength = 0.6, sec = 0.05 },
	HapticDamage = { motor = "Large", strength = 0.45, sec = 0.1 },
	HapticDoor = { motor = "Large", strength = 0.7, sec = 0.4 }, -- a door opening, the vault swing
	HapticDowned = { motor = "Large", strength = 0.5, sec = 0.25, pulses = 3, gap = 0.45 }, -- a slow pulse
	HapticSprint = { motor = "Small", strength = 0.3, sec = 0.04 },
	-- Round 24 mobile: every HUD button (combat + hub) is scaled by this on phones / tablets.
	MobileButtonScale = 1.3,
	MobileFireScale = 0.9, -- Round 28e: FIRE draws this share of its old size (same centre)
	MobileStoreTextScale = 1.2, -- Round 24d: premium shop labels on mobile read this much bigger
	MobileFireRight = 200, -- FIRE's right edge this far (UI px) from the screen's right edge (clear of jump)
	MobileFireUp = 110, -- FIRE's bottom edge this far above the screen's bottom (Round 24b: was 36)
	-- Cursor unlocked (Ctrl / Alt): the camera stays put and the character turns to face the cursor's
	-- world point, so you can aim all the way around. Shots go where the cursor is.
	-- Round 24aa PROTOTYPE: sprint (PC, Shift while moving). The gun goes away: no fire, no ADS.
	SprintEnabled = true,
	SprintSpeedMult = 2,
	-- Brief 11 step 3: sprint on every platform. Fire always wins: fire / ADS / ability / interact / swap / minigame
	-- end the sprint and happen in the same frame; sprint then needs a fresh engage (Sprint.lua, SprintRule.lua).
	SprintFovAdd = 6, -- degrees of FOV pushed while sprinting
	SprintFovRate = 8, -- how fast the FOV eases in / out
	SprintRaiseAnimSec = 0.12, -- the arms catch up this long after a cancel (the shot itself is instant)
	SprintPushRadius = 1.3, -- touch: the stretch zone drawn out to this x the thumbstick ring
	SprintPushAngle = 35, -- touch: the push must be within this many degrees of straight forward...
	SprintPushHoldSec = 0.25, -- ...past the ring for this long to engage
	SprintKeepThreshold = 0.6, -- touch: a push-through sprint holds while the thumb is at least this far forward
	SprintPadStopGraceSec = 0.3, -- pad: an L3 sprint ends after the stick has rested this long (any direction holds it)
	SprintReArmRadius = 0.88, -- touch: the thumb back inside this x the ring re-arms the next push-through
	SprintReEngageCooldownSec = 0.5, -- after a fire cancel, no sprint for this long (no instant bounce)
	SprintPressGraceSec = 0.35, -- a toggle press (L3, toggle Shift) waits this long for the stick to move, then lapses
	SprintTouchRingPx = 60, -- touch: the thumbstick ring radius when Roblox's own frame cannot be read (UI px)
	CameraFov = 70,
	CameraCenterRate = 8, -- Round 24aa: how fast the camera slides to centre when the cursor unlocks (and back)
	FireFovKick = 2.5, -- degrees of FOV punch per shot
	-- Zoom: scroll wheel / pinch changes the camera distance (studs behind the head).
	CameraZoomDefault = 8,
	CameraZoomMax = 16, -- outer limit
	CameraZoomStep = 1.5, -- studs per scroll-wheel tick
	CameraFirstPersonBelow = 2, -- zooming under this snaps to first person (character hidden locally)
	-- Round 24b/c first person: the body hides, a steady eye, and a camera-locked viewmodel (FirstPersonView).
	FirstPersonEyeLift = 0.9, -- Round 25: studs the first-person eye sits above the head's centre (0.45 still felt low)
	FirstPersonWallClearance = 1.6, -- Round 25: a wall closer than this ahead of the eye eases it back...
	FirstPersonWallPullMax = 0.9, -- ...by at most this many studs, and lowers the gun
	FirstPersonWallLowerDeg = Vector2.new(30, 18), -- the gun's muzzle-down / yaw-in degrees at a wall
	FirstPersonBobKeep = 0.2, -- share of the head's walk bob the view keeps (0 = rock steady, 1 = the raw head)
	FirstPersonSteadyRate = 6, -- how fast the steady eye follows the head's offset (crouch, downed, lean)
	-- Round 24r optics in first person: magnified zoom (FOV multipliers while aimed; plain ADS is AdsFovMult) and
	-- the sniper scope's HUD ring: a dark (not black) surround outside a circle ScopeRingPct of the screen height.
	ScopeFovMult = 0.28,
	AcogFovMult = 0.55,
	MediumScopeFovMult = 0.42, -- Round 24u: the mid scope (Mosin, SVD, FAL): between the ACOG and the sniper glass
	ScopeRingPct = 0.86,
	ScopeSurroundAlpha = 0.45, -- how dark the surround gets (0 = none, 1 = black)
	FirstPersonDrawSec = 0.32, -- Round 24aa: a swapped-in gun rises into view over this long
	FirstPersonGunScale = 0.5, -- Round 24e: the viewmodel gun's size vs the held gun (1 filled half the screen)
	FirstPersonHipGrip = Vector3.new(0.36, -0.52, -0.95), -- hip fire: the gun's grip in camera space (right, up, -forward); Round 24q: up -0.4 -> -0.52
	FirstPersonConverge = 40, -- Round 24p: hip fire: the barrel points at the crosshair line this many studs out
	FirstPersonBareAdsGrip = Vector3.new(0.2, -0.5, -0.85), -- Round 24aa: aiming a gun with no sights: its grip here (low, near the centre)
	FirstPersonHipTilt = Vector2.new(0, 0), -- hip fire: extra degrees pitch / yaw on top of that
	-- ADS: the rear of the sight sits this far ahead of the eye, per gun kind (Round 24g: a pistol at arm's
	-- length, long guns with the eye just behind the rear sight)...
	FirstPersonAdsRelief = {
		pistol = 0.9,
		smg = 0.28, -- Round 24aa: long guns sit a little further out so the body blocks less of the view
		rifle = 0.3,
		bullpup = 0.26,
		shotgun = 0.36,
		sniper = 0.26,
		lmg = 0.42,
		launcher = 0.3,
		energy = 0.25,
		thrown = 0.7,
		default = 0.25,
	},
	FirstPersonAdsDrop = 0.0, -- ...and this far below the crosshair line
	-- Round 25: aimed in first person the muzzle sits on the crosshair line, so its tracer ran straight away from
	-- the lens and drew as a dot. Aimed tracers start here in camera space instead (right, up, -forward): a hair
	-- below and right of the sight, so the line reads as a streak converging on the crosshair.
	FirstPersonAdsTracerStart = Vector3.new(0.05, -0.09, -1.4),
	FirstPersonAdsTracerLife = 0.07, -- seconds an aimed tracer shows (hip tracers 0.05)
	FirstPersonSway = 0.6, -- how much the gun trails camera turns
	FirstPersonSwayMaxDeg = 4, -- cap on that lag
	FirstPersonSwayReturn = 10, -- how fast it settles back (per second)
	FirstPersonBobSpeed = 9, -- walk bob cycle speed (radians per second)
	FirstPersonBobX = 0.025, -- walk bob side sway, studs (ADS keeps 30%)
	FirstPersonBobY = 0.03, -- walk bob dip, studs
	-- Round 24n: first-person recoil per gun kind: kick = studs the viewmodel shoves back, rise = degrees the
	-- muzzle flips up about the grip (stacks up to 2 shots, eases home at FirstPersonRecoilReturn per second).
	FirstPersonRecoil = {
		pistol = { kick = 0.08, rise = 7 },
		smg = { kick = 0.035, rise = 2 },
		rifle = { kick = 0.06, rise = 3 },
		bullpup = { kick = 0.05, rise = 2.5 },
		shotgun = { kick = 0.16, rise = 12 },
		sniper = { kick = 0.22, rise = 16 },
		lmg = { kick = 0.05, rise = 2.5 },
		launcher = { kick = 0.2, rise = 10 },
		energy = { kick = 0.06, rise = 3 },
		thrown = { kick = 0.1, rise = 8 },
	},
	FirstPersonRecoilAdsMult = 0.7, -- aimed shots kick this hard
	FirstPersonRecoilReturn = 9, -- how fast it settles (per second)
	-- Round 24n: the camera's own punch per shot (degrees up, every view), easing home at CameraRecoilReturn.
	CameraRecoilDeg = {
		pistol = 0.6,
		smg = 0.15,
		rifle = 0.3,
		bullpup = 0.25,
		shotgun = 1.6,
		sniper = 2.4,
		lmg = 0.2,
		launcher = 1.8,
		energy = 0.4,
		thrown = 0.6,
	},
	CameraRecoilReturn = 7,
	-- Round 24h first-person reload: the gun tilts about its grip, the mag drops out and a fresh one rises in.
	FirstPersonReloadTilt = Vector3.new(12, 10, 28), -- degrees: muzzle up, yaw in, roll in at the full pose
	FirstPersonReloadPull = Vector3.new(-0.05, -0.1, 0.08), -- studs the gun moves at the full pose (camera space)
	FirstPersonMagDrop = 1.2, -- studs (gun space, before FirstPersonGunScale) the mag falls before it vanishes
	FirstPersonShellBump = 0.12, -- radians the gun nods as each shell goes in
	FirstPersonArmWidth = 0.18, -- forearm block thickness
	FirstPersonRunSwing = 1, -- Round 24j hub (empty hands): how far the arms pump while running (0..1)
	FirstPersonRunSwingSpeed = 9, -- their cycle speed at walk speed 16 (radians per second)
	FirstPersonElbowR = Vector3.new(0.6, -0.95, -0.25), -- camera-space points the forearms run back to
	FirstPersonElbowL = Vector3.new(-0.3, -1.0, -0.45),
	CameraShoulder = Vector2.new(2.6, 1.2), -- right / up offset at CameraZoomDefault; shrinks as you zoom in
	CameraZoomSmoothing = 12, -- higher = snappier zoom
	-- ADS: hold RMB (tap the ADS button on mobile).
	AdsFovMult = 0.8, -- FOV while aiming, as a share of CameraFov
	AdsZoomMult = 0.7, -- third-person camera distance while aiming, as a share of the current zoom
	AdsSpreadMult = 0.5, -- bullet spread while aiming
	AdsSensitivityMult = 0.7, -- look sensitivity while aiming
	AdsBlendSec = 0.12, -- seconds to ease in / out of ADS
	-- Cursor unlocked (Ctrl): ADS only pulls in a little, and holding RMB drags the camera round like default Roblox.
	AdsFovMultUnlocked = 0.94,
	AdsZoomMultUnlocked = 0.92,
	-- Rarity juice, indexed by tier 1..5: camera shake amplitude (studs) and duration, screen flash alpha.
	JuiceShakeByTier = { 0, 0.1, 0.25, 0.45, 0.8 },
	JuiceShakeDurByTier = { 0, 0.15, 0.2, 0.3, 0.45 },
	JuiceFlashByTier = { 0, 0, 0.25, 0.4, 0.55 },

	------------------------------------------------------------------ Economy
	UpgradePrice = 100,
	UpgradePriceMult = 1.35, -- upgrade n costs UpgradePrice * mult^n

	------------------------------------------------------------------ Upgrade overlay
	ShopDimPct = 35, -- world dim while the pick-3 is open
	PanelShakePx = 2,
	CardDealStagger = 0.08,
	CardFlipStagger = 0.07, -- unused by the slot roll, kept for the flip variant
	CardRollSec = 0.45, -- each card's mini slot roll; starts as the card deals in
	CardRollStagger = 0.07, -- gap between card rolls starting
	TradeoffChance = { 0, 0.05, 0.12, 0.2, 0.25 }, -- per tier 1..5 (brief 5 halved); never on element cards
	TradeoffMalusRatio = 0.5, -- malus = one other stat at this ratio of the buff (never an element or CASH GAIN)
	TrackerCols = 10,

	------------------------------------------------------------------ Upgrades (brief 5: categories, elements, utility, income)
	-- The pick-3 and the dealer draw a category by these weights, then a stat inside it.
	CategoryWeights = { gun = 50, element = 15, defense = 15, utility = 10 }, -- Round 25: defense (Max HP, HP Regen, Armor)
	ArmorRegenDelay = 4, -- Round 25 ARMOR: seconds without a hit before spent armor refills...
	ArmorRegenPctPerSec = 0.25, -- ...at this share of the total per second
	ArmorColor = "8FD3FF", -- the HUD's armor plate bar
	-- Elements go on every bullet that lands (each shotgun pellet counts) and all three can be held. The numbers below are
	-- at power 1 (the first take, shown as 100%); every later take adds the card's percent (Upgrades.Magnitude) to the
	-- power, which scales the burn DPS and tick rate, the slow and freeze, and the knockback.
	IncendiaryDps = 3, -- burn on the enemy per stack (x power)...
	IncendiaryMaxStacks = 5, -- ...every bullet that lands adds a stack, up to this (a shotgun stacks it in one blast)...
	IncendiaryBurnSec = 2.5, -- ...each hit refreshes it...
	IncendiaryTickRatePerPower = 0.5, -- ...and every extra 100% power ticks it this much faster
	CryoSlowPct = 0.15, -- walk speed down this share (x power)...
	CryoSlowCap = 0.7, -- ...never more than this...
	CryoSlowSec = 2, -- ...for this long; also the stack window
	CryoStacksToFreeze = 10, -- this many hits inside the window freeze the enemy...
	CryoFreezeSec = 0.8, -- ...for this long x power (no move, no attack)...
	CryoFreezeCooldownSec = 3, -- ...at most once per this per enemy (no freeze lock)
	CryoBossSlowMult = 0.5, -- the boss takes this share of the slow and never freezes
	ConcussiveStuds = 1.0, -- knockback along the shot per bullet (x power; a full shotgun blast adds up)
	ConcussiveHeavyMult = 0.5, -- Heavy and the boss take this share of the knockback (the boss is never interrupted)
	ConcussiveStunSec = 0.3, -- the interrupt: a short stun that cancels the attack being wound up...
	ConcussiveInterruptSec = 1.5, -- ...at most this often per enemy
	ConcussiveSlideSec = 0.15, -- the knockback slide takes this long
	AbilityCooldownCap = 60, -- ABILITY COOLDOWN never takes more than this % off
	-- Round 25: ABILITY POWER also amplifies effects that aren't damage or healing. Shares of its bonus (+20% power
	-- at share 0.5 = +10%): buff strengths (Adrenaline / Stim Shot / Dead Eye / Overclock rate, Eagle Eye slow)...
	AbilityPowerBuffShare = 1,
	AbilityPowerDurationShare = 0.5, -- ...buff, stun, mark and Overclock durations...
	AbilityPowerRadiusShare = 0.35, -- ...and the Flashbang / Eagle Eye radius (soft: ranges stay readable)
	-- Kill cash = archetype cash x (1 + CashWaveMult x (wave - 1)) x elite x heat x CASH GAIN.
	CashWaveMult = 0.1,

	------------------------------------------------------------------ Synergy upgrades (conditional cards)
	-- Conditional stats (Upgrades.lua `requires`) sit outside CategoryWeights: they show up only while their condition
	-- holds (an element held, the equipped class), marked with a SYNERGY pill. Per magnitudes in Upgrades.Magnitude.
	SynergyChance = 0.2, -- per card slot (pick-3 and dealer stands), while at least one synergy card qualifies
	SynergyColor = "5CE1E6", -- the pill on a synergy card
	WildfireRadius = 10, -- WILDFIRE: a Fire Ammo burn jumps to enemies this close when the burning enemy dies...
	WildfireMaxPct = 100, -- ...at the card's % of its strength, never more than this (100 = the burn carries whole)
	ShatterFrozenMult = 2, -- SHATTER: a frozen enemy takes this x the bonus a chilled one does
	AftershockRadius = 7, -- AFTERSHOCK: a Stun Ammo stagger hits other enemies this close for the card's % of gun damage

	------------------------------------------------------------------ Ground loot
	SwapCooldownSec = 0.5, -- after a swap, further swaps are ignored for this long (anti-spam mid-combat)
	-- Round 21: two loadout slots. You start with one gun; a pickup with the second slot empty goes there and you
	-- switch to it; with both full a pickup replaces the gun in your hands (it drops). Key 1 / tapping the slot chip
	-- switches. 1 = the old single-gun loadout.
	WeaponSlots = 2,
	WeaponSwitchSec = 0.3, -- after a switch, further switches are ignored for this long
	-- The switch sound: every entry plays at once (layer a bolt clack over a holster draw for more weight).
	-- { id, volume, pitch }. Candidates, all ProSoundEffects (Roblox-licensed, approved), to audition by swapping ids:
	--   9116357355 Machine Gun Bolt 2 (1s)   9116357348 Machine Gun Bolt 1 (1s)   9116357621 Machine Gun Bolt 4 (1s)
	--   9114701864 Gun From Holster 1 (1s)   9113104176 Ammo Magazine 1 (1s)      9114724914 Gun Pick Up 4 (2s)
	--   9114724920 Gun Pick Up 5 (2s)        9114704367 Gun Handling 2 (4s, a long rattle)
	WeaponSwitchSounds = {
		{ id = "rbxassetid://9116357355", volume = 0.6, pitch = 1 }, -- Machine Gun Bolt 2: the clack
		{ id = "rbxassetid://9114701864", volume = 0.45, pitch = 1 }, -- Gun From Holster 1: the gear under it
	},
	GroundWeaponLifetime = 30, -- floor guns despawn after this; a fresh drop (or swap) restarts it
	GroundWeaponFadeSec = 10, -- beam fades over the last N seconds of lifetime
	InteractRadius = 8,
	-- Round 25: keys. Interact (every prompt, the dealer's BUY, the revive hold) and the three ability slots.
	InteractKey = "E",
	AbilityKeys = { "Q", "F", "Z" },
	-- Round 25: between a dealer stand and a floor gun both in reach, the one you look at more squarely wins the
	-- interact key: score = degrees off the camera's look line + this many per stud away.
	InteractDistWeight = 2,
	-- Round 25: loot light columns stop at the ceiling above them (Ground.ceiling), never taller than these.
	GunBeaconHeight = 14,
	-- Round 25: bags and crates that would sit in a wall or out of play (outside every zone) move to the nearest
	-- clear floor within LootClearSearch studs (Ground.clearSpot); a bag needs LootClearRadius of room.
	LootClearRadius = 1,
	LootClearSearch = 12,
	BagBeaconHeight = 50,
	MaxConsecutiveNonUpgrades = 3, -- pity, per player: crate rolls below your held rarity before the floor kicks in on your next roll

	-- Rarity odds per wave bracket, in order Common / Uncommon / Rare / Epic / Legendary.
	-- Weights, not percentages; they are normalised at roll time. Also drives upgrade card tiers.
	RarityOddsByWaveBracket = {
		{ maxWave = 5, odds = { 45, 30, 17, 7, 1 } },
		{ maxWave = 10, odds = { 30, 32, 24, 11, 3 } },
		{ maxWave = 20, odds = { 18, 28, 30, 17, 7 } },
		{ maxWave = math.huge, odds = { 10, 22, 30, 25, 13 } },
	},
	RarityDmgMult = { 1, 1.3, 1.7, 2.3, 3.0 }, -- a legendary of any gun out-DPSes an epic of any other

	------------------------------------------------------------------ Crates (brief 5: the only in-run weapon source)
	-- A GUN CRATE lands closed holding party size + CrateRollsExtra rolls. F (OPEN) by any member plays them all back
	-- to back: the sliding reel on a billboard above the crate for everyone, then each gun ejects to a free floor spot
	-- CrateDropRadius out. Sources: the intro, side job success (not the vault), the boss (first roll a Legendary).
	CrateRollsExtra = 1,
	RollDurationSec = 1.2, -- the row of icons slides this long and eases onto the gun
	RollLandHoldSec = 0.35, -- the result shows this long before the gun ejects...
	RollHighTierHoldSec = 0.3, -- ...plus this from Epic up
	RollEjectSec = 0.25, -- the panel closes as the gun flies out
	CrateRollGapSec = 0.15, -- then the next roll starts
	CrateReelScale = 0.8, -- the reel panel over the crate, as a share of the original weapon reel's size
	CrateOpenShake = 0.35, -- camera shake when a crate opens (fades with distance over CrateFxRange)...
	CrateEjectShake = 0.15, -- ...and per gun that flies out (Epic and up twice this)
	CrateFxRange = 60, -- studs
	CrateDropRadius = 6, -- studs from the crate the gun lands
	CrateLifetimeSec = 45, -- the crate closes after this even with rolls left (floor guns keep their own timers)
	BigCrateWaveInterval = 0, -- a crate at the start of every Nth wave; 0 = never
	BigCrateIntroDrop = true, -- one crate during the intro (the arena)...
	BigCrateIntroDropOnMaps = false, -- ...and on THE BANK / later maps too (Round 19c: off, you start with the starter gun)
	BigCrateIntroPosition = Vector3.new(0, 0, -14), -- where the intro crate lands
	BigCrateDespawnOnWaveEnd = false, -- true: crates close at wave end
	BigCrateRarityFloorByBracket = { 2, 3, 3, 4 }, -- the crate's rarity floor per wave bracket: Uncommon / Rare / Rare / Epic
	BigCrateDropHeight = 40,
	BigCrateDistanceFromCenter = 20,

	------------------------------------------------------------------ Crew call / stub Side Job
	CallHoldSec = 4.5, -- crew call card shows this long before it collapses to the pill (result cards too)
	SideJobReminderPct = 0.5, -- a reminder line comes in when this share of the job window has gone and it is still open
	SideJobFirstWave = 1,
	SideJobEveryWaves = 2,
	SideJobDurationSec = 75,
	SideJobReward = 600,
	SideJobGold = 5, -- Gold per completed side job, per player, paid with the run payout
	SideJobBeaconRadius = 6,
	SideJobHoldSec = 2, -- hold the HACK prompt on the beacon this long to complete
	-- Job type is rolled per job from these weights. hack | capture | one of the six minigames (played at the beacon
	-- at the session tier; retry until the timer runs out).
	SideJobKindWeights = {
		hack = 0, -- Round 19h: the plain hold-F terminal is out (door shutters keep their hold); minigames instead
		capture = 1,
		Lockpick = 1,
		Hotwire = 1,
		Keypad = 1,
		Charges = 1,
		Safe = 0, -- the Safe dial is the vault's own beat now, out of the normal rotation
		Freq = 1,
		Cut = 1, -- Round 19c: CUT THE CHAIN (the bolt cutter)
		alarm = 1, -- Round 19c: SILENCE THE ALARM (every alarm in the building rings until the panel is shut off)
		office = 1.5, -- Round 19f: RAID THE OFFICE (THE BANK: an office in an open zone, see Offices below)
		vault = 1, -- CRACK THE VAULT (from VaultJobMinWave, once per run when VaultJobOnce)
	},
	SideJobCaptureSec = 6, -- seconds a player must stand in the circle; pauses while nobody is inside (Round 19c: 10 -> 6)
	SideJobCaptureRadius = 7, -- studs
	SideJobRewardCrate = true, -- a crate drops at the beacon on completion
	CallPillWarnSec = 10, -- pill turns red under this many seconds

	------------------------------------------------------------------ Abilities (the four class kits, Classes.lua)
	-- Cooldown per ability id, seconds. Abilities are free in a run (the $ on the Classes tab is a label).
	AbilityCooldown = {
		frag = 12,
		barricade = 15,
		turret = 20,
		overclock = 30,
		eagleeye = 25,
		stim = 20,
		stimshot = 20,
		medbag = 25,
		healturret = 25,
		claymore = 12,
		deadeye = 25,
		flashbang = 18,
		molotov = 15,
		flameturret = 20,
		oildrum = 15,
	},
	StructurePlaceDistance = 0, -- studs in front of the player (placeables: turrets, barricade, oil drum, med bag, claymore); 0 = right where you stand (Round 18b; players walk through placeables)
	ThrowDistance = 12, -- studs in front of the player a thrown ability lands when no aim point comes with it (flashbang, molotov)
	ThrowMaxRange = 100, -- thrown abilities land at the cursor's floor point, no further than this from the player
	-- Aim assist (Round 16): the throw locks, and homes on in flight, the enemy under the cursor; else the one
	-- closest to the camera ray (within ThrowAssistRayStuds of it); else the one nearest the aim point (ThrowAssistRadius).
	ThrowAssistRadius = 14, -- 0 turns aim assist off
	ThrowAssistRayStuds = 5,
	ThrowAssistOriginSlack = 60, -- the camera ray's origin is only trusted this close to the thrower
	ThrowArcPerStud = 0.12, -- the throw's arc peaks this many studs high per stud of distance (never under 1.5)
	ThrowFlightRefStuds = 45, -- throws up to this far take ThrowFlightSec; further ones take proportionally longer (100 studs ~1.3s)
	ThrowFlightSec = 0.6, -- the throw's arc takes this long, then it goes off
	FieldTickSec = 0.5, -- ground fields (med bag, molotov, drum fire) apply their per-second numbers this often
	-- INITIATE (brief 5): Frag / Adrenaline / Claymore
	FragDamage = 120, -- to every enemy in the blast (x ABILITY POWER)
	FragRadius = 9, -- it goes off the moment it lands
	-- ENGINEER (brief 5): Turret / Barricade / Overclock
	OverclockSec = 8, -- every friendly placeable fires / heals OverclockRateMult x for this long...
	OverclockRateMult = 1.5,
	OverclockShieldHp = 150, -- ...and every barricade gets a shield that absorbs damage first, gone with the buff
	OverclockSelfGunShare = 1, -- Round 28e: the caster's own gun gets this share of the RATE bonus on fire rate and reload (0 = off)
	-- SHARPSHOOTER (brief 5): Eagle Vision (id eagleeye, EagleEye* keys) / Dead Eye / Flashbang
	EagleEyeRadius = 60, -- every enemy this close is marked through walls...
	EagleEyeSec = 6, -- ...for this long...
	EagleEyeSlowPct = 0.35, -- ...and walks this much slower while marked (Round 16: replaced the bonus damage)
	EagleEyeSlowCap = 0.7, -- the slow never passes this, whatever the level
	EagleEyeBossSlowMult = 0.5, -- the boss takes this share of the slow
	-- Placeables (ENGINEER's Turret / Barricade, the rest of the kits)
	TurretHP = 150,
	TurretDmg = 12,
	TurretFireRate = 3, -- shots per second
	TurretRange = 45,
	TurretLifetime = 0, -- seconds; 0 = stands until destroyed (Round 18d: every placeable but the med bag)
	BarricadeHP = 300,
	BarricadeSize = Vector3.new(8, 4, 1),
	BarricadeLifetime = 0,
	-- Adrenaline (ability id "stim"): fire rate, reload and move speed; no heal (DOC's stim shot heals)
	AdrenalineDuration = 6,
	AdrenalineMoveMult = 1.5,
	AdrenalineFireRateMult = 1.6,
	AdrenalineReloadSpeedMult = 1.6, -- reloads this much faster while it runs
	-- DOC
	StimShotDuration = 6,
	StimShotHeal = 40,
	StimShotFireRateMult = 1.3,
	StimShotReloadSpeedMult = 1.3,
	MedBagHealPerSec = 8, -- every standing teammate inside the circle
	MedBagRadius = 6,
	MedBagLifetime = 15, -- the one placeable with a duration
	HealTurretHP = 150,
	HealTurretBeamHeal = 6, -- HP per second on the beam
	HealTurretRange = 30, -- picks the hurt teammate with the lowest HP share in range
	HealTurretTickSec = 0.5,
	HealTurretLifetime = 0,
	-- SHARPSHOOTER
	ClaymoreDamage = 220, -- to every enemy in the blast
	ClaymoreTriggerRadius = 5, -- an enemy this close sets it off
	ClaymoreBlastRadius = 8,
	ClaymoreArmSec = 1, -- it cannot go off before this
	ClaymoreLifetime = 0, -- until it goes off or is destroyed
	DeadEyeDuration = 8,
	DeadEyeDmgPct = 25, -- weapon damage x (1 + this / 100)
	DeadEyeAccuracyPct = 50, -- Round 19c (was move speed): spread x (1 - this / 100) while it runs, on top of the Accuracy upgrade
	DeadEyePierce = 2, -- extra enemies every bullet passes through while it runs (on top of upgrades and sniper pierce)
	FlashRadius = 12, -- enemies this close to the burst are stunned
	StunDuration = 3, -- stunned enemies stop and do not swing
	-- TORCH
	-- Round 16: friendly fire fields (molotov, burst oil drum) burn in these colors with a solid rim (the med bag's
	-- green field gets the rim too); the enemies' fire stays orange / red, rimless.
	AllyFireColor = "3FA9FF",
	AllyFireSecondary = "D8F0FF",
	AllyFireDiscTransparency = 0.6,
	AllyFieldRimStuds = 0.5, -- rim width, centered on the field's edge
	AllyFieldRimSegments = 24, -- parts the rim ring is built from
	AllyFieldRimTransparency = 0.15,
	MolotovRadius = 7,
	MolotovLifetime = 8,
	MolotovBurnPerSec = 15,
	MolotovMoveSlowPct = 30, -- enemies in the fire walk this much slower
	FlameTurretHP = 150,
	FlameTurretDps = 30,
	FlameTurretRange = 14, -- short: a stream, not a gun
	FlameTurretTickSec = 0.25,
	FlameTurretLifetime = 0,
	OilDrumHP = 200,
	OilDrumLifetime = 0,
	OilDrumBurnPerSec = 20, -- the fire it leaves when enemies break it (not when it expires)
	OilDrumMoveSlowPct = 30,
	OilDrumBurnRadius = 7,
	OilDrumBurnSec = 6,

	------------------------------------------------------------------ Heat as pace (GDD_7; Heat.lua; stars 0..5 in half steps, no decay)
	HeatStart = 0,
	-- Par per wave: ParTimeBase + ParTimePerEnemy x waveBudget (boss waves add BossParBonusSec). Clear time runs
	-- from the WAVE N banner to the death of the last enemy tagged with that wave, so AUTO SKIP overlap counts.
	ParTimeBase = 15,
	ParTimePerEnemy = 1.5, -- placeholder: set from the clear / par ratios the Stats button prints
	FastClearPct = 0.6, -- clear <= this x par: HeatFastClear
	SlowClearMult = 1.5, -- clear > this x par: HeatSlowClear (between par and this: nothing)
	HeatFastClear = 1.0,
	HeatParClear = 0.5, -- clear <= par
	HeatSlowClear = -0.5,
	HeatAutoSkip = 0.5, -- AUTO SKIP active during the wave
	HeatJob = 0.5, -- per side job completed in the wave
	HeatJobFail = -0.5, -- per side job that expired in the wave
	HeatDowned = -0.5, -- per player downed in the wave...
	HeatDownedMax = -1.0, -- ...capped here per wave
	HeatBossKill = 1.0, -- on top, the moment the boss dies
	-- Effects at S stars, continuous: cash x (1 + HeatCashPerStar x S), elite chance HeatElitePerStar x max(0, S - 1),
	-- spawn interval x (1 - HeatSpawnPerStar x S), and at HeatShiftStars+ the composition bracket shifts HeatBracketShift rows.
	HeatCashPerStar = 0.15,
	HeatElitePerStar = 0.05,
	HeatSpawnPerStar = 0.08,
	HeatBracketShift = 1,
	HeatShiftStars = 4,

	------------------------------------------------------------------ Bags (Bags.lua; spots in BagSpots.lua)
	CashBagBase = 150, -- a cash bag pays CashBagBase x (1 + CashBagPerWave x wave) match cash to every member
	CashBagPerWave = 0.25,
	GoldBagValue = 25, -- a gold bag adds GoldBagValue x (1 + GoldBagPerWave x wave) to the team's Banked total
	GoldBagPerWave = 0.1,
	CashBagsPerWave = 1, -- spawned at every wave start (not the boss cutscene), up to MaxActiveBags; fractions carry (0.5 = every other wave)
	GoldBagsPerWave = 0.5,
	MaxActiveBags = 6, -- caps the wave-start trickle; bursts (boss, vault) bypass it
	BagPartyScale = 0.5, -- Round 19c: every bag count (trickle, cap, bursts: vault, doors, boss) x (1 + this per member past the first): 1x solo, 2.5x for 4
	-- Pickup has no button: stand near a bag and it fills, then it is yours. One bag at a time per player.
	BagChannelSec = 0.7, -- a bag fills over this long (the first one of a streak)
	BagStartRadius = 6, -- studs (flat, root to bag): a bag in this reach starts filling (one with fill first, else the nearest)...
	BagKeepRadius = 10, -- ...and keeps filling until you are past this, so a small step never cancels
	BagStreakMult = 0.8, -- each bag started within BagStreakWindowSec of your last pickup fills this much faster (x per bag)...
	BagStreakMinMult = 0.4, -- ...down to this fraction of BagChannelSec (a vault pile of 10 takes about 4s)
	BagStreakWindowSec = 1.5, -- ...and the streak ends after this long with nothing filling
	BagHoldSec = 0.6, -- a bag you leave keeps its fill this long...
	BagDrainPerSec = 0.5, -- ...then loses this much of a full fill per second; anyone can finish it meanwhile
	BagBusyGraceSec = 0.35, -- teammates' GRABBING tag stays up this long between bags of a pile
	BagRingSegments = 16, -- ticks in the fill ring over a bag
	BagRingMaxDistance = 45, -- the fill ring is drawn within this range only
	BagPullStuds = 1.6, -- a filling bag slides this far toward whoever fills it, and lifts a little
	BagSuckSec = 0.18, -- on pickup the bag shoots into the collector over this long while it shrinks
	BagFarMult = 3, -- spot weight beyond BagFarDistance from the crew...
	BagFarDistance = 60,
	BagNearMult = 0.25, -- ...and within BagNearDistance
	BagNearDistance = 25,
	GoldBagMinDistance = 50, -- gold bags never spawn closer than this to any player (when a spot allows it)
	LootRushCash = 4, -- the debug Loot Rush burst round the player: cash bags...
	LootRushGold = 2, -- ...and gold bags...
	LootRushRadius = 10, -- ...this far out

	------------------------------------------------------------------ Vault (the arena's vault closet; VaultJob.lua; regenerate the map after changing sizes)
	VaultSize = 24, -- the closet is this square, on the north wall
	VaultDoorWidth = 12,
	VaultBagSpots = 10, -- bag spots inside (BagSpots.Vault)
	VaultJobDurationSec = 150, -- CRACK THE VAULT's window to get the door open (Round 18c: 2x SideJobDurationSec)
	VaultJobMinWave = 3, -- CRACK THE VAULT can be drawn from this wave (weight in SideJobKindWeights)
	VaultSafeTierMax = 3, -- the vault's Safe dial follows the wave bracket up to this tier (SafeNumbersByTier: 3 / 4 / 5)
	VaultJobOnce = false, -- true: at most once per run (a failed draw can come back); false: a sealed vault resets for the next draw
	VaultJobEveryWaves = 5, -- testing: the vault job is forced at every multiple of this wave (0 = random draws only)
	VaultJobForceAfterUnlock = true, -- Round 22: the first side-job draw after the vault area opens is always the vault job
	VaultBurstCash = 6, -- bags dropped inside when it opens
	VaultBurstGold = 4,
	VaultOpenSec = 60, -- the loot window from the door opening
	VaultGasWarnSec = 10, -- alarm, strobe and MARLOW's warning this long before the gas
	VaultGasDps = 8, -- to any player inside once the gas is in (stops the moment they step out)
	GasToastNearStuds = 45, -- Round 25: vault / office / zone gas toasts (top centre) show only this close (zones: to the box)
	VaultGasMaxSec = 20, -- Round 25: the vault seals this long after the gas whoever is inside (they're moved out)
	VaultEjectStuds = 4, -- Round 19c: a player inside the sealed vault (walked in as the door shut) lands this far out on the landing side
	-- Brief 5: the CRACK THE VAULT draw is impossible to miss.
	VaultStampSec = 1.5, -- the center VAULT JOB stamp
	VaultDoorPulseSec = 1.2, -- the door pulses amber (with a light) once per this, until cracked
	VaultArrowSec = 10, -- the chevron strip from the crew to the door stays this long
	-- Brief 7: THE BANK's vault is the wheel door at the foot of the stairwell (D4).
	VaultWheelSpinSec = 1.2, -- the wheel spins this long...
	VaultDoorSwingSec = 1.5, -- ...then the door swings in over this long (the server door with it)
	VaultPillTunnelText = "TUNNEL OPEN", -- the vault pill's line while the tunnel is open (the map is a ring)
	HatchOneWayAfterSeal = true, -- the hatch stays open for the rest of the run once the vault has opened

	------------------------------------------------------------------ Audio (Round 19d; UI.sound, Client/Music.lua)
	-- Two faders: every sound effect plays through the SFX SoundGroup, the soundtrack through Music.
	SfxVolume = 1,
	MusicVolume = 0.32,
	SfxMaxVoices = 6, -- copies of one sound playing at once; the oldest stops (full-auto fire stays readable)
	-- Per Theme.Sounds key: a volume trim to level the assets (missing = 1)...
	SfxGain = { shot = 0.9, glass = 0.9, hiss = 0.7, shutter = 0.6, alarm = 0.9, whiz = 1.1 },
	-- ...and a random pitch spread (± share) so repeats never sound identical (missing = 0: UI chimes stay in tune).
	SfxPitchJitter = {
		shot = 0.05,
		hit = 0.04,
		kill = 0.05,
		body = 0.08,
		take = 0.03,
		reloadOut = 0.04,
		reloadIn = 0.04,
		crunch = 0.06,
		glass = 0.08,
		cash = 0.03,
		coins = 0.05,
		lootTick = 0.03,
		snip = 0.06,
		whiz = 0.12,
		hurt = 0.06,
	},
	ReloadSeatShare = 0.7, -- the mag-in click lands this far through a magazine reload (and the reload animation seats the mag)
	-- Art pass: stand-in gun models (GunModels.lua) and the procedural hold / aim / fire / reload animation
	-- (GunAnim.client.lua). Every client poses every crew member's arms and gun; nothing here is an uploaded asset.
	GunModelScale = 1, -- every gun's size (held, floor, store, icons)
	GunAnimEnabled = true, -- false: guns hang from the hand like the old block
	GunPoseBlendSec = 0.18, -- arms ease into / out of the gun pose (emotes, the downed crawl and cutscenes take the arms)
	GunAdsBlendSec = 0.12, -- hip <-> aimed raise
	GunAimPitchMax = 40, -- degrees the gun tilts up / down toward the aim point
	GunAimYawMax = 25, -- degrees it turns left / right of the body toward the aim point
	GunTorsoAimShare = 0.35, -- share of the aim pitch the upper body leans into
	GunPoseSendHz = 10, -- how often your aim pitch / ADS / reload state goes out so teammates see your pose
	-- Per gun kind (GunModels kinds): `blade` = the stance twist (degrees the chest turns right so the left hand
	-- reaches the handguard; the head turns back). hip / ads: which gun point is placed (butt = the stock's pad,
	-- grip = the pistol grip, sight = the sight line at the rear) and where, relative to the middle of the shoulders
	-- facing the aim (x right, y up, z back, studs), plus the gun's tilt (pitch up, yaw left, roll, degrees).
	GunPoses = {
		pistol = {
			blade = 15,
			hip = { anchor = "grip", pos = Vector3.new(0.3, -0.4, -0.95), rot = Vector3.new(-4, 2, 0) },
			ads = { anchor = "sight", pos = Vector3.new(0.2, 0.55, -0.85), rot = Vector3.new(0, 0, 0) },
		},
		smg = {
			blade = 40,
			hip = { anchor = "butt", pos = Vector3.new(0.4, -0.3, 0.55), rot = Vector3.new(-3, 4, 0) },
			ads = { anchor = "sight", pos = Vector3.new(0.2, 0.55, 0.6), rot = Vector3.new(0, 0, 0) },
		},
		rifle = {
			blade = 45,
			hip = { anchor = "butt", pos = Vector3.new(0.4, -0.3, 0.6), rot = Vector3.new(-3, 4, 0) },
			ads = { anchor = "sight", pos = Vector3.new(0.2, 0.55, 0.65), rot = Vector3.new(0, 0, 0) },
		},
		bullpup = {
			blade = 40,
			hip = { anchor = "butt", pos = Vector3.new(0.4, -0.3, 0.8), rot = Vector3.new(-3, 4, 0) },
			ads = { anchor = "sight", pos = Vector3.new(0.2, 0.55, 0.85), rot = Vector3.new(0, 0, 0) },
		},
		shotgun = {
			blade = 45,
			hip = { anchor = "butt", pos = Vector3.new(0.4, -0.3, 0.6), rot = Vector3.new(-4, 4, 0) },
			ads = { anchor = "sight", pos = Vector3.new(0.2, 0.5, 0.65), rot = Vector3.new(0, 0, 0) },
		},
		sniper = {
			blade = 45,
			hip = { anchor = "butt", pos = Vector3.new(0.4, -0.3, 0.65), rot = Vector3.new(-4, 4, 0) },
			ads = { anchor = "sight", pos = Vector3.new(0.2, 0.5, 0.7), rot = Vector3.new(0, 0, 0) },
		},
		lmg = {
			blade = 45,
			hip = { anchor = "butt", pos = Vector3.new(0.4, -0.4, 0.6), rot = Vector3.new(2, 5, 0) },
			ads = { anchor = "sight", pos = Vector3.new(0.2, 0.5, 0.7), rot = Vector3.new(0, 0, 0) },
		},
		-- Round 24v: launchers ride the shoulder, elemental guns sit at the hip like a rifle, TNT is held out.
		launcher = {
			blade = 40,
			hip = { anchor = "grip", pos = Vector3.new(0.45, 0.05, -0.2), rot = Vector3.new(0, 3, 0) },
			ads = { anchor = "sight", pos = Vector3.new(0.25, 0.55, 0.45), rot = Vector3.new(0, 0, 0) },
		},
		energy = {
			blade = 40,
			hip = { anchor = "butt", pos = Vector3.new(0.4, -0.35, 0.6), rot = Vector3.new(-2, 4, 0) },
			ads = { anchor = "sight", pos = Vector3.new(0.2, 0.5, 0.65), rot = Vector3.new(0, 0, 0) },
		},
		thrown = {
			blade = 15,
			hip = { anchor = "grip", pos = Vector3.new(0.35, -0.2, -0.8), rot = Vector3.new(-10, 5, 0) },
			ads = { anchor = "grip", pos = Vector3.new(0.3, 0.1, -0.85), rot = Vector3.new(-5, 0, 0) },
		},
	},
	-- Recoil per kind: kick = studs the gun jumps back, rise = degrees the muzzle flips up (each shot; a spring pulls
	-- it home). Aimed shots kick GunAdsRecoilMult as hard.
	GunRecoil = {
		pistol = { kick = 0.16, rise = 10 },
		smg = { kick = 0.07, rise = 3 },
		rifle = { kick = 0.11, rise = 4.5 },
		bullpup = { kick = 0.09, rise = 3.5 },
		shotgun = { kick = 0.3, rise = 14 },
		sniper = { kick = 0.35, rise = 12 },
		lmg = { kick = 0.09, rise = 3 },
		launcher = { kick = 0.32, rise = 9 },
		energy = { kick = 0.04, rise = 1 },
		thrown = { kick = 0.12, rise = 6 },
	},
	GunAdsRecoilMult = 0.6,
	GunRecoilSpring = 260, -- stiffness of the return (higher = snappier)
	GunRecoilMaxStack = 2.5, -- full-auto kick stacks up to this many single kicks
	GunSlideTravel = 0.3, -- studs a pistol slide runs back per shot (it locks back on an empty mag)
	GunCycleDelay = 0.08, -- seconds after a shot before a pump / bolt / lever gun cycles
	GunCycleSec = 0.4, -- longest a pump / bolt / lever cycle takes (shorter on fast-firing guns)
	GunReloadTilt = Vector3.new(14, 8, -30), -- the gun's tilt during a reload (pitch up, yaw left, roll) in degrees
	GunReloadPull = Vector3.new(-0.15, -0.15, -0.1), -- and how far it comes in toward the chest (x right, y up, z back)
	GunPouchOffset = Vector3.new(-0.75, -1.15, -0.25), -- the left hand's mag / shell pouch on the belt (torso space)
	GunMuzzleFlash = true,
	GunMuzzleFlashSec = 0.05,
	GunMuzzleFlashColor = "FFD27A",
	GunShellCasings = true, -- brass flies out of the port
	GunCasingLifeSec = 1.2,
	-- The soundtrack follows the run: hub (yard, menus), run (Round 19e: one track carries on through waves,
	-- intermissions, the dealer, alarms and gas), boss (TITAN alive, the one deliberate mood shift), summary (run end).
	-- Each state picks a track from its list (APM library music, public domain on Roblox) and crossfades; a track
	-- left mid-way resumes where it was when its state comes back within MusicResumeSec. Empty list = silence.
	MusicEnabled = true,
	MusicFadeSec = 1.8,
	MusicResumeSec = 120,
	MusicDuck = 0.35, -- the music drops to this share of its volume under big moments (boss cutscene, run over)
	MusicTracks = {
		hub = { "rbxassetid://9038506583", "rbxassetid://1844258065" }, -- Diamond Heist (b), The Heist (a)
		-- Round 19e: in the lobby tracks' vein (their sister cuts and the same APM albums), not chase or ambient
		-- underscore; the second pass dropped the jazzy / lo-fi cuts (Smooth Operator, Half Stepper (b), Diamond
		-- Heist (c)) for driving heist funk and rock.
		run = {
			"rbxassetid://9038505017", -- Diamond Heist (a)
			"rbxassetid://1844239389", -- The Heist (c)
			"rbxassetid://1844258008", -- Masterstroke (a)
			"rbxassetid://1841824912", -- Solid Crew (a)
			"rbxassetid://1841825236", -- Casino Hustle (a)
		},
		boss = { "rbxassetid://1846875833", "rbxassetid://1841825685" }, -- The Shootout (a), Armed Raid (c)
		summary = { "rbxassetid://9045731376" }, -- Smooth Operator (Round 19e: Casino Hustle moved to the run)
	},

	------------------------------------------------------------------ Offices (Round 19f; Offices.lua, THE BANK only)
	-- The four glass offices (Office nodes) are RAID THE OFFICE jobs: a minigame blows the door, bags drop inside,
	-- then the room's alarm, gas, and the office seals (anyone inside is put out, its bags fizzle) until it resets.
	OfficeMinigames = { "Lockpick", "Hotwire", "Charges", "Cut" }, -- how a door goes (a random pick per job)
	OfficeMinWave = 1, -- drawable from this wave (its zone must be open too)
	OfficeCashBags = 6, -- dropped inside when it opens (scaled with the party like every burst)...
	OfficeGoldBags = 2, -- ...and gold bags
	OfficeBagInset = 3, -- studs: bags stay this far off the room's walls
	OfficeOpenSec = 30, -- the loot window, then...
	OfficeGasWarnSec = 8, -- ...the room's alarm rings this long...
	OfficeGasSec = 6, -- ...then gas (OfficeGasDps) this long, then it seals
	OfficeGasDps = 12,
	OfficeEjectStuds = 4, -- anyone inside at the seal lands this far outside the door
	OfficeFrontStuds = 4, -- the job's beacon stands this far outside the door
	OfficeCooldownWaves = 3, -- a sealed office can be drawn again this many waves later

	------------------------------------------------------------------ Alarms (Round 19c; Alarms.lua)
	-- THE BANK's alarm fixtures strobe red and every client hears the horn while any source holds the alarm on:
	-- the vault's gas warning, a whole heat star gained, SILENCE THE ALARM, the zone gas warning.
	AlarmPartNames = { "alarm" }, -- the asset's fixtures (geometry part names)
	AlarmStrobeSec = 0.25, -- half a strobe cycle
	AlarmLightRange = 24, -- studs: the red light on each fixture
	AlarmHeatUpSec = 3, -- a whole star gained rings the alarm this long (0 = never)
	AlarmHornEverySec = 1.1, -- client: the horn repeats this often while ringing
	AlarmHornVolume = 0.35,
	AlarmScreenAlpha = 0.9, -- client: the red edge pulse peaks at this transparency (1 = none)
	-- Round 19d: SILENCE THE ALARM's panel opens one of these minigames (a random pick per job), not a hold.
	AlarmJobMinigames = { "Keypad", "Freq", "Charges", "Hotwire" }, -- Round 19e: the ones that fit an alarm panel
	-- Round 19e: THE BANK's first side job of a run (wave SideJobFirstWave, on the street) is always this kind, and for
	-- SILENCE THE ALARM this minigame ("" = roll as usual).
	BankFirstJobKind = "alarm",
	BankFirstJobGame = "Keypad",

	------------------------------------------------------------------ Zone gas (Round 19c; ZoneGas.lua, THE BANK only)
	-- Every few waves the zone the crew holds is gassed so nobody camps one room: alarm + warning, then gas.
	ZoneGasEnabled = true,
	ZoneGasFirstWave = 10, -- the first event can come at this wave (Round 19e: 4 -> 10; a boss wave pushes it on)...
	ZoneGasEveryWaves = { 3, 5 }, -- ...then the next one this many waves later (a random pick in the range)
	ZoneGasDelaySec = 12, -- into the wave before the warning (the crew has settled)
	ZoneGasWarnSec = 10, -- the alarms ring and the toast counts this long before the gas
	ZoneGasSec = 25, -- the gas hangs in the zone this long
	ZoneGasDps = 10, -- to anyone standing in the gassed zone
	ZoneGasHeight = 12, -- studs of each zone volume (from its floor) the cloud fills
	ZoneGasParticlesPerArea = 0.03, -- emitter rate per square stud of zone floor (capped at 400 a volume)
	ZoneGasSkipZones = { "vault", "tunnel" }, -- never gassed, and not a refuge (the vault has its own gas)
	-- Round 19d: lockdown gas. A door objective still shut DoorForceAfterWaves waves after the wave it was called for
	-- floods every zone except the ones that door opens: alarms and a countdown first, then gas until the door is open;
	-- chevrons from every player, the door's loud beacon and a screen-edge arrow point at it the whole time.
	DoorForceEnabled = true,
	DoorForceAfterWaves = 2, -- waves the crew gets (D1 called for wave 3 -> lockdown at wave 5)
	DoorForceDelaySec = 8, -- into the wave before the warning
	DoorForceWarnSec = 10, -- the alarms ring and the toast counts this long before the gas
	DoorForceGasDps = 5, -- lower than ZoneGasDps: the crew crosses the map and plays the door's minigame in it
	DoorForceLingerSec = 6, -- the gas hangs this long after the door opens (time to step through), then clears
	DoorForceArrowEverySec = 8, -- the chevrons from each standing player to the door refresh this often
	DoorForceParticleMult = 0.5, -- the cloud's emitter rate x this (it fills the whole map)

	------------------------------------------------------------------ Progression (account level; Progression.lua, LevelRewards.lua)
	-- XP per run, per player: XpPerWave x waves cleared + XpPerKill x kills + XpPerJob x jobs + XpPerBoss x boss kills
	-- + XpSurvivedPerMin x minutes survived, x XpFirstHeistMult on the first completed run of a UTC day.
	XpPerWave = 50,
	XpPerKill = 2,
	XpPerJob = 60,
	XpPerBoss = 300,
	XpSurvivedPerMin = 20,
	XpFirstHeistMult = 2.0,
	XpCurveBase = 400, -- XpToLevel(n) = XpCurveBase x n ^ XpCurvePow, no cap; overflow carries into the next level
	XpCurvePow = 1.4,
	LevelGold = 100, -- Gold on every level-up (plus the milestone rewards in LevelRewards.lua)
	XpFillSec = 1.2, -- the summary XP bar fills over this long after the Gold count-up
	RosterSyncSec = 1, -- the scoreboard roster resends this often

	------------------------------------------------------------------ Mastery (brief 5; server Mastery.lua, copy in MasteryCopy.lua)
	-- Accrues in the run, lands in the profile at the summary. Weapon XP per kill with that gun; class XP per wave
	-- played as that class. Class passives are always on while the class is equipped, at the tier the run started at.
	MasteryXpPerKill = 1,
	MasteryXpPerEliteKill = 3,
	MasteryXpPerBossKill = 50,
	WeaponMasteryTiers = { 100, 400, 1200 }, -- kills (placeholders)
	MasteryXpPerWave = 1,
	MasteryXpPerBossWave = 3,
	ClassMasteryTiers = { 20, 60, 150 }, -- waves
	MasteryWrapIds = { "gunmetal", "masterygold", "blackred" }, -- weapon tier 1 / 2 / 3 unlock these wraps on that gun
	MasteryPopSec = 3.2, -- the mid-run tier-up card holds this long (cards queue; the reward is live at once)
	-- INITIATE
	StimMasteryHealPct = 0.25, -- I: Adrenaline heals this share of max HP on use
	MasteryExtraCharges = 1, -- II: Frag and Claymore hold this many extra charges
	StimExtendSec = 0.5, -- III: every kill during Adrenaline extends it this much...
	StimExtendCap = 6, -- ...up to this much extra per use
	-- ENGINEER
	EngineerPlaceablePct = 0.2, -- I: placeables +HP and +fire rate
	FieldRepairPct = 0.03, -- II: placeables regen this share of max HP a second...
	FieldRepairRange = 10, -- ...while no enemy is this close
	CrewOverclockFireRatePct = 0.25, -- III: Overclock also gives every crew member's gun this fire rate...
	CrewOverclockReloadPct = 0.25, -- ...and reload speed while it runs
	-- DOC
	DocReachPct = 0.3, -- I: Med Bag radius and Healing Turret range
	AutoReviveSec = 6, -- II: a downed (or bled-out) ally inside a Med Bag / Healing Turret range stands up over this long
	FieldHospitalHealMult = 2, -- III: Med Bag heal...
	FieldHospitalRadiusMult = 1.5, -- ...and radius...
	FieldHospitalDmgPct = 0.2, -- ...and allies inside deal this much more damage
	-- SHARPSHOOTER
	SharpHeadshotAdd = 0.3, -- I: added to the headshot multiplier
	MarksmanKitReloadPct = 0.25, -- II: snipers and pistols reload this much faster
	DeadEyeHeadshotCdr = 0.2, -- III: every headshot during Dead Eye puts a round back and trims this off its cooldown
	-- TORCH
	TorchBurnRateMult = 2, -- I: your burns (fire fields, INCENDIARY) tick this much faster
	BackdraftCdr = 0.1, -- III: every burning enemy that dies trims this off your Molotov cooldown

	------------------------------------------------------------------ Dealer (brief 5; Dealer.lua, DealerUI.lua)
	-- After every boss wave is cleared: a DealerSec break (no spawns, heat frozen) with a stall of per-player stands.
	DealerSec = 90,
	DealerRevivesCrew = true, -- Round 25: the DEALER's break stands every downed / bled-out member back up, free
	DealerLine = "Set up in the middle of the floor. You've got ninety seconds, then I'm gone.", -- the DEALER's call (match DealerSec)
	DealerStallPosition = Vector3.new(0, 0, 18), -- arena center for the prototype (clear of the center spawn)
	DealerStock = 8, -- upgrade cards per player
	DealerArcRadius = 9, -- the tables stand on a half circle this far round the DEALER...
	DealerTableAngles = { -58, 0, 58 }, -- ...at these angles (0 = straight toward the arena)
	DealerPerTable = 3, -- cards per table (the last takes what is left)
	DealerStandSpacing = 2.8, -- studs between cards on a table
	DealerTeleportDistance = 4, -- TELEPORT TO DEALER (any number of times) lands you this far outside the middle table
	DealerCardWidth = 190, -- the stand panel (a pick-3 card with a price bar), design px
	ShopReadRadius = 6, -- walking this close to a stand or prop opens its panel (the nearest one only)
	-- Round 19c: about a quarter cheaper across the stall (was 100 / 160 / 260 / 420 / 700, crate 800, heal 300, reroll 150).
	-- Round 21: stall prices scale with the wave (income does: CashWaveMult, CashBagPerWave), not with upgrades bought.
	-- Round 25: card = your current UPGRADE price x DealerCardPriceShare[tier] x DealerFirstBuyDiscount[n] (the nth
	-- card bought this break; past the list = 1). Every buy counts toward the UPGRADE escalation, so cards climb with
	-- it (Round 21's wave-only prices fell to $5-10k against a $100k upgrade).
	DealerCardPriceShare = { 0.6, 0.75, 0.9, 1.1, 1.35 }, -- common .. legendary (you pick the exact card, so tier costs)
	DealerFirstBuyDiscount = { 0.35, 0.6 }, -- the first two cards each break come cheap
	-- props = price x (1 + DealerPropWaveMult x (wave - 1)) (wave 10: crate $2.8k, heal $1k, reroll $506 doubling per use)
	DealerPropWaveMult = 0.4,
	ShopCratePrice = 600, -- ARMS DROP: a crate at the stall for the party
	ShopHealPrice = 225, -- HEAL ALL: full HP for every member
	ShopRerollPrice = 110, -- REROLL: your eight stands again; doubles per use
	DealerWarnSec = { 15, 5 }, -- Round 21: "DEALER LEAVES IN Ns" warnings this many seconds before the stall packs up

	------------------------------------------------------------------ Pause (brief 5; Pause.lua)
	PauseMaxSec = 300, -- a pause lasts this long, then resumes by itself...
	PauseExtendSec = 300, -- ...VOTE TO EXTEND (everyone) adds this, as many times as the party agrees
	PauseCountdownSec = 10, -- ...after this long a countdown on the overlay

	------------------------------------------------------------------ Boss (TITAN, Boss.lua; step 5 of brief 4)
	BossWaveInterval = 10, -- the first boss wave and every multiple after (0 = never)
	BossWaveBudgetPct = 0.4, -- boss waves spawn this share of the normal budget alongside the boss
	BossParBonusSec = 30, -- added to a boss wave's par (computed on the regular budget)
	BossId = "Titan", -- which boss the boss waves bring (Bosses/<id>.lua; the shell takes any id)
	BossCutsceneSec = 4.0, -- the intermission's boss cutscene: game paused, players invulnerable and input-locked
	BossCutsceneBeats = { call = 0, blow = 0.8, gun = 2.2, back = 3.4 }, -- seconds: MARLOW's call and the low wall shot, the wall blows and the boss steps through, barrels spin and the name card, camera snaps back and the bar slides in
	BossAbilityGapSec = 1.5, -- the boss walks and swings this long between abilities
	BossBagBurst = 6, -- bags around the body on a kill (half cash, half gold)
	BossBagBurstRadius = 18, -- a wide ring, clear of the crate on the body
	-- TITAN
	TitanHp = 4000, -- x the wave HP scaling x the player count multiplier
	TitanSpeed = 5, -- (brief: 7, cut a third with the roster)
	TitanMeleeDmg = 23, -- (brief: 35)
	TitanKnockback = 12, -- contact knockback, like the Heavy
	TitanScale = 1.8,
	TitanPhasePcts = { 0.66, 0.33 }, -- phase 2 (plates 1-2 fall, faster sweep spin) and phase 3 (plates 3-4 fall, call-ins)
	TitanSweepSpinSec = 1.5, -- barrels spin with a glow, a rising whine and a faint cone on the floor...
	TitanSweepSpinSecP2 = 1.0, -- ...this long from phase 2
	TitanSweepSec = 3, -- the cone sweeps left to right over this long
	TitanSweepArc = 120, -- degrees
	TitanSweepRange = 40,
	TitanSweepWidth = 12, -- degrees either side of the beam that still counts as in it
	TitanSweepDps = 27, -- to players in the beam with LoS; placeables take it too (brief: 40)
	TitanSweepCooldown = 9,
	TitanChargeTelegraphSec = 1.0, -- red line on the floor from TITAN to the locked player
	TitanChargeSpeedMult = 6, -- (brief: 3; doubled in Round 14c)
	TitanChargeDmg = 33, -- the first player hit on the line (brief: 50)
	TitanChargeKnockback = 18,
	TitanChargeHitRadius = 5.5, -- studs either side of the run that count as hit: the telegraph rectangle is this wide
	TitanChargeOverrun = 12, -- studs past the locked player's position the run carries on to
	TitanChargeMaxSec = 3.5,
	TitanChargeCooldown = 12,
	TitanChargeMinRange = 12, -- a charge needs a player at least this far...
	TitanChargeMaxRange = 70, -- ...and at most this far
	TitanStaggerSec = 1.5, -- after hitting a wall: stands still...
	TitanStaggerDmgMult = 1.5, -- ...and takes this much more
	TitanVolleyTelegraphSec = 1.2, -- four red circles grow on the crew, then four Grenadier blasts with fire
	TitanVolleyCount = 4,
	TitanVolleyCooldown = 14,
	TitanCallInSec = 12, -- phase 3: Henchmen from the nearest marker this often...
	TitanCallInCount = 4, -- ...this many
	TitanCashBurst = 600, -- match cash to everyone on the kill

	------------------------------------------------------------------ HUD
	DebugEnabled = true,
	ComboWindowSec = 3, -- kills this close together chain into the multi-kill counter; the label fades this long after the last kill
	-- Combo words: the counter climbs every kill from x2; the word attaches at these counts ("x5 NICE").
	ComboTiers = {
		{ at = 5, name = "NICE" },
		{ at = 7, name = "GREAT" },
		{ at = 10, name = "AWESOME" },
		{ at = 15, name = "INSANE" },
		{ at = 20, name = "UNREAL" },
		{ at = 30, name = "GODLIKE" },
	},
	CallTypeCharsPerSec = 45, -- crew call dialogue typewriter speed
	WaveBannerHoldSec = 0.9, -- center WAVE N / WAVE CLEAR banner hold before it fades
	CountdownTickFrom = 3, -- the last N seconds of the intermission tick big in the center
	MarkerCompactDistance = 45, -- studs; further than this the beacon marker shrinks to an icon with distance + timer
	StragglerHighlightCount = 5, -- with this many or fewer enemies left, the survivors glow red through walls

	------------------------------------------------------------------ Room
	RoomSize = 200,
	WallHeight = 12,
	FloorTop = 0.5, -- y of the arena floor's top face; above the default Baseplate so nothing z-fights

	PillarGrid = 5, -- NxN pillars, the center one is skipped so the spawn stays clear
	PillarSize = 4,

	------------------------------------------------------------------ Hub (brief 8: the warehouse; where things stand is its nodes)
	MatchMode = "local", -- "local": the party plays in this server's maps. Reserved servers / TeleportService are out of scope.
	HubCash = 0, -- Match Cash shown in the hub (nothing to buy there)

	------------------------------------------------------------------ Maps (brief 7; the rows live in src/shared/Maps.lua)
	DefaultMap = "TheBank", -- the map a fresh Create Match card picks (and the fallback for an unknown id)
	BankOrigin = CFrame.new(0, 0, -1000), -- where THE BANK model is pivoted on load (the import baked it here)

	------------------------------------------------------------------ The hub (brief 8: the warehouse)
	HubOrigin = CFrame.new(0, 0, 1000), -- where the hub bakes: the floor logo (the star, the spawn) lands here
	HubImportDrop = { "Helicopter" }, -- models tools/importhub.luau drops (matched against the part names inside)
	-- Brief 10: models dropped by where they stand (the builder's unnamed ones): every model directly under the place
	-- whose name is in `models` and whose centre lies within `radius` studs (x / z from the floor star) of `at`.
	-- Round 27b: the red and blue drums on the hall floor in front of the loading platform (west side, south of its
	-- steps; two unnamed `Model`s of MeshParts) make room for the daily crate podium, in view from the star.
	HubImportDropAt = {
		{ name = "Barrels", models = { "Model" }, at = { -31.8, -14.6 }, radius = 3.5 },
	},
	-- Round 25: the booth keepers are three R15 NPCs (server-built from these avatars' HumanoidDescriptions, a
	-- plain body-coloured R15 if the fetch fails), named on a small tag that shows only right by the stall
	-- (fading out over BoothNpcTagFadeNear..Far) and hides while a menu is open. Keyed by the booth's Tab. (Replaces Round 20's
	-- BoothMannequin: the rigs wore your own character.)
	BoothNpcs = {
		WEAPONS = { name = "DUKE", role = "GUNSMITH", userId = 156 },
		CLASSES = { name = "SABLE", role = "TRAINER", userId = 261 },
		AVATAR = { name = "NOVA", role = "STYLIST", userId = 1 },
	},
	BoothNpcIdleAnim = "rbxassetid://507766666", -- R15 default idle
	BoothNpcTagFadeNear = 18, -- studs: the name tag is solid this close...
	BoothNpcTagFadeFar = 34, -- ...and fades out by here
	BoothNpcTagOffset = 2.4, -- studs above the head
	RangeDoorOpen = true, -- the range's roll-up door stays up (false: it stays down and the range is shut)
	HubDepartSec = 2.5, -- run start: the party fades into the hub van, the garage rolls up, the van pulls out
	GarageCloseSec = 3, -- the garage rolls back down this long after the van has gone (everyone sees it)
	HubDoorRollSec = 1.2, -- a roll-up door's travel time
	HubVanDriveStuds = 60, -- how far the van drives out through the garage before it fades
	DoorSupersedesSideJob = false, -- THE BANK: true = a door coming due ends the running side job (quietly) and holds the only slot; false (Round 24) = doors have their own slot and the pills stack
	HubWalkSpeedMult = 2, -- walk speed in the hub (outside the range) x this; runs and the range walk at PlayerWalkSpeed
	PassStageLight = 1, -- the battle pass stage's front key and top light brightness x this (0 = off)
	PremiumSetAmbient = "4A4552", -- the ambient while a premium scene (pass, store, crate room) is up (was near-black)
	PremiumWindowScale = 0.9, -- Round 23: 0.84 -> 0.9 (the premium SHOP window and the JOBS board take this share of the screen each way)
	-- Round 21 day / night (client/DayNight.lua): wave 1 at RunClockStart, each wave RunClockPerWave hours later
	-- (20:00, 20:30, ... 06:00 dawn at wave 21), eased over RunClockTweenSec as the wave starts. The hub keeps the
	-- place's own Lighting.ClockTime. Jumps bigger than RunClockMaxTweenHours (debug wave skips) snap.
	RunClockStart = 20,
	RunClockPerWave = 0.5,
	RunClockTweenSec = 6,
	RunClockMaxTweenHours = 3,
	PassDragTurn = 0.012, -- radians per pixel when you drag the battle pass mannequin
	BoothWalkIn = true, -- walking onto a booth's orange half-circle opens the customization scene on its tab
	BoothPromptDistance = 12, -- only with BoothWalkIn off: OPEN (F) at a booth reaches this far
	BoardPromptDistance = 12, -- OPEN at MARLOW's board (the prompt is on MARLOW when he stands there)
	MarlowNpc = true, -- MARLOW stands in front of his board in the hub (the board's OPEN prompt is on him)
	MarlowOffset = 3.2, -- studs out from the board's face
	MarlowIdleAnimationId = "rbxassetid://507766388", -- the default R15 idle
	MarlowRole = "FIXER", -- Round 25: the line under his name on the keeper tag
	-- The training range (the old helicopter bay): armed inside, nothing pays, scores or persists.
	RangeAbilities = true, -- all three class abilities live inside the range (cooldowns as in a run)
	DummyCount = 3, -- dummies standing on the Dummy nodes (at most one per node)
	DummyScale = 1, -- the dummies' rig scale (1 = Henchman size)
	DummyHp = 5000, -- a dummy's HP bar (it refills at 0: dummies never die); the plates fall at the Heavy's shares of it
	DummyHeavyPlates = true, -- the Dummy node marked Plates is the plated sponge (elite look)
	DummyPlateRegrowSec = 5, -- its plates grow back this long after the last one fell
	RangeDpsWindowSec = 3, -- the dummy readout's DPS is the damage over the last this many seconds
	CrewZoneSyncSec = 0.5, -- the crew zone (the zone holding the most standing players) is recomputed this often
	JobPoolBankEnabled = false, -- true adds JobPool.BankDaily (OPEN 3 DOORS ON THE BANK, ESCAPE THROUGH THE TUNNEL) to the dailies

	------------------------------------------------------------------ Doors (brief 7; per-door numbers live on the Door nodes)
	-- Overrides a Door node's TriggerWave when set (D4 is the vault draw). Round 19d: D5 chains the vault stairwells
	-- (the shutters open only the back now), so the vault is reachable once D5 is open.
	-- Round 19g: front doors 2, upper floor 5, back of the ground floor 8, the vault stairwells 12 (the first forced
	-- vault is then wave 15, VaultJobEveryWaves). Was D1 3, D3 7, D2 11, D5 14.
	DoorTriggerWave = { D1 = 2, D2 = 5, D3 = 8, D5 = 12 },
	-- Round 21: a door job that comes up while a standing crew member is already inside a zone it opens (in through a
	-- shot-out window) counts as done at once: the door breaks open (credit, cash bags) so enemies can pour through.
	DoorOpensIfCrewInside = true,
	-- Round 19g: a door called for the first time guides the crew there: floor chevrons from every standing player,
	-- re-planned every DoorGuideRefreshSec for DoorGuideSec (or until it opens), its loud beacon, and a screen-edge
	-- arrow whenever the door is off screen.
	DoorGuideSec = 0, -- Round 19h: 0 = the guide (chevrons, loud beacon, edge arrow) stays up until the door opens
	DoorGuideRefreshSec = 5,
	DoorInteractTime = 3, -- hold length at a door (a node's InteractTime overrides)
	DoorOpenCashReward = 400, -- per player when a door opens (a node's CashReward overrides)
	DoorHoldSec = 2, -- a released hold keeps its fill this long, then resets
	DoorOpenShake = 0.9, -- camera shake when a door opens
	DoorSignText = "UNLOCKS · WAVE %d", -- the sign board on a closed door
	DoorBeaconRange = 150, -- Round 19: a closed door's beacon shows within this many studs (only the next unlock has one)
	ZoneOpenCashBags = 3, -- a door's done drops this many cash bags on the opened zone's spots (bypasses the cap)...
	ZoneOpenGoldBags = 1, -- ...and this many gold bags
	BagOtherZoneMult = 2, -- bag spots outside the crew zone weigh this much more (bags pull the crew through the map)
	JobOtherZoneMult = 1.5, -- the same for side-job spots
	SideJobOutsideZones = { "street" }, -- Round 19d: once a zone inside the bank is open, no side job draws in these

	------------------------------------------------------------------ Nodes (brief 7: THE BANK's Workspace.Bank.Nodes)
	BreakableNames = { "bankwindow", "bankwindow2" }, -- Round 19: glass panes a shot or a blast breaks (then open)
	WindowShards = 10, -- shards per broken pane
	WindowGroupMaxParts = 12, -- Round 19c: a pane inside a model this small breaks with the whole model (its frame bars)
	WindowGroupMargin = 1, -- studs: see-through parts this close to a pane's box break with it (the glass sheet)
	WindowHitboxThickness = 1, -- studs: the invisible hit box over each pane (a shot anywhere on the window lands)
	-- Round 19e: loose see-through glass sheets of these sizes (studs, any axis order, ±0.3) break like windows too.
	BreakableGlassSizes = {
		{ 31.8, 8.3, 0.1 }, -- the teller counter's glass (two sheets, one per half)
	},
	EnemyPassNames = { "barrier" }, -- Round 19: THE BANK's geometry parts with these names stop players, not enemies
	MapLoaderStrict = false, -- true = refuse to start a run on a map with node errors ([GHS Map] ERROR lines)
	-- Debug Show nodes: the translucent box colour per node type.
	NodeShowColor = {
		Zones = "4D9FE8",
		Doors = "E8B64C",
		SpawnBoxes = "E8554D",
		BagSpots = "F2C14E",
		JobSpots = "6FB8FF",
		BossWalls = "8A2A2A",
		DealerSpots = "9BA0A8",
		Van = "9BA0A8",
		Lineup = "9BA0A8",
		Hatch = "9BA0A8",
		VaultRoom = "8FE3A1",
		Fences = "C9C4B8", -- Round 19c
		Offices = "E69D5E", -- Round 19f
		-- Brief 8: the hub's types.
		Spawn = "8FE3A1",
		QueuePads = "4D9FE8",
		Stations = "E8B64C",
		Board = "F2C14E",
		GarageDoor = "C9C4B8",
		RangeDoor = "C9C4B8",
		Range = "E8554D",
		Dummies = "E8554D",
		PropSpots = "6FB8FF",
		TierPad = "6FB8FF",
		DailyCrate = "E8B64C", -- brief 10
	},
	-- Round 19c: Fence nodes (the strip behind the bank) become solid site hoardings in these colours.
	FenceColor = "3B4048",
	FencePostColor = "23262B",
	FencePostSpacing = 8, -- studs between posts

	------------------------------------------------------------------ Queue zone / Create Match
	MaxPartySize = 4,
	QueueCountdownSec = 15, -- from CREATE; a full party or a party of 1 starts at once
	-- Brief 8: every pad holds its own party; runs on different maps play at once. The map geometry is one copy
	-- (doors, windows and the vault are stateful), so a second party on a busy map waits on its pad.
	MapInstancesPerMap = 1, -- parties per map at once (above 1 needs map copies: out of scope, capped to 1)
	MapBusyAutoStart = true, -- a waiting party starts the moment its map frees (false: its countdown restarts)
	PadBoardWidth = 8, -- studs wide, the billboard over each queue pad (its height follows)
	PadBoardLift = 4.5, -- studs above the middle of the pad
	MapBusyText = "MAP BUSY · %s IS INSIDE", -- the pad's billboard line while it waits (%s = the crew inside)
	-- Round 16: difficulty is live. Each row scales enemy HP (hpMult) and damage (dmgMult), the wave's enemy count
	-- (budgetMult) and the run's Gold payout (goldMult). Top waves are kept per map:difficulty.
	QueueDifficulties = {
		{ id = "Normal", name = "NORMAL", hpMult = 1.0, dmgMult = 1.0, budgetMult = 1.0, goldMult = 1.0 },
		{ id = "Hard", name = "HARD", hpMult = 1.4, dmgMult = 1.3, budgetMult = 1.2, goldMult = 1.5 },
		{ id = "Nightmare", name = "NIGHTMARE", hpMult = 2.0, dmgMult = 1.6, budgetMult = 1.4, goldMult = 2.25 },
	},

	------------------------------------------------------------------ Meta (profiles, Armory levels, classes, masks)
	StartingGold = 10000, -- fresh profile
	ProfileAutosaveSec = 60,
	ProfileSaveDebounceSec = 2, -- purchases / equips within this window write once
	-- Round 24ac: Armory levels are mostly damage; the rest soft-caps so the gun keeps its archetype.
	UpgDmgPct = 0.06, -- weapon base damage x (1 + UpgDmgPct x level) (was 0.05)
	UpgSoftCap = { mag = 0.25, reload = 0.2, rate = 0.1 }, -- the most a level can ever add: +25% mag, reload / 1.2, +10% fire rate
	UpgSoftScale = 15, -- the level at which ~63% of that cap is reached (LV 30: ~86%)
	RarityUpgCostMult = 1.0, -- upgrade cost = upgBaseCost x this ^ level
	AbilityGrowthPct = 0.1, -- default growth per ability level for every upgradeable variable (AbilityGrowth.lua)
	-- Round 24ae: soft caps. Variables whose name ends with these grow at the usual rate at first, then level off at
	-- base x (1 + cap): a flashbang's reach can at most double, a slow can't creep toward 100%. Damage / heal / HP / DPS
	-- aren't listed and keep growing in a straight line.
	AbilitySoftCapBy = {
		Radius = 1.0, -- reach: up to 2x
		Range = 1.0,
		SlowPct = 0.8, -- slows: up to 1.8x (Eagle Eye 35% -> 63%, Molotov / Oil Drum 30% -> 54%)
		Duration = 1.0, -- stuns and the like: up to 2x
		Pct = 1.5, -- buff percentages (fire rate, reload, move, accuracy, Overclock rate): up to 2.5x
		Pierce = 2.0,
		DmgPct = 0, -- 0 = no cap: damage buffs (Dead Eye) keep growing like damage does
	},
	-- Per-ability exceptions ("<abilityId>.<variable>"): Eagle Eye is the long-range read: up to 3x (60 -> 180 studs,
	-- most of a map but not all of it).
	AbilitySoftCap = {
		["eagleeye.EagleEyeRadius"] = 2.0,
	},
	-- Character idle in the customization scene, per equipped class (default R15 idles stand in).
	ClassIdleAnimationId = {
		INITIATE = "rbxassetid://507766388",
		ENGINEER = "rbxassetid://507766388",
		DOC = "rbxassetid://507766666",
		SHARPSHOOTER = "rbxassetid://507766388",
		TORCH = "rbxassetid://507766388",
	},
	MetaCameraDistance = 7.5, -- studs from the character in the customization scene (closer = bigger avatar)
	MetaCameraSideShare = 0.72, -- the camera sits this x distance to the character's left, so the avatar reads about a fifth in from the left edge
	MetaCameraHeight = 0.2, -- camera height relative to the character's center in the scene
	MetaCameraAim = -1.6, -- the camera aims this far below the character's center, so the avatar sits high in the frame (head near the top)
	MetaDragSensitivity = 0.012, -- radians per pixel when dragging the avatar round in the scene (Round 24: drag right turns it right)
	MetaCameraTweenSec = 0.45,
	MetaWrapZoomDistance = 3.5, -- CUSTOMIZE camera distance when no showcase gun could be built (fallback)
	-- Round 19h: CUSTOMIZE shows the gun alone, side-on (the avatar hides), spinning in as it opens.
	MetaGunStageForward = 3, -- studs in front of the avatar the showcase gun floats
	MetaGunStageHeight = 1.3, -- studs above the avatar's root
	MetaGunStagePad = 1.95, -- framing margin (1 = the gun's length fills the screen width); Round 19h: 1.3 -> 1.95
	MetaGunStageMinDistance = 1.8, -- the camera never gets closer than this (pistols)
	MetaGunStageLift = 0.12, -- share of the screen the gun sits above centre (clear of the bottom strip)
	MetaGunSpinSec = 0.9, -- the opening spin
	MetaGunSpinTurns = 1, -- full turns in the opening spin
	MetaGunStageBob = 0.03, -- studs of slow up / down float
	UpgradeTakeVolume = 0.5, -- Round 19k: the upgrade pick sound (Theme.Sounds.upgrade) at Roblox's default volume, pitch 1
	-- Round 19l: particles on picking an upgrade (Juice.sparks: GUI chips, a shockwave ring and a glow). Sizes and
	-- speeds are px on the 760 UI basis.
	UpgradeFxEnabled = true,
	UpgradeFxSparkBase = 14, -- chips off the card...
	UpgradeFxSparkPerTier = 5, -- ...plus this many per card tier (common 19, legendary 39)
	UpgradeFxSparkSpeed = 560, -- the fastest chip, px/s
	UpgradeFxSparkSize = 10, -- chip size, px
	UpgradeFxUpBias = 0.35, -- share of the speed added upward (a fountain)
	UpgradeFxGravity = 1400, -- px/s²
	UpgradeFxDrag = 2.2, -- per second (higher = chips stop sooner)
	UpgradeFxLife = 0.65, -- seconds
	UpgradeFxRingSize = 300, -- the shockwave ring's end size, px
	UpgradeFxTrailSparks = 2, -- sparkles left behind the flying icon every UpgradeFxTrailEvery seconds
	UpgradeFxTrailEvery = 0.035,
	UpgradeFxArriveSparks = 12, -- the pop at the tracker tile
	JuiceFxDisplayOrder = 20, -- the particle layer draws over the overlays (the upgrade overlay is 10)
	-- Round 19m: the premium scene sets (store showroom, crate room, pass stage) sit in a row of sealed rooms close to
	-- the hub so their lights are lit the moment a scene opens. Brief 8: the hub is the warehouse at HubOrigin, so they
	-- sit well under its floor (its lowest part is about y -14). Middle room here, the others PremiumSetsSpacing to each side (x).
	PremiumSetsOrigin = Vector3.new(0, -60, 1000),
	PremiumSetsSpacing = 56,
	KillBodyVolume = 0.22, -- Round 19h: the soft body drop under the kill tick
	MetaWeaponPreview = true, -- tapping a gun in the Weapons tab puts it in the avatar's hand (local only; the real one comes back on leaving the tab or closing)
	MetaTileHoverScale = 1.05, -- customization tiles grow this much under the cursor (scale only, they never move)
	MetaSelectPopScale = 1.1, -- the tile you just tapped pops from this scale back to 1
	MetaSuccessSparks = 30, -- Round 25: sparks off a button on a successful upgrade (unlocks / buys: x1.5)
	MetaEquipBadgeShare = 0.36, -- the big equipped check on a tile, as a share of the tile's width

	------------------------------------------------------------------ Skills (brief 9: the Skill Web; Skills.lua, SkillService.lua)
	-- 90 one-time account perks bought with Gold in the hub (the SKILLS tile). Every value below is a sample.
	SkillsEnabled = true, -- false hides the SKILLS tile and every node stops applying (modifiers are all zero)
	SkillCostByRing = { 500, 1500, 4000, 10000, 25000 }, -- Gold per node by ring (1 = next to START), before the stat's weight
	-- Round 26b: costs differ inside a ring so the choices aren't all equal. A node costs its ring's base x its stat's
	-- weight here (1 when missing) x (1 + SkillCostRepeatStep per earlier node of the same stat in its branch), rounded
	-- to a tidy number. A third field on a SkillNodes entry ({ stat, value, weight }) overrides the stat's weight.
	SkillCostByStat = {
		damage = 1.3,
		crit = 1.15,
		headshot = 1.0,
		elite = 0.9,
		boss = 0.8,
		ability = 0.95,
		maxHp = 1.2,
		armor = 1.1,
		regen = 0.85,
		tough = 1.25,
		armorRecovery = 0.8,
		revive = 0.7,
		lastStand = 0.65,
		move = 0.9,
		reload = 1.05,
		cooldown = 1.15,
		quickHands = 0.7,
		bagValue = 1.0,
		magnet = 0.75,
		fastHands = 0.8,
		fence = 1.3,
		seedMoney = 0.85,
		haggle = 1.1,
		cardLuck = 0.8,
		dealerLuck = 0.9,
		crateLuck = 1.0,
		pistols = 0.7,
		smgs = 0.9,
		rifles = 1.0,
		shotguns = 0.95,
		snipers = 0.85,
		lmgs = 0.9,
		explosives = 1.05,
		elemental = 1.05,
		pistolMags = 0.7,
		smgMags = 0.75,
		rifleMags = 0.8,
		shotgunShells = 0.85,
		sniperMags = 0.9,
		lmgBelts = 0.75,
		explosiveAmmo = 1.2,
	},
	SkillCostRepeatStep = 0.1, -- DAMAGE II costs 10% more than DAMAGE I would at the same ring, III 20% more...
	LuckOddsStep = 0.03, -- each LUCK node moves this share of the tier weights off the lowest tier onto the higher ones
	SkillZoomMin = 0.55, -- the web's smallest zoom (also never smaller than "the whole web fits")
	SkillZoomMax = 1.6,
	SkillStartCost = 250, -- Round 26c: START is bought too (UNLOCK SKILLS): it opens the web; ring 1 waits as ? until then
	SkillOpenZoom = 1.6, -- Round 26b: the web opens centred on START at this zoom (clamped to Min / Max)
	SkillHexPx = 64, -- a hex's width (corner to corner) at zoom 1, px at the UI basis (mobile never under 56 px)
	SkillNewPulseSec = 1.5, -- a hex that became affordable since the last visit pulses once this long on open
	SkillBuyRateSec = 0.25, -- the server refuses a second buy from the same player inside this
	-- The nodes, per branch, per ring (ring 1 next to START), in slot order (the order a ring's cells run clockwise).
	-- { stat, value }: the stat keys are Skills.lua's (STATS); percents are fractions (0.03 = +3%), armor / regen /
	-- bleed-out / seed money are flat, luck nodes are counts (each LuckOddsStep). Names, ids and numerals come from
	-- the order: the first "damage" in DAMAGE is DAMAGE I (id damage_damage_1), the next DAMAGE II.
	SkillNodes = {
		DAMAGE = {
			{ { "damage", 0.03 } },
			{ { "crit", 0.02 }, { "headshot", 0.05 } },
			{ { "damage", 0.03 }, { "elite", 0.05 }, { "ability", 0.05 } },
			{ { "crit", 0.02 }, { "boss", 0.05 }, { "damage", 0.03 }, { "headshot", 0.05 } },
			{ { "elite", 0.05 }, { "boss", 0.05 }, { "ability", 0.05 }, { "crit", 0.02 }, { "damage", 0.04 } },
		},
		SURVIVAL = {
			{ { "maxHp", 0.08 } },
			{ { "armor", 10 }, { "regen", 0.5 } },
			{ { "maxHp", 0.08 }, { "tough", 0.03 }, { "revive", 0.15 } },
			{ { "armor", 10 }, { "armorRecovery", 0.15 }, { "regen", 0.5 }, { "lastStand", 5 } },
			{ { "maxHp", 0.08 }, { "armor", 15 }, { "tough", 0.04 }, { "armorRecovery", 0.15 }, { "revive", 0.15 } },
		},
		SPEED = {
			{ { "move", 0.02 } },
			{ { "reload", 0.06 }, { "cooldown", 0.04 } },
			{ { "move", 0.02 }, { "quickHands", 0.1 }, { "reload", 0.06 } },
			{ { "cooldown", 0.04 }, { "quickHands", 0.1 }, { "move", 0.02 }, { "reload", 0.06 } },
			{ { "cooldown", 0.04 }, { "quickHands", 0.1 }, { "move", 0.03 }, { "reload", 0.07 }, { "cooldown", 0.05 } },
		},
		CASH = {
			{ { "bagValue", 0.04 } },
			{ { "magnet", 0.15 }, { "fastHands", 0.15 } },
			{ { "fence", 0.04 }, { "seedMoney", 200 }, { "bagValue", 0.04 } },
			{ { "haggle", 0.04 }, { "magnet", 0.15 }, { "fence", 0.04 }, { "fastHands", 0.15 } },
			{ { "seedMoney", 300 }, { "haggle", 0.05 }, { "bagValue", 0.05 }, { "magnet", 0.2 }, { "fence", 0.05 } },
		},
		LUCK = {
			{ { "cardLuck", 1 } },
			{ { "dealerLuck", 1 }, { "crateLuck", 1 } },
			{ { "cardLuck", 1 }, { "dealerLuck", 1 }, { "crateLuck", 1 } },
			{ { "cardLuck", 1 }, { "dealerLuck", 1 }, { "crateLuck", 1 }, { "cardLuck", 1 } },
			{ { "dealerLuck", 1 }, { "crateLuck", 1 }, { "cardLuck", 1 }, { "dealerLuck", 1 }, { "crateLuck", 1 } },
		},
		ARSENAL = {
			{ { "pistols", 0.04 } },
			{ { "smgs", 0.04 }, { "rifles", 0.04 } },
			{ { "shotguns", 0.04 }, { "snipers", 0.04 }, { "lmgs", 0.04 } },
			{ { "explosives", 0.04 }, { "elemental", 0.04 }, { "pistolMags", 0.1 }, { "smgMags", 0.1 } },
			{
				{ "rifleMags", 0.1 },
				{ "shotgunShells", 1 },
				{ "sniperMags", 1 },
				{ "lmgBelts", 0.1 },
				{ "explosiveAmmo", 1 },
			},
		},
	},

	------------------------------------------------------------------ Payout (GDD_7)
	GoldPerWaveBase = 20, -- per cleared wave
	GoldPerWaveAdd = 5, -- x (wave - 1)
	GoldPerObjective = 50, -- per side job completed
	-- GoldEarned = (sum over cleared waves + GoldPerObjective x objectives) x the difficulty's goldMult, plus SideJobGold per job.

	------------------------------------------------------------------ Minigames (test props in the yard)
	MinigameTier = 1, -- starting tier for every game (1..3); the tier pad and the debug panel change it per session
	MinigamePanelPct = 0.55, -- panel width as a share of the shorter screen edge
	-- Round 24 mobile: tap / drag games also take input on a band around the panel, between these screen-width
	-- margins (left and right edges stay free for the thumbstick and the buttons) and below the top bar.
	MinigameTouchEdgePct = 0.24,
	MinigameTouchTopPct = 0.1,
	SafeTouchGain = 0.55, -- mobile: the dial turns this much per degree your finger turns round it (1 = one to one)
	FreqPadSpeed = 0.7, -- brief 11: the needle's top speed on the right stick (slider widths per second; Round 28d: was 0.35)
	FreqPadNudge = 0.01, -- one D-pad press moves the needle this share of the slider
	SafeDialPadMode = "stick", -- brief 11: "stick" (the right stick's angle turns the dial) or "dpad" (left / right)
	-- A result that comes back faster than this is logged as a fail (a client cannot skip the game).
	-- A result faster than this (server clock, from the open) is treated as a script, not a player, and fails. Round 20u:
	-- halved or less (a fast tier 1 Keypad measured 1.48 s against the old 1.5 floor and was failed).
	MinigameMinSec = { Lockpick = 0.7, Hotwire = 0.7, Keypad = 0.6, Charges = 0.7, Safe = 1, Freq = 0.5, Cut = 0.4 },
	MinigameHaptics = true, -- HapticService pulses on hits and locks (mobile / gamepad)
	MinigameCloseDistance = 14, -- walking further than this from the prop closes the panel (counts as cancel)
	MinigameWalkAwayGraceSec = 0.75, -- Round 19i: out of range this long before the cancel (a game finishing as you walk off still counts)
	MinigameExitSec = 0.3, -- on DONE / FAILED the panel slides off over this long; input is back at once
	LockpickTargetByTier = { 3, 4, 5 }, -- points to open per tier: green zone +1, pink sliver +2
	LockpickZoneShrink = 0.9, -- zone width x this per hit, floored at half the starting width
	LockpickSpeedUp = 1.08, -- pin speed x this per hit
	LockpickZoneByTier = { 90, 70, 55 }, -- starting zone width in degrees
	LockpickPinSpeed = 150, -- degrees per second at the start
	LockpickSliverDeg = 10, -- width of the +2 pink sliver in the middle of the zone
	HotwireCountByTier = { 3, 4, 5 }, -- wires
	HotwireSnapPx = 48, -- a wire released within this many design px (400-wide basis) of a socket still connects
	KeypadShowSec = 1.2, -- the code shows this long before the pad lights
	KeypadReshowSec = 0.8, -- the code shows again this long after a wrong digit
	KeypadDigitsByTier = { 3, 4, 5 },
	ChargesCountByTier = { 5, 6, 8 }, -- blast caps to press in order
	-- Round 19c: Cut, the bolt cutter (D2's chains, the CUT THE CHAIN side job): hold to squeeze, let go in the band.
	CutLinksByTier = { 2, 3, 4 }, -- links to cut
	CutBandByTier = { 0.22, 0.17, 0.13 }, -- the green band's width, as a share of the gauge
	CutBandMin = 0.35, -- the band never starts below this share of the gauge (a tap is never a cut)
	CutFillSec = 1.3, -- seconds for the needle to climb the whole gauge on the first link...
	CutSpeedUp = 0.85, -- ...x this per link cut (faster)
	CutSlipSec = 0.35, -- squeezing to the top slips: a miss, and no new squeeze for this long
	SafeWarmRange = 18, -- needle turns amber within this many numbers of the target
	SafeHotRange = 6, -- needle turns green within this
	SafeLockSec = 0.3, -- hold inside the hot range this long to lock a number...
	SafeHotGraceSec = 0.2, -- ...a wobble out of it shorter than this keeps the hold
	SafeWrongWayDeg = 40, -- turning against the direction this far (outside the warm range) reads WRONG WAY; backing up near the number never does
	-- Round 16: reaching the number turning the wrong way (from its far side) keeps it cold until the dial leaves
	-- the warm range and comes back the right way. Each number crossed in the warm range clicks:
	SafeTickPitch = { 0.9, 1.7 }, -- click pitch at the edge of the warm range .. on the number
	SafeTickVolume = { 0.12, 0.45 }, -- click volume, same span
	SafeNumbersByTier = { 3, 4, 5 }, -- numbers to lock per tier (Round 15l: raised with the more lenient dial)
	FreqTolerance = 0.06, -- the two waves count as overlapping within this share of the fixed frequency
	FreqLockSec = 0.5, -- hold the overlap this long to lock
	FreqLocksByTier = { 1, 2, 3 },
	FreqRangeByTier = { 1.6, 2.4, 3.5 }, -- slider spans FreqCenter / r .. FreqCenter x r; wider = harder
	FreqCenter = 3, -- middle of the slider's frequency band
	FreqTargetEdge = 0.1, -- targets land at least this share of the slider in from either end
	FreqTargetMinMove = 0.25, -- each new target sits at least this share of the slider from the last one

	------------------------------------------------------------------ Downed / revive / game over
	DownedWalkSpeed = 6,
	DownedCameraHeight = 3, -- studs above the floor while downed
	DownedAnimationId = "rbxassetid://507784897", -- Roblox default R15 swim idle stands in for the crawl
	BleedOutSec = 15, -- GIVE UP on the bleed bar ends it early
	ReviveRadius = 6, -- studs from the downed player a reviver must stand within
	ReviveHoldSec = 3, -- hold F (mobile: the REVIVE button) this long
	ReviveHPPct = 50, -- HP after a teammate revive or REVIVE EVERYBODY, % of max
	SelfReviveHPPct = 50,
	ReviveInvulnSec = 1, -- no damage for this long after standing up
	RevivePausesBleed = true, -- a teammate's revive hold freezes the bleed timer; letting go resumes it
	ReviveTickSec = 0.5, -- the reviver's centered bar ticks this often while it fills
	BusyTagOffset = 3.2, -- studs above a teammate's head for the LOCKPICK / HACKING / CAPTURING tag
	-- Round 25: teammate markers in a run (client/TeammateMarkers.lua): diamond + name + distance at any range,
	-- an edge arrow when off screen.
	TeammateMarkers = true,
	TeammateMarkerOffset = 4.4, -- studs above the head (clear of the busy tag)
	TeammateMarkerHideNear = 12, -- on screen and this close: hidden (a downed teammate always shows)
	-- The hub nameplate (client/Nameplates.lua): level badge, name, VIP chip, class pictogram, best top wave.
	NameplateOffset = 2.8, -- studs above the head
	NameplateHeight = 44, -- px at the UI basis (the class block is this square); the level badge is 1.3x this
	NameplateMaxDistance = 90, -- studs: plates past this hide
	NameplateShowSelf = true, -- your own plate over your character
	-- Ally callouts (brief 5, lines in Callouts.lua): downed / revived / bled-out radio to teammates, and (Round 16)
	-- the big moments: the boss's last hit, a Legendary from a crate, a multi-kill, a mastery tier.
	CalloutMultiKill = 5, -- one frag / claymore killing at least this many sends the multi-kill callout
	CalloutSec = 2.5, -- on screen this long
	CalloutMaxWaitSec = 8, -- a callout still queued behind MARLOW or a cutscene after this long is dropped
	RunOverSlowSec = 1, -- slow-mo under the RUN OVER stamp
	-- The red screen and stamp stay this much longer, then the run end cutscene starts. The whole window
	-- (RunOverSlowSec + RunOverHoldSec) is when REVIVE EVERYBODY still saves the run: the crew stands up and the
	-- same wave restarts.
	RunOverHoldSec = 4,
	RunOverTimeScale = 0.3, -- player and enemy speed during the slow-mo
	-- Downed sidearm: the held gun is stowed and a Common pistol takes its place until revive (back exactly
	-- as it was) or bleed-out (the stowed gun drops as ground loot).
	DownedCanShoot = true, -- false restores the Round 9 "no fire while downed" rule
	DownedPistolId = "M1911",
	DownedSpreadMult = 1.5,

	------------------------------------------------------------------ Run start (IntroSec is the total length)
	RunStartBeats = { doors = 1.4, masks = 2.2, poses = 2.8, orbit = 4.2 }, -- seconds from START RUN
	SquadSize = 4, -- the start / end line-ups fill up to this many with dummy crew (prototype presentation)
	VanDriveInStuds = 90, -- brief 8: a map's van drives this far from behind its Van node (a node's DriveIn attribute overrides it)
	VanExitSec = 1.2, -- after control returns the van drives off and is removed; it only exists in the start animation
	PoseStagger = 0.15, -- gap between each player's pose starting
	MaskColors = { "E8554D", "4D9FE8", "8FE3A1", "E8B64C", "A864E8", "F2E6C8" }, -- head recolor per player, by join order
	MaskOnAnimationId = "rbxassetid://507770818", -- hands-to-face stand-in (default R15 laugh)
	-- Each player gets a random pose at run start and keeps it for the run end. Default R15 emotes.
	Poses = {
		{ name = "WAVE", animationId = "rbxassetid://507770239", holdSec = 1.2 },
		{ name = "POINT", animationId = "rbxassetid://507770453", holdSec = 1.2 },
		{ name = "CHEER", animationId = "rbxassetid://507770677", holdSec = 1.2 },
	},

	------------------------------------------------------------------ Run end
	-- Seconds from the start of the sequence: the camera pans the team until `mvp`, then the MVP beat runs to `summary`.
	RunEndBeats = { poses = 0.6, rain = 1.4, mvp = 4.0, summary = 7.0 },
	MvpOrbitSec = 2.5, -- the slow orbit on the MVP covers this long
	MvpAnimationId = "rbxassetid://507771019", -- the MVP's flex while the rest of the crew is hidden (default R15 dance)
	CashRainSec = 2,
	CashRainPerBanked = 0.02, -- bills = this x Total Banked
	CashRainMax = 200,
	MvpKillWeight = 1,
	MvpCashWeight = 0.05,
	MvpReviveWeight = 40,
	SummaryAutoLobbySec = 30, -- TO LOBBY fires on its own after this
	SummaryPassOpenDelaySec = 0.6, -- Round 19c: CLAIM IN PASS goes to the hub first; the pass opens this long after you land
	SummaryCountUpSec = 1, -- GOLD EARNED count-up length

	------------------------------------------------------------------ Monetization (brief 6; every purchase is fake)
	-- Robux prices live in the data files (Products, Bundles, GoldPacks, Crates, BoostDefs, CashPacks,
	-- ReviveTokenPacks, PassSeason); the keys here are the ones the brief names. Purchases.lua (server) and
	-- PurchaseSheet.lua (client) are the whole integration a real MarketplaceService flow replaces.
	FakeRobuxStart = 100000, -- a fresh profile's fake balance
	FakeRobuxTopUp = 10000, -- GET ROBUX (the + by the balance, or a short sheet) adds this, so a tester never sticks
	PurchaseProcessingSec = 0.6, -- the sheet's processing spinner holds at least this long
	PurchaseLogKeep = 200, -- purchase records kept on the profile for the readout
	-- Fake clocks: every timer below runs on the player's fake clock (real UTC + the debug offset on the profile).
	FeaturedRotationSec = 2 * 86400 + 14 * 3600, -- the featured bundle rotates this often (LEAVING IN hh:mm:ss)
	DailyShopItems = 6, -- FEATURED's daily single items (DailyShop.lua), redrawn every fake UTC day
	DailyShopRerollPrice = 25, -- R$: REROLL on DAILY ITEMS draws a fresh set for you today (no limit)
	FeaturedEpochUtc = 1793318400, -- 2026-10-30 00:00 UTC: the rotation clock counts from here
	BundleRevealStagger = 0.3, -- the stacked reveal cards each item in this far apart
	-- Crates (Crates.lua): pity, dupes, the opening scene.
	CratePity = 10, -- Epic or better is guaranteed on this open if the last CratePity - 1 were below Epic
	CrateExitHoldSec = 0.7, -- Round 27c: the black holds this long after a crate scene while the world's lighting settles
	CrateAutoNextSec = 2.5, -- xN: the next crate opens by itself this long after a reveal (NEXT skips the wait)
	CrateOpenSec = 1.4, -- rattle, seams glowing in the rolled rarity, then the lid
	CrateLegendarySlowSec = 0.5, -- Legendary: the reveal runs in slow motion this long
	DupeGoldByTier = { 40, 80, 160, 320, 800 }, -- an owned item converts to this much Gold by rarity...
	DupeMasteryByTier = { 20, 40, 80, 160, 400 }, -- ...plus this mastery XP for that item (weapons; masks bank it)
	-- Boosts (BoostDefs.lua): run-only effects on a real-time clock from purchase.
	PowerBoostPct = 0.2, -- POWER: weapon and ability damage
	CashBoostPct = 0.5, -- CASH: match cash from kills, cash bags and job payouts (Gold untouched)
	LuckyWeightShift = 1, -- LUCKY: in-run rarity rolls (crates, upgrade card tiers) use the wave bracket this many rows up
	BoostChipWarnSec = 60, -- a boost chip pulses in its last minute
	-- Revive tokens (ReviveTokenPacks.lua).
	ReviveTokensStart = 3, -- a fresh profile's tokens
	SelfReviveTokens = 1, -- SELF-REVIVE spends this many
	ReviveAllTokensPerPlayer = 1, -- REVIVE EVERYBODY spends this x the party size
	TokenNudgeSec = 10, -- downed with no tokens and this little bleed left: GET TOKENS pulses
	-- VIP (Vip.lua): a fake monthly subscription.
	VipPrice = 399, -- R$ / month
	VipPeriodDays = 30, -- the fake renewal clock
	VipCashPct = 0.25, -- a permanent CASH boost while active (in-run only, stacks with the CASH boost)
	VipMonthlyTokens = 10, -- revive tokens on subscribe and on every renewal
	VipDailyGold = 200, -- the daily gift chip on the hub HUD, once per UTC day
	-- Battle pass (Pass.lua; the grid and the seasons live in PassSeason.lua).
	SeasonEpochUtc = 1793232000, -- 2026-10-29 00:00 UTC: season 1 starts here, each season SeasonLengthDays long
	SeasonLengthDays = 30,
	PassLevels = 30, -- the season's own rewards; past it the track loops PassSeason.Bonus forever (Round 18c)
	PassXpPerLevel = 1000,
	PassXpPerWave = 40, -- pass XP per wave cleared...
	PassXpPerBoss = 200, -- ...and per boss kill (plus Job rewards)
	PassPremiumPrice = 499, -- PREMIUM (tier 1)
	PassPremiumPlusPrice = 999, -- PREMIUM+ (tier 2, includes PREMIUM; from PREMIUM it costs the difference)
	PassSkipPrice = 149, -- R$ per level skipped
	PassPageLevels = 4, -- levels shown on the track at once (three tiles each); BACK / NEXT page by this many
	-- Jobs (Jobs.lua; pool in JobPool.lua): three dailies and a weekly bounty.
	DailyXp = 300,
	DailyGold = 150,
	DailyPassXp = 400,
	WeeklyXp = 1500,
	WeeklyGold = 800,
	WeeklyPassXp = 2000,
	WeeklyTokens = 5,
	JobFreeRerollsPerDay = 1, -- Round 19c: the small R on any unclaimed sheet swaps the Job free this many times a fake day (then the fake-Robux REFRESH)
	JobAnnounceLine = "New jobs on the board. Pick your poison.",
	JobBoardStaggerSec = 0.07, -- the board's sheets cascade in this far apart when it opens
	JobBarFillSec = 0.5, -- progress bars fill from empty over this long on open
	JobStampSec = 0.18, -- the DONE / PAID stamp's slam
	JobClaimPulseSec = 1.4, -- a claimable sheet's glow breathes at this period (also the scoreboard's Job cards)
	ScoreJobCardH = 84, -- the scoreboard's Job cards (under the crew rows): card height in px before UI scaling
	ScoreJobStaggerSec = 0.06, -- the cards cascade in this far apart when the scoreboard opens
	ScoreJobFillSec = 0.35, -- a card's progress bar fills in (on open, and on live progress) over this long
	-- Upsells (each a one-line nudge, never a blocking popup).
	CashGlintMinCash = 400, -- the cash + glints when cash is under the next upgrade's price by less than this
	-- UI art pass: live 3D icons (UI/ModelIcon.lua) for guns, wraps and masks in tiles, wells, the reel and the HUD.
	ModelIconFov = 24, -- icon camera field of view in degrees (low = flatter, product-shot look)
	ModelIconPad = 0.07, -- share of the icon left empty on each side of the model
	ModelIconGunYaw = -18, -- guns lie muzzle-left: degrees the camera swings toward the muzzle (negative) or the stock
	ModelIconGunPitch = 14, -- degrees the camera looks down on a gun
	ModelIconBustYaw = 16, -- mask busts: degrees off front-on
	ModelIconBustPitch = 6, -- degrees the camera looks down on a bust
	ModelIconAmbient = "A4A8B2", -- the unlit side's light (hex): raise it if dark guns sink into dark wells
	ModelIconLight = "FFF4E6", -- the key light from the upper left (hex)
	ModelIconSwayDeg = 26, -- a moving icon (hovered tile, detail well) turns this far either way
	ModelIconSwaySec = 3.4, -- one full swing
	ModelIconDimTransparency = 0.35, -- unowned / not-yet icons fade this much
	ModelIconLockedShade = "5A5C64", -- a locked icon is drawn this dark (multiply, hex)
	ModelIconWrapGun = "AK-47", -- the gun a wrap icon is shown on
	ModelIconWellTint = 0.22, -- dark icon wells (held-gun slot, crate reel cells) lean this far toward the rarity colour

	------------------------------------------------------------------ Brief 10: retention
	-- The login streak: a 28-day track in four 7-day sets, one claim per fake day (the brief 6 fake clock), the
	-- modal on the first hub entry of the day. After day 28 the track wraps to day 22 so week 4 keeps paying.
	-- Each day is a list of rewards (Rewards.lua shape). A crate reward opens in the crate room on claim (nothing is
	-- banked); `floor` is its lowest rarity (3 = Rare: Common and Uncommon removed). Boosts are timed like the
	-- store's (there is no per-run boost): `sec` of real time from the claim. Days 7 / 14 / 21 / 28 are the big ones.
	StreakEnabled = true, -- false: no modal (the profile keeps its streak)
	-- Round 27d: day 1 is a crate and a crate comes every 2-3 days (1, 3, 6, 7, 9, 11, 13, 16, 18, 20, 21, 23, 25, 27, 28).
	StreakRewards = {
		-- Week 1
		{ { kind = "crate", id = "daily", amount = 1 } },
		{ { kind = "gold", amount = 400 } },
		{ { kind = "crate", id = "daily", amount = 1 } },
		{ { kind = "gold", amount = 600 } },
		{ { kind = "boost", id = "cash", sec = 1800 } },
		{ { kind = "crate", id = "daily", amount = 1 } },
		{ { kind = "crate", id = "daily", amount = 1, floor = 3 } }, -- day 7: RARE+
		-- Week 2
		{ { kind = "gold", amount = 600 } },
		{ { kind = "crate", id = "daily", amount = 1 } },
		{ { kind = "gold", amount = 800 } },
		{ { kind = "crate", id = "daily", amount = 1 } },
		{ { kind = "boost", id = "cash", sec = 1800 } },
		{ { kind = "crate", id = "daily", amount = 1 } },
		{ { kind = "passxp", amount = 1000 }, { kind = "gold", amount = 1000 } }, -- day 14
		-- Week 3
		{ { kind = "gold", amount = 800 } },
		{ { kind = "crate", id = "daily", amount = 1 } },
		{ { kind = "gold", amount = 1000 } },
		{ { kind = "crate", id = "daily", amount = 2 } },
		{ { kind = "boost", id = "cash", sec = 1800 } },
		{ { kind = "crate", id = "daily", amount = 1 } },
		{ { kind = "crate", id = "daily", amount = 1, floor = 4 } }, -- day 21: EPIC+
		-- Week 4 (loops)
		{ { kind = "gold", amount = 1000 } },
		{ { kind = "crate", id = "daily", amount = 1 } },
		{ { kind = "gold", amount = 1200 } },
		{ { kind = "crate", id = "daily", amount = 2 } },
		{ { kind = "boost", id = "cash", sec = 1800 } },
		{ { kind = "crate", id = "daily", amount = 2 } },
		{ { kind = "crate", id = "daily", amount = 1, floor = 4 }, { kind = "gold", amount = 1500 } }, -- day 28
	},
	-- Round 27d: the streak's crates are the daily crate (guns + masks, Catalog.dailyPool), its tier rising by week the
	-- way the level bands do (week 4 loops, so it stays ELITE). `floor` lifts the big days above a rarity.
	StreakCrateTierByWeek = { "basic", "gold", "diamond", "elite" },
	StreakLoopFrom = 22, -- after day 28 the next claim is this day (week 4 repeats)
	StreakRestorePrice = 49, -- fake R$: RESTORE on a lost streak keeps the day (product streak_restore)
	VipStreakRestores = 1, -- free restores per VipStreakRestoreDays fake days while VIP
	VipStreakRestoreDays = 30,
	StreakOpenDelaySec = 1.2, -- after the profile loads / the party lands in the hub, before the modal opens
	-- Round 27b: the modal also opens once at the start of every session with nothing to claim (today ticked, the next
	-- reward's countdown and the skip offer); X closes that one.
	StreakOpenEverySession = true,
	StreakSkipPrice = 29, -- fake R$: GET IT NOW claims the next day's reward today (product streak_skip)
	StreakSkipsPerDay = 0, -- skips a fake day; 0 = unlimited (Round 27d: the upsell is always there once today is claimed)
	StreakPeekDays = 3, -- the card list runs to the end of this week plus this many days, then a MORE card
	StreakClaimHoldSec = 0.9, -- the claimed tile's ding and burst play this long before the modal closes

	-- The daily crate: one podium in the hub (the DailyCrate node), unlocked for the fake day by finishing any match
	-- (a summary), one open a day. Its tier comes from the player's level only. The pool is every Direct-sale gun
	-- and mask (Catalog.dailyPool: no crate / event / bundle / VIP / pass items, none of the always-owned defaults).
	DailyCrateEnabled = true, -- false: no podium state, no PLAY line, nothing unlocks
	DailyCrateTierByLevel = { { 1, "basic" }, { 11, "gold" }, { 26, "diamond" }, { 51, "elite" } }, -- from-level, tier
	-- Per tier: rarity weights Common / Uncommon / Rare / Epic / Legendary, the crate's colours (hex) and its word.
	DailyCrateTierOdds = {
		basic = { weights = { 50, 30, 14, 5, 1 }, color = "3A3F48", trim = "B9C2CC", name = "BASIC" },
		gold = { weights = { 35, 32, 21, 9, 3 }, color = "4A3A1C", trim = "E8B64C", name = "GOLD" },
		diamond = { weights = { 20, 30, 28, 16, 6 }, color = "1C3A4A", trim = "6FD8F2", name = "DIAMOND" },
		elite = { weights = { 8, 22, 34, 25, 11 }, color = "3A1C46", trim = "E86FF2", name = "ELITE" },
	},
	DailyCrateFirstIsGun = true, -- the first daily crate a profile ever opens rolls from the guns only
	DailyCrateRerollEnabled = true, -- the claimed podium offers ROLL AGAIN for fake R$
	DailyCrateRerollPrice = 79, -- product dailycrate_reroll
	DailyCrateRerollMaxPerDay = 0, -- 0 = unlimited
	DailyCrateBuyPrice = 99, -- Round 27c: BUY 1 at a locked podium (product dailycrate_buy; the free one still unlocks by playing)
	DailyCrateGuideSpacing = 3.5, -- studs between the floor chevrons leading to a ready crate
	DailyCrateGuideNear = 9, -- the chevrons stop this close to the podium
	DailyCrateArrivalOpenSec = 2.6, -- tapping the summary's crate card opens the podium this long after you land
	DailyCrateNudgeSec = 5, -- in the hub with a ready crate, MARLOW's card nudges you this long after you land
	DailyCrateMarlowLine = "Your crate's unlocked. It's by the loading dock. Go crack it open.",
	DailyCrateIdleRange = 40, -- studs: the ready crate's quiet loot swell plays inside this range
	DailyCratePodiumScale = 1, -- the generated podium's scale (fits the gap beside the range door at 1)
	DailyCrateBeamHeight = 60, -- studs: the ready crate's beacon column
	DailyCratePromptDistance = 9, -- studs: the podium's E prompt

	------------------------------------------------------------------ Brief 12: Stats (server/Stats.lua, the resolver)
	-- Every bonus to a stat is a source (an upgrade card, a dealer stand, the held gun's Armory level, a Skill Web node,
	-- a class passive, a boost, a timed buff like Adrenaline or Overclock). How a stat's sources stack is its mode:
	--   haste    points add; a time divides by (1 + h / 100), a rate multiplies by it (never reaches zero)
	--   resist   1 - prod(1 - r): two -30% sources give -51%, never -100%
	--   softcap  base x (1 + max x h / (h + k) / 100): every point counts, the ceiling is never met (max = k keeps the
	--            first points close to linear)
	--   additive plain sum (the default for any stat not listed)
	--   capped   plain sum (plus `base`, a Config key), hard ceiling at `cap`
	-- Typed stats ("typeDamage.Rifle") use their root's row. Card and web labels never change (COOLDOWN -8% is +8 haste).
	StatDefs = {
		cooldown = { mode = "haste" }, -- ability cooldowns
		fireRate = { mode = "haste" },
		reload = { mode = "haste" },
		typeReload = { mode = "haste" }, -- reload haste on one archetype (SHARPSHOOTER II)
		interact = { mode = "haste" }, -- door / job holds
		revive = { mode = "haste" },
		pickup = { mode = "haste" }, -- bag fill speed
		armorDelay = { mode = "haste" }, -- the wait before armor refills
		damageTaken = { mode = "resist" },
		moveSpeed = { mode = "softcap" }, -- max / k: MoveSpeedSoftMax / MoveSpeedK
		pickupRadius = { mode = "softcap", max = 300, k = 300 }, -- the bag magnet
		turretRange = { mode = "softcap", max = 200, k = 200 }, -- turret / sentry reach
		area = { mode = "softcap", max = 200, k = 200 }, -- anything that is not a bullet (brief 12 step 5)
		critChance = { mode = "capped", cap = 100, base = "BaseCritChancePct" },
		elementProc = { mode = "capped", cap = 100 },
		droneInherit = { mode = "capped", cap = 100 }, -- SWARM's UPLINK share of the gun's damage
	},
	AbilityMinCooldownSec = 2, -- engine floor under any stack of cooldown haste
	MoveSpeedSoftMax = 1000, -- move speed's softcap ceiling, in percent: an asymptote nobody meets
	MoveSpeedK = 1000,
	StatMultFloor = 0.2, -- no pile of maluses takes a multiplier (or a haste factor) below this
	StatsLogEnabled = false, -- `[GHS Stats] <name> <stat> <resolved> <- <n> sources` on every change (debug: Stats log)

	------------------------------------------------------------------ Brief 12: kit changes
	-- INITIATE: Frag / Adrenaline / Turret (the basic turret above: TurretHP, TurretDmg, TurretRange..., instant deploy).
	-- ENGINEER: Sentry / Barricade / Overclock. DOC: Stim Shot / Med Bag / Heal Drone. PYRO (id TORCH): Molotov /
	-- Flame Turret / Inferno. Claymore, Oil Drum and Healing Turret keep their code and keys above, unassigned.
	-- Cooldowns of the brief 12 abilities (PlayerState.baseCooldown reads these after AbilityCooldown).
	SentryCooldown = 35,
	HealDroneCooldown = 25,
	InfernoCooldown = 30,
	-- ENGINEER's Sentry: a heavy tripod. Twin barrels alternate at 2x the turret's rate; per-barrel damage makes the
	-- total SentryDpsMult x the turret's DPS. Several can stand at once (cooldown / duration, nothing else).
	SentryDeploySec = 1.5, -- legs unfold and the barrels spin up before the first shot
	SentryDpsMult = 2.5,
	SentryHp = 300,
	SentrySec = 50, -- then it folds away
	SentryRangeMult = 1.5, -- x TurretRange (both scale with the turretRange stat)
	SentryScale = 1.6, -- x the turret's size, so apprentice and master read side by side
	SentryLaserColor = "FF3B30",
	-- DOC's Heal Drone: hovers at the caster's shoulder (an orbit, no pathfinding), heals the lowest-HP ally in range
	-- every FieldTickSec (an ally reviving a downed teammate first, ties to the caster). No HP, can't be hit.
	HealDroneRange = 18,
	HealDroneHps = 6, -- HP per second (x ABILITY POWER, x HEALING)
	HealDroneSec = 20,
	HealDroneColor = "8FE3A1",
	-- PYRO's Inferno: a ring of fire around the caster that moves with them; enemies in it burn (the burn status, so
	-- PYRO's fire mastery applies) and walk slower. Never touches players or placeables.
	InfernoRadius = 9, -- x the area stat
	InfernoSec = 10,
	InfernoSlowPct = 30, -- stacks with Ice Ammo's slow multiplicatively (never a full stop)
	InfernoBurnPerSec = 18, -- the burn it puts on (x ABILITY POWER, x ACCELERANT)
	InfernoBurnSec = 2, -- the burn outlasts the ring by this
	InfernoHeight = 7, -- studs above / below the caster's feet the ring still reaches
	UnassignedAbilitiesEnabled = false, -- true: Claymore / Oil Drum / Healing Turret can fire without a debug grant
	-- Ally radio lines when someone puts down a sentry, a drone or an Inferno (Callouts.Lines, [Copy: TBA]); one per
	-- player per this many seconds so a swarm build doesn't spam the radio.
	AbilityCalloutCooldownSec = 40,
	-- Every brief 12 effect (drones, rings, explosions) runs at this share of its particles / parts on a phone.
	MobileFxScale = 0.5,
	-- Drone sound (client DroneFx): one looped hum per caster, gain per live drone up to a cap; the shot zap plays at
	-- most DroneZapsPerSec times a second per client. DroneHumSoundId "" = no hum (no verified loop picked yet: audition
	-- a ProSoundEffects drone / servo loop and paste its rbxassetid here).
	DroneHumSoundId = "",
	DroneHumVolumePer = 0.02,
	DroneHumMaxVolume = 0.18,
	DroneZapsPerSec = 8,

	------------------------------------------------------------------ Brief 12: SWARM (Run/Swarm.lua)
	-- Nothing is aimed: every ability adds to the swarm, buffs it or protects you with it. Drones are orbits round the
	-- caster (DroneOrbit), never physics, never pathfinding, never in anyone's way, never targetable.
	-- DRONE (Q): one attack drone that orbits you and shoots the nearest enemy it can see. No count cap: how many you
	-- hold is duration / cooldown, so cooldown is the build.
	DroneSec = 20,
	DroneCooldown = 15,
	DroneRange = 40, -- studs from the drone
	DroneFireRate = 2, -- shots per second per drone
	DroneRetargetSec = 0.25, -- a target pick (nearest living enemy with line of sight) this often
	DroneColor = "6FE3D2", -- SWARM's class colour (tracers, glow)
	-- UPLINK (passive): drones inherit this % of your equipped gun's resolved damage per shot (a capped stat, 100 max:
	-- Armory, cards and the web on the gun scale the swarm). Switching guns re-reads the next shot.
	DroneWeaponDamagePct = 60,
	-- SURGE (E): every live drone fires SurgeFireMult x faster and each shot ricochets to SurgeRicochet more enemies
	-- within SurgeRicochetRange of its target; drones also fetch bags within SurgeFetchRange of you to your feet (one
	-- per drone per SurgeFetchEverySec).
	SurgeSec = 8,
	SurgeCooldown = 20,
	SurgeFireMult = 1.5,
	SurgeRicochet = 1,
	SurgeRicochetRange = 12,
	SurgeFetchRange = 20,
	SurgeFetchEverySec = 2,
	-- AEGIS (Z): a shield drone projects a bubble round you that moves with you: enemy hits on anyone inside are
	-- absorbed (they deplete its HP), melee enemies touching it are body-blocked and take AegisContactDps; when HP
	-- breaks or time ends it detonates (AegisBurst in AegisBurstRadius, x the area stat). Allies pass through it.
	AegisSec = 8,
	AegisCooldown = 35,
	AegisRadius = 7,
	AegisHp = 400, -- x ABILITY POWER
	AegisContactDps = 15,
	AegisBurst = 180, -- x ABILITY POWER
	AegisBurstRadius = 10,
	-- Mastery: I DroneSec + SwarmMasteryDroneSec; II SURGE ricochets SwarmMasteryRicochet times; III your kills add
	-- DroneKillExtendSec to every live drone, never above DroneKillExtendCap seconds remaining.
	SwarmMasteryDroneSec = 5,
	SwarmMasteryRicochet = 2,
	DroneKillExtendSec = 0.5,
	DroneKillExtendCap = 20,
	DroneHardCap = 40, -- per caster, an engine guard (the oldest is replaced, a WARN log), never surfaced as a rule
	SwarmCalloutAt = { 5, 10, 20 }, -- the radio line fires as your live drone count reaches each of these
}

return Config
