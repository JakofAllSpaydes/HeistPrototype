--!strict
-- The upgrade card's look, shared by the pick-3 overlay (UpgradeOverlay) and the dealer's stands (DealerUI,
-- Round 16): the stat icon tile in the tier color, and the card body (NAME, the big number, the stat line, the
-- red malus strip) laid out top-down from a y offset.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Upgrades = require(Shared:WaitForChild("Upgrades"))

local UI = require(script.Parent:WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Icons = require(script.Parent:WaitForChild("Icons"))

local CardFace = {}

function CardFace.tierColor(tier: number): Color3
	return Rarity.color(math.clamp(tier, 1, 5))
end

-- Stat icon: a rounded tile in a tier color with the stat's pictogram (Icons.lua, keyed by the Upgrades.lua stat id;
-- the short name is the text fallback). Shared by cards, reels and tracker.
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
	-- Cut-outs take the tile's colour as it reads over the card (the tile is slightly see-through).
	local detail = color:Lerp(Theme.Colors.panel, if ghost then 0.55 else 0.1)
	local icon = Icons.draw(tile, statId, math.floor(size * 0.72), Theme.Colors.bg, detail, Upgrades.shortName(statId))
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	if ghost then
		Icons.setTransparency(icon, 0.3)
	end
	return tile
end

-- A conditional (synergy) card's pill, centred on the card's top edge, saying why it showed up ("TORCH SYNERGY",
-- Upgrades.synergyTag). nil (and nothing drawn) for ordinary stats. `height` in px.
function CardFace.synergyPill(parent: GuiObject, statId: string, height: number): Frame?
	local tag = Upgrades.synergyTag(statId)
	if not tag then
		return nil
	end
	local pill, label =
		UI.pill(parent, tag, Color3.fromHex(Config.SynergyColor), Theme.Colors.bg, height, math.floor(height * 0.62))
	pill.Name = "Synergy"
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromScale(0.5, 0)
	pill.ZIndex = 4
	label.ZIndex = 4
	label.FontFace = Theme.Fonts.display
	return pill
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
		FontFace = Theme.Fonts.display,
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
		FontFace = Theme.Fonts.display,
		TextSize = s(44),
		TextColor3 = Theme.Colors.cash,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, s(48)),
		Parent = parent,
	})
	y += s(48)
	UI.text({
		Text = smallText,
		FontFace = Theme.Fonts.display,
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
