--!strict
-- Side Jobs: a timer plus a blue beacon at a random pillar. Two kinds, rolled per job (Config.SideJobKindWeights):
--   hack     - hold the HACK prompt on a terminal.
--   capture  - stand inside the circle for SideJobCaptureSec; progress pauses while nobody is in it.
-- Completing pays, plays a crew line and drops a crate at the beacon.
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
local Minigames = require(script.Parent.Minigames)
local Heat = require(script.Parent.Heat)
local VaultJob = require(script.Parent.VaultJob)

type Job = {
	id: number,
	kind: string, -- hack | capture | <minigame> | vault
	endsAt: number,
	beacon: Model?, -- nil for the vault (its door frame is the beacon)
	fill: BasePart?, -- capture: the disc that grows with progress
	active: boolean,
	position: Vector3,
	progress: number, -- capture: 0..1
	inside: boolean, -- capture: someone is in the circle
	insideSet: { [Player]: boolean }, -- capture: who is in it (CAPTURING tag over their head)
	lastSent: number,
	reminded: boolean, -- the half-time reminder line went out
}

local CrewCall = {}

local effects = Workspace:WaitForChild("Effects")
local job: Job? = nil
local nextId = 0
local BLUE = Color3.fromHex("4D9FE8")
local GREEN = Color3.fromHex("8FE3A1")

local function isMinigame(kind: string): boolean
	return table.find(Room.PropNames, kind) ~= nil
end

-- Teammates see what a player is busy with as a tag over their head (PlayerTags on the client).
local function busy(player: Player, label: string, on: boolean)
	World.fireRun("PlayerBusy", { userId = player.UserId, name = player.Name, label = label, on = on })
end

-- Crew call copy per kind. Minigame kinds build theirs from Lines.minigame with the prop's name.
local function copyFor(kind: string): any
	if kind == "capture" then
		return Lines.capture
	elseif kind == "vault" then
		return Lines.vault
	elseif not isMinigame(kind) then
		return Lines.job
	end
	local mg = Lines.minigame
	local prop = mg.props[kind] or { name = string.upper(kind), title = "CRACK THE " .. string.upper(kind) }
	return {
		name = prop.title,
		crewLead = mg.crewLead,
		typeLabel = mg.typeLabel,
		kind = mg.kind,
		text = { string.format(mg.text[1], prop.name), mg.text[2] },
		rewardLine = mg.rewardLine,
		markerHint = string.format(mg.markerHint, prop.name),
		propName = prop.name,
		doneTitle = mg.doneTitle,
		doneText = mg.doneText,
		failText = mg.failText,
	}
end

-- Weighted roll over Config.SideJobKindWeights. The vault only when it can be drawn this wave.
local function rollKind(): string
	local function weight(kind: string, w: number): number
		if kind == "vault" and not VaultJob.available(World.wave) then
			return 0
		end
		return math.max(0, w)
	end
	local total = 0
	for kind, w in Config.SideJobKindWeights do
		total += weight(kind, w)
	end
	local r = math.random() * total
	for kind, w in Config.SideJobKindWeights do
		r -= weight(kind, w)
		if r <= 0 and weight(kind, w) > 0 then
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

-- Hack / minigame: a terminal with a prompt (hold-to-HACK, or tap OPEN for a minigame).
local function buildHackBeacon(
	position: Vector3,
	actionText: string,
	objectText: string,
	holdSec: number,
	onTriggered: (Player) -> ()
): Model
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
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = Enum.KeyCode.F -- F is the interact key everywhere (guns, props, door, beacons)
	prompt.HoldDuration = holdSec
	prompt.MaxActivationDistance = Config.SideJobBeaconRadius + 2
	prompt.RequiresLineOfSight = false
	prompt.Parent = terminal
	prompt.Triggered:Connect(onTriggered)
	if holdSec > 0 then
		-- The hold itself is the work: HACKING over the holder's head until they let go or it lands.
		prompt.PromptButtonHoldBegan:Connect(function(player: Player)
			busy(player, Lines.job.busyTag or "HACKING", true)
		end)
		prompt.PromptButtonHoldEnded:Connect(function(player: Player)
			busy(player, Lines.job.busyTag or "HACKING", false)
		end)
	end
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
	World.fireRun("JobProgress", { id = j.id, progress = j.progress, inside = j.inside })
end

-- Standing players inside the capture circle.
local function playersInside(position: Vector3, radius: number): { [Player]: boolean }
	local set: { [Player]: boolean } = {}
	for _, player in World.runAudience() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 and PlayerState.isStanding(PlayerState.get(player)) then
			local d = root.Position - position
			if Vector3.new(d.X, 0, d.Z).Magnitude <= radius then
				set[player] = true
			end
		end
	end
	return set
end

-- Step in / step out: the CAPTURING tag follows each player's presence in the circle.
local function updateInsideSet(j: Job, set: { [Player]: boolean })
	local label = Lines.capture.busyTag or "CAPTURING"
	for player in set do
		if not j.insideSet[player] then
			busy(player, label, true)
		end
	end
	for player in j.insideSet do
		if not set[player] then
			busy(player, label, false)
		end
	end
	j.insideSet = set
end

-- `forceKind` skips the roll (the forced vault draw, debug).
function CrewCall.trigger(forceKind: string?)
	if job then
		CrewCall.finish(false, true)
	end
	nextId += 1
	local kind = if forceKind and (forceKind ~= "vault" or VaultJob.available(World.wave))
		then forceKind
		else rollKind()
	local copy = copyFor(kind)
	local pillar = Room.randomPillar()
	-- Beacon sits beside the pillar, pushed toward the room center so it is reachable.
	local radius = if kind == "capture" then Config.SideJobCaptureRadius else Config.SideJobBeaconRadius
	local toCenter = if pillar.Magnitude > 0.1 then -pillar.Unit else Vector3.new(1, 0, 0)
	local position = pillar + toCenter * (Config.PillarSize / 2 + radius + 1)
	local endsAt = Workspace:GetServerTimeNow() + Config.SideJobDurationSec
	local thisJob: Job
	local beacon: Model? = nil
	local fill: BasePart? = nil
	if kind == "vault" then
		-- The vault: no random beacon, the door frame turns blue and F at the door opens the Safe dial.
		position = VaultJob.front()
		VaultJob.startJob(function(player)
			if job == thisJob and thisJob.active then
				Log.event("Call", "%s cracked the vault for Side Job #%d", player.Name, thisJob.id)
				CrewCall.finish(true)
			end
		end)
	elseif kind == "capture" then
		beacon, fill = buildCaptureBeacon(position)
	elseif isMinigame(kind) then
		-- The prompt opens the minigame at the beacon; a validated done finishes the job. Fails can retry.
		beacon = buildHackBeacon(position, "OPEN", copy.propName, 0, function(player)
			if job ~= thisJob or not thisJob.active then
				return
			end
			Minigames.open(player, kind, {
				position = position,
				onDone = function(p)
					if job == thisJob and thisJob.active then
						Log.event("Call", "%s finished the %s for Side Job #%d", p.Name, kind, thisJob.id)
						CrewCall.finish(true)
					end
				end,
			})
		end)
	else
		beacon = buildHackBeacon(
			position,
			Lines.job.promptAction,
			Lines.job.promptObject,
			Config.SideJobHoldSec,
			function(player)
				if job == thisJob and thisJob.active and PlayerState.isStanding(PlayerState.get(player)) then
					Log.event("Call", "%s hacked the terminal for Side Job #%d", player.Name, thisJob.id)
					CrewCall.finish(true)
				end
			end
		)
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
		insideSet = {},
		lastSent = 0,
		reminded = false,
	}
	job = thisJob

	World.fireRun("CallStart", {
		id = thisJob.id,
		jobKind = kind,
		kind = copy.kind,
		name = copy.name,
		crewLead = copy.crewLead,
		typeLabel = copy.typeLabel,
		text = copy.text,
		rewardLine = string.format(copy.rewardLine, Config.SideJobReward, Config.SideJobGold),
		rewardShort = string.format("+$%d · %dG", Config.SideJobReward, Config.SideJobGold),
		reward = Config.SideJobReward,
		gold = Config.SideJobGold,
		endsAt = endsAt,
		duration = Config.SideJobDurationSec,
		position = position,
		captureSec = Config.SideJobCaptureSec,
		markerHint = copy.markerHint,
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
	if j.beacon then
		j.beacon:Destroy()
	end
	updateInsideSet(j, {}) -- nobody is capturing a finished job
	local copy = copyFor(j.kind)
	if success then
		for _, p in World.runAudience() do
			local state = PlayerState.get(p)
			Economy.addEarned(state, Config.SideJobReward) -- x CASH GAIN
			state.gold += Config.SideJobGold
			state.jobsDone += 1
		end
		World.addObjective()
		-- The vault's reward is the room itself: no crate for that kind.
		if Config.SideJobRewardCrate and j.kind ~= "vault" then
			BigCrate.drop(j.position)
		end
		Heat.onJobDone() -- lands as +HeatJob at this wave's end
	elseif not silent then
		Heat.onJobFailed()
	end
	if j.kind == "vault" then
		VaultJob.jobEnded(success)
	end
	if silent then
		-- Run ended or debug reset: the card, pill and marker just go away on every client.
		World.fireRun("CallCleared", { id = j.id })
	else
		World.fireRun("CallEnd", {
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
			rewardLine = if success
				then string.format(copy.rewardLine, Config.SideJobReward, Config.SideJobGold)
				else "",
			toast = if success
				then string.format(Lines.doneToast, copy.name, Config.SideJobReward, Config.SideJobGold)
				else Lines.failToast,
		})
	end
	Log.event("Call", "Side Job #%d %s", j.id, if success then "complete, paid $" .. Config.SideJobReward else "failed")
end

-- Testing: the vault job is forced at every VaultJobEveryWaves wave (when the vault can be drawn).
local function vaultDue(wave: number): boolean
	local every = Config.VaultJobEveryWaves
	return every > 0 and wave % every == 0 and VaultJob.available(wave)
end

function CrewCall.onWaveStart(wave: number)
	if vaultDue(wave) then
		CrewCall.trigger("vault")
	elseif wave >= Config.SideJobFirstWave and (wave - Config.SideJobFirstWave) % Config.SideJobEveryWaves == 0 then
		CrewCall.trigger()
	end
end

function CrewCall.init()
	RunService.Heartbeat:Connect(function(dt)
		local j = job
		if not j or not j.active then
			return
		end
		local now = Workspace:GetServerTimeNow()
		if now >= j.endsAt then
			CrewCall.finish(false)
			return
		end
		-- Half-time reminder: the card comes back with a nudge while the job is still open.
		if not j.reminded and now >= j.endsAt - Config.SideJobDurationSec * (1 - Config.SideJobReminderPct) then
			j.reminded = true
			World.fireRun("CallReminder", { id = j.id, title = Lines.reminder.title, text = Lines.reminder.text })
			Log.event("Call", "Side Job #%d reminder at %d%%", j.id, math.round(Config.SideJobReminderPct * 100))
		end
		if j.kind == "capture" then
			local set = playersInside(j.position, Config.SideJobCaptureRadius)
			updateInsideSet(j, set)
			local inside = next(set) ~= nil
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
