--!strict
-- Brief 6: the battle pass. profile.pass = { season, level, xp, tier, claimed = { ["L7"] = { free, p1, p2 } } }.
-- One track of Config.PassLevels levels on the season grid (PassSeason.lua); a level's cells are claimable once it
-- is reached and its lane's tier is owned (FREE 0, PREMIUM 1, PREMIUM+ 2), so buying a tier unlocks that lane for
-- every level already reached. Pass XP: PassXpPerWave per wave cleared + PassXpPerBoss per boss kill at the
-- summary, plus Job rewards; overflow carries, and past the last level every PassXpPerLevel pays PassOverflowGold.
-- Level skips (PassSkipPrice each) work at any tier. Season end (the fake clock): unclaimed cells of owned lanes
-- auto-claim, a SEASON OVER sheet waits for the next pass open, and the next season's grid loads.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Clock = require(Shared.Clock)
local PassSeason = require(Shared.PassSeason)
local Remotes = require(Shared.Remotes)
local Profiles = require(script.Parent.Profiles)
local PlayerState = require(script.Parent.PlayerState)
local Purchases = require(script.Parent.Purchases)
local Grants = require(script.Parent.Grants)
local Shop = require(script.Parent.Shop)
local Log = require(script.Parent.Log)

local Pass = {}

local function key(level: number): string
	return "L" .. level
end

local function season(profile: Profiles.Profile): PassSeason.Season
	return PassSeason.forNumber(profile.pass.season)
end

local function claimable(profile: Profiles.Profile, level: number, lane: string): boolean
	local p = profile.pass
	if level < 1 or level > math.min(p.level, Config.PassLevels) then
		return false
	end
	if (PassSeason.LaneTier[lane] or 9) > p.tier then
		return false
	end
	local c = p.claimed[key(level)]
	return not (c and (c :: any)[lane])
end

local function markClaimed(profile: Profiles.Profile, level: number, lane: string)
	local k = key(level)
	local c = profile.pass.claimed[k] or {}
	profile.pass.claimed[k] = c;
	(c :: any)[lane] = true
end

local function claimOne(
	player: Player,
	profile: Profiles.Profile,
	level: number,
	lane: string,
	source: string
): Grants.Result?
	if not claimable(profile, level, lane) then
		return nil
	end
	local cell = PassSeason.cell(season(profile), level, lane)
	if not cell then
		return nil
	end
	markClaimed(profile, level, lane)
	return Grants.apply(
		player,
		cell,
		{ source = string.format("%s S%d L%d %s", source, profile.pass.season, level, lane) }
	)
end

-- Every claimable cell, level order then lane order.
local function claimAll(player: Player, profile: Profiles.Profile, source: string): { Grants.Result }
	local out = {}
	for level = 1, math.min(profile.pass.level, Config.PassLevels) do
		for _, lane in PassSeason.Lanes do
			local r = claimOne(player, profile, level, lane, source)
			if r then
				table.insert(out, r)
			end
		end
	end
	return out
end

-- The season the fake clock is in; a later one ends the old season first.
function Pass.normalize(player: Player)
	local profile = Profiles.get(player)
	if not profile then
		return
	end
	local now = Clock.fake(os.time(), profile)
	local current = PassSeason.numberAt(now)
	local p = profile.pass
	if p.season == 0 then
		p.season = current
		Profiles.markDirty(player)
		return
	end
	if p.season >= current then
		return
	end
	local old = p.season
	local oldName = season(profile).name
	local auto = claimAll(player, profile, "season end")
	p.seasonOver = { season = old, name = oldName, autoClaimed = #auto, level = p.level }
	p.season = current
	p.level = 1
	p.xp = 0
	p.tier = 0
	p.claimed = {}
	Profiles.markDirty(player)
	PlayerState.get(player).dirty = true
	Log.event(
		"Pass",
		"%s: season %d over at LV %d, %d cells auto-claimed; season %d loaded",
		player.Name,
		old,
		p.seasonOver.level,
		#auto,
		current
	)
end

-- Pass XP (runs, Jobs, debug). Levels as it goes; past the last level every PassXpPerLevel pays PassOverflowGold.
function Pass.addXp(player: Player, amount: number, source: string): any
	local profile = Profiles.get(player)
	if not profile or amount <= 0 then
		return nil
	end
	Pass.normalize(player)
	local p = profile.pass
	local from = { level = p.level, xp = p.xp }
	p.xp += math.floor(amount)
	local levelUps = {}
	local overflowGold = 0
	while p.xp >= Config.PassXpPerLevel do
		p.xp -= Config.PassXpPerLevel
		if p.level < Config.PassLevels then
			p.level += 1
			table.insert(levelUps, p.level)
		else
			overflowGold += Config.PassOverflowGold
		end
	end
	if overflowGold > 0 then
		Grants.apply(player, { kind = "gold", amount = overflowGold }, { source = "pass overflow" })
	end
	Profiles.markDirty(player)
	PlayerState.get(player).dirty = true
	Log.event(
		"Pass",
		"%s +%d pass XP (%s): LV %d (%d/%d)%s%s",
		player.Name,
		amount,
		source,
		p.level,
		p.xp,
		Config.PassXpPerLevel,
		if #levelUps > 0 then " · level up to " .. table.concat(levelUps, ", ") else "",
		if overflowGold > 0 then string.format(" · +%d overflow gold", overflowGold) else ""
	)
	local award = {
		gained = math.floor(amount),
		fromLevel = from.level,
		fromXp = from.xp,
		toLevel = p.level,
		toXp = p.xp,
		levelUps = levelUps,
		overflowGold = overflowGold,
		perLevel = Config.PassXpPerLevel,
		maxLevel = Config.PassLevels,
	}
	Remotes.Juice:FireClient(player, "PassXp", award)
	return award
end

-- The summary's pass XP for a run.
function Pass.runXp(wavesCleared: number, bossKills: number): number
	return Config.PassXpPerWave * wavesCleared + Config.PassXpPerBoss * bossKills
end

function Pass.claimableCount(profile: Profiles.Profile): number
	local n = 0
	for level = 1, math.min(profile.pass.level, Config.PassLevels) do
		for _, lane in PassSeason.Lanes do
			if claimable(profile, level, lane) then
				n += 1
			end
		end
	end
	return n
end

------------------------------------------------------------------ Purchases
Purchases.register("pass", {
	check = function(player, profile, product)
		Pass.normalize(player)
		if profile.pass.tier >= (product.tier or 1) then
			return "You already have this tier"
		end
		return nil
	end,
	grant = function(player, profile, product)
		profile.pass.tier = product.tier or 1
		Profiles.markDirty(player)
		Log.event(
			"Pass",
			"%s bought %s: %d cells claimable now (retroactive)",
			player.Name,
			PassSeason.LaneName[if profile.pass.tier >= 2 then "p2" else "p1"],
			Pass.claimableCount(profile)
		)
		return { tier = profile.pass.tier, claimable = Pass.claimableCount(profile) }
	end,
})

Purchases.register("pass_skip", {
	check = function(player, profile)
		Pass.normalize(player)
		if profile.pass.level >= Config.PassLevels then
			return "Already at the last level"
		end
		return nil
	end,
	grant = function(player, profile, product)
		local before = profile.pass.level
		profile.pass.level = math.min(Config.PassLevels, before + (product.count or 1))
		Profiles.markDirty(player)
		Log.event("Pass", "%s skipped LV %d -> %d", player.Name, before, profile.pass.level)
		Remotes.Juice:FireClient(player, "PassXp", {
			gained = 0,
			fromLevel = before,
			fromXp = profile.pass.xp,
			toLevel = profile.pass.level,
			toXp = profile.pass.xp,
			levelUps = {},
			skip = true,
			perLevel = Config.PassXpPerLevel,
			maxLevel = Config.PassLevels,
		})
		return { from = before, to = profile.pass.level }
	end,
})

------------------------------------------------------------------ Shop actions
Shop.register("passClaim", function(player, profile, args)
	Pass.normalize(player)
	local level = if typeof(args) == "table" then math.floor(tonumber(args.level) or 0) else 0
	local lane = if typeof(args) == "table" then tostring(args.lane) else ""
	local r = claimOne(player, profile, level, lane, "claim")
	if not r then
		return { ok = false, reason = "Not claimable" }
	end
	return { ok = true, data = { results = { r } } }
end)

Shop.register("passClaimAll", function(player, profile)
	Pass.normalize(player)
	local results = claimAll(player, profile, "claim all")
	if #results == 0 then
		return { ok = false, reason = "Nothing to claim" }
	end
	return { ok = true, data = { results = results } }
end)

-- The SEASON OVER sheet was seen.
Shop.register("passSeen", function(_player, profile)
	profile.pass.seasonOver = nil
	return { ok = true }
end)

-- Opening the scene: make sure the season is current (a fake-clock jump may have ended one).
Shop.register("passOpen", function(player)
	Pass.normalize(player)
	return { ok = true }
end)

------------------------------------------------------------------ Debug
function Pass.advanceDay(player: Player, days: number)
	local profile = Profiles.get(player)
	if not profile then
		return
	end
	profile.clockOffset += days * 86400
	Profiles.markDirty(player)
	PlayerState.get(player).dirty = true
	Log.event("Clock", "%s fake clock +%dd (offset %dd)", player.Name, days, profile.clockOffset // 86400)
	Pass.normalize(player)
end

function Pass.init()
	Grants.passXpHook = function(player: Player, amount: number, source: string)
		Pass.addXp(player, amount, source)
	end
	Profiles.Loaded:Connect(function(player: Player)
		task.defer(Pass.normalize, player)
	end)
	-- The fake clock can cross a season boundary mid-session.
	task.spawn(function()
		while true do
			task.wait(10)
			for _, p in Players:GetPlayers() do
				Pass.normalize(p)
			end
		end
	end)
end

return Pass
