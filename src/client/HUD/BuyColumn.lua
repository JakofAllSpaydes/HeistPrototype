--!strict
-- Left column: header BUY and the UPGRADE tile (2). Weapons come only from crates (brief 5).
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ClientState = require(Client:WaitForChild("ClientState"))
local Tile = require(script.Parent.Tile)

local BuyColumn = {}

function BuyColumn.build(gui: ScreenGui, track: (RBXScriptConnection) -> ())
	local S = UI.S
	local profile = if ClientState.isMobile then Theme.Mobile else Theme.Desktop
	local root = UI.frame({
		Name = "BuyColumn",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, S(20), 0.5, 0),
		Size = UDim2.fromOffset(S(profile.tile.X) + S(12), 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = gui,
	})
	UI.mobileGrow(root, ClientState.isMobile) -- Round 24
	UI.list(root, Enum.FillDirection.Vertical, S(profile.tilePad), Enum.HorizontalAlignment.Center)
	UI.text({
		Text = "BUY",
		FontFace = Theme.Fonts.display,
		TextSize = S(20),
		TextColor3 = Theme.Colors.grey,
		Size = UDim2.new(1, 0, 0, S(26)),
		LayoutOrder = 0,
		Parent = root,
	})

	local tiles = {
		upgrade = Tile.build(
			root,
			{ name = "UPGRADE", hotkey = "2", action = "upgrade", order = 1, iconKind = "plus", showPrice = true },
			profile.tile,
			profile.hotkeyChips
		),
	}

	track(UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or ClientState.inHub() then
			return
		end
		-- Round 21: 1 switches guns now (Gun.client), so UPGRADE moved to 2.
		local tile = if input.KeyCode == Enum.KeyCode.Two then tiles.upgrade else nil
		if tile and tile.enabled and tile.onPress then
			tile.onPress()
		end
	end))
	-- Brief 11: D-pad up on a pad (Input.lua).
	track(ClientState.Juice:Connect(function(name: string)
		local tile = tiles.upgrade
		if name == "PadUpgrade" and not ClientState.inHub() and tile.enabled and tile.onPress then
			tile.onPress()
		end
	end))

	local component = {}
	component.frame = root
	component.tiles = tiles

	function component.update(sync: any)
		tiles.upgrade.setPrice(sync.prices.upgrade)
		tiles.upgrade.setAffordable(sync.cash >= sync.prices.upgrade)
	end

	return component
end

return BuyColumn
