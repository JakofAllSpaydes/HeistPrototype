--!strict
-- Shared pieces for the three tabs, styled to the reference: filter pills, dark section bars (OWNED /
-- UNOWNED), colored item tiles with the name on top and a price / level pill at the bottom, stat rows with
-- "42 » 54" deltas, big flat action buttons, and the two-column grid + detail layout.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Prices = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Prices"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MasteryCopy = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MasteryCopy"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))

local MetaUI = {}

MetaUI.Prices = Prices

-- Tile colors by archetype (reference tiles are saturated blocks).
MetaUI.ArchetypeColors = {
	Pistol = Color3.fromHex("7A8AA0"),
	SMG = Color3.fromHex("3FA873"),
	Rifle = Color3.fromHex("D9822B"),
	Shotgun = Color3.fromHex("C8323C"),
	Sniper = Color3.fromHex("7A4DE8"),
	LMG = Color3.fromHex("2F7FD6"),
} :: { [string]: Color3 }

MetaUI.Green = Color3.fromHex("2FD46A")
MetaUI.Pink = Color3.fromHex("E8347A")

export type TileOpts = {
	name: string,
	pill: string, -- bottom pill text: "LV 2", "◆ 100", "CRATE", "EVENT", "OWNED"
	pillColor: Color3?,
	color: Color3, -- tile background
	owned: boolean,
	selected: boolean,
	tag: string?, -- STARTER / EQUIPPED / CRATE / EVENT, top-right
	tagColor: Color3?,
	icon: string, -- gun | mask | wrap | class
	iconColor: Color3?,
	glyph: string?, -- for icon = "class": the letter in the circle
	size: number, -- tile width; height = size x 1.18
	order: number,
	nameTag: string?, -- gold text after the name in the top bar ("LV 2" on an owned weapon)
	noPill: boolean?, -- no bottom pill (the bottom carries the mastery bar); `tag` then sits bottom-center
}

function MetaUI.fmtGold(n: number): string
	return "◆ " .. UI.fmtNum(n)
end

-- Acquisition label for an unowned item: the Gold price (Direct) or where it comes from (brief 6: CRATE, BUNDLE,
-- VIP, PASS, EVENT).
MetaUI.SourceColors = {
	Crate = Theme.Colors.blue,
	Event = Theme.Colors.malus,
	Bundle = Color3.fromHex("E8792A"),
	VIP = Color3.fromHex("F2C14E"),
	Pass = Color3.fromHex("FF6A3D"),
	Mastery = Theme.Colors.gold,
} :: { [string]: Color3 }

function MetaUI.acquisition(saleType: string, price: number): (string, Color3)
	local c = MetaUI.SourceColors[saleType]
	if c then
		return string.upper(saleType), c
	end
	return MetaUI.fmtGold(price), Theme.Colors.cash
end

-- Brief 6 deep links: VIEW CRATE / VIEW BUNDLE / VIEW PASS / VIEW VIP for an unowned item that is not Gold-priced
-- (EVENT ONLY stays disabled). `kind` is the Rewards kind (weapon | mask | wrap | emote | class).
function MetaUI.sourceButton(scene: any, card: Instance, order: number, kind: string, id: string, saleType: string)
	local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	local Crates = require(Shared:WaitForChild("Crates")) :: any
	local Bundles = require(Shared:WaitForChild("Bundles")) :: any
	local PassSeason = require(Shared:WaitForChild("PassSeason")) :: any
	local ClientState = require(script.Parent.Parent:WaitForChild("ClientState")) :: any
	if saleType == "Crate" then
		MetaUI.button(card, order, "VIEW CRATE", "blue", function()
			ClientState.Juice:Fire("OpenStore", { tab = "CRATES", arg = { crate = Crates.crateOf(kind, id) } })
		end)
	elseif saleType == "Bundle" then
		local list = Bundles.containing(kind, id)
		MetaUI.button(card, order, "VIEW BUNDLE", "blue", function()
			ClientState.Juice:Fire("OpenStore", { tab = "FEATURED", arg = { bundle = list[1] } })
		end)
	elseif saleType == "VIP" then
		MetaUI.button(card, order, "VIEW VIP", "blue", function()
			ClientState.Juice:Fire("OpenStore", { tab = "VIP" })
		end)
	elseif saleType == "Pass" then
		local season, level = PassSeason.levelOf(kind, id)
		MetaUI.button(card, order, "VIEW PASS", "blue", function()
			ClientState.Juice:Fire("OpenPass", { level = level, season = season })
		end)
	else
		MetaUI.button(card, order, "EVENT ONLY", "disabled", nil)
	end
end

-- Icon drawn into a parent: gun silhouette, mask, wrap swatch or class circle. Returns the icon root.
function MetaUI.icon(kind: string, parent: Instance, size: number, color: Color3, glyph: string?): GuiObject
	if kind == "gun" then
		return UI.gunIcon(parent, color, size)
	end
	local f = UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size) })
	if kind == "mask" then
		local head = UI.frame({
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.6, 0.6),
			Parent = f,
		})
		UI.corner(head, math.floor(size * 0.18))
		local band = UI.frame({
			BackgroundColor3 = Theme.Colors.bg,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.46),
			Size = UDim2.fromScale(0.64, 0.14),
			Parent = f,
		})
		UI.corner(band, 3)
	elseif kind == "wrap" then
		local swatch = UI.frame({
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.7, 0.7),
			Parent = f,
		})
		UI.corner(swatch, math.floor(size * 0.2))
	else
		local circle = UI.frame({
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.66, 0.66),
			Parent = f,
		})
		UI.corner(circle, 999)
		UI.stroke(circle, Theme.Colors.bg, 2, 0.3)
		UI.text({
			Text = glyph or "?",
			Font = Theme.Fonts.display,
			TextSize = math.floor(size * 0.34),
			TextColor3 = Theme.Colors.bg,
			Size = UDim2.fromScale(1, 1),
			Parent = circle,
		})
	end
	f.Parent = parent
	return f
end

-- Mastery (brief 5): a thin bar with tier pips along the bottom of a weapon tile or class pill, and a tooltip on
-- hover / tap listing the tier rewards with the earned ones ticked. `kind` "weapon" | "class".
function MetaUI.masteryBar(parent: GuiObject, kind: string, id: string, xp: number, inset: number?)
	local S = UI.S
	local tiers = if kind == "weapon" then Config.WeaponMasteryTiers else Config.ClassMasteryTiers
	local tier, into, need = MasteryCopy.progress(xp, tiers)
	local pad = inset or S(6)
	local track = UI.frame({
		Name = "Mastery",
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.2,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(2)),
		Size = UDim2.new(1, -pad * 2, 0, S(4)),
		ZIndex = 6,
		Parent = parent,
	})
	UI.corner(track, S(2))
	local frac = if need > 0 then math.clamp(into / need, 0, 1) else 1
	local fill = UI.frame({
		BackgroundColor3 = if tier >= #tiers then Theme.Colors.gold else Theme.Colors.cash,
		Size = UDim2.fromScale(frac, 1),
		ZIndex = 6,
		Parent = track,
	})
	UI.corner(fill, S(2))
	-- Tier pips above the bar's right end: lit gold once earned.
	for t = 1, #tiers do
		local pip = UI.frame({
			BackgroundColor3 = if tier >= t then Theme.Colors.gold else Theme.Colors.panel2,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -(#tiers - t) * S(7), 0, -S(2)),
			Size = UDim2.fromOffset(S(5), S(5)),
			Rotation = 45,
			ZIndex = 6,
			Parent = track,
		})
		UI.stroke(pip, Theme.Colors.black, 1, 0.4)
	end
	local lines = MasteryCopy.tooltip(kind, id, tier)
	local tip = UI.frame({
		Name = "MasteryTip",
		BackgroundColor3 = Theme.Colors.panel2,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, S(4)),
		Size = UDim2.fromOffset(S(280), S(16) * (#lines + 1) + S(8)),
		Visible = false,
		ZIndex = 30,
		Parent = parent,
	})
	UI.corner(tip, S(6))
	UI.stroke(tip, Theme.Colors.grey, S(1))
	UI.pad(tip, S(8), S(4), S(8), S(4))
	UI.list(tip, Enum.FillDirection.Vertical, 0)
	UI.text({
		Text = string.format(
			"MASTERY %s · %s",
			if tier > 0 then MasteryCopy.Roman[tier] else "0",
			if need > 0 then string.format("%d / %d", into, need) else "MAX"
		),
		Font = Theme.Fonts.display,
		TextSize = S(11),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(16)),
		ZIndex = 31,
		Parent = tip,
	})
	for i, line in lines do
		UI.text({
			Text = line,
			TextSize = S(10),
			TextColor3 = if i <= tier then Theme.Colors.cash else Theme.Colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.new(1, 0, 0, S(16)),
			LayoutOrder = i,
			ZIndex = 31,
			Parent = tip,
		})
	end
	parent.MouseEnter:Connect(function()
		tip.Visible = true
	end)
	parent.MouseLeave:Connect(function()
		tip.Visible = false
	end)
end

-- The mastery panel in a detail column (weapons and classes share it). One line: `MASTERY II` with its tier
-- diamonds on the left, the next reward on the right (`NEXT · UNLOCK SKIN`); under it a full-width bar with the
-- progress written inside it (`15 / 800 KILLS`, or MAXED).
function MetaUI.masteryPanel(
	parent: Instance,
	order: number,
	tiers: { number },
	xp: number,
	unit: string,
	nextLabel: string?
): Frame
	local S = UI.S
	local tier, into, need = MasteryCopy.progress(xp, tiers)
	local pad = S(10)
	local row = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.new(1, 0, 0, S(54)),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.corner(row, S(6))
	-- Top line.
	local line = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(pad, S(6)),
		Size = UDim2.new(1, -pad * 2, 0, S(20)),
		Parent = row,
	})
	local left = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(0.55, 0, 1, 0),
		Parent = line,
	})
	UI.list(left, Enum.FillDirection.Horizontal, S(8), Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	UI.text({
		Text = if tier > 0 then "MASTERY " .. MasteryCopy.Roman[tier] else "MASTERY",
		Font = Theme.Fonts.display,
		TextSize = S(15),
		TextColor3 = if tier > 0 then Theme.Colors.gold else Theme.Colors.textDim,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 1,
		Parent = left,
	})
	local pips = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(S(12) * #tiers, S(12)),
		LayoutOrder = 2,
		Parent = left,
	})
	for t = 1, #tiers do
		local d = UI.frame({
			BackgroundColor3 = if tier >= t then Theme.Colors.gold else Theme.Colors.panel2,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, S(12) * (t - 0.5), 0.5, 0),
			Size = UDim2.fromOffset(S(7), S(7)),
			Rotation = 45,
			Parent = pips,
		})
		UI.stroke(d, Theme.Colors.black, 1, 0.3)
	end
	if need > 0 and nextLabel then
		UI.text({
			Text = "NEXT · " .. nextLabel,
			Font = Theme.Fonts.body,
			TextSize = S(10),
			TextColor3 = Theme.Colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0.45, 0, 1, 0),
			Parent = line,
		})
	end
	-- The bar with the count inside it.
	local barH = S(16)
	local track = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, pad, 1, -S(8)),
		Size = UDim2.new(1, -pad * 2, 0, barH),
		Parent = row,
	})
	UI.corner(track, barH / 2)
	local fill = UI.frame({
		BackgroundColor3 = if need > 0 then MetaUI.Green else Theme.Colors.gold,
		Size = UDim2.fromScale(if need > 0 then math.clamp(into / need, 0, 1) else 1, 1),
		Parent = track,
	})
	UI.corner(fill, barH / 2)
	local count = UI.text({
		Text = if need > 0 then string.format("%s / %s %s", UI.fmtInt(into), UI.fmtInt(need), unit) else "MAXED",
		Font = Theme.Fonts.display,
		TextSize = S(11),
		TextColor3 = Theme.Colors.white,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = track,
	})
	UI.stroke(count, Theme.Colors.black, S(1.5), 0.2)
	return row
end

-- A grid tile: colored block, name on top, icon in the middle, pill at the bottom.
function MetaUI.tile(parent: Instance, o: TileOpts): TextButton
	local S = UI.S
	local w = o.size
	local h = math.floor(w * 1.18)
	local b = UI.button({
		Name = o.name,
		Text = "",
		BackgroundColor3 = o.color,
		BackgroundTransparency = if o.owned then 0 else 0.45,
		Size = UDim2.fromOffset(w, h),
		LayoutOrder = o.order,
		ClipsDescendants = true,
		Parent = parent,
	})
	UI.corner(b, S(8))
	UI.stroke(
		b,
		if o.selected then Theme.Colors.white else Theme.Colors.black,
		S(if o.selected then 3 else 1.5),
		if o.selected then 0 else 0.4
	)
	UI.text({
		Text = if o.nameTag then string.format('%s  <font color="#E8B64C">%s</font>', o.name, o.nameTag) else o.name,
		RichText = o.nameTag ~= nil,
		Font = Theme.Fonts.body,
		TextSize = S(12),
		TextColor3 = Theme.Colors.white,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(S(4), S(4)),
		Size = UDim2.new(1, -S(8), 0, S(16)),
		Parent = b,
	})
	local ic = MetaUI.icon(o.icon, b, math.floor(w * 0.78), o.iconColor or Theme.Colors.white, o.glyph)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.new(0.5, 0, 0.5, S(2))
	if not o.owned then
		for _, c in ic:GetDescendants() do
			if c:IsA("Frame") then
				c.BackgroundTransparency = 0.35
			end
		end
	end
	if not o.noPill then
		local pill, label = UI.pill(b, o.pill, Theme.Colors.bg, o.pillColor or Theme.Colors.cash, S(20), S(11))
		pill.AnchorPoint = Vector2.new(0.5, 1)
		pill.Position = UDim2.new(0.5, 0, 1, -S(6))
		pill.BackgroundTransparency = 0.15
		label.Font = Theme.Fonts.display
	end
	if o.tag then
		local t, tl = UI.pill(b, o.tag, o.tagColor or Theme.Colors.gold, Theme.Colors.bg, S(14), S(9))
		if o.noPill then
			-- The top bar carries the name and level: the tag sits where the pill was.
			t.AnchorPoint = Vector2.new(0.5, 1)
			t.Position = UDim2.new(0.5, 0, 1, -S(12))
		else
			t.AnchorPoint = Vector2.new(1, 0)
			t.Position = UDim2.new(1, -S(4), 0, S(4))
		end
		t.ZIndex = 3
		tl.ZIndex = 3
		tl.Font = Theme.Fonts.display
	end
	b.MouseEnter:Connect(function()
		UI.punch(b, 1.04, 0.15)
	end)
	return b
end

-- Section bar: "OWNED" / "UNOWNED" on a dark strip.
function MetaUI.header(parent: Instance, order: number, text: string)
	local S = UI.S
	local bar = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.new(1, 0, 0, S(26)),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.corner(bar, S(4))
	UI.text({
		Text = text,
		Font = Theme.Fonts.body,
		TextSize = S(14),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(10), 0),
		Size = UDim2.new(1, -S(10), 1, 0),
		Parent = bar,
	})
end

-- A wrapping row of tiles.
function MetaUI.row(parent: Instance, order: number, tileW: number, perRow: number): Frame
	local S = UI.S
	local f = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = parent,
	})
	UI.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(tileW, math.floor(tileW * 1.18)),
		CellPadding = UDim2.fromOffset(S(8), S(8)),
		FillDirectionMaxCells = perRow,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = f,
	})
	return f
end

-- Tile width for `perRow` tiles across a grid's width.
function MetaUI.tileWidth(grid: GuiObject, perRow: number): number
	local S = UI.S
	local w = math.floor((grid.AbsoluteSize.X - S(8) * (perRow - 1) - S(12)) / perRow)
	return math.clamp(w, S(64), S(110))
end

-- Stat row: label left, "current » next" right, next in green when it differs.
function MetaUI.statRow(parent: Instance, order: number, label: string, current: string, nextValue: string?): Frame
	local S = UI.S
	local row = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.new(1, 0, 0, S(28)),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.corner(row, S(4))
	UI.text({
		Text = label,
		Font = Theme.Fonts.body,
		TextSize = S(13),
		TextColor3 = Theme.Colors.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(10), 0),
		Size = UDim2.new(0.45, 0, 1, 0),
		Parent = row,
	})
	local value = UI.text({
		Text = current,
		Font = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(10), 0, 0),
		Size = UDim2.new(0.55, 0, 1, 0),
		RichText = true,
		Parent = row,
	})
	if nextValue and nextValue ~= current then
		value.Text = string.format('%s <font color="#2FD46A">» %s</font>', current, nextValue)
	end
	return row
end

-- Big flat action button. kind: green | pink | blue | gold | disabled.
function MetaUI.button(parent: Instance, order: number, text: string, kind: string, onPress: (() -> ())?): TextButton
	local S = UI.S
	local enabled = kind ~= "disabled"
	local bg = if kind == "green"
		then MetaUI.Green
		elseif kind == "pink" then MetaUI.Pink
		elseif kind == "blue" then Theme.Colors.blue
		elseif kind == "gold" then Theme.Colors.gold
		else Theme.Colors.panel2
	local fg = if kind == "green" or kind == "gold"
		then Theme.Colors.bg
		elseif enabled then Theme.Colors.white
		else Theme.Colors.grey
	local b = UI.button({
		Text = text,
		Font = Theme.Fonts.body,
		TextSize = S(17),
		TextColor3 = fg,
		BackgroundColor3 = bg,
		Size = UDim2.new(1, 0, 0, S(44)),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.corner(b, S(6))
	if enabled and onPress then
		b.Activated:Connect(function()
			UI.punch(b, 0.95, 0.15)
			onPress()
		end)
		b.MouseEnter:Connect(function()
			UI.punch(b, 1.03, 0.12)
		end)
	end
	return b
end

-- Every refresh rebuilds the grid, so the scroll offset is remembered per `scrollKey` (one per tab / category)
-- and put back once the new canvas has its size. Only the player's own scrolling updates the memory.
local scrollMemory: { [string]: number } = {}

-- Two-column layout: scrolling grid left, detail card (vertical list) right.
function MetaUI.columns(panel: Frame, rightW: number, topOffset: number?, scrollKey: string?): (ScrollingFrame, Frame)
	local S = UI.S
	local y = topOffset or 0
	local left = UI.new("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, -rightW - S(12), 1, -y),
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = S(6),
		ScrollBarImageColor3 = Theme.Colors.grey,
		Parent = panel,
	}) :: ScrollingFrame
	if scrollKey then
		local armed = false
		left:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			if armed then
				scrollMemory[scrollKey] = left.CanvasPosition.Y
			end
		end)
		local remembered = scrollMemory[scrollKey] or 0
		-- The canvas only knows its height after the tiles land; restore on the next frame and once more a
		-- beat later, then start recording.
		task.defer(function()
			if left.Parent then
				left.CanvasPosition = Vector2.new(0, remembered)
			end
			task.delay(0.05, function()
				if left.Parent then
					left.CanvasPosition = Vector2.new(0, remembered)
					armed = true
				end
			end)
		end)
	end
	local right = UI.frame({
		Name = "Detail",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, y),
		Size = UDim2.new(0, rightW, 1, -y),
		Parent = panel,
	})
	UI.list(right, Enum.FillDirection.Vertical, S(8))
	return left, right
end

-- The detail card's image well: a colored block with a big icon. Returns the icon.
function MetaUI.well(
	card: Frame,
	order: number,
	color: Color3,
	icon: string,
	glyph: string?,
	iconColor: Color3?
): GuiObject
	local S = UI.S
	local well = UI.frame({
		BackgroundColor3 = color,
		Size = UDim2.new(1, 0, 0, S(150)),
		LayoutOrder = order,
		Parent = card,
	})
	UI.corner(well, S(8))
	UI.stroke(well, Theme.Colors.white, S(1.5), 0.6)
	local ic = MetaUI.icon(icon, well, S(130), iconColor or Theme.Colors.white, glyph)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, 0.5)
	return ic
end

-- Detail name and the small line under it.
function MetaUI.heading(card: Frame, order: number, name: string, sub: string, subColor: Color3?)
	local S = UI.S
	UI.text({
		Text = name,
		Font = Theme.Fonts.body,
		TextSize = S(24),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(28)),
		LayoutOrder = order,
		Parent = card,
	})
	UI.text({
		Text = sub,
		Font = Theme.Fonts.body,
		TextSize = S(11),
		TextColor3 = subColor or Theme.Colors.grey,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(14)),
		LayoutOrder = order + 1,
		Parent = card,
	})
end

-- Filter pill row (ALL · AR · SMG …). `onPick(id)` fires on press.
function MetaUI.pills(
	parent: Instance,
	entries: { { id: string, name: string, disabled: boolean? } },
	selected: string,
	onPick: (string) -> ()
): Frame
	local S = UI.S
	local row = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(34)),
		Parent = parent,
	})
	UI.list(row, Enum.FillDirection.Horizontal, S(6))
	for i, e in entries do
		local on = e.id == selected
		local b = UI.button({
			Text = e.name,
			Font = Theme.Fonts.body,
			TextSize = S(12),
			TextColor3 = if e.disabled then Theme.Colors.grey else Theme.Colors.white,
			BackgroundColor3 = if on then Theme.Colors.blue else Theme.Colors.panel,
			Size = UDim2.fromOffset(0, S(34)),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = i,
			Parent = row,
		})
		UI.corner(b, S(4))
		UI.pad(b, S(14), 0, S(14), 0)
		if not e.disabled then
			b.Activated:Connect(function()
				onPick(e.id)
			end)
		end
	end
	return row
end

return MetaUI
