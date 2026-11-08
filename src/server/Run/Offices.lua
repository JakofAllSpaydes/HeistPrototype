--!strict
-- Round 19f: the glass offices on THE BANK, a small vault event without the vault. Four rooms behind blinds walls
-- (Office nodes: a room volume `<id>` and its door box `<id>_door`) stand locked. RAID THE OFFICE is a side job
-- (kind `office`, CrewCall): its beacon stands at an office door in an open zone, and F there opens one of
-- OfficeMinigames. Done, the job pays as usual and the office blows open: the asset's double glass door (every
-- part inside the door box) shatters away and the wall's blinds go up, OfficeCashBags + OfficeGoldBags drop inside
-- (scaled with the party like any burst), and a marker counts OfficeOpenSec. Then the room's alarm rings for
-- OfficeGasWarnSec, gas fills it for OfficeGasSec (OfficeGasDps, the gas tint), and the office seals: anyone
-- still inside is put outside the door, the bags left in the room fizzle, the door and blinds come back, and the
-- office can be drawn again after OfficeCooldownWaves.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(script.Parent.SlotRemotes)
local Lines = require(Shared.CrewCall.Lines)
local Ground = require(Shared.Ground)
local World = require(script.Parent.World)
local Log = require(script.Parent.Parent.Log)
local MapLoader = require(script.Parent.MapLoader)
local PlayerState = require(script.Parent.Parent.PlayerState)
local Pause = require(script.Parent.Pause)
local Alarms = require(script.Parent.Alarms)
local Bags = require(script.Parent.Bags)
local CrewCall = require(script.Parent.CrewCall)

local Offices = {}

type Saved = { part: BasePart, transparency: number, collide: boolean, query: boolean }
type State = {
	office: MapLoader.Office,
	phase: string, -- closed | job | open | warn | gas
	door: { Saved }, -- the door's leaves, handles and bars: gone while open
	blinds: { Saved }, -- the wall's blinds mesh (it spans the doorway): up while open
	readyWave: number, -- can be drawn again from this wave
	token: number,
	clouds: { BasePart },
}

local GAS = Color3.fromRGB(150, 220, 110)
local states: { [string]: State } = {}
local order: { State } = {}
local tinted: { [Player]: boolean } = {}
local lastTick = 0

local function onBank(): boolean
	return World.map == MapLoader.MAP_ID and MapLoader.loaded
end

local function save(part: BasePart): Saved
	return { part = part, transparency = part.Transparency, collide = part.CanCollide, query = part.CanQuery }
end

local function setGone(list: { Saved }, gone: boolean)
	for _, s in list do
		if s.part.Parent then
			s.part.Transparency = if gone then 1 else s.transparency
			s.part.CanCollide = if gone then false else s.collide
			s.part.CanQuery = if gone then false else s.query
		end
	end
end

-- Out of the room: from the room's centre through the door, flat.
local function outward(o: MapLoader.Office): Vector3
	local d = o.door.cframe.Position - o.room.cframe.Position
	local flat = Vector3.new(d.X, 0, d.Z)
	return if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
end

-- Where the job's beacon stands and where an ejected player lands: on the floor just outside the door.
function Offices.front(o: MapLoader.Office, extra: number?): Vector3
	local c = o.door.cframe.Position
	local half = math.min(o.door.size.X, o.door.size.Z) / 2
	local p = c + outward(o) * (half + (extra or Config.OfficeFrontStuds))
	return Ground.at(Vector3.new(p.X, c.Y - o.door.size.Y / 2 + 2, p.Z))
end

local function inside(o: MapLoader.Office, position: Vector3): boolean
	return MapLoader.inVolume(o.room.cframe, o.room.size, position)
end

local function playersInside(o: MapLoader.Office): { Player }
	local out = {}
	for _, p in World.runAudience() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and inside(o, root.Position) then
			table.insert(out, p)
		end
	end
	return out
end

local function clearClouds(s: State)
	for _, c in s.clouds do
		c:Destroy()
	end
	s.clouds = {}
end

local function fillCloud(s: State)
	clearClouds(s)
	local room = s.office.room
	local h = math.min(room.size.Y, Config.ZoneGasHeight)
	local p = Instance.new("Part")
	p.Name = "OfficeGas"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(room.size.X, h, room.size.Z)
	p.CFrame = room.cframe * CFrame.new(0, -room.size.Y / 2 + h / 2, 0)
	local e = Instance.new("ParticleEmitter")
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Rate = math.clamp(room.size.X * room.size.Z * Config.ZoneGasParticlesPerArea * 2, 20, 300)
	e.Lifetime = NumberRange.new(2.5, 4.5)
	e.Speed = NumberRange.new(0.5, 2)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 10) })
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Color = ColorSequence.new(GAS)
	e.Drag = 1
	e.Parent = p
	p.Parent = Workspace:FindFirstChild("Effects") or Workspace
	table.insert(s.clouds, p)
end

-- Glass shards out of the doorway as it blows.
local function shards(o: MapLoader.Office)
	local effects = Workspace:FindFirstChild("Effects") or Workspace
	local cf, size = o.door.cframe, o.door.size
	local out = outward(o)
	for _ = 1, Config.WindowShards * 2 do
		local s = Instance.new("Part")
		s.Size = Vector3.new(0.2 + math.random() * 0.6, 0.2 + math.random() * 0.6, 0.08)
		s.CFrame = cf
			* CFrame.new((math.random() - 0.5) * size.X, (math.random() - 0.5) * size.Y, (math.random() - 0.5) * size.Z)
			* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		s.Color = Color3.fromRGB(200, 225, 240)
		s.Material = Enum.Material.Glass
		s.Transparency = 0.3
		s.CanQuery = false
		s.CanTouch = false
		s.CollisionGroup = "Corpse"
		s.Parent = effects
		s.AssemblyLinearVelocity = out * (6 + math.random() * 10)
			+ Vector3.new((math.random() - 0.5) * 8, math.random() * 6, (math.random() - 0.5) * 8)
		TweenService:Create(s, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.4), {
			Transparency = 1,
		}):Play()
		task.delay(2.1, function()
			s:Destroy()
		end)
	end
end

local function tint(player: Player, on: boolean)
	if (tinted[player] == true) == on then
		return
	end
	tinted[player] = if on then true else nil
	Remotes.Juice:FireClient(player, "OfficeGasTint", { on = on })
end

local function alarmSource(o: MapLoader.Office): string
	return "office_" .. o.id
end

------------------------------------------------------------------ The cycle
-- Sealed: anyone inside is put outside the door, the room's bags fizzle, door and blinds back, quiet.
local function seal(s: State, instant: boolean?)
	local o = s.office
	s.token += 1
	for _, p in playersInside(o) do
		local at = Offices.front(o, Config.OfficeEjectStuds) + Vector3.new(0, 3, 0)
		local look = outward(o)
		local char = p.Character
		if char then
			char:PivotTo(CFrame.lookAt(at, at + look))
			Log.event("Office", "%s was inside %s as it sealed: moved out", p.Name, o.id)
		end
	end
	Bags.fizzleIn(o.room.cframe, o.room.size)
	setGone(s.door, false)
	setGone(s.blinds, false)
	clearClouds(s)
	Alarms.set(alarmSource(o), false)
	local was = s.phase
	s.phase = "closed"
	s.readyWave = World.wave + Config.OfficeCooldownWaves
	if not instant and was ~= "closed" and was ~= "job" then
		World.fireRun("OfficeState", {
			id = o.id,
			phase = "sealed",
			position = o.door.cframe.Position,
			toast = string.format(Lines.office.sealedToast, o.label),
		})
		Log.event("Office", "%s sealed; drawable again from wave %d", o.id, s.readyWave)
	end
end

local function startGas(s: State, my: number)
	if my ~= s.token or s.phase ~= "warn" then
		return
	end
	s.phase = "gas"
	fillCloud(s)
	lastTick = 0
	World.fireRun("OfficeState", {
		id = s.office.id,
		phase = "gas",
		position = s.office.door.cframe.Position,
		endsAt = Workspace:GetServerTimeNow() + Config.OfficeGasSec,
		toast = Lines.office.gasToast,
	})
	Log.event("Office", "%s gassed", s.office.id)
	Pause.delay(Config.OfficeGasSec, function()
		if my == s.token and s.phase == "gas" then
			seal(s)
		end
	end)
end

local function startWarn(s: State, my: number)
	if my ~= s.token or s.phase ~= "open" then
		return
	end
	s.phase = "warn"
	Alarms.set(alarmSource(s.office), true)
	World.fireRun("OfficeState", {
		id = s.office.id,
		phase = "warn",
		position = s.office.door.cframe.Position,
		endsAt = Workspace:GetServerTimeNow() + Config.OfficeGasWarnSec,
		toast = string.format(Lines.office.warnToast, Config.OfficeGasWarnSec),
	})
	Pause.delay(Config.OfficeGasWarnSec, function()
		startGas(s, my)
	end)
end

-- The minigame is done: the door blows, the blinds go up, the bags drop, the clock runs.
function Offices.open(id: string, by: Player?)
	local s = states[id]
	if not s or (s.phase ~= "closed" and s.phase ~= "job") then
		return
	end
	local o = s.office
	s.token += 1
	local my = s.token
	s.phase = "open"
	setGone(s.door, true)
	setGone(s.blinds, true)
	shards(o)
	-- The bags: spread over the room's floor, kept off the walls.
	local spots = {}
	local n = Config.OfficeCashBags + Config.OfficeGoldBags
	local inset = Config.OfficeBagInset
	local half = o.room.size / 2
	for _ = 1, n do
		local lx = (math.random() * 2 - 1) * math.max(0, half.X - inset)
		local lz = (math.random() * 2 - 1) * math.max(0, half.Z - inset)
		local p = o.room.cframe:PointToWorldSpace(Vector3.new(lx, -half.Y + 2, lz))
		table.insert(spots, Ground.at(p, 0.5))
	end
	Bags.burstAtSpots(spots, Config.OfficeCashBags, Config.OfficeGoldBags, false)
	World.fireRun("OfficeState", {
		id = id,
		phase = "open",
		position = o.door.cframe.Position,
		label = o.label,
		endsAt = Workspace:GetServerTimeNow() + Config.OfficeOpenSec,
		toast = string.format(Lines.office.openToast, o.label, Config.OfficeOpenSec),
		shake = Config.DoorOpenShake,
	})
	Log.event("Office", "%s opened wave %d by %s", id, World.wave, if by then by.Name else "debug")
	Pause.delay(Config.OfficeOpenSec, function()
		startWarn(s, my)
	end)
end

------------------------------------------------------------------ The side job's view (CrewCall.office)
local function available(s: State): boolean
	return s.phase == "closed" and World.wave >= s.readyWave and MapLoader.zoneOpen(s.office.zone)
end

local function anyAvailable(): boolean
	if not onBank() or World.wave < Config.OfficeMinWave then
		return false
	end
	for _, s in order do
		if available(s) then
			return true
		end
	end
	return false
end

-- Claim a random drawable office for a job: its id, label and where the beacon stands.
local function claim(): (string?, string?, Vector3?)
	local pool = {}
	for _, s in order do
		if available(s) then
			table.insert(pool, s)
		end
	end
	if #pool == 0 then
		return nil, nil, nil
	end
	local s = pool[math.random(#pool)]
	s.phase = "job"
	return s.office.id, s.office.label, Offices.front(s.office)
end

-- The job ran out (or was replaced) before the door opened: the office is drawable again.
local function release(id: string)
	local s = states[id]
	if s and s.phase == "job" then
		s.phase = "closed"
	end
end

------------------------------------------------------------------ Build and lifecycle
-- The door parts: geometry inside the door box no bigger than it. The blinds: thin geometry that spans the door
-- box (it hangs across the doorway).
local function build()
	for _, s in order do
		seal(s, true)
	end
	states = {}
	order = {}
	local bank = MapLoader.bank
	local geo = bank and bank:FindFirstChild("Geometry")
	if not geo then
		return
	end
	local all: { BasePart } = {}
	for _, d in geo:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(all, d)
		end
	end
	for _, o in MapLoader.offices do
		local door, blinds = {}, {}
		local doorMax = math.max(o.door.size.X, o.door.size.Y, o.door.size.Z)
		local center = o.door.cframe.Position
		for _, p in all do
			local biggest = math.max(p.Size.X, p.Size.Y, p.Size.Z)
			local thinnest = math.min(p.Size.X, p.Size.Y, p.Size.Z)
			if biggest <= doorMax * 1.2 and MapLoader.inVolume(o.door.cframe, o.door.size, p.Position, 0.3) then
				table.insert(door, save(p))
			elseif
				biggest > doorMax * 1.5
				and thinnest <= 0.5
				and p.Transparency < 1
				and MapLoader.inVolume(p.CFrame, p.Size, center, 0.6)
			then
				table.insert(blinds, save(p))
			end
		end
		local s: State = {
			office = o,
			phase = "closed",
			door = door,
			blinds = blinds,
			readyWave = 0,
			token = 0,
			clouds = {},
		}
		states[o.id] = s
		table.insert(order, s)
		Log.event("Office", "%s: %d door parts, %d blinds", o.id, #door, #blinds)
		if #door == 0 then
			Log.event("Office", "WARN %s: no geometry inside its door box (drag the _door node onto the door)", o.id)
		end
	end
end

-- Run start / hub: every office sealed, quiet and drawable.
function Offices.resetRun()
	for _, s in order do
		seal(s, true)
		s.readyWave = 0
	end
	for p in table.clone(tinted) do
		tint(p, false)
	end
	tinted = {}
end

-- Debug: blow the nearest closed office to `player` now (no job).
function Offices.debugOpen(player: Player): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local best: State? = nil
	local bestD = math.huge
	for _, s in order do
		if s.phase == "closed" or s.phase == "job" then
			local d = if root then (s.office.door.cframe.Position - root.Position).Magnitude else 0
			if d < bestD then
				best, bestD = s, d
			end
		end
	end
	if not best then
		return false
	end
	Offices.open(best.office.id, player)
	return true
end

function Offices.init()
	if not MapLoader.bank then
		return
	end
	build()
	local prev = MapLoader.onRead
	MapLoader.onRead = function()
		if prev then
			prev()
		end
		build()
	end
	CrewCall.office = {
		available = anyAvailable,
		claim = claim,
		release = release,
		open = Offices.open,
	}
	RunService.Heartbeat:Connect(function()
		local any = false
		for _, s in order do
			if s.phase == "gas" then
				any = true
			end
		end
		if not any and next(tinted) == nil then
			return
		end
		if not World.inRun() or World.runOver then
			Offices.resetRun()
			return
		end
		local inGas: { [Player]: boolean } = {}
		for _, s in order do
			if s.phase == "gas" then
				for _, p in playersInside(s.office) do
					inGas[p] = true
				end
			end
		end
		for p in inGas do
			tint(p, true)
		end
		for p in table.clone(tinted) do
			if not inGas[p] then
				tint(p, false)
			end
		end
		local t = Workspace:GetServerTimeNow()
		if t - lastTick >= Config.FieldTickSec and not Pause.active() then
			lastTick = t
			for p in inGas do
				if PlayerState.isStanding(PlayerState.get(p)) then
					PlayerState.damage(p, Config.OfficeGasDps * Config.FieldTickSec, "gas")
				end
			end
		end
	end)
end

return Offices
