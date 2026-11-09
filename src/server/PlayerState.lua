--!strict
-- Per-player authoritative state: cash, upgrades, held gun, pity, debug flags, plus the profile (Gold,
-- Armory, class, mask) once loaded. Builds StateSync.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)
local Rarity = require(Shared.Rarity)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Masks = require(Shared.Masks)
local Emotes = require(Shared.Emotes)
local Wraps = require(Shared.Wraps)
local GunModels = require(Shared.GunModels)
local MaskShapes = require(Shared.MaskShapes)
local Classes = require(Shared.Classes)
local AbilityGrowth = require(Shared.AbilityGrowth)
local Skills = require(Shared.Skills)
local Stats = require(script.Parent.Stats)
local Runs = require(script.Parent.Runs)
local Log = require(script.Parent.Log)
local Profiles = require(script.Parent.Profiles)
local Boosts = require(script.Parent.Boosts)

export type State = {
	player: Player,
	profile: Profiles.Profile?, -- nil until loaded
	cash: number,
	upgradesBought: number,
	upgrades: { [string]: Types.TrackerItem },
	upgradeOrder: { string },
	openPick3: { Types.Card }?,
	held: Types.Held,
	offhand: Types.Held?, -- the other loadout slot (two guns, Round 21); nil = that slot is empty
	activeSlot: number, -- 1 or 2: which slot `held` is (the HUD numbers them)
	lastSwitchAt: number, -- os.clock() of the last slot switch (WeaponSwitchSec)
	stowed: Types.Held?, -- the real gun while downed with the sidearm
	pityStreak: number,
	forcedRarity: number?,
	forceTradeoff: boolean,
	forceElement: boolean, -- debug: the next pick-3 holds an element card
	forceSynergy: boolean, -- debug (Round 18): the next pick-3 holds a synergy card if any qualifies
	waveCash: number, -- cash earned since the last wave end (the income log)
	waveUpgrades: number, -- upgrades bought since the last wave end
	god: boolean,
	noCooldowns: boolean, -- debug (Round 18): abilities never spend a charge or start a cooldown
	lastShotAt: number,
	lastSwapAt: number,
	nextUid: number,
	dirty: boolean,
	cooldowns: { [string]: number }, -- ability id -> server time the cooldown ends
	buffId: string?, -- the running self buff (stim | stimshot | deadeye), nil = none
	buffUntil: number, -- server time the self buff ends, 0 = inactive
	abilityActive: { [string]: number }, -- non-buff abilities with a running window (overclock, eagleeye): server time it ends
	-- Mastery (brief 5): the class and its tier at run start (the passives), and the per-run passive counters.
	masteryClass: string?,
	masteryTier: number,
	stimExtended: number, -- ADRENALINE JUNKIE seconds added to the running Adrenaline
	charges: { [string]: number }, -- ability charges left (nil = full); DOUBLE DOWN gives Frag / Claymore a second
	fieldHospitalUntil: number, -- inside a FIELD HOSPITAL med bag until this server time (+damage)
	triageProgress: number, -- TRIAGE: 0..1 while downed inside a DOC's med bag / healing turret range
	-- Downed / revive
	downed: boolean,
	bledOut: boolean, -- spectator: no character until revived or the run ends
	bleedEndsAt: number,
	invulnUntil: number, -- no damage until this server time (just revived)
	armor: number, -- Round 25 ARMOR: points left (soak hits before HP)
	armorMax: number, -- the ARMOR total last seen (a new card fills the difference)
	lastHurtAt: number, -- server time of the last hit (armor refills ArmorRegenDelay after it)
	reviveProgress: number, -- 0..1 while a teammate holds the revive
	reviver: Player?,
	savedJump: { useJumpPower: boolean, jumpPower: number, jumpHeight: number }?,
	lastPosition: Vector3, -- where the character was when it bled out
	pendingSpawnCFrame: CFrame?, -- next LoadCharacter lands here
	inRange: boolean, -- brief 8: standing in the hub's training range (armed; Run/Range.lua)
	-- Brief 9: the Skill Web folded into one modifier table at the run start / range entry (PlayerState.armSkills);
	-- all zeros in the hub. Every hook reads one field of it.
	skillMods: Skills.Mods,
	-- Run stats (reset per run)
	kills: number,
	cashCollected: number, -- cash earned this run, not the balance
	revives: number, -- teammates stood up by this player
	downs: number,
	selfRevives: number,
	reviveAllUsed: number,
	gold: number, -- side job Gold earned this run, paid with the payout
	jobsDone: number, -- side jobs completed this run (everyone in the run gets the credit)
	minigamesDone: number, -- minigames finished this run
	bags: number, -- bags this player collected this run (cash or gold)
	pose: number, -- index into Config.Poses, rolled at run start
	maskColor: string, -- hex, the equipped mask's color
	joinIndex: number, -- order the player joined the server (ties, line-ups)
}

local states: { [Player]: State } = {}
local joinCounter = 0

local PlayerState = {}

local function freshState(player: Player, joinIndex: number): State
	return {
		player = player,
		profile = nil,
		cash = Config.HubCash, -- joiners land in the hub; Hub.beginRun sets StartingCash for the party
		upgradesBought = 0,
		upgrades = {},
		upgradeOrder = {},
		openPick3 = nil,
		held = { weaponId = Weapons.Starter, rarity = Rarity.Common, level = 0, uid = 1 },
		offhand = nil,
		activeSlot = 1,
		lastSwitchAt = 0,
		stowed = nil,
		pityStreak = 0,
		forcedRarity = nil,
		forceTradeoff = false,
		forceElement = false,
		forceSynergy = false,
		waveCash = 0,
		waveUpgrades = 0,
		god = false,
		noCooldowns = false,
		lastShotAt = 0,
		lastSwapAt = 0,
		nextUid = 2,
		dirty = true,
		cooldowns = {},
		buffId = nil,
		buffUntil = 0,
		abilityActive = {},
		masteryClass = nil,
		masteryTier = 0,
		stimExtended = 0,
		charges = {},
		fieldHospitalUntil = 0,
		triageProgress = 0,
		downed = false,
		bledOut = false,
		bleedEndsAt = 0,
		invulnUntil = 0,
		armor = 0,
		armorMax = 0,
		lastHurtAt = 0,
		reviveProgress = 0,
		reviver = nil,
		savedJump = nil,
		lastPosition = Vector3.zero,
		pendingSpawnCFrame = nil,
		inRange = false,
		skillMods = Skills.zero(),
		kills = 0,
		cashCollected = 0,
		revives = 0,
		downs = 0,
		selfRevives = 0,
		reviveAllUsed = 0,
		gold = 0,
		jobsDone = 0,
		minigamesDone = 0,
		bags = 0,
		pose = 1,
		maskColor = Masks.ById[Masks.Default].color,
		joinIndex = joinIndex,
	}
end

function PlayerState.get(player: Player): State
	local s = states[player]
	if not s then
		joinCounter += 1
		s = freshState(player, joinCounter)
		s.profile = Profiles.get(player)
		states[player] = s
	end
	return s
end

-- Alive and on their feet: has a character, not downed, not bled out.
function PlayerState.isStanding(state: State): boolean
	local char = state.player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and not state.downed and not state.bledOut
end

function PlayerState.all(): { [Player]: State }
	return states
end

function PlayerState.markDirty(player: Player)
	local s = states[player]
	if s then
		s.dirty = true
	end
end

function PlayerState.markAllDirty()
	for _, s in states do
		s.dirty = true
	end
end

function PlayerState.buffActive(state: State): boolean
	return state.buffId ~= nil and state.buffUntil > Workspace:GetServerTimeNow()
end

------------------------------------------------------------------ Profile-derived
function PlayerState.weaponLevel(state: State, weaponId: string): number
	local p = state.profile
	local entry = p and p.weapons[weaponId]
	return if entry then entry.level else 0
end

function PlayerState.wrapOf(state: State, weaponId: string): string?
	local p = state.profile
	local entry = p and p.weapons[weaponId]
	return if entry then entry.wrap else nil
end

function PlayerState.maskOf(state: State): Masks.Mask
	local p = state.profile
	local id = if p then p.masks.equipped else Masks.Default
	return Masks.ById[id] or Masks.ById[Masks.Default]
end

function PlayerState.classOf(state: State): string
	local p = state.profile
	return if p then p.classes.equipped else Classes.Default
end

-- The line-up pose and the MVP flex from the profile (defaults when nothing is set).
function PlayerState.squadEmote(state: State): Emotes.Emote
	local p = state.profile
	local id = if p and p.emotes then p.emotes.squad else Emotes.DefaultSquad
	return Emotes.ById[id] or Emotes.ById[Emotes.DefaultSquad]
end

function PlayerState.mvpEmote(state: State): Emotes.Emote
	local p = state.profile
	local id = if p and p.emotes then p.emotes.mvp else Emotes.DefaultMvp
	return Emotes.ById[id] or Emotes.ById[Emotes.DefaultMvp]
end

function PlayerState.abilityLevel(state: State, abilityId: string): number
	local p = state.profile
	return if p then (p.abilities[abilityId] or 0) else 0
end

-- The starter gun from the profile: Common, at its Armory level.
function PlayerState.starterHeld(state: State): Types.Held
	local p = state.profile
	local id = if p then p.starterWeaponId else Weapons.Starter
	if not Weapons.ById[id] then
		id = Weapons.Starter
	end
	local held =
		{ weaponId = id, rarity = Rarity.Common, level = PlayerState.weaponLevel(state, id), uid = state.nextUid }
	state.nextUid += 1
	return held
end

-- Round 24z: the second starter (the profile's slot 2), or nil when the slot is empty.
function PlayerState.starterOffhand(state: State): Types.Held?
	local p = state.profile
	local id = p and p.starterWeaponId2
	if typeof(id) ~= "string" or not Weapons.ById[id] or id == (p and p.starterWeaponId) then
		return nil
	end
	local held =
		{ weaponId = id, rarity = Rarity.Common, level = PlayerState.weaponLevel(state, id), uid = state.nextUid }
	state.nextUid += 1
	return held
end

-- Owned weapon ids, in Weapons.List order (the roll pool).
function PlayerState.ownedWeapons(state: State): { Weapons.Weapon }
	local out = {}
	local p = state.profile
	for _, w in Weapons.List do
		if not p or p.weapons[w.id] then
			table.insert(out, w)
		end
	end
	if #out == 0 then
		table.insert(out, Weapons.ById[Weapons.Starter])
	end
	return out
end

------------------------------------------------------------------ Computed stats
-- The multipliers a self buff gives at the player's level of that ability (AbilityGrowth on the percentages).
-- stim: fire rate, reload, move. stimshot: fire rate, reload (plus the heal on use). deadeye: damage, accuracy, pierce.
function PlayerState.buffFor(state: State, id: string): Stats.Buffs
	local level = PlayerState.abilityLevel(state, id)
	local b: Stats.Buffs = { fireRateMult = 1, moveSpeedMult = 1, reloadSpeedMult = 1, damageMult = 1, pierceAdd = 0 }
	-- Round 25: ABILITY POWER strengthens a buff's bonus too (AbilityPowerBuffShare of it), not only damage / heals.
	local amp = PlayerState.abilityBuffAmp(state)
	if id == "stim" then
		-- INITIATE's Adrenaline (the id stays "stim" for saved levels).
		b.fireRateMult = 1
			+ amp * AbilityGrowth.at(id, "FireRatePct", (Config.AdrenalineFireRateMult - 1) * 100, level) / 100
		b.reloadSpeedMult = 1
			+ amp * AbilityGrowth.at(id, "ReloadPct", (Config.AdrenalineReloadSpeedMult - 1) * 100, level) / 100
		b.moveSpeedMult = 1 + amp * AbilityGrowth.at(id, "MovePct", (Config.AdrenalineMoveMult - 1) * 100, level) / 100
	elseif id == "stimshot" then
		b.fireRateMult = 1
			+ amp * AbilityGrowth.at(id, "FireRatePct", (Config.StimShotFireRateMult - 1) * 100, level) / 100
		b.reloadSpeedMult = 1
			+ amp * AbilityGrowth.at(id, "ReloadPct", (Config.StimShotReloadSpeedMult - 1) * 100, level) / 100
	elseif id == "deadeye" then
		b.damageMult = 1 + amp * AbilityGrowth.at(id, "DmgPct", Config.DeadEyeDmgPct, level) / 100
		-- Round 19c: tighter spread instead of move speed (AccuracyPct less spread, like the Accuracy upgrade).
		b.spreadMult =
			math.max(0.05, 1 - amp * AbilityGrowth.at(id, "AccuracyPct", Config.DeadEyeAccuracyPct, level) / 100)
		-- Fractional pierce is real: 2.2 passes through two more enemies at full damage and a third at 20%.
		b.pierceAdd = amp * AbilityGrowth.at(id, "Pierce", Config.DeadEyePierce, level)
	end
	return b
end

-- Round 25: ABILITY POWER on effects that aren't damage or healing. Read straight from the upgrades (computed()
-- calls buffFor, so this can't go through it). Strength: the buff's bonus x this (1 = no Ability Power).
function PlayerState.abilityBuffAmp(state: State): number
	local u = state.upgrades.AbilityPower
	local pw = math.max(0.2, 1 + (if u then u.pct / 100 else 0))
	return 1 + (pw - 1) * Config.AbilityPowerBuffShare
end

-- Durations and radii take a smaller share, so a stacked build never turns a slow into a freeze or a radius
-- into the whole map (AbilityPowerDurationShare / AbilityPowerRadiusShare).
function PlayerState.abilityDurationAmp(state: State): number
	local u = state.upgrades.AbilityPower
	local pw = math.max(0.2, 1 + (if u then u.pct / 100 else 0))
	return 1 + (pw - 1) * Config.AbilityPowerDurationShare
end

function PlayerState.abilityRadiusAmp(state: State): number
	local u = state.upgrades.AbilityPower
	local pw = math.max(0.2, 1 + (if u then u.pct / 100 else 0))
	return 1 + (pw - 1) * Config.AbilityPowerRadiusShare
end

-- A class mastery passive: on while `classId` is the class the run started with at `tier` or better.
function PlayerState.passive(state: State, classId: string, tier: number): boolean
	return state.masteryClass == classId and state.masteryTier >= tier
end

function PlayerState.computed(state: State): Types.Computed
	local buffs: Stats.Buffs? = nil
	local id = state.buffId
	if id and PlayerState.buffActive(state) then
		buffs = PlayerState.buffFor(state, id)
	end
	-- CREW OVERCLOCK (ENGINEER III): every crew member's gun runs faster while the Overclock lasts.
	local W = Runs.worldOf(state.player)
	if W.crewOverclockUntil > Workspace:GetServerTimeNow() and W.isInParty(state.player) then
		local b = buffs or { fireRateMult = 1, moveSpeedMult = 1, reloadSpeedMult = 1, damageMult = 1, pierceAdd = 0 }
		b.fireRateMult *= 1 + Config.CrewOverclockFireRatePct
		b.reloadSpeedMult *= 1 + Config.CrewOverclockReloadPct
		buffs = b
	end
	local st = Stats.compute(state.upgrades, state.held, buffs, state.skillMods)
	-- SHARPSHOOTER I / II.
	if PlayerState.passive(state, "SHARPSHOOTER", 1) then
		st.headshotMult += Config.SharpHeadshotAdd
	end
	if PlayerState.passive(state, "SHARPSHOOTER", 2) then
		local w = Weapons.ById[state.held.weaponId]
		if w and (w.archetype == "Sniper" or w.archetype == "Pistol") then
			st.reloadTime /= 1 + Config.MarksmanKitReloadPct
		end
	end
	-- FIELD HOSPITAL (a DOC III's med bag): allies inside deal more damage.
	if state.fieldHospitalUntil > Workspace:GetServerTimeNow() then
		st.damage *= 1 + Config.FieldHospitalDmgPct
	end
	-- Brief 6 boosts: POWER on weapon damage, CASH (and VIP's +25%) on CASH GAIN.
	st.damage *= Boosts.damageMult(state.player)
	st.cashGain *= Boosts.cashMult(state.player)
	return st
end

function PlayerState.damagePct(state: State): number
	local u = state.upgrades.Damage
	return if u then u.pct / 100 else 0
end

------------------------------------------------------------------ Character dressing
-- Held gun visual (art pass): the weapon's GunModels stand-in model, joined to the right hand by the "GunJoint"
-- Motor6D in a hand-carry rest pose. Every client's GunAnim poses the arms and the gun from there during a run;
-- anything that doesn't animate it (the hub, mannequin clones) sees the gun carried in the hand. Rarity colours the
-- receiver strips, the equipped wrap paints the furniture (grip / handguard / stock).
function PlayerState.refreshHeldVisual(state: State)
	local char = state.player.Character
	if not char then
		return
	end
	local old = char:FindFirstChild("HeldGun")
	if old then
		old:Destroy()
	end
	local oldGrip = char:FindFirstChild("HeldGunWrap") -- pre-art-pass band, if a character still has one
	if oldGrip then
		oldGrip:Destroy()
	end
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local gun = GunModels.build(state.held.weaponId, {
		rarity = state.held.rarity,
		wrapId = PlayerState.wrapOf(state, state.held.weaponId),
	})
	gun.Name = "HeldGun"
	GunModels.mountToHand(gun, hand)
	gun.Parent = char
end

-- Mask: head recolor plus a simple accessory Part welded to the head (visor or bandana), from the profile.
function PlayerState.applyMask(state: State)
	local char = state.player.Character
	local head = char and char:FindFirstChild("Head")
	if not char or not head or not head:IsA("BasePart") then
		return
	end
	local mask = PlayerState.maskOf(state)
	state.maskColor = mask.color
	head.Color = Color3.fromHex(mask.color)
	local old = char:FindFirstChild("MaskPart")
	if old then
		old:Destroy()
	end
	-- Brief 6: every shape (the new crate / VIP / pass masks too) comes from the shared builder.
	local part = MaskShapes.build(head, mask, "MaskPart", char)
	-- The VIP mask gets the Epic+ sparkle treatment in the hub.
	if part and mask.rarity >= 4 and not Runs.inRun(state.player) then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "MaskSparkle"
		sparkle.Color = ColorSequence.new(Color3.fromHex(mask.accent or mask.color))
		sparkle.LightEmission = 1
		sparkle.Size = NumberSequence.new(0.12, 0)
		sparkle.Lifetime = NumberRange.new(0.6, 1.1)
		sparkle.Rate = if mask.saleType == "VIP" then 14 else 6
		sparkle.Speed = NumberRange.new(0.6, 1.4)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Parent = part
	end
end

-- Hats, hair and face accessories go on join so the mask reads; everything else stays.
local STRIPPED = {
	[Enum.AccessoryType.Hat] = true,
	[Enum.AccessoryType.Hair] = true,
	[Enum.AccessoryType.Face] = true,
	[Enum.AccessoryType.Eyebrow] = true,
	[Enum.AccessoryType.Eyelash] = true,
}
local function stripAccessories(char: Model)
	for _, acc in char:GetChildren() do
		if acc:IsA("Accessory") then
			local kind = acc.AccessoryType
			if STRIPPED[kind] or kind == Enum.AccessoryType.Unknown then
				acc:Destroy()
			end
		end
	end
end

-- mag: rounds the gun still has (a floor pickup); nil = a fresh gun with a full mag.
function PlayerState.setHeld(state: State, weaponId: string, rarity: number, level: number?, mag: number?)
	state.held = {
		weaponId = weaponId,
		rarity = rarity,
		level = level or PlayerState.weaponLevel(state, weaponId),
		uid = state.nextUid,
		mag = mag,
	}
	state.nextUid += 1
	PlayerState.refreshHeldVisual(state)
	state.dirty = true
end

function PlayerState.applyCharacterStats(state: State)
	local char = state.player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local st = PlayerState.computed(state)
	local oldMax = hum.MaxHealth
	hum.MaxHealth = st.maxHP
	if oldMax > 0 and st.maxHP > oldMax then
		hum.Health = math.min(hum.Health + (st.maxHP - oldMax), st.maxHP)
	else
		hum.Health = math.clamp(hum.Health, 1, st.maxHP)
	end
	-- Brief 8: the warehouse is big; the hub (outside the range) walks at HubWalkSpeedMult.
	local hubMult = if Runs.slotOf(state.player).isHub and not state.inRange then Config.HubWalkSpeedMult else 1
	-- Round 24aa prototype: sprinting (Shift) puts the gun away and runs SprintSpeedMult faster.
	local sprintMult = if (state :: any).sprinting then Config.SprintSpeedMult else 1
	hum.WalkSpeed = if state.downed then Config.DownedWalkSpeed else st.moveSpeed * hubMult * sprintMult
end

-- Installed by Hub: where a freshly loaded character goes (nil = the SpawnLocation).
PlayerState.spawnCFrame = nil :: ((Player) -> CFrame?)?

-- The profile arrived or changed its equips: starter, mask, wrap.
function PlayerState.applyProfile(state: State)
	state.profile = Profiles.get(state.player)
	state.held = PlayerState.starterHeld(state)
	state.offhand = PlayerState.starterOffhand(state)
	state.activeSlot = 1
	state.stowed = nil
	PlayerState.applyMask(state)
	PlayerState.refreshHeldVisual(state)
	state.dirty = true
end

function PlayerState.reset(state: State, cash: number?)
	local fresh = freshState(state.player, state.joinIndex)
	for k, v in fresh do
		(state :: any)[k] = v
	end
	state.profile = Profiles.get(state.player)
	state.cash = cash or Config.StartingCash
	state.held = PlayerState.starterHeld(state)
	state.offhand = PlayerState.starterOffhand(state) -- Round 24z: both starters go in
	local char = state.player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.MaxHealth = Config.PlayerMaxHP
		hum.Health = Config.PlayerMaxHP
		-- Back on their feet if the reset caught them downed.
		hum.UseJumpPower = false
		hum.JumpHeight = 7.2
	end
	PlayerState.applyCharacterStats(state)
	PlayerState.applyMask(state)
	PlayerState.refreshHeldVisual(state)
	state.dirty = true
end

-- Brief 9: fold the profile's Skill Web into the modifier table for a run start or the range (`why` is the log's
-- context). Logs every owned node once and the summary line. Health / walk speed pick it up at once.
function PlayerState.armSkills(state: State, why: string)
	local p = state.profile or Profiles.get(state.player)
	local owned = p and p.skills and p.skills.owned
	state.skillMods = Skills.modifiers(owned)
	if state.skillMods.nodes > 0 then
		for _, n in Skills.List do
			if owned and owned[n.id] then
				print(
					string.format(
						"[GHS Skills] %s applied %s%s %s",
						n.id,
						n.effect.stat,
						if n.effect.filter then "." .. n.effect.filter else "",
						Skills.fmtValue(n.effect.kind, n.effect.value)
					)
				)
			end
		end
	end
	Log.event(
		"Skills",
		"%s applied %d nodes (%s): %s",
		state.player.Name,
		state.skillMods.nodes,
		why,
		Skills.summary(state.skillMods)
	)
	PlayerState.applyCharacterStats(state)
	state.dirty = true
end

-- Back to nothing (leaving the range).
function PlayerState.disarmSkills(state: State)
	state.skillMods = Skills.zero()
	state.armor = 0
	state.armorMax = 0
	PlayerState.applyCharacterStats(state)
	state.dirty = true
end

-- Installed by Downed: what happens at 0 HP. Without it health just resets.
PlayerState.onZeroHP = nil :: ((Player) -> ())?

function PlayerState.damage(player: Player, amount: number, source: string?)
	local state = states[player]
	if not state or state.god or state.downed or state.bledOut or Runs.modOf(player, "Pause").active() then
		return
	end
	if state.invulnUntil > Workspace:GetServerTimeNow() then
		return
	end
	-- Brief 9 TOUGHNESS: less damage taken, before armor soaks it.
	amount *= math.max(0.05, 1 - state.skillMods.damageTakenPct)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
	end
	-- Brief 8: nothing reaches a player in the hub; in the range a debug enemy can hurt you but never down you.
	if Runs.slotOf(player).isHub then
		if state.inRange then
			hum.Health = math.max(1, hum.Health - amount)
			Remotes.Juice:FireClient(player, "PlayerHit", { amount = amount, source = source })
		end
		return
	end
	-- Round 25: ARMOR soaks the hit first; whatever is left reaches HP. Any hit restarts the armor refill clock.
	state.lastHurtAt = Workspace:GetServerTimeNow()
	if state.armor > 0 then
		local soak = math.min(state.armor, amount)
		state.armor -= soak
		amount -= soak
		state.dirty = true
		if amount <= 0 then
			Remotes.Juice:FireClient(player, "PlayerHit", { amount = soak, source = source, armor = true })
			return
		end
	end
	local newHP = hum.Health - amount
	Remotes.Juice:FireClient(player, "PlayerHit", { amount = amount, source = source })
	if newHP <= 0 then
		local hook = PlayerState.onZeroHP
		if hook then
			hum.Health = 1
			hook(player)
		else
			hum.Health = hum.MaxHealth
			Log.event("Player", "%s reached 0 HP with no downed handler: health reset", player.Name)
		end
	else
		hum.Health = newHP
	end
end

function PlayerState.inParty(state: State): boolean
	return not Runs.slotOf(state.player).isHub
end

-- An ability's cooldown for this player: the Config base less ABILITY COOLDOWN (capped in Stats).
function PlayerState.abilityCooldown(state: State, abilityId: string): number
	local base = Config.AbilityCooldown[abilityId] or 10
	-- Brief 9 COOLDOWN nodes take their share off the base first; the run's ABILITY COOLDOWN (capped) then applies.
	local skill = math.max(0.05, 1 - state.skillMods.cooldownPct)
	return base * skill * math.max(0.05, 1 - PlayerState.computed(state).abilityCdr)
end

-- ABILITY POWER: ability damage, heal and placeable HP multiplier.
function PlayerState.abilityPower(state: State): number
	return PlayerState.computed(state).abilityPower
end

-- Charges (DOUBLE DOWN, INITIATE II: Frag and Claymore hold MasteryExtraCharges more).
function PlayerState.maxCharges(state: State, abilityId: string): number
	if (abilityId == "frag" or abilityId == "claymore") and PlayerState.passive(state, "INITIATE", 2) then
		return 1 + Config.MasteryExtraCharges
	end
	return 1
end

function PlayerState.chargesLeft(state: State, abilityId: string): number
	local c = state.charges[abilityId]
	return if c == nil then PlayerState.maxCharges(state, abilityId) else c
end

local function abilityView(state: State): { [string]: Types.Ability }
	local out: { [string]: Types.Ability } = {}
	local class = Classes.ById[PlayerState.classOf(state)] or Classes.ById[Classes.Default]
	for _, a in class.abilities do
		local charges = PlayerState.chargesLeft(state, a.id)
		local max = PlayerState.maxCharges(state, a.id)
		out[a.id] = {
			cooldown = PlayerState.abilityCooldown(state, a.id),
			-- The cooldown runs from the use: the sweep shows it whenever a charge is missing (lighter while one is
			-- still in hand).
			cooldownEndsAt = if charges < max then state.cooldowns[a.id] or 0 else 0,
			activeUntil = if state.buffId == a.id then state.buffUntil else state.abilityActive[a.id],
			charges = charges,
			maxCharges = PlayerState.maxCharges(state, a.id),
		}
	end
	return out
end

-- Round 21: the slot that isn't in your hands, as the HUD chip draws it (nil = empty slot).
function PlayerState.offhandView(state: State): Types.OffhandView?
	local o = state.offhand
	local w = o and Weapons.ById[o.weaponId]
	if not o or not w then
		return nil
	end
	local wrapId = PlayerState.wrapOf(state, o.weaponId)
	local wrap = wrapId and Wraps.ById[wrapId]
	return {
		weaponId = w.id,
		displayName = w.displayName,
		archetype = w.archetype,
		rarity = o.rarity,
		rarityName = Rarity.name(o.rarity),
		level = o.level,
		wrapColor = if wrap then wrap.color else nil,
	}
end

-- Modules that sit above PlayerState add their own per-player views here (dealer, pause): key -> fn(player).
PlayerState.syncHooks = {} :: { [string]: (Player) -> any }

function PlayerState.buildSync(state: State): Types.Sync
	local st = PlayerState.computed(state)
	local w = Weapons.ById[state.held.weaponId]
	local total = 0
	for _, item in state.upgrades do
		total += item.count
	end
	local inParty = PlayerState.inParty(state)
	local World = Runs.worldOf(state.player) -- brief 8: the player's own run (the hub slot's when not in one)
	local levelRate = Weapons.levelRateMult(state.held.level)
	local wrapId = PlayerState.wrapOf(state, state.held.weaponId)
	local wrap = wrapId and Wraps.ById[wrapId]
	local sync = {
		wave = World.wave,
		-- Players outside the party only ever see the hub, whatever the arena is doing.
		waveState = if inParty or not World.inRunCycle() then World.state else "Hub",
		inParty = inParty,
		inRange = state.inRange, -- brief 8: the range arms you (HUD.setMode("range"))
		intermissionEndsAt = World.intermissionEndsAt,
		heat = World.heat,
		cash = state.cash,
		gold = state.gold,
		banked = World.banked,
		bags = state.bags,
		boss = World.bossView,
		roster = if inParty then World.roster else nil,
		maxHP = st.maxHP,
		armor = math.floor(state.armor), -- Round 25 ARMOR (the HP bar's overlay)
		maxArmor = state.armorMax,
		dmgPct = PlayerState.damagePct(state), -- the floor-gun tags show guns at your own damage upgrades
		skillMods = state.skillMods, -- brief 9: the armed Skill Web (floor-gun tags add its weapon bonus too)
		held = {
			weaponId = w.id,
			displayName = w.displayName,
			archetype = w.archetype,
			rarity = state.held.rarity,
			rarityName = Rarity.name(state.held.rarity),
			level = state.held.level,
			dmg = st.damage,
			dps = Stats.weaponDps(w.id, state.held.rarity, state.upgrades, state.held.level, state.skillMods),
			fireRate = st.fireRate,
			magSize = st.magSize,
			reloadTime = st.reloadTime,
			spread = w.spread * st.spreadMult * (if state.downed then Config.DownedSpreadMult else 1),
			pellets = w.pellets,
			auto = w.auto,
			shellReload = w.shellReload,
			burst = w.burst,
			burstDelay = w.burstDelay,
			displayRate = Weapons.effectiveRate(w, if w.fireRate > 0 then st.fireRate / w.fireRate else 1),
			builtInPierce = Weapons.builtInPierce(w, state.held.rarity),
			uid = state.held.uid,
			mag = state.held.mag,
			sidearm = state.stowed ~= nil,
			wrapColor = if wrap then wrap.color else nil,
			levelRateMult = levelRate,
		},
		-- Round 21: the other loadout slot (key 1 switches; the HUD's second chip).
		offhand = PlayerState.offhandView(state),
		activeSlot = state.activeSlot,
		stats = st,
		prices = {
			upgrade = Stats.upgradePrice(state.upgradesBought),
		},
		tracker = { order = state.upgradeOrder, items = state.upgrades, total = total },
		openPick3 = state.openPick3,
		god = state.god,
		noCooldowns = state.noCooldowns,
		abilities = abilityView(state),
		classId = PlayerState.classOf(state),
		profile = state.profile,
		spawnsPaused = World.spawnsPaused,
		debugEnabled = Config.DebugEnabled or RunService:IsStudio(),
		playerCount = #Players:GetPlayers(),
		enemiesLeft = World.enemiesLeft,
		waveStartedAt = World.waveStartedAt,
		skipVotes = World.skipVoteCount(),
		skipNeeded = World.skipNeeded(),
		myVote = World.skipVotes[state.player.UserId] == true,
		autoSkip = World.autoSkip[state.player.UserId] == true,
		minigameTier = Runs.hub.World.minigameTier,
		downed = state.downed,
		bledOut = state.bledOut,
		bleedEndsAt = state.bleedEndsAt,
		selfRevives = state.selfRevives,
		reviveAllUsed = state.reviveAllUsed,
	} :: any
	for key, fn in PlayerState.syncHooks do
		sync[key] = fn(state.player)
	end
	return sync
end

-- Collision groups: enemies never body-block players (or each other) unless Config says so.
function PlayerState.setupCollisionGroups()
	for _, name in { "Player", "Enemy", "Corpse", "Structure" } do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	PhysicsService:CollisionGroupSetCollidable("Enemy", "Player", Config.EnemyCollidesWithPlayers)
	PhysicsService:CollisionGroupSetCollidable("Enemy", "Enemy", Config.EnemyCollidesWithPlayers)
	-- Ragdolled bodies rest on the floor and walls only: never under a player's feet or in an enemy's way.
	PhysicsService:CollisionGroupSetCollidable("Corpse", "Player", false)
	PhysicsService:CollisionGroupSetCollidable("Corpse", "Enemy", false)
	PhysicsService:CollisionGroupSetCollidable("Corpse", "Corpse", false)
	-- Placeables (turrets, barricades, oil drums): they block enemies, never players.
	PhysicsService:CollisionGroupSetCollidable("Structure", "Player", false)
end

local function onCharacter(player: Player, char: Model)
	local state = PlayerState.get(player)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	for _, p in char:GetDescendants() do
		if p:IsA("BasePart") then
			p.CollisionGroup = "Player"
		end
	end
	char.DescendantAdded:Connect(function(p)
		if p:IsA("BasePart") then
			p.CollisionGroup = "Player"
		elseif p:IsA("Accessory") then
			task.defer(function()
				if p.Parent and (STRIPPED[p.AccessoryType] or p.AccessoryType == Enum.AccessoryType.Unknown) then
					p:Destroy()
				end
			end)
		end
	end)
	stripAccessories(char)
	-- Kill the default regen script; HP Regen is an upgrade stat here.
	local health = char:FindFirstChild("Health")
	if health then
		health:Destroy()
	end
	char.ChildAdded:Connect(function(c)
		if c.Name == "Health" and c:IsA("Script") then
			c:Destroy()
		end
	end)
	hum.MaxHealth = Config.PlayerMaxHP
	hum.Health = Config.PlayerMaxHP
	PlayerState.applyCharacterStats(state)
	task.spawn(function()
		char:WaitForChild("RightHand", 5)
		char:WaitForChild("Head", 5)
		PlayerState.refreshHeldVisual(state)
		PlayerState.applyMask(state)
	end)
	local hook = PlayerState.spawnCFrame
	local cf = state.pendingSpawnCFrame or (if hook then hook(player) else nil)
	state.pendingSpawnCFrame = nil
	if cf then
		task.spawn(function()
			if char:WaitForChild("HumanoidRootPart", 5) then
				char:PivotTo(cf)
			end
		end)
	end
	state.dirty = true
end

function PlayerState.init()
	PlayerState.setupCollisionGroups()
	-- (Brief 8: the pause's freeze hook is installed per run slot by Run/Main.)
	-- Characters are loaded by hand: a bled-out player has none until revived or the run ends, and the
	-- first character waits for the profile so the starter, mask and wrap are right from the first frame.
	Players.CharacterAutoLoads = false
	Profiles.Loaded:Connect(function(player: Player)
		local state = states[player]
		if state then
			PlayerState.applyProfile(state)
		end
	end)
	local function onPlayer(player: Player)
		local state = PlayerState.get(player)
		player.CharacterAdded:Connect(function(char)
			onCharacter(player, char)
			local hum = char:WaitForChild("Humanoid") :: Humanoid
			hum.Died:Connect(function()
				-- Falls and other oddities (damage never kills): respawn unless bled out on purpose.
				task.delay(3, function()
					if player.Parent and not state.bledOut and player.Character == char then
						player:LoadCharacter()
					end
				end)
			end)
		end)
		task.spawn(function()
			Profiles.waitFor(player)
			if not player.Parent then
				return
			end
			PlayerState.applyProfile(state)
			if player.Character then
				onCharacter(player, player.Character)
			else
				player:LoadCharacter()
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	local acc = 0
	local forceAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		-- Regen
		for player, state in states do
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if
				hum
				and not state.downed
				and hum.Health > 0
				and hum.Health < hum.MaxHealth
				and not Runs.modOf(player, "Pause").active()
			then
				local st = PlayerState.computed(state)
				hum.Health = math.min(hum.MaxHealth, hum.Health + st.hpRegen * dt)
			end
			-- Round 25: ARMOR. A new card fills its points at once; spent armor refills at ArmorRegenPctPerSec of
			-- the total once ArmorRegenDelay passes without a hit.
			local up = state.upgrades.Armor
			-- Brief 9 ARMOR nodes add flat points (full at the run start, like a new card).
			local maxArmor = math.max(0, (if up then up.pct else 0) + state.skillMods.armorFlat)
			if maxArmor ~= state.armorMax then
				if maxArmor > state.armorMax then
					state.armor += maxArmor - state.armorMax
				end
				state.armorMax = maxArmor
				state.armor = math.clamp(state.armor, 0, maxArmor)
				state.dirty = true
			end
			if
				hum
				and hum.Health > 0
				and not state.downed
				and state.armor < maxArmor
				and Workspace:GetServerTimeNow() - state.lastHurtAt >= Config.ArmorRegenDelay * math.max(
					0,
					1 - state.skillMods.armorDelayPct
				)
				and not Runs.modOf(player, "Pause").active()
			then
				local before = math.floor(state.armor)
				state.armor = math.min(maxArmor, state.armor + maxArmor * Config.ArmorRegenPctPerSec * dt)
				if math.floor(state.armor) ~= before then
					state.dirty = true
				end
			end
		end
		-- Flush dirty syncs at most 10x per second.
		acc += dt
		forceAcc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		-- A full resend every 2s covers a client that loaded after its first sync.
		-- Brief 8: a run's heat / pause / dealer change resends its own party only.
		local force = forceAcc >= 2
		if force then
			forceAcc = 0
		end
		local slotForced: { [any]: boolean } = {}
		for _, s in Runs.allSlots() do
			local w = s.World
			if w.heatDirty or w.pauseDirty or w.dealerDirty then
				w.heatDirty = false
				w.pauseDirty = false
				w.dealerDirty = false
				slotForced[s] = true
			end
		end
		for player, state in states do
			if state.dirty or force or (next(slotForced) ~= nil and slotForced[Runs.slotOf(player)]) then
				state.dirty = false
				Remotes.StateSync:FireClient(player, PlayerState.buildSync(state))
			end
		end
	end)
end

return PlayerState
