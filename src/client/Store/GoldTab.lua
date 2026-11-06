--!strict
-- Brief 6 GOLD tab: six packs on two shelves (GoldPacks.lua), the R$ per 100 Gold under each, BEST VALUE on the pack
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
		Font = Theme.Fonts.display,
		TextSize = S(26),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(30)),
		ZIndex = 6,
		Parent = root,
	})
	UI.text({
		Text = "Weapons, classes, upgrades and cosmetics in the customization scene all spend Gold.",
		Font = Theme.Fonts.body,
		TextSize = S(11),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, S(30)),
		Size = UDim2.new(1, 0, 0, S(16)),
		ZIndex = 6,
		Parent = root,
	})
	local best = GoldPacks.bestValueId()
	local area = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, S(56)),
		Size = UDim2.new(1, 0, 1, -S(56)),
		ZIndex = 6,
		Parent = root,
	})
	local areaH = area.AbsoluteSize.Y
	local areaW = area.AbsoluteSize.X
	if areaW < 50 or areaH < 50 then
		areaW, areaH = S(760), S(560) -- layout not resolved yet: the desktop panel size
	end
	local cols = 3
	local cardW = math.floor(math.min((areaW - S(24) * (cols - 1)) / cols, S(230)) / UI.scale)
	local cardH = math.floor(math.min((areaH - S(48)) / 2, S(250)) / UI.scale)
	local cards: { GuiObject } = {}
	for row = 0, 1 do
		-- The shelf: a dark plank with a gold edge under each row of packs.
		local shelfY = row * (S(cardH) + S(24)) + S(cardH) - S(8)
		local shelf = UI.frame({
			BackgroundColor3 = Color3.fromHex("24201A"),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, shelfY),
			Size = UDim2.new(1, 0, 0, S(14)),
			ZIndex = 6,
			Parent = area,
		})
		UI.corner(shelf, S(4))
		UI.frame({
			BackgroundColor3 = Theme.Colors.gold,
			BackgroundTransparency = 0.3,
			Size = UDim2.new(1, 0, 0, S(2)),
			ZIndex = 7,
			Parent = shelf,
		})
		local rowFrame = UI.frame({
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, row * (S(cardH) + S(24))),
			Size = UDim2.new(1, 0, 0, S(cardH)),
			ZIndex = 8,
			Parent = area,
		})
		UI.list(rowFrame, Enum.FillDirection.Horizontal, S(24), Enum.HorizontalAlignment.Center)
		for c = 1, cols do
			local pack = GoldPacks.List[row * cols + c]
			if not pack then
				continue
			end
			local product = Products.ById[pack.id]
			local handle: any
			handle = Card.new(rowFrame, {
				size = Vector2.new(cardW, cardH - 12),
				art = { kind = "gold", amount = pack.gold },
				artScale = 0.72,
				title = string.format("%s ◆", UI.fmtInt(pack.gold)),
				sub = string.format("%s · R$ %.1f PER 100 ◆", pack.name, GoldPacks.per100(pack)),
				price = product.price,
				ribbons = if pack.id == best then { "BEST VALUE" } else {},
				hero = pack.id == best,
				layoutOrder = c,
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
	end
	if not ctx.quiet then
		Fx.cascade(cards, 0.04)
	end
end

return GoldTab
