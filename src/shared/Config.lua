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
	IntroSec = 3, -- WAVE 1 banner hold before the first wave

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

	------------------------------------------------------------------ Player
	PlayerMaxHP = 100,
	PlayerWalkSpeed = 16,
	PlayerHPRegenPerSec = 1, -- base regen, scaled by the HP Regen upgrade
	MouseSensitivity = 0.0022, -- radians per mouse pixel
	TouchSensitivity = 0.006, -- radians per touch pixel

	------------------------------------------------------------------ Economy
	UpgradePrice = 100,
	UpgradePriceMult = 1.35, -- upgrade n costs UpgradePrice * mult^n
	WeaponPrice = 300,
	WeaponPriceMult = 1.4,

	------------------------------------------------------------------ Upgrade overlay
	ShopDimPct = 35, -- world dim while the pick-3 is open
	PanelShakePx = 2,
	CardDealStagger = 0.08,
	CardFlipStagger = 0.07,
	TradeoffChance = { 0, 0.1, 0.25, 0.4, 0.5 }, -- per tier 1..5
	TradeoffMalusRatio = 0.5, -- malus = one other stat at this ratio of the buff
	TrackerCols = 10,

	------------------------------------------------------------------ Weapon reel / ground loot
	RollDurationSec = 1.2,
	RollEjectSec = 0.4,
	GroundWeaponLifetime = 60,
	GroundWeaponFadeSec = 10, -- beam fades over the last N seconds of lifetime
	InteractRadius = 8,
	MaxConsecutiveNonUpgrades = 3, -- pity: rolls below held rarity before the floor kicks in

	-- Rarity odds per wave bracket, in order Common / Uncommon / Rare / Epic / Legendary.
	-- Weights, not percentages; they are normalised at roll time. Also drives upgrade card tiers.
	RarityOddsByWaveBracket = {
		{ maxWave = 5, odds = { 70, 22, 7, 1, 0 } },
		{ maxWave = 10, odds = { 50, 30, 15, 4.5, 0.5 } },
		{ maxWave = 20, odds = { 30, 35, 22, 10, 3 } },
		{ maxWave = math.huge, odds = { 15, 30, 30, 18, 7 } },
	},
	RarityDmgMult = { 1, 1.15, 1.35, 1.6, 2.0 },

	------------------------------------------------------------------ Big crate
	BigCrateWaveInterval = 1, -- a crate at the start of every Nth wave (brief says 10; 1 for testing)
	BigCrateIntroDrop = true, -- also drop one during the intro so there is a crate at the start
	BigCrateIntroPosition = Vector3.new(0, 0, -14), -- where the intro crate lands
	BigCrateWeaponCount = { plus = 1, min = 2 }, -- players + plus, never below min
	BigCrateRarityFloorByBracket = { 2, 3, 3, 4 }, -- Uncommon / Rare / Rare / Epic
	BigCrateDropHeight = 40,
	BigCrateDistanceFromCenter = 20,
	BigCrateFanMin = 5,
	BigCrateFanMax = 7,

	------------------------------------------------------------------ Crew call / stub Side Job
	CallHoldSec = 4,
	SideJobFirstWave = 5,
	SideJobEveryWaves = 5,
	SideJobDurationSec = 75,
	SideJobReward = 600,
	SideJobBeaconRadius = 6,
	SideJobStandSec = 10, -- cumulative seconds inside the beacon to complete
	CallPillWarnSec = 10, -- pill turns red under this many seconds

	------------------------------------------------------------------ HUD
	HeatStarsFixed = 2.5,
	DebugEnabled = true,

	------------------------------------------------------------------ Room
	RoomSize = 200,
	WallHeight = 12,
	PillarGrid = 5, -- NxN pillars, the center one is skipped so the spawn stays clear
	PillarSize = 4,
}

return Config
