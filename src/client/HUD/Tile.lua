--!strict
-- Shared tile builder for the buy and ability columns: hotkey chip, price pill, icon well, name.
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Icons = require(Client:WaitForChild("UI"):WaitForChild("Icons"))
local ModelIcon = require(Client:WaitForChild("UI"):WaitForChild("ModelIcon"))
local ClientState = require(Client:WaitForChild("ClientState"))

export type Tile = {
	button: TextButton,
	stroke: UIStroke,
	well: Frame,
	icon: GuiObject,
	name: TextLabel,
	priceLabel: TextLabel,
	pricePill: Frame,
	hotkeyChip: Frame?,
	tooltip: Frame?,
	enabled: boolean,
	onPress: (() -> ())?,
	setAffordable: (boolean) -> (),
	setPrice: (number?) -> (),
	setEnabled: (boolean) -> (),
	setGreyed: (boolean) -> (),
	shake: () -> (),
	showTooltip: (string) -> (),
}

export type Opts = {
	name: string,
	hotkey: string,
	order: number,
	iconKind: string, -- gun | plus | an ability's Icons.lua id (Classes.lua `icon`)
	stub: boolean?,
	showPrice: boolean?,
	weaponId: string?, -- iconKind "gun": the gun to show as a live model (else the generic glyph)
}

local Tile = {}

-- Text a kind falls back to when Icons.lua has no pictogram for it.
local FALLBACK: { [string]: string } =
	{ plus = "+", air = "AIR", turret = "TRT", wall = "WAL", boom = "BOM", stim = "STM", melee = "V" }

local function makeIcon(kind: string, parent: Frame, size: number, weaponId: string?): GuiObject
	if kind == "gun" then
		-- A known gun is its live model (UI art pass); without one, the generic weapons glyph.
		if weaponId then
			return ModelIcon.weapon(parent, weaponId, UDim2.new(1, -4, 1, -4))
		end
		return UI.gunIcon(parent, Theme.Colors.grey, size)
	end
	-- A pictogram (UI/Icons.lua): "plus", or an ability's icon id straight from Classes.lua; cut-outs take the
	-- well's colour.
	local fallback = FALLBACK[kind] or string.upper(string.sub(kind, 1, 3))
	return Icons.draw(parent, kind, math.floor(size * 0.78), Theme.Colors.grey, Theme.Colors.panel2, fallback)
end

function Tile.build(parent: Instance, opts: Opts, tileSize: Vector2, showChips: boolean): Tile
	local S = UI.S
	local w, h = S(tileSize.X), S(tileSize.Y)
	local compact = tileSize.Y <= 70

	local button = UI.button({
		Name = opts.name,
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = Theme.Colors.panel,
		LayoutOrder = opts.order,
		Parent = parent,
	})
	UI.corner(button, S(10))
	local stroke = UI.stroke(button, Theme.Colors.grey, S(2))

	local hotkeyChip: Frame? = nil
	if showChips then
		local chip = UI.frame({
			Name = "Hotkey",
			BackgroundColor3 = Theme.Colors.panel2,
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.fromOffset(-S(4), -S(6)),
			Size = UDim2.fromOffset(S(22), S(18)),
			ZIndex = 3,
			Parent = button,
		})
		chip.Size = UDim2.fromOffset(S(26), S(22))
		UI.corner(chip, S(5))
		UI.stroke(chip, Theme.Colors.grey, S(1), 0.4)
		UI.text({
			Text = opts.hotkey,
			FontFace = Theme.Fonts.display,
			TextSize = S(15),
			TextColor3 = Theme.Colors.text,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			Parent = chip,
		})
		hotkeyChip = chip
	end

	local pricePill, priceLabel = UI.pill(button, "", Theme.Colors.panel2, Theme.Colors.gold, S(22), S(14))
	priceLabel.FontFace = Theme.Fonts.display
	pricePill.AnchorPoint = Vector2.new(1, 0)
	pricePill.Position = UDim2.new(1, S(6), 0, -S(8))
	pricePill.ZIndex = 3
	priceLabel.ZIndex = 3
	UI.stroke(pricePill, Theme.Colors.gold, S(1), 0.3)
	pricePill.Visible = opts.showPrice == true

	-- Round 19o: the icon well fills the tile above a name strip, and the name scales to the strip's width (up to
	-- NAME_MAX) so short names read big and long ones still fit on one line.
	local inset = if compact then S(3) else S(5)
	local nameH = if compact then S(14) else S(24)
	local wellH = h - inset - nameH - S(2)
	local well = UI.frame({
		Name = "IconWell",
		BackgroundColor3 = Theme.Colors.panel2,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, inset),
		Size = UDim2.fromOffset(w - inset * 2, wellH),
		ClipsDescendants = true,
		Parent = button,
	})
	UI.corner(well, S(4))
	local icon = makeIcon(opts.iconKind, well, wellH, opts.weaponId)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)

	local name = UI.text({
		Name = "Name",
		Text = opts.name,
		FontFace = Theme.Fonts.display,
		TextScaled = true,
		TextColor3 = Theme.Colors.text,
		Size = UDim2.new(1, -inset * 2, 0, nameH),
		Position = UDim2.new(0, inset, 1, -nameH - S(1)),
		Parent = button,
	})
	UI.new("UITextSizeConstraint", { MaxTextSize = if compact then S(13) else S(21), Parent = name })

	local tooltip: Frame? = nil
	if opts.stub then
		local tip = UI.frame({
			Name = "Tooltip",
			BackgroundColor3 = Theme.Colors.panel2,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0, -S(10)),
			Size = UDim2.fromOffset(S(60), S(22)),
			Visible = false,
			ZIndex = 5,
			Parent = button,
		})
		UI.corner(tip, S(6))
		UI.stroke(tip, Theme.Colors.grey, S(1))
		UI.text({
			Text = "STUB",
			TextSize = S(11),
			TextColor3 = Theme.Colors.grey,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
			Parent = tip,
		})
		tooltip = tip
		button.MouseEnter:Connect(function()
			tip.Visible = true
		end)
		button.MouseLeave:Connect(function()
			tip.Visible = false
		end)
	end

	local tile = {} :: Tile
	tile.button = button
	tile.stroke = stroke
	tile.well = well
	tile.icon = icon
	tile.name = name
	tile.priceLabel = priceLabel
	tile.pricePill = pricePill
	tile.hotkeyChip = hotkeyChip
	tile.tooltip = tooltip
	tile.enabled = true
	tile.onPress = nil

	local wasAffordable: boolean? = nil
	function tile.setAffordable(ok: boolean)
		stroke.Color = if ok then Theme.Colors.gold else Theme.Colors.grey
		priceLabel.TextColor3 = if ok then Theme.Colors.gold else Theme.Colors.grey
		if ok and wasAffordable == false then
			-- Just became affordable: ready pop.
			UI.punch(button, 1.18, 0.35)
			stroke.Thickness = S(5)
			UI.tween(stroke, { Thickness = S(2) }, 0.4)
			UI.sound(Theme.Sounds.toast, 1.5, 0.3)
		end
		wasAffordable = ok
	end

	local currentPrice: number? = nil
	function tile.setPrice(price: number?)
		currentPrice = price
		if price then
			priceLabel.Text = UI.fmtCash(price)
			pricePill.Visible = true
		else
			pricePill.Visible = false
		end
	end

	function tile.setEnabled(on: boolean)
		tile.enabled = on
	end

	function tile.setGreyed(on: boolean)
		button.BackgroundColor3 = if on then Theme.Colors.bg else Theme.Colors.panel
		well.BackgroundTransparency = if on then 0.5 else 0
		name.TextColor3 = if on then Theme.Colors.grey else Theme.Colors.text
	end

	function tile.shake()
		UI.shake(button, UI.S(3), 0.2)
		stroke.Color = Theme.Colors.malus
		task.delay(0.25, function()
			local sync = ClientState.sync
			if sync and currentPrice then
				tile.setAffordable(sync.cash >= currentPrice)
			end
		end)
	end

	function tile.showTooltip(text: string)
		local tip = tooltip
		if not tip then
			return
		end
		local label = tip:FindFirstChildOfClass("TextLabel")
		if label then
			label.Text = text
		end
		tip.Visible = true
		task.delay(1, function()
			tip.Visible = false
		end)
	end

	button.Activated:Connect(function()
		if opts.stub then
			tile.showTooltip("STUB")
			return
		end
		if tile.enabled and tile.onPress then
			UI.punch(button, 0.92, 0.18)
			UI.sound(Theme.Sounds.toast, 1.4, 0.35)
			tile.onPress()
		end
	end)
	button.MouseEnter:Connect(function()
		if not UserInputService.TouchEnabled then
			UI.punch(button, 1.04, 0.15)
		end
	end)

	return tile
end

return Tile
