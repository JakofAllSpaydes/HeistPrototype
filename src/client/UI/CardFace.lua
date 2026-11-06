--!strict
-- The upgrade card's look, shared by the pick-3 overlay (UpgradeOverlay) and the dealer's stands (DealerUI,
-- Round 16): the stat icon tile in the tier color, and the card body (NAME, the big number, the stat line, the
-- red malus strip) laid out top-down from a y offset.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarity = require(Shared:WaitForChild("Rarity"))
local Upgrades = require(Shared:WaitForChild("Upgrades"))

local UI = require(script.Parent:WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local CardFace = {}

function CardFace.tierColor(tier: number): Color3
	return Rarity.color(math.clamp(tier, 1, 5))
end

-- Stat icon: a rounded tile in a tier color with the short name. Shared by cards, reels and tracker.
function CardFace.statIcon(parent: Instance, statId: string, color: Color3, size: number, ghost: boolean): Frame
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

-- The card body under the icon: NAME, the big number ("+30%" / "NEW"), the stat line, and the malus strip on a
-- tradeoff. `S` scales design px; `top` is where the name starts. Returns the y under the last row.
function CardFace.body(parent: GuiObject, card: any, S: (number) -> number, top: number, scale: number?): number
	local k = scale or 1
	local function s(n: number): number
		return S(n * k)
	end
	local y = top
	UI.text({
		Text = string.upper(tostring(card.name or "")),
		Font = Theme.Fonts.display,
		TextSize = s(20),
		TextWrapped = true,
		Position = UDim2.fromOffset(s(8), y),
		Size = UDim2.new(1, -s(16), 0, s(28)),
		Parent = parent,
	})
	y += s(30)
	local bigText, smallText = Upgrades.cardTexts(card.stat, card.pct)
	UI.text({
		Text = bigText,
		Font = Theme.Fonts.display,
		TextSize = s(44),
		TextColor3 = Theme.Colors.cash,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, s(48)),
		Parent = parent,
	})
	y += s(48)
	UI.text({
		Text = smallText,
		Font = Theme.Fonts.display,
		TextSize = s(16),
		TextColor3 = Theme.Colors.cash,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, s(20)),
		Parent = parent,
	})
	y += s(26)
	if card.isTradeoff and card.malusStat and card.malusPct then
		local malus = UI.frame({
			BackgroundColor3 = Theme.Colors.malus,
			BackgroundTransparency = 0.85,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, y),
			Size = UDim2.new(1, -s(24), 0, s(22)),
			Parent = parent,
		})
		UI.corner(malus, s(7))
		UI.stroke(malus, Theme.Colors.malus, S(1), 0.4)
		UI.text({
			Text = Upgrades.effectLine(card.malusStat, -card.malusPct),
			TextSize = s(12),
			TextColor3 = Theme.Colors.malus,
			Size = UDim2.fromScale(1, 1),
			Parent = malus,
		})
		y += s(28)
	end
	return y
end

return CardFace
