--!strict
-- Weapon and class mastery (brief 5). XP lands in profile.mastery the moment it is earned:
--   weapon XP: MasteryXpPerKill per kill with that gun (elites MasteryXpPerEliteKill, the boss MasteryXpPerBossKill),
--     tiers at WeaponMasteryTiers unlock the MasteryWrapIds wraps on that gun;
--   class XP: MasteryXpPerWave per wave played as that class (boss waves MasteryXpPerBossWave), tiers at
--     ClassMasteryTiers turn on the class passives (always on while the class is equipped).
-- A tier crossed mid-run applies at once (the passive is live from that moment, the wrap is owned) and the player
-- gets the MasteryUp celebration card (MasteryUI on the client); the summary lists the run's gains and tier-ups.
-- Stats, Combat, Abilities and Elements ask PlayerState.passive(state, classId, tier). This module also runs the
-- passives that hang off kills (ADRENALINE JUNKIE, BACKDRAFT) and installs the TORCH burn-rate hook.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)
local Classes = require(Shared.Classes)
local Remotes = require(script.Parent.SlotRemotes)
local MasteryCopy = require(Shared.MasteryCopy)
local PlayerState = require(script.Parent.Parent.PlayerState)
local Profiles = require(script.Parent.Parent.Profiles)
local UpgradeShop = require(script.Parent.UpgradeShop)
local Drones = require(script.Parent.Drones) -- brief 12: HIVE MIND
local Swarm = require(script.Parent.Swarm) -- brief 12: the wave-end swarm line
local Elements = require(script.Parent.Elements)
local World = require(script.Parent.World)
local Log = require(script.Parent.Parent.Log)
local AllyCallout = require(script.Parent.AllyCallout)

export type Line = { kind: string, id: string, name: string, gained: number }
export type TierUp = { kind: string, id: string, tier: number, text: string }
export type Award = { lines: { Line }, tierUps: { TierUp } }

local Mastery = {}

type Gains = { weapons: { [string]: number }, classes: { [string]: number }, tierUps: { TierUp } }
local gains: { [Player]: Gains } = {}

local function gainsOf(player: Player): Gains
	local g = gains[player]
	if not g then
		g = { weapons = {}, classes = {}, tierUps = {} }
		gains[player] = g
	end
	return g :: Gains
end

function Mastery.weaponXp(profile: Profiles.Profile?, weaponId: string): number
	local e = profile and profile.mastery.weapons[weaponId]
	return if e then e.xp else 0
end

function Mastery.classXp(profile: Profiles.Profile?, classId: string): number
	local e = profile and profile.mastery.classes[classId]
	return if e then e.xp else 0
end

local function nameOf(kind: string, id: string): string
	if kind == "weapon" then
		local w = Weapons.ById[id]
		return if w then string.upper(w.displayName) else id
	end
	local c = Classes.ById[id]
	return if c then c.displayName else id
end

-- A class tier the player now holds turns on right away for the class they are playing.
local function applyClassTier(state: PlayerState.State, classId: string, tier: number)
	if state.masteryClass ~= classId or tier <= state.masteryTier then
		return
	end
	state.masteryTier = tier
	PlayerState.registerPassives(state) -- brief 12
	if PlayerState.passive(state, "TORCH", 2) and World.inRun() then
		UpgradeShop.grantElement(state, "Incendiary") -- HOT ROUNDS
	end
	PlayerState.applyCharacterStats(state)
	state.dirty = true
end

-- Add XP to one weapon or class: the profile at once, the run tally, and the tier-up card for every tier crossed.
-- `deferred` (brief 6 crates): the tier-up cards are collected there instead of fired, so the client can play them
-- after the reveal that earned them.
local function add(player: Player, kind: string, id: string, xp: number, countForRun: boolean, deferred: { any }?)
	local profile = Profiles.get(player)
	if not profile or xp <= 0 then
		return
	end
	local book = if kind == "weapon" then profile.mastery.weapons else profile.mastery.classes
	local entry = book[id] or { xp = 0 }
	book[id] = entry
	local tiers = if kind == "weapon" then Config.WeaponMasteryTiers else Config.ClassMasteryTiers
	local before = MasteryCopy.tierOf(entry.xp, tiers)
	entry.xp += xp
	local after = MasteryCopy.tierOf(entry.xp, tiers)
	if kind == "weapon" then
		profile.stats.weaponMasteryXp += xp
	else
		profile.stats.classMasteryXp += xp
	end
	local g = gainsOf(player)
	if countForRun then
		local tally = if kind == "weapon" then g.weapons else g.classes
		tally[id] = (tally[id] or 0) + xp
	end
	Profiles.markDirty(player)
	for t = before + 1, after do
		local rewardName, rewardLine
		if kind == "weapon" then
			rewardName, rewardLine = MasteryCopy.weaponReward(t) .. " UNLOCKED", "Equip it on this gun in CUSTOMIZE"
		else
			rewardName, rewardLine = MasteryCopy.classReward(id, t)
		end
		local text = string.format("%s MASTERY %s · %s", nameOf(kind, id), MasteryCopy.Roman[t] or "", rewardName)
		table.insert(g.tierUps, { kind = kind, id = id, tier = t, text = text })
		local payload = {
			kind = kind,
			id = id,
			name = nameOf(kind, id),
			tier = t,
			maxTier = #tiers,
			roman = MasteryCopy.Roman[t] or tostring(t),
			reward = rewardName,
			line = rewardLine,
			wrap = if kind == "weapon" then Config.MasteryWrapIds[t] else nil,
		}
		if deferred then
			table.insert(deferred, payload)
		else
			Remotes.Juice:FireClient(player, "MasteryUp", payload)
		end
		Log.event("Mastery", "%s: %s", player.Name, text)
		if World.inRun() then
			AllyCallout.send(player, "masteryUp", nameOf(kind, id), MasteryCopy.Roman[t] or tostring(t))
		end
	end
	if kind == "class" and after > before then
		applyClassTier(PlayerState.get(player), id, after)
	end
end

-- Run start: snapshot the equipped class's tier for the passives; TORCH's HOT ROUNDS hands out INCENDIARY.
function Mastery.beginRun(players: { Player })
	table.clear(gains)
	for _, p in players do
		local state = PlayerState.get(p)
		local classId = PlayerState.classOf(state)
		state.masteryClass = classId
		state.masteryTier = MasteryCopy.classTier(Mastery.classXp(state.profile, classId))
		state.stimExtended = 0
		state.charges = {}
		PlayerState.registerPassives(state) -- brief 12: the stat-moving passives are resolver sources
		if PlayerState.passive(state, "TORCH", 2) then
			UpgradeShop.grantElement(state, "Incendiary")
		end
		state.dirty = true
		Log.event("Mastery", "%s runs %s at mastery %d", p.Name, classId, state.masteryTier)
		Log.event(
			"Class",
			"%s %s run by %s (mastery %d, kit %s)",
			string.lower(classId),
			Classes.displayName(classId),
			p.Name,
			state.masteryTier,
			table.concat(PlayerState.kitOf(state), " / ")
		)
	end
end

-- A kill with the held gun (Combat): weapon XP for that gun.
function Mastery.onGunKill(player: Player, weaponId: string, elite: boolean, boss: boolean)
	if not Weapons.ById[weaponId] then
		return
	end
	local xp = if boss
		then Config.MasteryXpPerBossKill
		elseif elite then Config.MasteryXpPerEliteKill
		else Config.MasteryXpPerKill
	add(player, "weapon", weaponId, xp, true)
end

-- Wave end: class XP for everyone who played it.
function Mastery.onWaveEnd(wave: number, players: { Player })
	Swarm.logWave(players) -- brief 12
	local xp = if World.isBossWave(wave) then Config.MasteryXpPerBossWave else Config.MasteryXpPerWave
	for _, p in players do
		local state = PlayerState.get(p)
		add(p, "class", state.masteryClass or PlayerState.classOf(state), xp, true)
	end
end

-- Any kill (Enemy.onDeath): ADRENALINE JUNKIE extends a running Adrenaline; BACKDRAFT (Round 29b) keeps a PYRO's
-- running Inferno burning (installed by Abilities: extendInferno(player, sec) -> did it extend).
Mastery.extendInferno = nil :: ((Player, number) -> boolean)?

function Mastery.onKill(model: Model, attacker: Player?)
	if attacker then
		local state = PlayerState.get(attacker)
		if
			PlayerState.passive(state, "INITIATE", 3)
			and state.buffId == "stim"
			and PlayerState.buffActive(state)
			and state.stimExtended < Config.StimExtendCap
		then
			local addSec = math.min(Config.StimExtendSec, Config.StimExtendCap - state.stimExtended)
			state.stimExtended += addSec
			state.buffUntil += addSec
			state.dirty = true
			Remotes.Juice:FireClient(attacker, "AbilityExtend", { id = "stim", sec = math.round(addSec * 10) / 10 })
		end
		-- HIVE MIND (SWARM III, brief 12): every kill the caster makes (their drones' included) keeps the swarm up.
		if PlayerState.passive(state, "SWARM", 3) then
			if Drones.extendOwner(attacker, Config.DroneKillExtendSec, Config.DroneKillExtendCap) > 0 then
				Remotes.Juice:FireClient(attacker, "AbilityExtend", { id = "drone", sec = Config.DroneKillExtendSec })
			end
		end
	end
	-- BACKDRAFT (PYRO III, Round 29b): every kill the PYRO makes, or a burning enemy of theirs dying, adds
	-- InfernoKillExtendSec to their running Inferno, uncapped: keep killing and it keeps burning.
	local pyro: Player? = nil
	if attacker and PlayerState.passive(PlayerState.get(attacker), "TORCH", 3) then
		pyro = attacker
	elseif Elements.isBurning(model) then
		local owner = Elements.burnOwnerOf(model)
		if owner and owner.Parent and PlayerState.passive(PlayerState.get(owner), "TORCH", 3) then
			pyro = owner
		end
	end
	local extend = Mastery.extendInferno
	if pyro and extend and extend(pyro, Config.InfernoKillExtendSec) then
		Remotes.Juice:FireClient(pyro, "AbilityExtend", { id = "inferno", sec = Config.InfernoKillExtendSec })
	end
end

-- Summary: the run's MASTERY line (guns by the most XP, then the class) and the tier-ups it crossed. The XP is
-- already in the profile.
function Mastery.award(player: Player): Award
	local out: Award = { lines = {}, tierUps = {} }
	local g = gains[player]
	if not g then
		return out
	end
	local list = {}
	for id, xp in g.weapons do
		table.insert(list, { id = id, xp = xp })
	end
	table.sort(list, function(a, b)
		return a.xp > b.xp
	end)
	for _, e in list do
		table.insert(out.lines, { kind = "weapon", id = e.id, name = nameOf("weapon", e.id), gained = e.xp })
	end
	for id, xp in g.classes do
		table.insert(out.lines, { kind = "class", id = id, name = nameOf("class", id), gained = xp })
	end
	out.tierUps = g.tierUps
	if #out.lines > 0 then
		local parts = {}
		for _, l in out.lines do
			table.insert(parts, string.format("%s +%d", l.name, l.gained))
		end
		Log.event("Mastery", "%s this run: %s", player.Name, table.concat(parts, " · "))
	end
	return out
end

-- Brief 6: mastery XP from a grant (crate dupes, the pass): straight into the profile, tier-ups pop as usual.
function Mastery.grant(player: Player, kind: string, id: string, xp: number, deferred: { any }?)
	add(player, kind, id, xp, false, deferred)
end

-- Debug: +amount mastery on the held (or stowed) gun and the equipped class. Tier-ups pop and apply like real ones.
function Mastery.debugAdd(player: Player, amount: number)
	local state = PlayerState.get(player)
	local weaponId = if state.stowed then state.stowed.weaponId else state.held.weaponId
	add(player, "weapon", weaponId, amount, false)
	add(player, "class", PlayerState.classOf(state), amount, false)
	state.dirty = true
	Log.event("Mastery", "debug +%d mastery: %s and %s", amount, weaponId, PlayerState.classOf(state))
end

function Mastery.init()
	-- TORCH I: your burns tick twice as fast.
	Elements.burnRateFor = function(owner: Player?): number
		if owner and owner.Parent and PlayerState.passive(PlayerState.get(owner), "TORCH", 1) then
			return Config.TorchBurnRateMult
		end
		return 1
	end
end

return Mastery
