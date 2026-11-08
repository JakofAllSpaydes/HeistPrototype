--!strict
-- Door objectives on THE BANK (brief 7). Every Door node gets a generated prop under Workspace.Bank.DoorProps
-- from its Size and DoorStyle (chain: posts and a chain at knee height; shutter: a roll shutter filling the
-- opening; panel: a locked double door; wheel: the asset's own vault door, animated), an invisible blocker that
-- stops players, enemies and paths (a PathfindingModifier labelled Door), a sign board `UNLOCKS · WAVE N` and a
-- ProximityPrompt that only says LOCKED until the door is called. Nothing opens on a wave alone.
--
-- At its TriggerWave (the intermission before that wave; the vault draw for D4, step 6) the door rides the crew
-- call shell as kind `door`: MARLOW's card, the blue beacon, the floor chevrons for DoorPingDuration, the pill
-- with no clock. It supersedes that wave's side-job draw and holds the one objective slot until done; a side job
-- already ticking finishes first; two doors due at once queue by Priority. Hold F (any member, either part of a
-- group) for InteractTime: progress pauses on release and keeps its fill DoorHoldSec. Done: the prop breaks with a
-- flash and shake, DoorOpenCashReward to everyone, the opener's NICE WORK card, HeatJob at the wave's end, the
-- zone's spawn boxes, bag spots and job spots come on, and a zone-open bag burst drops. A door never closes
-- again (D4 is the vault: it closes with the seal).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Lines = require(Shared.CrewCall.Lines)
local Ground = require(Shared.Ground)
local MapLoader = require(script.Parent.MapLoader)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
local PlayerState = require(script.Parent.PlayerState)
local Bags = require(script.Parent.Bags)
local CrewCall = require(script.Parent.CrewCall)
local Pause = require(script.Parent.Pause)

local Doors = {}

type MeshEntry = { part: BasePart, closed: CFrame }
type Prop = {
	part: MapLoader.DoorPart,
	model: Model,
	blocker: BasePart,
	prompt: ProximityPrompt?,
	mesh: { MeshEntry },
}
type GroupState = {
	state: string, -- closed | queued | called | open
	ever: boolean, -- has opened at least once this run
	calledAt: number,
	progress: number,
	keepUntil: number,
	holders: { [Player]: boolean },
	lastSent: number,
	wasHeld: boolean,
}

local AMBER = Color3.fromHex("E8B64C")
local STEEL = Color3.fromRGB(64, 66, 72)
local SHUTTER = Color3.fromRGB(118, 122, 128)
local WOOD = Color3.fromRGB(92, 58, 40)

local props: { Prop } = {}
local groups: { [string]: GroupState } = {}
local queue: { string } = {}
local folder: Folder? = nil

local function onBank(): boolean
	return World.map == MapLoader.MAP_ID and MapLoader.loaded
end

local function stateOf(group: string): GroupState
	local g = groups[group]
	if not g then
		g = {
			state = "closed",
			ever = false,
			calledAt = 0,
			progress = 0,
			keepUntil = 0,
			holders = {},
			lastSent = 0,
			wasHeld = false,
		}
		groups[group] = g
	end
	return g
end

function Doors.isOpen(group: string): boolean
	local g = groups[group]
	return g ~= nil and g.state == "open"
end

function Doors.everOpened(group: string): boolean
	local g = groups[group]
	return g ~= nil and g.ever
end

local function signText(door: MapLoader.Door): string
	if door.triggerWave == 0 then
		return Lines.door.vaultSign
	end
	return string.format(Config.DoorSignText, door.triggerWave)
end

------------------------------------------------------------------ Props
local function part(props_: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	for k, v in props_ do
		(p :: any)[k] = v
	end
	return p
end

-- The sign board: text on both faces, at chest height on the prop.
local function sign(model: Model, cf: CFrame, size: Vector3, text: string)
	local floor = Ground.y(cf.Position, cf.Position.Y - size.Y / 2)
	local y = math.min(floor + 5, cf.Position.Y + size.Y / 2 - 0.8)
	local at = cf.Rotation + Vector3.new(cf.Position.X, math.max(y, floor + 2.5), cf.Position.Z)
	local board = part({
		Name = "Sign",
		Size = Vector3.new(math.min(7, size.X), 1.4, size.Z + 0.3),
		CFrame = at,
		Color = Color3.fromRGB(26, 26, 31),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
		Parent = model,
	})
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.LuckiestGuy
		label.TextScaled = true
		label.Text = text
		label.TextColor3 = AMBER
		label.Parent = gui
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.04, 0)
		pad.PaddingRight = UDim.new(0.04, 0)
		pad.PaddingTop = UDim.new(0.12, 0)
		pad.PaddingBottom = UDim.new(0.12, 0)
		pad.Parent = label
	end
end

local function dressChain(model: Model, cf: CFrame, size: Vector3)
	local half = size.X / 2
	local floor = Ground.y(cf.Position, cf.Position.Y - size.Y / 2)
	local base = cf.Rotation + Vector3.new(cf.Position.X, floor, cf.Position.Z)
	for _, sx in { -1, 1 } do
		part({
			Name = "Post",
			Size = Vector3.new(0.5, 3.4, 0.5),
			CFrame = base * CFrame.new(sx * (half - 0.25), 1.7, 0),
			Color = STEEL,
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = model,
		})
	end
	-- Links along a shallow sag at knee height.
	local n = math.max(6, math.floor(size.X / 0.55))
	for i = 1, n do
		local t = (i - 0.5) / n
		local x = -half + 0.25 + t * (size.X - 0.5)
		local sag = 0.5 * (1 - (2 * t - 1) ^ 2)
		part({
			Name = "Link",
			Size = Vector3.new(0.6, 0.25, 0.12),
			CFrame = base * CFrame.new(x, 2.4 - sag, 0) * CFrame.Angles(if i % 2 == 0 then math.rad(90) else 0, 0, 0),
			Color = Color3.fromRGB(150, 150, 156),
			Material = Enum.Material.Metal,
			CanCollide = false,
			CanQuery = false,
			Parent = model,
		})
	end
	part({
		Name = "Padlock",
		Size = Vector3.new(0.7, 0.8, 0.35),
		CFrame = base * CFrame.new(0, 1.6, 0),
		Color = AMBER,
		Material = Enum.Material.Metal,
		CanCollide = false,
		CanQuery = false,
		Parent = model,
	})
end

local function dressShutter(model: Model, cf: CFrame, size: Vector3)
	part({
		Name = "Slab",
		Size = Vector3.new(size.X, size.Y, math.max(0.3, size.Z * 0.5)),
		CFrame = cf,
		Color = SHUTTER,
		Material = Enum.Material.DiamondPlate,
		CanCollide = false,
		Parent = model,
	})
	-- Slats: a few darker strips across it.
	local slats = math.max(3, math.floor(size.Y / 2.2))
	for i = 1, slats do
		local y = -size.Y / 2 + (i - 0.5) * size.Y / slats
		part({
			Name = "Slat",
			Size = Vector3.new(size.X, 0.18, math.max(0.3, size.Z * 0.5) + 0.06),
			CFrame = cf * CFrame.new(0, y, 0),
			Color = Color3.fromRGB(84, 88, 94),
			Material = Enum.Material.Metal,
			CanCollide = false,
			CanQuery = false,
			Parent = model,
		})
	end
	part({
		Name = "Housing",
		Size = Vector3.new(size.X + 0.6, 1.4, size.Z + 1),
		CFrame = cf * CFrame.new(0, size.Y / 2 - 0.7, 0),
		Color = STEEL,
		Material = Enum.Material.Metal,
		CanCollide = false,
		Parent = model,
	})
end

local function dressPanel(model: Model, cf: CFrame, size: Vector3)
	for _, sx in { -1, 1 } do
		local leaf = part({
			Name = if sx < 0 then "LeafL" else "LeafR",
			Size = Vector3.new(size.X / 2 - 0.05, size.Y, math.max(0.4, size.Z * 0.6)),
			CFrame = cf * CFrame.new(sx * size.X / 4, 0, 0),
			Color = WOOD,
			Material = Enum.Material.WoodPlanks,
			CanCollide = false,
			Parent = model,
		})
		leaf:SetAttribute("Hinge", sx)
	end
	part({
		Name = "Bar",
		Size = Vector3.new(size.X * 0.9, 0.5, size.Z + 0.4),
		CFrame = cf * CFrame.new(0, -size.Y / 2 + 4, 0),
		Color = AMBER,
		Material = Enum.Material.Metal,
		CanCollide = false,
		CanQuery = false,
		Parent = model,
	})
end

-- The opened zone's direction from the door (the side a panel or wheel swings toward).
local function towardZone(dp: MapLoader.DoorPart): Vector3
	local z = dp.opens and MapLoader.zones[dp.opens]
	local c = dp.cframe.Position
	if z and z.parts[1] then
		local best, bestD = z.parts[1].cframe.Position, math.huge
		for _, v in z.parts do
			local d = (v.cframe.Position - c).Magnitude
			if d < bestD then
				best, bestD = v.cframe.Position, d
			end
		end
		local dir = Vector3.new(best.X - c.X, 0, best.Z - c.Z)
		if dir.Magnitude > 0.1 then
			return dir.Unit
		end
	end
	return dp.cframe.LookVector
end

local function buildProp(dp: MapLoader.DoorPart, door: MapLoader.Door): Prop
	local model = Instance.new("Model")
	model.Name = "DoorProp_" .. dp.name
	local cf, size = dp.cframe, dp.size
	-- The blocker: solid for players and enemies, never in the way of bullets; paths treat it as a wall.
	local blockSize = if dp.style == "chain" then Vector3.new(size.X, math.max(size.Y, 8), size.Z) else size
	local floor = Ground.y(cf.Position, cf.Position.Y - size.Y / 2)
	local blockCF = if dp.style == "chain"
		then cf.Rotation + Vector3.new(cf.Position.X, floor + blockSize.Y / 2, cf.Position.Z)
		else cf
	local blocker = part({
		Name = "Blocker",
		Size = blockSize,
		CFrame = blockCF,
		Transparency = 1,
		CanCollide = true,
		CanQuery = false,
		Parent = model,
	})
	local mod = Instance.new("PathfindingModifier")
	mod.Label = "Door"
	mod.PassThrough = false
	mod.Parent = blocker
	if dp.style == "chain" then
		dressChain(model, cf, size)
	elseif dp.style == "shutter" then
		dressShutter(model, cf, size)
	elseif dp.style == "panel" then
		dressPanel(model, cf, size)
	end
	sign(model, if dp.style == "chain" then blockCF else cf, blockSize, signText(door))
	local mesh: { MeshEntry } = {}
	if dp.mesh then
		for _, p in MapLoader.meshParts(cf, size, dp.mesh, dp.meshMargin) do
			table.insert(mesh, { part = p, closed = p.CFrame })
		end
	end
	model.Parent = folder
	return { part = dp, model = model, blocker = blocker, prompt = nil, mesh = mesh }
end

------------------------------------------------------------------ Opening animations
-- Swing a set of parts round a vertical axis through `hinge` by `angle` radians over `sec`.
local function swingParts(entries: { MeshEntry }, hinge: Vector3, angle: number, sec: number, from: number?)
	local start = from or 0
	task.spawn(function()
		local t0 = os.clock()
		while true do
			local s = math.clamp((os.clock() - t0) / math.max(sec, 0.01), 0, 1)
			local e = 1 - (1 - s) ^ 3
			local a = start + (angle - start) * e
			local rot = CFrame.new(hinge) * CFrame.Angles(0, a, 0) * CFrame.new(-hinge)
			for _, m in entries do
				if m.part.Parent then
					m.part.CFrame = rot * m.closed
				end
			end
			if s >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

-- The wheel door: the wheel spins about the door's face normal, then the door swings toward the opened zone.
-- `instant`: no spin, the door snaps open (dressing doors on load).
local function openWheel(prop: Prop, instant: boolean?)
	local dp = prop.part
	if #prop.mesh == 0 then
		return
	end
	local hinge = dp.cframe.Position
	for _, m in prop.mesh do
		if string.find(string.lower(m.part.Name), "hinge") then
			hinge = m.closed.Position
			break
		end
	end
	-- The face normal: the node's thinnest axis.
	local s = dp.size
	local normal = if s.X <= s.Y and s.X <= s.Z
		then dp.cframe.RightVector
		elseif s.Z <= s.Y then dp.cframe.LookVector
		else dp.cframe.UpVector
	local wheel: { MeshEntry } = {}
	local wheelCenter = dp.cframe.Position
	for _, m in prop.mesh do
		if string.find(string.lower(m.part.Name), "handle") then
			table.insert(wheel, m)
			wheelCenter = m.closed.Position
		end
	end
	local spinSec = if instant then 0 else Config.VaultWheelSpinSec
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < spinSec do
			local a = (os.clock() - t0) / spinSec * math.pi * 2
			local rot = CFrame.new(wheelCenter) * CFrame.fromAxisAngle(normal, a) * CFrame.new(-wheelCenter)
			for _, m in wheel do
				m.part.CFrame = rot * m.closed
			end
			RunService.Heartbeat:Wait()
		end
		for _, m in wheel do
			m.part.CFrame = m.closed
		end
		-- Swing toward the opened zone: pick the sign that moves the door's centre that way.
		local toward = towardZone(dp)
		local c = dp.cframe.Position
		local function moved(a: number): number
			local rot = CFrame.new(hinge) * CFrame.Angles(0, a, 0) * CFrame.new(-hinge)
			return ((rot * c) - c):Dot(toward)
		end
		local angle = if moved(math.rad(100)) >= moved(math.rad(-100)) then math.rad(100) else math.rad(-100)
		if not instant then
			World.fireRun("DoorThud", { position = c })
		end
		swingParts(prop.mesh, hinge, angle, if instant then 0 else Config.VaultDoorSwingSec)
	end)
end

local function breakProp(prop: Prop, instant: boolean?)
	local dp = prop.part
	prop.blocker.CanCollide = false
	local mod = prop.blocker:FindFirstChildOfClass("PathfindingModifier")
	if mod then
		mod.PassThrough = true
	end
	if prop.prompt then
		prop.prompt.Enabled = false
	end
	local model = prop.model
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and d.Name == "Sign" then
			d:Destroy()
		end
	end
	if dp.style == "wheel" then
		openWheel(prop, instant)
		return
	end
	if dp.style == "chain" then
		for _, d in model:GetChildren() do
			if d:IsA("BasePart") and (d.Name == "Link" or d.Name == "Padlock") then
				d.Anchored = false
				d.CanCollide = true
				d.CollisionGroup = "Corpse"
				d.AssemblyLinearVelocity =
					Vector3.new((math.random() - 0.5) * 6, 4 + math.random() * 4, (math.random() - 0.5) * 6)
				TweenService
					:Create(d, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.8), {
						Transparency = 1,
					})
					:Play()
			end
		end
	elseif dp.style == "shutter" then
		for _, d in model:GetChildren() do
			if d:IsA("BasePart") and (d.Name == "Slab" or d.Name == "Slat") then
				local top = dp.cframe * CFrame.new(0, dp.size.Y / 2 - 0.7, 0)
				TweenService:Create(d, TweenInfo.new(if instant then 0 else 0.9, Enum.EasingStyle.Quad), {
					Size = Vector3.new(d.Size.X, 0.2, d.Size.Z),
					CFrame = top,
				}):Play()
			end
		end
	elseif dp.style == "panel" then
		local toward = towardZone(dp)
		for _, d in model:GetChildren() do
			if d:IsA("BasePart") and d.Name == "Bar" then
				d:Destroy()
			elseif d:IsA("BasePart") and (d.Name == "LeafL" or d.Name == "LeafR") then
				local sx = d:GetAttribute("Hinge") :: number
				local hinge = (dp.cframe * CFrame.new(sx * dp.size.X / 2, 0, 0)).Position
				local function test(a: number): number
					local rot = CFrame.new(hinge) * CFrame.Angles(0, a, 0) * CFrame.new(-hinge)
					return ((rot * d.Position) - d.Position):Dot(toward)
				end
				local a = if test(math.rad(100)) >= test(math.rad(-100)) then math.rad(100) else math.rad(-100)
				swingParts({ { part = d, closed = d.CFrame } }, hinge, a, if instant then 0 else 0.7)
			end
		end
	end
end

------------------------------------------------------------------ State to clients
function Doors.sendState()
	if not onBank() or not World.inRunCycle() then
		-- The hub (or another map): no door beacons anywhere.
		World.fireRun("DoorState", { doors = {} })
		return
	end
	local list = {}
	for gid, door in MapLoader.doors do
		if door.triggerWave < 0 then
			continue
		end
		for _, dp in door.parts do
			local group = gid
			table.insert(list, {
				name = dp.name,
				group = group,
				position = dp.cframe.Position,
				label = dp.label,
				ping = door.pingText,
				sign = signText(door),
				state = stateOf(group).state,
			})
		end
	end
	World.fireRun("DoorState", { doors = list })
end

------------------------------------------------------------------ Opening
local function groupProps(group: string): { Prop }
	local out = {}
	local door = MapLoader.doors[group]
	if not door then
		return out
	end
	for _, prop in props do
		if table.find(door.parts, prop.part) then
			table.insert(out, prop)
		end
	end
	return out
end

local function zoneLabels(door: MapLoader.Door): string
	local out = {}
	for _, z in door.opens do
		local zone = MapLoader.zones[z]
		table.insert(out, if zone then zone.label else string.upper(z))
	end
	return table.concat(out, " · ")
end

-- Open a group: the props break, and (unless `quiet`) the zone-open burst, the logs and the call's finish.
-- `by` is the opener (nil for debug and the vault's own open).
function Doors.open(group: string, by: Player?, quiet: boolean?)
	local g = stateOf(group)
	local door = MapLoader.doors[group]
	if not door or g.state == "open" then
		return
	end
	local wasCalled = g.state == "called"
	local idx = table.find(queue, group)
	if idx then
		table.remove(queue, idx)
	end
	g.state = "open"
	g.ever = true
	g.progress = 0
	for p in g.holders do
		World.fireRun("PlayerBusy", { userId = p.UserId, name = p.Name, label = Lines.door.busyTag, on = false })
	end
	g.holders = {}
	for _, prop in groupProps(group) do
		breakProp(prop, quiet)
	end
	World.fireRun("DoorOpened", {
		group = group,
		position = door.parts[1].cframe.Position,
		label = door.label,
		shake = if quiet then 0 else Config.DoorOpenShake,
	})
	if not quiet then
		-- A freshly opened zone pays for the risk of moving: a burst on its spots, bypassing the cap.
		local spots = {}
		for _, s in MapLoader.bagSpots do
			if table.find(door.opens, s.zone) and s.zone ~= "vault" then
				table.insert(spots, s.position)
			end
		end
		if #spots > 0 and (Config.ZoneOpenCashBags + Config.ZoneOpenGoldBags) > 0 then
			Bags.burstAtSpots(spots, Config.ZoneOpenCashBags, Config.ZoneOpenGoldBags, false)
		end
		Log.event(
			"Door",
			"%s opened wave %d by %s t=%.1f",
			group,
			World.wave,
			if by then by.Name else "debug",
			if g.calledAt > 0 then os.clock() - g.calledAt else 0
		)
		Doors.openedLog = Doors.openedLog or {}
		table.insert(Doors.openedLog, { group = group, wave = World.wave, by = if by then by.Name else "debug" })
	end
	if wasCalled then
		CrewCall.finishDoor(group, by)
	end
	Doors.sendState()
	Doors.pump()
end
Doors.openedLog = {} :: { { group: string, wave: number, by: string } }

-- Close a group again (the vault's D4 at the seal; debug Close all doors): fresh props, the asset door back.
function Doors.close(group: string)
	local g = stateOf(group)
	g.state = "closed"
	g.progress = 0
	g.holders = {}
	for i, prop in props do
		if table.find((MapLoader.doors[group] or { parts = {} }).parts, prop.part) then
			for _, m in prop.mesh do
				if m.part.Parent then
					m.part.CFrame = m.closed
				end
			end
			prop.model:Destroy()
			local door = MapLoader.doors[group] :: MapLoader.Door
			local fresh = buildProp(prop.part, door)
			props[i] = fresh
			Doors.attachPrompt(fresh, group, door)
		end
	end
	Doors.sendState()
end

------------------------------------------------------------------ Calls and the hold
-- The prompt on each prop: LOCKED · WAVE N until called, then a hold of the group's remaining time.
function Doors.attachPrompt(prop: Prop, group: string, door: MapLoader.Door)
	if door.triggerWave == 0 or door.triggerWave < 0 then
		return -- D4 is the vault's Safe dial (VaultJob); dressing doors never prompt
	end
	local p = Instance.new("ProximityPrompt")
	p.KeyboardKeyCode = Enum.KeyCode.F
	p.RequiresLineOfSight = false
	p.MaxActivationDistance = math.max(10, prop.part.size.X / 2 + 4)
	p.ActionText = Lines.door.lockedAction
	p.ObjectText = signText(door)
	p.HoldDuration = 0
	p.Parent = prop.blocker
	prop.prompt = p
	p.PromptButtonHoldBegan:Connect(function(player: Player)
		local g = stateOf(group)
		if g.state ~= "called" or not World.isInParty(player) then
			return
		end
		g.holders[player] = true
		World.fireRun(
			"PlayerBusy",
			{ userId = player.UserId, name = player.Name, label = Lines.door.busyTag, on = true }
		)
	end)
	p.PromptButtonHoldEnded:Connect(function(player: Player)
		local g = stateOf(group)
		if g.holders[player] then
			g.holders[player] = nil
			World.fireRun(
				"PlayerBusy",
				{ userId = player.UserId, name = player.Name, label = Lines.door.busyTag, on = false }
			)
		end
	end)
	p.Triggered:Connect(function(player: Player)
		local g = stateOf(group)
		if g.state == "called" and World.isInParty(player) and PlayerState.isStanding(PlayerState.get(player)) then
			Doors.open(group, player)
		end
	end)
end

local function setPrompts(group: string, called: boolean)
	local door = MapLoader.doors[group]
	if not door then
		return
	end
	local g = stateOf(group)
	for _, prop in groupProps(group) do
		local p = prop.prompt
		if p then
			p.ActionText = if called then Lines.door.promptAction else Lines.door.lockedAction
			p.ObjectText = if called then door.label else signText(door)
			p.HoldDuration = if called then math.max(0.1, (1 - g.progress) * door.interactTime) else 0
			p.Enabled = g.state ~= "open"
		end
	end
end

-- Start the next queued door when the objective slot is free.
function Doors.pump()
	if not onBank() or not World.inRun() or CrewCall.busy() or #queue == 0 then
		return
	end
	local group = table.remove(queue, 1) :: string
	local door = MapLoader.doors[group]
	local g = stateOf(group)
	if not door or g.state ~= "queued" then
		return Doors.pump()
	end
	g.state = "called"
	g.calledAt = os.clock()
	setPrompts(group, true)
	-- The chevrons and the beacon point at the part nearest the crew.
	local crew, n = Vector3.zero, 0
	for _, p in World.runAudience() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			crew += root.Position
			n += 1
		end
	end
	crew = if n > 0 then crew / n else door.parts[1].cframe.Position
	local target = door.parts[1].cframe.Position
	for _, dp in door.parts do
		if (dp.cframe.Position - crew).Magnitude < (target - crew).Magnitude then
			target = dp.cframe.Position
		end
	end
	CrewCall.triggerDoor({
		group = group,
		position = Ground.at(target),
		name = door.pingText,
		label = door.label,
		line = Lines.door.lines[group] or Lines.door.lines.default,
		cashReward = door.cashReward,
		opens = zoneLabels(door),
	})
	if n > 0 then
		World.fireRun("VaultArrows", { from = crew, to = Ground.at(target), sec = Config.DoorPingDuration })
	end
	World.fireRun("DoorPing", { group = group, sec = Config.DoorPingDuration })
	Doors.sendState()
end

-- Doors due by `wave` join the queue (by Priority) and the first one takes the slot when it is free.
local function due(wave: number)
	if not onBank() then
		return
	end
	local added = {}
	for gid, door in MapLoader.doors do
		local g = stateOf(gid)
		if door.triggerWave > 0 and door.triggerWave <= wave and g.state == "closed" then
			g.state = "queued"
			table.insert(added, gid)
			Log.event("Door", "%s trigger wave %d", gid, wave)
		end
	end
	for _, gid in added do
		table.insert(queue, gid)
	end
	table.sort(queue, function(a, b)
		return (MapLoader.doors[a] and MapLoader.doors[a].priority or 0)
			< (MapLoader.doors[b] and MapLoader.doors[b].priority or 0)
	end)
	Doors.pump()
end

-- The intermission before `nextWave` (and every wave start, for wave 1 and debug wave jumps).
function Doors.onIntermission(nextWave: number)
	due(nextWave)
end
function Doors.onWaveStart(wave: number)
	due(wave)
end

-- Does a door own (or wait for) the objective slot? Then the wave's side-job draw is skipped.
function Doors.supersedes(): boolean
	if not onBank() then
		return false
	end
	if #queue > 0 then
		return true
	end
	for _, g in groups do
		if g.state == "called" then
			return true
		end
	end
	return false
end

------------------------------------------------------------------ Zone gates
-- A zone is open when no door opens it (the street) or a door that opens it is open.
local function zoneOpen(zone: string): boolean
	local gated = false
	for gid, door in MapLoader.doors do
		if door.triggerWave >= 0 and table.find(door.opens, zone) then
			gated = true
			if Doors.isOpen(gid) then
				return true
			end
		end
	end
	return not gated
end

local function boxOpen(b: any): boolean
	if b.requiresDoor then
		local ok = if b.doorEver then Doors.everOpened(b.requiresDoor) else Doors.isOpen(b.requiresDoor)
		if not ok then
			return false
		end
	end
	if b.whileVault and not Doors.isOpen(MapLoader.vaultRoom and MapLoader.vaultRoom.door or "D4") then
		return false
	end
	if b.doorEver then
		return true
	end
	return zoneOpen(b.zone)
end

------------------------------------------------------------------ Run lifecycle
-- Build every prop from the nodes (load, Recompute nodes). Doors with TriggerWave -1 open at once.
function Doors.build()
	for _, prop in props do
		for _, m in prop.mesh do
			if m.part.Parent then
				m.part.CFrame = m.closed
			end
		end
		prop.model:Destroy()
	end
	props = {}
	local bank = MapLoader.bank
	if not bank then
		return
	end
	local f = bank:FindFirstChild("DoorProps")
	if not f then
		local nf = Instance.new("Folder")
		nf.Name = "DoorProps"
		nf.Parent = bank
		f = nf
	end
	folder = f :: Folder
	for gid, door in MapLoader.doors do
		for _, dp in door.parts do
			local prop = buildProp(dp, door)
			table.insert(props, prop)
			Doors.attachPrompt(prop, gid, door)
		end
	end
	Doors.resetRun()
end

-- Run start / hub / debug Close all doors: every door closed (dressing doors open), nothing queued.
function Doors.resetRun()
	queue = {}
	Doors.openedLog = {}
	for gid, door in MapLoader.doors do
		local g = stateOf(gid)
		if g.state == "open" and door.triggerWave >= 0 then
			Doors.close(gid)
		end
		g.state = "closed"
		g.ever = false
		g.calledAt = 0
		g.progress = 0
		g.holders = {}
		setPrompts(gid, false)
		if door.triggerWave < 0 then
			Doors.open(gid, nil, true)
		end
	end
	MapLoader.setHatch(false, true)
	Doors.sendState()
end

function Doors.init()
	if not MapLoader.bank then
		return
	end
	Doors.build()
	MapLoader.zoneOpen = zoneOpen
	MapLoader.boxOpen = boxOpen
	MapLoader.onRead = Doors.build
	CrewCall.onSlotFree = Doors.pump
	CrewCall.supersedes = Doors.supersedes

	-- The hold: any standing holder feeds the group; released, it keeps its fill DoorHoldSec, then resets.
	RunService.Heartbeat:Connect(function(dt)
		if Pause.active() or not onBank() then
			return
		end
		local now = os.clock()
		for gid, g in groups do
			if g.state ~= "called" then
				continue
			end
			local door = MapLoader.doors[gid]
			if not door then
				continue
			end
			local holder: Player? = nil
			for p in g.holders do
				if p.Parent and PlayerState.isStanding(PlayerState.get(p)) then
					holder = p
					break
				end
			end
			local before = g.progress
			if holder then
				g.progress = math.min(1, g.progress + dt / math.max(door.interactTime, 0.1))
				g.keepUntil = now + Config.DoorHoldSec
			elseif g.progress > 0 and now > g.keepUntil then
				g.progress = 0
				setPrompts(gid, true)
			end
			if g.progress ~= before and (now - g.lastSent > 0.1 or g.progress == 0 or g.progress >= 1) then
				g.lastSent = now
				World.fireRun("DoorProgress", {
					group = gid,
					progress = g.progress,
					byId = if holder then holder.UserId else nil,
					holdSec = door.interactTime,
				})
			end
			-- Released: the next hold's ring covers only what is left.
			if g.wasHeld and not holder then
				setPrompts(gid, true)
			end
			g.wasHeld = holder ~= nil
			if holder and g.progress >= 1 then
				Doors.open(gid, holder)
			end
		end
	end)
end

return Doors
