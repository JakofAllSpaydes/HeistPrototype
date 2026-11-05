--!strict
-- World-space juice: damage numbers, kill pop, cash floats, enemy hit flash, impact sparks, red screen pulse
-- on damage, and teammates' shots (tracer from their gun, shot sound at their gun).
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
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

-- Bullet line, the same look as the local one in Gun.client.lua.
local TRACER_COLOR = Color3.fromHex("FFE2A0")
local function tracer(from: Vector3, to: Vector3)
	local a0 = Instance.new("Attachment")
	a0.WorldPosition = from
	a0.Parent = Workspace.Terrain
	local a1 = Instance.new("Attachment")
	a1.WorldPosition = to
	a1.Parent = Workspace.Terrain
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 0.12
	beam.Width1 = 0.05
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Color = ColorSequence.new(TRACER_COLOR)
	beam.Transparency = NumberSequence.new(0.1)
	beam.Parent = a0
	task.delay(0.05, function()
		a0:Destroy()
		a1:Destroy()
	end)
end

-- A sound that sits in the world (a teammate's gun): quieter with distance, panned.
local function soundAt(parent: Instance, id: string, pitch: number, volume: number, range: number)
	if id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.PlaybackSpeed = pitch
	s.Volume = volume
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 8
	s.RollOffMaxDistance = range
	s.Parent = parent
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

-- A 3D sound at a world point (an enemy's gun, a shell landing): a throwaway attachment carries it.
local function soundAtPoint(position: Vector3, id: string, pitch: number, volume: number, range: number)
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = Workspace.Terrain
	soundAt(att, id, pitch, volume, range)
	task.delay(5, function()
		att:Destroy()
	end)
end

-- Enemy tracers: orange-red so they never read as a teammate's shot; a Marksman round is wider.
local ENEMY_TRACER = Color3.fromHex("FF8A5A")
local function enemyTracer(from: Vector3, to: Vector3, heavy: boolean)
	local a0 = Instance.new("Attachment")
	a0.WorldPosition = from
	a0.Parent = Workspace.Terrain
	local a1 = Instance.new("Attachment")
	a1.WorldPosition = to
	a1.Parent = Workspace.Terrain
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = if heavy then 0.3 else 0.14
	beam.Width1 = if heavy then 0.2 else 0.06
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Color = ColorSequence.new(if heavy then Theme.Colors.red else ENEMY_TRACER)
	beam.Transparency = NumberSequence.new(0.05)
	beam.Parent = a0
	task.delay(if heavy then 0.12 else 0.06, function()
		a0:Destroy()
		a1:Destroy()
	end)
end

-- Muzzle flash on an enemy gun: a short glow plus a few chips at the muzzle.
local function muzzleFlash(position: Vector3)
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = Workspace.Terrain
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 120)
	light.Brightness = 4
	light.Range = 10
	light.Parent = att
	task.delay(0.06, function()
		att:Destroy()
	end)
end

-- Short burst of glowing chips off a hit point (bullet impact / kill).
local function sparks(position: Vector3, color: Color3, count: number, speed: number)
	if count <= 0 then
		return
	end
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = Workspace.Terrain
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.15, 0.4)
	e.Speed = NumberRange.new(speed * 0.4, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Acceleration = Vector3.new(0, -40, 0)
	e.Drag = 4
	e.Parent = att
	e:Emit(count)
	task.delay(1, function()
		att:Destroy()
	end)
end

-- Expanding ring on the floor (splash blast).
local function blastRing(position: Vector3, radius: number, color: Color3)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, 1, 1)
	ring.CFrame = CFrame.new(position.X, Config.FloorTop + 0.4, position.Z) * CFrame.Angles(0, 0, math.rad(90))
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
	-- Vault gas: a sickly green tint while you stand in it.
	local gasTint = UI.frame({
		Name = "GasTint",
		BackgroundColor3 = Color3.fromRGB(150, 220, 110),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Parent = gui,
	})

	-- Enemy spawn puff: a dark ring where each enemy appears. Every enemy also gets its flinch watcher
	-- (the server stamps FlinchAt on a hit; a white pop reads as the hit reaction on every client) and the
	-- Runner its shrill approach wail.
	local enemies = Workspace:FindFirstChild("Enemies")
	local function watchEnemy(model: Instance, fresh: boolean)
		if not model:IsA("Model") then
			return
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		if fresh and root and root:IsA("BasePart") then
			blastRing(root.Position, 5, Color3.fromRGB(120, 40, 40))
		end
		local conn: RBXScriptConnection
		conn = model:GetAttributeChangedSignal("FlinchAt"):Connect(function()
			if not model.Parent then
				conn:Disconnect()
				return
			end
			local pop = Instance.new("Highlight")
			pop.Name = "FlinchPop"
			pop.FillColor = Theme.Colors.white
			pop.FillTransparency = 0.35
			pop.OutlineTransparency = 1
			pop.DepthMode = Enum.HighlightDepthMode.Occluded
			pop.Parent = model
			task.delay(0.09, function()
				pop:Destroy()
			end)
		end)
		track(conn)
		if
			model:GetAttribute("Archetype") == "Runner"
			and root
			and root:IsA("BasePart")
			and not root:FindFirstChild("RunnerWail")
		then
			local wail = Instance.new("Sound")
			wail.Name = "RunnerWail"
			wail.SoundId = Theme.Sounds.runner
			wail.PlaybackSpeed = 1.7
			wail.Volume = 0.25
			wail.Looped = true
			wail.RollOffMode = Enum.RollOffMode.InverseTapered
			wail.RollOffMinDistance = 10
			wail.RollOffMaxDistance = 70
			wail.Parent = root
			wail:Play()
			-- The wail stops with the body: a kill removes the Humanoid.
			model.ChildRemoved:Connect(function(child)
				if child:IsA("Humanoid") and wail.Parent then
					wail:Destroy()
				end
			end)
		end
	end
	if enemies then
		for _, model in enemies:GetChildren() do
			if model:FindFirstChildOfClass("Humanoid") then
				watchEnemy(model, false)
			end
		end
		track(enemies.ChildAdded:Connect(function(model)
			task.defer(watchEnemy, model, true)
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

	-- Stragglers: with StragglerHighlightCount or fewer left in the wave, every survivor gets a red Highlight
	-- that reads through walls, so the last few are findable.
	local highlighting = false
	local function highlight(model: Instance)
		-- A ragdolled body has no Humanoid any more: it is not a straggler.
		if
			not model:IsA("Model")
			or model:FindFirstChild("StragglerGlow")
			or not model:FindFirstChildOfClass("Humanoid")
		then
			return
		end
		local h = Instance.new("Highlight")
		h.Name = "StragglerGlow"
		h.FillColor = Theme.Colors.red
		h.FillTransparency = 0.55
		h.OutlineColor = Theme.Colors.red
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.Parent = model
	end
	local function setHighlighting(on: boolean)
		if on == highlighting then
			return
		end
		highlighting = on
		if not enemies then
			return
		end
		for _, model in enemies:GetChildren() do
			if on then
				highlight(model)
			else
				local h = model:FindFirstChild("StragglerGlow")
				if h then
					h:Destroy()
				end
			end
		end
	end
	if enemies then
		track(enemies.ChildAdded:Connect(function(model)
			if highlighting then
				task.defer(highlight, model)
			end
		end))
	end

	function component.update(sync: any)
		local left = sync.enemiesLeft or 0
		setHighlighting(sync.waveState == "Wave" and left > 0 and left <= Config.StragglerHighlightCount)
	end

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
			if typeof(data.position) == "Vector3" then
				sparks(data.position, TRACER_COLOR, Config.HitSparks, 18)
			end
			UI.sound(Theme.Sounds.hit, if data.headshot then 1.4 else 1, 0.2)
			if data.killed then
				killPop(data.position)
				if typeof(data.position) == "Vector3" then
					sparks(data.position, Theme.Colors.red, Config.KillSparks, 28)
				end
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
		elseif name == "RemoteShot" then
			-- A teammate fired: their tracer from their gun's muzzle to where each bullet stopped, and the shot
			-- sound at their gun. No numbers, no hitmarker: that feedback is the shooter's.
			local p = Players:GetPlayerByUserId(tonumber(data.userId) or 0)
			local char = p and p.Character
			local heldGun = char and char:FindFirstChild("HeldGun")
			local muzzleAtt = heldGun and heldGun:FindFirstChild("Muzzle")
			local from = if muzzleAtt and muzzleAtt:IsA("Attachment")
				then muzzleAtt.WorldPosition
				elseif typeof(data.from) == "Vector3" then data.from
				else nil
			if from and typeof(data.ends) == "table" then
				for _, to in data.ends do
					if typeof(to) == "Vector3" then
						tracer(from, to)
					end
				end
			end
			local head = char and char:FindFirstChild("Head")
			if head then
				local pitch = Config.ShotPitchByArchetype[tostring(data.archetype)] or 1
				soundAt(head, Theme.Sounds.shot, pitch, Config.RemoteShotVolume, Config.RemoteShotRange)
			end
		elseif name == "PlayerHit" then
			vignette.BackgroundTransparency = 0.55
			UI.tween(vignette, { BackgroundTransparency = 1 }, 0.45)
			UI.sound(Theme.Sounds.hurt, 1, 0.25)
		elseif name == "EnemyShot" then
			-- A Shooter or Marksman fired: tracer from its muzzle, flash and crack at the gun; a miss aimed at you
			-- whips past your ear.
			if typeof(data.from) == "Vector3" and typeof(data.to) == "Vector3" then
				enemyTracer(data.from, data.to, data.heavy == true)
				muzzleFlash(data.from)
				sparks(data.from, Color3.fromRGB(255, 210, 140), 4, 10)
				soundAtPoint(data.from, Theme.Sounds.shot, if data.heavy then 0.55 else 0.8, 0.35, 140)
				if data.userId == Players.LocalPlayer.UserId and not data.hit then
					UI.sound(Theme.Sounds.swap, 1.8, 0.35)
				end
			end
		elseif name == "EnemyLaser" and typeof(data.position) == "Vector3" then
			soundAtPoint(data.position, Theme.Sounds.laser, 0.45, 0.45, 120)
		elseif name == "BoomerFuse" then
			-- Rising beeps at the Boomer for the length of the fuse (at the body, or where it fell).
			local model = if typeof(data.model) == "Instance" then data.model else nil
			local root = model and model:FindFirstChild("HumanoidRootPart")
			local at: Vector3? = if typeof(data.position) == "Vector3" then data.position else nil
			local sec = tonumber(data.sec) or 1.2
			local beeps = math.max(3, math.floor(sec * 5))
			task.spawn(function()
				for i = 1, beeps do
					if root and root.Parent then
						soundAt(root, Theme.Sounds.beep, 0.9 + i * 0.25, 0.45, 90)
					elseif at then
						soundAtPoint(at, Theme.Sounds.beep, 0.9 + i * 0.3, 0.45, 90)
					else
						return
					end
					task.wait(sec / beeps)
				end
			end)
		elseif name == "EnemyLob" and typeof(data.from) == "Vector3" then
			soundAtPoint(data.from, Theme.Sounds.lob, 1.3, 0.35, 110)
		elseif name == "PlateOff" and typeof(data.position) == "Vector3" then
			sparks(data.position, Color3.fromRGB(200, 205, 215), 14, 22)
			soundAtPoint(data.position, Theme.Sounds.crunch, 0.6, 0.6, 120)
		elseif name == "BagCollected" and typeof(data.position) == "Vector3" then
			-- The bag pops in a money burst; the number floats where it stood.
			local gold = data.kind == "gold"
			local color = if gold then Theme.Colors.gold else Theme.Colors.cash
			sparks(data.position + Vector3.new(0, 1, 0), color, 24, 26)
			blastRing(data.position, 5, color)
			floatText(
				data.position + Vector3.new(0, 2, 0),
				if gold then "◆ +" .. tostring(data.value) else "+" .. UI.fmtCash(tonumber(data.value) or 0),
				color,
				26,
				4,
				1.1
			)
			UI.sound(Theme.Sounds.take, if gold then 0.9 else 1.3, 0.5)
			UI.sound(Theme.Sounds.reelLand, 1.2, 0.3)
		elseif name == "VaultGasTint" then
			UI.tween(gasTint, { BackgroundTransparency = if data.on then 0.55 else 1 }, 0.4)
			if data.on then
				UI.sound(Theme.Sounds.hurt, 0.6, 0.3)
			end
		elseif name == "VaultOpen" and typeof(data.position) == "Vector3" then
			blastRing(data.position, 12, Theme.Colors.amber)
			UI.sound(Theme.Sounds.swap, 0.45, 0.7)
			UI.sound(Theme.Sounds.crate, 0.8, 0.6)
			ClientState.Juice:Fire("Shake", { amp = 0.3, dur = 0.35 })
		elseif name == "VaultGas" then
			if data.phase == "warn" then
				-- The alarm: three low blasts.
				task.spawn(function()
					for i = 1, 3 do
						UI.sound(Theme.Sounds.deny, 0.5, 0.6)
						task.wait(0.35)
					end
				end)
			else
				UI.sound(Theme.Sounds.swap, 0.35, 0.8)
			end
		elseif name == "VaultSealed" and typeof(data.position) == "Vector3" then
			UI.sound(Theme.Sounds.crunch, 0.5, 0.6)
			blastRing(data.position, 8, Theme.Colors.grey)
		elseif name == "HubEnter" then
			gasTint.BackgroundTransparency = 1
		elseif name == "BossWallBlow" and typeof(data.position) == "Vector3" then
			blastRing(data.position, 16, Color3.fromRGB(160, 150, 130))
			sparks(data.position + Vector3.new(0, 4, 0), Color3.fromRGB(200, 190, 170), 30, 30)
		elseif name == "BossSweepSpin" and typeof(data.position) == "Vector3" then
			-- The rising whine: a run of ticks climbing in pitch over the spin-up.
			local sec = tonumber(data.sec) or 1.5
			task.spawn(function()
				local n = 8
				for i = 1, n do
					soundAtPoint(data.position, Theme.Sounds.laser, 0.6 + i * 0.18, 0.4, 160)
					task.wait(sec / n)
				end
			end)
		elseif name == "BossSweep" and typeof(data.position) == "Vector3" then
			local sec = tonumber(data.sec) or 3
			task.spawn(function()
				local t0 = os.clock()
				while os.clock() - t0 < sec do
					soundAtPoint(data.position, Theme.Sounds.shot, 0.7, 0.3, 160)
					task.wait(0.09)
				end
			end)
			ClientState.Juice:Fire("Shake", { amp = 0.2, dur = 0.3 })
		elseif name == "BossCharge" and typeof(data.position) == "Vector3" then
			if data.phase == "telegraph" then
				soundAtPoint(data.position, Theme.Sounds.hurt, 0.4, 0.9, 200)
			else
				soundAtPoint(data.position, Theme.Sounds.wave, 0.6, 0.8, 200)
				ClientState.Juice:Fire("Shake", { amp = 0.25, dur = 0.3 })
			end
		elseif name == "BossStagger" and typeof(data.position) == "Vector3" then
			blastRing(data.position, 10, Theme.Colors.grey)
			sparks(data.position + Vector3.new(0, 3, 0), Color3.fromRGB(200, 190, 170), 24, 26)
			soundAtPoint(data.position, Theme.Sounds.crunch, 0.4, 1, 220)
			ClientState.Juice:Fire("Shake", { amp = 0.7, dur = 0.45 })
		elseif name == "BossVolley" and typeof(data.position) == "Vector3" then
			soundAtPoint(data.position, Theme.Sounds.lob, 0.8, 0.6, 200)
		elseif name == "BossCallIn" and typeof(data.position) == "Vector3" then
			blastRing(data.position, 8, Theme.Colors.red)
			UI.sound(Theme.Sounds.call, 0.7, 0.5)
		elseif name == "BossDown" and typeof(data.position) == "Vector3" then
			-- Half a second of slow-mo read: the lens pulls in and the color drains, then recovers.
			local existing = Lighting:FindFirstChild("GHSSlowMo")
			local cc = if existing and existing:IsA("ColorCorrectionEffect")
				then existing
				else Instance.new("ColorCorrectionEffect")
			cc.Name = "GHSSlowMo"
			cc.Parent = Lighting
			UI.tween(cc, { Saturation = -0.7, TintColor = Color3.fromRGB(255, 220, 210) }, 0.15)
			task.delay(tonumber(data.slowSec) or 0.5, function()
				UI.tween(cc, { Saturation = 0, TintColor = Theme.Colors.white }, 0.5)
			end)
			sparks(data.position + Vector3.new(0, 3, 0), Theme.Colors.red, 60, 40)
			blastRing(data.position, 18, Theme.Colors.red)
			if data.cash and tonumber(data.cash) > 0 then
				floatText(
					data.position + Vector3.new(0, 4, 0),
					"+" .. UI.fmtCash(tonumber(data.cash) or 0),
					Theme.Colors.cash,
					34,
					6,
					1.4
				)
			end
		elseif name == "Knockback" and typeof(data.dir) == "Vector3" then
			-- A Heavy's hit: this client owns its character's physics, so the throw is applied here.
			local char = Players.LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local studs = tonumber(data.studs) or 10
				local flat = Vector3.new(data.dir.X, 0, data.dir.Z)
				local dir = if flat.Magnitude > 0.05 then flat.Unit else Vector3.zAxis
				root.AssemblyLinearVelocity = dir * studs * 2.4 + Vector3.new(0, 12, 0)
				ClientState.Juice:Fire("Shake", { amp = 0.5, dur = 0.3 })
			end
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
			blastRing(data.position, data.radius or 5, data.color or Theme.Colors.gold)
			UI.sound(Theme.Sounds.crate, 1.2, 0.5)
		elseif name == "StructureHit" then
			UI.sound(Theme.Sounds.kill, 0.8, 0.08)
		elseif name == "StructureGone" then
			blastRing(data.position, 6, Theme.Colors.malus)
			UI.sound(Theme.Sounds.deny, 0.9, 0.15)
		elseif name == "AbilityBeam" then
			-- Heal turret beam (green) and flame turret stream (orange): a short line per tick.
			trail(data.from, data.to, data.color or Theme.Colors.gold, data.life or 0.2)
			if data.sound == "flame" then
				UI.sound(Theme.Sounds.swap, 0.6, 0.12)
			end
		elseif name == "Blast" then
			-- Claymore (red), flashbang (white) and a thrown fire landing (orange).
			blastRing(data.position, data.radius or 8, data.color or Theme.Colors.red)
			UI.sound(Theme.Sounds.crate, data.pitch or 1.5, 0.5)
			ClientState.Juice:Fire("Shake", { amp = data.shake or 0.15, dur = 0.15 })
		elseif name == "Heal" then
			-- Small, quiet green number over the healed player.
			floatText(data.position, "+" .. tostring(data.amount), Theme.Colors.health, 16, 2, 0.7)
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
