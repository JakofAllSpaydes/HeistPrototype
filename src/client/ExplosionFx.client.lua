--!strict
-- Brief 12: how an explosion lands (the server's Explosion event, Run/Explosion.lua): a one-frame white flash at the
-- centre, a shock ring expanding to the blast radius, dust and debris by radius, a low thud under the boom, and the
-- shooter-side camera punch scaled by 1 / distance (capped at Config.ExplosionPunch); everyone else in range gets a
-- small shake. Its hit numbers pop outward (WorldFx, the Hit's `outward`). Everything scales with MobileFxScale.
-- Written so Brief 14's Fx ladder can absorb it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local SCALE = if ClientState.isMobile then Config.MobileFxScale else 1
local player = Players.LocalPlayer

local folder = Instance.new("Folder")
folder.Name = "GHSExplosions"
folder.Parent = Workspace

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = folder
	return p
end

local function emitter(props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	for k, v in props do
		(e :: any)[k] = v
	end
	return e
end

local function explode(at: Vector3, radius: number, color: Color3, ownerId: number, shake: number?)
	-- The flash: one frame of white at the centre.
	local flash = part({
		Name = "Flash",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * math.max(2, radius * 0.7),
		Position = at,
		Color = Color3.new(1, 1, 1),
		Material = Enum.Material.Neon,
		Transparency = 0,
	})
	local light = Instance.new("PointLight")
	light.Brightness = 6
	light.Range = math.min(60, radius * 2.5)
	light.Color = Color3.new(1, 0.92, 0.8)
	light.Parent = flash
	task.delay(1 / 30, function()
		flash.Transparency = 1
		TweenService:Create(light, TweenInfo.new(0.25), { Brightness = 0 }):Play()
		task.delay(0.3, function()
			flash:Destroy()
		end)
	end)
	-- The shock ring: a flat disc that grows out to the radius and fades.
	local ring = part({
		Name = "Shock",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, 1, 1),
		CFrame = CFrame.new(at.X, at.Y - 1.5, at.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color:Lerp(Color3.new(1, 1, 1), 0.4),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
	})
	TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	task.delay(0.4, function()
		ring:Destroy()
	end)
	-- Dust and debris, by radius.
	local anchor = part({ Name = "Dust", Size = Vector3.one * 0.2, Position = at, Transparency = 1 })
	local dust = emitter({
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(150, 140, 125), Color3.fromRGB(90, 86, 80)),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, radius * 0.25),
			NumberSequenceKeypoint.new(1, radius * 0.6),
		}),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(radius * 0.6, radius * 1.2),
		SpreadAngle = Vector2.new(180, 60),
		Drag = 3,
		Acceleration = Vector3.new(0, 2, 0),
		RotSpeed = NumberRange.new(-60, 60),
		Rotation = NumberRange.new(0, 360),
		Parent = anchor,
	})
	local debris = emitter({
		Color = ColorSequence.new(Color3.fromRGB(60, 56, 52)),
		Size = NumberSequence.new(0.18, 0.1),
		Lifetime = NumberRange.new(0.6, 1.1),
		Speed = NumberRange.new(radius * 1.2, radius * 2.2),
		SpreadAngle = Vector2.new(70, 70),
		Acceleration = Vector3.new(0, -60, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-300, 300),
		EmissionDirection = Enum.NormalId.Top,
		Parent = anchor,
	})
	dust:Emit(math.max(3, math.round(math.min(40, radius * 1.5) * SCALE)))
	debris:Emit(math.max(2, math.round(math.min(30, radius * 1.2) * SCALE)))
	task.delay(1.6, function()
		anchor:Destroy()
	end)
	-- The boom with a low thud under it.
	UI.soundAt(anchor, Theme.Sounds.shot, 0.35, 0.6, 140)
	UI.soundAt(anchor, Theme.Sounds.crate, 0.55, 0.55, 120)
	-- The camera: the shooter's punch by distance; a small shake for everyone else in range.
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local dist = if root and root:IsA("BasePart") then (root.Position - at).Magnitude else math.huge
	if ownerId == player.UserId then
		local amp = math.min(Config.ExplosionPunch, Config.ExplosionPunchRef / math.max(1, dist))
		ClientState.Juice:Fire("Shake", { amp = math.max(amp, (shake or 0) * 0.5), dur = 0.22 })
	elseif dist < Config.ExplosionShakeRange then
		local fade = 1 - dist / Config.ExplosionShakeRange
		ClientState.Juice:Fire("Shake", { amp = Config.ExplosionOthersShake * fade, dur = 0.15 })
	end
end

ClientState.Juice:Connect(function(name: string, data: any)
	if name ~= "Explosion" or typeof(data) ~= "table" or typeof(data.position) ~= "Vector3" then
		return
	end
	local color = if typeof(data.color) == "Color3" then data.color else Color3.fromHex("FF8A2A")
	explode(data.position, tonumber(data.radius) or 8, color, tonumber(data.owner) or 0, tonumber(data.shake))
end)
