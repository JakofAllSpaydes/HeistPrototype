--!strict
-- The arms crate on the client (brief 5): a small `N ROLLS LEFT` tag over every crate, and the reel on a
-- billboard above the crate whenever anyone opens it. Everyone in the run sees the same reel (the server sends
-- the filler icons and the result in CrateRoll); timing comes from the shared CrateReel module so the icon
-- lands as the server ejects the gun. Ticks are 3D at the crate and pitch up; the land punches the card with the
-- rarity juice, rays from Epic up and the Legendary sting.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local CrateReel = require(Shared:WaitForChild("CrateReel"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local Juice = require(script.Parent:WaitForChild("Juice"))

local CrateReelUI = {}

local TAG = "GHSCrate"
local player = Players.LocalPlayer

type CrateTag = { gui: BillboardGui, rolls: TextLabel, timer: TextLabel }
local tags: { [Model]: CrateTag } = {}

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

local function refreshTag(model: Model, tag: CrateTag)
	local rolls = tonumber(model:GetAttribute("RollsLeft")) or 0
	local busy = model:GetAttribute("Busy") == true
	local landed = model:GetAttribute("Landed") == true
	tag.rolls.Text = string.format("%d ROLL%s LEFT", rolls, if rolls == 1 then "" else "S")
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
	-- Pixel sized so it reads at any distance, small enough to stay out of the way (half again on a phone).
	local mult = if ClientState.isMobile then 1.5 else 1
	local function S(n: number): number
		return UI.S(n * mult)
	end
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
	local rolls = UI.text({
		Text = "",
		Font = Theme.Fonts.display,
		TextSize = S(15),
		TextColor3 = Theme.Colors.gold,
		Size = UDim2.fromScale(1, 1),
		Parent = pill,
	})
	local tag: CrateTag = { gui = gui, rolls = rolls, timer = timer }
	tags[model] = tag
	refreshTag(model, tag)
	model.AttributeChanged:Connect(function(attr)
		if tags[model] then
			refreshTag(model, tag)
			if attr == "RollsLeft" then
				UI.punch(pill, 1.15, 0.25)
			end
		end
	end)
end

-- Ray burst inside a billboard (the screen-space Juice.rays cannot follow a world point).
local function rays(parent: Instance, color: Color3, count: number, size: number)
	local holder = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(2, 2),
		ZIndex = 0,
		Parent = parent,
	})
	for i = 1, count do
		local ray = UI.frame({
			BackgroundColor3 = color,
			BackgroundTransparency = 0.2,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(UI.S(10), size),
			Rotation = (i - 1) * (360 / count),
			ZIndex = 0,
			Parent = holder,
		})
		UI.tween(ray, { BackgroundTransparency = 1, Size = UDim2.fromOffset(UI.S(3), size * 1.6) }, 0.9)
	end
	UI.tween(holder, { Rotation = 40 }, 0.9)
	task.delay(1, function()
		holder:Destroy()
	end)
end

local function playReel(data: any)
	local model = crateById(tostring(data.crateId))
	local body = model and bodyOf(model)
	if not body then
		return
	end
	local reel = data.reel
	if typeof(reel) ~= "table" or #reel == 0 then
		return
	end
	local S = UI.S
	local mobile = ClientState.isMobile
	-- Phones render UI.S at about half scale: the reel card is sized up there so it reads across the arena.
	local cardPx = S(if mobile then 160 else 110)
	local gui = Instance.new("BillboardGui")
	gui.Name = "CrateReel"
	gui.Adornee = body
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(cardPx * 2.4, cardPx * 2.2)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 6.5, 0)
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	gui.ClipsDescendants = false
	gui.Parent = body

	local card = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(cardPx, cardPx),
		ZIndex = 2,
		Parent = gui,
	})
	UI.corner(card, S(12))
	local stroke = UI.stroke(card, Theme.Colors.grey, S(3))
	local icon = UI.gunIcon(card, Theme.Colors.grey, math.floor(cardPx * 0.8))
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 3
	for _, c in icon:GetChildren() do
		if c:IsA("GuiObject") then
			c.ZIndex = 3
		end
	end
	local name = UI.text({
		Text = "",
		Font = Theme.Fonts.display,
		TextSize = S(if mobile then 24 else 16),
		TextColor3 = Theme.Colors.text,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.42, cardPx / 2 + S(4)),
		Size = UDim2.new(1, 0, 0, S(20)),
		ZIndex = 3,
		Parent = gui,
	})
	UI.stroke(name, Theme.Colors.black, 2, 0.2)
	card.Size = UDim2.fromOffset(0, 0)
	UI.tween(card, { Size = UDim2.fromOffset(cardPx, cardPx) }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	local steps = CrateReel.steps()
	local n = math.min(#steps, #reel)
	local mine = data.by == player.UserId
	for i = 1, n do
		if not gui.Parent then
			return
		end
		local entry = reel[i]
		local rarity = tonumber(entry.rarity) or 1
		local color = Rarity.color(rarity)
		local last = i == n
		stroke.Color = color
		stroke.Transparency = if last then 0 else 0.3
		UI.recolorIcon(icon, color)
		name.Text = string.upper(tostring(entry.name or ""))
		name.TextColor3 = if last then color else Theme.Colors.textDim
		if last then
			local j = Juice.tier(rarity)
			UI.punch(card, j.punch + 0.15, 0.4)
			UI.punch(name, 1.25, 0.35)
			stroke.Thickness = S(7)
			UI.tween(stroke, { Thickness = S(3) }, 0.5)
			soundOn(body, Theme.Sounds.reelLand, j.pitch, j.volume)
			if j.rays then
				rays(gui, color, j.rayCount, cardPx * (0.75 + j.tier * 0.12))
			end
			if mine then
				-- Shake / flash / the Legendary sting for the one who opened it.
				Juice.burst(rarity, color, nil)
			elseif j.tier == 5 then
				soundOn(body, Theme.Sounds.legendary, 1, 0.7)
			end
			task.wait(Config.CrateLandHoldSec)
		else
			UI.punch(card, 1.08, 0.12)
			soundOn(body, Theme.Sounds.reelTick, 0.8 + (i / n) * 1.0, 0.5)
			task.wait(steps[i])
		end
	end
	-- Eject: the card drops into the crate as the gun flies out.
	if gui.Parent then
		UI.tween(card, { Size = UDim2.fromOffset(0, 0), Position = UDim2.fromScale(0.5, 0.9) }, 0.25)
		UI.tween(name, { TextTransparency = 1 }, 0.2)
		soundOn(body, Theme.Sounds.swap, 0.8, 0.5)
		task.delay(0.3, function()
			gui:Destroy()
		end)
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
		if name == "CrateRoll" and typeof(data) == "table" then
			task.spawn(playReel, data)
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
