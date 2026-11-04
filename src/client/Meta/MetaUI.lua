--!strict
-- Shared pieces for the three tabs, styled to the reference: filter pills, dark section bars (OWNED /
-- UNOWNED), colored item tiles with the name on top and a price / level pill at the bottom, stat rows with
-- "42 » 54" deltas, big flat action buttons, and the two-column grid + detail layout.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Prices = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Prices"))

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
}

function MetaUI.fmtGold(n: number): string
	return "◆ " .. UI.fmtNum(n)
end

-- Acquisition label for an unowned Direct / Crate / Event item.
function MetaUI.acquisition(saleType: string, price: number): (string, Color3)
	if saleType == "Crate" then
		return "CRATE", Theme.Colors.blue
	elseif saleType == "Event" then
		return "EVENT", Theme.Colors.malus
	end
	return MetaUI.fmtGold(price), Theme.Colors.cash
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
		Text = o.name,
		Font = Theme.Fonts.body,
		TextSize = S(12),
		TextColor3 = Theme.Colors.white,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(0, S(4)),
		Size = UDim2.new(1, 0, 0, S(16)),
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
	local pill, label = UI.pill(b, o.pill, Theme.Colors.bg, o.pillColor or Theme.Colors.cash, S(20), S(11))
	pill.AnchorPoint = Vector2.new(0.5, 1)
	pill.Position = UDim2.new(0.5, 0, 1, -S(6))
	pill.BackgroundTransparency = 0.15
	label.Font = Theme.Fonts.display
	if o.tag then
		local t, tl = UI.pill(b, o.tag, o.tagColor or Theme.Colors.gold, Theme.Colors.bg, S(14), S(9))
		t.AnchorPoint = Vector2.new(1, 0)
		t.Position = UDim2.new(1, -S(4), 0, S(4))
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

-- Two-column layout: scrolling grid left, detail card (vertical list) right.
function MetaUI.columns(panel: Frame, rightW: number, topOffset: number?): (ScrollingFrame, Frame)
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
