--!strict
-- Safe dial (drag). Drag around the dial to turn it under a fixed pointer. The target number is hidden:
-- the pointer goes amber within SafeWarmRange, green within SafeHotRange, the dial shakes harder as it
-- warms and a ring around it fills with closeness (draining when you turn away). Hold in the hot range for
-- SafeLockSec to lock a number. Direction alternates per number.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Frame = require(script.Parent.Frame)

local RING_TICKS = 60

local Safe = {
	title = "SAFE DIAL",
	hint = "DRAG AROUND THE DIAL · TURN RIGHT FIRST",
	color = Theme.Colors.text,
	aspect = 1.05,
}

local function circDist(a: number, b: number): number
	local d = math.abs(a - b) % 100
	return if d > 50 then 100 - d else d
end

function Safe.open(host: Frame.Host)
	local u = host.u
	local numbers = Config.SafeNumbersByTier[host.tier] or Config.SafeNumbersByTier[1]
	local warm = Config.SafeWarmRange
	local hot = Config.SafeHotRange

	local R = math.floor(host.width * 0.28)
	local cx, cy = math.floor(host.width / 2), math.floor(host.height / 2) - u(6)

	-- Closeness ring outside the dial.
	local ringR = R + u(22)
	local ringTicks: { Frame } = {}
	for i = 1, RING_TICKS do
		local a = (i - 1) * 360 / RING_TICKS
		local rad = math.rad(a)
		local t = UI.frame({
			BackgroundColor3 = Theme.Colors.panel2,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx + math.sin(rad) * ringR, cy - math.cos(rad) * ringR),
			Size = UDim2.fromOffset(u(4), u(10)),
			Rotation = a,
			Parent = host.content,
		})
		UI.corner(t, u(2))
		ringTicks[i] = t
	end

	-- The dial: ticks and numbers are its children so they turn with it.
	local dial = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(R * 2, R * 2),
		ZIndex = 3,
		Parent = host.content,
	})
	UI.corner(dial, R)
	UI.stroke(dial, Theme.Colors.grey, u(3))
	for i = 0, 99 do
		local major = i % 10 == 0
		local a = i * 3.6
		local rad = math.rad(a)
		local len = if major then u(14) else u(7)
		UI.frame({
			BackgroundColor3 = if major then Theme.Colors.text else Theme.Colors.grey,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(
				R + math.sin(rad) * (R - len / 2 - u(4)),
				R - math.cos(rad) * (R - len / 2 - u(4))
			),
			Size = UDim2.fromOffset(if major then u(3) else u(2), len),
			Rotation = a,
			ZIndex = 4,
			Parent = dial,
		})
		if major then
			UI.text({
				Text = tostring(i),
				Font = Theme.Fonts.display,
				TextSize = u(14),
				TextColor3 = Theme.Colors.textDim,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(R + math.sin(rad) * (R - u(30)), R - math.cos(rad) * (R - u(30))),
				Size = UDim2.fromOffset(u(30), u(16)),
				Rotation = a,
				ZIndex = 4,
				Parent = dial,
			})
		end
	end

	-- Fixed pointer above the dial, and the readout in the middle.
	local pointer = UI.frame({
		BackgroundColor3 = Theme.Colors.grey,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy - R - u(6)),
		Size = UDim2.fromOffset(u(16), u(16)),
		Rotation = 45,
		ZIndex = 6,
		Parent = host.content,
	})
	UI.corner(pointer, u(3))
	local readout = UI.text({
		Text = "0",
		Font = Theme.Fonts.display,
		TextSize = u(34),
		TextColor3 = Theme.Colors.text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(u(90), u(40)),
		ZIndex = 7,
		Parent = host.content,
	})
	UI.stroke(readout, Theme.Colors.black, u(2), 0.3)
	local dirLabel = UI.text({
		Text = "TURN RIGHT ▶",
		Font = Theme.Fonts.display,
		TextSize = u(13),
		TextColor3 = Theme.Colors.textDim,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy + u(26)),
		Size = UDim2.fromOffset(u(140), u(18)),
		ZIndex = 7,
		Parent = host.content,
	})

	-- Progress pips under the ring.
	local pips: { Frame } = {}
	local pipSize = u(14)
	local pipRow = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(cx, cy + ringR + u(14)),
		Size = UDim2.fromOffset(numbers * (pipSize + u(8)), pipSize),
		Parent = host.content,
	})
	UI.list(pipRow, Enum.FillDirection.Horizontal, u(8), Enum.HorizontalAlignment.Center)
	for p = 1, numbers do
		local pip = UI.frame({
			BackgroundColor3 = Theme.Colors.panel2,
			Size = UDim2.fromOffset(pipSize, pipSize),
			LayoutOrder = p,
			Parent = pipRow,
		})
		UI.corner(pip, pipSize / 2)
		UI.stroke(pip, Theme.Colors.grey, u(1), 0.5)
		pips[p] = pip
	end

	local rot = 0 -- dial rotation in degrees; value under the pointer = rot / 3.6
	local locked = 0
	local direction = 1 -- +1 clockwise (rot increasing), -1 counter-clockwise; alternates per number
	local target = 0
	local hotSince = -1
	local coldSince = -1 -- left the hot range at this clock (the grace before the hold resets)
	local wrongWay = 0 -- degrees turned against the required direction since the last right-way turn
	local lastDist = 100
	local draining = false
	local done = false

	local function value(): number
		return (rot / 3.6) % 100
	end

	local function newTarget()
		local v = value()
		-- At least a fifth of a turn away so there is a sweep, never under the pointer already.
		target = (math.floor(v) + math.random(20, 80)) % 100
		hotSince = -1
		coldSince = -1
		wrongWay = 0
		lastDist = circDist(value(), target)
	end
	newTarget()

	local function paintDirection()
		local right = direction > 0
		dirLabel.Text = if right then "TURN RIGHT ▶" else "◀ TURN LEFT"
		dirLabel.TextColor3 = Theme.Colors.textDim
	end
	paintDirection()

	local inset = GuiService:GetGuiInset()
	local lastAngle = 0
	local function pointerAngle(p: Vector2): number
		-- Input positions sit below the top inset; AbsolutePosition under IgnoreGuiInset does not.
		local center = dial.AbsolutePosition + dial.AbsoluteSize / 2 - inset
		return math.deg(math.atan2(p.Y - center.Y, p.X - center.X))
	end
	local dragArea = UI.button({
		BackgroundTransparency = 1,
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(ringR * 2 + u(20), ringR * 2 + u(20)),
		ZIndex = 8,
		Parent = host.content,
	})
	Frame.drag(host, dragArea, function(p: Vector2)
		lastAngle = pointerAngle(p)
	end, function(p: Vector2)
		if done then
			return
		end
		local a = pointerAngle(p)
		local delta = (a - lastAngle + 540) % 360 - 180
		lastAngle = a
		rot += delta
		dial.Rotation = rot
		-- Backing up near the number (correcting an overshoot) never counts as the wrong way.
		local near = circDist(value(), target) <= warm
		if delta * direction < 0 and not near then
			wrongWay += math.abs(delta)
		else
			wrongWay = math.max(0, wrongWay - math.abs(delta) * 2)
		end
	end, function(_p: Vector2) end)

	local shakePhase = 0
	host.track(RunService.Heartbeat:Connect(function(dt)
		if done then
			return
		end
		local v = value()
		readout.Text = tostring(math.floor(v + 0.5) % 100)
		local dist = circDist(v, target)
		local againstDir = wrongWay > Config.SafeWrongWayDeg
		local closeness = if againstDir then 0 else math.clamp(1 - dist / warm, 0, 1)
		local isHot = not againstDir and dist <= hot
		local isWarm = not againstDir and dist <= warm

		-- Pointer and readout color.
		local color = if isHot then Theme.Colors.cash elseif isWarm then Theme.Colors.amber else Theme.Colors.grey
		pointer.BackgroundColor3 = color
		readout.TextColor3 = if isHot then Theme.Colors.cash elseif isWarm then Theme.Colors.amber else Theme.Colors.text
		dirLabel.TextColor3 = if againstDir then Theme.Colors.red else Theme.Colors.textDim
		if againstDir then
			dirLabel.Text = if direction > 0 then "WRONG WAY · TURN RIGHT ▶" else "◀ WRONG WAY · TURN LEFT"
		else
			paintDirection()
		end

		-- Ring fills with closeness; turning away inside the warm range drains it red.
		if isWarm and dist > lastDist + 0.05 then
			draining = true
		elseif dist < lastDist - 0.05 then
			draining = false
		end
		lastDist = dist
		local lit = math.floor(closeness * RING_TICKS + 0.5)
		for i, t in ringTicks do
			local on = i <= lit
			t.BackgroundColor3 = if not on then Theme.Colors.panel2 elseif draining then Theme.Colors.malus else color
			t.BackgroundTransparency = if on then 0 else 0.4
		end

		-- The dial shakes harder as it warms.
		if isWarm then
			shakePhase += dt * 40
			local amp = u(1 + 5 * closeness)
			dial.Position = UDim2.fromOffset(cx + math.sin(shakePhase) * amp, cy + math.cos(shakePhase * 1.3) * amp)
		else
			dial.Position = UDim2.fromOffset(cx, cy)
		end

		-- Hold in the hot range to lock; a wobble out of it shorter than SafeHotGraceSec keeps the hold going.
		if isHot then
			coldSince = -1
			if hotSince < 0 then
				hotSince = os.clock()
			elseif os.clock() - hotSince >= Config.SafeLockSec then
				locked += 1
				pips[locked].BackgroundColor3 = Theme.Colors.cash
				UI.punch(pips[locked], 1.5, 0.3)
				host.stamp("CLICK", Theme.Colors.cash)
				UI.punch(dial, 1.08, 0.25)
				host.haptic(1)
				UI.sound(Theme.Sounds.take, 0.8 + locked * 0.15, 0.6)
				if locked >= numbers then
					done = true
					task.delay(0.35, function()
						host.finish("done")
					end)
					return
				end
				direction = -direction
				newTarget()
				draining = false
				host.setHint(
					string.format("%d / %d · NOW TURN %s", locked, numbers, if direction > 0 then "RIGHT" else "LEFT"),
					Theme.Colors.cash
				)
				paintDirection()
			end
		elseif hotSince >= 0 then
			if coldSince < 0 then
				coldSince = os.clock()
			elseif os.clock() - coldSince > Config.SafeHotGraceSec then
				hotSince = -1
				coldSince = -1
			end
		end
	end))
end

return Safe
