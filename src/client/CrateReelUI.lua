--!strict
-- The gun crate on the client (brief 5, Round 15b): a `GUN CRATE` tag with its countdown over every closed crate,
-- and the reel when anyone opens it. The reel is the original weapon reel (a row of gun icons in rarity frames
-- sliding under a gold marker, ease-out onto the landed gun, ticks pitching up, the result line with DMG and RATE,
-- the rarity juice on land), drawn on a billboard over the crate so the whole run sees it. One F plays every roll
-- the crate holds back to back (the server sends a CrateRoll per roll; timing in CrateReel).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Weapons = require(Shared:WaitForChild("Weapons"))
local CrateReel = require(Shared:WaitForChild("CrateReel"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local Juice = require(script.Parent:WaitForChild("Juice"))

local CrateReelUI = {}

local TAG = "GHSCrate"
local player = Players.LocalPlayer

type CrateTag = { gui: BillboardGui, label: TextLabel, timer: TextLabel }
local tags: { [Model]: CrateTag } = {}

-- Phones render UI.S at about half scale: world billboards are sized up there so they read across the arena.
local function SS(n: number): number
	return UI.S(n * (if ClientState.isMobile then 1.5 else 1))
end

local function bodyOf(model: Model): BasePart?
	return model:FindFirstChild("Body") :: BasePart?
end

local function crateById(id: string): Model?
	for _, m in CollectionService:GetTagged(TAG) do
		if m:IsA("Model") and m:GetAttribute("CrateId") == id then
			return m
		end
	end
	return nil
end

-- 3D sound on the crate so a teammate's roll sounds like it comes from over there.
local function soundOn(part: BasePart, id: string, pitch: number, volume: number)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.PlaybackSpeed = pitch
	s.Volume = volume
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 10
	s.RollOffMaxDistance = 140
	s.Parent = part
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(6, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

------------------------------------------------------------------ The GUN CRATE tag
local function refreshTag(model: Model, tag: CrateTag)
	local busy = model:GetAttribute("Busy") == true
	local landed = model:GetAttribute("Landed") == true
	local rolls = tonumber(model:GetAttribute("RollsLeft")) or 0
	-- The reel takes the space over the crate while it plays.
	tag.gui.Enabled = landed and not busy and rolls > 0
end

local function addTag(model: Instance)
	if not model:IsA("Model") or tags[model] then
		return
	end
	local body = bodyOf(model) or model:WaitForChild("Body", 5) :: BasePart?
	if not body then
		return
	end
	local S = SS
	local gui = Instance.new("BillboardGui")
	gui.Name = "CrateTag"
	gui.Adornee = body
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(S(150), S(46))
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.Enabled = false
	gui.Parent = body
	local timer = UI.text({
		Text = "",
		Font = Theme.Fonts.display,
		TextSize = S(12),
		TextColor3 = Theme.Colors.grey,
		Size = UDim2.new(1, 0, 0, S(14)),
		Parent = gui,
	})
	UI.stroke(timer, Theme.Colors.black, 1.5, 0.3)
	local pill = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(16)),
		Size = UDim2.fromOffset(S(130), S(26)),
		Parent = gui,
	})
	UI.corner(pill, S(13))
	UI.stroke(pill, Theme.Colors.gold, S(2))
	local label = UI.text({
		Text = "GUN CRATE",
		Font = Theme.Fonts.display,
		TextSize = S(15),
		TextColor3 = Theme.Colors.gold,
		Size = UDim2.fromScale(1, 1),
		Parent = pill,
	})
	local tag: CrateTag = { gui = gui, label = label, timer = timer }
	tags[model] = tag
	refreshTag(model, tag)
	model.AttributeChanged:Connect(function()
		if tags[model] then
			refreshTag(model, tag)
		end
	end)
end

------------------------------------------------------------------ The reel (the original weapon reel, on the crate)
local CELLS = CrateReel.Cells
local LAND = CrateReel.Land

local function playReel(data: any)
	local model = crateById(tostring(data.crateId))
	local body = model and bodyOf(model)
	if not body then
		return
	end
	local function S(n: number): number
		return SS(n * Config.CrateReelScale)
	end
	local w = S(340)
	local h = S(128)
	local gui = Instance.new("BillboardGui")
	gui.Name = "CrateReel"
	gui.Adornee = body
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(w + S(160), h + S(160)) -- room for the rays round the panel
	gui.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	gui.ClipsDescendants = false
	gui.Parent = body

	local panel = UI.frame({
		Name = "ReelPanel",
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(w, h),
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = gui,
	})
	UI.corner(panel, S(14))
	local stroke = UI.stroke(panel, Theme.Colors.grey, S(3))
	local title = UI.text({
		Text = "GUN CRATE",
		Font = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Theme.Colors.grey,
		Size = UDim2.new(1, 0, 0, S(22)),
		Position = UDim2.fromOffset(0, S(4)),
		ZIndex = 3,
		Parent = panel,
	})
	local stripW = w - S(20)
	local stripH = S(66)
	local strip = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		Position = UDim2.fromOffset(S(10), S(28)),
		Size = UDim2.fromOffset(stripW, stripH),
		ClipsDescendants = true,
		ZIndex = 3,
		Parent = panel,
	})
	UI.corner(strip, S(10))
	local cellW = S(72)
	local row = UI.frame({
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(cellW * CELLS, stripH),
		ZIndex = 3,
		Parent = strip,
	})
	local marker = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(cellW, stripH),
		ZIndex = 5,
		Parent = strip,
	})
	UI.corner(marker, S(8))
	local markerStroke = UI.stroke(marker, Theme.Colors.gold, S(2), 0.3)
	for _, y in { 0, 1 } do
		local tick = UI.frame({
			BackgroundColor3 = Theme.Colors.gold,
			AnchorPoint = Vector2.new(0.5, y),
			Position = UDim2.new(0.5, 0, y, 0),
			Size = UDim2.fromOffset(S(4), S(8)),
			ZIndex = 6,
			Parent = strip,
		})
		UI.corner(tick, S(2))
	end
	local result = UI.text({
		Text = "ROLLING",
		Font = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.text,
		Size = UDim2.new(1, 0, 0, S(26)),
		Position = UDim2.fromOffset(0, S(98)),
		ZIndex = 3,
		Parent = panel,
	})

	-- The row: random rarities, the landed gun at LAND.
	local rarity = tonumber(data.rarity) or 1
	local fillers = data.fillers or {}
	for i = 1, CELLS do
		local isLast = i == LAND
		local r = if isLast then rarity else (tonumber(fillers[i]) or math.random(1, 5))
		local color = Rarity.color(r)
		local cell = UI.frame({
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset((i - 1) * cellW, 0),
			Size = UDim2.fromOffset(cellW, stripH),
			ZIndex = 4,
			Parent = row,
		})
		local frame = UI.frame({
			BackgroundColor3 = Theme.Colors.panel2,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -S(8), 1, -S(10)),
			ZIndex = 4,
			Parent = cell,
		})
		UI.corner(frame, S(8))
		UI.stroke(frame, color, S(2), if isLast then 0 else 0.4)
		local icon = UI.gunIcon(frame, color, math.floor(stripH * 0.72))
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		for _, c in icon:GetChildren() do
			if c:IsA("GuiObject") then
				c.ZIndex = 4
				if not isLast and c:IsA("Frame") then
					c.BackgroundTransparency = 0.3
				end
			end
		end
	end
	panel.Size = UDim2.fromOffset(w, 0)
	UI.tween(panel, { Size = UDim2.fromOffset(w, h) }, 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	-- Slide so the landed cell ends under the marker.
	local startX = stripW / 2 - cellW / 2
	local endX = stripW / 2 - (LAND - 0.5) * cellW
	row.Position = UDim2.fromOffset(startX, 0)
	local tween = UI.tween(
		row,
		{ Position = UDim2.fromOffset(endX, 0) },
		Config.RollDurationSec,
		Enum.EasingStyle.Quart,
		Enum.EasingDirection.Out
	)
	local lastIdx = 0
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		if not row.Parent then
			conn:Disconnect()
			return
		end
		local idx = math.floor((stripW / 2 - row.Position.X.Offset) / cellW + 0.5)
		if idx > lastIdx then
			lastIdx = idx
			soundOn(body, Theme.Sounds.reelTick, 0.7 + (idx / LAND) * 1.1, 0.45)
			UI.punch(marker, 1.06, 0.1)
		end
	end)
	tween.Completed:Wait()
	conn:Disconnect()
	if not panel.Parent then
		return
	end

	-- Land: the rarity color, the name with DMG and RATE, the juice.
	local color = Rarity.color(rarity)
	stroke.Color = color
	markerStroke.Color = color
	markerStroke.Transparency = 0
	title.Text = string.upper(tostring(data.rarityName or Rarity.name(rarity)))
	title.TextColor3 = color
	local w0 = Weapons.ById[tostring(data.weaponId)]
	local rate = if w0
		then Weapons.effectiveRate(w0, ClientState.rateMult() * (tonumber(data.levelRateMult) or 1))
		else 0
	result.Text = string.format(
		"%s  ·  DMG %s  ·  %s",
		string.upper(tostring(data.displayName or "")),
		UI.fmtDmg(tonumber(data.dmg) or 0, tonumber(data.pellets) or 1),
		UI.fmtRate(rate)
	)
	result.TextColor3 = color
	local j = Juice.tier(rarity)
	UI.punch(panel, j.punch, 0.35)
	UI.punch(result, 1.2 + j.tier * 0.08, 0.4)
	soundOn(body, Theme.Sounds.reelLand, j.pitch, j.volume)
	if j.tier >= 4 then
		stroke.Thickness = S(6)
		UI.tween(stroke, { Thickness = S(3) }, 0.5)
	end
	if j.rays then
		-- Rays behind the panel, inside the billboard (the screen rays cannot follow a world point).
		local holder = UI.frame({
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(2, 2),
			ZIndex = 1,
			Parent = gui,
		})
		for i = 1, j.rayCount do
			local ray = UI.frame({
				BackgroundColor3 = color,
				BackgroundTransparency = 0.25,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(S(14), S(j.raySize * 0.6)),
				Rotation = (i - 1) * (360 / j.rayCount),
				ZIndex = 1,
				Parent = holder,
			})
			UI.tween(ray, { BackgroundTransparency = 1, Size = UDim2.fromOffset(S(4), S(j.raySize)) }, 0.6)
		end
		UI.tween(holder, { Rotation = 35 }, 0.6)
		task.delay(0.65, function()
			holder:Destroy()
		end)
	end
	if data.by == player.UserId then
		Juice.burst(rarity, color, nil) -- shake / flash / the Legendary sting for the one who opened it
	elseif j.tier == 5 then
		soundOn(body, Theme.Sounds.legendary, 1, 0.7)
	end
	task.wait(CrateReel.ejectSec(rarity) - Config.RollDurationSec)

	-- Eject: the panel closes as the gun flies out of the crate.
	soundOn(body, Theme.Sounds.swap, 0.8, 0.5)
	local close = UI.tween(
		panel,
		{ Size = UDim2.fromOffset(w, 0) },
		Config.RollEjectSec,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	close.Completed:Wait()
	gui:Destroy()
end

------------------------------------------------------------------ Open / eject juice
-- Opening: a gold burst out of the lid, a floor ring, a light flash, a shake that fades with distance and the crate
-- thump. Each gun: a burst and ring in its rarity color (Epic and up bigger, with a column of light), a kick of the
-- lid (server) and the whoosh.

local function fxFolder(): Instance
	return Workspace:FindFirstChild("Effects") or Workspace
end

-- Shake that fades with distance from the crate.
local function nearShake(position: Vector3, amp: number, dur: number)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local k = 1 - math.clamp((root.Position - position).Magnitude / math.max(Config.CrateFxRange, 1), 0, 1)
	if k > 0.05 then
		ClientState.Juice:Fire("Shake", { amp = amp * k, dur = dur })
	end
end

-- A burst of glowing chips and a light flash at a point.
local function burst(position: Vector3, color: Color3, count: number, speed: number, light: number)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = CFrame.new(position)
	p.Parent = fxFolder()
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.35, 0.8)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(70, 70)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(0, -35, 0)
	e.Drag = 2
	e.Parent = p
	e:Emit(count)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = 16
	l.Brightness = light
	l.Parent = p
	TweenService:Create(l, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 })
		:Play()
	task.delay(1.2, function()
		p:Destroy()
	end)
end

-- A ring that rushes out along the floor.
local function floorRing(position: Vector3, color: Color3, size: number)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Size = Vector3.new(0.15, 2, 2)
	ring.CFrame = CFrame.new(position.X, Config.FloorTop + 0.15, position.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.2
	ring.Parent = fxFolder()
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, size, size),
		Transparency = 1,
	}):Play()
	task.delay(0.5, function()
		ring:Destroy()
	end)
end

-- Epic and up: a column of light shoots up out of the crate.
local function pillar(position: Vector3, color: Color3)
	local col = Instance.new("Part")
	col.Shape = Enum.PartType.Cylinder
	col.Anchored = true
	col.CanCollide = false
	col.CanQuery = false
	col.CanTouch = false
	col.Size = Vector3.new(1, 2.2, 2.2)
	col.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	col.Color = color
	col.Material = Enum.Material.Neon
	col.Transparency = 0.25
	col.Parent = fxFolder()
	TweenService:Create(col, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(26, 0.6, 0.6),
		CFrame = CFrame.new(position + Vector3.new(0, 13, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Transparency = 1,
	}):Play()
	task.delay(0.65, function()
		col:Destroy()
	end)
end

local function onOpened(data: any)
	local pos = data.position
	if typeof(pos) ~= "Vector3" then
		return
	end
	local model = crateById(tostring(data.crateId))
	local body = model and bodyOf(model)
	local gold = Theme.Colors.gold
	burst(pos, gold, 40, 26, 6)
	floorRing(pos, gold, 20)
	nearShake(pos, Config.CrateOpenShake, 0.3)
	if body then
		soundOn(body, Theme.Sounds.crate, 1.1, 0.8)
		soundOn(body, Theme.Sounds.reelLand, 0.7, 0.6)
	end
	if data.by == player.UserId then
		ClientState.Juice:Fire("RarityFlash", { color = gold, alpha = 0.15 })
	end
end

local function onEject(data: any)
	local pos = data.position
	if typeof(pos) ~= "Vector3" then
		return
	end
	local rarity = tonumber(data.rarity) or 1
	local color = Rarity.color(rarity)
	local high = rarity >= 4
	burst(pos, color, if high then 45 else 22, if high then 30 else 20, if high then 8 else 4)
	floorRing(pos, color, if high then 18 else 11)
	if high then
		pillar(pos, color)
	end
	nearShake(pos, Config.CrateEjectShake * (if high then 2 else 1), 0.2)
	local model = crateById(tostring(data.crateId))
	local body = model and bodyOf(model)
	if body then
		soundOn(body, Theme.Sounds.swap, 0.9 + rarity * 0.08, 0.7)
		soundOn(body, Theme.Sounds.take, 0.8 + rarity * 0.1, 0.5)
	end
end

function CrateReelUI.init()
	for _, m in CollectionService:GetTagged(TAG) do
		task.spawn(addTag, m)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(m)
		task.spawn(addTag, m)
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(m)
		if m:IsA("Model") then
			tags[m] = nil
		end
	end)
	ClientState.Juice:Connect(function(name: string, data: any)
		if typeof(data) ~= "table" then
			return
		end
		if name == "CrateRoll" then
			task.spawn(playReel, data)
		elseif name == "CrateOpened" then
			onOpened(data)
		elseif name == "CrateEject" then
			onEject(data)
		end
	end)
	-- Crate lifetime countdown above the tag.
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		local now = ClientState.serverNow()
		for model, tag in tags do
			if not model.Parent then
				tags[model] = nil
				continue
			end
			local endsAt = tonumber(model:GetAttribute("EndsAt")) or 0
			local remaining = math.max(0, endsAt - now)
			tag.timer.Text = string.format("%ds", math.ceil(remaining))
			tag.timer.TextColor3 = if remaining < 10 then Theme.Colors.malus else Theme.Colors.grey
		end
	end)
end

return CrateReelUI
