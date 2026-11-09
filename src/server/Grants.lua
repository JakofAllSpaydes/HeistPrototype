--!strict
-- Brief 6: applies a Rewards.Reward to a player's profile. Bundles, the pass, VIP, Jobs and crates all grant through
-- here, so the Armory, Crew, Locker and Gold reflect a grant on the next sync. Items already owned either skip (a
-- bundle: its price already left them out) or convert (crates, the pass): Gold by rarity plus mastery XP for that
-- item (a mask's mastery goes to the equipped class, since masks have none of their own).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Rewards = require(Shared.Rewards)
local Weapons = require(Shared.Weapons)
local Masks = require(Shared.Masks)
local Wraps = require(Shared.Wraps)
local Emotes = require(Shared.Emotes)
local Classes = require(Shared.Classes)
local Crates = require(Shared.Crates)
local Profiles = require(script.Parent.Profiles)
local PlayerState = require(script.Parent.PlayerState)
local Runs = require(script.Parent.Runs)
local Boosts = require(script.Parent.Boosts)
local Progression = require(script.Parent.Progression)
local Log = require(script.Parent.Log)

export type Result = {
	kind: string,
	id: string?,
	amount: number?,
	sec: number?,
	name: string,
	rarity: number,
	new: boolean, -- an item that was not owned
	dupe: boolean, -- an owned item that converted (or was skipped)
	gold: number, -- dupe Gold
	mastery: number, -- dupe mastery XP
	skipped: boolean,
}

export type Opts = {
	source: string, -- for the log ("bundle_starter", "pass L7", "crate arms")
	owned: string?, -- "skip" (bundles) | "convert" (default)
	wrapOn: string?, -- a wrap goes straight onto this weapon when it is owned
	deferMastery: { any }?, -- mastery tier-up cards collect here instead of firing (crates play them after the reveal)
}

local Grants = {}

-- Installed by Pass.init (Pass grants through here, so it cannot be required back).
Grants.passXpHook = nil :: ((Player, number, string) -> ())?

local function owned(profile: Profiles.Profile, r: Rewards.Reward): boolean
	return Rewards.owned(profile, r)
end

local function giveItem(player: Player, profile: Profiles.Profile, r: Rewards.Reward, opts: Opts)
	local id = r.id or ""
	if r.kind == "weapon" and Weapons.ById[id] then
		profile.weapons[id] = profile.weapons[id] or { level = 0 }
	elseif r.kind == "mask" and Masks.ById[id] then
		profile.masks.owned[id] = true
	elseif r.kind == "wrap" and Wraps.ById[id] then
		local target = r.on or opts.wrapOn
		if Wraps.perGun(Wraps.ById[id]) then
			-- Round 30d: a shop wrap is owned per gun: on the named gun, else (no gun named) on every gun owned.
			if target and profile.weapons[target] then
				profile.wraps.owned[Wraps.key(target, id)] = true
			else
				for weaponId in profile.weapons do
					profile.wraps.owned[Wraps.key(weaponId, id)] = true
				end
			end
		else
			profile.wraps.owned[id] = true
		end
		local entry = target and profile.weapons[target]
		-- Round 30d: a crate's wrap (r.on) goes on its gun only when that gun wears none; wrapOn always applies.
		if entry and (opts.wrapOn ~= nil or (entry :: any).wrap == nil) then
			entry.wrap = id
			local state = PlayerState.get(player)
			if state.held.weaponId == target then
				PlayerState.refreshHeldVisual(state)
			end
		end
	elseif r.kind == "emote" and Emotes.ById[id] then
		profile.emotes.owned[id] = true
	elseif r.kind == "class" and Classes.ById[id] then
		profile.classes.owned[id] = true
	end
end

function Grants.apply(player: Player, r: Rewards.Reward, opts: Opts): Result
	local profile = Profiles.get(player)
	local res: Result = {
		kind = r.kind,
		id = r.id,
		amount = r.amount,
		sec = r.sec,
		name = Rewards.name(r),
		rarity = Rewards.rarity(r),
		new = false,
		dupe = false,
		gold = 0,
		mastery = 0,
		skipped = false,
	}
	if not profile then
		res.skipped = true
		return res
	end
	local n = r.amount or 0
	if Rewards.isItem(r) then
		if owned(profile, r) then
			res.dupe = true
			if opts.owned == "skip" then
				res.skipped = true
			else
				local tier = math.clamp(res.rarity, 1, 5)
				res.gold = Config.DupeGoldByTier[tier] or 0
				res.mastery = Config.DupeMasteryByTier[tier] or 0
				profile.gold += res.gold
				if r.kind == "weapon" and r.id then
					Runs.modOf(player, "Mastery").grant(player, "weapon", r.id, res.mastery, opts.deferMastery)
				else
					Runs.modOf(player, "Mastery")
						.grant(player, "class", profile.classes.equipped, res.mastery, opts.deferMastery)
				end
			end
		else
			giveItem(player, profile, r, opts)
			res.new = true
		end
	elseif r.kind == "gold" then
		profile.gold += n
	elseif r.kind == "tokens" then
		profile.reviveTokens += n
		Log.event("Tokens", "%s +%d from %s, now %d", player.Name, n, opts.source, profile.reviveTokens)
	elseif r.kind == "crate" and r.id and Crates.ById[r.id] then
		profile.crateOpens[r.id] = (profile.crateOpens[r.id] or 0) + n
	elseif r.kind == "boost" and r.id then
		Boosts.extend(player, r.id, r.sec or 0)
	elseif r.kind == "mastery" then
		-- On the starter gun and the equipped class.
		Runs.modOf(player, "Mastery").grant(player, "weapon", profile.starterWeaponId, n)
		Runs.modOf(player, "Mastery").grant(player, "class", profile.classes.equipped, n)
	elseif r.kind == "xp" then
		Progression.addXp(player, n)
	elseif r.kind == "passxp" then
		local hook = Grants.passXpHook
		if hook then
			hook(player, n, opts.source)
		end
	end
	Profiles.markDirty(player)
	PlayerState.get(player).dirty = true
	return res
end

function Grants.applyAll(player: Player, list: { Rewards.Reward }, opts: Opts): { Result }
	local out = {}
	for _, r in list do
		table.insert(out, Grants.apply(player, r, opts))
	end
	local names = {}
	for _, res in out do
		table.insert(
			names,
			res.name .. (if res.skipped then " (owned, skipped)" elseif res.dupe then " (dupe)" else "")
		)
	end
	Log.event("Grant", "%s from %s: %s", player.Name, opts.source, table.concat(names, ", "))
	return out
end

return Grants
