--!strict
-- The dealer break (brief 5): the run's pace break after every boss wave is cleared, before the next
-- intermission. GameLoop hands over with Dealer.run(wave): World.state is "Dealer" for DealerSec (no spawns, heat
-- frozen, bags and floor guns keep their timers; only a pause stops the clock). MARLOW calls it, a stall of Parts
-- goes up at DealerStallPosition with a DEALER NPC, and the HUD card offers TELEPORT TO DEALER (once per break),
-- SKIP (unanimous) and VOTE TO PAUSE.
--
-- The shop is diegetic and per player: eight upgrade stands on the table (drawn by the pick-3 generator, same
-- categories and tradeoff rules; Round 25: priced as a share of your own UPGRADE price, see cardPrice) that every client draws
-- from its own stock (DealerStock), plus three props for the party: ARMS DROP (a crate at the stall), HEAL ALL and
-- REROLL (new stands, price doubles per use). DealerUI opens the nearest stand's panel within ShopReadRadius; F
-- (DealerAction "buy") buys: the upgrade applies at once, a bought stand stays empty.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Fonts = require(Shared.Fonts)
local Config = require(Shared.Config)
local Remotes = require(script.Parent.SlotRemotes)
local Upgrades = require(Shared.Upgrades)
local Rarity = require(Shared.Rarity)
local Types = require(Shared.Types)
local PlayerState = require(script.Parent.Parent.PlayerState)
local Economy = require(script.Parent.Parent.Economy)
local UpgradeShop = require(script.Parent.UpgradeShop)
local BigCrate = require(script.Parent.BigCrate)
local Pause = require(script.Parent.Pause)
local World = require(script.Parent.World)
local Log = require(script.Parent.Parent.Log)
local Purchases = require(script.Parent.Parent.Purchases)
local Room = require(script.Parent.Room)
local Ground = require(Shared.Ground)

local Dealer = {}

type Stock = { cards: { Types.Card }, sold: { boolean }, rerolls: number, buys: number } -- buys: cards bought this break

local stall: Model? = nil
local stock: { [Player]: Stock } = {}
local skipVotes: { [number]: boolean } = {}
local endsAt = 0
local skipped = false
local active = false

Dealer.requested = false -- debug: open the dealer at the next chance

local AMBER = Color3.fromHex("E8B64C")
local WOOD = Color3.fromRGB(110, 78, 46)
local DARK = Color3.fromRGB(40, 40, 46)

-- Brief 7: the stall stands on a DealerSpot of the map (the crew zone's on THE BANK, the arena's single one),
-- opening along the spot's LookVector (the arena's faces -Z, into the room). Chosen when the break starts.
local stallFrame = CFrame.new(Config.DealerStallPosition.X, Config.FloorTop, Config.DealerStallPosition.Z)

-- The crew zone's spot, else the spot nearest the crew.
local function pickFrame(): CFrame
	local view = Room.current()
	local best: Room.DealerSpot? = nil
	local bestDist = math.huge
	local crew = Vector3.zero
	local n = 0
	for _, p in World.runAudience() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			crew += root.Position
			n += 1
		end
	end
	crew = if n > 0 then crew / n else Vector3.zero
	for _, s in view.dealerSpots do
		local d = (s.cframe.Position - crew).Magnitude - (if s.zone == World.crewZone then 1e6 else 0)
		if d < bestDist then
			bestDist = d
			best = s
		end
	end
	if not best then
		return stallFrame
	end
	local cf = best.cframe
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	local p = Ground.at(cf.Position)
	return if look.Magnitude > 0.1 then CFrame.lookAt(p, p + look.Unit) else CFrame.new(p)
end

local function origin(): Vector3
	return stallFrame.Position
end

local function tableTop(): number
	return stallFrame.Position.Y + 3
end

-- The stall is a half circle of DealerTableAngles tables round the DEALER (who stands at the origin), opening
-- toward the arena (-Z). Each table is a CFrame on the arc facing the DEALER; its RightVector runs along it.
local function tableCFrame(t: number): CFrame
	local o = origin()
	local a = math.rad(Config.DealerTableAngles[t] or 0)
	local r = Config.DealerArcRadius
	local p = stallFrame:PointToWorldSpace(Vector3.new(math.sin(a) * r, tableTop() - 0.2 - o.Y, -math.cos(a) * r))
	return CFrame.lookAt(p, Vector3.new(o.X, p.Y, o.Z))
end

-- Stand i (1..DealerStock): DealerPerTable per table, left to right along each.
local function standPosition(i: number): Vector3
	local per = math.max(1, Config.DealerPerTable)
	local t = math.floor((i - 1) / per) + 1
	local k = (i - 1) % per + 1
	local onTable = math.min(per, Config.DealerStock - (t - 1) * per)
	local cf = tableCFrame(t)
	local offset = (k - (onTable + 1) / 2) * Config.DealerStandSpacing
	return cf.Position + cf.RightVector * offset + Vector3.new(0, 1.6, 0)
end

local PROPS = { "crate", "heal", "reroll" }
-- The props stand on the floor just past the arc's ends.
local function propPosition(id: string): Vector3
	local deg = if id == "crate" then -100 elseif id == "heal" then 100 else 122
	local a = math.rad(deg)
	local r = Config.DealerArcRadius
	return stallFrame:PointToWorldSpace(Vector3.new(math.sin(a) * r, 1.2, -math.cos(a) * r))
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanQuery = false
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

------------------------------------------------------------------ The stall (Parts only)
local function buildStall(): Model
	local o = origin()
	local model = Instance.new("Model")
	model.Name = "DealerStall"
	-- Three tables on the arc; the cards over them are each player's own UI (DealerUI), no stand parts.
	local per = math.max(1, Config.DealerPerTable)
	local width = per * Config.DealerStandSpacing + 0.8
	for t = 1, #Config.DealerTableAngles do
		local cf = tableCFrame(t)
		part({
			Name = "Table",
			Size = Vector3.new(width, 0.4, 2.4),
			CFrame = cf,
			Color = WOOD,
			Material = Enum.Material.WoodPlanks,
			Parent = model,
		})
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				part({
					Name = "Leg",
					Size = Vector3.new(0.4, 2.6, 0.4),
					CFrame = cf * CFrame.new(sx * (width / 2 - 0.4), -1.5, sz * 0.9),
					Color = DARK,
					Material = Enum.Material.Metal,
					Parent = model,
				})
			end
		end
	end
	-- Props: an ammo crate, a medkit and a dice cup on side boxes past the arc's ends.
	local cp = propPosition("crate")
	part({
		Name = "AmmoCrate",
		Size = Vector3.new(3, 2.4, 2),
		CFrame = CFrame.new(cp),
		Color = Color3.fromRGB(70, 90, 50),
		Material = Enum.Material.Metal,
		Parent = model,
	})
	part({
		Name = "AmmoStripe",
		Size = Vector3.new(3.05, 0.3, 2.05),
		CFrame = CFrame.new(cp + Vector3.new(0, 0.6, 0)),
		Color = AMBER,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = model,
	})
	local side = propPosition("heal")
	for _, p in { side, propPosition("reroll") } do
		part({
			Name = "SideBox",
			Size = Vector3.new(2, 1.2, 2),
			CFrame = CFrame.new(p - Vector3.new(0, 0.6, 0)),
			Color = WOOD,
			Material = Enum.Material.WoodPlanks,
			Parent = model,
		})
	end
	part({
		Name = "Medkit",
		Size = Vector3.new(1.4, 0.8, 1),
		CFrame = CFrame.new(side),
		Color = Color3.new(1, 1, 1),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	part({
		Name = "MedkitCross",
		Size = Vector3.new(0.9, 0.82, 0.25),
		CFrame = CFrame.new(side),
		Color = Color3.fromHex("E8554D"),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = model,
	})
	local dice = propPosition("reroll")
	part({
		Name = "DiceCup",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.1, 0.9, 0.9),
		CFrame = CFrame.new(dice) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(120, 40, 40),
		Material = Enum.Material.Fabric,
		Parent = model,
	})
	-- Dressing: crates behind the DEALER, a lamp.
	for _, x in { -3, 3 } do
		part({
			Name = "Crate",
			Size = Vector3.new(2, 2, 2),
			CFrame = stallFrame * CFrame.new(x, 1, 2.5),
			Color = WOOD,
			Material = Enum.Material.WoodPlanks,
			Parent = model,
		})
	end
	part({
		Name = "LampPost",
		Size = Vector3.new(0.3, 6, 0.3),
		CFrame = stallFrame * CFrame.new(-1.8, 3, 2),
		Color = DARK,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	local bulb = part({
		Name = "Lamp",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.9, 0.9, 0.9),
		CFrame = stallFrame * CFrame.new(-1.8, 6.2, 2),
		Color = AMBER,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = model,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 160)
	light.Range = 22
	light.Brightness = 2
	light.Parent = bulb
	-- The DEALER: a Part rig in the middle of the half circle that idles.
	local npcPos = o
	local body = part({
		Name = "DealerBody",
		Size = Vector3.new(2, 3, 1.2),
		CFrame = CFrame.new(npcPos + Vector3.new(0, 1.5, 0)),
		Color = Color3.fromRGB(60, 50, 70),
		Material = Enum.Material.Fabric,
		Parent = model,
	})
	local head = part({
		Name = "DealerHead",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.3, 1.3, 1.3),
		CFrame = CFrame.new(npcPos + Vector3.new(0, 3.65, 0)),
		Color = Color3.fromRGB(220, 180, 140),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = model,
	})
	part({
		Name = "DealerHat",
		Size = Vector3.new(1.6, 0.3, 1.6),
		CFrame = CFrame.new(npcPos + Vector3.new(0, 4.35, 0)),
		Color = DARK,
		CanCollide = false,
		Parent = model,
	})
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(120, 28)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0)
	tag.AlwaysOnTop = true
	tag.MaxDistance = 120
	tag.LightInfluence = 0
	tag.Parent = head
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Fonts.display
	label.Text = "DEALER"
	label.TextScaled = true
	label.TextColor3 = AMBER
	label.TextStrokeTransparency = 0.3
	label.Parent = tag
	model.Parent = Workspace:WaitForChild("Effects")
	-- Rise out of the floor, then idle: a slow bob and turn.
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			local final = p.CFrame
			p.CFrame = final - Vector3.new(0, 6, 0)
			TweenService:Create(p, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				CFrame = final,
			}):Play()
		end
	end
	task.spawn(function()
		task.wait(0.7)
		local t0 = os.clock()
		local bodyCF, headCF = body.CFrame, head.CFrame
		while model.Parent do
			local t = os.clock() - t0
			local bob = math.sin(t * 2) * 0.08
			local turn = math.rad(math.sin(t * 0.7) * 18)
			body.CFrame = bodyCF * CFrame.new(0, bob, 0) * CFrame.Angles(0, turn * 0.4, 0)
			head.CFrame = headCF * CFrame.new(0, bob, 0) * CFrame.Angles(0, turn, 0)
			task.wait(1 / 20)
		end
	end)
	return model
end

------------------------------------------------------------------ Stock and prices
-- Round 25: cards are a share of YOUR current UPGRADE price again (Round 21's wave-only pricing left them at
-- $5-10k against a $100k upgrade): DealerCardPriceShare by card tier, and the first cards bought each break at
-- DealerFirstBuyDiscount, so a few always feel cheap before it climbs back to normal. Every buy counts toward
-- the escalation (upgradesBought), so the next card re-prices up. Crates, heals and rerolls scale with the wave.
local function waveScale(perWave: number): number
	return 1 + perWave * math.max(0, World.wave - 1)
end

-- Brief 9 HAGGLE: the buyer's Skill Web takes its share off every dealer price.
local function haggle(state: PlayerState.State): number
	return math.max(0.05, 1 - state.skillMods.dealerPct)
end

local function cardPrice(card: Types.Card, s: Stock, state: PlayerState.State): number
	local share = Config.DealerCardPriceShare[math.clamp(card.tier, 1, 5)] or 1
	local discount = Config.DealerFirstBuyDiscount[s.buys + 1] or 1
	return math.max(1, math.round(Economy.upgradePrice(state) * share * discount * haggle(state)))
end

local function rerollPrice(s: Stock): number
	return math.round(Config.ShopRerollPrice * waveScale(Config.DealerPropWaveMult) * 2 ^ s.rerolls)
end

local function propPrice(id: string, s: Stock, state: PlayerState.State): number
	local k = haggle(state)
	if id == "crate" then
		return math.round(Config.ShopCratePrice * waveScale(Config.DealerPropWaveMult) * k)
	elseif id == "heal" then
		return math.round(Config.ShopHealPrice * waveScale(Config.DealerPropWaveMult) * k)
	end
	return math.round(rerollPrice(s) * k)
end

-- "DAMAGE +30% → +52%": the stat's running total now and after the card (malus lines the same way).
local function effectLines(state: PlayerState.State, card: Types.Card): { string }
	local function line(statId: string, delta: number): string
		local item = state.upgrades[statId]
		local now = if item then item.pct else 0
		-- Elements read by their effect: "BURN ON EVERY SHOT" for new ammo, "BURN +100% → +130%" after. Synergy
		-- stats read by theirs too ("BURN SPREAD +0% → +40%").
		local effect = Upgrades.effectName(statId)
		if effect then
			if not item and Upgrades.isElement(statId) then
				return effect .. " ON EVERY SHOT"
			end
			return string.format(
				"%s %s → %s",
				effect,
				Upgrades.pctText(now, statId),
				Upgrades.pctText(math.round((now + delta) * 10) / 10, statId)
			)
		end
		return string.format(
			"%s %s → %s",
			string.upper(Upgrades.statName(statId)),
			Upgrades.pctText(now, statId),
			Upgrades.pctText(math.round((now + delta) * 10) / 10, statId)
		)
	end
	local out = { line(card.stat, card.pct) }
	if card.malusStat and card.malusPct then
		table.insert(out, line(card.malusStat, -card.malusPct))
	end
	return out
end

local PROP_COPY = {
	crate = { name = "ARMS DROP", lines = { "A weapon crate lands by the stall", "for the whole crew" } },
	heal = { name = "HEAL ALL", lines = { "Every crew member back to full HP" } },
	reroll = { name = "REROLL", lines = { "Eight new stands for you", "Price doubles each use" } },
}

local function sendStock(player: Player)
	local state = PlayerState.get(player)
	local s = stock[player]
	if not s or not active then
		return
	end
	local slots = {}
	for i, card in s.cards do
		slots[i] = {
			index = i,
			position = standPosition(i),
			card = card,
			sold = s.sold[i] == true,
			price = cardPrice(card, s, state),
			title = string.upper(card.name),
			tierName = string.upper(Rarity.name(card.tier)),
			lines = effectLines(state, card),
		}
	end
	local props = {}
	for _, id in PROPS do
		table.insert(props, {
			id = id,
			position = propPosition(id),
			price = propPrice(id, s, state),
			title = PROP_COPY[id].name,
			lines = PROP_COPY[id].lines,
		})
	end
	Remotes.Juice:FireClient(player, "DealerStock", {
		slots = slots,
		props = props,
		readRadius = Config.ShopReadRadius,
	})
end

local function restock(player: Player, rerolls: number?)
	local state = PlayerState.get(player)
	local old = stock[player]
	stock[player] = {
		cards = UpgradeShop.generate(
			state,
			World.wave,
			Config.DealerStock,
			state.skillMods.dealerLuck * Config.LuckOddsStep
		),
		sold = {},
		rerolls = rerolls or 0,
		buys = if rerolls and old then old.buys else 0, -- a reroll keeps this break's count
	}
end

------------------------------------------------------------------ Actions
local function near(player: Player, position: Vector3): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local d = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z).Magnitude
	return d <= Config.ShopReadRadius + 3
end

local function result(player: Player, ok: boolean, slot: any, reason: string?)
	Remotes.Juice:FireClient(player, "DealerResult", { ok = ok, slot = slot, reason = reason })
end

local function buy(player: Player, slot: any)
	local s = stock[player]
	local state = PlayerState.get(player)
	if not active or not s or Pause.active() or state.downed or state.bledOut then
		return
	end
	if typeof(slot) == "number" then
		local i = math.floor(slot)
		local card = s.cards[i]
		if not card or s.sold[i] or not near(player, standPosition(i)) then
			return result(player, false, slot, "gone")
		end
		local price = cardPrice(card, s, state)
		if not Economy.tryCharge(state, price) then
			return result(player, false, slot, "cash")
		end
		s.sold[i] = true
		s.buys += 1
		state.upgradesBought += 1
		state.waveUpgrades += 1
		UpgradeShop.applyCard(player, card, "dealer")
		Log.event("Dealer", "%s bought %s for $%d", player.Name, UpgradeShop.describeCards({ card }), price)
		result(player, true, slot)
	elseif slot == "crate" or slot == "heal" or slot == "reroll" then
		if not near(player, propPosition(slot)) then
			return result(player, false, slot, "far")
		end
		local price = propPrice(slot, s, state)
		if not Economy.tryCharge(state, price) then
			return result(player, false, slot, "cash")
		end
		if slot == "crate" then
			BigCrate.drop(stallFrame:PointToWorldSpace(Vector3.new(0, 0, -Config.DealerArcRadius - 10))) -- in front of the half circle
		elseif slot == "heal" then
			for _, p in World.runAudience() do
				local ps = PlayerState.get(p)
				local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
				if hum and PlayerState.isStanding(ps) then
					hum.Health = hum.MaxHealth
				end
			end
			World.fireRun("DealerHealAll", { name = player.Name })
		else
			restock(player, s.rerolls + 1)
		end
		Log.event("Dealer", "%s bought %s for $%d", player.Name, slot, price)
		result(player, true, slot)
	else
		return
	end
	-- Prices follow the escalation: everyone's stands re-price after a buy (the buyer's own at least).
	sendStock(player)
end

-- Brief 6: RESTOCK for fake Robux (the purchase sheet): your eight stands again, no match cash, no doubling.
-- The R$ RESTOCK. Brief 8: one purchase kind for every run slot; the buyer's own run's dealer answers.
function Dealer.restockCheck(player: Player): string?
	if not active or not stock[player] then
		return "The dealer is not open"
	end
	return nil
end

function Dealer.restockGrant(player: Player): any
	local s = stock[player]
	restock(player, s.rerolls)
	sendStock(player)
	Log.event("Dealer", "%s restocked for Robux (fake)", player.Name)
	return { ok = true }
end

Purchases.register("dealer_restock", {
	check = function(player)
		return (require(script.Parent.Parent.Runs) :: any).modOf(player, "Dealer").restockCheck(player)
	end,
	grant = function(player)
		return (require(script.Parent.Parent.Runs) :: any).modOf(player, "Dealer").restockGrant(player)
	end,
})

local function skipNeeded(): number
	return #World.runAudience()
end

local function skipCount(): number
	local n = 0
	for _, p in World.runAudience() do
		if skipVotes[p.UserId] then
			n += 1
		end
	end
	return n
end

local function onAction(player: Player, action: any, arg: any)
	if not active or not World.isInParty(player) then
		return
	end
	if action == "buy" then
		buy(player, arg)
	elseif action == "skip" then
		skipVotes[player.UserId] = not skipVotes[player.UserId] or nil
		World.dealerDirty = true
		World.fireRun("DealerSkip", { name = player.Name, votes = skipCount(), needed = skipNeeded() })
		if skipCount() >= skipNeeded() then
			skipped = true
		end
	elseif action == "teleport" then
		-- As often as you like during the break.
		if Pause.active() then
			return
		end
		local state = PlayerState.get(player)
		local char = player.Character
		if not char or state.downed or state.bledOut then
			return
		end
		local o = origin()
		local spot = stallFrame:PointToWorldSpace(
			Vector3.new((math.random() - 0.5) * 6, 3, -Config.DealerArcRadius - Config.DealerTeleportDistance)
		)
		char:PivotTo(CFrame.lookAt(spot, Vector3.new(o.X, spot.Y, o.Z)))
		Remotes.Juice:FireClient(player, "DealerTeleported", { position = spot })
		Log.event("Dealer", "%s teleported to the dealer", player.Name)
	end
end

-- The sync view: Types.Sync.dealer.
function Dealer.view(player: Player): any
	if not active then
		return nil
	end
	return {
		endsAt = endsAt,
		skips = skipCount(),
		needed = skipNeeded(),
		mySkip = skipVotes[player.UserId] == true,
		position = origin(),
	}
end

function Dealer.isActive(): boolean
	return active
end

-- Yields for the whole break.
function Dealer.run(wave: number)
	active = true
	skipped = false
	Dealer.requested = false
	table.clear(skipVotes)
	table.clear(stock)
	endsAt = Workspace:GetServerTimeNow() + Config.DealerSec
	World.state = "Dealer"
	PlayerState.markAllDirty()
	stallFrame = pickFrame()
	stall = buildStall()
	for _, p in World.runAudience() do
		restock(p)
		sendStock(p)
	end
	World.fireRun("DealerStart", { endsAt = endsAt, position = origin(), sec = Config.DealerSec })
	-- The DEALER phones in (the crew-call card), then the client's dealer card takes its place in the stack.
	World.fireRun("CrewLine", {
		kind = "door",
		crewLead = "DEALER",
		typeLabel = "SHOP OPEN",
		text = { Config.DealerLine },
		hold = Config.CallHoldSec,
	})
	Log.event("Dealer", "break after wave %d: %ds, stall at (%d, %d)", wave, Config.DealerSec, origin().X, origin().Z)
	-- Round 21: DealerWarnSec warnings before the stall packs up (the clock is pause-aware: endsAt moves).
	local warned: { [number]: boolean } = {}
	while active and not skipped and not World.runOver and Workspace:GetServerTimeNow() < endsAt do
		local left = endsAt - Workspace:GetServerTimeNow()
		for _, sec in Config.DealerWarnSec do
			if left <= sec and not warned[sec] then
				warned[sec] = true
				if left > sec - 1 then -- a skip vote or a short DealerSec never warns late
					World.fireRun("DealerWarn", { sec = sec })
				end
			end
		end
		task.wait(0.1)
	end
	Dealer.close(if skipped then "skipped" else "timer")
end

function Dealer.close(reason: string)
	if not active then
		return
	end
	active = false
	table.clear(stock)
	local m = stall
	stall = nil
	if m then
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then
				TweenService:Create(p, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
					CFrame = p.CFrame - Vector3.new(0, 6, 0),
				}):Play()
			end
		end
		task.delay(0.45, function()
			m:Destroy()
		end)
	end
	World.fireRun("DealerEnd", { reason = reason })
	PlayerState.markAllDirty()
	Log.event("Dealer", "packed up (%s)", reason)
end

function Dealer.init()
	Remotes.DealerAction.OnServerEvent:Connect(onAction)
	-- The break clock stands still while paused.
	Pause.onTick(function(dt)
		if active then
			endsAt += dt
		end
	end)
end

return Dealer
