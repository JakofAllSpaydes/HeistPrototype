--!strict
-- Brief 13: the debug panel's HEIST group (the pre-heist, markers, dressing, relics). DebugPanel hands over its
-- row / button helpers; the server half is server/Run/HeistDebug.lua.
local Client = script.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local TierMarkers = require(Client:WaitForChild("TierMarkers"))

local HeistDebug = {}

export type Helpers = {
	row: (Instance, number, number) -> Frame,
	btn: (Instance, string, number, () -> (), Color3?) -> TextButton,
	send: (string, any?) -> (),
	rh: number,
}

function HeistDebug.build(panel: Instance, h: Helpers)
	local S = UI.S
	UI.text({
		Text = "HEIST",
		FontFace = Theme.Fonts.display,
		TextSize = S(12),
		TextColor3 = Theme.Colors.amber,
		Size = UDim2.new(1, 0, 0, S(16)),
		LayoutOrder = 31,
		Parent = panel,
	})
	local r1 = h.row(panel, 31.1, h.rh)
	h.btn(r1, "Breach now", 0.5, function()
		h.send("BreachNow")
	end, Theme.Colors.red)
	-- Step 3: the tier, range and cap decision over every marker (local only).
	local markerBtn: TextButton
	markerBtn = h.btn(r1, if TierMarkers.debugEnabled() then "Marker debug ON" else "Marker debug", 0.5, function()
		TierMarkers.setDebug(not TierMarkers.debugEnabled())
		markerBtn.Text = if TierMarkers.debugEnabled() then "Marker debug ON" else "Marker debug"
		markerBtn.TextColor3 = if TierMarkers.debugEnabled() then Theme.Colors.gold else Theme.Colors.text
	end, Theme.Colors.blue)
end

return HeistDebug
