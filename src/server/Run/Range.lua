--!strict
-- Brief 8: the training range, the walled bay behind the warehouse's north-west door (the hub's Range node). Only
-- the hub slot runs it. Step over the threshold and you are armed: your starter gun at Common at its Armory level
-- with a full mag (the record a run start builds), abilities live (RangeAbilities), the client's HUD in "range"
-- mode; step out and the gun is stowed, your placeables and fields are cleared and the hub HUD comes back. Nothing
-- in here pays, scores or persists: the hub slot's Combat / Enemy pay no cash, count no kills and feed no Jobs,
-- mastery or stats, and nothing hurts a player outside the range (PlayerState.damage).
-- Three dummies stand at the far end facing the door: Enemy rigs that take every hit (damage numbers, flinch,
-- element statuses, sparks) and never die, move or attack, each with a `DMG · DPS · HS` readout over it and a
-- RESET prompt (R) on its sign. One is a plated sponge: its plates fly off at the Heavy's HP shares and regrow
-- DummyPlateRegrowSec after the last one falls. Debug `Spawn at range` puts a moving target in (it only goes for
-- players in the range and never leaves it).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Fonts = require(Shared.Fonts)
local Ground = require(Shared.Ground)
local Slot = require(script.Parent.Slot)
local Enemy = require(script.Parent.Enemy)
local Abilities = require(script.Parent.Abilities)
local PlayerState = require(script.Parent.Parent.PlayerState)
local Log = require(script.Parent.Parent.Log)

local Range = {}

type Hit = { t: number, amount: number }
type PlateSpec = { index: number, template: BasePart, rel: CFrame }
type Dummy = {
	index: number,
	name: string,
	cframe: CFrame,
	plated: boolean,
	model: Model?,
	total: number,
	shots: number,
	heads: number,
	recent: { Hit },
	label: TextLabel?,
	plates: { PlateSpec },
	regrowToken: number,
}

local dummies: { Dummy } = {}
local byModel: { [Model]: Dummy } = {}
local GREY = Color3.fromRGB(120, 124, 132)
local RED = Color3.fromRGB(140, 30, 30)

local function hubMap(): any
	return require(script.Parent.Parent:FindFirstChild("HubMap") :: ModuleScript)
end

------------------------------------------------------------------ Presence
-- The hub nameplate follows the range (Hub.refreshTag hides it inside).
local function refreshPlate(player: Player)
	local Hub = require(script.Parent.Parent:FindFirstChild("Hub") :: ModuleScript) :: any
	Hub.refreshTag(player)
end

function Range.isIn(player: Player): boolean
	return PlayerState.get(player).inRange
end

local function enter(player: Player)
	local state = PlayerState.get(player)
	if state.inRange then
		return
	end
	state.inRange = true
	if player.Character then
		player.Character:SetAttribute("InRange", true) -- every client poses this character's gun (GunAnim)
	end
	-- The run start's record: the starter at Common at its Armory level, a full mag.
	state.held = PlayerState.starterHeld(state)
	state.offhand = nil -- Round 21: one gun in, the second slot empty, as at a run start
	state.activeSlot = 1
	PlayerState.refreshHeldVisual(state)
	PlayerState.applyCharacterStats(state) -- run walk speed inside (the hub's is HubWalkSpeedMult)
	refreshPlate(player) -- the hub nameplate is off in the range
	state.dirty = true
	Log.event("Range", "%s enter", player.Name)
end

local function leave(player: Player, why: string?)
	local state = PlayerState.get(player)
	if not state.inRange then
		return
	end
	state.inRange = false
	if player.Character then
		player.Character:SetAttribute("InRange", nil)
	end
	local n = Abilities.clearOwner(player)
	state.buffId = nil
	state.buffUntil = 0
	PlayerState.applyCharacterStats(state)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		hum.Health = hum.MaxHealth
	end
	state.dirty = true
	refreshPlate(player)
	Log.event(
		"Range",
		"%s leave%s%s",
		player.Name,
		if why then " (" .. why .. ")" else "",
		if n > 0 then string.format(", %d placeable%s cleared", n, if n == 1 then "" else "s") else ""
	)
end

------------------------------------------------------------------ Dummies
local function paint(d: Dummy)
	local label = d.label
	if not label then
		return
	end
	local now = os.clock()
	local window = math.max(0.5, Config.RangeDpsWindowSec)
	local sum = 0
	local keep = {}
	for _, h in d.recent do
		if now - h.t <= window then
			sum += h.amount
			table.insert(keep, h)
		end
	end
	d.recent = keep
	local dps = sum / window
	local hs = if d.shots > 0 then math.round(d.heads / d.shots * 100) else 0
	local function comma(n: number): string
		local s = tostring(math.floor(n + 0.5))
		local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
		return (out:gsub("^,", ""))
	end
	label.Text = string.format("DMG %s · DPS %s · HS %d%%", comma(d.total), comma(dps), hs)
end

local function reset(d: Dummy, who: string?)
	d.total = 0
	d.shots = 0
	d.heads = 0
	d.recent = {}
	paint(d)
	Log.event("Range", "reset dummy %d%s", d.index, if who then " (" .. who .. ")" else "")
end

function Range.resetAll(who: string?)
	for _, d in dummies do
		reset(d, who)
	end
end

local function regrow(d: Dummy)
	local model = d.model
	local data = model and Enemy.data(model)
	if not model or not data then
		return
	end
	for _, spec in d.plates do
		if data.plates[spec.index] then
			continue
		end
		local plate = spec.template:Clone()
		for _, c in plate:GetChildren() do
			if c:IsA("WeldConstraint") then
				c:Destroy()
			end
		end
		plate.CFrame = data.root.CFrame * spec.rel
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = data.root
		weld.Part1 = plate
		weld.Parent = plate
		plate.Parent = model
		data.plates[spec.index] = plate
	end
	data.hp = data.maxHP
	model:SetAttribute("HP", data.hp)
end

-- The dummy's brain: it stands, never attacks; the plated one sheds plates like a Heavy and grows them back.
local function brainFor(d: Dummy): any
	return {
		tick = function(data: any, api: any, _now: number)
			api.hold(data)
		end,
		onDamaged = function(data: any, api: any)
			if not d.plated then
				return
			end
			local share = data.hp / math.max(data.maxHP, 1)
			local dropped = false
			for i, pct in Config.HeavyPlateHpPcts do
				local plate = data.plates[i]
				if plate and share <= pct then
					data.plates[i] = nil
					api.dropPlate(data, plate)
					dropped = true
				end
			end
			if dropped then
				d.regrowToken += 1
				local my = d.regrowToken
				task.delay(Config.DummyPlateRegrowSec, function()
					if my == d.regrowToken then
						regrow(d)
					end
				end)
			end
		end,
	}
end

local function buildBoard(d: Dummy, model: Model)
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "DummyTag"
	gui.Adornee = head
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 90
	gui.Size = UDim2.fromOffset(190, 22)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	local label = Instance.new("TextLabel")
	label.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
	label.BackgroundTransparency = 0.25
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Fonts.mono
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(242, 230, 200)
	label.Text = ""
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = label
	gui.Parent = model
	d.label = label
	paint(d)
end

-- The sign in front of each dummy's feet: its number and the RESET prompt (R).
local function buildSign(d: Dummy, parent: Instance)
	local cf = d.cframe * CFrame.new(-2.6, 1.6, -2.2)
	local sign = Instance.new("Part")
	sign.Name = "DummySign" .. d.index
	sign.Anchored = true
	sign.CanCollide = false
	sign.Size = Vector3.new(1.8, 1.1, 0.15)
	sign.CFrame = cf
	sign.Color = Color3.fromRGB(26, 26, 32)
	sign.Material = Enum.Material.SmoothPlastic
	sign.Parent = parent
	local post = Instance.new("Part")
	post.Name = "Post"
	post.Anchored = true
	post.CanCollide = false
	post.Size = Vector3.new(0.15, cf.Position.Y - d.cframe.Position.Y, 0.15)
	post.CFrame = CFrame.new(cf.Position.X, (cf.Position.Y + d.cframe.Position.Y) / 2 - 0.5, cf.Position.Z)
	post.Color = Color3.fromRGB(60, 62, 70)
	post.Material = Enum.Material.Metal
	post.Parent = parent
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = sign
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.FontFace = Fonts.display
	text.TextScaled = true
	text.TextColor3 = Color3.fromHex("E8B64C")
	text.Text = "DUMMY " .. d.index
	text.Parent = gui
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Reset"
	prompt.ActionText = "RESET"
	prompt.ObjectText = "DUMMY " .. d.index
	prompt.KeyboardKeyCode = Enum.KeyCode.R
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = sign
	prompt.Triggered:Connect(function(player)
		reset(d, player.Name)
	end)
end

-- A default R15 rig (Players:CreateHumanoidModelFromDescription), in Rig.build's shape for Enemy.spawn. The plated
-- dummy gets a chest plate and a shoulder plate welded to its root (they fall at the Heavy's HP shares).
local STEEL = Color3.fromRGB(96, 104, 116)
local function buildR15(plated: boolean): any
	local ok, made = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if not ok or not made then
		Log.event("Range", "no R15 rig (%s): the dummy uses the enemy rig", tostring(made))
		return nil
	end
	local model = made :: Model
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	local head = model:FindFirstChild("Head")
	if not hum or not root or not root:IsA("BasePart") or not head or not head:IsA("BasePart") then
		model:Destroy()
		return nil
	end
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CollisionGroup = "Enemy"
		end
	end
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	local plates: { BasePart } = {}
	if plated then
		for i, spec in
			{
				{ Vector3.new(2.3, 1.6, 0.3), CFrame.new(0, 1, -0.75) },
				{ Vector3.new(3.4, 0.45, 1.5), CFrame.new(0, 1.85, 0) },
			}
		do
			local plate = Instance.new("Part")
			plate.Name = "Plate" .. i
			plate.Size = spec[1]
			plate.CFrame = root.CFrame * spec[2]
			plate.Color = STEEL
			plate.Material = Enum.Material.Metal
			plate.Massless = true
			plate.CanCollide = false
			plate.CollisionGroup = "Enemy"
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = plate
			weld.Parent = plate
			plate.Parent = model
			table.insert(plates, plate)
		end
	end
	return { model = model, root = root, head = head, humanoid = hum, plates = plates }
end

local function spawnDummy(d: Dummy)
	local built = buildR15(d.plated)
	local archetype = if built then "Henchman" elseif d.plated then "Heavy" else "Henchman"
	local model = Enemy.spawn(archetype, 1, d.cframe.Position, {
		dummy = true,
		elite = d.plated and not built,
		brain = brainFor(d),
		built = built,
	})
	local data = Enemy.data(model)
	if not data then
		return
	end
	if Config.DummyScale ~= 1 then
		pcall(function()
			model:ScaleTo(Config.DummyScale)
		end)
	end
	data.maxHP = Config.DummyHp
	data.hp = Config.DummyHp
	model:SetAttribute("MaxHP", data.maxHP)
	model:SetAttribute("HP", data.hp)
	model:SetAttribute("Dummy", true)
	model.Name = "RangeDummy" .. d.index
	data.root.Anchored = true
	-- Stand on the floor facing the door.
	local floor = Ground.y(d.cframe.Position + Vector3.new(0, 2, 0), d.cframe.Position.Y)
	local up = data.root.Size.Y / 2 + data.humanoid.HipHeight
	model:PivotTo(
		CFrame.lookAt(
			Vector3.new(d.cframe.X, floor + up, d.cframe.Z),
			Vector3.new(d.cframe.X, floor + up, d.cframe.Z) + d.cframe.LookVector
		)
	)
	-- A grey body (the plated one darker, under steel) and the red neon head so headshots read.
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= data.head and p.Transparency < 1 and not string.match(p.Name, "^Plate") then
			p.Color = if d.plated then Color3.fromRGB(70, 74, 84) else GREY
		end
	end
	local face = data.head:FindFirstChildOfClass("Decal")
	if face then
		face:Destroy()
	end
	data.head.Color = RED
	data.head.Material = Enum.Material.Neon
	data.headColor = RED
	d.plates = {}
	for i, plate in data.plates do
		table.insert(
			d.plates,
			{ index = i, template = plate:Clone(), rel = data.root.CFrame:ToObjectSpace(plate.CFrame) }
		)
	end
	d.model = model
	byModel[model] = d
	buildBoard(d, model)
end

local function build()
	local view = hubMap().view
	if not view or #view.dummies == 0 then
		Log.event("Range", "no Dummy nodes: the range has no targets")
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "RangeSigns"
	folder.Parent = hubMap().model or Workspace
	for i, node in view.dummies do
		if i > Config.DummyCount then
			break
		end
		local d: Dummy = {
			index = i,
			name = node.name,
			cframe = node.cframe,
			plated = node.plates and Config.DummyHeavyPlates,
			model = nil,
			total = 0,
			shots = 0,
			heads = 0,
			recent = {},
			label = nil,
			plates = {},
			regrowToken = 0,
		}
		table.insert(dummies, d)
		spawnDummy(d)
		buildSign(d, folder)
	end
	Log.event("Range", "%d dumm%s", #dummies, if #dummies == 1 then "y" else "ies")
end

------------------------------------------------------------------ Debug: Spawn at range
-- A moving target inside the range: it only goes for players in the range (Enemy) and is pulled back if it
-- wanders out. Kill all, or the range emptying, clears it.
local spawned: { [Model]: boolean } = {}

function Range.spawnEnemy(archetype: string, elite: boolean): Model?
	local view = hubMap().view
	local r = view and view.range
	if not r then
		return nil
	end
	-- Halfway between the door and the dummies.
	local p = r.cframe.Position
	local at = Vector3.new(p.X, Ground.y(p + Vector3.new(0, 4, 0), p.Y - r.size.Y / 2), p.Z)
	local model = Enemy.spawn(archetype, 1, at, { elite = elite })
	spawned[model] = true
	Log.event("Range", "debug spawned %s%s in the range", archetype, if elite then " (elite)" else "")
	return model
end

-- TITAN in the range (debug Spawn at range > Boss): the same moving-target rules.
function Range.spawnBoss(): Model?
	local view = hubMap().view
	local r = view and view.range
	if not r then
		return nil
	end
	local p = r.cframe.Position
	local at = Vector3.new(p.X, Ground.y(p + Vector3.new(0, 4, 0), p.Y - r.size.Y / 2), p.Z)
	local Boss = require(script.Parent:FindFirstChild("Boss") :: ModuleScript) :: any
	local model = Boss.spawn(Config.BossId, 1, at)
	if model then
		spawned[model] = true
		Log.event("Range", "debug spawned the boss in the range")
	end
	return model
end

local function anyoneIn(): boolean
	for _, p in Players:GetPlayers() do
		if PlayerState.get(p).inRange then
			return true
		end
	end
	return false
end

function Range.init()
	if not Slot.isHub then
		return
	end
	Enemy.onDummyHit = function(data: any, amount: number, _attacker: Player?, hit: any)
		local d = byModel[data.model]
		if not d then
			return
		end
		d.total += amount
		table.insert(d.recent, { t = os.clock(), amount = amount })
		if hit and not hit.tick and hit.dir then
			d.shots += 1
			if hit.headshot then
				d.heads += 1
			end
		end
	end
	task.spawn(function()
		-- The hub's nodes load after the slots start (Hub.init): wait for them.
		local t0 = os.clock()
		while not hubMap().loaded and os.clock() - t0 < 30 do
			task.wait(0.2)
		end
		build()
	end)
	local acc, paintAcc = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		paintAcc += dt
		if paintAcc >= 0.25 then
			paintAcc = 0
			for _, d in dummies do
				paint(d)
			end
		end
		if acc < 0.1 then
			return
		end
		acc = 0
		local Runs = require(script.Parent.Parent:FindFirstChild("Runs") :: ModuleScript) :: any
		local map = hubMap()
		for _, player in Players:GetPlayers() do
			local state = PlayerState.get(player)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hubbed = Runs.slotOf(player).isHub
			local inside = hubbed and root ~= nil and PlayerState.isStanding(state) and map.inRange(root.Position)
			if inside and not state.inRange then
				enter(player)
			elseif not inside and state.inRange then
				leave(player, if not hubbed then "joined a run" else nil)
			end
		end
		-- Debug enemies: back inside if they wander out; gone once nobody is in the range.
		local empty = not anyoneIn()
		for model in table.clone(spawned) do
			local data = Enemy.data(model)
			if not data then
				spawned[model] = nil
			elseif empty then
				spawned[model] = nil
				Enemy.kill(model, nil)
			elseif not map.inRange(data.root.Position, -1) then
				local r = map.view and map.view.range
				if r then
					model:PivotTo(CFrame.new(r.cframe.Position))
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local state = PlayerState.get(player)
		state.inRange = false
		Abilities.clearOwner(player)
	end)
end

return Range
