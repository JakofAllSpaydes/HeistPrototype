--!strict
-- Brief 6 GOLD section: six packs in a 3 × 2 grid (GoldPacks.lua), the art filling each card, BEST VALUE on the pack
-- with the most Gold per Robux. Buying plays a Gold burst into the header counter, which counts up, and the chime.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GoldPacks = require(Shared:WaitForChild("GoldPacks"))
local Products = require(Shared:WaitForChild("Products"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local Card = require(script.Parent:WaitForChild("Card"))

local GoldTab = {}

function GoldTab.render(ctx: any)
	local S = UI.S
	local root = ctx.content :: Frame
	UI.text({
		Text = "GOLD",
		FontFace = Theme.Fonts.display,
		TextSize = S(28),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(32)),
		ZIndex = 6,
		Parent = root,
	})
	UI.text({
		Text = "Weapons, classes, upgrades and cosmetics in the customization scene all spend Gold.",
		FontFace = Theme.Fonts.body,
		TextSize = S(13),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, S(32)),
		Size = UDim2.new(1, 0, 0, S(18)),
		ZIndex = 6,
		Parent = root,
	})
	local best = GoldPacks.bestValueId()
	local area = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, S(64)),
		Size = UDim2.new(1, 0, 1, -S(64)),
		ZIndex = 6,
		Parent = root,
	})
	local areaW, areaH = area.AbsoluteSize.X, area.AbsoluteSize.Y
	if areaW < 50 or areaH < 50 then
		areaW, areaH = S(1000), S(470)
	end
	local cols = 3
	local gap = S(22)
	local cardW = math.floor(math.min((areaW - gap * (cols - 1)) / cols, S(300)) / UI.scale)
	local cardH = math.floor(math.min((areaH - gap) / 2, S(250)) / UI.scale)
	local grid = UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = area })
	UI.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(S(cardW), S(cardH)),
		CellPadding = UDim2.fromOffset(gap, gap),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local cards: { GuiObject } = {}
	for i, pack in GoldPacks.List do
		local product = Products.ById[pack.id]
		local handle: any
		handle = Card.new(grid, {
			size = Vector2.new(cardW, cardH),
			art = { kind = "gold", amount = pack.gold },
			artScale = 0.9,
			wellShare = 0.58,
			title = string.format("%s ◆", UI.fmtInt(pack.gold)),
			price = product.price,
			ribbons = if pack.id == best then { "BEST VALUE" } else {},
			hero = pack.id == best,
			layoutOrder = i,
			z = 8,
			onClick = function()
				ctx.buy(pack.id, {
					onSuccess = function()
						local h = handle.holder :: Frame
						ctx.goldBurst(h.AbsolutePosition + h.AbsoluteSize / 2)
						Fx.burst(
							ctx.gui,
							UDim2.fromOffset(
								h.AbsolutePosition.X + h.AbsoluteSize.X / 2,
								h.AbsolutePosition.Y + h.AbsoluteSize.Y / 3
							),
							Theme.Colors.gold,
							20,
							80
						)
					end,
				})
			end,
		})
		table.insert(cards, handle.holder)
	end
	if not ctx.quiet then
		Fx.cascade(cards, 0.04)
	end
end

return GoldTab
