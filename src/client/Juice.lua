--!strict
-- Rarity-scaled feedback shared by the weapon reel, the upgrade overlay and swaps.
-- Higher tier = bigger punch, camera shake, screen flash, ray burst, louder and higher sound.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local HUD = require(script.Parent:WaitForChild("HUD"))

export type Tier = {
	tier: number,
	punch: number,
	shake: number,
	shakeDur: number,
	flash: number,
	rays: boolean,
	rayCount: number,
	raySize: number,
	volume: number,
	pitch: number,
	hold: number,
}

local Juice = {}

function Juice.tier(tier: number): Tier
	local t = math.clamp(math.floor(tier), 1, 5)
	return {
		tier = t,
		punch = 1.04 + t * 0.035,
		shake = Config.JuiceShakeByTier[t],
		shakeDur = Config.JuiceShakeDurByTier[t],
		flash = Config.JuiceFlashByTier[t],
		rays = t >= 3,
		rayCount = 4 + t * 2,
		raySize = 120 + t * 50,
		volume = 0.35 + t * 0.09,
		pitch = 0.55 + t * 0.15,
		hold = if t >= 4 then 0.3 else 0,
	}
end

-- Radial ray burst behind a screen point.
function Juice.rays(center: Vector2, color: Color3, count: number, size: number, duration: number)
	local S = UI.S
	local gui = HUD.gui
	if not gui then
		return
	end
	local rays = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = UDim2.fromOffset(S(10), S(10)),
		ZIndex = 0,
		Parent = gui,
	})
	for i = 1, count do
		local ray = UI.frame({
			BackgroundColor3 = color,
			BackgroundTransparency = 0.25,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(S(16), S(size)),
			Rotation = (i - 1) * (360 / count),
			Parent = rays,
		})
		UI.tween(ray, { BackgroundTransparency = 1, Size = UDim2.fromOffset(S(4), S(size * 1.7)) }, duration)
	end
	UI.tween(rays, { Rotation = 35 }, duration)
	task.delay(duration + 0.05, function()
		rays:Destroy()
	end)
end

-- Round 19l: GUI particles. They draw on their own top ScreenGui (IgnoreGuiInset, so screen points from an inset-free
-- overlay line up) and outlive the panel that spawned them (the upgrade overlay hides 0.34 s after a pick).
local fxGui: ScreenGui? = nil
local function fxLayer(): ScreenGui
	local g = fxGui
	if g and g.Parent then
		return g
	end
	local made = Instance.new("ScreenGui")
	made.Name = "JuiceFx"
	made.IgnoreGuiInset = true
	made.ResetOnSpawn = false
	made.DisplayOrder = Config.JuiceFxDisplayOrder
	made.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	made.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	fxGui = made
	return made
end

export type SparkOpts = {
	speed: number?, -- px/s (760 basis) of the fastest chip
	life: number?, -- seconds a chip lives (each varies ±)
	size: number?, -- px (760 basis) of a chip
	ring: number?, -- shockwave ring end size in px (760 basis); 0 = no ring / glow
	up: number?, -- share of `speed` added upward (a fountain); default Config.UpgradeFxUpBias
}

-- A burst of chips at a screen point: squares, slivers and dots in `color` (some washed toward white) flying out on
-- arcs with gravity, drag, spin, shrinking and fading late; plus a shockwave ring and a soft glow. One RenderStepped
-- connection per burst, gone with it.
function Juice.sparks(center: Vector2, color: Color3, count: number, opts: SparkOpts?)
	local o: SparkOpts = opts or {}
	local S = UI.S
	local layer = fxLayer()
	local life = o.life or Config.UpgradeFxLife
	local speed = S(o.speed or Config.UpgradeFxSparkSpeed)
	local gravity = S(Config.UpgradeFxGravity)
	local size = S(o.size or Config.UpgradeFxSparkSize)
	local up = o.up or Config.UpgradeFxUpBias
	local white = Color3.new(1, 1, 1)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = layer

	local ringEnd = if o.ring == nil then Config.UpgradeFxRingSize else o.ring
	if ringEnd > 0 then
		local rs = S(ringEnd)
		local ring = UI.frame({
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center.X, center.Y),
			Size = UDim2.fromOffset(S(16), S(16)),
			Parent = holder,
		})
		UI.corner(ring, 9999)
		local stroke = UI.stroke(ring, color:Lerp(white, 0.25), S(7), 0)
		UI.tween(ring, { Size = UDim2.fromOffset(rs, rs) }, life * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		UI.tween(stroke, { Transparency = 1, Thickness = 1 }, life * 0.6)
		local glow = UI.frame({
			BackgroundColor3 = color:Lerp(white, 0.6),
			BackgroundTransparency = 0.3,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center.X, center.Y),
			Size = UDim2.fromOffset(rs * 0.2, rs * 0.2),
			Parent = holder,
		})
		UI.corner(glow, 9999)
		UI.tween(
			glow,
			{ Size = UDim2.fromOffset(rs * 0.55, rs * 0.55), BackgroundTransparency = 1 },
			life * 0.35,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		)
	end

	type Chip = {
		f: Frame,
		x: number,
		y: number,
		vx: number,
		vy: number,
		rot: number,
		spin: number,
		w: number,
		h: number,
		life: number,
	}
	local chips: { Chip } = {}
	for i = 1, count do
		local a = (i / count) * math.pi * 2 + (math.random() - 0.5) * 0.6
		local sp = speed * (0.45 + math.random() * 0.75)
		local w = size * (0.6 + math.random() * 0.8)
		local sliver = i % 3 == 0
		local h = if sliver then w * 2.4 else w
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = color:Lerp(white, math.random() * 0.6)
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromOffset(center.X, center.Y)
		f.Size = UDim2.fromOffset(w, h)
		f.Rotation = math.random(0, 359)
		if i % 4 == 0 then
			UI.corner(f, 9999) -- a few round dots among the squares
		end
		f.Parent = holder
		table.insert(chips, {
			f = f,
			x = center.X,
			y = center.Y,
			vx = math.cos(a) * sp,
			vy = math.sin(a) * sp - speed * up,
			rot = f.Rotation,
			spin = (math.random() * 2 - 1) * 900,
			w = w,
			h = h,
			life = life * (0.7 + math.random() * 0.5),
		})
	end

	local t = 0
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt: number)
		t += dt
		local drag = math.exp(-dt * Config.UpgradeFxDrag)
		for _, c in chips do
			if t < c.life then
				c.vx *= drag
				c.vy = c.vy * drag + gravity * dt
				c.x += c.vx * dt
				c.y += c.vy * dt
				c.rot += c.spin * dt
				local k = t / c.life
				local s = 1 - 0.55 * k
				c.f.Position = UDim2.fromOffset(c.x, c.y)
				c.f.Rotation = c.rot
				c.f.Size = UDim2.fromOffset(c.w * s, c.h * s)
				c.f.BackgroundTransparency = k * k
			elseif c.f.Visible then
				c.f.Visible = false
			end
		end
		if t > life * 1.25 then
			conn:Disconnect()
			holder:Destroy()
		end
	end)
end

-- The full burst for a tier at a screen point (rays), plus shake and flash through the Juice signal.
function Juice.burst(tier: number, color: Color3, center: Vector2?): Tier
	local j = Juice.tier(tier)
	if j.rays and center then
		Juice.rays(center, color, j.rayCount, j.raySize, 0.6)
	end
	if j.flash > 0 then
		ClientState.Juice:Fire("RarityFlash", { color = color, alpha = j.flash })
	end
	if j.shake > 0 then
		ClientState.Juice:Fire("Shake", { amp = j.shake, dur = j.shakeDur })
	end
	if j.tier == 5 then
		UI.sound(Theme.Sounds.legendary, 1, 0.75)
	end
	return j
end

return Juice
