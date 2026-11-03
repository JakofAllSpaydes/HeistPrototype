--!strict
-- Stub Side Job: a timer and a blue beacon at a random pillar with a hold-to-HACK prompt.
-- Completing it pays, plays a crew line and drops a crate at the beacon. Enough to test the
-- call -> pill -> toast rhythm under wave pressure.
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

type Job = { id: number, endsAt: number, beacon: Model, active: boolean, position: Vector3 }

local CrewCall = {}

local effects = Workspace:WaitForChild("Effects")
local job: Job? = nil
local nextId = 0

local function buildBeacon(position: Vector3, onTriggered: (Player) -> ()): Model
	local model = Instance.new("Model")
	model.Name = "SideJobBeacon"
	local blue = Color3.fromHex("4D9FE8")
	local pad = Instance.new("Part")
	pad.Name = "Pad"
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(0.3, Config.SideJobBeaconRadius * 2, Config.SideJobBeaconRadius * 2)
	pad.CFrame = CFrame.new(position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanQuery = false
	pad.Color = blue
	pad.Material = Enum.Material.Neon
	pad.Transparency = 0.5
	pad.Parent = model
	local column = Instance.new("Part")
	column.Name = "Column"
	column.Size = Vector3.new(2, 40, 2)
	column.CFrame = CFrame.new(position + Vector3.new(0, 20, 0))
	column.Anchored = true
	column.CanCollide = false
	column.CanQuery = false
	column.Color = blue
	column.Material = Enum.Material.Neon
	column.Transparency = 0.75
	column.Parent = model
	-- The terminal: a small box you hack.
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
	screen.Color = blue
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
	model.PrimaryPart = pad
	model.Parent = effects
	return model
end

function CrewCall.trigger()
	if job then
		CrewCall.finish(false, true)
	end
	nextId += 1
	local pillar = Room.randomPillar()
	-- Beacon sits beside the pillar, pushed toward the room center so it is reachable.
	local toCenter = if pillar.Magnitude > 0.1 then -pillar.Unit else Vector3.new(1, 0, 0)
	local position = pillar + toCenter * (Config.PillarSize / 2 + Config.SideJobBeaconRadius + 1)
	local endsAt = Workspace:GetServerTimeNow() + Config.SideJobDurationSec
	local thisJob: Job
	thisJob = {
		id = nextId,
		endsAt = endsAt,
		beacon = buildBeacon(position, function(player)
			if job == thisJob and thisJob.active then
				Log.event("Call", "%s hacked the terminal for Side Job #%d", player.Name, thisJob.id)
				CrewCall.finish(true)
			end
		end),
		active = true,
		position = position,
	}
	job = thisJob

	Remotes.Juice:FireAllClients("CallStart", {
		id = thisJob.id,
		kind = Lines.job.kind,
		name = Lines.job.name,
		crewLead = Lines.job.crewLead,
		typeLabel = Lines.job.typeLabel,
		text = Lines.job.text,
		rewardLine = string.format(Lines.job.rewardLine, Config.SideJobReward),
		reward = Config.SideJobReward,
		endsAt = endsAt,
		duration = Config.SideJobDurationSec,
		position = position,
	})
	Log.event(
		"Call",
		"Side Job #%d started, %ds, beacon at (%d, %d)",
		thisJob.id,
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
			success = success,
			reward = Config.SideJobReward,
			name = Lines.job.name,
			crewLead = Lines.job.crewLead,
			kind = Lines.job.kind,
			title = if success then Lines.job.doneTitle else Lines.failToast,
			text = if success then Lines.job.doneText else Lines.job.failText,
			rewardLine = if success then string.format(Lines.job.rewardLine, Config.SideJobReward) else "",
			toast = if success
				then string.format(Lines.doneToast, Lines.job.name, Config.SideJobReward)
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
	RunService.Heartbeat:Connect(function()
		local j = job
		if not j or not j.active then
			return
		end
		if Workspace:GetServerTimeNow() >= j.endsAt then
			CrewCall.finish(false)
		end
	end)
end

return CrewCall
