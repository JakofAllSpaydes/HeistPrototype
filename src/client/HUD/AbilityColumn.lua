--!strict
-- Right column: header ABILITIES, inert tiles Auto Turret (Q), Barricade (E), Explosive (Z, cooldown stub).
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ClientState = require(Client:WaitForChild("ClientState"))
local Tile = require(script.Parent.Tile)

local AbilityColumn = {}

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
			{ name = "AUTO TURRET", hotkey = "Q", order = 1, iconKind = "turret", stub = true },
			profile.tile,
			profile.hotkeyChips
		),
		barricade = Tile.build(
			root,
			{ name = "BARRICADE", hotkey = "E", order = 2, iconKind = "wall", stub = true },
			profile.tile,
			profile.hotkeyChips
		),
		explosive = Tile.build(
			root,
			{ name = "EXPLOSIVE", hotkey = "Z", order = 3, iconKind = "boom", stub = true },
			profile.tile,
			profile.hotkeyChips
		),
	}

	-- Visual cooldown stub on Z: dark sweep from the bottom plus a seconds label.
	local cd = UI.frame({
		Name = "Cooldown",
		BackgroundColor3 = Theme.Colors.black,
		BackgroundTransparency = 0.45,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.6),
		ZIndex = 2,
		Parent = tiles.explosive.button,
	})
	UI.corner(cd, S(10))
	UI.text({
		Text = "12s",
		Font = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.text,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = cd,
	})

	track(UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		local tile = if input.KeyCode == Enum.KeyCode.Q
			then tiles.turret
			elseif input.KeyCode == Enum.KeyCode.E then tiles.barricade
			elseif input.KeyCode == Enum.KeyCode.Z then tiles.explosive
			else nil
		if tile then
			tile.showTooltip("STUB")
			UI.punch(tile.button, 0.96, 0.15)
		end
	end))

	return { frame = root, tiles = tiles }
end

return AbilityColumn
