--!strict
-- Brief 6: paid crate rolls. Before any animation the server resolves every open: a rarity by the crate's weights
-- (Crates.odds, the table the odds panel shows), Epic or better forced when the pity counter reaches
-- Config.CratePity, then an item uniformly inside that rarity. Owned items convert (Grants: Gold by rarity plus
-- mastery XP). The profile is written up front; the client's CrateScene only plays the results back. LUCKY never
-- touches these odds.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Crates = require(Shared.Crates)
local Rarity = require(Shared.Rarity)
local Profiles = require(script.Parent.Profiles)
local PlayerState = require(script.Parent.PlayerState)
local Purchases = require(script.Parent.Purchases)
local Grants = require(script.Parent.Grants)
local Shop = require(script.Parent.Shop)
local Log = require(script.Parent.Log)

local CrateOpen = {}

-- Debug: the next open of this player's lands on this rarity (Force rarity on the debug panel).
CrateOpen.forced = {} :: { [Player]: number }

local function pick(odds: { number }): number
	local x = math.random()
	for r = 1, 5 do
		x -= odds[r]
		if x < 0 then
			return r
		end
	end
	for r = 5, 1, -1 do
		if odds[r] > 0 then
			return r
		end
	end
	return 1
end

export type Roll = {
	kind: string,
	id: string,
	rarity: number,
	name: string,
	new: boolean,
	dupe: boolean,
	gold: number,
	mastery: number,
	pity: boolean, -- the pity rule forced this one
	pityLeft: number, -- opens until the guarantee after this one
}

-- Rolls and grants `count` opens of a crate. Returns the results in order.
function CrateOpen.open(player: Player, crateId: string, count: number, source: string): { Roll }
	local crate = Crates.ById[crateId]
	local profile = Profiles.get(player)
	local out: { Roll } = {}
	if not crate or not profile then
		return out
	end
	for _ = 1, count do
		local since = profile.cratePity[crateId] or 0
		local pity = since >= Config.CratePity - 1
		local rarity: number
		local forced = CrateOpen.forced[player]
		if forced then
			CrateOpen.forced[player] = nil
			rarity = forced
			if #Crates.itemsAt(crate, rarity) == 0 then
				rarity = pick(Crates.odds(crate, 1))
			end
		elseif pity then
			rarity = pick(Crates.odds(crate, Rarity.Epic))
		else
			rarity = pick(Crates.odds(crate, 1))
		end
		local pool = Crates.itemsAt(crate, rarity)
		local id = pool[math.random(1, #pool)]
		profile.cratePity[crateId] = if rarity >= Rarity.Epic then 0 else since + 1
		local res = Grants.apply(player, { kind = crate.kind, id = id }, { source = "crate " .. crateId })
		table.insert(out, {
			kind = crate.kind,
			id = id,
			rarity = rarity,
			name = res.name,
			new = res.new,
			dupe = res.dupe,
			gold = res.gold,
			mastery = res.mastery,
			pity = pity and not forced,
			pityLeft = Config.CratePity - (profile.cratePity[crateId] or 0),
		})
	end
	Profiles.markDirty(player)
	PlayerState.get(player).dirty = true
	local parts = {}
	for _, r in out do
		table.insert(
			parts,
			string.format(
				"%s %s%s%s",
				Rarity.Letters[r.rarity],
				r.id,
				if r.dupe then " (dupe)" else "",
				if r.pity then " (pity)" else ""
			)
		)
	end
	Log.event(
		"Crate",
		"%s opened %s x%d (%s): %s · pity %d/%d",
		player.Name,
		crateId,
		count,
		source,
		table.concat(parts, ", "),
		profile.cratePity[crateId] or 0,
		Config.CratePity
	)
	return out
end

Purchases.register("crate", {
	check = function(_player, _profile, product)
		if not (product.crateId and Crates.ById[product.crateId]) then
			return "Unknown crate"
		end
		return nil
	end,
	grant = function(player, _profile, product)
		local results = CrateOpen.open(player, product.crateId :: string, product.count or 1, product.id)
		return { crateId = product.crateId, count = product.count, results = results }
	end,
})

-- Banked opens (bundles, the pass, debug): open them without a charge.
Shop.register("openCredits", function(player, profile, args)
	local crateId = if typeof(args) == "table" then tostring(args.crateId) else ""
	local want = if typeof(args) == "table" then math.floor(tonumber(args.count) or 1) else 1
	if not Crates.ById[crateId] then
		return { ok = false, reason = "Unknown crate" }
	end
	local have = profile.crateOpens[crateId] or 0
	local n = math.clamp(want, 1, math.max(have, 1))
	if have < 1 then
		return { ok = false, reason = "No free opens" }
	end
	profile.crateOpens[crateId] = have - n
	local results = CrateOpen.open(player, crateId, n, "free opens")
	return { ok = true, data = { crateId = crateId, count = n, results = results } }
end)

-- Debug: bank free opens.
function CrateOpen.grantCredits(player: Player, crateId: string, n: number)
	local profile = Profiles.get(player)
	if not profile or not Crates.ById[crateId] then
		return
	end
	profile.crateOpens[crateId] = (profile.crateOpens[crateId] or 0) + n
	Profiles.markDirty(player)
	PlayerState.get(player).dirty = true
	Log.event("Crate", "%s +%d free %s opens (debug)", player.Name, n, crateId)
end

return CrateOpen
