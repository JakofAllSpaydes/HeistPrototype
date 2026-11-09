--!strict
-- Round 27c: the run summary tells you the daily crate just unlocked. When this run unlocked it (the server's Juice
-- "DailyUnlocked" at the summary write), a card slides in on the left of the summary a beat after the panel lands
-- (top and bottom belong to the level and pass bars): the crate in its tier colours, DAILY CRATE / UNLOCKED, and
-- TAP TO OPEN. Tapping it is TO LOBBY, and once you land the podium sheet opens by itself
-- (DailyCrateArrivalOpenSec; MARLOW's nudge stays quiet). Not tapped: the hub's guide and nudge take over.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Crates = require(Shared:WaitForChild("Crates"))

local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Store = Client:WaitForChild("Store")
local Fx = require(Store:WaitForChild("Fx"))
local ItemArt = require(Store:WaitForChild("ItemArt"))

local SummaryCrateCard = {}

local player = Players.LocalPlayer
local GREEN = Color3.fromHex("2FB75A")

local pendingTier: string? = nil -- this run unlocked the crate (tier)
local beganAt: number? = nil -- os.clock of RunEndBegin
local gui: ScreenGui? = nil
local token = 0

local function destroy()
	token += 1
	local g = gui
	gui = nil
	if g then
		g:Destroy()
	end
end

local function show(tierId: string)
	destroy()
	local my = token
	local S = UI.S
	local mobile = ClientState.isMobile
	local function T(n: number): number
		return if mobile then math.round(S(n) * (Config.MobileStoreTextScale or 1)) else S(n)
	end
	local def = (Config.DailyCrateTierOdds :: any)[tierId] or (Config.DailyCrateTierOdds :: any).basic
	local trim = Color3.fromHex(def.trim)
	local g = UI.new("ScreenGui", {
		Name = "SummaryCrateCard",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 13, -- over the summary (12)
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	gui = g
	local w = S(if mobile then 170 else 210)
	local art = math.floor(w * 0.62)
	local h = S(12) + T(26) + T(20) + S(4) + art + S(8) + T(40) + S(12)
	local card = UI.button({
		Name = "Card",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromHex("121216"),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, S(20), 0.5, S(30)),
		Size = UDim2.fromOffset(w, h),
		ZIndex = 5,
		Parent = g,
	})
	UI.corner(card, S(6))
	UI.stroke(card, trim, S(2), 0)
	local glow, setGlow = Fx.glow(card, trim, S(6), 4)
	glow.ZIndex = 4
	Fx.pulse(setGlow, function()
		return token == my and card.Parent ~= nil
	end, 1.3, 0.7, 1.7)
	local header = UI.text({
		Text = "DAILY CRATE",
		FontFace = Theme.Fonts.display,
		TextSize = T(24),
		TextColor3 = trim,
		Position = UDim2.fromOffset(0, S(12)),
		Size = UDim2.new(1, 0, 0, T(26)),
		ZIndex = 6,
		Parent = card,
	})
	local _ = header
	UI.text({
		Text = "UNLOCKED",
		FontFace = Theme.Fonts.display,
		TextSize = T(18),
		TextColor3 = Theme.Colors.health,
		Position = UDim2.fromOffset(0, S(12) + T(26)),
		Size = UDim2.new(1, 0, 0, T(20)),
		ZIndex = 6,
		Parent = card,
	})
	local rays = Fx.rays(card, trim, 10, art, 5, 0.25)
	rays.Position = UDim2.new(0.5, 0, 0, S(12) + T(46) + S(4) + art / 2)
	local a = ItemArt.draw(card, { kind = "crate", id = Crates.dailyId(tierId), amount = 1 }, art, 6)
	a.AnchorPoint = Vector2.new(0.5, 0)
	a.Position = UDim2.new(0.5, 0, 0, S(12) + T(46) + S(4))
	Fx.bob(a, S(4), 2.2)
	local cta = UI.text({
		Text = "TAP TO OPEN",
		FontFace = Theme.Fonts.display,
		TextSize = T(20),
		TextColor3 = Theme.Colors.white,
		BackgroundTransparency = 0,
		BackgroundColor3 = GREEN,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(12)),
		Size = UDim2.new(1, -S(24), 0, T(40)),
		ZIndex = 6,
		Parent = card,
	})
	UI.corner(cta, S(4))
	Fx.shine(cta)
	Fx.interactive(card)
	-- Slide in from the left with a burst and the loot ding.
	Fx.slideIn(card, UDim2.fromOffset(-(w + S(40)), 0), 0.35)
	task.delay(0.3, function()
		if token == my then
			UI.sound(Fx.Sounds.ding, 1.1, 0.5)
			Fx.burst(card, UDim2.fromScale(0.5, 0.45), trim, 16, 7)
		end
	end)
	card.Activated:Connect(function()
		if ClientState.dailyOpenOnArrival then
			return
		end
		ClientState.dailyOpenOnArrival = true
		Remotes.SummaryChoice:FireServer("lobby")
		UI.punch(card, 0.94, 0.2)
		UI.sound(Theme.Sounds.toast, 1.3, 0.5)
		cta.Text = "TO THE LOBBY…"
	end)
end

local function maybeShow()
	local tier = pendingTier
	local began = beganAt
	if not tier or not began then
		return
	end
	pendingTier = nil
	local at = began + (Config.RunEndBeats :: any).summary + 1.2
	task.delay(math.max(0, at - os.clock()), function()
		if beganAt == began then
			show(tier)
		end
	end)
end

function SummaryCrateCard.init()
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "DailyUnlocked" then
			pendingTier = if typeof(data) == "table" and typeof(data.tier) == "string" then data.tier else "basic"
			maybeShow()
		elseif name == "RunEndBegin" then
			beganAt = os.clock()
			ClientState.dailyOpenOnArrival = false
			maybeShow()
		elseif name == "HubEnter" then
			beganAt = nil
			pendingTier = nil
			destroy()
			if ClientState.dailyOpenOnArrival then
				task.delay(Config.DailyCrateArrivalOpenSec, function()
					ClientState.dailyOpenOnArrival = false
					local state = player:GetAttribute("DailyCrate")
					ClientState.Juice:Fire("DailySheet", { state = if typeof(state) == "string" then state else "" })
				end)
			end
		elseif name == "RunStartBegin" then
			destroy()
		end
	end)
end

return SummaryCrateCard
