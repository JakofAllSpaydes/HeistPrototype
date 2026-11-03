--!strict
-- The New Weapon tile is the reel: spin, land, eject, reset. Nothing else appears on the HUD.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Weapons = require(Shared:WaitForChild("Weapons"))
local Rarity = require(Shared:WaitForChild("Rarity"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local HUD = require(script.Parent:WaitForChild("HUD"))

local WeaponReel = {}

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera :: Camera
local spinning = false

local function tile()
	local buy = HUD.get("buy")
	return buy and buy.tiles.weapon
end

local function feetScreenPos(): Vector2
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local p = camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
		return Vector2.new(p.X, p.Y)
	end
	return camera.ViewportSize / 2
end

local function legendaryRays(button: GuiObject)
	local S = UI.S
	local center = button.AbsolutePosition + button.AbsoluteSize / 2
	local gui = HUD.gui
	if not gui then
		return
	end
	local rays = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = UDim2.fromOffset(S(10), S(10)),
		ZIndex = 0,
		Parent = gui,
	})
	for i = 1, 10 do
		local ray = UI.frame({
			BackgroundColor3 = Theme.Colors.gold,
			BackgroundTransparency = 0.3,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(S(14), S(160)),
			Rotation = (i - 1) * 36,
			Parent = rays,
		})
		UI.tween(ray, { BackgroundTransparency = 1, Size = UDim2.fromOffset(S(4), S(260)) }, 0.6)
	end
	UI.tween(rays, { Rotation = 40 }, 0.6)
	task.delay(0.65, function()
		rays:Destroy()
	end)
end

local function spin(weapon: any)
	local t = tile()
	if not t then
		spinning = false
		return
	end
	local S = UI.S
	local well = t.well :: Frame
	local cellH = math.max(well.AbsoluteSize.Y, S(24))
	local cellW = math.max(well.AbsoluteSize.X, S(24))
	local N = 14
	t.icon.Visible = false
	t.name.Text = "ROLLING"
	t.stroke.Color = Theme.Colors.grey
	t.pricePill.Visible = false

	local column = UI.frame({
		Name = "Reel",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(cellW, cellH * N),
		Position = UDim2.fromOffset(0, 0),
		Parent = well,
	})
	for i = 1, N do
		local isLast = i == N
		local rarity = if isLast then weapon.rarity else math.random(1, 5)
		local cell = UI.frame({
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, (i - 1) * cellH),
			Size = UDim2.fromOffset(cellW, cellH),
			Parent = column,
		})
		local frame = UI.frame({
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -S(6), 1, -S(6)),
			Parent = cell,
		})
		UI.corner(frame, S(6))
		UI.stroke(frame, Rarity.color(rarity), S(2), if isLast then 0 else 0.35)
		local icon = UI.gunIcon(frame, Rarity.color(rarity), math.floor(cellH * 0.8))
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		if not isLast then
			for _, c in icon:GetChildren() do
				if c:IsA("Frame") then
					c.BackgroundTransparency = 0.35
				end
			end
		end
	end

	local travel = (N - 1) * cellH
	local tween = UI.tween(
		column,
		{ Position = UDim2.fromOffset(0, -travel) },
		Config.RollDurationSec,
		Enum.EasingStyle.Quart,
		Enum.EasingDirection.Out
	)
	local lastIdx = 0
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		if not column.Parent then
			conn:Disconnect()
			return
		end
		local idx = math.floor(-column.Position.Y.Offset / cellH + 0.5)
		if idx > lastIdx then
			lastIdx = idx
			UI.sound(Theme.Sounds.reelTick, 0.8 + (idx / N) * 0.9, 0.35)
		end
	end)
	tween.Completed:Wait()
	conn:Disconnect()
	if not column.Parent then
		spinning = false
		return
	end

	-- Land
	local color = Rarity.color(weapon.rarity)
	UI.punch(t.button, 1.06, 0.3)
	t.stroke.Color = color
	t.name.Text = string.format("%s\n%s", string.upper(weapon.displayName), string.upper(weapon.rarityName))
	UI.sound(Theme.Sounds.reelLand, 0.7 + weapon.rarity * 0.15, 0.6)
	if weapon.rarity == Rarity.Legendary then
		legendaryRays(t.button)
		UI.sound(Theme.Sounds.legendary, 1, 0.6)
	end
	task.wait(0.35)

	-- Eject: icon tweens out toward the player's feet and fades.
	local gui = HUD.gui
	if gui then
		local start = well.AbsolutePosition + well.AbsoluteSize / 2
		local ghost = UI.gunIcon(gui, color, math.floor(cellH * 0.9))
		ghost.AnchorPoint = Vector2.new(0.5, 0.5)
		ghost.Position = UDim2.fromOffset(start.X, start.Y)
		ghost.ZIndex = 20
		local feet = feetScreenPos()
		UI.tween(
			ghost,
			{ Position = UDim2.fromOffset(feet.X, feet.Y), Rotation = 90 },
			Config.RollEjectSec,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		for _, c in ghost:GetChildren() do
			if c:IsA("Frame") then
				UI.tween(
					c,
					{ BackgroundTransparency = 1 },
					Config.RollEjectSec,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				)
			end
		end
		task.delay(Config.RollEjectSec + 0.05, function()
			ghost:Destroy()
		end)
	end
	column:Destroy()
	t.setGreyed(true)
	task.wait(Config.RollEjectSec)

	-- Reset: next price, interactive again.
	t.setGreyed(false)
	t.icon.Visible = true
	t.name.Text = "NEW WEAPON"
	local sync = ClientState.sync
	if sync then
		t.setPrice(sync.prices.weapon)
		t.setAffordable(sync.cash >= sync.prices.weapon)
	end
	spinning = false
	t.setEnabled(true)
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
	-- Keep the pool warm for the reel cells so the first spin has icons to show.
	local _ = Weapons.List
end

return WeaponReel
