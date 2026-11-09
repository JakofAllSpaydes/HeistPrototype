--!strict
-- Brief 13: a relic coming out of a gun crate, the same for the whole crew. After the guns: the mask rises out of
-- the crate on a vertical light beam in the relic colour (the beam reads through walls for the whole show), hangs
-- RelicHangSec at head height spinning with rays while the sting plays for everyone wherever they are, then flies
-- to the camera and the RELIC FOUND card drops in with the mastery card's framing: the stamp, the mask spinning,
-- THE TELLER · THE BANK and under it UNLOCKED or ALREADY OWNED · +500 G. The card interrupts (it never queues) and
-- holds RelicPopupSec. A beat on a pad.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Lines = require(Shared:WaitForChild("CrewCall"):WaitForChild("Lines"))

local Client = script.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ModelIcon = require(Client:WaitForChild("UI"):WaitForChild("ModelIcon"))
local Models = require(Client:WaitForChild("Store"):WaitForChild("Models"))
local Haptics = require(Client:WaitForChild("Haptics"))

local RelicShow = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local RELIC = Rarity.color(Rarity.Relic)

local function sting()
	if Config.RelicSting == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = Config.RelicSting
	s.Volume = Config.RelicStingVolume
	s.SoundGroup = UI.soundGroup("SFX")
	s.Parent = SoundService
	s:Play()
	task.delay(12, function()
		s:Destroy()
	end)
end

-- A burst of light rays round a world point (a billboard: on top of the world, like the reel's rays).
local function rays(att: Attachment): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "RelicRays"
	gui.Adornee = att
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(UI.S(300), UI.S(300))
	gui.Parent = att
	local spin = UI.frame({
		Name = "Spin",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	for i = 1, 10 do
		-- A GuiObject turns about its own centre, so each ray sits in a full-size holder turned about the burst's.
		local holder = UI.frame({
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Rotation = (i - 1) * 36,
			Parent = spin,
		})
		local ray = UI.frame({
			BackgroundColor3 = RELIC,
			BackgroundTransparency = 0.72,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, UI.S(if i % 2 == 0 then 10 else 6), 0.5, 0),
			Parent = holder,
		})
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new(1, 0)
		g.Parent = ray
	end
	return gui
end

------------------------------------------------------------------ The card
local gui: ScreenGui? = nil
local cardToken = 0

local function ensureGui(): ScreenGui
	local g = gui
	if g and g.Parent then
		return g
	end
	local s = UI.new("ScreenGui", {
		Name = "RelicFound",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 41, -- over the mastery card: a relic interrupts, it never waits in a queue
		Parent = playerGui,
	}) :: ScreenGui
	gui = s
	return s
end

local function card(d: any)
	cardToken += 1
	local token = cardToken
	local g = ensureGui()
	for _, c in g:GetChildren() do
		c:Destroy()
	end
	local S = UI.S
	local mobile = ClientState.isMobile
	local W, H = S(if mobile then 340 else 420), S(if mobile then 92 else 104)
	local frame = UI.frame({
		Name = "Card",
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.05,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -H - S(20)),
		Size = UDim2.fromOffset(W, H),
		ClipsDescendants = false,
		Parent = g,
	})
	UI.corner(frame, S(14))
	local stroke = UI.stroke(frame, RELIC, S(3))
	local edge = UI.frame({ BackgroundColor3 = RELIC, Size = UDim2.new(0, S(6), 1, 0), Parent = frame })
	UI.corner(edge, S(3))
	local shineClip = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		Parent = frame,
	})
	UI.corner(shineClip, S(14))
	local shine = UI.frame({
		BackgroundColor3 = Theme.Colors.white,
		BackgroundTransparency = 0.8,
		Position = UDim2.new(0, -S(60), 0, 0),
		Size = UDim2.new(0, S(40), 1, 0),
		Rotation = 12,
		Parent = shineClip,
	})
	-- The mask, spinning, over a ring in the relic colour.
	local ring = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, H * 0.62, 0.5, 0),
		Size = UDim2.fromOffset(H * 1.1, H * 1.1),
		Parent = frame,
	})
	UI.corner(ring, H)
	UI.stroke(ring, RELIC, S(3))
	local icon = ModelIcon.mask(ring, tostring(d.id), UDim2.fromScale(0.95, 0.95), { motion = "always" })
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	local textX = H * 1.3
	UI.text({
		Text = Lines.relic.stamp,
		FontFace = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = RELIC,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(textX, S(8)),
		Size = UDim2.new(1, -textX - S(10), 0, S(16)),
		Parent = frame,
	})
	local title = UI.text({
		Text = string.format("%s · %s", tostring(d.name or ""), tostring(d.mapName or "")),
		FontFace = Theme.Fonts.display,
		TextSize = S(if mobile then 19 else 23),
		TextColor3 = Theme.Colors.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(textX, S(26)),
		Size = UDim2.new(1, -textX - S(10), 0, S(28)),
		Parent = frame,
	})
	local mine = typeof(d.results) == "table" and d.results[tostring(player.UserId)] or "unlocked"
	UI.text({
		Text = if mine == "dupe"
			then string.format(Lines.relic.dupe, tonumber(d.dupeGold) or Config.RelicDupeGold)
			else Lines.relic.unlocked,
		FontFace = Theme.Fonts.display,
		TextSize = S(17),
		TextColor3 = if mine == "dupe" then Theme.Colors.gold else Theme.Colors.cash,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(textX, S(58)),
		Size = UDim2.new(1, -textX - S(10), 0, S(22)),
		Parent = frame,
	})
	if d.starter then
		UI.text({
			Text = Lines.relic.firstCrate,
			FontFace = Theme.Fonts.display,
			TextSize = S(11),
			TextColor3 = Theme.Colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(textX, S(80)),
			Size = UDim2.new(1, -textX - S(10), 0, S(14)),
			Parent = frame,
		})
	end
	local y = S(if mobile then 70 else 96)
	UI.tween(frame, { Position = UDim2.new(0.5, 0, 0, y) }, 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	UI.punch(ring, 1.6, 0.5)
	UI.punch(title, 1.15, 0.4)
	UI.tween(
		shine,
		{ Position = UDim2.new(1, S(20), 0, 0) },
		0.7,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out,
		0.25
	)
	UI.sound(Theme.Sounds.legendary, 0.9, 0.7)
	ClientState.Juice:Fire("RarityFlash", { color = RELIC, alpha = 0.25 })
	ClientState.Juice:Fire("Shake", { amp = 0.2, dur = 0.25 })
	stroke.Thickness = S(8)
	UI.tween(stroke, { Thickness = S(3) }, 0.6)
	task.delay(tonumber(d.popupSec) or Config.RelicPopupSec, function()
		if token ~= cardToken or not frame.Parent then
			return
		end
		local out = UI.tween(
			frame,
			{ Position = UDim2.new(0.5, 0, 0, -H - S(20)) },
			0.3,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		out.Completed:Wait()
		frame:Destroy()
	end)
end

------------------------------------------------------------------ The world show
local function show(d: any)
	local at = d.position
	if typeof(at) ~= "Vector3" then
		card(d)
		return
	end
	local rise = tonumber(d.riseSec) or Config.RelicRiseSec
	local hang = tonumber(d.hangSec) or Config.RelicHangSec
	local folder = Instance.new("Folder")
	folder.Name = "RelicShow"
	folder.Parent = Workspace.CurrentCamera or Workspace
	-- The beam: a tall column in the relic colour, outlined on top of everything so it reads through walls.
	local beam = Instance.new("Part")
	beam.Name = "RelicBeam"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Shape = Enum.PartType.Cylinder
	beam.Material = Enum.Material.Neon
	beam.Color = RELIC
	beam.Transparency = 0.35
	beam.Size = Vector3.new(80, 1.6, 1.6)
	beam.CFrame = CFrame.new(at + Vector3.new(0, 40, 0)) * CFrame.Angles(0, 0, math.rad(90))
	beam.Parent = folder
	local glow = Instance.new("Highlight")
	glow.Adornee = beam
	glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	glow.FillColor = RELIC
	glow.FillTransparency = 0.45
	glow.OutlineTransparency = 1
	glow.Parent = folder
	local light = Instance.new("PointLight")
	light.Color = RELIC
	light.Range = 24
	light.Brightness = 3
	light.Parent = beam
	-- The mask on its bust, big, rising out of the crate.
	local model = Models.maskBust(tostring(d.id))
	model:ScaleTo(2.4)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
		end
	end
	model.Parent = folder
	local att = Instance.new("Attachment")
	att.Parent = Workspace.Terrain
	local rayGui = rays(att)
	rayGui.Enabled = false
	sting()
	Haptics.pulse(Config.HapticRelic) -- a beat on a pad
	local t0 = os.clock()
	local low, high = at + Vector3.new(0, 0.5, 0), at + Vector3.new(0, 5.5, 0)
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - t0
		local h = math.clamp(t / math.max(rise, 0.05), 0, 1)
		local e = 1 - (1 - h) ^ 3
		local pos = low:Lerp(high, e) + Vector3.new(0, math.sin(t * 2.2) * 0.25 * h, 0)
		model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, t * 2.4, 0))
		att.WorldPosition = pos
		if h >= 1 and not rayGui.Enabled then
			rayGui.Enabled = true
			UI.punch(rayGui:FindFirstChild("Spin") :: Frame, 1.4, 0.35)
		end
		local spin = rayGui:FindFirstChild("Spin") :: Frame?
		if spin then
			spin.Rotation = (spin.Rotation + dt * 40) % 360
		end
	end)
	task.delay(rise + hang, function()
		conn:Disconnect()
		rayGui.Enabled = false
		-- Off it goes, toward the camera, and the card takes over.
		local cam = Workspace.CurrentCamera
		local from = model:GetPivot()
		local t1 = os.clock()
		local fly: RBXScriptConnection
		fly = RunService.RenderStepped:Connect(function()
			local k = math.clamp((os.clock() - t1) / 0.35, 0, 1)
			local to = if cam then cam.CFrame * CFrame.new(0, 0, -3) else from
			model:PivotTo(from:Lerp(to, k * k))
			beam.Transparency = 0.35 + 0.65 * k
			if k >= 1 then
				fly:Disconnect()
				folder:Destroy()
				att:Destroy()
			end
		end)
		card(d)
	end)
end

function RelicShow.init()
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "RelicFound" and typeof(data) == "table" then
			task.spawn(show, data)
		end
	end)
end

return RelicShow
