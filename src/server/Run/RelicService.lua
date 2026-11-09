--!strict
-- Brief 13: relics. When a gun crate finishes its reels (BigCrate.open), this decides whether a relic comes out of it:
--   1. a guarantee (Relics.guarantees: first_crate = Config.StarterRelic on any map, plus Config.RelicGuarantees)
--      the opener's profile has not had yet -> the party gets its relic and the opener's profile records its id, so
--      one added later reaches existing players on their next qualifying crate;
--   2. otherwise, on a map with relics, ONE roll per crate (not per gun) at Config.RelicDropChance among the map's
--      relics that at least one member does not own (none left to find = no roll). No pity, no luck source (not
--      LUCKY, not the Skill Web's LUCK, not Stats), no difficulty or wave factor. Debug Force relic drop makes the
--      next roll hit.
-- A hit unlocks the relic for every member at once (saved now, not at run end, so a disconnect cannot lose it);
-- members who already own it get Config.RelicDupeGold instead. Everyone sees the show (RelicFound: the beam, the
-- hang, the sting, the RELIC FOUND popup) and the summary carries a RELIC FOUND row.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Relics = require(Shared.Relics)
local Maps = require(Shared.Maps)
local Lines = require(Shared.CrewCall.Lines)
local Rarity = require(Shared.Rarity)
local MixedRoll = require(Shared.MixedRoll) -- Round 30d: the crate's bonus roll
local World = require(script.Parent.World)
local Remotes = require(script.Parent.SlotRemotes)
local Profiles = require(script.Parent.Parent.Profiles)
local Log = require(script.Parent.Parent.Log)

local RelicService = {}

RelicService.forceNext = false -- debug Force relic drop: the next roll hits
RelicService.found = {} :: { string } -- relic ids found this run (the summary's RELIC FOUND rows)

local function owns(player: Player, id: string): boolean
	local p = Profiles.get(player)
	return p ~= nil and p.relics.owned[id] == true
end

-- Unlock `id` for one player: "unlocked", or "dupe" (owned already: RelicDupeGold instead), or "none" (no profile).
function RelicService.grant(player: Player, id: string): string
	local p = Profiles.get(player)
	if not p or not Relics.ById[id] then
		return "none"
	end
	if p.relics.owned[id] then
		Profiles.addGold(player, Config.RelicDupeGold, "relic dupe " .. id)
		Log.event("Relic", "dupe %s %s +%dG", player.Name, id, Config.RelicDupeGold)
		return "dupe"
	end
	p.relics.owned[id] = true
	local row = Relics.ById[id]
	if row.kind == "mask" then
		p.masks.owned[id] = true -- equips from the Avatar booth like any mask
	end
	-- (Round 30d: other relic kinds unlock through their own owner here when the first one lands.)
	Profiles.markDirty(player)
	task.spawn(Profiles.save, player, "relic")
	Log.event("Relic", "unlock %s %s", player.Name, id)
	return "unlocked"
end

-- Which relic (if any) this crate drops for the party, and why. A guarantee the opener has not had yet (in list
-- order, on its map) comes first and is recorded on their profile; one per crate.
local function decide(opener: Player, crateId: string): (string?, string)
	local prof = Profiles.get(opener)
	if prof then
		for _, g in Relics.guarantees() do
			if prof.relics.guarantees[g.id] or not Relics.ById[g.relic] or (g.map ~= "" and g.map ~= World.map) then
				continue
			end
			prof.relics.guarantees[g.id] = true
			Profiles.markDirty(opener)
			task.spawn(Profiles.save, opener, "guarantee " .. g.id)
			Log.event("Relic", "roll %s hit %s (guarantee %s for %s)", crateId, g.relic, g.id, opener.Name)
			return g.relic, if g.id == "first_crate" then "first" else "guarantee"
		end
	end
	local members = World.partyPlayers()
	local candidates = {}
	for _, r in Relics.forMap(World.map) do
		for _, p in members do
			if not owns(p, r.id) then
				table.insert(candidates, r.id)
				break
			end
		end
	end
	if #candidates == 0 then
		return nil, "none left"
	end
	-- Round 30d: the crate's one bonus roll is the shared mixed roll (MixedRoll): a `relic` category at
	-- RelicDropChance against `none` for the rest. Other bonus kinds (a wrap, a mask, a weapon unlock) are further
	-- categories beside these; relics themselves can be any kind (Relics row `kind`).
	local forced = RelicService.forceNext
	RelicService.forceNext = false
	local chance = if forced then 1 else math.clamp(Config.RelicDropChance, 0, 1)
	local relicCategory: MixedRoll.Category = {
		id = "relic",
		weight = chance,
		rarities = { Rarity.Relic },
		has = function(_r: number): boolean
			return #candidates > 0
		end,
		pick = function(r: number, _rng: Random?): MixedRoll.Picked?
			local rid = candidates[math.random(#candidates)]
			local row = Relics.ById[rid]
			return { kind = if row then row.kind else "mask", id = rid, rarity = r }
		end,
	}
	local picked = MixedRoll.roll({
		categories = { relicCategory, MixedRoll.none(1 - chance, { Rarity.Relic }) },
		rarityWeights = {},
	})
	local hit = picked ~= nil
	local id = if picked then picked.id else nil
	Log.event(
		"Relic",
		"roll %s %s %s%s",
		crateId,
		if hit then "hit" else "miss",
		id or "-",
		if forced then " (forced)" else ""
	)
	return id, if forced then "forced" else "roll"
end

-- After a gun crate's last reel (BigCrate.open): the roll, the unlocks and the show. Returns how long the crate
-- should stay (the relic rises out of it and hangs over it), 0 when nothing dropped.
function RelicService.afterCrate(opener: Player, crateId: string, at: Vector3): number
	if not Config.RelicsEnabled or not World.inRun() then
		return 0
	end
	local id, why = decide(opener, crateId)
	if not id then
		return 0
	end
	local relic = Relics.ById[id]
	local results: { [string]: string } = {}
	for _, p in World.partyPlayers() do
		results[tostring(p.UserId)] = RelicService.grant(p, id)
	end
	table.insert(RelicService.found, id)
	local mapName = Maps.get(relic.map).name
	World.fireRun("RelicFound", {
		crateId = crateId,
		position = at,
		id = id,
		name = Relics.title(id),
		mapName = mapName,
		color = relic.color,
		accent = relic.accent,
		shape = relic.shape,
		results = results, -- userId -> "unlocked" | "dupe"
		dupeGold = Config.RelicDupeGold,
		riseSec = Config.RelicRiseSec,
		hangSec = Config.RelicHangSec,
		popupSec = Config.RelicPopupSec,
		starter = why == "first",
		by = opener.Name,
	})
	-- MARLOW's line and the toast once it has flown off the crate.
	task.delay(Config.RelicRiseSec + Config.RelicHangSec + Config.RelicPopupSec, function()
		World.fireRun("CrewLine", {
			kind = "legendary",
			crewLead = Lines.door.crewLead,
			typeLabel = Lines.relic.typeLabel,
			text = { string.format(Lines.relicFound, Relics.title(id)) },
			hold = Config.CallHoldSec,
		})
	end)
	for _, p in World.partyPlayers() do
		Remotes.Juice:FireClient(p, "Toast", { text = string.format(Lines.relic.toast, Relics.title(id)) })
	end
	return Config.RelicRiseSec + Config.RelicHangSec
end

-- Run start: nothing found yet.
function RelicService.resetRun()
	RelicService.found = {}
end

-- Debug Reset relics: no relic owned, every guarantee armed again (equipped relics go back to the plain mask).
function RelicService.reset(player: Player)
	local p = Profiles.get(player)
	if not p then
		return
	end
	for id in p.relics.owned do
		p.masks.owned[id] = nil
		if p.masks.equipped == id then
			p.masks.equipped = "default"
		end
	end
	p.relics.owned = {}
	p.relics.guarantees = {}
	Profiles.markDirty(player)
	Log.event("Relic", "%s reset relics", player.Name)
end

return RelicService
