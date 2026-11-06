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
local Classes = require(Shared.Classes)
local AbilityGrowth = require(Shared.AbilityGrowth)
local Stats = require(script.Parent.Stats)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
local Profiles = require(script.Parent.Profiles)
local Pause = require(script.Parent.Pause)

export type State = {
	player: Player,
	profile: Profiles.Profile?, -- nil until loaded
	cash: number,
	upgradesBought: number,
	upgrades: { [string]: Types.TrackerItem },
	upgradeOrder: { string },
	openPick3: { Types.Card }?,
	held: Types.Held,
	stowed: Types.Held?, -- the real gun while downed with the sidearm
	pityStreak: number,
	forcedRarity: number?,
	forceTradeoff: boolean,
	forceElement: boolean, -- debug: the next pick-3 holds an element card
	waveCash: number, -- cash earned since the last wave end (the income log)
	waveUpgrades: number, -- upgrades bought since the last wave end
	god: boolean,
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
	reviveProgress: number, -- 0..1 while a teammate holds the revive
	reviver: Player?,
	savedJump: { useJumpPower: boolean, jumpPower: number, jumpHeight: number }?,
	lastPosition: Vector3, -- where the character was when it bled out
	pendingSpawnCFrame: CFrame?, -- next LoadCharacter lands here
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
		stowed = nil,
		pityStreak = 0,
		forcedRarity = nil,
		forceTradeoff = false,
		forceElement = false,
		waveCash = 0,
		waveUpgrades = 0,
		god = false,
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
		reviveProgress = 0,
		reviver = nil,
		savedJump = nil,
		lastPosition = Vector3.zero,
		pendingSpawnCFrame = nil,
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
-- stim: fire rate, reload, move. stimshot: fire rate, reload (plus the heal on use). deadeye: damage, move, pierce.
function PlayerState.buffFor(state: State, id: string): Stats.Buffs
	local level = PlayerState.abilityLevel(state, id)
	local b: Stats.Buffs = { fireRateMult = 1, moveSpeedMult = 1, reloadSpeedMult = 1, damageMult = 1, pierceAdd = 0 }
	if id == "stim" then
		-- INITIATE's Adrenaline (the id stays "stim" for saved levels).
		b.fireRateMult = 1 + AbilityGrowth.at(id, "FireRatePct", (Config.AdrenalineFireRateMult - 1) * 100, level) / 100
		b.reloadSpeedMult = 1
			+ AbilityGrowth.at(id, "ReloadPct", (Config.AdrenalineReloadSpeedMult - 1) * 100, level) / 100
		b.moveSpeedMult = 1 + AbilityGrowth.at(id, "MovePct", (Config.AdrenalineMoveMult - 1) * 100, level) / 100
	elseif id == "stimshot" then
		b.fireRateMult = 1 + AbilityGrowth.at(id, "FireRatePct", (Config.StimShotFireRateMult - 1) * 100, level) / 100
		b.reloadSpeedMult = 1
			+ AbilityGrowth.at(id, "ReloadPct", (Config.StimShotReloadSpeedMult - 1) * 100, level) / 100
	elseif id == "deadeye" then
		b.damageMult = 1 + AbilityGrowth.at(id, "DmgPct", Config.DeadEyeDmgPct, level) / 100
		b.moveSpeedMult = 1 + AbilityGrowth.at(id, "SpeedPct", Config.DeadEyeSpeedPct, level) / 100
		-- Fractional pierce is real: 2.2 passes through two more enemies at full damage and a third at 20%.
		b.pierceAdd = AbilityGrowth.at(id, "Pierce", Config.DeadEyePierce, level)
	end
	return b
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
	if World.crewOverclockUntil > Workspace:GetServerTimeNow() and World.isInParty(state.player) then
		local b = buffs or { fireRateMult = 1, moveSpeedMult = 1, reloadSpeedMult = 1, damageMult = 1, pierceAdd = 0 }
		b.fireRateMult *= 1 + Config.CrewOverclockFireRatePct
		b.reloadSpeedMult *= 1 + Config.CrewOverclockReloadPct
		buffs = b
	end
	local st = Stats.compute(state.upgrades, state.held, buffs)
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
	return st
end

function PlayerState.damagePct(state: State): number
	local u = state.upgrades.Damage
	return if u then u.pct / 100 else 0
end

------------------------------------------------------------------ Character dressing
-- Held gun visual: a Part welded to the right hand so tracers have a muzzle. Body = rarity color,
-- grip = the equipped wrap (or dark).
function PlayerState.refreshHeldVisual(state: State)
	local char = state.player.Character
	if not char then
		return
	end
	local old = char:FindFirstChild("HeldGun")
	if old then
		old:Destroy()
	end
	local oldGrip = char:FindFirstChild("HeldGunWrap")
	if oldGrip then
		oldGrip:Destroy()
	end
	local hand = (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")) :: BasePart?
	if not hand then
		return
	end
	local gun = Instance.new("Part")
	gun.Name = "HeldGun"
	gun.Size = Vector3.new(0.35, 0.5, 1.6)
	gun.Color = Rarity.color(state.held.rarity)
	gun.Material = Enum.Material.Metal
	gun.CanCollide = false
	gun.CanQuery = false
	gun.CanTouch = false
	gun.Massless = true
	gun.CFrame = hand.CFrame * CFrame.new(0, -0.25, -0.9)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = gun
	weld.Parent = gun
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0, -0.8)
	muzzle.Parent = gun
	gun.Parent = char
	-- Wrappable part: the grip / stock band under the body.
	local wrapId = PlayerState.wrapOf(state, state.held.weaponId)
	local wrap = wrapId and Wraps.ById[wrapId]
	local grip = Instance.new("Part")
	grip.Name = "HeldGunWrap"
	grip.Size = Vector3.new(0.38, 0.22, 0.7)
	grip.Color = if wrap then Color3.fromHex(wrap.color) else Color3.fromRGB(40, 40, 46)
	grip.Material = if wrap then Enum.Material.SmoothPlastic else Enum.Material.Metal
	grip.CanCollide = false
	grip.CanQuery = false
	grip.CanTouch = false
	grip.Massless = true
	grip.CFrame = gun.CFrame * CFrame.new(0, -0.3, 0.3)
	local weld2 = Instance.new("WeldConstraint")
	weld2.Part0 = gun
	weld2.Part1 = grip
	weld2.Parent = grip
	grip.Parent = char
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
	if mask.shape == "none" then
		return
	end
	local part = Instance.new("Part")
	part.Name = "MaskPart"
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Color = Color3.fromHex(mask.color)
	if mask.shape == "visor" then
		part.Size = Vector3.new(1.3, 0.35, 0.3)
		part.Material = Enum.Material.Neon
		part.CFrame = head.CFrame * CFrame.new(0, 0.1, -0.55)
	else
		part.Size = Vector3.new(1.25, 0.5, 1.25)
		part.Material = Enum.Material.Fabric
		part.CFrame = head.CFrame * CFrame.new(0, -0.25, 0)
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = part
	weld.Parent = part
	part.Parent = char
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
	hum.WalkSpeed = if state.downed then Config.DownedWalkSpeed else st.moveSpeed
end

-- Installed by Hub: where a freshly loaded character goes (nil = the SpawnLocation).
PlayerState.spawnCFrame = nil :: ((Player) -> CFrame?)?

-- The profile arrived or changed its equips: starter, mask, wrap.
function PlayerState.applyProfile(state: State)
	state.profile = Profiles.get(state.player)
	state.held = PlayerState.starterHeld(state)
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

-- Installed by Downed: what happens at 0 HP. Without it health just resets.
PlayerState.onZeroHP = nil :: ((Player) -> ())?

function PlayerState.damage(player: Player, amount: number, source: string?)
	local state = states[player]
	if not state or state.god or state.downed or state.bledOut or Pause.active() then
		return
	end
	if state.invulnUntil > Workspace:GetServerTimeNow() then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
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
	return World.isInParty(state.player)
end

-- An ability's cooldown for this player: the Config base less ABILITY COOLDOWN (capped in Stats).
function PlayerState.abilityCooldown(state: State, abilityId: string): number
	local base = Config.AbilityCooldown[abilityId] or 10
	return base * math.max(0.05, 1 - PlayerState.computed(state).abilityCdr)
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
	local levelRate = Weapons.levelRateMult(state.held.level)
	local wrapId = PlayerState.wrapOf(state, state.held.weaponId)
	local wrap = wrapId and Wraps.ById[wrapId]
	local sync = {
		wave = World.wave,
		-- Players outside the party only ever see the hub, whatever the arena is doing.
		waveState = if inParty or not World.inRunCycle() then World.state else "Hub",
		inParty = inParty,
		intermissionEndsAt = World.intermissionEndsAt,
		heat = World.heat,
		cash = state.cash,
		gold = state.gold,
		banked = World.banked,
		bags = state.bags,
		boss = World.bossView,
		roster = if inParty then World.roster else nil,
		maxHP = st.maxHP,
		dmgPct = PlayerState.damagePct(state), -- the floor-gun tags show guns at your own damage upgrades
		held = {
			weaponId = w.id,
			displayName = w.displayName,
			archetype = w.archetype,
			rarity = state.held.rarity,
			rarityName = Rarity.name(state.held.rarity),
			level = state.held.level,
			dmg = st.damage,
			dps = Stats.weaponDps(w.id, state.held.rarity, state.upgrades, state.held.level),
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
		stats = st,
		prices = {
			upgrade = Stats.upgradePrice(state.upgradesBought),
		},
		tracker = { order = state.upgradeOrder, items = state.upgrades, total = total },
		openPick3 = state.openPick3,
		god = state.god,
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
		minigameTier = World.minigameTier,
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
	-- The pause: every party member's character is held where it stands, then let go.
	Pause.setFreezeHook(function(on: boolean)
		for _, p in World.partyPlayers() do
			local char = p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				root.Anchored = on
			end
			local s = states[p]
			if s and not on then
				PlayerState.applyCharacterStats(s)
			end
			if s then
				s.dirty = true
			end
		end
	end)
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
			if hum and not state.downed and not Pause.active() and hum.Health > 0 and hum.Health < hum.MaxHealth then
				local st = PlayerState.computed(state)
				hum.Health = math.min(hum.MaxHealth, hum.Health + st.hpRegen * dt)
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
		local force = forceAcc >= 2 or World.heatDirty or World.pauseDirty or World.dealerDirty
		if force then
			forceAcc = 0
			World.heatDirty = false
			World.pauseDirty = false
			World.dealerDirty = false
		end
		for player, state in states do
			if state.dirty or force then
				state.dirty = false
				Remotes.StateSync:FireClient(player, PlayerState.buildSync(state))
			end
		end
	end)
end

return PlayerState
