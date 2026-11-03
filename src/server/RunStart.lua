--!strict
-- Run start timeline (Config.IntroSec total, beats in Config.RunStartBeats). The server moves things: the
-- crew vanishes into the van, the van drives from the yard through the door and brakes at the arena spawn,
-- the crew steps out in a line in join order, heads recolor to their mask color, control returns. Clients
-- run the camera and the animations off the same clock (RunStartUI).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Room = require(script.Parent.Room)
local PlayerState = require(script.Parent.PlayerState)
local Log = require(script.Parent.Log)

local RunStart = {}

local LINE_GAP = 3 -- studs between players in the line
local LINE_Z = 3 -- line sits this far south of the arena spawn
local VAN_X = -7 -- the van brakes west of the spawn; the crew lines up east of it

-- Where the van stops: beside the arena spawn, still facing north.
function RunStart.vanBrake(): CFrame
	local home = Room.vanHome
	return CFrame.new(Room.arenaSpawn.X + VAN_X, home.Position.Y, Room.arenaSpawn.Z + LINE_Z)
end

-- Slot i of n in the crew line, facing north into the arena.
function RunStart.lineCFrame(i: number, n: number): CFrame
	local x = Room.arenaSpawn.X + VAN_X + 6 + (i - 1) * LINE_GAP
	local _ = n
	return CFrame.new(x, 3, Room.arenaSpawn.Z + LINE_Z)
end

-- Players in join order: the line, the MVP tie-break, the summary rows.
function RunStart.roster(): { Player }
	local players = Players:GetPlayers()
	table.sort(players, function(a, b)
		return PlayerState.get(a).joinIndex < PlayerState.get(b).joinIndex
	end)
	return players
end

local function driveVan(from: CFrame, to: CFrame, sec: number)
	local van = Room.van
	if not van then
		return
	end
	local value = Instance.new("CFrameValue")
	value.Value = from
	local conn = value.Changed:Connect(function(v)
		van:PivotTo(v :: any)
	end)
	local tween = TweenService:Create(value, TweenInfo.new(sec, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Value = to,
	})
	tween:Play()
	tween.Completed:Wait()
	conn:Disconnect()
	value:Destroy()
	van:PivotTo(to)
end

-- Yields Config.IntroSec. Rolls poses and mask colors, which the run end reuses.
function RunStart.play()
	local players = RunStart.roster()
	local n = #players
	local beats = Config.RunStartBeats
	local startedAt = Workspace:GetServerTimeNow()
	local vanTo = RunStart.vanBrake()
	local roster = {}
	local line = {}
	local hiddenParts: { [BasePart]: number } = {}
	local hiddenDecals: { [Decal]: number } = {}

	for i, p in players do
		local state = PlayerState.get(p)
		state.pose = math.random(#Config.Poses)
		state.maskColor = Config.MaskColors[((i - 1) % #Config.MaskColors) + 1]
		roster[i] = { userId = p.UserId, name = p.Name, pose = state.pose, maskColor = state.maskColor, lineIndex = i }
		line[i] = RunStart.lineCFrame(i, n)
		-- Into the van: parked inside the body, anchored and invisible.
		local char = p.Character
		if char then
			local root = char:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				root.Anchored = true
			end
			for _, d in char:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 1 then
					hiddenParts[d] = d.Transparency
					d.Transparency = 1
				elseif d:IsA("Decal") and d.Transparency < 1 then
					hiddenDecals[d] = d.Transparency
					d.Transparency = 1
				end
			end
			char:PivotTo(Room.vanHome)
		end
	end

	Remotes.Juice:FireAllClients("RunStartBegin", {
		startedAt = startedAt,
		players = roster,
		vanFrom = Room.vanHome,
		vanTo = vanTo,
		door = Room.doorPosition,
		line = line,
		beats = beats,
		introSec = Config.IntroSec,
	})
	Log.event("Run", "run start sequence, %d in the van, %.1fs", n, Config.IntroSec)

	-- Beat 0: the van drives in and brakes as the doors beat lands.
	task.spawn(driveVan, Room.vanHome, vanTo, beats.doors)
	task.wait(beats.doors)
	Remotes.Juice:FireAllClients("VanBrake", { position = vanTo.Position })

	-- Doors: the crew steps out in a line, join order, facing the arena.
	for i, p in players do
		local char = p.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			char:PivotTo(line[i])
		end
	end
	for part, t in hiddenParts do
		if part.Parent then
			part.Transparency = t
		end
	end
	for decal, t in hiddenDecals do
		if decal.Parent then
			decal.Transparency = t
		end
	end
	task.wait(beats.masks - beats.doors)

	-- Masks on: heads recolor to the mask color.
	for i, p in players do
		local char = p.Character
		local head = char and char:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			head.Color = Color3.fromHex(roster[i].maskColor)
		end
	end
	task.wait(math.max(0, Config.IntroSec - beats.masks))

	-- Control returns.
	for _, p in players do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.Anchored = false
		end
	end
end

return RunStart
