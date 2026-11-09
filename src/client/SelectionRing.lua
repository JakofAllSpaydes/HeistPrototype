--!strict
-- Brief 11 step 4: the one selection ring. A drawn frame in the theme (an amber stroke, a soft outer glow), sliding
-- SelectionRingSlideSec between selections with a small scale pulse on arrival. Never Roblox's default selection
-- image (PlayerGui.SelectionImageObject is set to an empty frame). GamepadNav decides what it rings.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local SelectionRing = {}

local gui: ScreenGui? = nil
local ring: Frame? = nil
local target: GuiObject? = nil
local fromPos, fromSize = Vector2.zero, Vector2.zero
local animAt = -math.huge
local shown = false

local function cfg(key: string, default: any): any
	local v = (Config :: any)[key]
	return if v ~= nil then v else default
end

-- A GuiObject's rect in this ring's space (IgnoreGuiInset): add the inset for guis that keep it.
local function rectOf(g: GuiObject): (Vector2, Vector2)
	local pos, size = g.AbsolutePosition, g.AbsoluteSize
	local layer = g:FindFirstAncestorWhichIsA("ScreenGui")
	if layer and not layer.IgnoreGuiInset then
		pos += GuiService:GetGuiInset()
	end
	return pos, size
end
SelectionRing.rectOf = rectOf

local function build()
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	-- Roblox's own selection image never shows.
	local blank = Instance.new("Frame")
	blank.Name = "GHSNoSelectionImage"
	blank.BackgroundTransparency = 1
	blank.Size = UDim2.fromScale(1, 1)
	pg.SelectionImageObject = blank
	local g = UI.new("ScreenGui", {
		Name = "SelectionRing",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 60,
		Parent = pg,
	}) :: ScreenGui
	local r = UI.frame({
		Name = "Ring",
		BackgroundTransparency = 1,
		Visible = false,
		Parent = g,
	})
	local color = Color3.fromHex(cfg("SelectionRingColor", "E8B64C"))
	UI.corner(r, UI.S(Theme.Corner))
	UI.new("UIStroke", {
		Name = "Edge",
		Color = color,
		Thickness = UI.S(cfg("SelectionRingStroke", 3)),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = r,
	})
	-- the glow: a wider, faint ring just outside
	local glowPad = UI.S(cfg("SelectionRingGlow", 5))
	local glow = UI.frame({
		Name = "Glow",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, glowPad * 2, 1, glowPad * 2),
		Parent = r,
	})
	UI.corner(glow, UI.S(Theme.Corner) + glowPad)
	UI.new("UIStroke", {
		Color = color,
		Thickness = glowPad,
		Transparency = 0.75,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = glow,
	})
	UI.new("UIScale", { Name = "Pulse", Parent = r })
	gui = g
	ring = r
end

-- Ring `g` (nil hides). Call every frame: it follows the target as it moves and slides on a change.
function SelectionRing.set(g: GuiObject?)
	if not ring then
		build()
	end
	local r = ring :: Frame
	if g ~= target then
		if g and target and shown then
			fromPos, fromSize = r.AbsolutePosition, r.AbsoluteSize
			animAt = os.clock()
		else
			animAt = -math.huge
		end
		target = g
		if g then
			local pulse = r:FindFirstChild("Pulse") :: UIScale?
			if pulse then
				pulse.Scale = 1.08
				UI.tween(pulse, { Scale = 1 }, 0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			end
		end
	end
	if not g or not g.Parent then
		r.Visible = false
		shown = false
		return
	end
	local pad = UI.S(cfg("SelectionRingPad", 4))
	local pos, size = rectOf(g)
	pos -= Vector2.new(pad, pad)
	size += Vector2.new(pad * 2, pad * 2)
	local slide = cfg("SelectionRingSlideSec", 0.12)
	local t = math.clamp((os.clock() - animAt) / math.max(slide, 1e-3), 0, 1)
	if t < 1 then
		local e = 1 - (1 - t) ^ 3
		pos = fromPos:Lerp(pos, e)
		size = fromSize:Lerp(size, e)
	end
	r.Position = UDim2.fromOffset(pos.X, pos.Y)
	r.Size = UDim2.fromOffset(size.X, size.Y)
	r.Visible = true
	shown = true
end

function SelectionRing.target(): GuiObject?
	return target
end

function SelectionRing.gui(): ScreenGui?
	return gui
end

return SelectionRing
