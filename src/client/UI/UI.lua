--!strict
-- Instance.new helpers so every HUD piece is a few lines. All sizes go through UI.S for viewport scaling.
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local UI = {}
UI.scale = 1

function UI.S(n: number): number
	return math.round(n * UI.scale)
end

function UI.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className) :: any
	if props then
		for k, v in props do
			if k ~= "Parent" then
				inst[k] = v
			end
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function merge(defaults: { [string]: any }, props: { [string]: any }?): { [string]: any }
	local out = table.clone(defaults)
	if props then
		for k, v in props do
			out[k] = v
		end
	end
	return out
end

function UI.frame(props: { [string]: any }?, children: { Instance }?): Frame
	return UI.new("Frame", merge({ BackgroundColor3 = Theme.Colors.panel, BorderSizePixel = 0 }, props), children)
end

function UI.text(props: { [string]: any }?): TextLabel
	return UI.new(
		"TextLabel",
		merge({
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Font = Theme.Fonts.body,
			TextColor3 = Theme.Colors.text,
			TextSize = UI.S(14),
			Text = "",
		}, props)
	)
end

function UI.button(props: { [string]: any }?): TextButton
	return UI.new(
		"TextButton",
		merge({
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Colors.panel,
			BorderSizePixel = 0,
			Font = Theme.Fonts.body,
			TextColor3 = Theme.Colors.text,
			TextSize = UI.S(14),
			Text = "",
		}, props)
	)
end

function UI.corner(parent: Instance, radius: number): UICorner
	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

-- Border stroke on frames and buttons; text outline on labels.
function UI.stroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	return UI.new("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = if parent:IsA("TextLabel")
			then Enum.ApplyStrokeMode.Contextual
			else Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function UI.pad(parent: Instance, left: number, top: number, right: number, bottom: number): UIPadding
	return UI.new("UIPadding", {
		PaddingLeft = UDim.new(0, left),
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right),
		PaddingBottom = UDim.new(0, bottom),
		Parent = parent,
	})
end

function UI.list(
	parent: Instance,
	direction: Enum.FillDirection,
	padding: number,
	hAlign: Enum.HorizontalAlignment?,
	vAlign: Enum.VerticalAlignment?
): UIListLayout
	return UI.new("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, padding),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function UI.tween(
	inst: Instance,
	props: { [string]: any },
	duration: number,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?,
	delay: number?
): Tween
	local tween = TweenService:Create(
		inst,
		TweenInfo.new(
			duration,
			style or Enum.EasingStyle.Quad,
			direction or Enum.EasingDirection.Out,
			0,
			false,
			delay or 0
		),
		props
	)
	tween:Play()
	return tween
end

-- Scale punch via a UIScale child; safe to call repeatedly.
function UI.punch(inst: GuiObject, to: number, duration: number)
	local scale = inst:FindFirstChild("PunchScale") :: UIScale?
	if not scale then
		scale = UI.new("UIScale", { Name = "PunchScale", Parent = inst })
	end
	local s = scale :: UIScale
	s.Scale = to
	UI.tween(s, { Scale = 1 }, duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

-- Position jitter for `duration` seconds, then back to where it was.
function UI.shake(inst: GuiObject, px: number, duration: number)
	local origin = inst.Position
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < duration and inst.Parent do
			local dx = (math.random() * 2 - 1) * px
			local dy = (math.random() * 2 - 1) * px
			inst.Position = origin + UDim2.fromOffset(dx, dy)
			task.wait()
		end
		if inst.Parent then
			inst.Position = origin
		end
	end)
end

function UI.sound(id: string, pitch: number?, volume: number?)
	if id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.PlaybackSpeed = pitch or 1
	s.Volume = volume or 0.5
	s.Parent = SoundService
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(5, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

-- Shared gun silhouette: body, barrel, grip. Recolored by rarity.
function UI.gunIcon(parent: Instance?, color: Color3, size: number): Frame
	local root = UI.frame({ Name = "GunIcon", BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size) })
	local body = UI.frame({
		BackgroundColor3 = color,
		Position = UDim2.fromScale(0.08, 0.38),
		Size = UDim2.fromScale(0.62, 0.2),
		Parent = root,
	})
	UI.corner(body, math.max(2, size * 0.04))
	local barrel = UI.frame({
		BackgroundColor3 = color,
		Position = UDim2.fromScale(0.62, 0.42),
		Size = UDim2.fromScale(0.34, 0.1),
		Parent = root,
	})
	UI.corner(barrel, math.max(2, size * 0.03))
	local grip = UI.frame({
		BackgroundColor3 = color,
		Position = UDim2.fromScale(0.22, 0.52),
		Size = UDim2.fromScale(0.16, 0.34),
		Rotation = -12,
		Parent = root,
	})
	UI.corner(grip, math.max(2, size * 0.03))
	local mag = UI.frame({
		BackgroundColor3 = color,
		Position = UDim2.fromScale(0.44, 0.56),
		Size = UDim2.fromScale(0.1, 0.22),
		Parent = root,
	})
	UI.corner(mag, 2)
	if parent then
		root.Parent = parent
	end
	return root
end

function UI.recolorIcon(icon: Frame, color: Color3)
	for _, c in icon:GetChildren() do
		if c:IsA("Frame") then
			c.BackgroundColor3 = color
		end
	end
end

-- Small rounded label. Returns the pill and its text label.
function UI.pill(
	parent: Instance?,
	text: string,
	bg: Color3,
	fg: Color3,
	height: number,
	textSize: number?
): (Frame, TextLabel)
	local pill = UI.frame({
		Name = "Pill",
		BackgroundColor3 = bg,
		Size = UDim2.fromOffset(0, height),
		AutomaticSize = Enum.AutomaticSize.X,
	})
	UI.corner(pill, height / 2)
	UI.pad(pill, UI.S(8), 0, UI.S(8), 0)
	local label = UI.text({
		Text = text,
		TextColor3 = fg,
		TextSize = textSize or math.max(9, math.floor(height * 0.6)),
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = pill,
	})
	if parent then
		pill.Parent = parent
	end
	return pill, label
end

function UI.fmtCash(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = ""
	local count = 0
	for i = #s, 1, -1 do
		out = string.sub(s, i, i) .. out
		count += 1
		if count % 3 == 0 and i > 1 then
			out = "," .. out
		end
	end
	return (if n < 0 then "-$" else "$") .. out
end

function UI.fmtNum(n: number): string
	return if n == math.floor(n) then string.format("%d", n) else string.format("%.1f", n)
end

-- Damage per shot: "33", or "33x8" for multi-pellet guns.
function UI.fmtDmg(dmg: number, pellets: number): string
	return if pellets > 1
		then string.format("%dx%d", math.round(dmg), pellets)
		else string.format("%d", math.round(dmg))
end

-- Shots per second: "1.6/s" under ten, "12/s" above.
function UI.fmtRate(rate: number): string
	return if rate >= 10 then string.format("%d/s", math.round(rate)) else string.format("%.1f/s", rate)
end

-- " ▲" / " ▼" / "" comparing a to b, and the matching color.
function UI.arrow(a: number, b: number): (string, Color3)
	if a > b + 0.01 then
		return " ▲", Theme.Colors.cash
	elseif a < b - 0.01 then
		return " ▼", Theme.Colors.malus
	end
	return "", Theme.Colors.text
end

return UI
