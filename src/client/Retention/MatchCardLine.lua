--!strict
-- Brief 10 / Round 27e: the Create Match card's copy of the PLAY bar. While today's first run is still to come
-- (PlayRibbon.live), the same glowing amber bar (PlayRibbon.build) sits right under the Select Map row: PLAY A
-- MATCH · DAILY CRATE · ×2 XP. It hides for the rest of the fake day once a run reaches the summary.
local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local PlayRibbon = require(script.Parent:WaitForChild("PlayRibbon"))

local MatchCardLine = {}

-- `body` is the card's vertical list; the line takes `order` and everything at or after it steps down one.
function MatchCardLine.add(body: Instance, order: number): Frame
	local S = UI.S
	for _, c in body:GetChildren() do
		if c:IsA("GuiObject") and c.LayoutOrder >= order then
			c.LayoutOrder += 1
		end
	end
	-- Round 27e: the same urgent glowing bar as under PLAY (a holder with room round it for the glow).
	local row = UI.frame({
		Name = "DailyLine",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(40)),
		LayoutOrder = order,
		Parent = body,
	})
	local bar = PlayRibbon.build(row, UDim2.new(1, -S(8), 0, S(32)), PlayRibbon.text(false), S(18), 3)
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(0.5, 0.5)
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
