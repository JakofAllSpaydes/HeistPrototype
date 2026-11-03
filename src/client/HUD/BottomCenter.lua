--!strict
-- Bottom-center: health bar with cur / max, held weapon slot (icon, name, rarity pill, DMG), melee slot (V, stub).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ClientState = require(Client:WaitForChild("ClientState"))
local Rarity = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rarity"))

local BottomCenter = {}

function BottomCenter.build(gui: ScreenGui, track: (RBXScriptConnection) -> ())
	local S = UI.S
	local profile = if ClientState.isMobile then Theme.Mobile else Theme.Desktop
	local hw, hh = S(profile.health.X), S(profile.health.Y)
	local slotH = S(58)
	local root = UI.frame({
		Name = "BottomCenter",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(18)),
		Size = UDim2.fromOffset(S(360), hh + S(10) + slotH),
		Parent = gui,
	})

	-- Health
	local health = UI.frame({
		Name = "Health",
		BackgroundColor3 = Theme.Colors.panel2,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(hw, hh),
		Parent = root,
	})
	UI.corner(health, hh / 2)
	UI.stroke(health, Theme.Colors.black, S(1), 0.5)
	local fill = UI.frame({
		Name = "Fill",
		BackgroundColor3 = Theme.Colors.health,
		Size = UDim2.fromScale(1, 1),
		Parent = health,
	})
	UI.corner(fill, hh / 2)
	local healthText = UI.text({
		Text = "100 / 100",
		TextSize = math.max(9, hh - S(5)),
		TextColor3 = Theme.Colors.bg,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = health,
	})

	-- Weapon slot
	local slotY = hh + S(10)
	local slot = UI.frame({
		Name = "WeaponSlot",
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, -S(34), 0, slotY),
		Size = UDim2.fromOffset(S(220), slotH),
		Parent = root,
	})
	UI.corner(slot, S(10))
	local slotStroke = UI.stroke(slot, Theme.Colors.grey, S(2))
	local iconWell = UI.frame({
		BackgroundColor3 = Theme.Colors.panel2,
		Position = UDim2.fromOffset(S(6), S(6)),
		Size = UDim2.fromOffset(slotH - S(12), slotH - S(12)),
		Parent = slot,
	})
	UI.corner(iconWell, S(8))
	local icon = UI.gunIcon(iconWell, Theme.Colors.grey, slotH - S(14))
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	local name = UI.text({
		Text = "M1911",
		Font = Theme.Fonts.display,
		TextSize = S(18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(slotH + S(2), S(4)),
		Size = UDim2.new(1, -slotH, 0, S(24)),
		Parent = slot,
	})
	local pill, pillLabel = UI.pill(slot, "COMMON", Theme.Colors.grey, Theme.Colors.bg, S(16), S(10))
	pill.Position = UDim2.fromOffset(slotH + S(2), S(30))
	local dmg = UI.text({
		Text = "DMG 22",
		TextSize = S(12),
		TextColor3 = Theme.Colors.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(8), 0, S(30)),
		Size = UDim2.fromOffset(S(80), S(18)),
		Parent = slot,
	})

	-- Melee slot (stub)
	local melee = UI.button({
		Name = "MeleeSlot",
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0.5, S(82), 0, slotY),
		Size = UDim2.fromOffset(slotH, slotH),
		Parent = root,
	})
	UI.corner(melee, S(10))
	UI.stroke(melee, Theme.Colors.grey, S(2))
	local chip = UI.frame({
		BackgroundColor3 = Theme.Colors.panel2,
		Position = UDim2.fromOffset(-S(4), -S(6)),
		Size = UDim2.fromOffset(S(20), S(18)),
		ZIndex = 2,
		Parent = melee,
	})
	UI.corner(chip, S(5))
	UI.text({ Text = "V", TextSize = S(11), Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = chip })
	UI.text({
		Text = "MELEE",
		Font = Theme.Fonts.display,
		TextSize = S(11),
		TextColor3 = Theme.Colors.grey,
		Size = UDim2.new(1, 0, 0, S(16)),
		Position = UDim2.new(0, 0, 1, -S(18)),
		Parent = melee,
	})
	UI.text({
		Text = "/",
		Font = Theme.Fonts.display,
		TextSize = S(26),
		TextColor3 = Theme.Colors.grey,
		Size = UDim2.new(1, 0, 0, S(34)),
		Parent = melee,
	})
	local stubTip = UI.frame({
		BackgroundColor3 = Theme.Colors.panel2,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -S(10)),
		Size = UDim2.fromOffset(S(60), S(22)),
		Visible = false,
		ZIndex = 5,
		Parent = melee,
	})
	UI.corner(stubTip, S(6))
	UI.text({
		Text = "STUB",
		TextSize = S(11),
		TextColor3 = Theme.Colors.grey,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = stubTip,
	})
	melee.MouseEnter:Connect(function()
		stubTip.Visible = true
	end)
	melee.MouseLeave:Connect(function()
		stubTip.Visible = false
	end)
	melee.Activated:Connect(function()
		stubTip.Visible = true
		task.delay(1, function()
			stubTip.Visible = false
		end)
	end)

	-- Health binding
	local maxHP = 100
	local function setHealth(cur: number, max: number)
		local frac = if max > 0 then math.clamp(cur / max, 0, 1) else 0
		fill.Size = UDim2.fromScale(frac, 1)
		fill.BackgroundColor3 = if frac < 0.3 then Theme.Colors.red else Theme.Colors.health
		healthText.Text = string.format("%d / %d", math.ceil(cur), math.round(max))
	end
	local player = Players.LocalPlayer
	local humConn: RBXScriptConnection? = nil
	local function bindCharacter(char: Model)
		if humConn then
			humConn:Disconnect()
		end
		local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
		if not hum then
			return
		end
		humConn = hum.HealthChanged:Connect(function(h)
			setHealth(h, hum.MaxHealth)
		end)
		track(humConn :: RBXScriptConnection)
		setHealth(hum.Health, hum.MaxHealth)
	end
	track(player.CharacterAdded:Connect(bindCharacter))
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end

	local component = {}
	component.frame = root
	component.slot = slot

	function component.update(sync: any)
		maxHP = sync.maxHP
		local held = sync.held
		local color = Rarity.color(held.rarity)
		name.Text = string.upper(held.displayName)
		pillLabel.Text = string.upper(held.rarityName)
		pill.BackgroundColor3 = color
		slotStroke.Color = color
		UI.recolorIcon(icon, color)
		dmg.Text = string.format("DMG %d", math.round(held.dmg))
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			setHealth(hum.Health, math.max(hum.MaxHealth, maxHP))
		end
	end

	function component.onJuice(juiceName: string)
		if juiceName == "Swap" then
			UI.punch(slot, 1.12, 0.3)
			UI.sound(Theme.Sounds.swap, 1, 0.5)
		elseif juiceName == "PlayerHit" then
			UI.shake(health, S(2), 0.15)
		end
	end

	return component
end

return BottomCenter
