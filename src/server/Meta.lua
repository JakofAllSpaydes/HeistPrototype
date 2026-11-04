--!strict
-- Meta actions from the customization scene, all Gold-priced from Prices.lua: weapon unlock / upgrade /
-- starter / wraps, class unlock / equip, ability upgrade, mask purchase / equip. Every action validates
-- against the profile, charges, marks the profile dirty (debounced write) and returns a toast line.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Weapons = require(Shared.Weapons)
local Classes = require(Shared.Classes)
local Masks = require(Shared.Masks)
local Emotes = require(Shared.Emotes)
local Wraps = require(Shared.Wraps)
local Prices = require(Shared.Prices)
local PlayerState = require(script.Parent.PlayerState)
local Profiles = require(script.Parent.Profiles)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
local Hub = require(script.Parent.Hub)

local Meta = {}

type Result = { ok: boolean, reason: string?, toast: string?, kind: string? }

local function fail(reason: string, toast: string?): Result
	return { ok = false, reason = reason, toast = toast or reason, kind = "error" }
end

local function done(toast: string, kind: string?): Result
	return { ok = true, toast = toast, kind = kind or "click" }
end

local function charge(player: Player, amount: number): boolean
	if not Profiles.tryCharge(player, amount) then
		return false
	end
	return true
end

local NOT_ENOUGH = "Not enough Gold!"

local handlers: { [string]: (Player, PlayerState.State, Profiles.Profile, any) -> Result } = {}

------------------------------------------------------------------ Weapons
handlers.unlockWeapon = function(player, state, p, args)
	local w = Weapons.ById[tostring(args and args.weaponId)]
	if not w then
		return fail("no such weapon")
	end
	if p.weapons[w.id] then
		return fail("already owned")
	end
	if w.saleType == "Event" then
		return fail("EVENT ONLY")
	elseif w.saleType == "Crate" then
		return fail("CRATE UI · PHASE 4")
	end
	local cost = Weapons.unlockCost(w)
	if not charge(player, cost) then
		return fail("gold", NOT_ENOUGH)
	end
	p.weapons[w.id] = { level = 0 }
	-- New things are equipped as they are unlocked.
	p.starterWeaponId = w.id
	Profiles.markDirty(player)
	if not World.inRun() then
		state.held = PlayerState.starterHeld(state)
		PlayerState.refreshHeldVisual(state)
		state.dirty = true
	end
	Log.event("Meta", "%s unlocked %s for %d gold and equipped it as starter", player.Name, w.id, cost)
	return done(w.displayName .. " unlocked and equipped!", "celebrate")
end

handlers.upgradeWeapon = function(player, state, p, args)
	local w = Weapons.ById[tostring(args and args.weaponId)]
	local entry = w and p.weapons[w.id]
	if not w or not entry then
		return fail("not owned")
	end
	local cost = Weapons.upgradeCost(w, entry.level)
	if not charge(player, cost) then
		return fail("gold", NOT_ENOUGH)
	end
	entry.level += 1
	Profiles.markDirty(player)
	if state.held.weaponId == w.id then
		state.held.level = entry.level
		PlayerState.applyCharacterStats(state)
		state.dirty = true
	end
	Log.event("Meta", "%s upgraded %s to LV %d for %d gold", player.Name, w.id, entry.level, cost)
	return done(string.format("%s LV %d!", w.displayName, entry.level), "celebrate")
end

handlers.equipStarter = function(player, state, p, args)
	local w = Weapons.ById[tostring(args and args.weaponId)]
	if not w or not p.weapons[w.id] then
		return fail("not owned")
	end
	p.starterWeaponId = w.id
	Profiles.markDirty(player)
	if not World.inRun() then
		state.held = PlayerState.starterHeld(state)
		PlayerState.refreshHeldVisual(state)
		state.dirty = true
	end
	Log.event("Meta", "%s equipped %s as starter", player.Name, w.id)
	return done(w.displayName .. " equipped as Starter!", "click")
end

handlers.buyWrap = function(player, state, p, args)
	local wrap = Wraps.ById[tostring(args and args.wrapId)]
	if not wrap then
		return fail("no such wrap")
	end
	if p.wraps.owned[wrap.id] then
		return fail("already owned")
	end
	if not charge(player, Prices.wrap) then
		return fail("gold", NOT_ENOUGH)
	end
	p.wraps.owned[wrap.id] = true
	-- Applied at once to the weapon it was bought from (args.weaponId), when owned.
	local w = Weapons.ById[tostring(args and args.weaponId)]
	local entry = w and p.weapons[w.id]
	if w and entry then
		entry.wrap = wrap.id
		if state.held.weaponId == w.id then
			PlayerState.refreshHeldVisual(state)
			state.dirty = true
		end
	end
	Profiles.markDirty(player)
	Log.event("Meta", "%s bought the %s wrap%s", player.Name, wrap.id, if w then " and put it on " .. w.id else "")
	return done(wrap.name .. (if w then " unlocked and applied!" else " unlocked!"), "celebrate")
end

-- Apply (or clear, wrapId nil) a wrap on an owned weapon. Owned wraps only.
handlers.applyWrap = function(player, state, p, args)
	local w = Weapons.ById[tostring(args and args.weaponId)]
	local entry = w and p.weapons[w.id]
	if not w or not entry then
		return fail("not owned")
	end
	local wrapId = if args and typeof(args.wrapId) == "string" then args.wrapId else nil
	if wrapId and not (Wraps.ById[wrapId] and p.wraps.owned[wrapId]) then
		return fail("wrap not owned")
	end
	entry.wrap = wrapId
	Profiles.markDirty(player)
	if state.held.weaponId == w.id then
		PlayerState.refreshHeldVisual(state)
		state.dirty = true
	end
	Log.event("Meta", "%s put %s on %s", player.Name, tostring(wrapId or "no wrap"), w.id)
	local name = if wrapId then Wraps.ById[wrapId].name else "No wrap"
	return done(name .. " equipped!", "click")
end

------------------------------------------------------------------ Classes
handlers.unlockClass = function(player, state, p, args)
	local c = Classes.ById[tostring(args and args.classId)]
	if not c then
		return fail("no such class")
	end
	if p.classes.owned[c.id] then
		return fail("already owned")
	end
	if not charge(player, Prices.class) then
		return fail("gold", NOT_ENOUGH)
	end
	p.classes.owned[c.id] = true
	p.classes.equipped = c.id
	state.cooldowns = {}
	Profiles.markDirty(player)
	state.dirty = true
	Hub.refreshTag(player)
	Log.event("Meta", "%s unlocked and equipped class %s", player.Name, c.id)
	return done(string.upper(c.name) .. " unlocked and equipped!", "celebrate")
end

handlers.equipClass = function(player, state, p, args)
	local c = Classes.ById[tostring(args and args.classId)]
	if not c or not p.classes.owned[c.id] then
		return fail("not owned")
	end
	p.classes.equipped = c.id
	Profiles.markDirty(player)
	state.cooldowns = {}
	state.dirty = true
	Hub.refreshTag(player)
	Log.event("Meta", "%s equipped class %s", player.Name, c.id)
	return done(string.upper(c.name) .. " equipped!", "click")
end

handlers.upgradeAbility = function(player, state, p, args)
	local a = Classes.AbilityById[tostring(args and args.abilityId)]
	if not a then
		return fail("no such ability")
	end
	local classId = Classes.ClassOfAbility[a.id]
	if not p.classes.owned[classId] then
		return fail("NOT UNLOCKED")
	end
	if not charge(player, Prices.ability) then
		return fail("gold", NOT_ENOUGH)
	end
	p.abilities[a.id] = (p.abilities[a.id] or 0) + 1
	Profiles.markDirty(player)
	state.dirty = true
	Log.event("Meta", "%s upgraded %s to LV %d", player.Name, a.id, p.abilities[a.id])
	return done(string.format("%s LV %d!", a.name, p.abilities[a.id]), "celebrate")
end

------------------------------------------------------------------ Masks
handlers.buyMask = function(player, state, p, args)
	local m = Masks.ById[tostring(args and args.maskId)]
	if not m then
		return fail("no such mask")
	end
	if p.masks.owned[m.id] then
		return fail("already owned")
	end
	if m.saleType == "Event" then
		return fail("EVENT ONLY")
	elseif m.saleType == "Crate" then
		return fail("CRATE UI · PHASE 4")
	end
	if not charge(player, m.price or Prices.mask) then
		return fail("gold", NOT_ENOUGH)
	end
	p.masks.owned[m.id] = true
	p.masks.equipped = m.id
	Profiles.markDirty(player)
	PlayerState.applyMask(state)
	state.dirty = true
	Log.event("Meta", "%s bought and equipped the %s mask", player.Name, m.id)
	return done(m.name .. " unlocked and equipped!", "celebrate")
end

handlers.equipMask = function(player, state, p, args)
	local m = Masks.ById[tostring(args and args.maskId)]
	if not m or not p.masks.owned[m.id] then
		return fail("not owned")
	end
	p.masks.equipped = m.id
	Profiles.markDirty(player)
	PlayerState.applyMask(state)
	state.dirty = true
	Log.event("Meta", "%s equipped the %s mask", player.Name, m.id)
	return done(m.name .. " equipped!", "click")
end

------------------------------------------------------------------ Emotes (SQUAD pose, MVP flex)
handlers.buyEmote = function(player, _state, p, args)
	local e = Emotes.ById[tostring(args and args.emoteId)]
	if not e then
		return fail("no such emote")
	end
	if p.emotes.owned[e.id] then
		return fail("already owned")
	end
	if e.saleType == "Event" then
		return fail("EVENT ONLY")
	elseif e.saleType == "Crate" then
		return fail("CRATE UI · PHASE 4")
	end
	if not charge(player, e.price or Prices.emote) then
		return fail("gold", NOT_ENOUGH)
	end
	p.emotes.owned[e.id] = true
	if e.slot == "mvp" then
		p.emotes.mvp = e.id
	else
		p.emotes.squad = e.id
	end
	Profiles.markDirty(player)
	Log.event("Meta", "%s bought and equipped the %s emote (%s)", player.Name, e.id, e.slot)
	return done(e.name .. " unlocked and equipped!", "celebrate")
end

handlers.equipEmote = function(player, _state, p, args)
	local e = Emotes.ById[tostring(args and args.emoteId)]
	if not e or not p.emotes.owned[e.id] then
		return fail("not owned")
	end
	if e.slot == "mvp" then
		p.emotes.mvp = e.id
	else
		p.emotes.squad = e.id
	end
	Profiles.markDirty(player)
	Log.event("Meta", "%s equipped the %s emote (%s)", player.Name, e.id, e.slot)
	return done(e.name .. " equipped!", "click")
end

function Meta.init()
	Remotes.Meta.OnServerInvoke = function(player: Player, action: any, args: any): Result
		local handler = handlers[tostring(action)]
		if not handler then
			return fail("unknown action")
		end
		local state = PlayerState.get(player)
		local profile = state.profile or Profiles.get(player)
		if not profile then
			return fail("profile loading")
		end
		state.profile = profile
		if World.inRun() and World.isInParty(player) then
			return fail("not in a run")
		end
		local result = handler(player, state, profile, args)
		state.dirty = true
		return result
	end
	-- Nothing else: the MatchMode is local, so there is no server list to talk to.
	local _ = Config.MatchMode
end

return Meta
