--!strict
-- Cash bags and gold bags (brief 4). Both are Parts with a beacon column; a cash bag pays match cash to every
-- member, a gold bag ticks the team's Banked total (paid in full to everyone at the summary). Wave-start spawns
-- pick weighted spots far from the crew (BagSpots.Arena) up to MaxActiveBags; bursts (boss body, the vault)
-- bypass the cap. Uncollected bags persist until the run ends.
--
-- Pickup has no button (round 18). Every frame each standing party member within BagStartRadius of a free bag
-- claims one (a bag that already has fill first, else the nearest) and fills it over BagChannelSec; it stays
-- theirs until they step past BagKeepRadius, go down or the run stops. A full bag is collected and the next one
-- in reach is claimed the same frame, so walking through a pile empties it in sequence; bags started within
-- BagStreakWindowSec of the last pickup fill faster (BagStreakMult per bag, floor BagStreakMinMult). A bag
-- someone leaves keeps its fill for BagHoldSec, then drains at BagDrainPerSec; anyone may claim it meanwhile and
-- carry on from there. A claimed bag is skipped by everyone else, so two players in a pile take different bags.
-- Clients draw it from the model's Progress (0..1) / By (userId) / Kind attributes (client BagChannel.lua).
-- Everything is dt-driven inside a loop that stands still while Pause.active(), so a pause freezes it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Ground = require(Shared.Ground)
local Room = require(script.Parent.Room)
local Lines = require(Shared.CrewCall.Lines)
local PlayerState = require(script.Parent.PlayerState)
local Economy = require(script.Parent.Economy)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
local RunEvents = require(script.Parent.RunEvents)
local Pause = require(script.Parent.Pause)

export type Bag = {
	id: number,
	kind: string, -- cash | gold
	model: Model,
	position: Vector3,
	wave: number,
	value: number,
	vault: boolean, -- dropped inside the vault (fizzles with the gas)
	active: boolean,
	progress: number, -- fill 0..1
	by: Player?, -- who is filling it now
	idle: number, -- seconds unclaimed since it was last filled (hold, then drain)
	shown: number, -- last Progress attribute written
	shownBy: number, -- last By attribute written
}

-- One per party member in a run: the bag they are filling and their pickup streak.
type Channel = {
	bag: Bag?,
	streak: number, -- bags picked in a row
	idle: number, -- seconds with nothing to fill
	busyOn: boolean, -- teammates see GRABBING
}

local Bags = {}

local CASH = Color3.fromHex("8FE3A1")
local CASH_BODY = Color3.fromRGB(47, 150, 85)
local GOLD = Color3.fromHex("E8B64C")
local DARK = Color3.fromRGB(26, 26, 31)

local effects = Workspace:WaitForChild("Effects")
local bags: { [number]: Bag } = {}
local channels: { [Player]: Channel } = {}
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

-- The bag itself: a green duffel with a $ or a gold case with a bar, a beacon column. No prompt: standing
-- near it fills it (the channel loop below).
local function build(b: Bag): Model
	local model = Instance.new("Model")
	model.Name = "Bag_" .. b.id
	model:SetAttribute("Kind", b.kind)
	model:SetAttribute("Progress", 0)
	model:SetAttribute("By", 0)
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
		position = Ground.at(position),
		wave = World.wave,
		value = Bags.valueFor(kind, World.wave),
		vault = vault == true,
		active = true,
		progress = 0,
		by = nil,
		idle = 0,
		shown = 0,
		shownBy = 0,
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

-- Brief 7: the door system installs this on THE BANK so spots in closed zones (and the sealed vault) never draw.
Bags.spotOpen = nil :: ((Room.BagSpot) -> boolean)?

-- A free spot on the map weighted away from the crew (x BagOtherZoneMult outside the crew zone); gold bags need
-- a Gold spot and keep GoldBagMinDistance when any spot allows it.
function Bags.pickSpot(kind: string): Vector3?
	local candidates = {}
	local weights = {}
	local total = 0
	local goldOk = {}
	local open = Bags.spotOpen
	for _, s in Room.current().bagSpots do
		local spot = s.position
		if occupied(spot) or (open and not open(s)) or (kind == "gold" and not s.gold) then
			continue
		end
		local d = crewDistance(spot)
		local w = (
			if d > Config.BagFarDistance
				then Config.BagFarMult
				elseif d < Config.BagNearDistance then Config.BagNearMult
				else 1
		) * (if s.zone ~= World.crewZone then Config.BagOtherZoneMult else 1)
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

-- Round 19c: bag counts scale with the party: x (1 + BagPartyScale per member past the first).
function Bags.partyMult(): number
	return 1 + Config.BagPartyScale * math.max(0, #World.partyPlayers() - 1)
end

local function scaled(n: number): number
	return math.max(if n > 0 then 1 else 0, math.round(n * Bags.partyMult()))
end

local function spawnKind(kind: string, perWave: number): number
	carry[kind] += perWave * Bags.partyMult()
	local n = 0
	while carry[kind] >= 1 do
		carry[kind] -= 1
		if Bags.count() >= math.round(Config.MaxActiveBags * Bags.partyMult()) then
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

-- A burst onto listed spots (the vault), cash first. Bypasses the cap. Counts scale with the party.
local function burst(spots: { Vector3 }, cash: number, gold: number, vault: boolean)
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

function Bags.burstAtSpots(spots: { Vector3 }, cash: number, gold: number, vault: boolean)
	burst(spots, scaled(cash), scaled(gold), vault)
end

-- A burst in a ring around a point (the boss body). Bypasses the cap.
function Bags.burstAround(center: Vector3, cash: number, gold: number, radius: number)
	cash, gold = scaled(cash), scaled(gold)
	local total = cash + gold
	local spots = {}
	for i = 1, total do
		local a = (i - 1) / total * math.pi * 2 + math.random() * 0.4
		table.insert(
			spots,
			Ground.at(Vector3.new(center.X + math.cos(a) * radius, center.Y, center.Z + math.sin(a) * radius))
		)
	end
	burst(spots, cash, gold, false)
end

local function remove(b: Bag, popped: boolean)
	if not b.active then
		return
	end
	b.active = false
	b.by = nil
	bags[b.id] = nil
	local model = b.model
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
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

local function rootOf(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Within `radius` studs of the bag on the floor plane (and not a floor above or below).
local function within(root: BasePart, b: Bag, radius: number): boolean
	local d = root.Position - b.position
	return math.abs(d.Y) <= Config.BagKeepRadius and Vector2.new(d.X, d.Z).Magnitude <= radius
end

-- `streak` is the player's pickup streak before this bag (for the log and the client's rising tick).
function Bags.collect(player: Player, b: Bag, streak: number?): boolean
	if not b.active or not World.inRun() or not World.isInParty(player) then
		return false
	end
	local state = PlayerState.get(player)
	if not PlayerState.isStanding(state) then
		return false
	end
	local root = rootOf(player)
	if not root or not within(root, b, Config.BagKeepRadius + 2) then
		return false
	end
	remove(b, true)
	state.bags += 1
	state.dirty = true
	RunEvents.emit(player, "bag", 1) -- brief 6 Jobs
	local toast: string
	if b.kind == "gold" then
		World.banked += b.value
		for _, p in World.runAudience() do
			RunEvents.emit(p, "goldBanked", b.value) -- the team's banked total counts for everyone
		end
		PlayerState.markAllDirty()
		toast = string.format(Lines.bagBanked, string.upper(player.Name), b.value)
	else
		for _, p in World.runAudience() do
			Economy.addEarned(PlayerState.get(p), b.value) -- each member's own CASH GAIN
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
		streak = streak or 0,
	})
	-- Round 19c: the last vault bag picked up takes the vault's CLEAN IT OUT marker down.
	if b.vault then
		local left = false
		for _, other in bags do
			if other.active and other.vault then
				left = true
				break
			end
		end
		if not left then
			World.fireRun("VaultLooted", {})
		end
	end
	Log.event(
		"Bags",
		"%s %s a %s bag worth %d (banked %d, %d bags left, streak %d)",
		player.Name,
		if b.kind == "gold" then "banked" else "grabbed",
		b.kind,
		b.value,
		World.banked,
		Bags.count(),
		streak or 0
	)
	return true
end

------------------------------------------------------------------ the channel (round 18)

local function channelSec(streak: number): number
	return math.max(0.05, Config.BagChannelSec * math.max(Config.BagStreakMinMult, Config.BagStreakMult ^ streak))
end

local function setBusy(player: Player, ch: Channel, on: boolean)
	if ch.busyOn ~= on then
		ch.busyOn = on
		busy(player, on)
	end
end

-- Let go of the bag (it keeps its fill: hold, then drain).
local function release(player: Player, ch: Channel)
	local b = ch.bag
	if b and b.by == player then
		b.by = nil
		b.idle = 0
	end
	ch.bag = nil
end

-- The bag to start on: free (or already ours), within BagStartRadius; the most filled first, else the nearest.
local function pick(player: Player, root: BasePart): Bag?
	local best: Bag? = nil
	local bestFill, bestDist = -1, math.huge
	for _, b in bags do
		if not b.active or (b.by ~= nil and b.by ~= player) then
			continue
		end
		local d = root.Position - b.position
		local dist = Vector2.new(d.X, d.Z).Magnitude
		if math.abs(d.Y) > Config.BagKeepRadius or dist > Config.BagStartRadius then
			continue
		end
		local fill = math.floor(b.progress * 20) -- 5% bands, so a sliver of drain does not outrank a nearer bag
		if fill > bestFill or (fill == bestFill and dist < bestDist) then
			best, bestFill, bestDist = b, fill, dist
		end
	end
	return best
end

local function claim(player: Player, ch: Channel, b: Bag)
	b.by = player
	b.idle = 0
	ch.bag = b
	ch.idle = 0
	setBusy(player, ch, true)
end

-- Writes Progress / By only when they change (rounded to 1%).
local function publish(b: Bag)
	local p = math.floor(b.progress * 100 + 0.5) / 100
	if p ~= b.shown then
		b.shown = p
		b.model:SetAttribute("Progress", p)
	end
	local by = if b.by then b.by.UserId else 0
	if by ~= b.shownBy then
		b.shownBy = by
		b.model:SetAttribute("By", by)
	end
end

local function stopAll()
	for player, ch in channels do
		release(player, ch)
		if ch.busyOn and player.Parent then
			busy(player, false)
		end
	end
	table.clear(channels)
end

local function step(dt: number)
	if Pause.active() then
		return -- fills, holds, drains and streak windows all stand still
	end
	if not World.inRun() then
		if next(channels) then
			stopAll()
		end
		return
	end
	local present: { [Player]: boolean } = {}
	for _, player in World.runAudience() do
		if not World.isInParty(player) then
			continue
		end
		present[player] = true
		local ch = channels[player]
		if not ch then
			ch = { bag = nil, streak = 0, idle = 0, busyOn = false }
			channels[player] = ch
		end
		local c = ch :: Channel
		local root = rootOf(player)
		if not root or not PlayerState.isStanding(PlayerState.get(player)) then
			-- Downed, bled out or between characters: no channel, no streak.
			release(player, c)
			c.streak = 0
			setBusy(player, c, false)
			continue
		end
		local b = c.bag
		if b and (not b.active or b.by ~= player or not within(root, b, Config.BagKeepRadius)) then
			release(player, c)
			b = nil
		end
		if not b then
			b = pick(player, root)
			if b then
				claim(player, c, b)
			end
		end
		if b then
			c.idle = 0
			b.progress = math.min(1, b.progress + dt / channelSec(c.streak))
			if b.progress >= 1 then
				release(player, c)
				if Bags.collect(player, b, c.streak) then
					c.streak += 1
				end
				-- Straight on to the next bag in reach, this frame, so a pile empties without a gap.
				local nextBag = pick(player, root)
				if nextBag then
					claim(player, c, nextBag)
				end
			end
		else
			c.idle += dt
			if c.idle > Config.BagStreakWindowSec then
				c.streak = 0
			end
			if c.idle > Config.BagBusyGraceSec then
				setBusy(player, c, false)
			end
		end
	end
	-- Left the party or the server: let go of their bag.
	for player, ch in channels do
		if not present[player] then
			release(player, ch)
			if ch.busyOn and player.Parent then
				busy(player, false)
			end
			channels[player] = nil
		end
	end
	-- Unclaimed bags hold their fill, then drain.
	for _, b in bags do
		if b.by == nil and b.progress > 0 then
			b.idle += dt
			if b.idle > Config.BagHoldSec then
				b.progress = math.max(0, b.progress - Config.BagDrainPerSec * dt)
			end
		end
		publish(b)
	end
end

RunService.Heartbeat:Connect(step)

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
	stopAll()
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
	for _, s in Room.current().bagSpots do
		local spot = s.position
		if occupied(spot) then
			continue
		end
		local d = if root then (spot - root.Position).Magnitude else math.random() * 100
		if d < bestDist then
			bestDist = d
			best = spot
		end
	end
	local at = best
		or (if root then root.Position + root.CFrame.LookVector * 6 else Room.current().floorTop * Vector3.yAxis)
	Bags.spawnAt(if kind == "gold" then "gold" else "cash", at)
	Remotes.Juice:FireClient(player, "Toast", { text = string.upper(kind) .. " BAG DROPPED" })
end

return Bags
