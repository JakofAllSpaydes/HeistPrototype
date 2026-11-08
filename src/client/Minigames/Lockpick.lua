--!strict
-- Lockpick (tap). A pin sweeps a ring; tap while it is in the green zone (+1) or the pink sliver (+2).
-- Each hit shrinks the zone and speeds the pin up. Tier sets the starting zone width.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Frame = require(script.Parent.Frame)

local TICKS = 72
local PINK = Color3.fromHex("FF7AB8")

local Lockpick = {
	title = "LOCKPICK",
	hint = "TAP WHEN THE PIN IS IN THE GREEN · PINK IS WORTH 2",
	color = Theme.Colors.gold,
	aspect = 1.0,
}

local function angDist(a: number, b: number): number
	local d = (a - b) % 360
	return if d > 180 then 360 - d else d
end

function Lockpick.open(host: Frame.Host)
	local u = host.u
	local zoneStart = Config.LockpickZoneByTier[host.tier] or Config.LockpickZoneByTier[1]
	local zone = zoneStart
	local sliver = Config.LockpickSliverDeg
	local speed = Config.LockpickPinSpeed
	local target = Config.LockpickTargetByTier[host.tier] or Config.LockpickTargetByTier[1]
	local zoneCenter = math.random() * 360
	local angle = (zoneCenter + 180) % 360
	local score = 0
	local stunUntil = 0

	local R = math.floor(host.width * 0.3)
	local cx, cy = math.floor(host.width / 2), math.floor(host.height / 2) - u(14)
	local ring = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(R * 2, R * 2),
		Parent = host.content,
	})
	UI.corner(ring, R)
	local ringStroke = UI.stroke(ring, Theme.Colors.grey, u(3))

	-- The zone is drawn as ticks around the ring: green inside the zone, pink in the sliver, dark elsewhere.
	local ticks: { { frame: Frame, angle: number } } = {}
	for i = 1, TICKS do
		local a = (i - 1) * 360 / TICKS
		local rad = math.rad(a)
		local t = UI.frame({
			BackgroundColor3 = Theme.Colors.panel2,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx + math.sin(rad) * R, cy - math.cos(rad) * R),
			Size = UDim2.fromOffset(u(6), u(16)),
			Rotation = a,
			ZIndex = 2,
			Parent = host.content,
		})
		UI.corner(t, u(2))
		ticks[i] = { frame = t, angle = a }
	end
	local function paintZone()
		for _, t in ticks do
			local d = angDist(t.angle, zoneCenter)
			t.frame.BackgroundColor3 = if d <= sliver / 2
				then PINK
				elseif d <= zone / 2 then Theme.Colors.cash
				else Theme.Colors.panel2
		end
	end
	paintZone()

	-- Pin: a symmetric holder rotates about the center; only its top half is drawn.
	local pinLen = R + u(10)
	local pinHolder = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(u(6), pinLen * 2),
		Rotation = angle,
		ZIndex = 4,
		Parent = host.content,
	})
	local pin = UI.frame({
		BackgroundColor3 = Theme.Colors.text,
		Size = UDim2.new(1, 0, 0.5, 0),
		ZIndex = 4,
		Parent = pinHolder,
	})
	UI.corner(pin, u(3))
	local hub = UI.frame({
		BackgroundColor3 = Theme.Colors.gold,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(u(22), u(22)),
		ZIndex = 5,
		Parent = host.content,
	})
	UI.corner(hub, u(11))

	-- Progress pips under the ring.
	local pips: { Frame } = {}
	local pipSize = u(16)
	local pipRow = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(cx, cy + R + u(22)),
		Size = UDim2.fromOffset(target * (pipSize + u(8)), pipSize),
		Parent = host.content,
	})
	UI.list(pipRow, Enum.FillDirection.Horizontal, u(8), Enum.HorizontalAlignment.Center)
	for p = 1, target do
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
	local function paintPips()
		for p, pip in pips do
			local lit = p <= score
			pip.BackgroundColor3 = if lit then Theme.Colors.cash else Theme.Colors.panel2
			if lit then
				UI.punch(pip, 1.5, 0.3)
			end
		end
	end

	local tapArea = UI.button({
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 8,
		Parent = host.content,
	})
	Frame.press(host, { tapArea, host.zone }, function()
		if os.clock() < stunUntil then
			return
		end
		local d = angDist(angle, zoneCenter)
		local gained = if d <= sliver / 2 then 2 elseif d <= zone / 2 then 1 else 0
		if gained == 0 then
			-- Miss: the pin stutters red; the zone stays where it is.
			host.miss()
			stunUntil = os.clock() + 0.18
			pin.BackgroundColor3 = Theme.Colors.red
			UI.tween(pin, { BackgroundColor3 = Theme.Colors.text }, 0.3, nil, nil, 0.15)
			return
		end
		score = math.min(target, score + gained)
		ringStroke.Color = if gained == 2 then PINK else Theme.Colors.cash
		ringStroke.Thickness = u(6)
		UI.tween(ringStroke, { Color = Theme.Colors.grey, Thickness = u(3) }, 0.4)
		UI.punch(hub, 1.6, 0.25)
		UI.punch(pinHolder, 1.12, 0.2)
		host.haptic(if gained == 2 then 1 else 0.6)
		UI.sound(Theme.Sounds.take, 1 + score * 0.15, 0.5)
		paintPips()
		if score >= target then
			host.finish("done")
			return
		end
		zone = math.max(zone * Config.LockpickZoneShrink, zoneStart * 0.5)
		speed *= Config.LockpickSpeedUp
		-- The next zone sits well ahead of the pin so there is a sweep before the next tap.
		zoneCenter = (angle + 100 + math.random() * 160) % 360
		paintZone()
		host.setHint(string.format("%d / %d · ZONE %d°", score, target, math.round(zone)), Theme.Colors.cash)
	end)

	host.track(RunService.Heartbeat:Connect(function(dt)
		if os.clock() < stunUntil then
			return
		end
		angle = (angle + speed * dt) % 360
		pinHolder.Rotation = angle
	end))
end

return Lockpick
