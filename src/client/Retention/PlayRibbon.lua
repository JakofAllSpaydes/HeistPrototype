--!strict
-- Brief 10: "your first match today" surfaced on PLAY. While today's first run is still to come (the fake day of the
-- last summary, profile.lastHeistDay, is not today: the FIRST HEIST OF THE DAY x2 XP and the daily crate's unlock
-- share it), a thin amber ribbon across PLAY's top edge reads PLAY A MATCH · DAILY CRATE · ×2 XP (phone: DAILY CRATE
-- · ×2 XP). It goes for the rest of the fake day once a run reaches the summary. Each player reads their own profile,
-- so in a party only the member who has not run today sees it. Off with DailyCrateEnabled.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Clock = require(Shared:WaitForChild("Clock"))

local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))

local PlayRibbon = {}

local AMBER = Color3.fromHex("F2A93B")

-- The line is live: the day's first run is still to come.
function PlayRibbon.live(): boolean
	if not Config.DailyCrateEnabled then
		return false
	end
	local sync = ClientState.sync
	local p = sync and (sync :: any).profile
	if not p then
		return false
	end
	return (tonumber(p.lastHeistDay) or 0) ~= Clock.day(ClientState.fakeNow())
end

function PlayRibbon.text(short: boolean): string
	return if short then "DAILY CRATE · ×2 XP" else "PLAY A MATCH · DAILY CRATE · ×2 XP"
end

-- Puts the ribbon on PLAY and keeps it current (profile syncs, and a fake day turning while you stand there).
function PlayRibbon.attach(play: GuiObject)
	local S = UI.S
	local mobile = ClientState.isMobile
	local ribbon = UI.text({
		Name = "DailyRibbon",
		Text = PlayRibbon.text(mobile),
		FontFace = Theme.Fonts.display,
		TextSize = S(if mobile then 13 else 15),
		TextColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0,
		BackgroundColor3 = AMBER,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(1, S(if mobile then 24 else 40), 0, S(if mobile then 18 else 21)),
		ZIndex = play.ZIndex + 2,
		Visible = false,
		Parent = play,
	})
	UI.corner(ribbon, S(3))
	UI.stroke(ribbon, Theme.Colors.black, S(1.5), 0.35)
	local function paint()
		ribbon.Visible = PlayRibbon.live()
	end
	ClientState.Changed:Connect(paint)
	task.spawn(function()
		while ribbon.Parent do
			paint()
			task.wait(1)
		end
	end)
	paint()
	return ribbon
end

return PlayRibbon
