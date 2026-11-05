--!strict
-- Cash bags and gold bags (brief 4). Both are Parts with a beacon column and a hold-F prompt; a cash bag
-- pays match cash to every member, a gold bag ticks the team's Banked total (paid in full to everyone at
-- the summary). Wave-start spawns pick weighted spots far from the crew (BagSpots.Arena) up to
-- MaxActiveBags; bursts (boss body, the vault) bypass the cap. Uncollected bags persist until the run ends.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local BagSpots = require(Shared.BagSpots)
local Lines = require(Shared.CrewCall.Lines)
local PlayerState = require(script.Parent.PlayerState)
local Economy = require(script.Parent.Economy)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)

export type Bag = {
	id: number,
	kind: string, -- cash | gold
	model: Model,
	position: Vector3,
	wave: number,
	value: number,
	vault: boolean, -- dropped inside the vault (fizzles with the gas)
	active: boolean,
}

local Bags = {}

local CASH = Color3.fromHex("8FE3A1")
local CASH_BODY = Color3.fromRGB(47, 150, 85)
local GOLD = Color3.fromHex("E8B64C")
local DARK = Color3.fromRGB(26, 26, 31)

local effects = Workspace:WaitForChild("Effects")
local bags: { [number]: Bag } = {}
local nextId = 0

function Bags.count(): number
	local n = 0
	for _, b in bags do
		if b.active then
			n += 1
		end
	end
	return n
end

function Bags.valueFor(kind: string, wave: number): number
	if kind == "gold" then
		return math.round(Config.GoldBagValue * (1 + Config.GoldBagPerWave * wave))
	end
	return math.round(Config.CashBagBase * (1 + Config.CashBagPerWave * wave))
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function busy(player: Player, on: boolean)
	World.fireRun("PlayerBusy", { userId = player.UserId, name = player.Name, label = "GRABBING", on = on })
end

-- The bag itself: a green duffel with a $ or a gold case with a bar, a beacon column, a prompt.
local function build(b: Bag): Model
	local model = Instance.new("Model")
	model.Name = "Bag_" .. b.id
	local isGold = b.kind == "gold"
	local color = if isGold then GOLD else CASH
	local yaw = math.random() * math.pi * 2
	local body = part({
		Name = "Body",
		Size = if isGold then Vector3.new(2, 1.2, 1.5) else Vector3.new(2.2, 1.5, 1.3),
		CFrame = CFrame.new(b.position + Vector3.new(0, if isGold then 0.6 else 0.75, 0)) * CFrame.Angles(0, yaw, 0),
		Color = if isGold then GOLD else CASH_BODY,
		Material = if isGold then Enum.Material.Metal else Enum.Material.Fabric,
		CanQuery = true,
		Parent = model,
	})
	if isGold then
		-- A dark bar on the lid.
		part({
			Name = "Bar",
			Size = Vector3.new(1.2, 0.25, 0.5),
			CFrame = body.CFrame * CFrame.new(0, 0.72, 0),
			Color = DARK,
			Material = Enum.Material.SmoothPlastic,
			CanQuery = false,
			Parent = model,
		})
	else
		-- A neon strap and a $ on the top.
		part({
			Name = "Strap",
			Size = Vector3.new(2.25, 0.3, 1.35),
			CFrame = body.CFrame * CFrame.new(0, 0.3, 0),
			Color = CASH,
			Material = Enum.Material.Neon,
			CanQuery = false,
			Parent = model,
		})
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = body
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.LuckiestGuy
		label.Text = "$"
		label.TextScaled = true
		label.TextColor3 = CASH
		label.Parent = gui
	end
	local column = part({
		Name = "Beacon",
		Size = Vector3.new(1.2, 26, 1.2),
		CFrame = CFrame.new(b.position + Vector3.new(0, 13, 0)),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.78,
		CanQuery = false,
		Parent = model,
	})
	local _ = column
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = if isGold then "BANK" else "COLLECT"
	prompt.ObjectText = if isGold then "GOLD BAG" else "CASH BAG"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.HoldDuration = Config.BagCollectSec
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	prompt.PromptButtonHoldBegan:Connect(function(player: Player)
		busy(player, true)
	end)
	prompt.PromptButtonHoldEnded:Connect(function(player: Player)
		busy(player, false)
	end)
	prompt.Triggered:Connect(function(player: Player)
		Bags.collect(player, b)
	end)
	model.PrimaryPart = body
	model.Parent = effects
	return model
end

-- One bag at a floor point.
function Bags.spawnAt(kind: string, position: Vector3, vault: boolean?): Bag
	nextId += 1
	local b: Bag = {
		id = nextId,
		kind = kind,
		model = nil :: any,
		position = Vector3.new(position.X, Config.FloorTop, position.Z),
		wave = World.wave,
		value = Bags.valueFor(kind, World.wave),
		vault = vault == true,
		active = true,
	}
	b.model = build(b)
	bags[b.id] = b
	World.fireRun("BagSpawned", { id = b.id, kind = kind, position = b.position, value = b.value })
	return b
end

-- Nearest standing player to a point (huge when nobody stands).
local function crewDistance(point: Vector3): number
	local best = math.huge
	for _, player in World.runAudience() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and PlayerState.isStanding(PlayerState.get(player)) then
			best = math.min(best, (root.Position - point).Magnitude)
		end
	end
	return best
end

local function occupied(spot: Vector3): boolean
	for _, b in bags do
		if b.active and (b.position - spot).Magnitude < 2 then
			return true
		end
	end
	return false
end

-- A free arena spot weighted away from the crew; gold bags also keep GoldBagMinDistance when any spot allows it.
function Bags.pickSpot(kind: string): Vector3?
	local candidates = {}
	local weights = {}
	local total = 0
	local goldOk = {}
	for _, spot in BagSpots.Arena do
		if occupied(spot) then
			continue
		end
		local d = crewDistance(spot)
		local w = if d > Config.BagFarDistance
			then Config.BagFarMult
			elseif d < Config.BagNearDistance then Config.BagNearMult
			else 1
		table.insert(candidates, spot)
		table.insert(weights, w)
		table.insert(goldOk, d >= Config.GoldBagMinDistance)
		total += w
	end
	if #candidates == 0 then
		return nil
	end
	if kind == "gold" then
		local any = false
		for _, ok in goldOk do
			any = any or ok
		end
		if any then
			total = 0
			for i, ok in goldOk do
				if not ok then
					weights[i] = 0
				end
				total += weights[i]
			end
		end
	end
	local r = math.random() * total
	for i, w in weights do
		r -= w
		if r <= 0 then
			return candidates[i]
		end
	end
	return candidates[#candidates]
end

-- Wave start: the trickle, up to the cap. Fractional per-wave counts carry over (0.5 = every other wave).
local carry = { cash = 0, gold = 0 }

local function spawnKind(kind: string, perWave: number): number
	carry[kind] += perWave
	local n = 0
	while carry[kind] >= 1 do
		carry[kind] -= 1
		if Bags.count() >= Config.MaxActiveBags then
			break
		end
		local spot = Bags.pickSpot(kind)
		if spot then
			Bags.spawnAt(kind, spot)
			n += 1
		end
	end
	return n
end

function Bags.onWaveStart(wave: number)
	local cash = spawnKind("cash", Config.CashBagsPerWave)
	local gold = spawnKind("gold", Config.GoldBagsPerWave)
	if cash + gold > 0 then
		World.fireRun("BagsDropped", { cash = cash, gold = gold })
		Log.event("Bags", "wave %d: %d cash, %d gold dropped (%d active)", wave, cash, gold, Bags.count())
	end
end

-- A burst onto listed spots (the vault), cash first. Bypasses the cap.
function Bags.burstAtSpots(spots: { Vector3 }, cash: number, gold: number, vault: boolean)
	local order = table.clone(spots)
	for i = #order, 2, -1 do
		local k = math.random(i)
		order[i], order[k] = order[k], order[i]
	end
	local n = 0
	for i = 1, cash + gold do
		local spot = order[((i - 1) % math.max(#order, 1)) + 1]
		if not spot then
			break
		end
		local jitter = if i > #order
			then Vector3.new((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2)
			else Vector3.zero
		Bags.spawnAt(if i <= cash then "cash" else "gold", spot + jitter, vault)
		n += 1
	end
	World.fireRun("BagsDropped", { cash = cash, gold = gold, burst = true })
	Log.event("Bags", "burst: %d cash, %d gold%s", cash, gold, if vault then " in the vault" else "")
end

-- A burst in a ring around a point (the boss body). Bypasses the cap.
function Bags.burstAround(center: Vector3, cash: number, gold: number, radius: number)
	local total = cash + gold
	local spots = {}
	for i = 1, total do
		local a = (i - 1) / total * math.pi * 2 + math.random() * 0.4
		table.insert(
			spots,
			Vector3.new(center.X + math.cos(a) * radius, Config.FloorTop, center.Z + math.sin(a) * radius)
		)
	end
	Bags.burstAtSpots(spots, cash, gold, false)
end

local function remove(b: Bag, popped: boolean)
	if not b.active then
		return
	end
	b.active = false
	bags[b.id] = nil
	local model = b.model
	for _, p in model:GetDescendants() do
		if p:IsA("ProximityPrompt") then
			p.Enabled = false
		elseif p:IsA("BasePart") then
			TweenService
				:Create(p, TweenInfo.new(if popped then 0.2 else 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Size = if popped then Vector3.new(0.05, 0.05, 0.05) else p.Size,
					Transparency = 1,
				})
				:Play()
		end
	end
	task.delay(0.55, function()
		model:Destroy()
	end)
end

function Bags.collect(player: Player, b: Bag)
	if not b.active or not World.inRun() or not World.isInParty(player) then
		return
	end
	local state = PlayerState.get(player)
	if not PlayerState.isStanding(state) then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (root.Position - b.position).Magnitude > 12 then
		return
	end
	busy(player, false)
	remove(b, true)
	state.bags += 1
	state.dirty = true
	local toast: string
	if b.kind == "gold" then
		World.banked += b.value
		PlayerState.markAllDirty()
		toast = string.format(Lines.bagBanked, string.upper(player.Name), b.value)
	else
		for _, p in World.runAudience() do
			Economy.addCash(PlayerState.get(p), b.value)
		end
		toast = string.format(Lines.bagGrabbed, string.upper(player.Name), "$" .. tostring(b.value))
	end
	World.fireRun("BagCollected", {
		id = b.id,
		kind = b.kind,
		value = b.value,
		position = b.position,
		userId = player.UserId,
		name = player.Name,
		toast = toast,
		banked = World.banked,
	})
	Log.event(
		"Bags",
		"%s %s a %s bag worth %d (banked %d, %d bags left)",
		player.Name,
		if b.kind == "gold" then "banked" else "grabbed",
		b.kind,
		b.value,
		World.banked,
		Bags.count()
	)
end

-- The gas: every bag still inside the vault fizzles.
function Bags.fizzleVault()
	local n = 0
	for _, b in table.clone(bags) do
		if b.active and b.vault then
			remove(b, false)
			World.fireRun("BagFizzled", { id = b.id })
			n += 1
		end
	end
	if n > 0 then
		Log.event("Bags", "%d vault bag%s fizzled in the gas", n, if n == 1 then "" else "s")
	end
end

function Bags.clearAll()
	carry.cash, carry.gold = 0, 0
	for _, b in table.clone(bags) do
		remove(b, false)
		World.fireRun("BagFizzled", { id = b.id })
	end
end

-- Debug: one bag on a free spot near the player (any spot when none is free).
function Bags.debugSpawn(player: Player, kind: string)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local best: Vector3? = nil
	local bestDist = math.huge
	for _, spot in BagSpots.Arena do
		if occupied(spot) then
			continue
		end
		local d = if root then (spot - root.Position).Magnitude else math.random() * 100
		if d < bestDist then
			bestDist = d
			best = spot
		end
	end
	local at = best or (if root then root.Position + root.CFrame.LookVector * 6 else BagSpots.Arena[1])
	Bags.spawnAt(if kind == "gold" then "gold" else "cash", at)
	Remotes.Juice:FireClient(player, "Toast", { text = string.upper(kind) .. " BAG DROPPED" })
end

return Bags
