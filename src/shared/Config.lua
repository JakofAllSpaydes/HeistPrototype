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
	MaxActiveEnemies = 50, -- hard cap on alive enemies, backfilled as they die
	IntermissionSec = 5, -- NEXT WAVE IN countdown
	IntroSec = 5.0, -- run start sequence length (START RUN pressed -> WAVE 1); also the GET READY hold
	SkipVoteFraction = 0.5, -- share of players that must vote (or have AUTO SKIP on) to end the intermission early
	SkipMinIntermissionSec = 1, -- the intermission always lasts at least this long, even with every vote in
	AutoSkipWaveSec = 10, -- with AUTO SKIP on, the next wave starts this long into the current one (once it has all spawned)

	------------------------------------------------------------------ Enemy
	EnemyHP = 60,
	EnemyHPMultPerWave = 1.12, -- HP = EnemyHP * mult^(wave-1)
	EnemyDmg = 8,
	EnemyDmgMultPerWave = 1.06,
	EnemyWalkSpeed = 12,
	RetargetSec = 0.5, -- how often an enemy re-picks the nearest player
	EnemyMeleeReach = 4.5, -- studs, root-to-root distance that counts as a touch
	EnemySwingCooldown = 1, -- seconds between melee hits
	EnemyCollidesWithPlayers = false, -- false: enemies walk through players and each other, never body-block
	EnemyStuckDetourSec = 1, -- no progress for this long -> sidestep + jump around the obstacle
	EnemyStuckTeleportSec = 8, -- still stuck after this long -> re-spawn at a random spawn point
	SpawnRingRadius = 90, -- studs from room center
	SpawnPointCount = 8,

	------------------------------------------------------------------ Combat
	StartingCash = 3000, -- Match Cash at run start (brief says 0; raised for testing)
	CashPerKill = 40,
	HoldToFire = true, -- true: every weapon fires while LMB is held; false: Weapons.auto decides
	HeadshotMult = 1.5,
	CritDmgMult = 2, -- damage multiplier when a crit lands (Crit Chance upgrade)
	BaseCritChancePct = 0, -- crit chance before upgrades, in percentage points
	MaxOriginDriftStuds = 8, -- reject FireShot if origin is further than this from the head
	MaxShotRange = 600,
	FireRateTolerance = 1.5, -- server accepts shots up to this multiple of the weapon fire rate
	RicochetRange = 22, -- studs a ricochet can jump to another enemy
	RicochetDmgRatio = 0.75, -- ricochet damage as a share of the original hit
	SplashRadius = 9, -- studs around a kill that Splash damages
	MultishotSpread = 4, -- extra cone (degrees) on the multishot bullet
	-- Damage falloff by archetype: full damage out to `start` studs, scaling down to `min` at `finish`,
	-- flat `min` beyond. The room is 200 studs across; the spawn ring is 90 out.
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
	TouchSensitivity = 0.006, -- radians per touch pixel
	-- Cursor unlocked (Ctrl / Alt): the camera stays put and the character turns to face the cursor's
	-- world point, so you can aim all the way around. Shots go where the cursor is.
	CameraFov = 70,
	FireFovKick = 2.5, -- degrees of FOV punch per shot
	-- Zoom: scroll wheel / pinch changes the camera distance (studs behind the head).
	CameraZoomDefault = 8,
	CameraZoomMax = 16, -- outer limit
	CameraZoomStep = 1.5, -- studs per scroll-wheel tick
	CameraFirstPersonBelow = 2, -- zooming under this snaps to first person (character hidden locally)
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
	WeaponPrice = 300,
	WeaponPriceMult = 1.4,

	------------------------------------------------------------------ Upgrade overlay
	ShopDimPct = 35, -- world dim while the pick-3 is open
	PanelShakePx = 2,
	CardDealStagger = 0.08,
	CardFlipStagger = 0.07, -- unused by the slot roll, kept for the flip variant
	CardRollSec = 0.45, -- each card's mini slot roll; starts as the card deals in
	CardRollStagger = 0.07, -- gap between card rolls starting
	TradeoffChance = { 0, 0.1, 0.25, 0.4, 0.5 }, -- per tier 1..5
	TradeoffMalusRatio = 0.5, -- malus = one other stat at this ratio of the buff
	TrackerCols = 10,

	------------------------------------------------------------------ Weapon reel / ground loot
	RollDurationSec = 2.0,
	RollLandHoldSec = 0.5, -- reel shows the result this long before the gun ejects
	RollEjectSec = 0.4,
	GunDropHeight = 14, -- rolled guns fall in from this height
	GunDropSec = 0.45,
	SwapCooldownSec = 0.5, -- after a swap, further swaps are ignored for this long (anti-spam mid-combat)
	GroundWeaponLifetime = 30, -- floor guns despawn after this; a fresh drop (or swap) restarts it
	GroundWeaponFadeSec = 10, -- beam fades over the last N seconds of lifetime
	InteractRadius = 8,
	MaxConsecutiveNonUpgrades = 3, -- pity: rolls below held rarity before the floor kicks in

	-- Rarity odds per wave bracket, in order Common / Uncommon / Rare / Epic / Legendary.
	-- Weights, not percentages; they are normalised at roll time. Also drives upgrade card tiers.
	RarityOddsByWaveBracket = {
		{ maxWave = 5, odds = { 45, 30, 17, 7, 1 } },
		{ maxWave = 10, odds = { 30, 32, 24, 11, 3 } },
		{ maxWave = 20, odds = { 18, 28, 30, 17, 7 } },
		{ maxWave = math.huge, odds = { 10, 22, 30, 25, 13 } },
	},
	RarityDmgMult = { 1, 1.3, 1.7, 2.3, 3.0 }, -- a legendary of any gun out-DPSes an epic of any other

	------------------------------------------------------------------ Big crate
	BigCrateWaveInterval = 0, -- a crate at the start of every Nth wave; 0 = never (brief says 10)
	BigCrateIntroDrop = true, -- one crate during the intro; after that only Side Job completion drops one
	BigCrateIntroPosition = Vector3.new(0, 0, -14), -- where the intro crate lands
	BigCrateLifetime = 30, -- crate clears after this, or as soon as all its guns are gone
	BigCrateDespawnOnWaveEnd = false, -- true restores the brief's "crate closes at wave end"
	BigCrateWeaponCount = { plus = 1, min = 2 }, -- players + plus, never below min
	BigCrateRarityFloorByBracket = { 2, 3, 3, 4 }, -- Uncommon / Rare / Rare / Epic
	BigCrateDropHeight = 40,
	BigCrateDistanceFromCenter = 20,
	BigCrateFanMin = 5,
	BigCrateFanMax = 7,

	------------------------------------------------------------------ Crew call / stub Side Job
	CallHoldSec = 4,
	SideJobFirstWave = 1,
	SideJobEveryWaves = 2,
	SideJobDurationSec = 75,
	SideJobReward = 600,
	SideJobGold = 5, -- meta currency per completed side job, per player (display only, no persistence)
	SideJobBeaconRadius = 6,
	SideJobHoldSec = 2, -- hold the HACK prompt on the beacon this long to complete
	-- Job type is rolled per job from these weights. hack | capture | one of the six minigames (played at the beacon
	-- at the session tier; retry until the timer runs out).
	SideJobKindWeights = {
		hack = 1,
		capture = 1,
		Lockpick = 1,
		Hotwire = 1,
		Keypad = 1,
		Charges = 1,
		Safe = 1,
		Freq = 1,
	},
	SideJobCaptureSec = 10, -- seconds a player must stand in the circle; pauses while nobody is inside
	SideJobCaptureRadius = 7, -- studs
	SideJobRewardCrate = true, -- a crate drops at the beacon on completion
	CallPillWarnSec = 10, -- pill turns red under this many seconds

	------------------------------------------------------------------ Abilities (Q turret, E barricade, Z stim)
	StructurePlaceDistance = 5, -- studs in front of the player
	TurretHP = 150,
	TurretDmg = 12,
	TurretFireRate = 3, -- shots per second
	TurretRange = 45,
	TurretLifetime = 30,
	TurretCooldown = 20,
	BarricadeHP = 300,
	BarricadeSize = Vector3.new(8, 4, 1),
	BarricadeLifetime = 45,
	BarricadeCooldown = 15,
	StimDuration = 6,
	StimMoveMult = 1.5,
	StimFireRateMult = 1.6,
	StimReloadSpeedMult = 1.6, -- reloads this much faster while stimmed
	StimCooldown = 20,

	------------------------------------------------------------------ Heat (stars, 0..5)
	HeatStart = 2.5,
	HeatWaveClear = 0.5, -- per wave cleared
	HeatSideJobDone = 1, -- per Side Job completed
	HeatSideJobFail = -0.5,
	HeatDowned = -0.5, -- per time health hits 0

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
	FloorTop = 0.5, -- y of the floor's top face (arena and yard); above the default Baseplate so nothing z-fights

	PillarGrid = 5, -- NxN pillars, the center one is skipped so the spawn stays clear
	PillarSize = 4,

	------------------------------------------------------------------ Staging yard (regenerate the map after changing sizes)
	StagingCash = 5000, -- Match Cash while in the yard so the buy tiles can be tested there; START RUN resets to StartingCash
	YardWidth = 120, -- studs east-west, attached to the arena's south wall
	YardDepth = 80, -- studs north-south
	DoorWidth = 12, -- run start door opening in the south wall
	PropSpacing = 10, -- studs between the minigame props along the yard's west wall

	------------------------------------------------------------------ Minigames (test props in the yard)
	MinigameTier = 1, -- starting tier for every game (1..3); the tier pad and the debug panel change it per session
	MinigamePanelPct = 0.55, -- panel width as a share of the shorter screen edge
	-- A result that comes back faster than this is logged as a fail (a client cannot skip the game).
	MinigameMinSec = { Lockpick = 1.5, Hotwire = 1.5, Keypad = 1.5, Charges = 1.5, Safe = 2, Freq = 1 },
	MinigameHaptics = true, -- HapticService pulses on hits and locks (mobile / gamepad)
	MinigameCloseDistance = 14, -- walking further than this from the prop closes the panel (counts as cancel)
	MinigameExitSec = 0.3, -- on DONE / FAILED the panel slides off over this long; input is back at once
	LockpickTargetByTier = { 3, 4, 5 }, -- points to open per tier: green zone +1, pink sliver +2
	LockpickZoneShrink = 0.9, -- zone width x this per hit, floored at half the starting width
	LockpickSpeedUp = 1.08, -- pin speed x this per hit
	LockpickZoneByTier = { 90, 70, 55 }, -- starting zone width in degrees
	LockpickPinSpeed = 150, -- degrees per second at the start
	LockpickSliverDeg = 10, -- width of the +2 pink sliver in the middle of the zone
	HotwireCountByTier = { 3, 4, 5 }, -- wires
	KeypadShowSec = 1.2, -- the code shows this long before the pad lights
	KeypadReshowSec = 0.8, -- the code shows again this long after a wrong digit
	KeypadDigitsByTier = { 3, 4, 5 },
	ChargesCountByTier = { 5, 6, 8 }, -- blast caps to press in order
	SafeWarmRange = 15, -- needle turns amber within this many numbers of the target
	SafeHotRange = 4, -- needle turns green within this
	SafeLockSec = 0.4, -- hold inside the hot range this long to lock a number
	SafeNumbersByTier = { 2, 3, 4 },
	FreqTolerance = 0.06, -- the two waves count as overlapping within this share of the fixed frequency
	FreqLockSec = 0.5, -- hold the overlap this long to lock
	FreqLocksByTier = { 1, 2, 3 },
	FreqRangeByTier = { 1.6, 2.4, 3.5 }, -- slider range as a multiple of the base frequency; wider = harder

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
	RunOverSlowSec = 1, -- slow-mo under the RUN OVER stamp
	-- The red screen and stamp stay this much longer, then the run end cutscene starts. The whole window
	-- (RunOverSlowSec + RunOverHoldSec) is when REVIVE EVERYBODY still saves the run: the crew stands up and the
	-- same wave restarts.
	RunOverHoldSec = 4,
	RunOverTimeScale = 0.3, -- player and enemy speed during the slow-mo

	------------------------------------------------------------------ Run start (IntroSec is the total length)
	RunStartBeats = { doors = 1.4, masks = 2.2, poses = 2.8, orbit = 4.2 }, -- seconds from START RUN
	SquadSize = 4, -- the start / end line-ups fill up to this many with dummy crew (prototype presentation)
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
	SummaryCountUpSec = 1, -- TOTAL BANKED / GOLD count-up length
	GoldPerBanked = 0.01, -- display only, no persistence
}

return Config
