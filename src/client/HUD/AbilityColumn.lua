--!strict
-- Right column: header ABILITIES, tiles Auto Turret (Q), Barricade (E), Stim (Z) with live cooldown sweeps.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ClientState = require(Client:WaitForChild("ClientState"))
local Tile = require(script.Parent.Tile)

local AbilityColumn = {}

type CooldownUI = { sweep: Frame, label: TextLabel }

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
	UI.text({
		Text = "ABILITIES",
		Font = Theme.Fonts.display,
		TextSize = S(16),
		TextColor3 = Theme.Colors.grey,
		Size = UDim2.new(1, 0, 0, S(20)),
		LayoutOrder = 0,
		Parent = root,
	})

	local tiles = {
		turret = Tile.build(
			root,
			{ name = "AUTO TURRET", hotkey = "Q", order = 1, iconKind = "turret" },
			profile.tile,
			profile.hotkeyChips
		),
		barricade = Tile.build(
			root,
			{ name = "BARRICADE", hotkey = "E", order = 2, iconKind = "wall" },
			profile.tile,
			profile.hotkeyChips
		),
		stim = Tile.build(
			root,
			{ name = "STIM", hotkey = "Z", order = 3, iconKind = "stim" },
			profile.tile,
			profile.hotkeyChips
		),
	}
	for _, t in tiles do
		t.setAffordable(true)
	end

	-- Cooldown sweep: dark overlay that drains from the top, plus a seconds label.
	local cooldowns: { [string]: CooldownUI } = {}
	for id, t in tiles do
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
		cooldowns[id] = { sweep = sweep, label = label }
	end

	local function use(id: string)
		local t = tiles[id]
		if ClientState.downed then
			t.shake()
			return
		end
		UI.punch(t.button, 0.9, 0.2)
		Remotes.UseAbility:FireServer(id)
	end
	for id, t in tiles do
		t.onPress = function()
			use(id)
		end
	end

	track(UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		local id = if input.KeyCode == Enum.KeyCode.Q
			then "turret"
			elseif input.KeyCode == Enum.KeyCode.E then "barricade"
			elseif input.KeyCode == Enum.KeyCode.Z then "stim"
			else nil
		if id then
			use(id)
		end
	end))

	local abilities: { [string]: any } = {}
	local stimPulse = 0
	track(RunService.Heartbeat:Connect(function(dt)
		local now = ClientState.serverNow()
		for id, t in tiles do
			local a = abilities[id]
			local cd = cooldowns[id]
			if not a then
				continue
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
	component.tiles = tiles

	function component.update(sync: any)
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
			UI.punch(tiles.stim.button, 1.3, 0.4)
			UI.sound(Theme.Sounds.legendary, 1.5, 0.5)
		end
	end

	return component
end

return AbilityColumn
