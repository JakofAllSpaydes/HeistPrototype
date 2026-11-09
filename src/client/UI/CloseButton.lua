--!strict
-- The close control every window and modal shares (designer feedback, 9 Nov 2026: "they should all be red squares
-- with an X", top-right): a red square, a bold white X drawn as two crossed bars, sharp corners, a dark edge, the
-- same size on every screen (Config.CloseButtonSize at the UI basis, never under Config.CloseButtonMinPx real px so
-- it stays a thumb target on a phone).
--   CloseButton.new(parent, onClose, opts?) -> TextButton
--       anchored to the parent's top-right corner
--       opts.margin  px in from the parent's right edge (default UI.S(Config.CloseButtonMargin))
--       opts.top     px from the parent's top edge to the button's top (default: the margin); a full-screen scene
--                    passes Fx.topInset() so the Roblox top bar stays clear
--       opts.z       ZIndex (the bars draw one above; default 20)
--   CloseButton.size() -> number
--       its side in px, for headers that reserve room for it
-- Hover (or a pad's selection) lightens it and a press punches its scale (UI.punch, its one UIScale): it never moves
-- away from the cursor. Selectable, so a pad's selection can land on it; each screen keeps its own Esc / ButtonB
-- handler calling the same close function. Never give it UI.mobileGrow (that goes on containers).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local UI = require(script.Parent:WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local CloseButton = {}

local EDGE = Color3.fromHex("0B0B0F")

export type Opts = { margin: number?, top: number?, z: number? }

function CloseButton.size(): number
	return math.max(Config.CloseButtonMinPx, UI.S(Config.CloseButtonSize))
end

function CloseButton.new(parent: Instance, onClose: () -> (), opts: Opts?): TextButton
	local S = UI.S
	local o: Opts = opts or {}
	local size = CloseButton.size()
	local margin = o.margin or S(Config.CloseButtonMargin)
	local z = o.z or 20
	local red = Theme.Colors.red
	local lit = red:Lerp(Theme.Colors.white, 0.2)
	local b = UI.button({
		Name = "Close",
		Text = "",
		BackgroundColor3 = red,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -margin, 0, o.top or margin),
		Size = UDim2.fromOffset(size, size),
		Selectable = true,
		ZIndex = z,
		Parent = parent,
	})
	UI.corner(b, S(Theme.Corner))
	UI.stroke(b, EDGE, math.max(2, S(2)), 0)
	for _, rot in { 45, -45 } do
		UI.frame({
			Name = "Bar",
			BackgroundColor3 = Theme.Colors.white,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.64, 0.15),
			Rotation = rot,
			ZIndex = z + 1,
			Parent = b,
		})
	end
	local function light(on: boolean)
		UI.tween(b, { BackgroundColor3 = if on then lit else red }, 0.1)
	end
	b.MouseEnter:Connect(function()
		light(true)
	end)
	b.MouseLeave:Connect(function()
		light(false)
	end)
	b.SelectionGained:Connect(function()
		light(true)
	end)
	b.SelectionLost:Connect(function()
		light(false)
	end)
	b.Activated:Connect(function()
		UI.punch(b, 0.88, 0.18)
		UI.sound(Theme.Sounds.click, 1, 0.3)
		onClose()
	end)
	return b
end

return CloseButton
