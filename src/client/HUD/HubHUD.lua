--!strict
-- The hub HUD (canvas board "Hub HUD — desktop"): PLAY top-center, SHOP tile left-center, Gold row with +
-- and INVITE FRIENDS bottom-left, the WEAPONS · CLASSES · AVATAR dock bottom-center, BOOSTS chips
-- bottom-right, and a slot under PLAY for the compact queue card. Shown by HUD.setMode("hub"); the match
-- HUD pieces are hidden by the mode. Top-left stays empty for server chat.
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ClientState = require(Client:WaitForChild("ClientState"))

local HubHUD = {}

local player = Players.LocalPlayer

-- Nearest queue pad part in the map (QueueZone1..N).
local function nearestZone(from: Vector3): BasePart?
	local room = Workspace:FindFirstChild("Room")
	if not room then
		return nil
	end
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, child in room:GetChildren() do
		if child:IsA("BasePart") and string.match(child.Name, "^QueueZone%d+$") then
			local d = (child.Position - from).Magnitude
			if d < bestDist then
				bestDist = d
				best = child
			end
		end
	end
	return best
end

local walkToken = 0

-- PLAY: walk to the nearest zone along a computed path (straight line when the path fails). Any
-- player input cancels it (the humanoid's own MoveTo is overridden by the controls).
local function walkToZone()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not root or not hum then
		return
	end
	local zone = nearestZone(root.Position)
	if not zone then
		return
	end
	walkToken += 1
	local token = walkToken
	local target = Vector3.new(zone.Position.X, root.Position.Y, zone.Position.Z)
	task.spawn(function()
		local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
		local ok = pcall(function()
			path:ComputeAsync(root.Position, target)
		end)
		local waypoints = if ok and path.Status == Enum.PathStatus.Success then path:GetWaypoints() else nil
		if not waypoints or #waypoints == 0 then
			hum:MoveTo(target)
			return
		end
		for i, wp in waypoints do
			if token ~= walkToken or hum.Parent ~= char then
				return
			end
			if i == 1 then
				continue
			end
			hum:MoveTo(wp.Position)
			local reached = hum.MoveToFinished:Wait()
			if not reached then
				hum:MoveTo(target)
				return
			end
		end
	end)
end

function HubHUD.build(gui: ScreenGui, track: (RBXScriptConnection) -> ())
	local S = UI.S
	local mobile = ClientState.isMobile
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
		BackgroundColor3 = Theme.Colors.gold,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(if mobile then 12 else 22)),
		Size = UDim2.fromOffset(if mobile then S(200) else S(280), playH),
		Parent = root,
	})
	UI.corner(play, S(14))
	UI.stroke(play, Theme.Colors.black, S(2), 0.4)
	play.Activated:Connect(function()
		UI.punch(play, 0.92, 0.2)
		UI.sound(Theme.Sounds.toast, 1.3, 0.5)
		walkToZone()
	end)
	play.MouseEnter:Connect(function()
		if not mobile then
			UI.punch(play, 1.04, 0.15)
		end
	end)

	-- Slot for the compact queue card, under PLAY (QueueUI parents its card here).
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

	-- SHOP tile, left-center (amber frame). Opens a placeholder.
	local tileW, tileH = if mobile then S(56) else S(92), if mobile then S(56) else S(104)
	local shop = UI.button({
		Name = "Shop",
		Text = "",
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, S(20), 0.5, 0),
		Size = UDim2.fromOffset(tileW, tileH),
		Parent = root,
	})
	UI.corner(shop, S(10))
	UI.stroke(shop, Theme.Colors.amber, S(2))
	UI.text({
		Text = "$",
		Font = Theme.Fonts.display,
		TextSize = if mobile then S(26) else S(40),
		TextColor3 = Theme.Colors.amber,
		Size = UDim2.new(1, 0, if mobile then 1 else 0.66, 0),
		Parent = shop,
	})
	if not mobile then
		UI.text({
			Text = "SHOP",
			Font = Theme.Fonts.display,
			TextSize = S(14),
			TextColor3 = Theme.Colors.text,
			Position = UDim2.fromScale(0, 0.66),
			Size = UDim2.fromScale(1, 0.3),
			Parent = shop,
		})
	end

	-- Placeholder panel (SHOP · PHASE 4, CRATE UI · PHASE 4): centered card with a title and an OK.
	local placeholder = UI.frame({
		Name = "Placeholder",
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.08,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(S(360), S(160)),
		Visible = false,
		ZIndex = 20,
		Parent = root,
	})
	UI.corner(placeholder, S(14))
	UI.stroke(placeholder, Theme.Colors.amber, S(2))
	local placeholderTitle = UI.text({
		Text = "SHOP · PHASE 4",
		Font = Theme.Fonts.display,
		TextSize = S(26),
		TextColor3 = Theme.Colors.amber,
		Position = UDim2.fromOffset(0, S(24)),
		Size = UDim2.new(1, 0, 0, S(34)),
		ZIndex = 21,
		Parent = placeholder,
	})
	UI.text({
		Text = "ROBUX AND CRATES ARE OUT OF SCOPE FOR THIS BRIEF",
		TextSize = S(11),
		TextColor3 = Theme.Colors.grey,
		Position = UDim2.fromOffset(0, S(62)),
		Size = UDim2.new(1, 0, 0, S(16)),
		ZIndex = 21,
		Parent = placeholder,
	})
	local okBtn = UI.button({
		Text = "OK",
		Font = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.bg,
		BackgroundColor3 = Theme.Colors.amber,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(16)),
		Size = UDim2.fromOffset(S(120), S(40)),
		ZIndex = 21,
		Parent = placeholder,
	})
	UI.corner(okBtn, S(10))
	okBtn.Activated:Connect(function()
		placeholder.Visible = false
	end)
	local component: { [string]: any } = {}
	function component.showPlaceholder(title: string)
		placeholderTitle.Text = title
		placeholder.Visible = true
		UI.punch(placeholder, 1.1, 0.25)
		UI.sound(Theme.Sounds.toast, 1.1, 0.4)
	end
	shop.Activated:Connect(function()
		UI.punch(shop, 0.92, 0.15)
		component.showPlaceholder("SHOP · PHASE 4")
	end)

	-- Gold row, bottom-left, with + (placeholder) and INVITE FRIENDS under it.
	local goldRoot = UI.frame({
		Name = "GoldRow",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, S(20), 1, -S(20)),
		Size = UDim2.fromOffset(S(260), S(78)),
		Parent = root,
	})
	local bar = UI.frame({
		BackgroundColor3 = Theme.Colors.gold,
		Size = UDim2.fromOffset(S(28), S(14)),
		Position = UDim2.fromOffset(S(2), S(12)),
		Rotation = -8,
		Parent = goldRoot,
	})
	UI.corner(bar, S(3))
	local goldLabel = UI.text({
		Name = "Gold",
		Text = "0",
		Font = Theme.Fonts.display,
		TextSize = S(30),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(40), 0),
		Size = UDim2.new(1, -S(80), 0, S(40)),
		Parent = goldRoot,
	})
	UI.stroke(goldLabel, Theme.Colors.black, S(1.5), 0.4)
	local plus = UI.button({
		Text = "+",
		Font = Theme.Fonts.display,
		TextSize = S(20),
		TextColor3 = Theme.Colors.gold,
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.fromOffset(S(26), S(26)),
		Position = UDim2.fromOffset(S(40) + S(160), S(7)),
		Parent = goldRoot,
	})
	UI.corner(plus, S(7))
	UI.stroke(plus, Theme.Colors.gold, S(1.5))
	plus.Activated:Connect(function()
		UI.punch(plus, 0.9, 0.15)
		component.showPlaceholder("GOLD · PHASE 4")
	end)
	local invite = UI.button({
		Name = "Invite",
		Text = if mobile then "+👥" else "INVITE FRIENDS",
		Font = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Theme.Colors.text,
		BackgroundColor3 = Theme.Colors.panel,
		Position = UDim2.fromOffset(0, S(44)),
		Size = UDim2.fromOffset(if mobile then S(44) else S(160), S(30)),
		Parent = goldRoot,
	})
	UI.corner(invite, S(8))
	UI.stroke(invite, Theme.Colors.grey, S(1.5), 0.3)
	invite.Activated:Connect(function()
		UI.punch(invite, 0.92, 0.15) -- present, does nothing (brief)
	end)

	-- Dock, bottom-center: WEAPONS · CLASSES · AVATAR.
	local dockW, dockH = if mobile then S(76) else S(108), if mobile then S(68) else S(96)
	local dock = UI.frame({
		Name = "Dock",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(18)),
		Size = UDim2.fromOffset(dockW * 3 + S(24), dockH),
		Parent = root,
	})
	UI.list(dock, Enum.FillDirection.Horizontal, S(12), Enum.HorizontalAlignment.Center)
	local tiles: { [string]: TextButton } = {}
	local glyphs = { WEAPONS = "GUN", CLASSES = "CLS", AVATAR = "MSK" }
	for i, tab in { "WEAPONS", "CLASSES", "AVATAR" } do
		local tile = UI.button({
			Name = tab,
			Text = "",
			BackgroundColor3 = Theme.Colors.panel,
			Size = UDim2.fromOffset(dockW, dockH),
			LayoutOrder = i,
			Parent = dock,
		})
		UI.corner(tile, S(10))
		UI.stroke(tile, Theme.Colors.gold, S(2))
		local well = UI.frame({
			BackgroundColor3 = Theme.Colors.panel2,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, S(8)),
			Size = UDim2.fromOffset(dockH * 0.5, dockH * 0.5),
			Parent = tile,
		})
		UI.corner(well, S(8))
		if tab == "WEAPONS" then
			local icon = UI.gunIcon(well, Theme.Colors.gold, math.floor(dockH * 0.46))
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
		else
			UI.text({
				Text = glyphs[tab],
				Font = Theme.Fonts.display,
				TextSize = math.floor(dockH * 0.2),
				TextColor3 = Theme.Colors.gold,
				Size = UDim2.fromScale(1, 1),
				Parent = well,
			})
		end
		UI.text({
			Text = tab,
			Font = Theme.Fonts.display,
			TextSize = if mobile then S(10) else S(14),
			TextColor3 = Theme.Colors.text,
			Position = UDim2.new(0, 0, 1, if mobile then -S(16) else -S(28)),
			Size = UDim2.new(1, 0, 0, if mobile then S(14) else S(22)),
			Parent = tile,
		})
		tile.Activated:Connect(function()
			UI.punch(tile, 0.92, 0.18)
			UI.sound(Theme.Sounds.toast, 1.4, 0.35)
			if component.onDock then
				component.onDock(tab)
			end
		end)
		tile.MouseEnter:Connect(function()
			if not mobile then
				UI.punch(tile, 1.04, 0.15)
			end
		end)
		tiles[tab] = tile
	end

	-- BOOSTS, bottom-right: three chips, the first a stub, the others dashed empty.
	local boosts = UI.frame({
		Name = "Boosts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -S(20), 1, -S(20)),
		Size = UDim2.fromOffset(S(300), S(52)),
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
		Size = UDim2.new(1, 0, 0, S(30)),
		Parent = boosts,
	})
	UI.list(chips, Enum.FillDirection.Horizontal, S(8), Enum.HorizontalAlignment.Right)
	for i = 1, 3 do
		local filled = i == 1
		local chip = UI.frame({
			BackgroundColor3 = if filled then Theme.Colors.panel else Theme.Colors.bg,
			BackgroundTransparency = if filled then 0 else 0.5,
			Size = UDim2.fromOffset(S(90), S(30)),
			LayoutOrder = i,
			Parent = chips,
		})
		UI.corner(chip, S(15))
		local stroke =
			UI.stroke(chip, if filled then Theme.Colors.gold else Theme.Colors.grey, S(1.5), if filled then 0 else 0.4)
		if not filled then
			stroke.LineJoinMode = Enum.LineJoinMode.Round
		end
		UI.text({
			Text = if filled then "+50% GOLD" else "— — —",
			Font = Theme.Fonts.display,
			TextSize = S(11),
			TextColor3 = if filled then Theme.Colors.gold else Theme.Colors.grey,
			Size = UDim2.fromScale(1, 1),
			Parent = chip,
		})
	end

	-- Mobile: the slot and card scale down.
	if mobile then
		local scale = UI.new("UIScale", { Scale = 0.8, Parent = queueSlot })
		local _ = scale
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

	-- PLAY breathes while nobody is in a party; a small nudge so it reads as the thing to press.
	local t = 0
	track(RunService.Heartbeat:Connect(function(dt)
		if not root.Visible then
			return
		end
		t += dt
		local stroke = play:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0.3 + 0.2 * math.sin(t * 2)
		end
	end))

	return component
end

return HubHUD
