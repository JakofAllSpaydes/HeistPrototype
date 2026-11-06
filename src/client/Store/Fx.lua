--!strict
-- Brief 6 style bar, shared by every premium surface (store, sheets, crate scene, pass, job board): rarity glow,
-- rays, UI particles, hover / press / disabled states, count-ups, entrance motion, the store's sound set and
-- haptics. Every function takes plain GuiObjects so any screen can opt in.
local HapticService = game:GetService("HapticService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Rarity = require(Shared:WaitForChild("Rarity"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))

local Fx = {}

-- The store's sound set (Roblox default library; swap ids here).
Fx.Sounds = {
	tab = "rbxasset://sounds/switch3.wav",
	hover = "rbxasset://sounds/clickfast.wav",
	press = "rbxasset://sounds/button.wav",
	chime = "rbxasset://sounds/victory.wav",
	tick = "rbxasset://sounds/electronicpingshort.wav",
	whoosh = "rbxasset://sounds/swoosh.wav",
	thump = "rbxasset://sounds/bass.wav",
	lid = "rbxasset://sounds/collide.wav",
	deny = "rbxasset://sounds/flashbulb.wav",
	rattle = "rbxasset://sounds/switch3.wav",
	stamp = "rbxasset://sounds/snap.mp3",
	tear = "rbxasset://sounds/swoosh.wav",
}

-- Stinger per rarity tier: pitch rises with the tier, Legendary gets the victory sting on top.
function Fx.stinger(tier: number)
	local t = math.clamp(tier, 1, 5)
	UI.sound(Fx.Sounds.thump, 0.7 + t * 0.12, 0.35 + t * 0.08)
	UI.sound(Fx.Sounds.press, 0.8 + t * 0.18, 0.3 + t * 0.05)
	if t >= 4 then
		UI.sound(Fx.Sounds.chime, if t == 5 then 1.0 else 1.25, if t == 5 then 0.7 else 0.4)
	end
end

function Fx.haptic(strength: number?)
	if not UserInputService.TouchEnabled then
		return
	end
	local s = strength or 0.5
	pcall(function()
		HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, s)
	end)
	task.delay(0.12, function()
		pcall(function()
			HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0)
		end)
	end)
end

function Fx.rarityColor(tier: number): Color3
	return Rarity.color(math.clamp(tier, 1, 5))
end

-- A lighter / darker version of a color (k > 0 lighter).
function Fx.shade(c: Color3, k: number): Color3
	if k >= 0 then
		return c:Lerp(Color3.new(1, 1, 1), k)
	end
	return c:Lerp(Color3.new(0, 0, 0), -k)
end

------------------------------------------------------------------ Glow
-- Soft glow behind a frame: stacked rounded layers that fade outward. Returns the holder (put it behind the body
-- with a lower ZIndex) and a setter for the intensity (1 = resting, >1 brighter).
function Fx.glow(parent: GuiObject, color: Color3, radius: number, z: number?): (Frame, (number) -> ())
	local S = UI.S
	local holder = UI.frame({
		Name = "Glow",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z or 0,
		Parent = parent,
	})
	local layers: { Frame } = {}
	local base = { 0.55, 0.75, 0.88 }
	for i, spread in { S(4), S(10), S(18) } do
		local f = UI.frame({
			BackgroundColor3 = color,
			BackgroundTransparency = base[i],
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, spread * 2, 1, spread * 2),
			ZIndex = z or 0,
			Parent = holder,
		})
		UI.corner(f, radius + spread)
		layers[i] = f
	end
	local function set(k: number)
		for i, f in layers do
			local t = 1 - (1 - base[i]) * math.clamp(k, 0, 2)
			UI.tween(f, { BackgroundTransparency = math.clamp(t, 0, 1) }, 0.15)
		end
	end
	return holder, set
end

-- Breathing glow (hero items, claimable cells): the setter oscillates around `k`.
function Fx.pulse(set: (number) -> (), alive: () -> boolean, period: number?, lo: number?, hi: number?)
	task.spawn(function()
		local t0 = os.clock()
		while alive() do
			local s = (math.sin((os.clock() - t0) / (period or 1.6) * math.pi * 2) + 1) / 2
			set((lo or 0.8) + ((hi or 1.4) - (lo or 0.8)) * s)
			task.wait(0.15)
		end
	end)
end

------------------------------------------------------------------ Rays and particles
-- Slowly turning rays behind a reveal (Legendary in the brief; any tier can ask). Returns the holder.
function Fx.rays(parent: GuiObject, color: Color3, count: number, size: number, z: number?, speed: number?): Frame
	local holder = UI.frame({
		Name = "Rays",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		ZIndex = z or 0,
		Parent = parent,
	})
	for i = 1, count do
		local ray = UI.frame({
			BackgroundColor3 = color,
			BackgroundTransparency = 0.55,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, math.max(3, math.floor(size * 0.05)), 1, 0),
			Rotation = (i - 1) * (180 / count),
			ZIndex = z or 0,
			Parent = holder,
		})
		UI.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.15),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Rotation = 90,
			Parent = ray,
		})
	end
	local spin = speed or 12
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		if not holder.Parent then
			conn:Disconnect()
			return
		end
		holder.Rotation = (holder.Rotation + dt * spin) % 360
	end)
	return holder
end

-- Sparks drifting up out of a frame (Epic+). Runs until the frame goes; `rate` sparks a second.
function Fx.particles(parent: GuiObject, color: Color3, rate: number, z: number?)
	local S = UI.S
	task.spawn(function()
		while parent.Parent do
			if parent.Visible and parent.AbsoluteSize.X > 0 then
				local size = S(math.random(3, 6))
				local p = UI.frame({
					BackgroundColor3 = Fx.shade(color, math.random() * 0.4),
					BackgroundTransparency = 0.1,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(math.random() * 0.9 + 0.05, 0, 0.85 + math.random() * 0.1, 0),
					Size = UDim2.fromOffset(size, size),
					Rotation = math.random(0, 90),
					ZIndex = z or 5,
					Parent = parent,
				})
				UI.corner(p, size // 2)
				local dur = 0.9 + math.random() * 0.8
				UI.tween(p, {
					Position = p.Position - UDim2.new(0, 0, 0.45 + math.random() * 0.3, 0),
					BackgroundTransparency = 1,
					Rotation = p.Rotation + 120,
				}, dur, Enum.EasingStyle.Sine)
				task.delay(dur, function()
					p:Destroy()
				end)
			end
			task.wait(1 / math.max(rate, 0.5))
		end
	end)
end

-- One burst of sparks from a point (purchase, claim, Gold landing).
function Fx.burst(parent: GuiObject, at: UDim2, color: Color3, count: number, z: number?)
	local S = UI.S
	for _ = 1, count do
		local size = S(math.random(4, 8))
		local p = UI.frame({
			BackgroundColor3 = Fx.shade(color, math.random() * 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = at,
			Size = UDim2.fromOffset(size, size),
			Rotation = math.random(0, 90),
			ZIndex = z or 20,
			Parent = parent,
		})
		UI.corner(p, size // 3)
		local a = math.random() * math.pi * 2
		local d = S(math.random(40, 110))
		UI.tween(p, {
			Position = at + UDim2.fromOffset(math.cos(a) * d, math.sin(a) * d),
			BackgroundTransparency = 1,
			Rotation = p.Rotation + 180,
		}, 0.55 + math.random() * 0.3, Enum.EasingStyle.Quad)
		task.delay(0.9, function()
			p:Destroy()
		end)
	end
end

------------------------------------------------------------------ Motion
-- The panel slides in from `dir` (UDim2 offset) and settles with an overshoot.
function Fx.slideIn(obj: GuiObject, from: UDim2, sec: number?)
	local to = obj.Position
	obj.Position = to + from
	UI.tween(obj, { Position = to }, sec or 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

-- Cards cascade in: each starts lower and see-through, then rises in, `stagger` apart.
function Fx.cascade(items: { GuiObject }, stagger: number?, rise: number?)
	local S = UI.S
	for i, item in items do
		local scale = item:FindFirstChild("CascadeScale") :: UIScale?
		if not scale then
			scale = UI.new("UIScale", { Name = "CascadeScale", Parent = item })
		end
		local sc = scale :: UIScale
		sc.Scale = 0.85
		local group = item:FindFirstChildOfClass("CanvasGroup")
		local to = item.Position
		item.Position = to + UDim2.fromOffset(0, S(rise or 26))
		item.Visible = false
		task.delay((i - 1) * (stagger or 0.04), function()
			if not item.Parent then
				return
			end
			item.Visible = true
			UI.tween(item, { Position = to }, 0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			UI.tween(sc, { Scale = 1 }, 0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			if group then
				group.GroupTransparency = 1
				UI.tween(group, { GroupTransparency = 0 }, 0.2)
			end
		end)
	end
end

-- Crossfade: the old content fades out while the new one fades in (tab switches never pop). Works on
-- CanvasGroups.
function Fx.crossfade(old: CanvasGroup?, new: CanvasGroup, sec: number?)
	local d = sec or 0.18
	if old then
		UI.tween(old, { GroupTransparency = 1 }, d)
		task.delay(d, function()
			old:Destroy()
		end)
	end
	new.GroupTransparency = 1
	UI.tween(new, { GroupTransparency = 0 }, d)
end

-- A gentle bob (and optional sway) for hero art. Stops when the object goes.
function Fx.bob(obj: GuiObject, px: number, period: number?, sway: number?)
	local base = obj.Position
	local t0 = os.clock() + math.random() * 3
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		if not obj.Parent then
			conn:Disconnect()
			return
		end
		local t = (os.clock() - t0) / (period or 2.4) * math.pi * 2
		obj.Position = base + UDim2.fromOffset(0, math.sin(t) * px)
		if sway then
			obj.Rotation = math.sin(t * 0.5) * sway
		end
	end)
end

-- Numbers count up, never jump. `fmt` formats the value (defaults to the comma-grouped integer).
function Fx.countUp(
	label: TextLabel,
	from: number,
	to: number,
	sec: number,
	fmt: ((number) -> string)?,
	sound: boolean?
)
	local f = fmt or function(n: number): string
		return UI.fmtInt(n)
	end
	if from == to or sec <= 0 then
		label.Text = f(to)
		return
	end
	local token = (label:GetAttribute("CountToken") or 0) + 1
	label:SetAttribute("CountToken", token)
	task.spawn(function()
		local t0 = os.clock()
		local lastTick = 0
		while os.clock() - t0 < sec do
			if label:GetAttribute("CountToken") ~= token then
				return
			end
			local k = (os.clock() - t0) / sec
			local e = 1 - (1 - k) ^ 3
			label.Text = f(math.floor(from + (to - from) * e))
			if sound and os.clock() - lastTick > 0.06 then
				lastTick = os.clock()
				UI.sound(Fx.Sounds.tick, 1.2 + e * 0.8, 0.12)
			end
			task.wait()
		end
		if label:GetAttribute("CountToken") == token then
			label.Text = f(to)
		end
	end)
end

------------------------------------------------------------------ Buttons and cards
export type Interactive = {
	setEnabled: (boolean) -> (),
	setGlow: ((number) -> ())?,
}

-- Hover lifts 4px and brightens the glow, press scales 0.96 and pulses, disabled dims to 40%. `lift` is the frame
-- that moves (defaults to the button itself); SFX on hover and press; haptic on press (mobile).
function Fx.interactive(
	btn: GuiButton,
	opts: { lift: GuiObject?, glow: ((number) -> ())?, silent: boolean? }?
): Interactive
	local S = UI.S
	local o = opts or {}
	local lift = o.lift or btn
	local base = lift.Position
	local scale = lift:FindFirstChild("PressScale") :: UIScale?
	if not scale then
		scale = UI.new("UIScale", { Name = "PressScale", Parent = lift })
	end
	local sc = scale :: UIScale
	local enabled = true
	local hovering = false
	btn.MouseEnter:Connect(function()
		if not enabled or UserInputService.TouchEnabled then
			return
		end
		hovering = true
		UI.tween(lift, { Position = base - UDim2.fromOffset(0, S(4)) }, 0.12)
		if o.glow then
			o.glow(1.6)
		end
		if not o.silent then
			UI.sound(Fx.Sounds.hover, 1.6, 0.12)
		end
	end)
	btn.MouseLeave:Connect(function()
		hovering = false
		UI.tween(lift, { Position = base }, 0.12)
		if o.glow then
			o.glow(1)
		end
	end)
	btn.MouseButton1Down:Connect(function()
		if not enabled then
			return
		end
		UI.tween(sc, { Scale = 0.96 }, 0.06)
	end)
	btn.MouseButton1Up:Connect(function()
		UI.tween(sc, { Scale = 1 }, 0.18, Enum.EasingStyle.Back)
	end)
	btn.Activated:Connect(function()
		if not enabled then
			UI.sound(Fx.Sounds.deny, 1, 0.25)
			UI.shake(lift, S(3), 0.15)
			return
		end
		sc.Scale = 0.96
		UI.tween(sc, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
		if o.glow then
			o.glow(2)
			task.delay(0.15, function()
				if o.glow then
					o.glow(if hovering then 1.6 else 1)
				end
			end)
		end
		if not o.silent then
			UI.sound(Fx.Sounds.press, 1.15, 0.3)
		end
		Fx.haptic(0.3)
	end)
	local function setEnabled(on: boolean)
		enabled = on
		-- Disabled dims to 40%: a dark veil over the lift frame.
		local veil = lift:FindFirstChild("DisabledVeil") :: Frame?
		if not on and not veil then
			veil = UI.frame({
				Name = "DisabledVeil",
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.4,
				Size = UDim2.fromScale(1, 1),
				ZIndex = (lift.ZIndex or 1) + 40,
				Parent = lift,
			})
			local corner = lift:FindFirstChildOfClass("UICorner")
			if corner and veil then
				UI.corner(veil, corner.CornerRadius.Offset)
			end
		elseif on and veil then
			veil:Destroy()
		end
	end
	return { setEnabled = setEnabled, setGlow = o.glow }
end

-- A flat store button (display font, color fill, light edge). Returns the button and its interactive handle.
function Fx.button(
	parent: Instance,
	text: string,
	bg: Color3,
	fg: Color3,
	size: UDim2,
	z: number?
): (TextButton, Interactive)
	local S = UI.S
	local b = UI.button({
		Text = text,
		Font = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = fg,
		BackgroundColor3 = bg,
		Size = size,
		ZIndex = z or 5,
		Parent = parent,
	})
	UI.corner(b, S(8))
	UI.stroke(b, Fx.shade(bg, 0.35), S(1), 0.2)
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)),
		Rotation = 90,
		Parent = b,
	})
	return b, Fx.interactive(b)
end

-- The R$ badge: the Robux mark stands in as a small rounded hex-like plate with "R$".
function Fx.robux(parent: Instance, height: number, z: number?): Frame
	local plate = UI.frame({
		Name = "Robux",
		BackgroundColor3 = Color3.fromHex("2FD46A"),
		Size = UDim2.fromOffset(math.floor(height * 1.35), height),
		ZIndex = z or 5,
		Parent = parent,
	})
	UI.corner(plate, math.floor(height * 0.3))
	UI.text({
		Text = "R$",
		Font = Theme.Fonts.display,
		TextSize = math.floor(height * 0.72),
		TextColor3 = Color3.fromHex("0E2A17"),
		Size = UDim2.fromScale(1, 1),
		ZIndex = (z or 5) + 1,
		Parent = plate,
	})
	return plate
end

function Fx.fmtRobux(n: number): string
	return "R$ " .. UI.fmtInt(n)
end

return Fx
