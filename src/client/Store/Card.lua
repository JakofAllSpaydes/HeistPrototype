--!strict
-- Brief 6: the store card. Layered frames (rarity glow behind, dark body, 1px light edge, a rarity bar), the item
-- art on a pedestal with a slow idle bob, a price pill, tag ribbons (BEST VALUE, NEW, LIMITED, -30%) in the top
-- corner. States: hover lifts 4px and brightens the glow, press scales 0.96 and pulses, disabled dims to 40%,
-- owned shows a check and OWNED across the price. Epic+ art sparkles, Legendary art has rays.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Rewards = require(Shared:WaitForChild("Rewards"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local ItemArt = require(script.Parent:WaitForChild("ItemArt"))

local Card = {}

export type Spec = {
	size: Vector2, -- px at the basis (UI.S applied)
	rarity: number?, -- defaults to the art's rarity
	art: { kind: string, id: string?, amount: number?, sec: number? }?,
	artScale: number?, -- art size as a share of the well (0.62)
	wellShare: number?, -- the art well's share of the card height (0.5)
	title: string,
	sub: string?,
	price: number?, -- R$; nil = no price pill (use priceText)
	priceText: string?, -- replaces the R$ number ("FREE ×2", "SUBSCRIBED")
	priceColor: Color3?,
	ribbons: { string }?,
	owned: boolean?,
	enabled: boolean?,
	layoutOrder: number?,
	hero: boolean?, -- bigger glow, always-on particles
	onClick: (() -> ())?,
	z: number?,
}

export type Handle = {
	holder: Frame,
	body: TextButton,
	well: Frame,
	content: Frame, -- extra content area between the title and the price (tabs add rows here)
	setOwned: (boolean) -> (),
	setEnabled: (boolean) -> (),
	setPrice: (number?, string?) -> (),
	setSub: (string) -> (),
	setRibbons: ({ string }) -> (),
	glow: (number) -> (),
}

local RIBBON_COLORS: { [string]: Color3 } = {
	["BEST VALUE"] = Color3.fromHex("F2C14E"),
	["NEW"] = Color3.fromHex("3FD47A"),
	["LIMITED"] = Color3.fromHex("E8554D"),
	["POPULAR"] = Color3.fromHex("4D9FE8"),
	["OWNED"] = Color3.fromHex("9BA0A8"),
	["ACTIVE"] = Color3.fromHex("3FD47A"),
	["VIP"] = Color3.fromHex("F2C14E"),
}

local function ribbonColor(text: string): Color3
	if string.sub(text, 1, 1) == "-" then
		return Color3.fromHex("FF6A3D")
	end
	return RIBBON_COLORS[text] or Theme.Colors.blue
end

function Card.new(parent: Instance, spec: Spec): Handle
	local S = UI.S
	local z = spec.z or 5
	local w, h = S(spec.size.X), S(spec.size.Y)
	local rarity = spec.rarity or (if spec.art then Rewards.rarity(spec.art :: any) else 1)
	local color = Fx.rarityColor(rarity)
	local holder = UI.frame({
		Name = "Card",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(w, h),
		LayoutOrder = spec.layoutOrder or 0,
		ZIndex = z,
		Parent = parent,
	})
	-- The holder is what a parent layout positions; the Lift frame inside is what hovers and cascades.
	local lift = UI.frame({
		Name = "Lift",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = holder,
	})
	local _glowFrame, setGlow = Fx.glow(lift, color, S(12), z)
	setGlow(if spec.hero then 1.4 else 1)
	local body = UI.button({
		Name = "Body",
		BackgroundColor3 = Color3.fromHex("17171C"),
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = false,
		ZIndex = z + 1,
		Parent = lift,
	})
	UI.corner(body, S(12))
	UI.stroke(body, Color3.new(1, 1, 1), S(1), 0.82)
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromHex("2A2A33"), Color3.fromHex("121216")),
		Rotation = 90,
		Parent = body,
	})
	-- Rarity bar along the top edge.
	local bar = UI.frame({
		BackgroundColor3 = color,
		Position = UDim2.fromOffset(S(10), 0),
		Size = UDim2.new(1, -S(20), 0, S(3)),
		ZIndex = z + 2,
		Parent = body,
	})
	UI.corner(bar, S(2))

	-- Art well with a pedestal.
	local wellH = math.floor(h * (spec.wellShare or 0.5))
	local well = UI.frame({
		Name = "Well",
		BackgroundColor3 = Fx.shade(color, -0.75),
		BackgroundTransparency = 0.2,
		Position = UDim2.fromOffset(S(8), S(10)),
		Size = UDim2.new(1, -S(16), 0, wellH),
		ClipsDescendants = true,
		ZIndex = z + 2,
		Parent = body,
	})
	UI.corner(well, S(9))
	UI.new("UIGradient", {
		Color = ColorSequence.new(Fx.shade(color, -0.45), Fx.shade(color, -0.85)),
		Rotation = 90,
		Parent = well,
	})
	if rarity >= 5 then
		Fx.rays(well, color, 8, math.floor(math.max(w, wellH) * 1.4), z + 2, 10)
	end
	local pedestal = UI.frame({
		BackgroundColor3 = Color3.fromHex("0C0C10"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.86),
		Size = UDim2.fromScale(0.62, 0.14),
		ZIndex = z + 3,
		Parent = well,
	})
	UI.corner(pedestal, S(40))
	UI.stroke(pedestal, color, S(1.5), 0.25)
	if spec.art then
		local artSize = math.floor(math.min(w - S(16), wellH) * (spec.artScale or 0.62))
		local art = ItemArt.draw(well, spec.art :: any, artSize, z + 4)
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.Position = UDim2.fromScale(0.5, 0.46)
		Fx.bob(art, S(3), 2.6, if spec.hero then 3 else 1.5)
	end
	if rarity >= 4 or spec.hero then
		Fx.particles(well, color, if spec.hero then 6 else 3, z + 5)
	end

	-- Title and sub line.
	local textTop = S(10) + wellH + S(6)
	UI.text({
		Name = "Title",
		Text = spec.title,
		Font = Theme.Fonts.display,
		TextSize = S(if w < S(150) then 15 else 18),
		TextColor3 = Theme.Colors.white,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(S(10), textTop),
		Size = UDim2.new(1, -S(20), 0, S(22)),
		ZIndex = z + 2,
		Parent = body,
	})
	local subLabel = UI.text({
		Name = "Sub",
		Text = spec.sub or "",
		Font = Theme.Fonts.body,
		TextSize = S(10),
		TextColor3 = Theme.Colors.textDim,
		TextWrapped = true,
		Position = UDim2.fromOffset(S(10), textTop + S(22)),
		Size = UDim2.new(1, -S(20), 0, S(26)),
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = z + 2,
		Parent = body,
	})
	local content = UI.frame({
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(S(8), textTop + S(48)),
		Size = UDim2.new(1, -S(16), 1, -(textTop + S(48)) - (if spec.price or spec.priceText then S(48) else S(10))),
		ZIndex = z + 2,
		Parent = body,
	})

	-- Price pill.
	local pill = UI.frame({
		Name = "Price",
		BackgroundColor3 = Color3.fromHex("2FB75A"),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(10)),
		Size = UDim2.new(1, -S(20), 0, S(32)),
		ZIndex = z + 3,
		Parent = body,
	})
	UI.corner(pill, S(8))
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205)),
		Rotation = 90,
		Parent = pill,
	})
	local priceRow = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 4,
		Parent = pill,
	})
	UI.list(
		priceRow,
		Enum.FillDirection.Horizontal,
		S(6),
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Center
	)
	local badge = Fx.robux(priceRow, S(18), z + 5)
	local priceLabel = UI.text({
		Text = "",
		Font = Theme.Fonts.display,
		TextSize = S(17),
		TextColor3 = Theme.Colors.white,
		Size = UDim2.fromOffset(0, S(24)),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		ZIndex = z + 5,
		Parent = priceRow,
	})
	UI.stroke(priceLabel, Color3.fromHex("0E2A17"), S(1), 0.5)
	-- OWNED: a check and the word across the price.
	local ownedBand = UI.frame({
		Name = "Owned",
		BackgroundColor3 = Color3.fromHex("3A3D44"),
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = z + 6,
		Parent = pill,
	})
	UI.corner(ownedBand, S(8))
	local check = UI.frame({
		BackgroundColor3 = Color3.fromHex("3FD47A"),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, S(10), 0.5, 0),
		Size = UDim2.fromOffset(S(20), S(20)),
		ZIndex = z + 7,
		Parent = ownedBand,
	})
	UI.corner(check, S(10))
	UI.text({
		Text = "✓",
		Font = Theme.Fonts.body,
		TextSize = S(14),
		TextColor3 = Theme.Colors.white,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 8,
		Parent = check,
	})
	UI.text({
		Text = "OWNED",
		Font = Theme.Fonts.display,
		TextSize = S(17),
		TextColor3 = Theme.Colors.text,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 7,
		Parent = ownedBand,
	})

	-- Ribbons in the top-right corner.
	local ribbonHolder = UI.frame({
		Name = "Ribbons",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, S(6), 0, -S(6)),
		Size = UDim2.fromOffset(S(110), S(60)),
		ZIndex = z + 9,
		Parent = lift,
	})
	UI.list(ribbonHolder, Enum.FillDirection.Vertical, S(3), Enum.HorizontalAlignment.Right)
	local function setRibbons(list: { string })
		for _, c in ribbonHolder:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		for i, text in list do
			local rc = ribbonColor(text)
			local r = UI.frame({
				BackgroundColor3 = rc,
				Size = UDim2.fromOffset(0, S(20)),
				AutomaticSize = Enum.AutomaticSize.X,
				LayoutOrder = i,
				ZIndex = z + 10,
				Parent = ribbonHolder,
			})
			UI.corner(r, S(4))
			UI.stroke(r, Fx.shade(rc, -0.5), S(1), 0.2)
			UI.pad(r, S(7), 0, S(7), 0)
			UI.text({
				Text = text,
				Font = Theme.Fonts.display,
				TextSize = S(12),
				TextColor3 = if rc == RIBBON_COLORS["BEST VALUE"] or rc == RIBBON_COLORS["VIP"]
					then Theme.Colors.bg
					else Theme.Colors.white,
				Size = UDim2.fromScale(0, 1),
				AutomaticSize = Enum.AutomaticSize.X,
				ZIndex = z + 11,
				Parent = r,
			})
		end
	end
	setRibbons(spec.ribbons or {})

	local function setPrice(price: number?, text: string?)
		badge.Visible = price ~= nil and text == nil
		priceLabel.Text = if text then text elseif price then UI.fmtInt(price) else ""
		pill.Visible = price ~= nil or text ~= nil
		pill.BackgroundColor3 = spec.priceColor or Color3.fromHex("2FB75A")
	end
	setPrice(spec.price, spec.priceText)

	local handle = Fx.interactive(body, { lift = lift, glow = setGlow })
	if spec.onClick then
		body.Activated:Connect(function()
			if spec.onClick then
				spec.onClick()
			end
		end)
	end
	local function setOwned(on: boolean)
		ownedBand.Visible = on
	end
	setOwned(spec.owned == true)
	handle.setEnabled(spec.enabled ~= false)
	if spec.hero then
		Fx.pulse(setGlow, function()
			return holder.Parent ~= nil
		end, 2.2, 1.0, 1.6)
	end
	return {
		holder = holder,
		body = body,
		well = well,
		content = content,
		setOwned = setOwned,
		setEnabled = handle.setEnabled,
		setPrice = setPrice,
		setSub = function(t: string)
			subLabel.Text = t
		end,
		setRibbons = setRibbons,
		glow = setGlow,
	}
end

return Card
