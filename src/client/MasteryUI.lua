--!strict
-- The mastery tier-up moment (brief 5 feedback): when a gun or class crosses a mastery tier mid-run the server sends
-- MasteryUp and this card drops in under the wave bar, the way a shooter's rank-up shows mid-game: a spinning
-- tier emblem with rays, `WEAPON MASTERY` / `CLASS MASTERY`, `AK-47 · MASTERY II`, the reward in gold and what it
-- does. The reward is already live (the passive is on, the wrap is owned). Cards queue, wait out cutscenes and
-- hold MasteryPopSec each.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Wraps = require(Shared:WaitForChild("Wraps"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local MasteryUI = {}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local gui: ScreenGui? = nil
local queue: { any } = {}
local busy = false

-- Tier I / II / III read as Rare / Epic / Legendary.
local function tierColor(tier: number, maxTier: number): Color3
	return Rarity.color(math.clamp(5 - (maxTier - tier), 3, 5))
end

local function ensureGui(): ScreenGui
	local g = gui
	if g and g.Parent then
		return g
	end
	local s = UI.new("ScreenGui", {
		Name = "MasteryUp",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 40,
		Parent = playerGui,
	}) :: ScreenGui
	gui = s
	return s
end

local function emblem(parent: Instance, color: Color3, roman: string, size: number): Frame
	local holder = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		ZIndex = 3,
		Parent = parent,
	})
	-- Rays behind the badge.
	local rays = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(2, 2),
		ZIndex = 2,
		Parent = holder,
	})
	for i = 1, 10 do
		local ray = UI.frame({
			BackgroundColor3 = color,
			BackgroundTransparency = 0.25,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(UI.S(8), size * 0.9),
			Rotation = (i - 1) * 36,
			ZIndex = 2,
			Parent = rays,
		})
		UI.tween(ray, { BackgroundTransparency = 1, Size = UDim2.fromOffset(UI.S(2), size * 1.5) }, 1.2)
	end
	UI.tween(rays, { Rotation = 60 }, 1.2)
	-- The badge: a diamond in the tier color with the numeral.
	local badge = UI.frame({
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.66, 0.66),
		Rotation = 45,
		ZIndex = 3,
		Parent = holder,
	})
	UI.corner(badge, UI.S(8))
	UI.stroke(badge, Theme.Colors.white, UI.S(3), 0.1)
	local inner = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.72),
		ZIndex = 3,
		Parent = badge,
	})
	UI.corner(inner, UI.S(6))
	local numeral = UI.text({
		Text = roman,
		Font = Theme.Fonts.display,
		TextSize = math.floor(size * 0.32),
		TextColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = holder,
	})
	UI.stroke(numeral, Theme.Colors.black, UI.S(1.5), 0.3)
	return holder
end

local function show(d: any)
	local g = ensureGui()
	local S = UI.S
	local mobile = ClientState.isMobile
	local tier = tonumber(d.tier) or 1
	local maxTier = tonumber(d.maxTier) or 3
	local color = tierColor(tier, maxTier)
	local W, H = S(if mobile then 330 else 400), S(if mobile then 80 else 92)
	local card = UI.frame({
		Name = "Card",
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.05,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -H - S(20)),
		Size = UDim2.fromOffset(W, H),
		ClipsDescendants = false,
		Parent = g,
	})
	UI.corner(card, S(14))
	local stroke = UI.stroke(card, color, S(3))
	-- A thin bar in the tier color along the left edge, and a shine that sweeps once.
	local edge = UI.frame({
		BackgroundColor3 = color,
		Size = UDim2.new(0, S(6), 1, 0),
		Parent = card,
	})
	UI.corner(edge, S(3))
	local shineClip = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		Parent = card,
	})
	UI.corner(shineClip, S(14))
	local shine = UI.frame({
		BackgroundColor3 = Theme.Colors.white,
		BackgroundTransparency = 0.82,
		Position = UDim2.new(0, -S(60), 0, 0),
		Size = UDim2.new(0, S(40), 1, 0),
		Rotation = 12,
		Parent = shineClip,
	})
	local emb = emblem(card, color, tostring(d.roman or tier), H * 1.15)
	emb.Position = UDim2.new(0, H * 0.62, 0.5, 0)
	local textX = H * 1.25
	UI.text({
		Text = if d.kind == "weapon" then "WEAPON MASTERY" else "CLASS MASTERY",
		Font = Theme.Fonts.display,
		TextSize = S(12),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(textX, S(8)),
		Size = UDim2.new(1, -textX - S(10), 0, S(14)),
		Parent = card,
	})
	local title = UI.text({
		Text = string.format("%s · MASTERY %s", tostring(d.name or ""), tostring(d.roman or tier)),
		Font = Theme.Fonts.display,
		TextSize = S(if mobile then 18 else 21),
		TextColor3 = Theme.Colors.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(textX, S(22)),
		Size = UDim2.new(1, -textX - S(10), 0, S(24)),
		Parent = card,
	})
	-- The reward: the wrap swatch for a gun, the passive's name for a class.
	local rewardX = textX
	local wrap = if typeof(d.wrap) == "string" then Wraps.ById[d.wrap] else nil
	if wrap then
		local sw = UI.frame({
			BackgroundColor3 = Color3.fromHex(wrap.color),
			Position = UDim2.fromOffset(textX, S(50)),
			Size = UDim2.fromOffset(S(16), S(16)),
			Parent = card,
		})
		UI.corner(sw, S(4))
		UI.stroke(sw, Theme.Colors.white, S(1), 0.3)
		rewardX += S(22)
	end
	UI.text({
		Text = tostring(d.reward or ""),
		Font = Theme.Fonts.display,
		TextSize = S(15),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(rewardX, S(48)),
		Size = UDim2.new(1, -rewardX - S(10), 0, S(20)),
		Parent = card,
	})
	UI.text({
		Text = tostring(d.line or ""),
		TextSize = S(10),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(textX, S(68)),
		Size = UDim2.new(1, -textX - S(10), 0, S(14)),
		Parent = card,
	})

	-- In: drop under the wave bar, punch, rays, shine, the sting.
	local y = S(if mobile then 70 else 96)
	UI.tween(card, { Position = UDim2.new(0.5, 0, 0, y) }, 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	UI.punch(emb, 1.6, 0.5)
	UI.punch(title, 1.15, 0.4)
	UI.tween(
		shine,
		{ Position = UDim2.new(1, S(20), 0, 0) },
		0.7,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out,
		0.25
	)
	UI.sound(Theme.Sounds.legendary, if d.kind == "weapon" then 1.15 else 1, 0.7)
	UI.sound(Theme.Sounds.reelLand, 0.8, 0.6)
	ClientState.Juice:Fire("RarityFlash", { color = color, alpha = 0.18 })
	ClientState.Juice:Fire("Shake", { amp = 0.15, dur = 0.2 })
	stroke.Thickness = S(7)
	UI.tween(stroke, { Thickness = S(3) }, 0.6)
	task.wait(Config.MasteryPopSec)
	-- Out: up and gone.
	local out = UI.tween(
		card,
		{ Position = UDim2.new(0.5, 0, 0, -H - S(20)) },
		0.3,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	out.Completed:Wait()
	card:Destroy()
end

local function pump()
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		while #queue > 0 do
			-- Never over a cutscene: wait for the camera to come back.
			while ClientState.cameraMode == "cinematic" do
				task.wait(0.2)
			end
			show(table.remove(queue, 1))
			task.wait(0.15)
		end
		busy = false
	end)
end

function MasteryUI.init()
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "MasteryUp" and typeof(data) == "table" then
			table.insert(queue, data)
			pump()
		end
	end)
end

return MasteryUI
