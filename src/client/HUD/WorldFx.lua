--!strict
-- World-space juice: damage numbers, kill pop, cash floats, enemy hit flash, red screen pulse on damage.
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ClientState = require(Client:WaitForChild("ClientState"))
local Rarity = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rarity"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local WorldFx = {}

local function billboard(position: Vector3, width: number, height: number, lifetime: number): (BillboardGui, Attachment)
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = Workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Adornee = att
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(width, height)
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	gui.Parent = att
	task.delay(lifetime, function()
		att:Destroy()
	end)
	return gui, att
end

local function floatText(position: Vector3, text: string, color: Color3, size: number, rise: number, lifetime: number)
	local gui = billboard(position + Vector3.new((math.random() - 0.5) * 1.5, 0, 0), 160, 60, lifetime)
	local label = UI.text({
		Text = text,
		Font = Theme.Fonts.display,
		TextSize = size,
		TextColor3 = color,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	UI.stroke(label, Theme.Colors.black, 2, 0.2)
	UI.punch(label, 1.4, 0.25)
	UI.tween(gui, { StudsOffset = Vector3.new(0, rise, 0) }, lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	UI.tween(
		label,
		{ TextTransparency = 1 },
		lifetime * 0.5,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In,
		lifetime * 0.5
	)
end

local function flashEnemy(model: Model)
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p.Name ~= "Head" then
			local original = p:GetAttribute("OrigColor") :: Color3?
			if not original then
				original = p.Color
				p:SetAttribute("OrigColor", original)
			end
			p.Color = Theme.Colors.red
			task.delay(0.08, function()
				if p.Parent and original then
					p.Color = original
				end
			end)
		end
	end
end

-- Short glowing line between two world points (ricochet trail).
local function trail(from: Vector3, to: Vector3, color: Color3, lifetime: number)
	local a0 = Instance.new("Attachment")
	a0.WorldPosition = from
	a0.Parent = Workspace.Terrain
	local a1 = Instance.new("Attachment")
	a1.WorldPosition = to
	a1.Parent = Workspace.Terrain
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 0.35
	beam.Width1 = 0.1
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new(0)
	beam.Parent = a0
	task.delay(lifetime, function()
		a0:Destroy()
		a1:Destroy()
	end)
end

-- Expanding ring on the floor (splash blast).
local function blastRing(position: Vector3, radius: number, color: Color3)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, 1, 1)
	ring.CFrame = CFrame.new(position.X, 0.4, position.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.2
	ring.Parent = Workspace:FindFirstChild("Effects") or Workspace
	UI.tween(ring, { Size = Vector3.new(0.3, radius * 2, radius * 2), Transparency = 1 }, 0.35)
	task.delay(0.4, function()
		ring:Destroy()
	end)
end

local function killPop(position: Vector3)
	local gui = billboard(position, 40, 40, 0.4)
	local ring = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.3, 0.3),
		Parent = gui,
	})
	UI.corner(ring, 999)
	local stroke = UI.stroke(ring, Theme.Colors.gold, 4)
	UI.tween(ring, { Size = UDim2.fromScale(1, 1) }, 0.3)
	UI.tween(stroke, { Transparency = 1 }, 0.3)
end

function WorldFx.build(gui: ScreenGui, track: (RBXScriptConnection) -> ())
	local vignette = UI.frame({
		Name = "HurtVignette",
		BackgroundColor3 = Theme.Colors.red,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Parent = gui,
	})
	UI.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.35, 1),
			NumberSequenceKeypoint.new(0.65, 1),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Parent = vignette,
	})

	local flash = UI.frame({
		Name = "RarityFlash",
		BackgroundColor3 = Theme.Colors.gold,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Parent = gui,
	})

	-- Enemy spawn puff: a dark ring where each enemy appears.
	local enemies = Workspace:FindFirstChild("Enemies")
	if enemies then
		track(enemies.ChildAdded:Connect(function(model)
			task.defer(function()
				local root = model:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					blastRing(root.Position, 5, Color3.fromRGB(120, 40, 40))
				end
			end)
		end))
	end

	-- Multi-kill counter beside the crosshair: kills inside Config.ComboWindowSec chain, pitch climbs.
	local S = UI.S
	local comboLabel = UI.text({
		Name = "Combo",
		Text = "",
		Font = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, S(44), 0.5, -S(30)),
		Size = UDim2.fromOffset(S(200), S(40)),
		Visible = false,
		ZIndex = 4,
		Parent = gui,
	})
	local comboStroke = UI.stroke(comboLabel, Theme.Colors.black, S(2), 0.2)
	local combo = 0
	local lastKillAt = -100
	local comboToken = 0
	local function onKill()
		local now = os.clock()
		combo = if now - lastKillAt <= Config.ComboWindowSec then combo + 1 else 1
		lastKillAt = now
		-- The count climbs with every kill from x2; the word only changes when a tier count is reached.
		if combo < 2 then
			return
		end
		local reached = 0
		local hit = false
		for i, tier in Config.ComboTiers do
			if combo >= tier.at then
				reached = i
			end
			if combo == tier.at then
				hit = true
			end
		end
		local word = if reached > 0 then " " .. Config.ComboTiers[reached].name else ""
		comboLabel.Text = string.format("x%d%s", combo, word)
		comboLabel.TextColor3 = if reached >= 5 then Theme.Colors.red else Theme.Colors.gold
		comboLabel.TextSize = S(16 + reached * 2)
		comboLabel.TextTransparency = 0
		comboStroke.Transparency = 0.2
		comboLabel.Visible = true
		if hit then
			UI.punch(comboLabel, 1.4 + reached * 0.08, 0.3)
			UI.sound(Theme.Sounds.kill, math.min(2.4, 1.3 + reached * 0.15), 0.25)
			if reached >= 4 then
				ClientState.Juice:Fire("Shake", { amp = 0.15, dur = 0.2 })
			end
		else
			UI.punch(comboLabel, 1.15, 0.15)
		end
		comboToken += 1
		local token = comboToken
		task.delay(Config.ComboWindowSec, function()
			if token ~= comboToken then
				return
			end
			UI.tween(comboLabel, { TextTransparency = 1 }, 0.3)
			UI.tween(comboStroke, { Transparency = 1 }, 0.3)
			task.delay(0.32, function()
				if token == comboToken then
					comboLabel.Visible = false
				end
			end)
		end)
	end

	local component = {}

	function component.onJuice(name: string, data: any)
		if name == "RarityFlash" then
			flash.BackgroundColor3 = data.color or Theme.Colors.gold
			flash.BackgroundTransparency = 1 - (data.alpha or 0.3)
			UI.tween(flash, { BackgroundTransparency = 1 }, 0.4)
		elseif name == "Hit" then
			local color = if data.crit
				then Theme.Colors.red
				elseif data.headshot then Theme.Colors.gold
				else Theme.Colors.text
			local size = if data.secondary then 18 elseif data.crit then 34 elseif data.headshot then 30 else 24
			floatText(data.position, tostring(data.amount), color, size, 2.5, 0.7)
			if typeof(data.model) == "Instance" then
				flashEnemy(data.model)
			end
			UI.sound(Theme.Sounds.hit, if data.headshot then 1.4 else 1, 0.2)
			if data.killed then
				killPop(data.position)
				UI.sound(Theme.Sounds.kill, 1.2, 0.12)
				onKill()
				if data.cash and data.cash > 0 then
					floatText(
						data.position + Vector3.new(0, 1, 0),
						"+" .. UI.fmtCash(data.cash),
						Theme.Colors.cash,
						28,
						5,
						1.1
					)
				end
			end
		elseif name == "PlayerHit" then
			vignette.BackgroundTransparency = 0.55
			UI.tween(vignette, { BackgroundTransparency = 1 }, 0.45)
			UI.sound(Theme.Sounds.hurt, 1, 0.25)
		elseif name == "Ricochet" then
			trail(data.from, data.to, Theme.Colors.gold, 0.12)
			UI.sound(Theme.Sounds.reelTick, 1.8, 0.45)
		elseif name == "Splash" then
			blastRing(data.position, data.radius or 8, Theme.Colors.malus)
			UI.sound(Theme.Sounds.crate, 1.6, 0.5)
			ClientState.Juice:Fire("Shake", { amp = 0.15, dur = 0.15 })
		elseif name == "Swap" and typeof(data.position) == "Vector3" then
			blastRing(data.position, 6, Rarity.color(data.rarity or 1))
		elseif name == "CallEnd" and typeof(data.position) == "Vector3" then
			blastRing(data.position, 10, if data.success then Theme.Colors.cash else Theme.Colors.red)
		elseif name == "WaveStart" then
			flash.BackgroundColor3 = Theme.Colors.text
			flash.BackgroundTransparency = 0.8
			UI.tween(flash, { BackgroundTransparency = 1 }, 0.5)
			ClientState.Juice:Fire("Shake", { amp = 0.25, dur = 0.3 })
		elseif name == "VanBrake" and typeof(data.position) == "Vector3" then
			blastRing(data.position, 14, Color3.fromRGB(160, 150, 130))
			UI.sound(Theme.Sounds.crate, 0.7, 0.7)
			ClientState.Juice:Fire("Shake", { amp = 0.3, dur = 0.3 })
		elseif name == "RunOver" then
			-- Slow-mo read: the world drains of color and tints red for the stamp, then recovers.
			local existing = Lighting:FindFirstChild("GHSSlowMo")
			local cc = if existing and existing:IsA("ColorCorrectionEffect")
				then existing
				else Instance.new("ColorCorrectionEffect")
			cc.Name = "GHSSlowMo"
			cc.Saturation = 0
			cc.TintColor = Theme.Colors.white
			cc.Parent = Lighting
			UI.tween(cc, { Saturation = -0.8, TintColor = Color3.fromRGB(255, 200, 200) }, 0.25)
			task.delay((data.slowSec or 1) + (data.holdSec or 2.5) - 0.6, function()
				UI.tween(cc, { Saturation = 0, TintColor = Theme.Colors.white }, 0.6)
			end)
		elseif name == "RunResumed" then
			local cc = Lighting:FindFirstChild("GHSSlowMo")
			if cc and cc:IsA("ColorCorrectionEffect") then
				UI.tween(cc, { Saturation = 0, TintColor = Theme.Colors.white }, 0.3)
			end
		elseif name == "Multishot" then
			UI.sound(Theme.Sounds.shot, 1.4, 0.25)
		elseif name == "TurretShot" then
			trail(data.from, data.to, Theme.Colors.gold, 0.06)
			UI.sound(Theme.Sounds.shot, 1.6, 0.15)
		elseif name == "StructurePlaced" then
			blastRing(data.position, 5, Theme.Colors.gold)
			UI.sound(Theme.Sounds.crate, 1.2, 0.5)
		elseif name == "StructureHit" then
			UI.sound(Theme.Sounds.kill, 0.8, 0.08)
		elseif name == "StructureGone" then
			blastRing(data.position, 6, Theme.Colors.malus)
			UI.sound(Theme.Sounds.deny, 0.9, 0.15)
		elseif name == "StimStart" then
			vignette.BackgroundColor3 = Theme.Colors.gold
			vignette.BackgroundTransparency = 0.5
			UI.tween(vignette, { BackgroundTransparency = 1 }, 0.6)
			task.delay(0.65, function()
				vignette.BackgroundColor3 = Theme.Colors.red
			end)
		elseif name == "GunLanded" then
			UI.sound(Theme.Sounds.crate, 1.3, 0.5)
			local gui = billboard(data.position + Vector3.new(0, 1, 0), 60, 60, 0.5)
			local ring = UI.frame({
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.2, 0.2),
				Parent = gui,
			})
			UI.corner(ring, 999)
			local stroke = UI.stroke(ring, Rarity.color(data.rarity or 1), 4)
			UI.tween(ring, { Size = UDim2.fromScale(1, 1) }, 0.4)
			UI.tween(stroke, { Transparency = 1 }, 0.4)
		end
	end

	return component
end

return WorldFx
