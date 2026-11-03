--!strict
-- Top-right stack above the ability column: persistent pills (the Side Job timer) live here so the
-- center of the screen stays clear.
local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))

local TopRight = {}

function TopRight.build(gui: ScreenGui, _track: (RBXScriptConnection) -> ())
	local S = UI.S
	local width = S(320)
	local root = UI.frame({
		Name = "TopRight",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(20), 0, S(20)),
		Size = UDim2.fromOffset(width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = gui,
	})
	UI.list(root, Enum.FillDirection.Vertical, S(6), Enum.HorizontalAlignment.Right)

	local component = {}
	component.frame = root
	component.width = width

	function component.add(frame: GuiObject, order: number)
		frame.LayoutOrder = order
		frame.Parent = root
	end

	return component
end

return TopRight
