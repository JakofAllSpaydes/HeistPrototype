--!strict
-- Brief 11: ProximityPrompts on a pad. Roblox's default prompt draws its own (Xbox) button art; on a pad every prompt
-- switches to Custom style on this client only and this module draws it: the glyph chip for the prompt's pad button
-- (□ by default, InputGlyphs), the object line, the action in big caps, and the hold bar. On keyboard and touch the
-- prompts go back to Roblox's Default style, untouched. Input is still Roblox's: the style is only the look.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local InputGlyphs = require(script.Parent:WaitForChild("InputGlyphs"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local PadPrompt = {}

local original: { [ProximityPrompt]: Enum.ProximityPromptStyle } = {}
local drawn: { [ProximityPrompt]: BillboardGui } = {}
local onPad = false

local function folder(): Instance
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local f = pg:FindFirstChild("PadPrompts")
	if not f then
		local fo = Instance.new("Folder")
		fo.Name = "PadPrompts"
		fo.Parent = pg
		f = fo
	end
	return f :: Instance
end

local function undraw(prompt: ProximityPrompt)
	local g = drawn[prompt]
	if g then
		g:Destroy()
		drawn[prompt] = nil
	end
end

local function draw(prompt: ProximityPrompt)
	undraw(prompt)
	local adornee = prompt.Parent
	if not adornee or not (adornee:IsA("BasePart") or adornee:IsA("Attachment") or adornee:IsA("Model")) then
		return
	end
	local S = UI.S
	local h = S(46)
	local g = Instance.new("BillboardGui")
	g.Name = "PadPrompt"
	g.AlwaysOnTop = true
	g.LightInfluence = 0
	g.Size = UDim2.fromOffset(S(300), h + S(14))
	g.Adornee = adornee :: any
	g.ResetOnSpawn = false
	local box = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.25,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, h),
		Parent = g,
	})
	UI.corner(box, S(4))
	UI.pad(box, S(6), S(4), S(12), S(4))
	UI.list(box, Enum.FillDirection.Horizontal, S(10), nil, Enum.VerticalAlignment.Center)
	InputGlyphs.chip("interact", h - S(10), { LayoutOrder = 1, Parent = box }, { button = prompt.GamepadKeyCode.Name })
	local col = UI.frame({
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, h - S(8)),
		LayoutOrder = 2,
		Parent = box,
	})
	UI.list(col, Enum.FillDirection.Vertical, 0, nil, Enum.VerticalAlignment.Center)
	if prompt.ObjectText ~= "" then
		UI.text({
			Text = string.upper(prompt.ObjectText),
			TextSize = S(12),
			TextColor3 = Theme.Colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, S(14)),
			LayoutOrder = 1,
			Parent = col,
		})
	end
	UI.text({
		Text = string.upper(prompt.ActionText),
		FontFace = Theme.Fonts.display,
		TextSize = S(22),
		TextColor3 = Theme.Colors.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, S(24)),
		LayoutOrder = 2,
		Parent = col,
	})
	-- The hold bar under the box (only for hold prompts).
	local bar = UI.frame({
		Name = "Hold",
		BackgroundColor3 = Theme.Colors.panel2,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(0, S(160), 0, S(6)),
		Visible = prompt.HoldDuration > 0,
		Parent = g,
	})
	local fill = UI.frame({
		Name = "Fill",
		BackgroundColor3 = Theme.Colors.gold,
		Size = UDim2.fromScale(0, 1),
		Parent = bar,
	})
	local _ = fill
	g.Parent = folder()
	drawn[prompt] = g
end

local function holdBegan(prompt: ProximityPrompt)
	local g = drawn[prompt]
	local fill = g and g:FindFirstChild("Fill", true) :: Frame?
	if fill then
		fill.Size = UDim2.fromScale(0, 1)
		UI.tween(fill, { Size = UDim2.fromScale(1, 1) }, math.max(prompt.HoldDuration, 0.01), Enum.EasingStyle.Linear)
	end
end

local function holdEnded(prompt: ProximityPrompt)
	local g = drawn[prompt]
	local fill = g and g:FindFirstChild("Fill", true) :: Frame?
	if fill then
		UI.tween(fill, { Size = UDim2.fromScale(0, 1) }, 0.15)
	end
end

local function styleOne(prompt: ProximityPrompt)
	if onPad then
		if original[prompt] == nil then
			original[prompt] = prompt.Style
		end
		prompt.Style = Enum.ProximityPromptStyle.Custom
	else
		local was = original[prompt]
		if was ~= nil then
			prompt.Style = was
			original[prompt] = nil
		end
		undraw(prompt)
	end
end

local function restyleAll()
	for _, d in Workspace:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			styleOne(d)
		end
	end
end

function PadPrompt.init()
	onPad = ClientState.inputDevice == "gamepad"
	if onPad then
		restyleAll()
	end
	ClientState.DeviceChanged:Connect(function(d: string)
		local want = d == "gamepad"
		if want ~= onPad then
			onPad = want
			restyleAll()
		end
	end)
	Workspace.DescendantAdded:Connect(function(d: Instance)
		if onPad and d:IsA("ProximityPrompt") then
			styleOne(d)
		end
	end)
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		if onPad and prompt.Style == Enum.ProximityPromptStyle.Custom then
			draw(prompt)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(undraw)
	ProximityPromptService.PromptButtonHoldBegan:Connect(holdBegan)
	ProximityPromptService.PromptButtonHoldEnded:Connect(holdEnded)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local g = drawn[prompt]
		local box = g and g:FindFirstChildWhichIsA("Frame")
		if box then
			UI.punch(box, 1.1, 0.15)
		end
	end)
end

return PadPrompt
