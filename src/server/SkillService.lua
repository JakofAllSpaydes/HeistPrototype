--!strict
-- Brief 9: the Skill Web's server side. SkillBuy(id) validates (known id, not owned, next to an owned hex, Gold
-- covers the ring's cost), spends the Gold the way Armory levels do (Profiles.tryCharge), saves, and replies with
-- the owned set and the new balance. SkillSeen(ids) records the pulse-once set. Hub only, rate-limited. The run
-- start / range folds the owned set into a modifier table (PlayerState.armSkills); nothing in a run reads a node.
-- Debug helpers: unlock all, reset, grant by branch + ring, the stats print.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Skills = require(Shared.Skills)
local Profiles = require(script.Parent.Profiles)
local PlayerState = require(script.Parent.PlayerState)
local Runs = require(script.Parent.Runs)
local Log = require(script.Parent.Log)

local SkillService = {}

local lastBuy: { [Player]: number } = {}

type Result = { ok: boolean, reason: string?, owned: { string }?, gold: number? }

local function ownedList(p: Profiles.Profile): { string }
	local out = {}
	for id, v in p.skills.owned do
		if v then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

local function reply(p: Profiles.Profile, ok: boolean, reason: string?): Result
	return { ok = ok, reason = reason, owned = ownedList(p), gold = p.gold }
end

function SkillService.buy(player: Player, id: any): Result
	local p = Profiles.get(player)
	if not p then
		return { ok = false, reason = "PROFILE LOADING" }
	end
	if not Config.SkillsEnabled then
		return reply(p, false, "SKILLS ARE OFF")
	end
	local now = os.clock()
	if now - (lastBuy[player] or 0) < Config.SkillBuyRateSec then
		return reply(p, false, "TOO FAST")
	end
	lastBuy[player] = now
	if Runs.inRun(player) then
		return reply(p, false, "NOT IN A RUN")
	end
	-- Round 26c: START is bought too (it unlocks the web) and needs no neighbour.
	local isStart = id == Skills.START
	local node = if typeof(id) == "string" then Skills.ById[id] else nil
	if not node and not isStart then
		return reply(p, false, "NO SUCH SKILL")
	end
	local key = if isStart then Skills.START else (node :: Skills.Node).id
	if p.skills.owned[key] then
		return reply(p, false, "OWNED")
	end
	if not Skills.adjacent(p.skills.owned, key) then
		return reply(p, false, "LOCKED · UNLOCK A NEIGHBOUR")
	end
	local cost = Skills.cost(key)
	if not Profiles.tryCharge(player, cost) then
		return reply(p, false, "NOT ENOUGH GOLD")
	end
	p.skills.owned[key] = true
	p.skills.seen[key] = nil -- owned now; the seen set only tracks affordable ones
	Profiles.markDirty(player)
	PlayerState.get(player).dirty = true
	local n = #ownedList(p)
	Log.event(
		"Economy",
		"%s spent %d gold on skill %s (%s, ring %d), %d gold left, %d / %d nodes",
		player.Name,
		cost,
		key,
		if node then node.name else "UNLOCK SKILLS",
		if node then node.ring else 0,
		p.gold,
		n,
		#Skills.List + 1
	)
	-- A buy in the range applies at once (the range is armed); everywhere else it waits for the next run start.
	local state = PlayerState.get(player)
	if state.inRange then
		PlayerState.armSkills(state, "range buy")
	end
	return reply(p, true)
end

function SkillService.seen(player: Player, ids: any)
	local p = Profiles.get(player)
	if not p or typeof(ids) ~= "table" then
		return
	end
	local changed = false
	for i, id in ids do
		if i > #Skills.List + 1 then
			break
		end
		if typeof(id) == "string" and (Skills.ById[id] or id == Skills.START) and not p.skills.seen[id] then
			p.skills.seen[id] = true
			changed = true
		end
	end
	if changed then
		Profiles.markDirty(player)
		PlayerState.get(player).dirty = true
	end
end

------------------------------------------------------------------ Debug
local function changed(player: Player, why: string)
	local p = Profiles.get(player)
	if not p then
		return
	end
	Profiles.markDirty(player)
	local state = PlayerState.get(player)
	state.dirty = true
	if state.inRange or Runs.inRun(player) then
		PlayerState.armSkills(state, why)
	end
	Log.event("Skills", "%s %s: %d / %d nodes owned", player.Name, why, #ownedList(p), #Skills.List)
end

function SkillService.unlockAll(player: Player)
	local p = Profiles.get(player)
	if not p then
		return
	end
	p.skills.owned[Skills.START] = true
	for _, n in Skills.List do
		p.skills.owned[n.id] = true
	end
	changed(player, "debug unlock all skills")
end

function SkillService.reset(player: Player)
	local p = Profiles.get(player)
	if not p then
		return
	end
	table.clear(p.skills.owned)
	table.clear(p.skills.seen)
	changed(player, "debug reset skills")
end

-- Grant the first unowned node of `branch` in `ring` (adjacency and Gold ignored). Returns its id.
function SkillService.grant(player: Player, branch: string, ring: number): string?
	local p = Profiles.get(player)
	if not p then
		return nil
	end
	for _, n in Skills.List do
		if n.branch == branch and n.ring == ring and not p.skills.owned[n.id] then
			p.skills.owned[Skills.START] = true -- a grant opens the web too
			p.skills.owned[n.id] = true
			changed(player, "debug grant " .. n.id)
			return n.id
		end
	end
	return nil
end

-- Debug Stats: owned per branch and the modifier table the next run start would arm.
function SkillService.printStats(player: Player)
	local p = Profiles.get(player)
	if not p then
		return
	end
	local parts = {}
	for _, b in Skills.Branches do
		local have, all = 0, 0
		for _, n in Skills.List do
			if n.branch == b.id then
				all += 1
				if p.skills.owned[n.id] then
					have += 1
				end
			end
		end
		table.insert(parts, string.format("%s %d/%d", b.id, have, all))
	end
	print("[GHS Skills] " .. player.Name .. " owned: " .. table.concat(parts, "  "))
	local m = Skills.modifiers(p.skills.owned)
	print("[GHS Skills] modifiers (next run start): " .. Skills.summary(m))
	local armed = PlayerState.get(player).skillMods
	print(string.format("[GHS Skills] armed now: %d nodes: %s", armed.nodes, Skills.summary(armed)))
end

function SkillService.init()
	Remotes.SkillBuy.OnServerInvoke = function(player: Player, id: any): Result
		return SkillService.buy(player, id)
	end
	Remotes.SkillSeen.OnServerEvent:Connect(function(player: Player, ids: any)
		SkillService.seen(player, ids)
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastBuy[player] = nil
	end)
end

return SkillService
