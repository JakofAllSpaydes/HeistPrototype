--!strict
-- Pick-3 overlay: world dims, cards deal and flip, Take flies to the run tracker, Esc/X keeps the cards.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local currentCards: { Types.Card }? = nil
local cardInners: { Frame } = {}
local trackerTiles: { [string]: Frame } = {}

local function tierColor(tier: number): Color3
	return Rarity.color(math.clamp(tier, 1, 5))
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
	local badge, badgeLabel =
		UI.pill(tile, string.format("x%d", item.count), Theme.Colors.gold, Theme.Colors.bg, S(16), S(10))
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
	-- Tooltip: stat name, total %, next tier values.
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
			Upgrades.pctText(item.pct),
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

local function buildCard(index: number, card: Types.Card): (Frame, Frame, Frame, Frame)
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
	UI.stroke(inner, color, S(3))

	local back = UI.frame({
		Name = "Back",
		BackgroundColor3 = Theme.Colors.panel2,
		Size = UDim2.fromScale(1, 1),
		Parent = inner,
	})
	UI.corner(back, S(14))
	UI.text({
		Text = "?",
		Font = Theme.Fonts.display,
		TextSize = S(72),
		TextColor3 = Theme.Colors.gold,
		Size = UDim2.fromScale(1, 1),
		Parent = back,
	})

	local face = UI.frame({
		Name = "Face",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = inner,
	})
	local iconTile = UI.frame({
		BackgroundColor3 = Theme.Colors.panel2,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -S(26)),
		Size = UDim2.fromOffset(S(64), S(64)),
		ZIndex = 3,
		Parent = face,
	})
	UI.corner(iconTile, S(12))
	UI.stroke(iconTile, color, S(2))
	UI.text({
		Text = Upgrades.shortName(card.stat),
		Font = Theme.Fonts.display,
		TextSize = S(22),
		TextColor3 = color,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = iconTile,
	})
	UI.text({
		Text = string.upper(card.name),
		Font = Theme.Fonts.display,
		TextSize = S(20),
		TextWrapped = true,
		Position = UDim2.fromOffset(S(8), S(46)),
		Size = UDim2.new(1, -S(16), 0, S(30)),
		Parent = face,
	})
	local pill = UI.pill(face, string.upper(Rarity.name(card.tier)), color, Theme.Colors.bg, S(18), S(11))
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, S(82))
	UI.text({
		Text = Upgrades.pctText(card.pct),
		Font = Theme.Fonts.display,
		TextSize = S(46),
		TextColor3 = Theme.Colors.cash,
		Position = UDim2.fromOffset(0, S(112)),
		Size = UDim2.new(1, 0, 0, S(52)),
		Parent = face,
	})
	UI.text({
		Text = string.upper(Upgrades.statName(card.stat)),
		TextSize = S(15),
		TextColor3 = Theme.Colors.cash,
		Position = UDim2.fromOffset(0, S(164)),
		Size = UDim2.new(1, 0, 0, S(20)),
		Parent = face,
	})
	if card.isTradeoff and card.malusStat and card.malusPct then
		local malus = UI.frame({
			BackgroundColor3 = Theme.Colors.malus,
			BackgroundTransparency = 0.85,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, S(194)),
			Size = UDim2.new(1, -S(24), 0, S(28)),
			Parent = face,
		})
		UI.corner(malus, S(8))
		UI.stroke(malus, Theme.Colors.malus, S(1), 0.4)
		UI.text({
			Text = Upgrades.effectLine(card.malusStat, -card.malusPct),
			TextSize = S(13),
			TextColor3 = Theme.Colors.malus,
			Size = UDim2.fromScale(1, 1),
			Parent = malus,
		})
	end
	UI.text({
		Text = "TAKE",
		TextSize = S(12),
		TextColor3 = Theme.Colors.grey,
		Position = UDim2.new(0, 0, 1, -S(26)),
		Size = UDim2.new(1, 0, 0, S(20)),
		Parent = face,
	})
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
		if not UserInputService.TouchEnabled then
			UI.punch(inner, 1.05, 0.2)
		end
	end)
	return holder, inner, back, face
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
	local p = HUD.profile()
	local w, h = S(p.card.X), S(p.card.Y)
	local dealTotal = Config.CardDealStagger * 3 + 0.25
	for i, card in cards do
		local _holder, inner, back, face = buildCard(i, card)
		cardInners[i] = inner
		if reopened then
			back.Visible = false
			face.Visible = true
		else
			inner.Size = UDim2.fromOffset(math.floor(w * 0.5), math.floor(h * 0.5))
			inner.BackgroundTransparency = 1
			UI.tween(
				inner,
				{ Size = UDim2.fromOffset(w, h), BackgroundTransparency = 0 },
				0.25,
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out,
				Config.CardDealStagger * (i - 1)
			)
			task.delay(dealTotal + Config.CardFlipStagger * (i - 1), function()
				if not inner.Parent then
					return
				end
				UI.sound(Theme.Sounds.cardFlip, 1.2 + i * 0.1, 0.4)
				local shrink = UI.tween(
					inner,
					{ Size = UDim2.fromOffset(S(4), h) },
					0.09,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				)
				shrink.Completed:Wait()
				if not inner.Parent then
					return
				end
				back.Visible = false
				face.Visible = true
				UI.tween(
					inner,
					{ Size = UDim2.fromOffset(w, h) },
					0.12,
					Enum.EasingStyle.Back,
					Enum.EasingDirection.Out
				)
			end)
		end
	end
end

function UpgradeOverlay.close()
	local g = gui
	if not isOpen or not g then
		return
	end
	isOpen = false
	g.Enabled = false
	ClientState.setBlock("overlay", false)
end

function UpgradeOverlay.open()
	if isOpen or busy then
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
	if not isOpen or taking or not g or not cards then
		return
	end
	local card = cards[index]
	local inner = cardInners[index]
	if not card or not inner then
		return
	end
	taking = true
	Remotes.TakeUpgrade:FireServer(index)
	UI.punch(inner, 1.12, 0.15)
	UI.sound(Theme.Sounds.take, 1, 0.6)

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
	local start = inner.AbsolutePosition + inner.AbsoluteSize / 2
	local ghost = UI.frame({
		BackgroundColor3 = tierColor(card.tier),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(start.X, start.Y),
		Size = UDim2.fromOffset(S(90), S(110)),
		ZIndex = 20,
		Parent = g,
	})
	UI.corner(ghost, S(10))
	UI.text({
		Text = Upgrades.shortName(card.stat),
		Font = Theme.Fonts.display,
		TextSize = S(24),
		TextColor3 = Theme.Colors.bg,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 21,
		Parent = ghost,
	})
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
			HUD.get("toast").show(Upgrades.effectLine(card.stat, card.pct), Theme.Colors.cash, 1)
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
