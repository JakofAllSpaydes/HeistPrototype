--!strict
-- Brief 13: the debug panel's HEIST group (the pre-heist, markers, dressing, relics). DebugPanel hands over its
-- row / button helpers; the server half is server/Run/HeistDebug.lua.
local Client = script.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local TierMarkers = require(Client:WaitForChild("TierMarkers"))
local Relics = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Relics"))

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
	-- Step 4: the street dressing at a stage (0..3, BOSS = stage 3 + the boss pieces) and the helicopter.
	local r2 = h.row(panel, 31.2, h.rh)
	for _, n in { 0, 1, 2, 3, 4 } do
		local b = h.btn(r2, if n == 4 then "BOSS" else "Stage " .. n, 0.2, function()
			h.send("DressingStage", n)
		end, Theme.Colors.malus)
		b.TextSize = S(9)
	end
	local r3 = h.row(panel, 31.3, h.rh)
	h.btn(r3, "Heli on / off", 1, function()
		h.send("HeliToggle")
	end, Theme.Colors.malus)
	-- Step 5: relics.
	local r4 = h.row(panel, 31.4, h.rh)
	h.btn(r4, "Force relic drop", 0.5, function()
		h.send("ForceRelic")
	end, Theme.Colors.gold)
	h.btn(r4, "Force first crate", 0.5, function()
		h.send("ForceFirstCrate")
	end, Theme.Colors.gold)
	local r5 = h.row(panel, 31.5, h.rh)
	local ids = {}
	for _, r in Relics.List do
		table.insert(ids, r.id)
	end
	local pickIndex = 1
	local pick: TextButton
	pick = h.btn(r5, "Relic: " .. (ids[1] or "-"), 0.5, function()
		pickIndex = pickIndex % math.max(#ids, 1) + 1
		pick.Text = "Relic: " .. (ids[pickIndex] or "-")
	end, Theme.Colors.grey)
	pick.TextSize = S(9)
	h.btn(r5, "Grant relic", 0.25, function()
		h.send("GrantRelic", ids[pickIndex])
	end, Theme.Colors.gold)
	h.btn(r5, "Reset relics", 0.25, function()
		h.send("ResetRelics")
	end, Theme.Colors.malus)
end

return HeistDebug
