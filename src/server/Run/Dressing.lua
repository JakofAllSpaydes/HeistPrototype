--!strict
-- Brief 13: exterior escalation on THE BANK. The street tells the wave count: at each intermission start the stage
-- for the coming wave is recomputed (Config.DressingStageWaves: stage 1 from wave 5, 2 from 10, 3 from 15) and every
-- Dressing node (Workspace.Bank.Nodes.Dressing) whose Stage the run has reached gets a clone of its Mesh template
-- (Workspace.Bank.Dressing.Templates, taken out of the world at load) under Workspace.Bank.DressingLive. Boss nodes
-- show only for a boss wave. Pieces appear behind the fences: one never appears inside a player (it waits until the
-- spot is clear), and a member on the street sees a short dust puff where it lands. Nothing of it collides or stops
-- a shot. Stage 3 adds the helicopter on the HeliPath loop (HeliEnabled): the clients fly it, spin the rotors and
-- aim its spotlight at the member the server names every HeliSpotSwitchSec (attribute SpotTarget). The live
-- folder's attributes (Stage, Boss, Ambience, Street) drive the clients' siren bed (DressingFx.client.lua).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Ground = require(Shared.Ground)
local World = require(script.Parent.World)
local MapLoader = require(script.Parent.MapLoader)
local Slot = require(script.Parent.Slot)
local Log = require(script.Parent.Parent.Log)

local Dressing = {}

Dressing.stage = 0
Dressing.boss = false
Dressing.forcedStage = nil :: number? -- debug Set dressing stage
Dressing.heliOverride = nil :: boolean? -- debug Heli on / off (nil = Config.HeliEnabled)

local templates: Folder? = nil
local live: Folder? = nil
local shown: { [BasePart]: Model } = {} -- node -> its clone
local pending: { [BasePart]: boolean } = {} -- nodes waiting for a player to step clear
local heli: Model? = nil

local function onBank(): boolean
	return World.map == MapLoader.MAP_ID and MapLoader.loaded and live ~= nil
end

local function nodesOf(kind: string): { BasePart }
	local out = {}
	local nodes = MapLoader.nodesFolder
	local f = nodes and nodes:FindFirstChild(kind)
	if f then
		for _, c in f:GetChildren() do
			if c:IsA("BasePart") then
				table.insert(out, c)
			end
		end
	end
	return out
end

-- The node's CFrame on the ground, moved in with the street when it is marked StreetScale.
local function placeOf(node: BasePart): CFrame
	local cf = node.CFrame
	if node:GetAttribute("StreetScale") == true then
		local cx = Config.BankOrigin.X
		local p = cf.Position
		cf = cf.Rotation + Vector3.new(cx + (p.X - cx) * Config.StreetSpawnDistanceMult, p.Y, p.Z)
	end
	local p = cf.Position
	local y = Ground.y(p + Vector3.new(0, 4, 0), p.Y - node.Size.Y / 2, 0, 40)
	return cf.Rotation + Vector3.new(p.X, y, p.Z)
end

-- The stage a wave plays at.
function Dressing.stageFor(wave: number): number
	local stage = 0
	for i, w in Config.DressingStageWaves do
		if wave >= w then
			stage = i
		end
	end
	return stage
end

local function heliOn(): boolean
	if Dressing.heliOverride ~= nil then
		return Dressing.heliOverride == true
	end
	return Config.HeliEnabled
end

local function clone(node: BasePart): Model?
	local t = templates
	local mesh = node:GetAttribute("Mesh")
	local template = t and typeof(mesh) == "string" and t:FindFirstChild(mesh)
	if not template or not template:IsA("Model") then
		Log.event("Dressing", "ERROR %s: Mesh '%s' is not a template", node.Name, tostring(mesh))
		return nil
	end
	local m = template:Clone()
	m.Name = node.Name
	local rootPart = m:FindFirstChild("Root")
	if rootPart and rootPart:IsA("BasePart") then
		m.PrimaryPart = rootPart
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	m:PivotTo(placeOf(node))
	return m
end

-- Is a member standing inside where this piece would go (its bounding box plus a margin)?
local function blocked(m: Model): boolean
	local cf, size = m:GetBoundingBox()
	for _, p in World.partyPlayers() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and MapLoader.inVolume(cf, size, root.Position, Config.DressingClearance) then
			return true
		end
	end
	return false
end

local function streetMembers(): boolean
	for _, p in World.partyPlayers() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and MapLoader.zoneAt(root.Position) == "street" then
			return true
		end
	end
	return false
end

-- Show / hide every node for the current stage and boss flag. New pieces wait for a clear spot.
local function apply()
	local f = live
	if not f then
		return
	end
	local puffs: { Vector3 } = {}
	local want: { [BasePart]: boolean } = {}
	for _, node in nodesOf("Dressing") do
		local stage = tonumber(node:GetAttribute("Stage")) or 0
		local isBoss = node:GetAttribute("Boss") == true
		local on = if isBoss then Dressing.boss else (stage > 0 and Dressing.stage >= stage)
		if on then
			want[node] = true
		end
	end
	for node, m in shown do
		if not want[node] then
			m:Destroy()
			shown[node] = nil
		end
	end
	pending = {}
	for node in want do
		if shown[node] then
			continue
		end
		local m = clone(node)
		if not m then
			continue
		end
		if blocked(m) then
			pending[node] = true
			m:Destroy()
			continue
		end
		m.Parent = f
		shown[node] = m
		table.insert(puffs, m:GetPivot().Position)
	end
	if #puffs > 0 and streetMembers() then
		World.fireRun("DressingPuff", { positions = puffs })
	end
	-- The helicopter (stage 3, HeliEnabled): one model the clients fly round the HeliPath loop.
	local wantHeli = Dressing.stage >= 3 and heliOn()
	if wantHeli and not heli then
		local t = templates
		local template = t and t:FindFirstChild("Helicopter")
		if template and template:IsA("Model") then
			local h = template:Clone()
			h.Name = "Helicopter"
			local rootPart = h:FindFirstChild("Root")
			if rootPart and rootPart:IsA("BasePart") then
				h.PrimaryPart = rootPart
			end
			local path = nodesOf("HeliPath")
			table.sort(path, function(a, b)
				return (tonumber(a:GetAttribute("Index")) or 0) < (tonumber(b:GetAttribute("Index")) or 0)
			end)
			for i, n in path do
				h:SetAttribute("P" .. i, n.Position)
			end
			h:SetAttribute("Count", #path)
			h:SetAttribute("Altitude", Config.BankOrigin.Y + Config.HeliAltitude)
			h:SetAttribute("Speed", Config.HeliSpeed)
			for _, d in h:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
				end
			end
			local first = path[1]
			h:PivotTo(CFrame.new(if first then first.Position else Vector3.new(0, 90, -1100)))
			h.Parent = f
			heli = h
			Log.event("Dressing", "helicopter up (%d path points)", #path)
		end
	elseif not wantHeli and heli then
		heli:Destroy()
		heli = nil
	end
	f:SetAttribute("Stage", Dressing.stage)
	f:SetAttribute("Boss", Dressing.boss)
	f:SetAttribute("Ambience", Config.DressingAmbience[Dressing.stage] or "")
end

local function setStage(stage: number, boss: boolean, why: string)
	local changed = stage ~= Dressing.stage
	Dressing.stage = stage
	Dressing.boss = boss
	apply()
	if changed then
		Log.event("Dressing", "stage %d wave %d (%s)", stage, World.wave, why)
	end
end

-- The intermission before `nextWave` (Main): the street dresses up for it while nobody is fighting.
function Dressing.onIntermission(nextWave: number)
	if not onBank() then
		return
	end
	local stage = Dressing.forcedStage or Dressing.stageFor(nextWave)
	setStage(stage, World.isBossWave(nextWave), "intermission")
end

-- Wave start: catches up a stage the intermission never got to (AUTO SKIP rolls waves together with none).
function Dressing.onWaveStart(wave: number)
	if not onBank() or Dressing.forcedStage then
		return
	end
	local stage = Dressing.stageFor(wave)
	local boss = World.isBossWave(wave)
	if stage ~= Dressing.stage or boss ~= Dressing.boss then
		setStage(stage, boss, "wave start")
	end
end

-- Debug Set dressing stage: 0..3 now (and kept until reset); 4 = stage 3 plus the boss pieces.
function Dressing.debugStage(n: number)
	if not onBank() then
		return
	end
	local stage = math.clamp(math.floor(n), 0, 3)
	Dressing.forcedStage = stage
	setStage(stage, n >= 4, "debug")
end

function Dressing.debugHeli(on: boolean)
	Dressing.heliOverride = on
	apply()
end

-- Run start / hub: the clean street.
function Dressing.resetRun()
	Dressing.forcedStage = nil
	for _, m in shown do
		m:Destroy()
	end
	shown = {}
	pending = {}
	if heli then
		heli:Destroy()
		heli = nil
	end
	Dressing.stage = 0
	Dressing.boss = false
	local f = live
	if f then
		f:SetAttribute("Stage", 0)
		f:SetAttribute("Boss", false)
		f:SetAttribute("Ambience", "")
	end
end

function Dressing.init()
	if Slot.mapId ~= MapLoader.MAP_ID then
		return
	end
	local bank = MapLoader.bank
	if not bank then
		return
	end
	local dressing = bank:FindFirstChild("Dressing")
	local t = dressing and dressing:FindFirstChild("Templates")
	if not t or not t:IsA("Folder") then
		Log.event(
			"Dressing",
			"no Workspace.Bank.Dressing.Templates (sync src/map/Bank.dressing.rbxmx); no street dressing"
		)
		return
	end
	-- The templates leave the world; clones go to the live folder.
	t.Name = "BankDressingTemplates"
	t.Parent = ServerStorage
	templates = t
	local f = Instance.new("Folder")
	f.Name = "DressingLive"
	local streetZone = MapLoader.zones.street
	local street = if streetZone and streetZone.parts[1]
		then streetZone.parts[1].cframe.Position
		else bank:GetPivot().Position
	f:SetAttribute("Street", street)
	f:SetAttribute("Stage", 0)
	f:SetAttribute("Boss", false)
	f:SetAttribute("Ambience", "")
	f.Parent = bank
	live = f
	local n = #nodesOf("Dressing")
	Log.event("Dressing", "%d dressing nodes, %d heli path points", n, #nodesOf("HeliPath"))
	-- Waiting pieces drop in once their spot is clear; the helicopter's spotlight changes target.
	task.spawn(function()
		while true do
			task.wait(1)
			if next(pending) and onBank() then
				apply()
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.HeliSpotSwitchSec)
			local h = heli
			if h and h.Parent then
				local crew = World.partyPlayers()
				if #crew > 0 then
					h:SetAttribute("SpotTarget", crew[math.random(#crew)].UserId)
				end
			end
		end
	end)
end

return Dressing
