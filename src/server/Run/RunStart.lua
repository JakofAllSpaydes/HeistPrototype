--!strict
-- Run start timeline (Config.IntroSec total, beats in Config.RunStartBeats). The server moves things: the
-- crew (players plus dummies up to SquadSize) vanishes into the van, the van drives from the yard through
-- the door and brakes beside the arena spawn, the crew steps out in a line in join order, heads recolor to
-- their mask color, control returns, the van drives off and is removed. Clients run the camera and the
-- animations off the same clock (RunStartUI).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Room = require(script.Parent.Room)
local World = require(script.Parent.World)
local PlayerState = require(script.Parent.Parent.PlayerState)
local Squad = require(script.Parent.Squad)
local Log = require(script.Parent.Parent.Log)
local Ground = require(Shared.Ground)

local RunStart = {}

local LINE_GAP = 4.5 -- studs between crew in the line (room to read each one)
local LINE_Z = 3 -- line sits this far south of the arena spawn
local VAN_GAP = 7 -- the van brakes this far west of the line's west end

-- Slot i of n in the crew line. The arena: centered on the arena spawn, facing north into the arena. Brief 7:
-- a map with a lineup CFrame (`base`, or the map's run start line) centers the line on it, facing its look.
function RunStart.lineCFrame(i: number, n: number, base: CFrame?): CFrame
	local b = base or Room.current().lineup
	if b then
		local look = Vector3.new(b.LookVector.X, 0, b.LookVector.Z)
		local facing = if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, -1)
		local right = Vector3.new(-facing.Z, 0, facing.X)
		local p = b.Position + right * ((i - (n + 1) / 2) * LINE_GAP)
		local at = Vector3.new(p.X, Ground.y(p) + 3, p.Z)
		return CFrame.lookAt(at, at + facing)
	end
	local x = Room.arenaSpawn.X + (i - (n + 1) / 2) * LINE_GAP
	return CFrame.new(x, Config.FloorTop + 3, Room.arenaSpawn.Z + LINE_Z)
end

-- The van's height over the floor (its pivot sits this far up in the yard).
local function vanLift(): number
	return Room.vanHome.Position.Y - Config.FloorTop
end

-- Where the van stops for a line of n: just west of it, still facing north (the arena), or on the map's Van node.
function RunStart.vanBrake(n: number): CFrame
	local node = Room.current().van
	if node then
		local look = Vector3.new(node.LookVector.X, 0, node.LookVector.Z)
		local p = node.Position
		local at = Vector3.new(p.X, Ground.y(p) + vanLift(), p.Z)
		return CFrame.lookAt(at, at + (if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, -1)))
	end
	local westEnd = RunStart.lineCFrame(1, n).Position.X
	return CFrame.new(westEnd - VAN_GAP, Room.vanHome.Position.Y, Room.arenaSpawn.Z + LINE_Z)
end

-- Where the van starts: the yard (the arena) or a drive-in from behind the map's Van node.
local function vanStart(vanTo: CFrame): CFrame
	if Room.current().van then
		return vanTo * CFrame.new(0, 0, 90)
	end
	return Room.vanHome
end

-- The party in join order: the line, the MVP tie-break, the summary rows.
function RunStart.roster(): { Player }
	local players = World.partyPlayers()
	table.sort(players, function(a, b)
		return PlayerState.get(a).joinIndex < PlayerState.get(b).joinIndex
	end)
	return players
end

function RunStart.dummyCount(): number
	return math.max(0, Config.SquadSize - #World.partyPlayers())
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

-- The van only exists during this animation: shown parked in the yard at t = 0, driven off and removed after.
local function showVan()
	local van = Room.van
	if van then
		van:PivotTo(Room.vanHome)
		van.Parent = Room.folder
	end
end

local function exitVan(from: CFrame)
	local van = Room.van
	if not van then
		return
	end
	-- The arena: on through the room; a map: back out the way it came (it faces the building it parked at).
	local away = if Room.current().van then CFrame.new(0, 0, 90) else CFrame.new(0, 0, -80)
	driveVan(from, from * away, Config.VanExitSec)
	van.Parent = nil
end

-- Yields Config.IntroSec. Rolls poses and mask colors, which the run end reuses.
function RunStart.play()
	local players = RunStart.roster()
	local dummyCount = RunStart.dummyCount()
	local n = #players + dummyCount
	local beats = Config.RunStartBeats
	local startedAt = Workspace:GetServerTimeNow()
	local vanTo = RunStart.vanBrake(n)
	local vanFrom = vanStart(vanTo)
	local roster = {}
	local line = {}
	local models: { Model? } = {}
	local hiddenParts: { [BasePart]: number } = {}
	local hiddenDecals: { [Decal]: number } = {}

	for i, p in players do
		local state = PlayerState.get(p)
		state.pose = math.random(#Config.Poses)
		-- The mask color is the equipped mask's (PlayerState.applyMask); dummies use Config.MaskColors.
		state.maskColor = PlayerState.maskOf(state).color
		local squad = PlayerState.squadEmote(state)
		roster[i] = {
			userId = p.UserId,
			name = p.Name,
			pose = state.pose,
			poseAnim = squad.animationId,
			poseHold = squad.holdSec,
			maskColor = state.maskColor,
			lineIndex = i,
		}
		line[i] = RunStart.lineCFrame(i, n)
		models[i] = p.Character
	end
	local dummies = Squad.spawn(dummyCount, #players + 1, function(slot)
		return RunStart.lineCFrame(slot, n)
	end)
	for k, d in dummies do
		local i = #players + k
		roster[i] = {
			userId = -k,
			name = d.name,
			pose = d.pose,
			maskColor = d.maskColor,
			lineIndex = i,
			model = d.model,
			dummy = true,
		}
		line[i] = RunStart.lineCFrame(i, n)
		models[i] = d.model
	end

	-- Into the van: anchored, invisible, parked inside the body.
	showVan()
	if vanFrom ~= Room.vanHome and Room.van then
		Room.van:PivotTo(vanFrom)
	end
	for _, char in models do
		if not char then
			continue
		end
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
		char:PivotTo(vanFrom)
	end

	World.fireRun("RunStartBegin", {
		startedAt = startedAt,
		players = roster,
		vanFrom = vanFrom,
		vanTo = vanTo,
		door = if Room.current().van then vanTo.Position else Room.doorPosition,
		-- Brief 7: on a map the line faces its lineup's look (the clients turn their shots with it).
		facing = if Room.current().lineup then (Room.current().lineup :: CFrame).LookVector else nil,
		line = line,
		beats = beats,
		introSec = Config.IntroSec,
	})
	Log.event("Run", "run start sequence, %d in the van (%d dummies), %.1fs", n, #dummies, Config.IntroSec)

	-- Beat 0: the van drives in and brakes as the doors beat lands.
	task.spawn(driveVan, vanFrom, vanTo, beats.doors)
	task.wait(beats.doors)
	World.fireRun("VanBrake", { position = vanTo.Position })

	-- Doors: the crew steps out in a line, join order, facing the arena.
	for i, char in models do
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

	-- Masks on: heads recolor to the mask color (players already wear their mask part from the hub).
	for i, char in models do
		local head = char and char:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			head.Color = Color3.fromHex(roster[i].maskColor)
		end
	end
	task.wait(math.max(0, Config.IntroSec - beats.masks))

	-- Control returns; the dummies go, the van drives off and is removed.
	for _, p in players do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.Anchored = false
		end
	end
	Squad.clear()
	task.spawn(exitVan, vanTo)
end

return RunStart
