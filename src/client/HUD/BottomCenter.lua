--!strict
-- Bottom-center: health bar with cur / max and the held weapon slot (icon, name, rarity pill, DMG + RATE).
-- Downed: the bar becomes a red bleed bar counting down from BleedOutSec, SELF-REVIVE sits on its right,
-- and a green second fill mirrors a teammate's revive hold (`<NAME> IS REVIVING YOU`).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Weapons = require(Shared:WaitForChild("Weapons"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ModelIcon = require(Client:WaitForChild("UI"):WaitForChild("ModelIcon"))
local ClientState = require(Client:WaitForChild("ClientState"))

-- Brief 6: GET TOKENS opens the purchase sheet (required lazily: PurchaseSheet loads the store kit).
local function sheet(): any
	return require(Client:WaitForChild("PurchaseSheet") :: ModuleScript)
end

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
	local healthStroke = UI.stroke(health, Theme.Colors.black, S(1), 0.5)
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
		ZIndex = 3,
		Parent = health,
	})

	-- While downed: GIVE UP and SELF-REVIVE sit side by side above the bar.
	local btnH = hh + S(20) -- brief 6: room for the token line under the label
	local function downedButton(name: string, text: string, bg: Color3, anchorX: number, x: number): TextButton
		local b = UI.button({
			Name = name,
			Text = text,
			Font = Theme.Fonts.display,
			TextSize = S(13),
			TextColor3 = Theme.Colors.bg,
			BackgroundColor3 = bg,
			AnchorPoint = Vector2.new(anchorX, 1),
			Position = UDim2.new(0.5, x, 0, -S(8)),
			Size = UDim2.fromOffset(S(150), btnH),
			Visible = false,
			ZIndex = 3,
			Parent = root,
		})
		UI.corner(b, S(8))
		UI.stroke(b, Theme.Colors.black, S(1.5), 0.4)
		return b
	end
	local giveUpBtn = downedButton("GiveUp", "GIVE UP", Theme.Colors.red, 1, -S(5))
	giveUpBtn.TextColor3 = Theme.Colors.text
	giveUpBtn.Activated:Connect(function()
		UI.punch(giveUpBtn, 0.9, 0.15)
		Remotes.GiveUp:FireServer()
	end)
	local selfBtn = downedButton("SelfRevive", "SELF-REVIVE", Theme.Colors.cash, 0, S(5))
	-- Brief 6: SELF-REVIVE spends revive tokens on the press; the sub line shows the cost and the count, and at
	-- zero the button reads GET TOKENS and opens the purchase sheet on the 5-pack (the bleed keeps running).
	selfBtn.TextYAlignment = Enum.TextYAlignment.Top
	UI.pad(selfBtn, 0, S(4), 0, 0)
	local selfSub = UI.text({
		Text = "",
		Font = Theme.Fonts.body,
		TextSize = S(9),
		TextColor3 = Theme.Colors.bg,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -S(2)),
		Size = UDim2.new(1, 0, 0, S(11)),
		ZIndex = 4,
		Parent = selfBtn,
	})
	local tokens, selfCost = 0, 1
	selfBtn.Activated:Connect(function()
		UI.punch(selfBtn, 0.9, 0.15)
		if tokens < selfCost then
			sheet().open("tokens_5", {
				context = "downed GET TOKENS",
				note = "Out of revive tokens. The bleed keeps running.",
			})
			return
		end
		Remotes.SelfRevive:FireServer()
	end)
	-- The token chip beside the health bar (match HUD).
	local tokenChip = UI.frame({
		Name = "Tokens",
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, hw / 2 + S(8), 0, hh / 2),
		Size = UDim2.fromOffset(S(46), math.max(S(18), hh + S(4))),
		Parent = root,
	})
	UI.corner(tokenChip, S(6))
	UI.stroke(tokenChip, Color3.fromHex("3FD47A"), S(1.5), 0.2)
	local tokenDot = UI.frame({
		BackgroundColor3 = Color3.fromHex("3FD47A"),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, S(4), 0.5, 0),
		Size = UDim2.fromOffset(S(14), S(14)),
		Parent = tokenChip,
	})
	UI.corner(tokenDot, S(7))
	UI.text({
		Text = "+",
		Font = Theme.Fonts.display,
		TextSize = S(12),
		TextColor3 = Theme.Colors.white,
		Size = UDim2.fromScale(1, 1),
		Parent = tokenDot,
	})
	local tokenLabel = UI.text({
		Text = "0",
		Font = Theme.Fonts.display,
		TextSize = S(13),
		TextColor3 = Theme.Colors.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(22), 0),
		Size = UDim2.new(1, -S(24), 1, 0),
		Parent = tokenChip,
	})

	-- Brief 5: while a teammate holds the revive, a green second fill grows over the red bleed fill, mirroring
	-- their progress, and the bar reads `<NAME> IS REVIVING YOU`.
	local reviveFill = UI.frame({
		Name = "ReviveFill",
		BackgroundColor3 = Theme.Colors.cash,
		Size = UDim2.fromScale(0, 1),
		Visible = false,
		ZIndex = 2,
		Parent = health,
	})
	UI.corner(reviveFill, hh / 2)
	local reviveBy: string? = nil

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
	-- UI art pass: the held gun's real model (its rarity strips and wrap), swapped when the held gun changes.
	local icon = ModelIcon.weapon(iconWell, Weapons.Starter, UDim2.new(1, -S(4), 1, -S(4)), { pad = 0.04 })
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	local name = UI.text({
		Text = "M1911",
		RichText = true, -- Round 19e: the weapon type sits beside the name, smaller and dimmed
		Font = Theme.Fonts.display,
		TextSize = S(18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(slotH + S(2), S(4)),
		Size = UDim2.new(1, -slotH, 0, S(24)),
		Parent = slot,
	})
	local pill, pillLabel = UI.pill(slot, "COMMON", Theme.Colors.grey, Theme.Colors.bg, S(16), S(10))
	pill.Position = UDim2.fromOffset(slotH + S(2), S(30))
	-- Armory level beside the rarity; SIDEARM (red) replaces it while downed with the pistol.
	local levelPill, levelLabel = UI.pill(slot, "LV 0", Theme.Colors.panel2, Theme.Colors.gold, S(16), S(10))
	levelPill.Position = UDim2.fromOffset(slotH + S(74), S(30))
	levelPill.Visible = false
	local sidearmPill, _sidearmLabel = UI.pill(slot, "SIDEARM", Theme.Colors.red, Theme.Colors.text, S(16), S(10))
	sidearmPill.Position = UDim2.fromOffset(slotH + S(74), S(30))
	sidearmPill.Visible = false
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
	local bleeding = false
	local bleedEndsAt = 0
	local lastBleedShown = -1
	local function setHealth(cur: number, max: number)
		if bleeding then
			return
		end
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

	-- Bleed countdown.
	local nudgeAt = 0
	track(RunService.Heartbeat:Connect(function()
		if not bleeding then
			return
		end
		local remaining = math.max(0, bleedEndsAt - ClientState.serverNow())
		-- Upsell nudge: downed with no tokens and little bleed left, GET TOKENS pulses (never a popup).
		if tokens < selfCost and remaining <= Config.TokenNudgeSec and os.clock() >= nudgeAt then
			nudgeAt = os.clock() + 0.9
			UI.punch(selfBtn, 1.15, 0.45)
		end
		fill.Size = UDim2.fromScale(math.clamp(remaining / math.max(Config.BleedOutSec, 0.1), 0, 1), 1)
		local shown = math.ceil(remaining)
		local by = reviveBy
		if by then
			healthText.Text = string.format("%s IS REVIVING YOU", string.upper(by))
			lastBleedShown = -1
		elseif shown ~= lastBleedShown then
			lastBleedShown = shown
			healthText.Text = string.format("DOWNED · %ds", shown)
			UI.punch(health, if shown <= 5 then 1.1 else 1.03, 0.2)
		end
	end))

	local component = {}
	component.frame = root
	component.slot = slot

	local selfRevives = 0
	local function paintSelf()
		if tokens < selfCost then
			selfBtn.Text = "GET TOKENS"
			selfBtn.BackgroundColor3 = Theme.Colors.gold
			selfSub.Text = string.format("%d TOKENS · TAP TO BUY", tokens)
		else
			selfBtn.Text = "SELF-REVIVE"
			selfBtn.BackgroundColor3 = Theme.Colors.cash
			selfSub.Text =
				string.format("%d TOKEN%s · YOU HAVE %d", selfCost, if selfCost == 1 then "" else "S", tokens)
		end
		local _ = selfRevives
	end

	function component.setDowned(endsAt: number, used: number?)
		bleeding = true
		bleedEndsAt = endsAt
		lastBleedShown = -1
		selfRevives = used or selfRevives
		fill.BackgroundColor3 = Theme.Colors.red
		fill.Size = UDim2.fromScale(1, 1)
		healthText.TextColor3 = Theme.Colors.text
		healthStroke.Color = Theme.Colors.red
		healthStroke.Transparency = 0
		paintSelf()
		selfBtn.Visible = true
		giveUpBtn.Visible = true
		UI.punch(selfBtn, 1.2, 0.4)
		UI.punch(giveUpBtn, 1.2, 0.4)
		UI.punch(health, 1.15, 0.4)
	end

	function component.clearDowned()
		if not bleeding then
			return
		end
		bleeding = false
		selfBtn.Visible = false
		giveUpBtn.Visible = false
		reviveFill.Visible = false
		reviveFill.Size = UDim2.fromScale(0, 1)
		reviveBy = nil
		healthText.TextColor3 = Theme.Colors.bg
		healthStroke.Color = Theme.Colors.black
		healthStroke.Transparency = 0.5
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			setHealth(hum.Health, math.max(hum.MaxHealth, maxHP))
		end
		UI.punch(health, 1.2, 0.4)
	end

	-- The server moved the bleed end time (a revive hold pauses it).
	function component.setBleedEndsAt(endsAt: number)
		if bleeding then
			bleedEndsAt = endsAt
		end
	end

	-- A teammate's revive hold on this player: the green fill follows their progress; 0 snaps it back.
	function component.setReviveProgress(progress: number, reviver: string?)
		if progress <= 0 then
			reviveBy = nil
			if reviveFill.Visible then
				reviveFill.Visible = false
				reviveFill.Size = UDim2.fromScale(0, 1)
			end
			return
		end
		if not reviveFill.Visible then
			reviveFill.Visible = true
			UI.punch(health, 1.12, 0.25)
		end
		reviveBy = reviver
		UI.tween(reviveFill, { Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1) }, 0.1, Enum.EasingStyle.Linear)
	end

	-- Revived: a green pulse on the bar.
	function component.revivePulse()
		local flash = UI.frame({
			BackgroundColor3 = Theme.Colors.cash,
			BackgroundTransparency = 0.1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
			Parent = health,
		})
		UI.corner(flash, hh / 2)
		UI.tween(flash, { BackgroundTransparency = 1, Size = UDim2.new(1, S(40), 1, S(16)) }, 0.5)
		task.delay(0.55, function()
			flash:Destroy()
		end)
	end

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
		local kind = if typeof(held.archetype) == "string" then string.upper(held.archetype) else ""
		name.Text = if kind ~= ""
			then string.format(
				'%s <font size="%d" color="#%s">%s</font>',
				string.upper(held.displayName),
				S(11),
				Theme.Colors.textDim:ToHex(),
				kind
			)
			else string.upper(held.displayName)
		pill.BackgroundColor3 = color
		slotStroke.Color = color
		iconWell.BackgroundColor3 = Theme.Colors.panel2:Lerp(color, Config.ModelIconWellTint)
		if typeof(held.weaponId) == "string" then
			ModelIcon.setWeapon(icon, held.weaponId, {
				rarity = held.rarity,
				wrapColor = if held.wrapColor then tostring(held.wrapColor) else nil,
			})
		end
		local dps = math.round(held.dps or 0)
		if lastDps >= 0 and dps ~= lastDps then
			floatDps(dps - lastDps)
		end
		lastDps = dps
		dmg.Text = "DMG " .. UI.fmtDmg(held.dmg or 0, held.pellets or 1)
		rate.Text = "RATE " .. UI.fmtRate(held.displayRate or held.fireRate or 0)
		pillLabel.Text = string.upper(held.rarityName)
		local level = tonumber(held.level) or 0
		levelLabel.Text = string.format("LV %d", level)
		sidearmPill.Visible = held.sidearm == true
		levelPill.Visible = not sidearmPill.Visible and level > 0
		local profile = sync.profile
		local t = if profile and typeof(profile.reviveTokens) == "number" then profile.reviveTokens else 0
		local cost = if sync.revive and typeof(sync.revive.selfCost) == "number" then sync.revive.selfCost else 1
		if
			t ~= tokens
			or cost ~= selfCost
			or (typeof(sync.selfRevives) == "number" and sync.selfRevives ~= selfRevives)
		then
			if t > tokens then
				UI.punch(tokenChip, 1.3, 0.35)
				if bleeding then
					UI.punch(selfBtn, 1.2, 0.4) -- bought while downed: the button is armed again
				end
			end
			tokens, selfCost = t, cost
			selfRevives = tonumber(sync.selfRevives) or selfRevives
			tokenLabel.Text = tostring(tokens)
			paintSelf()
		end
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
