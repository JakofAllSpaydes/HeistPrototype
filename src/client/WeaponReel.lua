--!strict
-- Weapon roll: a reel panel in the top-center slot under the wave bar. Spin -> land -> eject toward the
-- player's feet while the server drops the real gun in from above. The buy tile just shows ROLLING.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Weapons = require(Shared:WaitForChild("Weapons"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local HUD = require(script.Parent:WaitForChild("HUD"))
local Juice = require(script.Parent:WaitForChild("Juice"))

local WeaponReel = {}

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera :: Camera
local spinning = false
local CELLS = 18
local LAND = 14 -- the rolled gun sits here; the cells after it make the stop read as a stop

local function tile()
	local buy = HUD.get("buy")
	return buy and buy.tiles.weapon
end

local function feetScreenPos(): Vector2
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local p = camera:WorldToViewportPoint(root.Position + root.CFrame.LookVector * 4 - Vector3.new(0, 2.5, 0))
		return Vector2.new(p.X, p.Y)
	end
	return camera.ViewportSize / 2
end

-- Builds the panel in the call slot. Returns the pieces the spin needs.
local function buildPanel()
	local S = UI.S
	local cs = HUD.get("callSlot")
	local w = cs.width
	local h = S(128)
	local panel = UI.frame({
		Name = "ReelPanel",
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.fromOffset(w, h),
		ClipsDescendants = true,
	})
	UI.corner(panel, S(14))
	local stroke = UI.stroke(panel, Theme.Colors.grey, S(3))
	local title = UI.text({
		Text = "NEW WEAPON",
		Font = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Theme.Colors.grey,
		Size = UDim2.new(1, 0, 0, S(22)),
		Position = UDim2.fromOffset(0, S(4)),
		Parent = panel,
	})
	local stripW = w - S(20)
	local stripH = S(66)
	local strip = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		Position = UDim2.fromOffset(S(10), S(28)),
		Size = UDim2.fromOffset(stripW, stripH),
		ClipsDescendants = true,
		Parent = panel,
	})
	UI.corner(strip, S(10))
	local cellW = S(72)
	local row = UI.frame({
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(cellW * CELLS, stripH),
		Position = UDim2.fromOffset(stripW / 2 - cellW / 2, 0),
		Parent = strip,
	})
	-- Center marker.
	local marker = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(cellW, stripH),
		ZIndex = 3,
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
			ZIndex = 4,
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
		Parent = panel,
	})
	cs.add(panel, 0)
	panel.Size = UDim2.fromOffset(w, 0)
	UI.tween(panel, { Size = UDim2.fromOffset(w, h) }, 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	return {
		panel = panel,
		stroke = stroke,
		title = title,
		strip = strip,
		stripW = stripW,
		stripH = stripH,
		row = row,
		cellW = cellW,
		marker = marker,
		markerStroke = markerStroke,
		result = result,
		width = w,
		height = h,
	}
end

local function fillRow(p: any, weapon: any)
	local S = UI.S
	for i = 1, CELLS do
		local isLast = i == LAND
		local rarity = if isLast then weapon.rarity else math.random(1, 5)
		local color = Rarity.color(rarity)
		local cell = UI.frame({
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset((i - 1) * p.cellW, 0),
			Size = UDim2.fromOffset(p.cellW, p.stripH),
			Parent = p.row,
		})
		local frame = UI.frame({
			BackgroundColor3 = Theme.Colors.panel2,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -S(8), 1, -S(10)),
			Parent = cell,
		})
		UI.corner(frame, S(8))
		UI.stroke(frame, color, S(2), if isLast then 0 else 0.4)
		local icon = UI.gunIcon(frame, color, math.floor(p.stripH * 0.72))
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		if not isLast then
			for _, c in icon:GetChildren() do
				if c:IsA("Frame") then
					c.BackgroundTransparency = 0.3
				end
			end
		end
	end
end

local function spin(weapon: any)
	local t = tile()
	local p = buildPanel()
	fillRow(p, weapon)
	local pulsing = true
	if t then
		t.icon.Visible = false
		t.name.Text = "ROLLING"
		t.pricePill.Visible = false
		t.setGreyed(true)
		-- Gold stroke breathes on the tile for as long as the reel runs.
		task.spawn(function()
			local tt = 0
			while pulsing and t.button.Parent do
				tt += 6 * task.wait()
				t.stroke.Color = Theme.Colors.gold
				t.stroke.Transparency = 0.2 + 0.3 * (0.5 + 0.5 * math.sin(tt))
				t.stroke.Thickness = UI.S(2) + UI.S(2) * (0.5 + 0.5 * math.sin(tt))
			end
			if t.button.Parent then
				t.stroke.Transparency = 0
				t.stroke.Thickness = UI.S(2)
			end
		end)
	end

	-- Scroll so the last cell ends under the marker.
	local startX = p.stripW / 2 - p.cellW / 2
	local endX = p.stripW / 2 - (LAND - 0.5) * p.cellW
	p.row.Position = UDim2.fromOffset(startX, 0)
	local tween = UI.tween(
		p.row,
		{ Position = UDim2.fromOffset(endX, 0) },
		Config.RollDurationSec,
		Enum.EasingStyle.Quart,
		Enum.EasingDirection.Out
	)
	local lastIdx = 0
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		if not p.row.Parent then
			conn:Disconnect()
			return
		end
		local idx = math.floor((p.stripW / 2 - p.row.Position.X.Offset) / p.cellW + 0.5)
		if idx > lastIdx then
			lastIdx = idx
			UI.sound(Theme.Sounds.reelTick, 0.7 + (idx / LAND) * 1.1, 0.4)
			UI.punch(p.marker, 1.06, 0.1)
		end
	end)
	tween.Completed:Wait()
	conn:Disconnect()
	pulsing = false
	if not p.panel.Parent then
		spinning = false
		return
	end

	-- Land.
	local color = Rarity.color(weapon.rarity)
	p.stroke.Color = color
	p.markerStroke.Color = color
	p.markerStroke.Transparency = 0
	p.title.Text = string.upper(weapon.rarityName)
	p.title.TextColor3 = color
	p.result.Text = string.format(
		"%s  ·  DMG %s  ·  %s",
		string.upper(weapon.displayName),
		UI.fmtDmg(weapon.dmg or 0, weapon.pellets or 1),
		UI.fmtRate(
			if Weapons.ById[weapon.weaponId]
				then Weapons.effectiveRate(
					Weapons.ById[weapon.weaponId],
					ClientState.rateMult() * (tonumber(weapon.levelRateMult) or 1)
				)
				else (weapon.fireRate or 0) * ClientState.rateMult()
		)
	)
	p.result.TextColor3 = color
	local center = p.panel.AbsolutePosition + p.panel.AbsoluteSize / 2
	local j = Juice.burst(weapon.rarity, color, center)
	UI.punch(p.panel, j.punch, 0.35)
	UI.punch(p.result, 1.2 + j.tier * 0.08, 0.4)
	UI.sound(Theme.Sounds.reelLand, j.pitch, j.volume)
	if j.tier >= 4 then
		-- Double tap on the stroke so high tiers visibly "lock in".
		p.stroke.Thickness = UI.S(6)
		UI.tween(p.stroke, { Thickness = UI.S(3) }, 0.5)
	end
	task.wait(Config.RollLandHoldSec + j.hold)

	-- Eject: the icon flies down toward the player's feet while the real gun drops in.
	local gui = HUD.gui
	if gui and p.panel.Parent then
		local start = p.marker.AbsolutePosition + p.marker.AbsoluteSize / 2
		local ghost = UI.gunIcon(gui, color, math.floor(p.stripH * 0.9))
		ghost.AnchorPoint = Vector2.new(0.5, 0.5)
		ghost.Position = UDim2.fromOffset(start.X, start.Y)
		ghost.ZIndex = 20
		local feet = feetScreenPos()
		UI.tween(
			ghost,
			{ Position = UDim2.fromOffset(feet.X, feet.Y), Rotation = 110 },
			Config.RollEjectSec,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		for _, c in ghost:GetChildren() do
			if c:IsA("Frame") then
				UI.tween(
					c,
					{ BackgroundTransparency = 0.6 },
					Config.RollEjectSec,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				)
			end
		end
		task.delay(Config.RollEjectSec + 0.05, function()
			ghost:Destroy()
		end)
		UI.sound(Theme.Sounds.swap, 0.8, 0.5)
	end
	local close = UI.tween(
		p.panel,
		{ Size = UDim2.fromOffset(p.width, 0) },
		Config.RollEjectSec,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	close.Completed:Wait()
	p.panel:Destroy()

	-- Reset the tile: next price, interactive again.
	if t then
		t.setGreyed(false)
		t.icon.Visible = true
		t.name.Text = "NEW WEAPON"
		local sync = ClientState.sync
		if sync then
			t.setPrice(sync.prices.weapon)
			t.setAffordable(sync.cash >= sync.prices.weapon)
		end
		t.setEnabled(true)
	end
	spinning = false
end

function WeaponReel.press()
	if spinning then
		return
	end
	local t = tile()
	local sync = ClientState.sync
	if not t or not sync then
		return
	end
	if ClientState.downed or ClientState.inHub() then
		t.shake()
		UI.sound(Theme.Sounds.deny, 1, 0.4)
		return
	end
	if sync.cash < sync.prices.weapon then
		t.shake()
		UI.sound(Theme.Sounds.deny, 1, 0.4)
		HUD.get("toast")
			.show(string.format("NEED %s FOR A WEAPON", UI.fmtCash(sync.prices.weapon)), Theme.Colors.malus, 1)
		return
	end
	spinning = true
	t.setEnabled(false)
	local ok, result = pcall(function()
		return Remotes.BuyWeapon:InvokeServer()
	end)
	if not ok or not result or not result.ok then
		spinning = false
		t.setEnabled(true)
		t.shake()
		return
	end
	task.spawn(spin, result.weapon)
end

function WeaponReel.init()
	local function bind()
		local t = tile()
		if t then
			t.onPress = WeaponReel.press
		end
	end
	bind()
	HUD.Rebuilt:Connect(function()
		spinning = false
		bind()
	end)
end

return WeaponReel
