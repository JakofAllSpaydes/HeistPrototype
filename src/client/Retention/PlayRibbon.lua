--!strict
-- Brief 10 / Round 27e: "your first match today" surfaced on PLAY and on the Create Match card. While today's first
-- run is still to come (the fake day of the last summary, profile.lastHeistDay, is not today: the FIRST HEIST OF THE
-- DAY x2 XP and the daily crate's unlock share it), an urgent amber bar reads PLAY A MATCH · DAILY CRATE · ×2 XP
-- (phone, under PLAY: DAILY CRATE · ×2 XP). Round 27e: it sits under PLAY (not over its top edge) and is built to be
-- impossible to miss: a bright amber gradient with dark condensed caps and the crate pictogram, a pulsing amber glow,
-- a light sweep and a slow breath. It goes for the rest of the fake day once a run reaches the summary. Each player
-- reads their own profile, so in a party only the member who has not run today sees it. Off with DailyCrateEnabled.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Clock = require(Shared:WaitForChild("Clock"))

local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Icons = require(Client:WaitForChild("UI"):WaitForChild("Icons"))
local Fx = require(Client:WaitForChild("Store"):WaitForChild("Fx"))

local PlayRibbon = {}

local AMBER = Color3.fromHex("F2A93B")
local INK = Color3.fromHex("10142A")

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

-- The urgent bar in a holder of `size` (the holder carries the glow and the breath; the bar clips the sweep).
function PlayRibbon.build(parent: Instance, size: UDim2, text: string, textSize: number, z: number): Frame
	local S = UI.S
	local holder = UI.frame({
		Name = "DailyRibbon",
		BackgroundTransparency = 1,
		Size = size,
		ZIndex = z,
		Parent = parent,
	})
	local glow, setGlow = Fx.glow(holder, AMBER, S(4), z)
	glow.ZIndex = z
	Fx.pulse(setGlow, function()
		return holder.Parent ~= nil
	end, 1.1, 0.6, 1.8)
	local bar = UI.frame({
		Name = "Bar",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 1,
		Parent = holder,
	})
	UI.corner(bar, S(4))
	UI.stroke(bar, INK, S(1.5), 0)
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromHex("FFD86A"), Color3.fromHex("F29A1E")),
		Rotation = 90,
		Parent = bar,
	})
	-- Round 27g: the icon and words sit in their own row; the light sweep is the bar's child outside any layout (inside
	-- the bar's list it was laid out as a fixed block on the left and pushed the words right).
	local content = UI.frame({
		Name = "Content",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 2,
		Parent = bar,
	})
	local layout = UI.list(
		content,
		Enum.FillDirection.Horizontal,
		S(8),
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Center
	)
	local h = bar.AbsoluteSize.Y
	local iconSize = math.max(S(16), math.floor(textSize * 1.25))
	if h > 0 then
		iconSize = math.min(iconSize, math.floor(h * 0.8))
	end
	local icon = Icons.draw(content, "crate", iconSize, INK, Color3.fromHex("8A5A12"))
	icon.LayoutOrder = 1
	icon.ZIndex = z + 2
	local label = UI.text({
		Text = text,
		FontFace = Theme.Fonts.display,
		TextSize = textSize,
		TextColor3 = INK,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 2,
		ZIndex = z + 2,
		Parent = content,
	})
	local _ = label
	-- Round 27h: on a narrow bar (under PLAY) the icon and words shrink about the centre to fit.
	local fit = UI.new("UIScale", { Name = "Fit", Parent = content }) :: UIScale
	local function refit()
		local k = fit.Scale
		local natural = layout.AbsoluteContentSize.X / math.max(k, 0.01)
		local room = bar.AbsoluteSize.X - S(18)
		if natural > 0 and room > 0 then
			local want = math.clamp(room / natural, 0.4, 1)
			if math.abs(want - k) > 0.01 then
				fit.Scale = want
			end
		end
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refit)
	bar:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	task.defer(refit)
	Fx.shine(bar, 1.8)
	-- A slow breath so it draws the eye even when nothing else moves.
	local breath = UI.new("UIScale", { Parent = holder }) :: UIScale
	task.spawn(function()
		local t0 = os.clock()
		while holder.Parent do
			breath.Scale = 1 + (math.sin((os.clock() - t0) * 3.2) + 1) * 0.02
			task.wait()
		end
	end)
	return holder
end

-- Puts the bar under PLAY and keeps it current (profile syncs, and a fake day turning while you stand there).
-- Round 27h: as wide as PLAY itself, and a tap on it is a tap on PLAY (`onTap`).
function PlayRibbon.attach(play: GuiObject, onTap: (() -> ())?): Frame
	local S = UI.S
	local mobile = ClientState.isMobile
	local holder = PlayRibbon.build(
		play,
		UDim2.fromOffset(S(if mobile then 200 else 280), S(if mobile then 26 else 32)),
		PlayRibbon.text(mobile),
		S(if mobile then 15 else 18),
		play.ZIndex + 2
	)
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 1, S(10))
	holder.Visible = false
	if onTap then
		local hit = UI.button({
			Name = "Tap",
			Text = "",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = play.ZIndex + 10,
			Parent = holder,
		})
		hit.Activated:Connect(function()
			local bar = holder:FindFirstChild("Bar")
			if bar and bar:IsA("GuiObject") then
				UI.punch(bar, 0.94, 0.2)
			end
			onTap()
		end)
	end
	local function paint()
		holder.Visible = PlayRibbon.live()
	end
	ClientState.Changed:Connect(paint)
	task.spawn(function()
		while holder.Parent do
			paint()
			task.wait(1)
		end
	end)
	paint()
	return holder
end

return PlayRibbon
