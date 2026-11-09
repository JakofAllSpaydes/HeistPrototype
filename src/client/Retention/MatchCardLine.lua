--!strict
-- Brief 10: the Create Match card's copy of the PLAY ribbon. While today's first run is still to come
-- (PlayRibbon.live), a line in the card's secondary style sits right under the Select Map row: PLAY A MATCH · DAILY
-- CRATE · ×2 XP. It hides for the rest of the fake day once a run reaches the summary.
local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local PlayRibbon = require(script.Parent:WaitForChild("PlayRibbon"))

local MatchCardLine = {}

local AMBER = Color3.fromHex("F2A93B")

-- `body` is the card's vertical list; the line takes `order` and everything at or after it steps down one.
function MatchCardLine.add(body: Instance, order: number): Frame
	local S = UI.S
	for _, c in body:GetChildren() do
		if c:IsA("GuiObject") and c.LayoutOrder >= order then
			c.LayoutOrder += 1
		end
	end
	local row = UI.frame({
		Name = "DailyLine",
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.new(1, 0, 0, S(28)),
		LayoutOrder = order,
		Parent = body,
	})
	UI.corner(row, S(4))
	UI.stroke(row, AMBER, S(1), 0.5)
	UI.text({
		Text = PlayRibbon.text(false),
		FontFace = Theme.Fonts.display,
		TextSize = S(15),
		TextColor3 = AMBER,
		Size = UDim2.fromScale(1, 1),
		Parent = row,
	})
	local function paint()
		row.Visible = PlayRibbon.live()
	end
	local conn = ClientState.Changed:Connect(paint)
	row.Destroying:Connect(function()
		conn:Disconnect()
	end)
	paint()
	return row
end

return MatchCardLine
