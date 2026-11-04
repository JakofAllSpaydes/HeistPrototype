--!strict
-- The hub HUD: PLAY top-center (teleports you onto the queue pad; the card opens there), SHOP tile
-- left-center, Gold pill with + and INVITE FRIENDS bottom-left, the WEAPONS · CLASSES · AVATAR dock
-- bottom-center as icon tiles with labels (reference style), BOOSTS bottom-right as icon chips with a
-- countdown, and a slot under PLAY for the compact queue card. Shown by HUD.setMode("hub").
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ClientState = require(Client:WaitForChild("ClientState"))

local HubHUD = {}

local GREEN = Color3.fromHex("2FD46A")
local boostStartedAt = os.clock() -- the stub boost's countdown runs from the first HUD build

-- Icon tile with a label under it. Returns the button.
local function iconTile(
	parent: Instance,
	order: number,
	label: string,
	glyph: string,
	bg: Color3,
	fg: Color3,
	size: number
): TextButton
	local S = UI.S
	local holder = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size + S(16)),
		LayoutOrder = order,
		Parent = parent,
	})
	local b = UI.button({
		Name = label,
		Text = "",
		BackgroundColor3 = bg,
		Size = UDim2.fromOffset(size, size),
		Parent = holder,
	})
	UI.corner(b, S(10))
	UI.stroke(b, Theme.Colors.black, S(1.5), 0.3)
	if glyph == "gun" then
		local icon = UI.gunIcon(b, fg, math.floor(size * 0.8))
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
	else
		UI.text({
			Text = glyph,
			Font = Theme.Fonts.display,
			TextSize = math.floor(size * (if #glyph > 1 then 0.34 else 0.6)),
			TextColor3 = fg,
			Size = UDim2.fromScale(1, 1),
			Parent = b,
		})
	end
	local l = UI.text({
		Text = label,
		Font = Theme.Fonts.display,
		TextSize = S(11),
		TextColor3 = Theme.Colors.text,
		Position = UDim2.fromOffset(0, size + S(1)),
		Size = UDim2.new(1, 0, 0, S(14)),
		Parent = holder,
	})
	UI.stroke(l, Theme.Colors.black, S(1.5), 0.3)
	b.MouseEnter:Connect(function()
		if not ClientState.isMobile then
			UI.punch(b, 1.06, 0.15)
		end
	end)
	return b
end

function HubHUD.build(gui: ScreenGui, track: (RBXScriptConnection) -> ())
	local S = UI.S
	local mobile = ClientState.isMobile
	local component: { [string]: any } = {}
	local root = UI.frame({
		Name = "HubHUD",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = gui,
	})

	-- PLAY, top-center.
	local playH = if mobile then S(44) else S(64)
	local play = UI.button({
		Name = "Play",
		Text = "PLAY",
		Font = Theme.Fonts.display,
		TextSize = if mobile then S(22) else S(32),
		TextColor3 = Theme.Colors.bg,
		BackgroundColor3 = GREEN,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(if mobile then 12 else 22)),
		Size = UDim2.fromOffset(if mobile then S(200) else S(280), playH),
		Parent = root,
	})
	UI.corner(play, S(10))
	UI.stroke(play, Theme.Colors.black, S(2), 0.4)
	play.Activated:Connect(function()
		UI.punch(play, 0.92, 0.2)
		UI.sound(Theme.Sounds.toast, 1.3, 0.5)
		Remotes.QueueAction:FireServer("play")
	end)
	play.MouseEnter:Connect(function()
		if not mobile then
			UI.punch(play, 1.04, 0.15)
		end
	end)

	-- Slot for the compact queue card, under PLAY.
	local queueSlot = UI.frame({
		Name = "QueueSlot",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(if mobile then 12 else 22) + playH + S(10)),
		Size = UDim2.fromOffset(S(360), 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	})
	UI.list(queueSlot, Enum.FillDirection.Vertical, S(6), Enum.HorizontalAlignment.Center)
	if mobile then
		UI.new("UIScale", { Scale = 0.8, Parent = queueSlot })
	end

	-- Placeholder panel (SHOP / GOLD / CRATE · PHASE 4).
	local placeholder = UI.frame({
		Name = "Placeholder",
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.04,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(S(360), S(170)),
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})
	UI.corner(placeholder, S(10))
	UI.stroke(placeholder, Theme.Colors.black, S(2), 0.3)
	local phHeader = UI.frame({
		BackgroundColor3 = Theme.Colors.blue,
		Size = UDim2.new(1, 0, 0, S(44)),
		ZIndex = 21,
		Parent = placeholder,
	})
	UI.corner(phHeader, S(10))
	local placeholderTitle = UI.text({
		Text = "Shop",
		Font = Theme.Fonts.body,
		TextSize = S(22),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(16), 0),
		Size = UDim2.new(1, -S(32), 1, 0),
		ZIndex = 22,
		Parent = phHeader,
	})
	UI.text({
		Text = "PHASE 4 · ROBUX AND CRATES ARE OUT OF SCOPE FOR THIS BRIEF",
		TextSize = S(11),
		TextColor3 = Theme.Colors.grey,
		Position = UDim2.fromOffset(0, S(64)),
		Size = UDim2.new(1, 0, 0, S(16)),
		ZIndex = 21,
		Parent = placeholder,
	})
	local okBtn = UI.button({
		Text = "OK",
		Font = Theme.Fonts.body,
		TextSize = S(18),
		TextColor3 = Theme.Colors.bg,
		BackgroundColor3 = GREEN,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(14)),
		Size = UDim2.new(1, -S(28), 0, S(44)),
		ZIndex = 21,
		Parent = placeholder,
	})
	UI.corner(okBtn, S(6))
	okBtn.Activated:Connect(function()
		placeholder.Visible = false
	end)
	function component.showPlaceholder(title: string)
		placeholderTitle.Text = title
		placeholder.Visible = true
		UI.punch(placeholder, 1.08, 0.25)
		UI.sound(Theme.Sounds.toast, 1.1, 0.4)
	end

	-- SHOP tile, left-center.
	local shopSize = if mobile then S(52) else S(64)
	local shopHolder = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, S(20), 0.5, 0),
		Size = UDim2.fromOffset(shopSize, shopSize + S(16)),
		Parent = root,
	})
	local shop = iconTile(shopHolder, 1, "Shop", "$", Theme.Colors.amber, Theme.Colors.bg, shopSize)
	shop.Activated:Connect(function()
		UI.punch(shop, 0.92, 0.15)
		component.showPlaceholder("Shop")
	end)

	-- Gold pill with + and INVITE FRIENDS, bottom-left.
	local goldW = if mobile then S(170) else S(230)
	local gold = UI.frame({
		Name = "Gold",
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, S(20), 1, -S(62)),
		Size = UDim2.fromOffset(goldW, S(38)),
		Parent = root,
	})
	UI.corner(gold, S(8))
	UI.stroke(gold, Theme.Colors.black, S(1.5), 0.3)
	local bar = UI.frame({
		BackgroundColor3 = Theme.Colors.gold,
		Size = UDim2.fromOffset(S(26), S(13)),
		Position = UDim2.fromOffset(S(10), S(13)),
		Rotation = -8,
		Parent = gold,
	})
	UI.corner(bar, S(3))
	local goldLabel = UI.text({
		Name = "Gold",
		Text = "0",
		Font = Theme.Fonts.display,
		TextSize = S(22),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(44), 0),
		Size = UDim2.new(1, -S(88), 1, 0),
		Parent = gold,
	})
	local plus = UI.button({
		Text = "+",
		Font = Theme.Fonts.display,
		TextSize = S(20),
		TextColor3 = Theme.Colors.bg,
		BackgroundColor3 = GREEN,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -S(6), 0.5, 0),
		Size = UDim2.fromOffset(S(28), S(28)),
		Parent = gold,
	})
	UI.corner(plus, S(6))
	plus.Activated:Connect(function()
		UI.punch(plus, 0.9, 0.15)
		component.showPlaceholder("Gold")
	end)
	local invite = UI.button({
		Name = "Invite",
		Text = if mobile then "+👥" else "INVITE FRIENDS",
		Font = Theme.Fonts.body,
		TextSize = S(13),
		TextColor3 = Theme.Colors.white,
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, S(20), 1, -S(20)),
		Size = UDim2.fromOffset(if mobile then S(44) else goldW, S(34)),
		Parent = root,
	})
	UI.corner(invite, S(6))
	UI.stroke(invite, Theme.Colors.black, S(1.5), 0.3)
	invite.Activated:Connect(function()
		UI.punch(invite, 0.92, 0.15) -- present, does nothing (brief)
	end)

	-- Dock, bottom-center: WEAPONS · CLASSES · AVATAR icon tiles with labels.
	local tile = if mobile then S(56) else S(68)
	local dock = UI.frame({
		Name = "Dock",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(16)),
		Size = UDim2.fromOffset(tile * 3 + S(24), tile + S(16)),
		Parent = root,
	})
	UI.list(dock, Enum.FillDirection.Horizontal, S(12), Enum.HorizontalAlignment.Center)
	local tiles: { [string]: TextButton } = {}
	local glyphs = { WEAPONS = "gun", CLASSES = "CLS", AVATAR = "MSK" }
	local colors = { WEAPONS = Theme.Colors.blue, CLASSES = Theme.Colors.grey, AVATAR = Theme.Colors.gold }
	local labels = { WEAPONS = "Weapons", CLASSES = "Classes", AVATAR = "Avatar" }
	for i, tab in { "WEAPONS", "CLASSES", "AVATAR" } do
		local b = iconTile(dock, i, labels[tab], glyphs[tab], Theme.Colors.panel, colors[tab], tile)
		local stroke = b:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = Theme.Colors.gold
			stroke.Transparency = 0
		end
		b.Activated:Connect(function()
			UI.punch(b, 0.92, 0.18)
			UI.sound(Theme.Sounds.toast, 1.4, 0.35)
			if component.onDock then
				component.onDock(tab)
			end
		end)
		tiles[tab] = b
	end

	-- BOOSTS, bottom-right: icon chips; the first is a stub +50% GOLD with a countdown, the others empty.
	local chipSize = if mobile then S(44) else S(56)
	local boosts = UI.frame({
		Name = "Boosts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -S(20), 1, -S(16)),
		Size = UDim2.fromOffset(chipSize * 3 + S(20), chipSize + S(34)),
		Parent = root,
	})
	UI.text({
		Text = "BOOSTS",
		Font = Theme.Fonts.display,
		TextSize = S(12),
		TextColor3 = Theme.Colors.grey,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, 0, 0, S(14)),
		Parent = boosts,
	})
	local chips = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, S(18)),
		Size = UDim2.new(1, 0, 0, chipSize + S(16)),
		Parent = boosts,
	})
	UI.list(chips, Enum.FillDirection.Horizontal, S(10), Enum.HorizontalAlignment.Right)
	local timerLabel: TextLabel? = nil
	for i = 1, 3 do
		local filled = i == 1
		local holder = UI.frame({
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(chipSize, chipSize + S(16)),
			LayoutOrder = i,
			Parent = chips,
		})
		local chip = UI.frame({
			BackgroundColor3 = if filled then Theme.Colors.panel else Theme.Colors.bg,
			BackgroundTransparency = if filled then 0 else 0.6,
			Size = UDim2.fromOffset(chipSize, chipSize),
			Parent = holder,
		})
		UI.corner(chip, S(10))
		UI.stroke(chip, if filled then Theme.Colors.gold else Theme.Colors.grey, S(1.5), if filled then 0 else 0.5)
		if filled then
			UI.text({
				Text = "◆",
				Font = Theme.Fonts.display,
				TextSize = math.floor(chipSize * 0.42),
				TextColor3 = Theme.Colors.gold,
				Position = UDim2.fromOffset(0, S(2)),
				Size = UDim2.new(1, 0, 0.6, 0),
				Parent = chip,
			})
			UI.text({
				Text = "+50%",
				Font = Theme.Fonts.display,
				TextSize = S(11),
				TextColor3 = Theme.Colors.gold,
				Position = UDim2.fromScale(0, 0.6),
				Size = UDim2.new(1, 0, 0.4, 0),
				Parent = chip,
			})
			timerLabel = UI.text({
				Text = "",
				Font = Theme.Fonts.display,
				TextSize = S(11),
				TextColor3 = Theme.Colors.text,
				Position = UDim2.fromOffset(0, chipSize + S(1)),
				Size = UDim2.new(1, 0, 0, S(14)),
				Parent = holder,
			})
			UI.stroke(timerLabel :: TextLabel, Theme.Colors.black, S(1.5), 0.3)
		else
			UI.text({
				Text = "+",
				Font = Theme.Fonts.display,
				TextSize = math.floor(chipSize * 0.4),
				TextColor3 = Theme.Colors.grey,
				Size = UDim2.fromScale(1, 1),
				Parent = chip,
			})
		end
	end

	component.frame = root
	component.queueSlot = queueSlot
	component.goldLabel = goldLabel
	component.tiles = tiles
	component.play = play
	component.onDock = nil :: ((string) -> ())?

	local shown = -1
	function component.update(sync: any)
		local profile = sync.profile
		local gold = if profile and typeof(profile.gold) == "number" then profile.gold else 0
		if gold ~= shown then
			if shown >= 0 then
				UI.punch(goldLabel, if gold > shown then 1.15 else 0.95, 0.3)
			end
			shown = gold
			goldLabel.Text = UI.fmtNum(gold)
		end
	end

	-- The stub boost ticks down; PLAY breathes.
	local t = 0
	local lastSec = -1
	track(RunService.Heartbeat:Connect(function(dt)
		if not root.Visible then
			return
		end
		t += dt
		local stroke = play:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0.3 + 0.2 * math.sin(t * 2)
		end
		local label = timerLabel
		if label then
			local left = math.max(0, Config.StubBoostSec - (os.clock() - boostStartedAt))
			local sec = math.ceil(left)
			if sec ~= lastSec then
				lastSec = sec
				label.Text = string.format("%d:%02d", sec // 60, sec % 60)
			end
		end
	end))

	return component
end

return HubHUD
