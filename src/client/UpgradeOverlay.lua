--!strict
-- Pick-3 overlay: world dims, each card has a big icon reel at the top that spins through stat icons and
-- lands on the card's stat; the text pops in on land with tier-scaled juice. Take flies the card to the
-- run tracker. Esc / X / 2 keeps the cards.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Upgrades = require(Shared:WaitForChild("Upgrades"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Types = require(Shared:WaitForChild("Types"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local HUD = require(script.Parent:WaitForChild("HUD"))
local Juice = require(script.Parent:WaitForChild("Juice"))

local UpgradeOverlay = {}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local gui: ScreenGui? = nil
local panel: Frame
local cardsRow: Frame
local trackerHeader: TextLabel
local trackerGrid: Frame
local vignettes: { Frame } = {}
local isOpen = false
local busy = false
local taking = false
local rolling = false
local currentCards: { Types.Card }? = nil
local cardInners: { Frame } = {}
local trackerTiles: { [string]: Frame } = {}
local REEL_CELLS = 12
local REEL_LAND = 9 -- the card's icon sits here; icons after it make the stop read as a stop

local function tierColor(tier: number): Color3
	return Rarity.color(math.clamp(tier, 1, 5))
end

-- Stat icon: a rounded tile in a tier color with the short name. Shared by cards, reels and tracker.
local function statIcon(parent: Instance, statId: string, color: Color3, size: number, ghost: boolean): Frame
	local S = UI.S
	local tile = UI.frame({
		BackgroundColor3 = color,
		BackgroundTransparency = if ghost then 0.55 else 0.1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		Parent = parent,
	})
	UI.corner(tile, math.floor(size * 0.18))
	UI.stroke(tile, color, S(2), if ghost then 0.6 else 0)
	UI.text({
		Text = Upgrades.shortName(statId),
		Font = Theme.Fonts.display,
		TextSize = math.floor(size * 0.34),
		TextColor3 = Theme.Colors.bg,
		TextTransparency = if ghost then 0.3 else 0,
		Size = UDim2.fromScale(1, 1),
		Parent = tile,
	})
	return tile
end

-- Tracker tile: icon, count badge, border = highest tier, card-back layers per 5 taken, red pip if ever a malus.
local function buildTrackerTile(
	parent: Instance,
	statId: string,
	item: Types.TrackerItem,
	size: number,
	order: number
): Frame
	local S = UI.S
	local holder = UI.frame({
		Name = statId,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = order,
		Parent = parent,
	})
	local layers = math.min(5, math.floor(item.count / 5))
	for k = layers, 1, -1 do
		local layer = UI.frame({
			BackgroundColor3 = Theme.Colors.panel2,
			Position = UDim2.fromOffset(S(2) * k, -S(2) * k),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
			Parent = holder,
		})
		UI.corner(layer, S(10))
		UI.stroke(layer, Theme.Colors.grey, S(1), 0.5)
	end
	local tile = UI.button({
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = holder,
	})
	UI.corner(tile, S(10))
	UI.stroke(tile, if item.highestTier > 0 then tierColor(item.highestTier) else Theme.Colors.grey, S(2))
	UI.text({
		Text = Upgrades.shortName(statId),
		Font = Theme.Fonts.display,
		TextSize = math.floor(size * 0.3),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = tile,
	})
	-- Elements show the proc chance, utility stats the running total, gun stats the count.
	local badge, badgeLabel =
		UI.pill(tile, Upgrades.badgeText(statId, item), Theme.Colors.gold, Theme.Colors.bg, S(16), S(10))
	badge.AnchorPoint = Vector2.new(1, 1)
	badge.Position = UDim2.new(1, S(4), 1, S(4))
	badge.ZIndex = 4
	badgeLabel.ZIndex = 4
	if item.everMalus then
		local pip = UI.frame({
			BackgroundColor3 = Theme.Colors.malus,
			Position = UDim2.fromOffset(-S(5), -S(5)),
			Size = UDim2.fromOffset(S(16), S(16)),
			ZIndex = 4,
			Parent = tile,
		})
		UI.corner(pip, S(8))
		UI.text({
			Text = "-",
			Font = Theme.Fonts.display,
			TextSize = S(14),
			TextColor3 = Theme.Colors.bg,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
			Parent = pip,
		})
	end
	local tip = UI.frame({
		BackgroundColor3 = Theme.Colors.panel2,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -S(8)),
		Size = UDim2.fromOffset(S(230), S(56)),
		Visible = false,
		ZIndex = 10,
		Parent = tile,
	})
	UI.corner(tip, S(8))
	UI.stroke(tip, Theme.Colors.grey, S(1))
	UI.text({
		Text = string.format(
			"%s · %s TOTAL\n%s",
			string.upper(Upgrades.statName(statId)),
			Upgrades.pctText(item.pct, statId),
			Upgrades.tierTable(statId)
		),
		TextSize = S(11),
		TextWrapped = true,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 11,
		Parent = tip,
	})
	tile.MouseEnter:Connect(function()
		tip.Visible = true
	end)
	tile.MouseLeave:Connect(function()
		tip.Visible = false
	end)
	tile.Activated:Connect(function()
		tip.Visible = not tip.Visible
	end)
	return holder
end

local function refreshTracker()
	local sync = ClientState.sync
	if not sync or not trackerGrid.Parent then
		return
	end
	for _, c in trackerGrid:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	trackerTiles = {}
	local size = UI.S(HUD.profile().tracker)
	local tracker = sync.tracker
	trackerHeader.Text = string.format("THIS RUN · %d", tracker.total)
	for i, statId in tracker.order do
		local item = tracker.items[statId]
		if item then
			trackerTiles[statId] = buildTrackerTile(trackerGrid, statId, item, size, i)
		end
	end
end

type CardUI = {
	holder: Frame,
	inner: Frame,
	stroke: UIStroke,
	well: Frame,
	wellStroke: UIStroke,
	column: Frame,
	cellH: number,
	details: { GuiObject },
}

local function buildCard(index: number, card: Types.Card): CardUI
	local S = UI.S
	local p = HUD.profile()
	local w, h = S(p.card.X), S(p.card.Y)
	local color = tierColor(card.tier)

	local holder = UI.frame({
		Name = "Card" .. index,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(w, h + S(30)),
		LayoutOrder = index,
		Parent = cardsRow,
	})
	local inner = UI.frame({
		Name = "Inner",
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, S(10)),
		Size = UDim2.fromOffset(w, h),
		Parent = holder,
	})
	UI.corner(inner, S(14))
	local stroke = UI.stroke(inner, Theme.Colors.grey, S(3))

	-- Icon reel at the top: a column of stat icons scrolls past; the one at REEL_LAND is this card's stat.
	local cellH = S(104)
	local well = UI.frame({
		Name = "IconWell",
		BackgroundColor3 = Theme.Colors.bg,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(12)),
		Size = UDim2.fromOffset(cellH, cellH),
		ClipsDescendants = true,
		Parent = inner,
	})
	UI.corner(well, S(16))
	local wellStroke = UI.stroke(well, Theme.Colors.grey, S(2))
	local column = UI.frame({
		Name = "Column",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, cellH * REEL_CELLS),
		Parent = well,
	})
	for i = 1, REEL_CELLS do
		local cell = UI.frame({
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, (i - 1) * cellH),
			Size = UDim2.new(1, 0, 0, cellH),
			Parent = column,
		})
		if i == REEL_LAND then
			statIcon(cell, card.stat, color, S(80), false)
		else
			local stat = Upgrades.Stats[math.random(#Upgrades.Stats)]
			statIcon(cell, stat.id, tierColor(math.random(1, 5)), S(80), true)
		end
	end

	-- Text appears once the reel lands.
	local details: { GuiObject } = {}
	local function detail(obj: GuiObject): GuiObject
		obj.Visible = false
		table.insert(details, obj)
		return obj
	end
	detail(UI.text({
		Text = string.upper(card.name),
		Font = Theme.Fonts.display,
		TextSize = S(20),
		TextWrapped = true,
		Position = UDim2.fromOffset(S(8), S(122)),
		Size = UDim2.new(1, -S(16), 0, S(28)),
		Parent = inner,
	}))
	-- Rarity reads from the card color alone; no pill, no TAKE hint.
	detail(UI.text({
		Text = Upgrades.pctText(card.pct, card.stat),
		Font = Theme.Fonts.display,
		TextSize = S(48),
		TextColor3 = Theme.Colors.cash,
		Position = UDim2.fromOffset(0, S(160)),
		Size = UDim2.new(1, 0, 0, S(52)),
		Parent = inner,
	}))
	detail(UI.text({
		Text = string.upper(Upgrades.statName(card.stat)),
		Font = Theme.Fonts.display,
		TextSize = S(16),
		TextColor3 = Theme.Colors.cash,
		Position = UDim2.fromOffset(0, S(210)),
		Size = UDim2.new(1, 0, 0, S(20)),
		Parent = inner,
	}))
	if card.isTradeoff and card.malusStat and card.malusPct then
		local malus = UI.frame({
			BackgroundColor3 = Theme.Colors.malus,
			BackgroundTransparency = 0.85,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, S(240)),
			Size = UDim2.new(1, -S(24), 0, S(22)),
			Parent = inner,
		})
		UI.corner(malus, S(7))
		UI.stroke(malus, Theme.Colors.malus, S(1), 0.4)
		UI.text({
			Text = Upgrades.effectLine(card.malusStat, -card.malusPct),
			TextSize = S(12),
			TextColor3 = Theme.Colors.malus,
			Size = UDim2.fromScale(1, 1),
			Parent = malus,
		})
		detail(malus)
	end

	local button = UI.button({
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = inner,
	})
	button.Activated:Connect(function()
		UpgradeOverlay.take(index)
	end)
	button.MouseEnter:Connect(function()
		if not UserInputService.TouchEnabled and not rolling then
			UI.punch(inner, 1.05, 0.2)
		end
	end)
	return {
		holder = holder,
		inner = inner,
		stroke = stroke,
		well = well,
		wellStroke = wellStroke,
		column = column,
		cellH = cellH,
		details = details,
	}
end

local function landedOffset(ui: CardUI): number
	return -(REEL_LAND - 1) * ui.cellH
end

local function showDetails(ui: CardUI, animate: boolean)
	for i, obj in ui.details do
		obj.Visible = true
		if animate then
			task.delay((i - 1) * 0.04, function()
				if obj.Parent then
					UI.punch(obj, if i == 2 then 1.6 else 1.25, 0.35)
				end
			end)
		end
	end
end

local function reveal(ui: CardUI, card: Types.Card)
	local color = tierColor(card.tier)
	ui.stroke.Color = color
	ui.wellStroke.Color = color
	UI.punch(ui.well, 1.15, 0.35)
	showDetails(ui, true)
	local center = ui.inner.AbsolutePosition + ui.inner.AbsoluteSize / 2
	local j = Juice.burst(card.tier, color, center)
	UI.punch(ui.inner, j.punch + 0.04, 0.45)
	UI.sound(Theme.Sounds.reelLand, j.pitch, j.volume)
	if j.tier >= 4 then
		ui.stroke.Thickness = UI.S(6)
		UI.tween(ui.stroke, { Thickness = UI.S(3) }, 0.5)
	end
end

local function rollCard(ui: CardUI, card: Types.Card)
	ui.column.Position = UDim2.fromOffset(0, 0)
	local tween = UI.tween(
		ui.column,
		{ Position = UDim2.fromOffset(0, landedOffset(ui)) },
		Config.CardRollSec,
		Enum.EasingStyle.Quart,
		Enum.EasingDirection.Out
	)
	local lastIdx = 0
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		if not ui.column.Parent then
			conn:Disconnect()
			return
		end
		local idx = math.floor(-ui.column.Position.Y.Offset / ui.cellH + 0.5)
		if idx > lastIdx then
			lastIdx = idx
			UI.sound(Theme.Sounds.reelTick, 0.8 + (idx / REEL_LAND) * 1.0, 0.3)
			UI.punch(ui.well, 1.04, 0.1)
		end
	end)
	tween.Completed:Wait()
	conn:Disconnect()
	if ui.inner.Parent then
		reveal(ui, card)
	end
end

local function build()
	if gui then
		gui:Destroy()
	end
	local S = UI.S
	local p = HUD.profile()
	local g = UI.new("ScreenGui", {
		Name = "UpgradeOverlay",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = playerGui,
	}) :: ScreenGui
	gui = g

	UI.frame({
		Name = "Dim",
		BackgroundColor3 = Theme.Colors.black,
		BackgroundTransparency = 1 - Config.ShopDimPct / 100,
		Size = UDim2.fromScale(1, 1),
		Active = true,
		Parent = g,
	})
	vignettes = {}
	for _, rotation in { 0, 90 } do
		local v = UI.frame({
			BackgroundColor3 = Theme.Colors.red,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Parent = g,
		})
		UI.new("UIGradient", {
			Rotation = rotation,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.3, 1),
				NumberSequenceKeypoint.new(0.7, 1),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Parent = v,
		})
		table.insert(vignettes, v)
	end

	local cardW, cardH = S(p.card.X), S(p.card.Y)
	local trackerSize = S(p.tracker)
	local gridW = Config.TrackerCols * (trackerSize + S(8))
	local panelW = math.max(3 * cardW + 2 * S(24) + S(40), gridW + S(40))
	local panelH = S(50) + cardH + S(30) + S(40) + trackerSize + S(24)
	panel = UI.frame({
		Name = "Panel",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -S(10)),
		Size = UDim2.fromOffset(panelW, panelH),
		ZIndex = 3,
		Parent = g,
	})
	UI.text({
		Text = "PICK ONE",
		Font = Theme.Fonts.display,
		TextSize = S(30),
		Size = UDim2.new(1, 0, 0, S(36)),
		Parent = panel,
	})
	UI.text({
		Text = "ESC / X / 2 KEEPS THESE CARDS",
		TextSize = S(11),
		TextColor3 = Theme.Colors.grey,
		Position = UDim2.fromOffset(0, S(34)),
		Size = UDim2.new(1, 0, 0, S(16)),
		Parent = panel,
	})
	cardsRow = UI.frame({
		Name = "Cards",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, S(50)),
		Size = UDim2.new(1, 0, 0, cardH + S(30)),
		Parent = panel,
	})
	UI.list(
		cardsRow,
		Enum.FillDirection.Horizontal,
		S(24),
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Center
	)

	local trackerY = S(50) + cardH + S(30) + S(10)
	trackerHeader = UI.text({
		Text = "THIS RUN · 0",
		Font = Theme.Fonts.display,
		TextSize = S(16),
		TextColor3 = Theme.Colors.grey,
		Position = UDim2.fromOffset(0, trackerY),
		Size = UDim2.new(1, 0, 0, S(22)),
		Parent = panel,
	})
	trackerGrid = UI.frame({
		Name = "Tracker",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, trackerY + S(28)),
		Size = UDim2.fromOffset(gridW, trackerSize),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = panel,
	})
	UI.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(trackerSize, trackerSize),
		CellPadding = UDim2.fromOffset(S(8), S(12)),
		FillDirectionMaxCells = Config.TrackerCols,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = trackerGrid,
	})
end

local function show(cards: { Types.Card }, reopened: boolean)
	local g = gui
	if not g then
		return
	end
	currentCards = cards
	for _, c in cardsRow:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	cardInners = {}
	isOpen = true
	taking = false
	g.Enabled = true
	ClientState.setBlock("overlay", true)
	refreshTracker()

	local S = UI.S
	if not reopened then
		-- The panel drops in from above as the cards deal.
		panel.Position = UDim2.new(0.5, 0, 0.5, -S(50))
		UI.tween(
			panel,
			{ Position = UDim2.new(0.5, 0, 0.5, -S(10)) },
			0.3,
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out
		)
	end
	local p = HUD.profile()
	local w, h = S(p.card.X), S(p.card.Y)
	local uis: { CardUI } = {}
	for i, card in cards do
		local ui = buildCard(i, card)
		uis[i] = ui
		cardInners[i] = ui.inner
		if reopened then
			ui.column.Position = UDim2.fromOffset(0, landedOffset(ui))
			ui.stroke.Color = tierColor(card.tier)
			ui.wellStroke.Color = tierColor(card.tier)
			showDetails(ui, false)
		else
			ui.inner.Size = UDim2.fromOffset(math.floor(w * 0.5), math.floor(h * 0.5))
			ui.inner.BackgroundTransparency = 1
			UI.tween(
				ui.inner,
				{ Size = UDim2.fromOffset(w, h), BackgroundTransparency = 0 },
				0.25,
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out,
				Config.CardDealStagger * (i - 1)
			)
		end
	end
	if reopened then
		return
	end
	rolling = true
	local last = #cards
	for i, card in cards do
		task.delay(Config.CardDealStagger * (i - 1) + Config.CardRollStagger * (i - 1), function()
			if not uis[i].inner.Parent then
				return
			end
			rollCard(uis[i], card)
			if i == last then
				rolling = false
			end
		end)
	end
end

function UpgradeOverlay.close()
	local g = gui
	if not isOpen or not g then
		return
	end
	isOpen = false
	rolling = false
	g.Enabled = false
	ClientState.setBlock("overlay", false)
end

function UpgradeOverlay.open()
	if isOpen or busy or ClientState.downed or ClientState.inHub() then
		return
	end
	local sync = ClientState.sync
	if not sync then
		return
	end
	busy = true
	local ok, result = pcall(function()
		return Remotes.BuyUpgrade:InvokeServer()
	end)
	busy = false
	if not ok or not result or not result.ok then
		local buy = HUD.get("buy")
		if buy then
			buy.tiles.upgrade.shake()
		end
		UI.sound(Theme.Sounds.deny, 1, 0.4)
		local price = if ok and result and result.price then result.price else sync.prices.upgrade
		HUD.get("toast").show(string.format("NEED %s FOR AN UPGRADE", UI.fmtCash(price)), Theme.Colors.malus, 1)
		return
	end
	show(result.cards, result.reopened == true)
	UI.sound(Theme.Sounds.call, if result.reopened then 0.9 else 1.2, 0.5)
end

function UpgradeOverlay.toggle()
	if isOpen then
		UpgradeOverlay.close()
	else
		UpgradeOverlay.open()
	end
end

function UpgradeOverlay.isOpen(): boolean
	return isOpen
end

function UpgradeOverlay.take(index: number)
	local g = gui
	local cards = currentCards
	if not isOpen or taking or rolling or not g or not cards then
		return
	end
	local card = cards[index]
	local inner = cardInners[index]
	if not card or not inner then
		return
	end
	taking = true
	Remotes.TakeUpgrade:FireServer(index)
	local color = tierColor(card.tier)
	local center = inner.AbsolutePosition + inner.AbsoluteSize / 2
	local j = Juice.burst(card.tier, color, center)
	UI.punch(inner, j.punch + 0.06, 0.2)
	UI.sound(Theme.Sounds.take, j.pitch, j.volume)

	-- Fly a ghost from the card to its tracker tile, or to where a new tile will appear.
	local S = UI.S
	local target = trackerTiles[card.stat]
	local targetPos: Vector2
	if target then
		targetPos = target.AbsolutePosition + target.AbsoluteSize / 2
	else
		local n = 0
		for _ in trackerTiles do
			n += 1
		end
		local size = S(HUD.profile().tracker)
		local col = n % Config.TrackerCols
		local row = math.floor(n / Config.TrackerCols)
		targetPos = trackerGrid.AbsolutePosition
			+ Vector2.new(col * (size + S(8)) + size / 2, row * (size + S(12)) + size / 2)
	end
	local ghost = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = UDim2.fromOffset(S(90), S(90)),
		ZIndex = 20,
		Parent = g,
	})
	statIcon(ghost, card.stat, color, S(90), false)
	for _, other in cardInners do
		if other ~= inner then
			UI.tween(other, { BackgroundTransparency = 0.6 }, 0.2)
		end
	end
	UI.tween(ghost, {
		Position = UDim2.fromOffset(targetPos.X, targetPos.Y),
		Size = UDim2.fromOffset(S(48), S(48)),
		Rotation = 180,
	}, 0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.34, function()
		ghost:Destroy()
		if target and target.Parent then
			UI.punch(target, 1.4, 0.3)
		end
		UpgradeOverlay.close()
		taking = false
	end)
end

function UpgradeOverlay.init()
	build()
	local function bindTile()
		local buy = HUD.get("buy")
		if buy then
			buy.tiles.upgrade.onPress = UpgradeOverlay.toggle
		end
	end
	bindTile()
	HUD.Rebuilt:Connect(function()
		build()
		bindTile()
	end)

	ClientState.Changed:Connect(function()
		if isOpen then
			refreshTracker()
		end
	end)

	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "UpgradeApplied" then
			local card = data.card
			local text = Upgrades.effectLine(card.stat, card.pct)
			if typeof(data.totalPct) == "number" and math.abs(data.totalPct - card.pct) > 0.01 then
				text ..= string.format("  ·  %s TOTAL", Upgrades.pctText(data.totalPct, card.stat))
			end
			if card.isTradeoff and card.malusStat and card.malusPct then
				text ..= "   /   " .. Upgrades.effectLine(card.malusStat, -card.malusPct)
			end
			HUD.get("toast").show(text, tierColor(card.tier), 1.5)
		elseif name == "PlayerHit" and isOpen then
			UI.shake(panel, UI.S(Config.PanelShakePx), 0.2)
			for _, v in vignettes do
				v.BackgroundTransparency = 0.5
				UI.tween(v, { BackgroundTransparency = 1 }, 0.5)
			end
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or not isOpen then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.X then
			UpgradeOverlay.close()
		end
	end)
end

return UpgradeOverlay
