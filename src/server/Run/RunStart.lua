--!strict
-- Run start timeline. Brief 8: first the departure in the warehouse hub (Config.HubDepartSec: the party fades
-- into the hub van, the garage rolls up, the van pulls out; Hub.depart), then the cut to the map's own drive-in
-- (Config.IntroSec, beats in Config.RunStartBeats, counted from the cut): the crew (players plus dummies up to
-- SquadSize) rides a copy of the hub van in from behind the map's Van node, it brakes, the crew steps out in a
-- line in join order on the Lineup node, heads recolor to their mask color, control returns, the van drives off
-- and is removed. Clients run the camera and the animations off the same clock (RunStartUI).
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
local Hub = require(script.Parent.Parent.Hub)

local RunStart = {}

local LINE_GAP = 4.5 -- studs between crew in the line (room to read each one)
local LINE_Z = 3 -- line sits this far south of the arena spawn
local VAN_GAP = 7 -- the van brakes this far west of the line's west end

-- Slot i of n in the crew line. The arena: centered on the arena spawn, facing north into the arena. Brief 7:
-- a map with a lineup CFrame (`base`, or the map's run start line) centers the line on it, facing its look.
-- Brief 8: the run start line steps clear of the (much bigger) asset van; RunStart.play works it out per run.
local lineShift = Vector3.zero

function RunStart.lineCFrame(i: number, n: number, base: CFrame?): CFrame
	local b = base or Room.current().lineup
	if b and not base then
		b = b + lineShift
	end
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

-- Brief 8: the arrival van is a copy of the hub's van (Hub.vanTemplate), its pivot at its underside; made once.
local arrival: Model? = nil
local function arrivalVan(): Model?
	if not arrival then
		arrival = Hub.vanTemplate()
		if arrival then
			arrival.Name = "ArrivalVan"
		end
	end
	return arrival
end

-- The van's pivot height over the floor (0: the copy's pivot is its underside).
local function vanLift(): number
	return if arrivalVan() then 0 else Room.vanHome.Position.Y - Config.FloorTop
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

-- Where the van starts: a drive-in from behind the map's Van node (its DriveIn studs).
local function driveIn(): number
	return Room.current().driveIn or Config.VanDriveInStuds
end

local function vanStart(vanTo: CFrame): CFrame
	if Room.current().van then
		return vanTo * CFrame.new(0, 0, driveIn())
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

-- Brief 8: the party's clients drive the van (VanDrive: a smooth local move between the same two CFrames, eased
-- the same way); the server only parks it at the start and the end. A server tween replicated in steps and juddered.
local function driveVan(from: CFrame, to: CFrame, sec: number, ease: string?)
	local van = arrivalVan()
	if not van then
		return
	end
	van:PivotTo(from)
	World.fireRun("VanDrive", {
		van = van,
		from = from,
		to = to,
		sec = sec,
		ease = ease or "out",
		startedAt = Workspace:GetServerTimeNow(),
	})
	task.wait(sec)
	van:PivotTo(to)
end

-- Move the line along `away` until no slot stands inside the van's footprint (plus a margin).
local function clearLine(n: number, vanTo: CFrame)
	lineShift = Vector3.zero
	local van = arrivalVan()
	if not van or not Room.current().lineup then
		return
	end
	local size = van:GetExtentsSize()
	local function clashes(): boolean
		for i = 1, n do
			local p = vanTo:PointToObjectSpace(RunStart.lineCFrame(i, n).Position)
			if math.abs(p.X) < size.X / 2 + 2.5 and math.abs(p.Z) < size.Z / 2 + 2.5 then
				return true
			end
		end
		return false
	end
	local mid = (RunStart.lineCFrame(1, n).Position + RunStart.lineCFrame(n, n).Position) / 2
	local away = Vector3.new(mid.X - vanTo.Position.X, 0, mid.Z - vanTo.Position.Z)
	away = if away.Magnitude > 0.1 then away.Unit else -vanTo.LookVector
	for _ = 1, 40 do
		if not clashes() then
			break
		end
		lineShift += away
	end
end

-- The arrival van only exists during this animation: shown at the start of the drive-in, driven off and removed.
local function showVan(at: CFrame)
	local van = arrivalVan()
	if van then
		van:PivotTo(at)
		van.Parent = Workspace
	end
end

local function exitVan(from: CFrame)
	local van = arrivalVan()
	if not van then
		return
	end
	-- Back out the way it came (it faces the building it parked at).
	local away = CFrame.new(0, 0, driveIn())
	driveVan(from, from * away, Config.VanExitSec, "in")
	van.Parent = nil
end

-- Yields Config.IntroSec. Rolls poses and mask colors, which the run end reuses.
function RunStart.play()
	local players = RunStart.roster()
	local dummyCount = RunStart.dummyCount()
	local n = #players + dummyCount
	local beats = Config.RunStartBeats
	local vanTo = RunStart.vanBrake(n)
	local vanFrom = vanStart(vanTo)
	clearLine(n, vanTo)
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

	-- Into the van: anchored, invisible. Brief 8: the players first ride the hub van out of the garage.
	local seat = Hub.vanSeat()
	for i, char in models do
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
		char:PivotTo(if seat and i <= #players then seat else vanFrom)
	end
	Hub.depart(players)
	-- The cut: the map's drive-in.
	for i, char in models do
		if char and i <= #players then
			char:PivotTo(vanFrom)
		end
	end
	showVan(vanFrom)
	local startedAt = Workspace:GetServerTimeNow()

	World.fireRun("RunStartBegin", {
		van = arrivalVan(),
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
