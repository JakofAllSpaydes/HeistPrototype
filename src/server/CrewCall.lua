--!strict
-- Side Jobs: a timer plus a blue beacon at a random pillar. Two kinds, rolled per job (Config.SideJobKindWeights):
--   hack     - hold the HACK prompt on a terminal.
--   capture  - stand inside the circle for SideJobCaptureSec; progress pauses while nobody is in it.
-- Completing pays, plays a crew line and drops a crate at the beacon.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Lines = require(Shared.CrewCall.Lines)
local PlayerState = require(script.Parent.PlayerState)
local Economy = require(script.Parent.Economy)
local Room = require(script.Parent.Room)
local BigCrate = require(script.Parent.BigCrate)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)

type Job = {
	id: number,
	kind: string, -- hack | capture
	endsAt: number,
	beacon: Model,
	fill: BasePart?, -- capture: the disc that grows with progress
	active: boolean,
	position: Vector3,
	progress: number, -- capture: 0..1
	inside: boolean, -- capture: someone is in the circle
	lastSent: number,
}

local CrewCall = {}

local effects = Workspace:WaitForChild("Effects")
local job: Job? = nil
local nextId = 0
local BLUE = Color3.fromHex("4D9FE8")
local GREEN = Color3.fromHex("8FE3A1")

local function copyFor(kind: string): any
	return if kind == "capture" then Lines.capture else Lines.job
end

-- Weighted roll over Config.SideJobKindWeights.
local function rollKind(): string
	local total = 0
	for _, w in Config.SideJobKindWeights do
		total += math.max(0, w)
	end
	local r = math.random() * total
	for kind, w in Config.SideJobKindWeights do
		r -= math.max(0, w)
		if r <= 0 then
			return kind
		end
	end
	return "hack"
end

local function cylinder(
	name: string,
	position: Vector3,
	radius: number,
	thickness: number,
	color: Color3,
	transparency: number
): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(thickness, radius * 2, radius * 2)
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Transparency = transparency
	return part
end

-- Shared beacon: floor pad and a tall column so it reads across the room.
local function buildBeaconBase(position: Vector3, radius: number): Model
	local model = Instance.new("Model")
	model.Name = "SideJobBeacon"
	local pad = cylinder("Pad", position + Vector3.new(0, 0.15, 0), radius, 0.3, BLUE, 0.5)
	pad.Parent = model
	local column = Instance.new("Part")
	column.Name = "Column"
	column.Size = Vector3.new(2, 40, 2)
	column.CFrame = CFrame.new(position + Vector3.new(0, 20, 0))
	column.Anchored = true
	column.CanCollide = false
	column.CanQuery = false
	column.Color = BLUE
	column.Material = Enum.Material.Neon
	column.Transparency = 0.75
	column.Parent = model
	model.PrimaryPart = pad
	return model
end

-- Hack: a terminal with a hold-to-HACK prompt.
local function buildHackBeacon(position: Vector3, onTriggered: (Player) -> ()): Model
	local model = buildBeaconBase(position, Config.SideJobBeaconRadius)
	local terminal = Instance.new("Part")
	terminal.Name = "Terminal"
	terminal.Size = Vector3.new(2, 3, 1)
	terminal.CFrame = CFrame.new(position + Vector3.new(0, 1.5, 0))
	terminal.Anchored = true
	terminal.CanCollide = false
	terminal.Color = Color3.fromRGB(30, 34, 44)
	terminal.Material = Enum.Material.Metal
	terminal.Parent = model
	local screen = Instance.new("Part")
	screen.Name = "Screen"
	screen.Size = Vector3.new(1.6, 1, 0.1)
	screen.CFrame = terminal.CFrame * CFrame.new(0, 0.6, -0.55)
	screen.Anchored = true
	screen.CanCollide = false
	screen.Color = BLUE
	screen.Material = Enum.Material.Neon
	screen.Parent = model
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = Lines.job.promptAction
	prompt.ObjectText = Lines.job.promptObject
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = Config.SideJobHoldSec
	prompt.MaxActivationDistance = Config.SideJobBeaconRadius + 2
	prompt.RequiresLineOfSight = false
	prompt.Parent = terminal
	prompt.Triggered:Connect(onTriggered)
	model.Parent = effects
	return model
end

-- Capture: a wider ring, a thin rim, and a green fill disc that grows with progress.
local function buildCaptureBeacon(position: Vector3): (Model, BasePart)
	local r = Config.SideJobCaptureRadius
	local model = buildBeaconBase(position, r)
	local rim = cylinder("Rim", position + Vector3.new(0, 0.2, 0), r + 0.4, 0.2, BLUE, 0.1)
	rim.Parent = model
	local fill = cylinder("Fill", position + Vector3.new(0, 0.32, 0), 0.05, 0.1, GREEN, 0.3)
	fill.Parent = model
	model.Parent = effects
	return model, fill
end

local function sendProgress(j: Job, force: boolean)
	local now = os.clock()
	if not force and now - j.lastSent < 0.1 then
		return
	end
	j.lastSent = now
	Remotes.Juice:FireAllClients("JobProgress", { id = j.id, progress = j.progress, inside = j.inside })
end

local function anyoneInside(position: Vector3, radius: number): boolean
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 and PlayerState.isStanding(PlayerState.get(player)) then
			local d = root.Position - position
			if Vector3.new(d.X, 0, d.Z).Magnitude <= radius then
				return true
			end
		end
	end
	return false
end

function CrewCall.trigger()
	if job then
		CrewCall.finish(false, true)
	end
	nextId += 1
	local kind = rollKind()
	local copy = copyFor(kind)
	local pillar = Room.randomPillar()
	-- Beacon sits beside the pillar, pushed toward the room center so it is reachable.
	local radius = if kind == "capture" then Config.SideJobCaptureRadius else Config.SideJobBeaconRadius
	local toCenter = if pillar.Magnitude > 0.1 then -pillar.Unit else Vector3.new(1, 0, 0)
	local position = pillar + toCenter * (Config.PillarSize / 2 + radius + 1)
	local endsAt = Workspace:GetServerTimeNow() + Config.SideJobDurationSec
	local thisJob: Job
	local beacon: Model
	local fill: BasePart? = nil
	if kind == "capture" then
		beacon, fill = buildCaptureBeacon(position)
	else
		beacon = buildHackBeacon(position, function(player)
			if job == thisJob and thisJob.active then
				Log.event("Call", "%s hacked the terminal for Side Job #%d", player.Name, thisJob.id)
				CrewCall.finish(true)
			end
		end)
	end
	thisJob = {
		id = nextId,
		kind = kind,
		endsAt = endsAt,
		beacon = beacon,
		fill = fill,
		active = true,
		position = position,
		progress = 0,
		inside = false,
		lastSent = 0,
	}
	job = thisJob

	Remotes.Juice:FireAllClients("CallStart", {
		id = thisJob.id,
		jobKind = kind,
		kind = copy.kind,
		name = copy.name,
		crewLead = copy.crewLead,
		typeLabel = copy.typeLabel,
		text = copy.text,
		rewardLine = string.format(copy.rewardLine, Config.SideJobReward),
		reward = Config.SideJobReward,
		endsAt = endsAt,
		duration = Config.SideJobDurationSec,
		position = position,
		captureSec = Config.SideJobCaptureSec,
	})
	Log.event(
		"Call",
		"Side Job #%d (%s) started, %ds, beacon at (%d, %d)",
		thisJob.id,
		kind,
		Config.SideJobDurationSec,
		math.round(position.X),
		math.round(position.Z)
	)
end

function CrewCall.finish(success: boolean, silent: boolean?)
	local j = job
	if not j or not j.active then
		return
	end
	j.active = false
	job = nil
	j.beacon:Destroy()
	local copy = copyFor(j.kind)
	if success then
		for _, state in PlayerState.all() do
			Economy.addCash(state, Config.SideJobReward)
		end
		if Config.SideJobRewardCrate then
			BigCrate.drop(j.position)
		end
		World.addHeat(Config.HeatSideJobDone, "side job done")
	elseif not silent then
		World.addHeat(Config.HeatSideJobFail, "side job failed")
	end
	if not silent then
		Remotes.Juice:FireAllClients("CallEnd", {
			id = j.id,
			jobKind = j.kind,
			success = success,
			position = j.position,
			reward = Config.SideJobReward,
			name = copy.name,
			crewLead = copy.crewLead,
			kind = copy.kind,
			title = if success then copy.doneTitle else Lines.failToast,
			text = if success then copy.doneText else copy.failText,
			rewardLine = if success then string.format(copy.rewardLine, Config.SideJobReward) else "",
			toast = if success
				then string.format(Lines.doneToast, copy.name, Config.SideJobReward)
				else Lines.failToast,
		})
	end
	Log.event("Call", "Side Job #%d %s", j.id, if success then "complete, paid $" .. Config.SideJobReward else "failed")
end

function CrewCall.onWaveStart(wave: number)
	if wave >= Config.SideJobFirstWave and (wave - Config.SideJobFirstWave) % Config.SideJobEveryWaves == 0 then
		CrewCall.trigger()
	end
end

function CrewCall.init()
	RunService.Heartbeat:Connect(function(dt)
		local j = job
		if not j or not j.active then
			return
		end
		if Workspace:GetServerTimeNow() >= j.endsAt then
			CrewCall.finish(false)
			return
		end
		if j.kind == "capture" then
			local inside = anyoneInside(j.position, Config.SideJobCaptureRadius)
			local changed = inside ~= j.inside
			j.inside = inside
			if inside then
				j.progress = math.min(1, j.progress + dt / math.max(Config.SideJobCaptureSec, 0.1))
				local fill = j.fill
				if fill then
					local r = math.max(0.05, Config.SideJobCaptureRadius * j.progress)
					fill.Size = Vector3.new(0.1, r * 2, r * 2)
				end
				sendProgress(j, changed)
				if j.progress >= 1 then
					Log.event("Call", "Capture point held for Side Job #%d", j.id)
					CrewCall.finish(true)
				end
			elseif changed then
				sendProgress(j, true)
			end
		end
	end)
end

return CrewCall
