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
			speed = 12,
			dmg = 5,
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
			speed = 22,
			dmg = 4,
			range = 4,
			cooldown = 0.7,
			scale = 0.85,
			color = "D8D2C4",
			cash = 12,
			attack = "melee",
			lean = true,
		},
		{
			id = "Shooter",
			name = "SHOOTER",
			hp = 100,
			speed = 10,
			dmg = 2,
			range = 45,
			cooldown = 1.5,
			scale = 1.0,
			color = "2F4A8A",
			cash = 20,
			attack = "shooter",
		},
		{
			id = "Marksman",
			name = "MARKSMAN",
			hp = 70,
			speed = 8,
			dmg = 15,
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
			speed = 8,
			dmg = 12,
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
			speed = 9,
			dmg = 10,
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
			speed = 6,
			dmg = 20,
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
	-- Scaling: FinalHp = BaseHp x (1 + HpWaveMult)^(wave - 1) x (1 + HpPerPlayerMult x (players - 1)) x DiffHpMult;
	-- FinalDamage = BaseDamage x (1 + DamageWaveMult)^(wave - 1) x DiffDamageMult. Player count never changes spawn counts.
	HpWaveMult = 0.12,
	DamageWaveMult = 0.06,
	HpPerPlayerMult = 0.5,
	RetargetInterval = 1.0, -- how often an enemy re-picks its target
	EnemyCollidesWithPlayers = false, -- false: enemies walk through players and each other, never body-block
	EnemyStuckDetourSec = 1, -- no progress for this long -> sidestep + jump around the obstacle
	EnemyStuckTeleportSec = 8, -- still stuck after this long -> re-spawn at a random spawn point
	SpawnRingRadius = 90, -- studs from room center
	SpawnPointCount = 8,
	-- Proximity-weighted spawning (GDD): each marker's chance scales by its distance to the nearest living player.
	NearRange = 60, -- within this: x NearWeightMult
	FarRange = 150, -- up to this: x1; beyond: x FarWeightMult
	NearWeightMult = 3.0,
	FarWeightMult = 0.25,
	-- Shooter / Marksman / Boomer / Grenadier / Heavy tuning.
	ShooterHitChance = 0.55, -- a miss cracks a tracer past the player
	MarksmanAimSec = 1.5, -- the red laser paints the line this long, then the shot goes down the line
	MarksmanHitRadius = 2.2, -- studs from the laser line that still counts as "in the beam"
	BoomerPlaceableSearch = 40, -- a placeable this close is preferred over players
	BoomerFuseSec = 1.2, -- beeps rising and swelling once in range, then the blast
	BoomerDamage = 12, -- to players in the blast
	BoomerPlaceableMult = 4, -- x BoomerDamage to structures
	BoomerRadius = 8,
	BoomerDeathRadiusMult = 0.6, -- a Boomer killed by damage still goes off, smaller
	GrenadierRadius = 7, -- the red circle grows from 0 to this over GrenadierTelegraphSec, then bursts
	GrenadierTelegraphSec = 1.2,
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
		{ WaveMin = 1, Henchman = 100, Runner = 0, Shooter = 0, Marksman = 0, Boomer = 0, Grenadier = 0, Heavy = 0 },
		{ WaveMin = 2, Henchman = 75, Runner = 25, Shooter = 0, Marksman = 0, Boomer = 0, Grenadier = 0, Heavy = 0 },
		{ WaveMin = 3, Henchman = 60, Runner = 22, Shooter = 0, Marksman = 0, Boomer = 0, Grenadier = 18, Heavy = 0 },
		{ WaveMin = 4, Henchman = 50, Runner = 20, Shooter = 10, Marksman = 0, Boomer = 5, Grenadier = 15, Heavy = 0 },
		{ WaveMin = 5, Henchman = 44, Runner = 18, Shooter = 10, Marksman = 0, Boomer = 6, Grenadier = 14, Heavy = 8 },
		{ WaveMin = 6, Henchman = 40, Runner = 16, Shooter = 10, Marksman = 6, Boomer = 6, Grenadier = 14, Heavy = 8 },
		{ WaveMin = 8, Henchman = 34, Runner = 16, Shooter = 12, Marksman = 8, Boomer = 8, Grenadier = 14, Heavy = 8 },
		{
			WaveMin = 12,
			Henchman = 30,
			Runner = 15,
			Shooter = 14,
			Marksman = 10,
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
	RagdollForceByArchetype = { Pistol = 1, SMG = 0.8, Rifle = 1.3, Shotgun = 2.8, Sniper = 2.4, LMG = 1.5 }, -- x RagdollImpulse / RagdollLift / RagdollSpin
	RagdollOverkillMax = 1.5, -- extra multiplier when the overkill damage reaches the enemy's max HP (scales up to it)
	RagdollVariance = 0.25, -- +/- random share on every throw so no two look alike
	RagdollBlastImpulse = 90, -- studs/s outward from an explosion (claymore, Splash upgrade kill), at the center
	RagdollBlastLift = 40, -- upward at the center; both fall off to RagdollBlastEdge at the blast radius
	RagdollBlastSpin = 25,
	RagdollBlastEdge = 0.35,
	RagdollTickForce = 0.4, -- fire fields, flame turret and turret shots: a slump, not a throw

	------------------------------------------------------------------ Combat
	StartingCash = 3000, -- Match Cash at run start (brief says 0; raised for testing)
	-- Kill cash is the archetype's `cash` row (Enemies) x greed x the elite and heat multipliers.
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
	-- Other players' shots: the server sends every teammate the shot's end points, the client draws the same
	-- tracer from that gun's muzzle and plays the shot sound at the gun (3D, falls off over RemoteShotRange).
	RemoteTracers = true,
	RemoteShotVolume = 0.3,
	RemoteShotRange = 110, -- studs the teammate's shot sound carries
	ShotPitchByArchetype = { Sniper = 0.6, Shotgun = 0.7, SMG = 1.3, LMG = 0.85 }, -- anything else plays at 1
	HitSparks = 6, -- impact particles per bullet hit on an enemy (0 = none)
	KillSparks = 18, -- extra burst on a kill
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
		hack = 1,
		capture = 1,
		Lockpick = 1,
		Hotwire = 1,
		Keypad = 1,
		Charges = 1,
		Safe = 1,
		Freq = 1,
		vault = 1, -- CRACK THE VAULT (from VaultJobMinWave, once per run when VaultJobOnce)
	},
	SideJobCaptureSec = 10, -- seconds a player must stand in the circle; pauses while nobody is inside
	SideJobCaptureRadius = 7, -- studs
	SideJobRewardCrate = true, -- a crate drops at the beacon on completion
	CallPillWarnSec = 10, -- pill turns red under this many seconds

	------------------------------------------------------------------ Abilities (the four class kits, Classes.lua)
	-- Cooldown per ability id, seconds. Abilities are free in a run (the $ on the Classes tab is a label).
	AbilityCooldown = {
		barricade = 15,
		turret = 20,
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
	StructurePlaceDistance = 5, -- studs in front of the player (placeables: turrets, barricade, oil drum, med bag, claymore)
	ThrowDistance = 12, -- studs in front of the player a thrown ability lands (flashbang, molotov)
	ThrowFlightSec = 0.6, -- the throw's arc takes this long, then it goes off
	FieldTickSec = 0.5, -- ground fields (med bag, molotov, drum fire) apply their per-second numbers this often
	-- INITIATE
	TurretHP = 150,
	TurretDmg = 12,
	TurretFireRate = 3, -- shots per second
	TurretRange = 45,
	TurretLifetime = 30,
	BarricadeHP = 300,
	BarricadeSize = Vector3.new(8, 4, 1),
	BarricadeLifetime = 45,
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
	MedBagLifetime = 15,
	HealTurretHP = 150,
	HealTurretBeamHeal = 6, -- HP per second on the beam
	HealTurretRange = 30, -- picks the hurt teammate with the lowest HP share in range
	HealTurretTickSec = 0.5,
	HealTurretLifetime = 30,
	-- SHARPSHOOTER
	ClaymoreDamage = 220, -- to every enemy in the blast
	ClaymoreTriggerRadius = 5, -- an enemy this close sets it off
	ClaymoreBlastRadius = 8,
	ClaymoreArmSec = 1, -- it cannot go off before this
	ClaymoreLifetime = 60,
	DeadEyeDuration = 8,
	DeadEyeDmgPct = 25, -- weapon damage x (1 + this / 100)
	DeadEyeSpeedPct = 20,
	DeadEyePierce = 2, -- extra enemies every bullet passes through while it runs (on top of upgrades and sniper pierce)
	FlashRadius = 12, -- enemies this close to the burst are stunned
	StunDuration = 3, -- stunned enemies stop and do not swing
	-- TORCH
	MolotovRadius = 7,
	MolotovLifetime = 8,
	MolotovBurnPerSec = 15,
	MolotovMoveSlowPct = 30, -- enemies in the fire walk this much slower
	FlameTurretHP = 150,
	FlameTurretDps = 30,
	FlameTurretRange = 14, -- short: a stream, not a gun
	FlameTurretTickSec = 0.25,
	FlameTurretLifetime = 30,
	OilDrumHP = 200,
	OilDrumLifetime = 45,
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
	CashBagsPerWave = 2, -- spawned at every wave start (not the boss cutscene), up to MaxActiveBags
	GoldBagsPerWave = 1,
	MaxActiveBags = 6, -- caps the wave-start trickle; bursts (boss, vault) bypass it
	BagCollectSec = 1.0, -- hold F on a bag
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
	VaultJobMinWave = 3, -- CRACK THE VAULT can be drawn from this wave (weight in SideJobKindWeights)
	VaultJobOnce = true, -- at most once per run (a failed draw can come back)
	VaultBurstCash = 6, -- bags dropped inside when it opens
	VaultBurstGold = 4,
	VaultOpenSec = 60, -- the loot window from the door opening
	VaultGasWarnSec = 10, -- alarm, strobe and MARLOW's warning this long before the gas
	VaultGasDps = 8, -- to any player inside once the gas is in (stops the moment they step out)

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

	------------------------------------------------------------------ Boss (TITAN, Boss.lua; step 5 of brief 4)
	BossWaveInterval = 10, -- the first boss wave and every multiple after (0 = never)
	BossWaveBudgetPct = 0.4, -- boss waves spawn this share of the normal budget alongside the boss
	BossParBonusSec = 30, -- added to a boss wave's par (computed on the regular budget)
	BossId = "Titan", -- which boss the boss waves bring (Bosses/<id>.lua; the shell takes any id)
	BossCutsceneSec = 4.0, -- the intermission's boss cutscene: game paused, players invulnerable and input-locked
	BossCutsceneBeats = { call = 0, blow = 0.8, gun = 2.2, back = 3.4 }, -- seconds: MARLOW's call and the low wall shot, the wall blows and the boss steps through, barrels spin and the name card, camera snaps back and the bar slides in
	BossAbilityGapSec = 1.5, -- the boss walks and swings this long between abilities
	BossBagBurst = 6, -- bags around the body on a kill (half cash, half gold)
	BossBagBurstRadius = 9,
	BossCrateCount = 2, -- the boss crate: one guaranteed Legendary of a random owned gun plus the rest as normal deals
	-- TITAN
	TitanHp = 4000, -- x the wave HP scaling x the player count multiplier
	TitanSpeed = 7,
	TitanMeleeDmg = 35,
	TitanKnockback = 12, -- contact knockback, like the Heavy
	TitanScale = 1.8,
	TitanPhasePcts = { 0.66, 0.33 }, -- phase 2 (plates 1-2 fall, faster sweep spin) and phase 3 (plates 3-4 fall, call-ins)
	TitanSweepSpinSec = 1.5, -- barrels spin with a glow, a rising whine and a faint cone on the floor...
	TitanSweepSpinSecP2 = 1.0, -- ...this long from phase 2
	TitanSweepSec = 3, -- the cone sweeps left to right over this long
	TitanSweepArc = 120, -- degrees
	TitanSweepRange = 40,
	TitanSweepWidth = 12, -- degrees either side of the beam that still counts as in it
	TitanSweepDps = 40, -- to players in the beam with LoS; placeables take it too
	TitanSweepCooldown = 9,
	TitanChargeTelegraphSec = 1.0, -- red line on the floor from TITAN to the locked player
	TitanChargeSpeedMult = 3,
	TitanChargeDmg = 50, -- the first player hit on the line
	TitanChargeKnockback = 18,
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
	FloorTop = 0.5, -- y of the floor's top face (arena and yard); above the default Baseplate so nothing z-fights

	PillarGrid = 5, -- NxN pillars, the center one is skipped so the spawn stays clear
	PillarSize = 4,

	------------------------------------------------------------------ Hub (the yard; regenerate the map after changing sizes)
	MatchMode = "local", -- "local": the party plays in this server's arena. Reserved servers / TeleportService are out of scope.
	YardWidth = 120, -- studs east-west, attached to the arena's south wall
	YardDepth = 80, -- studs north-south
	DoorWidth = 12, -- arena door opening in the south wall
	PropSpacing = 10, -- studs between the minigame props along the yard's east wall
	QueueZoneSize = 16, -- the queue pad is this many studs square, in front of the arena door
	StationSpacing = 16, -- studs between the three customization stations along the west wall
	HubCash = 0, -- Match Cash shown in the hub (nothing to buy there)

	------------------------------------------------------------------ Queue zone / Create Match
	QueueZoneCount = 1, -- zones in the hub (QueueZone1..N parts in the map); the code never assumes 1
	MaxPartySize = 4,
	QueueCountdownSec = 15, -- from CREATE; a full party or a party of 1 starts at once
	QueueMaps = { { id = "TheBank", name = "THE BANK" } }, -- one entry in the prototype
	QueueDifficulties = { { id = "Normal", name = "NORMAL" } },
	DiffHpMult = 1.0,
	DiffDamageMult = 1.0,
	DiffGoldMult = 1.0,

	------------------------------------------------------------------ Meta (profiles, Armory levels, classes, masks)
	StubBoostSec = 1800, -- the hub HUD's stub +50% GOLD boost chip counts down from this (display only)
	StartingGold = 10000, -- fresh profile
	ProfileAutosaveSec = 60,
	ProfileSaveDebounceSec = 2, -- purchases / equips within this window write once
	UpgDmgPct = 0.05, -- weapon base damage x (1 + UpgDmgPct x level)
	UpgMagPct = 0.05, -- mag x (1 + UpgMagPct x level)
	UpgReloadPct = 0.05, -- reload time / (1 + UpgReloadPct x level)
	UpgFireRatePct = 0.03, -- fire rate x (1 + UpgFireRatePct x level)
	RarityUpgCostMult = 1.0, -- upgrade cost = upgBaseCost x this ^ level
	AbilityGrowthPct = 0.1, -- default growth per ability level for every upgradeable variable (AbilityGrowth.lua)
	-- Character idle in the customization scene, per equipped class (default R15 idles stand in).
	ClassIdleAnimationId = {
		INITIATE = "rbxassetid://507766388",
		DOC = "rbxassetid://507766666",
		SHARPSHOOTER = "rbxassetid://507766388",
		TORCH = "rbxassetid://507766388",
	},
	MetaCameraDistance = 7.5, -- studs from the character in the customization scene (closer = bigger avatar)
	MetaCameraSideShare = 0.72, -- the camera sits this x distance to the character's left, so the avatar reads about a fifth in from the left edge
	MetaCameraHeight = 0.2, -- camera height relative to the character's center in the scene
	MetaCameraAim = -1.6, -- the camera aims this far below the character's center, so the avatar sits high in the frame (head near the top)
	MetaDragSensitivity = 0.012, -- radians per pixel when dragging the avatar round in the scene
	MetaCameraTweenSec = 0.45,
	MetaWrapZoomDistance = 3.5, -- CUSTOMIZE pushes the camera in on the gun to this distance

	------------------------------------------------------------------ Payout (GDD_7)
	GoldPerWaveBase = 20, -- per cleared wave
	GoldPerWaveAdd = 5, -- x (wave - 1)
	GoldPerObjective = 50, -- per side job completed
	-- GoldEarned = (sum over cleared waves + GoldPerObjective x objectives) x DiffGoldMult, plus SideJobGold per job.

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
	HotwireSnapPx = 48, -- a wire released within this many design px (400-wide basis) of a socket still connects
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
	RevivePausesBleed = true, -- a teammate's revive hold freezes the bleed timer; letting go resumes it
	BusyTagOffset = 3.2, -- studs above a teammate's head for the LOCKPICK / HACKING / CAPTURING tag
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
	SummaryCountUpSec = 1, -- GOLD EARNED count-up length
}

return Config
