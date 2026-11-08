--!strict
-- The hub nameplate over every character (yours too, Config.NameplateShowSelf). Left to right: the level badge
-- (the level card's emblem, chevron over the level number, so no "LV" text) overlapping the plate's left end;
-- the name in condensed caps with a gold VIP tag, the best top wave and its map under it (★ WAVE 14 · BANK); and a
-- solid class-coloured block with the class pictogram on the right end. The plate is near-black with a class-tinted
-- gradient from the left and a class-coloured underline that fades out to the right.
-- The server publishes the numbers as Player attributes (Hub.refreshTag: Plate, PlateLevel, PlateTop, PlateMap,
-- PlateClass, PlateVip); this module draws them. The Roblox name over a plated character hides locally (the plate
-- carries the name) and comes back when the plate goes (runs).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Classes = require(Shared:WaitForChild("Classes"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local Icons = require(script.Parent:WaitForChild("UI"):WaitForChild("Icons"))

local Nameplates = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- The level card's emblem colours (HUD/LevelCard.lua), so the badge reads as the same profile badge.
local EMBLEM = Color3.fromRGB(205, 208, 214)
local EMBLEM_DARK = Color3.fromRGB(42, 42, 48)
local VIP = Color3.fromHex("F2C14E")
local PLATE = Color3.fromHex("0B0B0F")
local BOLD = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
local MEDIUM = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Medium)

type Plate = { gui: BillboardGui, humanoid: Humanoid?, savedDisplay: Enum.HumanoidDisplayDistanceType? }

local plates: { [Player]: Plate } = {}
local lastLevel: { [Player]: number } = {}
local pending: { [Player]: boolean } = {}
local localHidden = false

local function text(props: { [string]: any }, font: Font): TextLabel
	local label = UI.text(props)
	label.FontFace = font
	return label
end

local function gradient(parent: Instance, colors: ColorSequence, rotation: number, transparency: NumberSequence?)
	local g = Instance.new("UIGradient")
	g.Color = colors
	g.Rotation = rotation
	if transparency then
		g.Transparency = transparency
	end
	g.Parent = parent
end

-- The emblem with the level in it: a light square (tight corners), a dark chevron on top, the number under it.
local function badge(parent: Instance, level: number, size: number): Frame
	local b = UI.frame({
		Name = "Badge",
		BackgroundColor3 = Theme.Colors.white,
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = 1,
		ZIndex = 5,
		Parent = parent,
	})
	UI.corner(b, math.floor(size * 0.14))
	UI.stroke(b, EMBLEM_DARK, math.max(2, size * 0.06), 0)
	gradient(b, ColorSequence.new(Color3.fromRGB(236, 238, 242), EMBLEM:Lerp(EMBLEM_DARK, 0.18)), 90)
	for _, side in { -1, 1 } do
		local bar = UI.frame({
			BackgroundColor3 = EMBLEM_DARK,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, side * size * 0.12, 0.24, 0),
			Size = UDim2.fromOffset(math.floor(size * 0.3), math.max(2, math.floor(size * 0.09))),
			Rotation = side * 30,
			ZIndex = 6,
			Parent = b,
		})
		UI.corner(bar, math.max(1, math.floor(size * 0.03)))
	end
	local s = tostring(level)
	text({
		Name = "Level",
		Text = s,
		TextSize = math.floor(size * (if #s >= 3 then 0.44 else 0.56)),
		TextColor3 = EMBLEM_DARK,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.64),
		Size = UDim2.fromScale(1, 0.6),
		ZIndex = 6,
		Parent = b,
	}, BOLD)
	return b
end

local function row(parent: Instance, order: number, height: number): Frame
	local r = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, height),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order,
		ZIndex = 3,
		Parent = parent,
	})
	UI.list(r, Enum.FillDirection.Horizontal, UI.S(6), nil, Enum.VerticalAlignment.Center)
	return r
end

local function remove(p: Player)
	local plate = plates[p]
	if not plate then
		return
	end
	plates[p] = nil
	local hum = plate.humanoid
	if hum and hum.Parent and plate.savedDisplay then
		hum.DisplayDistanceType = plate.savedDisplay
	end
	plate.gui:Destroy()
end

local function build(p: Player, head: BasePart): Plate
	local S = UI.S
	local level = math.max(1, math.floor(tonumber(p:GetAttribute("PlateLevel")) or 1))
	local top = tonumber(p:GetAttribute("PlateTop")) or 0
	local map = tostring(p:GetAttribute("PlateMap") or "")
	local class = Classes.ById[tostring(p:GetAttribute("PlateClass"))] or Classes.ById[Classes.Default]
	local classColor = Color3.fromHex(class.color)

	local H = S(Config.NameplateHeight)
	local badgeSize = math.floor(H * 1.3)
	local overlap = math.floor(badgeSize * 0.35) -- how far the badge sits over the plate's left end
	local radius = S(3)

	local gui = Instance.new("BillboardGui")
	gui.Name = "Nameplate_" .. p.UserId
	gui.Adornee = head
	gui.AlwaysOnTop = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Size = UDim2.fromOffset(S(460), badgeSize + S(6))
	gui.StudsOffset = Vector3.new(0, Config.NameplateOffset, 0)
	gui.MaxDistance = Config.NameplateMaxDistance
	gui.LightInfluence = 0
	gui.Enabled = not (p == player and localHidden)

	-- Badge and plate side by side, the badge pulled over the plate's end; the pair is centred over the head.
	local root = UI.frame({
		Name = "Root",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, badgeSize),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = gui,
	})
	UI.list(root, Enum.FillDirection.Horizontal, -overlap, nil, Enum.VerticalAlignment.Center)
	local b = badge(root, level, badgeSize)

	local holder = UI.frame({
		Name = "Holder",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, H),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		ZIndex = 1,
		Parent = root,
	})
	local plate = UI.frame({
		Name = "Plate",
		BackgroundColor3 = Theme.Colors.white,
		BackgroundTransparency = 0.1,
		Size = UDim2.fromOffset(0, H),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 1,
		Parent = holder,
	})
	UI.corner(plate, radius)
	UI.stroke(plate, Theme.Colors.white, S(1), 0.86)
	gradient(
		plate,
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, classColor:Lerp(PLATE, 0.72)),
			ColorSequenceKeypoint.new(0.45, PLATE),
			ColorSequenceKeypoint.new(1, PLATE),
		}),
		0
	)
	UI.pad(plate, overlap + S(10), 0, 0, 0)
	UI.list(plate, Enum.FillDirection.Horizontal, S(14), nil, Enum.VerticalAlignment.Center)
	-- The class-coloured underline, fading out to the right.
	local line = UI.frame({
		Name = "Accent",
		BackgroundColor3 = classColor,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, S(2)),
		ZIndex = 2,
		Parent = holder,
	})
	gradient(
		line,
		ColorSequence.new(Theme.Colors.white),
		0,
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.9) })
	)

	local body = UI.frame({
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, H),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
		ZIndex = 3,
		Parent = plate,
	})
	UI.list(body, Enum.FillDirection.Vertical, -S(2), nil, Enum.VerticalAlignment.Center)

	-- Line 1: the name in caps, with the VIP tag after it.
	local line1 = row(body, 1, math.floor(H * 0.5))
	text({
		Text = string.upper(p.DisplayName),
		TextSize = S(21),
		TextColor3 = Theme.Colors.white,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
		ZIndex = 3,
		Parent = line1,
	}, BOLD)
	if p:GetAttribute("PlateVip") == true then
		local tag = UI.frame({
			BackgroundColor3 = VIP,
			Size = UDim2.fromOffset(0, S(16)),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 2,
			ZIndex = 3,
			Parent = line1,
		})
		UI.corner(tag, S(2))
		UI.pad(tag, S(5), 0, S(5), 0)
		text({
			Text = "VIP",
			TextSize = S(13),
			TextColor3 = PLATE,
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			ZIndex = 4,
			Parent = tag,
		}, BOLD)
	end

	-- Line 2: the best wave and its map (the class name when there is no wave yet).
	local line2 = row(body, 2, math.floor(H * 0.36))
	local info = if top > 0
		then string.format(
			'<font color="#%s">★ WAVE %d</font>%s',
			Theme.Colors.gold:ToHex(),
			top,
			if map ~= "" then string.format('<font color="#%s">  ·  %s</font>', Theme.Colors.grey:ToHex(), map) else ""
		)
		else string.format('<font color="#%s">%s</font>', class.color, string.upper(class.name))
	text({
		Text = info,
		RichText = true,
		TextSize = S(14),
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 3,
		Parent = line2,
	}, MEDIUM)

	-- The class block: the full plate height in the class colour, the pictogram large on it.
	local block = UI.frame({
		Name = "Class",
		BackgroundColor3 = Theme.Colors.white,
		Size = UDim2.fromOffset(H, H),
		LayoutOrder = 2,
		ZIndex = 3,
		Parent = plate,
	})
	UI.corner(block, radius)
	gradient(block, ColorSequence.new(classColor:Lerp(Theme.Colors.white, 0.18), classColor:Lerp(PLATE, 0.2)), 90)
	local icon = Icons.draw(block, class.id, math.floor(H * 0.68), PLATE, classColor, class.glyph)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 4

	-- The Roblox name would sit over the plate saying the same thing.
	local hum = head.Parent and head.Parent:FindFirstChildOfClass("Humanoid")
	local saved: Enum.HumanoidDisplayDistanceType? = nil
	if hum then
		saved = hum.DisplayDistanceType
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	gui.Parent = playerGui
	-- Pop the badge on a level-up only, never on a plain rebuild.
	local was = lastLevel[p]
	lastLevel[p] = level
	if was and level > was then
		UI.punch(b, 1.4, 0.5)
	end
	return { gui = gui, humanoid = hum, savedDisplay = saved }
end

local function refresh(p: Player)
	pending[p] = nil
	remove(p)
	if p.Parent == nil or p:GetAttribute("Plate") ~= true then
		return
	end
	if p == player and not Config.NameplateShowSelf then
		return
	end
	local char = p.Character
	local head = char and char:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		plates[p] = build(p, head)
	end
end

-- Attributes set in one server step land together: one rebuild per frame per player.
local function schedule(p: Player)
	if pending[p] then
		return
	end
	pending[p] = true
	task.defer(refresh, p)
end

-- The customization scene hides your own plate (it would sit in the shot). Cheap to call every frame.
function Nameplates.setLocalHidden(hidden: boolean)
	if hidden == localHidden then
		return
	end
	localHidden = hidden
	local plate = plates[player]
	if plate then
		plate.gui.Enabled = not hidden
	end
end

function Nameplates.init()
	local function watch(p: Player)
		p.AttributeChanged:Connect(function(name: string)
			if string.sub(name, 1, 5) == "Plate" then
				schedule(p)
			end
		end)
		p.CharacterAdded:Connect(function(char: Model)
			char:WaitForChild("Head", 5)
			schedule(p)
		end)
		p.CharacterRemoving:Connect(function()
			remove(p)
		end)
		if p.Character then
			schedule(p)
		end
	end
	for _, p in Players:GetPlayers() do
		task.spawn(watch, p)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(p: Player)
		remove(p)
		pending[p] = nil
		lastLevel[p] = nil
	end)
end

return Nameplates
