--!strict
-- Bottom-center: health bar with cur / max and the held weapon slot (icon, name, rarity pill, DMG + RATE).
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
		Position = UDim2.new(0.5, 0, 0, slotY),
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
	-- Right column: damage per shot over fire rate, the same two numbers the floor tags compare.
	local dmg = UI.text({
		Text = "DMG 22",
		TextSize = S(11),
		TextColor3 = Theme.Colors.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(8), 0, S(22)),
		Size = UDim2.fromOffset(S(90), S(16)),
		Parent = slot,
	})
	local rate = UI.text({
		Text = "RATE 4.0/s",
		TextSize = S(11),
		TextColor3 = Theme.Colors.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(8), 0, S(37)),
		Size = UDim2.fromOffset(S(90), S(16)),
		Parent = slot,
	})

	-- Health binding
	local maxHP = 100
	local function setHealth(cur: number, max: number)
		local frac = if max > 0 then math.clamp(cur / max, 0, 1) else 0
		fill.Size = UDim2.fromScale(frac, 1)
		fill.BackgroundColor3 = if frac < 0.3 then Theme.Colors.red else Theme.Colors.health
		healthText.Text = string.format("%d / %d", math.ceil(cur), math.round(max))
		if frac < 0.3 and frac > 0 then
			UI.punch(health, 1.08, 0.3)
		end
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

	-- Any DPS change (upgrade, swap, tradeoff) floats the delta off the slot.
	local lastDps = -1
	local function floatDps(delta: number)
		local up = delta > 0
		local label = UI.text({
			Text = string.format("%s%d DPS", if up then "+" else "", delta),
			Font = Theme.Fonts.display,
			TextSize = S(18),
			TextColor3 = if up then Theme.Colors.cash else Theme.Colors.malus,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -S(8), 0, S(4)),
			Size = UDim2.fromOffset(S(120), S(24)),
			ZIndex = 6,
			Parent = slot,
		})
		UI.stroke(label, Theme.Colors.black, S(1.5), 0.3)
		UI.punch(label, 1.5, 0.3)
		UI.tween(label, { Position = UDim2.new(1, -S(8), 0, -S(26)), TextTransparency = 1 }, 0.9, nil, nil, 0.3)
		task.delay(1.25, function()
			label:Destroy()
		end)
		dmg.TextColor3 = if up then Theme.Colors.cash else Theme.Colors.malus
		UI.punch(dmg, if up then 1.4 else 1.2, 0.35)
		UI.tween(dmg, { TextColor3 = Theme.Colors.text }, 0.8)
	end

	function component.update(sync: any)
		maxHP = sync.maxHP
		local held = sync.held
		local color = Rarity.color(held.rarity)
		name.Text = string.upper(held.displayName)
		pillLabel.Text = string.upper(held.rarityName)
		pill.BackgroundColor3 = color
		slotStroke.Color = color
		UI.recolorIcon(icon, color)
		local dps = math.round(held.dps or 0)
		if lastDps >= 0 and dps ~= lastDps then
			floatDps(dps - lastDps)
		end
		lastDps = dps
		dmg.Text = "DMG " .. UI.fmtDmg(held.dmg or 0, held.pellets or 1)
		rate.Text = "RATE " .. UI.fmtRate(held.fireRate or 0)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			setHealth(hum.Health, math.max(hum.MaxHealth, maxHP))
		end
	end

	function component.onJuice(juiceName: string, data: any)
		if juiceName == "Swap" then
			local tier = (data and data.rarity) or 1
			UI.punch(slot, 1.1 + tier * 0.04, 0.35)
			UI.sound(Theme.Sounds.swap, 0.8 + tier * 0.1, 0.5)
			slotStroke.Thickness = S(3 + tier)
			UI.tween(slotStroke, { Thickness = S(2) }, 0.4)
			if tier >= 3 then
				ClientState.Juice:Fire("Shake", { amp = 0.08 * tier, dur = 0.2 })
			end
		elseif juiceName == "UpgradeApplied" then
			UI.punch(slot, 1.1, 0.3)
			local statId = data and data.card and data.card.stat
			if statId == "Damage" or statId == "HeadshotMult" or statId == "CritChance" then
				dmg.TextColor3 = Theme.Colors.cash
				UI.punch(dmg, 1.5, 0.4)
				UI.tween(dmg, { TextColor3 = Theme.Colors.text }, 0.8)
			elseif statId == "FireRate" then
				rate.TextColor3 = Theme.Colors.cash
				UI.punch(rate, 1.5, 0.4)
				UI.tween(rate, { TextColor3 = Theme.Colors.text }, 0.8)
			end
		elseif juiceName == "PlayerHit" then
			UI.shake(health, S(2), 0.15)
		end
	end

	return component
end

return BottomCenter
