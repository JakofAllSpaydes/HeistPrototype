--!strict
-- Right column: header ABILITIES, three tiles for the equipped class's abilities (Q / E / Z) with live
-- cooldown sweeps. The tiles rebuild when the class in the sync changes. A running self buff shows its
-- seconds left on its tile with a gold pulse.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Classes = require(Shared:WaitForChild("Classes"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ClientState = require(Client:WaitForChild("ClientState"))
local Tile = require(script.Parent.Tile)

local AbilityColumn = {}

type CooldownUI = { sweep: Frame, label: TextLabel, chargePill: Frame, chargeLabel: TextLabel }

local HOTKEYS = { Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.Z }

function AbilityColumn.build(gui: ScreenGui, track: (RBXScriptConnection) -> ())
	local S = UI.S
	local profile = if ClientState.isMobile then Theme.Mobile else Theme.Desktop
	local root = UI.frame({
		Name = "AbilityColumn",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -S(20), 0.5, 0),
		Size = UDim2.fromOffset(S(profile.tile.X) + S(12), 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = gui,
	})
	UI.list(root, Enum.FillDirection.Vertical, S(profile.tilePad), Enum.HorizontalAlignment.Center)
	local header = UI.text({
		Text = "ABILITIES",
		Font = Theme.Fonts.display,
		TextSize = S(16),
		TextColor3 = Theme.Colors.grey,
		Size = UDim2.new(1, 0, 0, S(20)),
		LayoutOrder = 0,
		Parent = root,
	})

	local tiles: { [string]: Tile.Tile } = {}
	local order: { string } = {} -- ability ids in slot order (Q, E, Z)
	local cooldowns: { [string]: CooldownUI } = {}
	local classId = ""
	local abilities: { [string]: any } = {}

	local function use(id: string)
		local t = tiles[id]
		if not t then
			return
		end
		if ClientState.downed then
			t.shake()
			return
		end
		UI.punch(t.button, 0.9, 0.2)
		-- The cursor's floor point rides along: thrown abilities land there (up to ThrowMaxRange).
		local char = Players.LocalPlayer.Character
		local aim = if char then ClientState.cursorAimPoint(char) else nil
		Remotes.UseAbility:FireServer(id, aim)
	end

	local function rebuild(newClassId: string)
		classId = newClassId
		for _, t in tiles do
			t.button:Destroy()
		end
		tiles = {}
		order = {}
		cooldowns = {}
		local class = Classes.ById[classId] or Classes.ById[Classes.Default]
		header.Text = string.upper(class.name)
		header.TextColor3 = Color3.fromHex(class.color)
		for i, a in class.abilities do
			local t = Tile.build(
				root,
				{ name = string.upper(a.name), hotkey = a.hotkey, order = i, iconKind = a.icon },
				profile.tile,
				profile.hotkeyChips
			)
			t.setAffordable(true)
			tiles[a.id] = t
			order[i] = a.id
			-- Cooldown sweep: dark overlay that drains from the top, plus a seconds label.
			local sweep = UI.frame({
				Name = "Cooldown",
				BackgroundColor3 = Theme.Colors.black,
				BackgroundTransparency = 0.45,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.fromScale(1, 0),
				Visible = false,
				ZIndex = 4,
				Parent = t.button,
			})
			UI.corner(sweep, S(10))
			local label = UI.text({
				Text = "",
				Font = Theme.Fonts.display,
				TextSize = S(20),
				TextColor3 = Theme.Colors.text,
				Size = UDim2.fromScale(1, 1),
				Visible = false,
				ZIndex = 5,
				Parent = t.button,
			})
			UI.stroke(label, Theme.Colors.black, S(1.5), 0.3)
			-- Charges left (DOUBLE DOWN): a small gold count in the corner, only on multi-charge abilities.
			local chargePill, chargeLabel = UI.pill(t.button, "", Theme.Colors.gold, Theme.Colors.bg, S(16), S(10))
			chargePill.AnchorPoint = Vector2.new(1, 0)
			chargePill.Position = UDim2.new(1, -S(3), 0, S(3))
			chargePill.ZIndex = 6
			chargeLabel.ZIndex = 6
			chargePill.Visible = false
			cooldowns[a.id] = { sweep = sweep, label = label, chargePill = chargePill, chargeLabel = chargeLabel }
			t.onPress = function()
				use(a.id)
			end
		end
	end
	rebuild(Classes.Default)

	track(UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or ClientState.blocked() or ClientState.inHub() then
			return
		end
		for slot, key in HOTKEYS do
			if input.KeyCode == key and order[slot] then
				use(order[slot])
			end
		end
	end))

	local stimPulse = 0
	track(RunService.Heartbeat:Connect(function(dt)
		local now = ClientState.serverNow()
		for id, t in tiles do
			local a = abilities[id]
			local cd = cooldowns[id]
			if not a or not cd then
				continue
			end
			local maxCharges = tonumber(a.maxCharges) or 1
			cd.chargePill.Visible = maxCharges > 1
			if maxCharges > 1 then
				local text = string.format("x%d", tonumber(a.charges) or 0)
				if cd.chargeLabel.Text ~= text then
					cd.chargeLabel.Text = text
					UI.punch(cd.chargePill, 1.25, 0.2)
				end
			end
			local activeUntil = a.activeUntil or 0
			if activeUntil > now then
				-- Stim running: gold pulse, show seconds left.
				stimPulse += dt * 8
				t.stroke.Color = Theme.Colors.gold
				t.stroke.Thickness = S(2) + S(2) * (0.5 + 0.5 * math.sin(stimPulse))
				cd.sweep.Visible = false
				cd.label.Visible = true
				cd.label.TextColor3 = Theme.Colors.gold
				cd.label.Text = string.format("%ds", math.ceil(activeUntil - now))
				continue
			end
			local remaining = (a.cooldownEndsAt or 0) - now
			if remaining > 0 then
				local frac = math.clamp(remaining / math.max(a.cooldown or 1, 0.01), 0, 1)
				cd.sweep.Visible = true
				cd.sweep.Size = UDim2.fromScale(1, frac)
				cd.label.Visible = true
				cd.label.TextColor3 = Theme.Colors.text
				cd.label.Text = string.format("%ds", math.ceil(remaining))
				t.stroke.Color = Theme.Colors.grey
				t.stroke.Thickness = S(2)
			else
				if cd.sweep.Visible then
					-- Just came off cooldown: ready pop.
					UI.punch(t.button, 1.15, 0.3)
					UI.sound(Theme.Sounds.toast, 1.6, 0.35)
				end
				cd.sweep.Visible = false
				cd.label.Visible = false
				t.stroke.Color = Theme.Colors.gold
				t.stroke.Thickness = S(2)
			end
		end
	end))

	local component = {}
	component.frame = root

	function component.update(sync: any)
		if typeof(sync.classId) == "string" and sync.classId ~= classId then
			rebuild(sync.classId)
		end
		abilities = sync.abilities or {}
	end

	function component.onJuice(name: string, data: any)
		if name == "AbilityDenied" then
			local t = tiles[data.id]
			if t then
				t.shake()
				UI.sound(Theme.Sounds.deny, 1, 0.35)
			end
		elseif name == "StimStart" then
			-- Any self buff (stim, stim shot, dead eye): the tile that fired it pops.
			local t = tiles[data.id or "stim"]
			if t then
				UI.punch(t.button, 1.3, 0.4)
			end
			UI.sound(Theme.Sounds.legendary, 1.5, 0.5)
		end
	end

	return component
end

return AbilityColumn
