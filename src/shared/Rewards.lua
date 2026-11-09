--!strict
-- Brief 6: one reward shape for everything bundles, the pass, VIP, Jobs and crates hand out, plus the copy and
-- rarity the store, the pass track and the reveals draw from. The server's Grants.lua applies them.
local Weapons = require(script.Parent.Weapons)
local Masks = require(script.Parent.Masks)
local Wraps = require(script.Parent.Wraps)
local Emotes = require(script.Parent.Emotes)
local Classes = require(script.Parent.Classes)
local BoostDefs = require(script.Parent.BoostDefs)

-- kind: gold | tokens | crate (id = crate id, amount = opens) | weapon | mask | wrap | emote | class |
-- boost (id = boost id, sec) | mastery (amount: XP on the starter gun and the equipped class) | xp | passxp
-- Round 30d: `on` = the gun a per-gun shop wrap is for (the daily crate names it).
export type Reward = { kind: string, id: string?, amount: number?, sec: number?, on: string? }

local Rewards = {}

local function int(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = ""
	local count = 0
	for i = #s, 1, -1 do
		out = string.sub(s, i, i) .. out
		count += 1
		if count % 3 == 0 and i > 1 then
			out = "," .. out
		end
	end
	return out
end
Rewards.int = int

function Rewards.duration(sec: number): string
	if sec >= 86400 and sec % 86400 == 0 then
		return string.format("%dD", sec // 86400)
	elseif sec >= 3600 then
		return string.format("%dH", math.round(sec / 3600))
	end
	return string.format("%dM", math.round(sec / 60))
end

-- Crate names are looked up lazily (Crates.lua requires this module's item tables).
local crateNames: { [string]: string } = { arms = "ARMS CRATE", mask = "MASK CRATE" }

function Rewards.isItem(r: Reward): boolean
	return r.kind == "weapon" or r.kind == "mask" or r.kind == "wrap" or r.kind == "emote" or r.kind == "class"
end

function Rewards.name(r: Reward): string
	local k, id, n = r.kind, r.id or "", r.amount or 0
	if k == "gold" then
		return int(n) .. " GOLD"
	elseif k == "tokens" then
		return int(n) .. (if n == 1 then " REVIVE TOKEN" else " REVIVE TOKENS")
	elseif k == "crate" then
		return string.format("%s ×%d", crateNames[id] or "CRATE", n)
	elseif k == "weapon" then
		local w = Weapons.ById[id]
		return if w then string.upper(w.displayName) else id
	elseif k == "mask" then
		local m = Masks.ById[id]
		return if m then string.upper(m.name) else id
	elseif k == "wrap" then
		local w = Wraps.ById[id]
		-- Round 30d: a per-gun wrap names its gun (CRIMSON · AK-47).
		local gun = r.on and Weapons.ById[r.on]
		if w and gun then
			return string.upper(w.name) .. " · " .. string.upper(gun.displayName)
		end
		return if w then string.upper(w.name) .. " WRAP" else id
	elseif k == "emote" then
		local e = Emotes.ById[id]
		return if e then string.upper(e.name) else id
	elseif k == "class" then
		local c = Classes.ById[id]
		return if c then c.displayName else id
	elseif k == "boost" then
		local b = BoostDefs.ById[id]
		return string.format("%s %s BOOST", Rewards.duration(r.sec or 0), if b then b.name else id)
	elseif k == "mastery" then
		return "+" .. int(n) .. " MASTERY XP"
	elseif k == "xp" then
		return "+" .. int(n) .. " XP"
	elseif k == "passxp" then
		return "+" .. int(n) .. " PASS XP"
	end
	return k
end

-- A short type label under the name (store detail rows, the pass center panel).
function Rewards.kindLabel(r: Reward): string
	local k = r.kind
	if k == "emote" then
		local e = Emotes.ById[r.id or ""]
		return if e and e.slot == "mvp" then "MVP POSE" else "SQUAD POSE"
	end
	local labels = {
		gold = "GOLD",
		tokens = "REVIVE TOKENS",
		crate = "CRATE OPENS",
		weapon = "WEAPON",
		mask = "MASK",
		wrap = "WRAP",
		class = "CLASS",
		boost = "BOOST",
		mastery = "MASTERY",
		xp = "ACCOUNT XP",
		passxp = "PASS XP",
	}
	return labels[k] or string.upper(k)
end

-- Rarity for the frame: an item's own rarity; currencies scale with the amount.
function Rewards.rarity(r: Reward): number
	local k, id, n = r.kind, r.id or "", r.amount or 0
	if k == "weapon" then
		local w = Weapons.ById[id]
		return if w then w.rarity else 1
	elseif k == "mask" then
		local m = Masks.ById[id]
		return if m then m.rarity else 1
	elseif k == "wrap" then
		local w = Wraps.ById[id]
		return if w then w.rarity else 1
	elseif k == "emote" then
		local e = Emotes.ById[id]
		return if e then e.rarity else 1
	elseif k == "class" then
		return 4
	elseif k == "gold" then
		return if n >= 5000 then 5 elseif n >= 2000 then 4 elseif n >= 700 then 3 elseif n >= 300 then 2 else 1
	elseif k == "tokens" then
		return if n >= 25 then 5 elseif n >= 10 then 4 elseif n >= 5 then 3 elseif n >= 2 then 2 else 1
	elseif k == "crate" then
		return if n >= 10 then 5 elseif n >= 3 then 4 else 3
	elseif k == "boost" then
		return if (r.sec or 0) >= 86400 then 4 else 3
	elseif k == "mastery" then
		return if n >= 400 then 3 else 2
	end
	return 1
end

-- Already owned (items only; currencies never are).
function Rewards.owned(profile: any, r: Reward): boolean
	if not profile then
		return false
	end
	local id = r.id or ""
	if r.kind == "weapon" then
		return profile.weapons ~= nil and profile.weapons[id] ~= nil
	elseif r.kind == "mask" then
		return profile.masks ~= nil and profile.masks.owned[id] == true
	elseif r.kind == "wrap" then
		return Wraps.owns(profile, id, r.on) -- Round 30d: per gun for shop wraps
	elseif r.kind == "emote" then
		return profile.emotes ~= nil and profile.emotes.owned[id] == true
	elseif r.kind == "class" then
		return profile.classes ~= nil and profile.classes.owned[id] == true
	end
	return false
end

-- The color an item draws in (its own color for masks / wraps / weapon looks, the class color, else nil).
function Rewards.color(r: Reward): string?
	local id = r.id or ""
	if r.kind == "mask" then
		local m = Masks.ById[id]
		return if m then m.color else nil
	elseif r.kind == "wrap" then
		local w = Wraps.ById[id]
		return if w then w.color else nil
	elseif r.kind == "weapon" then
		local w = Weapons.ById[id]
		return if w and w.look then w.look.color else nil
	elseif r.kind == "class" then
		local c = Classes.ById[id]
		return if c then c.color else nil
	elseif r.kind == "boost" then
		local b = BoostDefs.ById[id]
		return if b then b.color else nil
	end
	return nil
end

return Rewards
