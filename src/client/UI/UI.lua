--!strict
-- Instance.new helpers so every HUD piece is a few lines. All sizes go through UI.S for viewport scaling.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Theme = require(script.Parent.Theme)

local UI = {}
UI.scale = 1

function UI.S(n: number): number
	return math.round(n * UI.scale)
end

-- Round 24: mobile HUD groups grow by Config.MobileButtonScale around their anchor point. Goes on a container,
-- never on a button that UI.punch scales (one UIScale per object).
function UI.mobileGrow(inst: GuiObject, mobile: boolean)
	local k = Config.MobileButtonScale or 1
	if mobile and k ~= 1 then
		UI.new("UIScale", { Name = "MobileGrow", Scale = k, Parent = inst })
	end
end

-- Upper-cases text outside rich-text tags (<font ...>) and entities (&lt;), which must keep their case.
local function upperText(s: string): string
	local out = {}
	local i = 1
	while i <= #s do
		local a = string.find(s, "[<&]", i)
		if not a then
			table.insert(out, string.upper(string.sub(s, i)))
			break
		end
		table.insert(out, string.upper(string.sub(s, i, a - 1)))
		local close = if string.sub(s, a, a) == "<" then string.find(s, ">", a, true) else string.find(s, ";", a, true)
		if not close or (string.sub(s, a, a) == "&" and close - a > 8) then
			table.insert(out, string.sub(s, a, a))
			i = a + 1
		else
			table.insert(out, string.sub(s, a, close))
			i = close + 1
		end
	end
	return table.concat(out)
end

-- Round 19o: the house fonts draw smaller than the old ones at the same TextSize (Oswald is narrow, Builder Sans
-- has a smaller x-height), so every label's TextSize is the size the code asked for x Theme.TextScale[font]. The
-- base (what the code wrote) is remembered per label; our own write is told apart from an outside one (a later
-- `.TextSize =`, a tween step) by the value we last set. Opt out with the FixedTextSize attribute.
local textBase: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any
local textSet: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any

local function textFactor(font: Font): number
	local f = Theme.Fonts
	local k = Theme.TextScale
	if font.Family == f.display.Family then
		return k.display
	elseif font.Family == f.body.Family then
		return k.body
	elseif font.Family == f.mono.Family then
		return k.mono
	end
	return 1
end

-- Display-font text is always caps (LuckiestGuy, the old display face, had no lower case, so mixed-case strings
-- always rendered as caps; Oswald has both), and every label gets the font's size factor.
function UI.caps(label: TextLabel | TextButton)
	local family = Theme.Fonts.display.Family
	local function caps()
		if label.FontFace.Family == family then
			local up = upperText(label.Text)
			if up ~= label.Text then
				label.Text = up
			end
		end
	end
	local function size()
		if label:GetAttribute("FixedTextSize") then
			return
		end
		local current = label.TextSize
		if textSet[label] ~= current then
			textBase[label] = current
		end
		local base = textBase[label] or current
		local want = math.clamp(math.round(base * textFactor(label.FontFace)), 1, 100)
		textSet[label] = want
		if current ~= want then
			label.TextSize = want
		end
	end
	label:GetPropertyChangedSignal("Text"):Connect(caps)
	label:GetPropertyChangedSignal("FontFace"):Connect(function()
		caps()
		size()
	end)
	label:GetPropertyChangedSignal("TextSize"):Connect(size)
	caps()
	-- Deferred, so a FixedTextSize set right after creation (or a FontFace swap) is seen first.
	task.defer(size)
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
	if className == "TextLabel" or className == "TextButton" then
		UI.caps(inst)
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
			FontFace = Theme.Fonts.body,
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
			FontFace = Theme.Fonts.body,
			TextColor3 = Theme.Colors.text,
			TextSize = UI.S(14),
			Text = "",
		}, props)
	)
end

-- Round 19o: every radius caps at Theme.Corner (sharp panels, cards, tags), except a full round on an
-- offset-sized square (dots, dials, rings, knobs), which stays a circle.
function UI.corner(parent: Instance, radius: number): UICorner
	local r = radius
	local cap = UI.S(Theme.Corner)
	if r > cap then
		local round = false
		if parent:IsA("GuiObject") then
			local size = parent.Size
			local w, h = size.X.Offset, size.Y.Offset
			round = size.X.Scale == 0
				and size.Y.Scale == 0
				and w > 0
				and math.abs(w - h) <= 2
				and r >= math.min(w, h) / 2 - 1
		end
		if not round then
			r = cap
		end
	end
	return UI.new("UICorner", { CornerRadius = UDim.new(0, r), Parent = parent })
end

-- Border stroke on frames and buttons; text outline on labels (capped at Theme.TextStrokeMax).
function UI.stroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	local isText = parent:IsA("TextLabel") or parent:IsA("TextButton") or parent:IsA("TextBox")
	return UI.new("UIStroke", {
		Color = color,
		Thickness = if isText then math.min(thickness, math.max(1, UI.S(Theme.TextStrokeMax))) else thickness,
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

------------------------------------------------------------------ Sound (Round 19d polish pass)
-- Every sound plays through a SoundGroup (SFX / Music, volumes from Config) so the mix has two faders and the
-- music can duck. Per Theme.Sounds key: a gain to level the assets (Config.SfxGain), a little pitch variation so
-- repeats do not machine-gun (Config.SfxPitchJitter), and at most Config.SfxMaxVoices copies of one sound at once
-- (the oldest stops: full-auto fire stays readable).
local groups: { [string]: SoundGroup } = {}
function UI.soundGroup(name: string): SoundGroup
	local g = groups[name]
	if g and g.Parent then
		return g
	end
	local found = SoundService:FindFirstChild(name)
	local made: SoundGroup = if found and found:IsA("SoundGroup") then found else Instance.new("SoundGroup")
	made.Name = name
	made.Volume = if name == "Music" then Config.MusicVolume else Config.SfxVolume
	made.Parent = SoundService
	groups[name] = made
	return made
end

local keyById: { [string]: string }? = nil
local function keyOf(id: string): string?
	if not keyById then
		local map = {}
		for key, sid in Theme.Sounds do
			if map[sid] == nil then
				map[sid] = key
			end
		end
		keyById = map
	end
	return (keyById :: { [string]: string })[id]
end

local voices: { [string]: { Sound } } = {}

-- A Sound for `id` with the gain, jitter and voice cap applied, parented and playing. Gone when it ends.
local function play(parent: Instance, id: string, pitch: number?, volume: number?): Sound
	local key = keyOf(id)
	local gain = if key then (Config.SfxGain :: any)[key] or 1 else 1
	local jitter = if key then (Config.SfxPitchJitter :: any)[key] or 0 else 0
	local s = Instance.new("Sound")
	s.SoundId = id
	s.PlaybackSpeed = (pitch or 1) * (1 + (math.random() * 2 - 1) * jitter)
	s.Volume = (volume or 0.5) * gain
	s.SoundGroup = UI.soundGroup("SFX")
	s.Parent = parent
	local list = voices[id]
	if not list then
		list = {}
		voices[id] = list
	end
	local live = list :: { Sound }
	table.insert(live, s)
	while #live > Config.SfxMaxVoices do
		local old = table.remove(live, 1)
		if old and old.Parent then
			old:Destroy()
		end
	end
	local function gone()
		local i = table.find(live, s)
		if i then
			table.remove(live, i)
		end
		if s.Parent then
			s:Destroy()
		end
	end
	s.Ended:Once(gone)
	task.delay(10, gone)
	s:Play()
	return s
end

function UI.sound(id: string, pitch: number?, volume: number?)
	if id == "" then
		return
	end
	play(SoundService, id, pitch, volume)
end

-- A sound in the world: falls off over `range` studs and pans. `parent` is a part or attachment.
function UI.soundAt(parent: Instance, id: string, pitch: number, volume: number, range: number)
	if id == "" then
		return
	end
	local s = play(parent, id, pitch, volume)
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 8
	s.RollOffMaxDistance = range
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

-- Brief 6: the VIP gold tag before a name (labels that show it set RichText = true).
UI.VipTag = '<font color="#F2C14E">VIP</font> '

function UI.vipName(name: string, vip: any): string
	return if vip == true then UI.VipTag .. name else name
end

-- Comma-grouped integer: 3110 -> "3,110".
function UI.fmtInt(n: number): string
	return string.sub(UI.fmtCash(math.floor(math.abs(n))), 2)
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
