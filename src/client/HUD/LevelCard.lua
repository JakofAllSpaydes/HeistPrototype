--!strict
-- The level card (reference board): a light-bordered dark card with the emblem on the left, `LV 19` and the
-- rank name, `+47 XP` in green on the right, and a bar underneath reading `993 / 3,110 XP`. One builder for
-- the hub HUD (above the Gold pill) and the floating card above the summary; `compact` is the hub size.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LevelRewards = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LevelRewards"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))

local LevelCard = {}

export type Card = {
	frame: Frame,
	set: (level: number, xp: number, need: number, gain: string?, sub: string?) -> (),
	punch: () -> (),
	flash: () -> (),
}

local GREEN = Color3.fromHex("5BF28A")
local EMBLEM = Color3.fromRGB(205, 208, 214)
local EMBLEM_DARK = Color3.fromRGB(42, 42, 48)
local BORDER = Color3.fromRGB(200, 203, 208)

-- The label's text shrinks to fit its box, never past Config.MobileTextMin; the TextSize it was given (after the
-- font factor) stays the ceiling.
local function fit(label: TextLabel)
	local c = UI.new("UITextSizeConstraint", { Parent = label })
	local function cap()
		c.MaxTextSize = math.clamp(math.max(label.TextSize, Config.MobileTextMin), 1, 100)
		c.MinTextSize = math.min(Config.MobileTextMin, c.MaxTextSize)
	end
	cap()
	label:GetPropertyChangedSignal("TextSize"):Connect(cap)
	label.TextScaled = true
end

-- The phone hub's card (`height` px tall): the emblem fills the height, LV and the rank share the top row, the bar
-- fills the row under it with `xp / need`, every label fitted to its box. No gain / sub line (the hub sets none).
local function buildSlim(parent: Instance, width: number, height: number): Card
	local S = UI.S
	local H = height
	local frame = UI.frame({
		Name = "LevelCard",
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.08,
		Size = UDim2.fromOffset(width, H),
		ZIndex = 10,
		Parent = parent,
	})
	UI.corner(frame, S(3))
	UI.stroke(frame, BORDER, S(2), 0.1)
	local pad = S(5)
	local emblemSize = H - pad * 2
	local emblem = UI.frame({
		Name = "Emblem",
		BackgroundColor3 = EMBLEM,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, pad, 0.5, 0),
		Size = UDim2.fromOffset(emblemSize, emblemSize),
		ZIndex = 11,
		Parent = frame,
	})
	UI.corner(emblem, S(4))
	UI.stroke(emblem, EMBLEM_DARK, S(1.5), 0.2)
	for _, side in { -1, 1 } do
		local bar = UI.frame({
			BackgroundColor3 = EMBLEM_DARK,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, side * emblemSize * 0.16, 0.36, 0),
			Size = UDim2.fromOffset(math.floor(emblemSize * 0.36), math.max(2, math.floor(emblemSize * 0.11))),
			Rotation = side * 30,
			ZIndex = 12,
			Parent = emblem,
		})
		UI.corner(bar, S(2))
	end
	UI.text({
		Text = "★",
		FontFace = Theme.Fonts.display,
		TextSize = math.floor(emblemSize * 0.36),
		TextColor3 = EMBLEM_DARK,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.72),
		Size = UDim2.fromScale(1, 0.4),
		ZIndex = 12,
		Parent = emblem,
	})

	local textX = pad + emblemSize + S(7)
	local rowH = math.floor((H - pad * 2) * 0.52)
	local levelW = S(58)
	local levelLabel = UI.text({
		Text = "LV 1",
		FontFace = Theme.Fonts.display,
		TextSize = S(24),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(textX, pad),
		Size = UDim2.fromOffset(levelW, rowH),
		ZIndex = 11,
		Parent = frame,
	})
	fit(levelLabel)
	local rankLabel = UI.text({
		Text = "ROOKIE",
		FontFace = Theme.Fonts.display,
		TextSize = S(16),
		TextColor3 = Theme.Colors.grey,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(7), 0, pad),
		Size = UDim2.new(1, -(textX + levelW + S(4) + S(7)), 0, rowH),
		ZIndex = 11,
		Parent = frame,
	})
	fit(rankLabel)
	local barH = H - pad * 2 - rowH - S(3)
	local bar = UI.frame({
		BackgroundColor3 = Color3.fromRGB(16, 22, 18),
		Position = UDim2.fromOffset(textX, H - pad - barH),
		Size = UDim2.new(1, -textX - S(7), 0, barH),
		ZIndex = 11,
		Parent = frame,
	})
	UI.corner(bar, S(2))
	UI.stroke(bar, GREEN, S(1), 0.5)
	local fill = UI.frame({
		BackgroundColor3 = GREEN,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 12,
		Parent = bar,
	})
	UI.corner(fill, S(2))
	local barText = UI.text({
		Text = "",
		FontFace = Theme.Fonts.mono,
		TextSize = S(16),
		TextColor3 = Theme.Colors.white,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 13,
		Parent = bar,
	})
	fit(barText)
	UI.stroke(barText, Theme.Colors.black, S(1.5), 0.3)

	return {
		frame = frame,
		set = function(level: number, xp: number, need: number, _gain: string?, _sub: string?)
			levelLabel.Text = string.format("LV %d", level)
			rankLabel.Text = LevelRewards.rank(level)
			fill.Size = UDim2.fromScale(math.clamp(xp / math.max(need, 1), 0, 1), 1)
			barText.Text = string.format("%s / %s", UI.fmtInt(xp), UI.fmtInt(need))
		end,
		punch = function()
			UI.punch(frame, 1.06, 0.35)
			UI.punch(levelLabel, 1.3, 0.45)
			UI.punch(emblem, 1.2, 0.45)
		end,
		flash = function()
			fill.BackgroundColor3 = Theme.Colors.white
			UI.tween(fill, { BackgroundColor3 = GREEN }, 0.45)
			emblem.BackgroundColor3 = Theme.Colors.white
			UI.tween(emblem, { BackgroundColor3 = EMBLEM }, 0.45)
		end,
	}
end

-- `slimHeight` (px): the phone hub's one-row card at that height instead (buildSlim).
function LevelCard.build(parent: Instance, width: number, compact: boolean?, slimHeight: number?): Card
	if slimHeight then
		return buildSlim(parent, width, slimHeight)
	end
	local S = UI.S
	local k = if compact then 0.72 else 1
	local function s(n: number): number
		return S(n * k)
	end
	local H = s(86)
	local frame = UI.frame({
		Name = "LevelCard",
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.08,
		Size = UDim2.fromOffset(width, H),
		ZIndex = 10,
		Parent = parent,
	})
	UI.corner(frame, s(4))
	UI.stroke(frame, BORDER, s(2.5), 0.1)

	-- Emblem: a light badge with a dark chevron over a star.
	local emblemSize = s(66)
	local emblem = UI.frame({
		Name = "Emblem",
		BackgroundColor3 = EMBLEM,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, s(10), 0.5, 0),
		Size = UDim2.fromOffset(emblemSize, emblemSize),
		Rotation = 0,
		ZIndex = 11,
		Parent = frame,
	})
	UI.corner(emblem, s(10))
	UI.stroke(emblem, EMBLEM_DARK, s(2), 0.2)
	for _, side in { -1, 1 } do
		local bar = UI.frame({
			BackgroundColor3 = EMBLEM_DARK,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, side * emblemSize * 0.16, 0.36, 0),
			Size = UDim2.fromOffset(math.floor(emblemSize * 0.36), math.floor(emblemSize * 0.11)),
			Rotation = side * 30,
			ZIndex = 12,
			Parent = emblem,
		})
		UI.corner(bar, s(2))
	end
	UI.text({
		Text = "★",
		FontFace = Theme.Fonts.display,
		TextSize = math.floor(emblemSize * 0.36),
		TextColor3 = EMBLEM_DARK,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.72),
		Size = UDim2.fromScale(1, 0.4),
		ZIndex = 12,
		Parent = emblem,
	})

	local textX = s(10) + emblemSize + s(14)
	local levelLabel = UI.text({
		Text = "LV 1",
		FontFace = Theme.Fonts.display,
		TextSize = s(30),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(textX, s(10)),
		Size = UDim2.fromOffset(s(110), s(34)),
		ZIndex = 11,
		Parent = frame,
	})
	local rankLabel = UI.text({
		Text = "ROOKIE",
		FontFace = Theme.Fonts.body,
		TextSize = s(15),
		TextColor3 = Theme.Colors.grey,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(textX + s(96), s(14)),
		Size = UDim2.fromOffset(s(160), s(26)),
		ZIndex = 11,
		Parent = frame,
	})
	local gainLabel = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = s(28),
		TextColor3 = GREEN,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -s(14), 0, s(8)),
		Size = UDim2.fromOffset(s(200), s(36)),
		ZIndex = 11,
		Parent = frame,
	})
	local subLabel = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = s(10),
		TextColor3 = GREEN,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -s(14), 0, s(42)),
		Size = UDim2.fromOffset(s(220), s(12)),
		ZIndex = 11,
		Parent = frame,
	})
	-- The bar with the number inside it.
	local bar = UI.frame({
		BackgroundColor3 = Color3.fromRGB(16, 22, 18),
		Position = UDim2.fromOffset(textX, H - s(30)),
		Size = UDim2.new(1, -textX - s(14), 0, s(22)),
		ZIndex = 11,
		Parent = frame,
	})
	UI.corner(bar, s(3))
	UI.stroke(bar, GREEN, s(1.5), 0.5)
	local fill = UI.frame({
		BackgroundColor3 = GREEN,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 12,
		Parent = bar,
	})
	UI.corner(fill, s(3))
	local barText = UI.text({
		Text = "",
		FontFace = Theme.Fonts.mono,
		TextSize = s(13),
		TextColor3 = Theme.Colors.white,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 13,
		Parent = bar,
	})
	UI.stroke(barText, Theme.Colors.black, s(1.5), 0.3)

	local card: Card = {
		frame = frame,
		set = function(level: number, xp: number, need: number, gain: string?, sub: string?)
			levelLabel.Text = string.format("LV %d", level)
			rankLabel.Text = LevelRewards.rank(level)
			gainLabel.Text = gain or ""
			subLabel.Text = sub or ""
			fill.Size = UDim2.fromScale(math.clamp(xp / math.max(need, 1), 0, 1), 1)
			barText.Text = string.format("%s / %s XP", UI.fmtInt(xp), UI.fmtInt(need))
		end,
		punch = function()
			UI.punch(frame, 1.06, 0.35)
			UI.punch(levelLabel, 1.5, 0.45)
			UI.punch(emblem, 1.25, 0.45)
		end,
		flash = function()
			fill.BackgroundColor3 = Theme.Colors.white
			UI.tween(fill, { BackgroundColor3 = GREEN }, 0.45)
			emblem.BackgroundColor3 = Theme.Colors.white
			UI.tween(emblem, { BackgroundColor3 = EMBLEM }, 0.45)
		end,
	}
	return card
end

return LevelCard
