--!strict
-- Shared pieces for the three tabs: item tiles (silhouette, name, LV / acquisition label, STARTER tag,
-- selected frame), stat rows with current > next deltas, and the action buttons.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Prices = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Prices"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))

local MetaUI = {}

export type TileOpts = {
	name: string,
	sub: string, -- LV n / ◆ 100 / CRATE / EVENT / OWNED
	subColor: Color3?,
	color: Color3, -- silhouette / accent color
	owned: boolean,
	selected: boolean,
	tag: string?, -- STARTER / EQUIPPED / CRATE / EVENT
	tagColor: Color3?,
	icon: string, -- gun | mask | wrap | class
	size: number,
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
	return MetaUI.fmtGold(price), Theme.Colors.gold
end

local function icon(kind: string, parent: Frame, size: number, color: Color3): GuiObject
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
			Size = UDim2.fromScale(0.7, 0.7),
			Parent = f,
		})
		UI.corner(circle, 999)
	end
	f.Parent = parent
	return f
end

-- A grid tile. Returns the button so the tab can wire Activated.
function MetaUI.tile(parent: Instance, o: TileOpts): TextButton
	local S = UI.S
	local size = o.size
	local b = UI.button({
		Name = o.name,
		Text = "",
		BackgroundColor3 = if o.owned then Theme.Colors.panel else Theme.Colors.bg,
		Size = UDim2.fromOffset(size, size + S(26)),
		LayoutOrder = o.order,
		Parent = parent,
	})
	UI.corner(b, S(10))
	UI.stroke(
		b,
		if o.selected then Theme.Colors.blue else (if o.owned then Theme.Colors.grey else Theme.Colors.panel2),
		S(if o.selected then 3 else 1.5)
	)
	local well = UI.frame({
		BackgroundColor3 = Theme.Colors.panel2,
		BackgroundTransparency = if o.owned then 0 else 0.5,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(6)),
		Size = UDim2.fromOffset(size - S(16), size - S(28)),
		ClipsDescendants = true,
		Parent = b,
	})
	UI.corner(well, S(8))
	local ic = icon(
		o.icon,
		well,
		math.floor((size - S(28)) * 0.9),
		if o.owned or o.icon == "wrap" or o.icon == "mask" then o.color else Theme.Colors.grey
	)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, 0.5)
	UI.text({
		Text = string.upper(o.name),
		Font = Theme.Fonts.display,
		TextSize = S(11),
		TextColor3 = if o.owned then Theme.Colors.text else Theme.Colors.grey,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.new(0, S(4), 0, size - S(20)),
		Size = UDim2.new(1, -S(8), 0, S(16)),
		Parent = b,
	})
	UI.text({
		Text = o.sub,
		TextSize = S(10),
		TextColor3 = o.subColor or Theme.Colors.gold,
		Position = UDim2.new(0, 0, 0, size - S(4)),
		Size = UDim2.new(1, 0, 0, S(14)),
		Parent = b,
	})
	if o.tag then
		local pill, label = UI.pill(b, o.tag, o.tagColor or Theme.Colors.gold, Theme.Colors.bg, S(14), S(9))
		pill.AnchorPoint = Vector2.new(1, 0)
		pill.Position = UDim2.new(1, S(4), 0, -S(6))
		pill.ZIndex = 3
		label.ZIndex = 3
		label.Font = Theme.Fonts.display
	end
	b.MouseEnter:Connect(function()
		UI.punch(b, 1.04, 0.15)
	end)
	return b
end

-- One stat row: label left, "current" right, with " > next" in green when `next` differs.
function MetaUI.statRow(parent: Instance, order: number, label: string, current: string, nextValue: string?): Frame
	local S = UI.S
	local row = UI.frame({
		BackgroundColor3 = Theme.Colors.panel2,
		Size = UDim2.new(1, 0, 0, S(24)),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.corner(row, S(6))
	UI.text({
		Text = label,
		TextSize = S(11),
		TextColor3 = Theme.Colors.grey,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(10), 0),
		Size = UDim2.new(0.4, 0, 1, 0),
		Parent = row,
	})
	local value = UI.text({
		Text = current,
		Font = Theme.Fonts.display,
		TextSize = S(13),
		TextColor3 = Theme.Colors.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(10), 0, 0),
		Size = UDim2.new(0.6, 0, 1, 0),
		RichText = true,
		Parent = row,
	})
	if nextValue and nextValue ~= current then
		value.Text = string.format('%s <font color="#8FE3A1">> %s</font>', current, nextValue)
	end
	return row
end

-- Action button: full width of its parent list, colored by kind (primary gold / blue / grey disabled).
function MetaUI.button(parent: Instance, order: number, text: string, kind: string, onPress: (() -> ())?): TextButton
	local S = UI.S
	local enabled = kind ~= "disabled"
	local bg = if kind == "primary"
		then Theme.Colors.gold
		elseif kind == "blue" then Theme.Colors.blue
		elseif kind == "green" then Theme.Colors.cash
		else Theme.Colors.panel2
	local fg = if kind == "primary" or kind == "blue" or kind == "green" then Theme.Colors.bg else Theme.Colors.grey
	local b = UI.button({
		Text = text,
		Font = Theme.Fonts.display,
		TextSize = S(15),
		TextColor3 = fg,
		BackgroundColor3 = bg,
		Size = UDim2.new(1, 0, 0, S(38)),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.corner(b, S(10))
	UI.stroke(b, if enabled then Theme.Colors.black else Theme.Colors.grey, S(1.5), if enabled then 0.5 else 0.6)
	if enabled and onPress then
		b.Activated:Connect(function()
			UI.punch(b, 0.94, 0.15)
			onPress()
		end)
		b.MouseEnter:Connect(function()
			UI.punch(b, 1.03, 0.12)
		end)
	end
	return b
end

-- Two-column layout inside a panel: a scrolling grid on the left, a detail card on the right.
function MetaUI.columns(panel: Frame, rightW: number): (ScrollingFrame, Frame)
	local S = UI.S
	local left = UI.new("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -rightW - S(12), 1, 0),
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = S(6),
		ScrollBarImageColor3 = Theme.Colors.grey,
		Parent = panel,
	}) :: ScrollingFrame
	local right = UI.frame({
		Name = "Detail",
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, rightW, 1, 0),
		Parent = panel,
	})
	UI.corner(right, S(12))
	UI.stroke(right, Theme.Colors.grey, S(1.5), 0.5)
	return left, right
end

-- Section header inside a grid ("OWNED", "UNOWNED").
function MetaUI.header(parent: Instance, order: number, text: string)
	local S = UI.S
	UI.text({
		Text = text,
		Font = Theme.Fonts.display,
		TextSize = S(13),
		TextColor3 = Theme.Colors.grey,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(20)),
		LayoutOrder = order,
		Parent = parent,
	})
end

-- A row of tiles that wraps: a Frame with a grid layout and automatic height.
function MetaUI.row(parent: Instance, order: number, tileSize: number, perRow: number): Frame
	local S = UI.S
	local f = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = parent,
	})
	UI.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(tileSize, tileSize + S(26)),
		CellPadding = UDim2.fromOffset(S(8), S(10)),
		FillDirectionMaxCells = perRow,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = f,
	})
	return f
end

MetaUI.Prices = Prices

return MetaUI
