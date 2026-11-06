--!strict
-- Brief 6: the JOBS board. Opens from the hub HUD JOBS button, F at MARLOW's corkboard in the yard, or a finished
-- Job on the summary; the camera pushes onto the corkboard and the HUD hides.
--   header   JOBS · NEW JOBS IN 6h 12m · BOUNTY RESETS IN 3d
--   dailies  three pinned paper cards, slightly rotated: title, MARLOW's line, progress, the reward row, CLAIM when
--            done, REROLL on one card per day (it tears off and a new one pins in)
--   bounty   a WANTED poster: title, MARLOW's portrait, progress, the reward row, CLAIM
--   footer   CLAIM ALL when more than one is done, BACK
-- States: in progress (paper, pin), complete (a red DONE stamp slams on, the card lifts and glows), claimed (a stub
-- with a check until the reset). Also here: MARLOW's hub announcement card, the board's beacon pulse, the in-run JOB
-- toasts.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local JobPool = require(Shared:WaitForChild("JobPool"))
local Clock = require(Shared:WaitForChild("Clock"))

local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local HUD = require(Client:WaitForChild("HUD"))
local PurchaseSheet = require(Client:WaitForChild("PurchaseSheet"))
local Fx = require(Client:WaitForChild("Store"):WaitForChild("Fx"))
local Reveal = require(Client:WaitForChild("Store"):WaitForChild("Reveal"))

local JobBoard = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera :: Camera

local PAPER = Color3.fromHex("F2E6C8")
local INK = Color3.fromHex("2A2420")
local STAMP = Color3.fromHex("C8323C")

local open = false
local gui: ScreenGui? = nil
local body: Frame? = nil
local camFrom: CFrame? = nil
local camTo: CFrame? = nil
local camT0, camSec = 0, 0.6
local savedMode = "gameplay"
local savedHud = "hub"
local lockedMovement = false
local seenDone: { [string]: boolean } = {} -- entry ids already shown as DONE (the stamp slams once)

local function profile(): any
	local sync = ClientState.sync
	return sync and sync.profile
end

local function shop(action: string, args: any?): any
	local ok, res = pcall(function()
		return Remotes.Shop:InvokeServer(action, args)
	end)
	return if ok and typeof(res) == "table" then res else { ok = false, reason = "Server error" }
end

local function boardModel(): Model?
	local m = Workspace:FindFirstChild("JobBoard", true)
	return if m and m:IsA("Model") then m else nil
end

local function rewardText(weekly: boolean): string
	if weekly then
		return string.format(
			"+%s XP · +◆ %s · +%s PASS XP · +%d TOKENS",
			UI.fmtInt(Config.WeeklyXp),
			UI.fmtInt(Config.WeeklyGold),
			UI.fmtInt(Config.WeeklyPassXp),
			Config.WeeklyTokens
		)
	end
	return string.format("+%d XP · +◆ %d · +%d PASS XP", Config.DailyXp, Config.DailyGold, Config.DailyPassXp)
end

------------------------------------------------------------------ Cards
local render: () -> ()

local function pin(parent: Instance, z: number)
	local S = UI.S
	local p = UI.frame({
		BackgroundColor3 = Color3.fromHex("E8554D"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, S(6)),
		Size = UDim2.fromOffset(S(16), S(16)),
		ZIndex = z,
		Parent = parent,
	})
	UI.corner(p, S(8))
	UI.stroke(p, Color3.fromHex("7A1E1A"), S(1.5), 0)
	UI.frame({
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.4,
		Position = UDim2.fromScale(0.2, 0.2),
		Size = UDim2.fromScale(0.3, 0.3),
		ZIndex = z + 1,
		Parent = p,
	})
end

local function stamp(parent: Instance, text: string, z: number, animate: boolean)
	local S = UI.S
	local s = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.55, 0.5),
		Size = UDim2.fromOffset(S(150), S(56)),
		Rotation = -14,
		ZIndex = z,
		Parent = parent,
	})
	UI.corner(s, S(6))
	UI.stroke(s, STAMP, S(4), 0.1)
	local l = UI.text({
		Text = text,
		Font = Theme.Fonts.display,
		TextSize = S(36),
		TextColor3 = STAMP,
		TextTransparency = 0.1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 1,
		Parent = s,
	})
	local _ = l
	if animate then
		local sc = UI.new("UIScale", { Scale = 2.4, Parent = s })
		UI.tween(sc, { Scale = 1 }, 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.18, function()
			UI.sound(Fx.Sounds.stamp, 0.7, 0.7)
			Fx.haptic(0.5)
			if s.Parent then
				UI.shake(parent :: any, S(4), 0.15)
			end
		end)
	end
end

local function progressBar(parent: Instance, progress: number, target: number, z: number, order: number)
	local S = UI.S
	local row = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(20)),
		LayoutOrder = order,
		ZIndex = z,
		Parent = parent,
	})
	local bar = UI.frame({
		BackgroundColor3 = Color3.fromHex("CDBF9E"),
		Size = UDim2.new(1, -S(78), 0, S(12)),
		Position = UDim2.fromOffset(0, S(4)),
		ZIndex = z,
		Parent = row,
	})
	UI.corner(bar, S(6))
	local k = math.clamp(progress / math.max(target, 1), 0, 1)
	local fill = UI.frame({
		BackgroundColor3 = if k >= 1 then Color3.fromHex("3FA85C") else Color3.fromHex("C9772A"),
		Size = UDim2.fromScale(k, 1),
		ZIndex = z + 1,
		Parent = bar,
	})
	UI.corner(fill, S(6))
	UI.text({
		Text = string.format("%s / %s", UI.fmtInt(progress), UI.fmtInt(target)),
		Font = Theme.Fonts.display,
		TextSize = S(13),
		TextColor3 = INK,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(S(74), S(20)),
		ZIndex = z,
		Parent = row,
	})
end

local function claimWith(res: any, title: string)
	if res.ok and res.data and typeof(res.data.results) == "table" then
		local g = gui
		if g then
			Reveal.stack(g, res.data.results, title, { mini = true })
		end
		UI.sound(Fx.Sounds.chime, 1.3, 0.35)
	else
		PurchaseSheet.toast(tostring(res.reason or "Not ready"), Theme.Colors.malus, false)
	end
end

-- One daily card. `slot` 1..3; `canReroll` while today's reroll is unused.
local function dailyCard(parent: Frame, slot: number, e: any, canReroll: boolean, order: number)
	local S = UI.S
	local def = JobPool.ById[e.id]
	if not def then
		return
	end
	local progress = tonumber(e.progress) or 0
	local done = progress >= def.target
	local claimed = e.claimed == true
	local holder = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(S(230), S(250)),
		LayoutOrder = order,
		ZIndex = 5,
		Parent = parent,
	})
	local card = UI.frame({
		Name = "Paper",
		BackgroundColor3 = PAPER,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(1, 0, if claimed then 0 else 1, if claimed then S(84) else 0),
		Rotation = ({ -3, 2, -1.5 })[slot] or 0,
		ZIndex = 6,
		Parent = holder,
	})
	UI.corner(card, S(4))
	UI.stroke(card, Color3.fromHex("B8A57E"), S(1), 0.3)
	-- A soft shadow under the paper.
	local shadow = UI.frame({
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.7,
		Position = UDim2.fromOffset(S(5), S(6)),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = card,
	})
	UI.corner(shadow, S(4))
	pin(card, 9)
	local inner = UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 7, Parent = card })
	UI.pad(inner, S(14), S(20), S(14), S(12))
	UI.list(inner, Enum.FillDirection.Vertical, S(6))
	UI.text({
		Text = def.title,
		Font = Theme.Fonts.display,
		TextSize = S(19),
		TextColor3 = INK,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(44)),
		LayoutOrder = 1,
		ZIndex = 8,
		Parent = inner,
	})
	if claimed then
		local c = UI.frame({
			BackgroundColor3 = Color3.fromHex("3FA85C"),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -S(12), 0.6, 0),
			Size = UDim2.fromOffset(S(26), S(26)),
			ZIndex = 9,
			Parent = card,
		})
		UI.corner(c, S(13))
		UI.text({
			Text = "✓",
			Font = Theme.Fonts.body,
			TextSize = S(18),
			TextColor3 = Theme.Colors.white,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 10,
			Parent = c,
		})
		UI.text({
			Text = "CLAIMED",
			Font = Theme.Fonts.display,
			TextSize = S(12),
			TextColor3 = Color3.fromHex("3FA85C"),
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, S(14)),
			LayoutOrder = 2,
			ZIndex = 8,
			Parent = inner,
		})
		return
	end
	UI.text({
		Text = '"' .. def.flavor .. '" — MARLOW',
		Font = Enum.Font.GothamMedium,
		TextSize = S(11),
		TextColor3 = Color3.fromHex("6A5A40"),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(30)),
		LayoutOrder = 2,
		ZIndex = 8,
		Parent = inner,
	})
	progressBar(inner, progress, def.target, 8, 3)
	UI.text({
		Text = rewardText(false),
		Font = Theme.Fonts.display,
		TextSize = S(11),
		TextColor3 = Color3.fromHex("9A6A1A"),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(28)),
		LayoutOrder = 4,
		ZIndex = 8,
		Parent = inner,
	})
	local actions = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(38)),
		LayoutOrder = 5,
		ZIndex = 8,
		Parent = inner,
	})
	UI.list(actions, Enum.FillDirection.Horizontal, S(6))
	if done then
		local b, _ = Fx.button(actions, "CLAIM", Color3.fromHex("2FB75A"), Theme.Colors.white, UDim2.new(1, 0, 1, 0), 9)
		b.Activated:Connect(function()
			claimWith(shop("jobClaim", { key = "d" .. slot }), def.title)
		end)
		-- Complete: the DONE stamp slams on (once), the card lifts and glows.
		local first = not seenDone[e.id]
		seenDone[e.id] = true
		stamp(card, "DONE", 12, first)
		local sc = UI.new("UIScale", { Scale = 1, Parent = holder })
		UI.tween(sc, { Scale = 1.04 }, 0.3, Enum.EasingStyle.Back)
		local _g, setGlow = Fx.glow(card, Color3.fromHex("FFE08A"), S(6), 4)
		setGlow(1.2)
	elseif canReroll then
		local r, _ = Fx.button(actions, "REROLL", Color3.fromHex("5A4A30"), PAPER, UDim2.new(1, 0, 1, 0), 9)
		r.TextSize = S(15)
		r.Activated:Connect(function()
			-- Tear-off: the card swings off the pin and drops; the new one pins in.
			UI.sound(Fx.Sounds.tear, 0.8, 0.6)
			UI.tween(
				card,
				{ Rotation = 28, Position = UDim2.new(0.5, S(40), 0, S(260)) },
				0.4,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			)
			task.delay(0.42, function()
				local res = shop("jobReroll", { slot = slot })
				if not res.ok then
					PurchaseSheet.toast(tostring(res.reason), Theme.Colors.malus, false)
				end
				render()
				UI.sound(Fx.Sounds.thump, 1.4, 0.4)
			end)
		end)
	end
	if not seenDone[e.id] or not done then
		-- New cards drop in onto their pin.
		local to = card.Position
		card.Position = to - UDim2.fromOffset(0, S(30))
		UI.tween(card, { Position = to }, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
end

-- The WANTED poster.
local function bountyCard(parent: Frame, e: any)
	local S = UI.S
	local def = JobPool.ById[e.id]
	if not def then
		return
	end
	local progress = tonumber(e.progress) or 0
	local done = progress >= def.target
	local claimed = e.claimed == true
	local poster = UI.frame({
		BackgroundColor3 = Color3.fromHex("E2CDA0"),
		Size = UDim2.fromScale(1, 1),
		Rotation = 1.5,
		ZIndex = 6,
		Parent = parent,
	})
	UI.corner(poster, S(4))
	UI.stroke(poster, Color3.fromHex("8A6A3A"), S(2), 0.2)
	pin(poster, 9)
	local inner = UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 7, Parent = poster })
	UI.pad(inner, S(18), S(22), S(18), S(14))
	UI.list(inner, Enum.FillDirection.Vertical, S(6), Enum.HorizontalAlignment.Center)
	UI.text({
		Text = "WANTED",
		Font = Theme.Fonts.display,
		TextSize = S(40),
		TextColor3 = Color3.fromHex("5A2A14"),
		Size = UDim2.new(1, 0, 0, S(42)),
		LayoutOrder = 1,
		ZIndex = 8,
		Parent = inner,
	})
	UI.text({
		Text = "WEEKLY BOUNTY",
		Font = Theme.Fonts.display,
		TextSize = S(12),
		TextColor3 = Color3.fromHex("8A5A2A"),
		Size = UDim2.new(1, 0, 0, S(14)),
		LayoutOrder = 2,
		ZIndex = 8,
		Parent = inner,
	})
	-- MARLOW's portrait: a dummy bust in the house style.
	local frame = UI.frame({
		BackgroundColor3 = Color3.fromHex("3A2A1A"),
		Size = UDim2.fromOffset(S(96), S(96)),
		LayoutOrder = 3,
		ZIndex = 8,
		Parent = inner,
	})
	UI.corner(frame, S(6))
	UI.stroke(frame, Color3.fromHex("5A2A14"), S(2), 0)
	local head = UI.frame({
		BackgroundColor3 = Color3.fromHex("C9A46A"),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.16),
		Size = UDim2.fromScale(0.42, 0.42),
		ZIndex = 9,
		Parent = frame,
	})
	UI.corner(head, S(40))
	local shoulders = UI.frame({
		BackgroundColor3 = Color3.fromHex("23232B"),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(0.8, 0.34),
		ZIndex = 9,
		Parent = frame,
	})
	UI.corner(shoulders, S(20))
	UI.frame({
		BackgroundColor3 = Color3.fromHex("1A1A1E"),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.12),
		Size = UDim2.fromScale(0.5, 0.12),
		ZIndex = 10,
		Parent = frame,
	})
	UI.text({
		Text = "MARLOW",
		Font = Theme.Fonts.display,
		TextSize = S(11),
		TextColor3 = Color3.fromHex("8A5A2A"),
		Size = UDim2.new(1, 0, 0, S(12)),
		LayoutOrder = 4,
		ZIndex = 8,
		Parent = inner,
	})
	UI.text({
		Text = def.title,
		Font = Theme.Fonts.display,
		TextSize = S(22),
		TextColor3 = INK,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, S(52)),
		LayoutOrder = 5,
		ZIndex = 8,
		Parent = inner,
	})
	UI.text({
		Text = '"' .. def.flavor .. '"',
		Font = Enum.Font.GothamMedium,
		TextSize = S(11),
		TextColor3 = Color3.fromHex("6A5A40"),
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, S(28)),
		LayoutOrder = 6,
		ZIndex = 8,
		Parent = inner,
	})
	progressBar(inner, progress, def.target, 8, 7)
	UI.text({
		Text = rewardText(true),
		Font = Theme.Fonts.display,
		TextSize = S(11),
		TextColor3 = Color3.fromHex("9A6A1A"),
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, S(28)),
		LayoutOrder = 8,
		ZIndex = 8,
		Parent = inner,
	})
	if claimed then
		stamp(poster, "PAID", 12, false)
	elseif done then
		local b, _ =
			Fx.button(inner, "CLAIM", Color3.fromHex("2FB75A"), Theme.Colors.white, UDim2.new(1, 0, 0, S(42)), 9)
		b.LayoutOrder = 9
		b.Activated:Connect(function()
			claimWith(shop("jobClaim", { key = "b1" }), def.title)
		end)
		local first = not seenDone[e.id]
		seenDone[e.id] = true
		stamp(poster, "DONE", 12, first)
		local _g, setGlow = Fx.glow(poster, Color3.fromHex("FFE08A"), S(6), 4)
		setGlow(1.3)
	end
end

render = function()
	if not open then
		return
	end
	local S = UI.S
	local b = body
	if not b then
		return
	end
	for _, c in b:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local p = profile()
	local jobs = p and p.jobs
	if not jobs then
		return
	end
	local mobile = ClientState.isMobile
	local now = ClientState.fakeNow()
	-- Header.
	local header = UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, S(60)), ZIndex = 5, Parent = b })
	local title = UI.text({
		Text = "JOBS",
		Font = Theme.Fonts.display,
		TextSize = S(44),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(S(160), S(56)),
		ZIndex = 6,
		Parent = header,
	})
	UI.stroke(title, Color3.new(0, 0, 0), S(2), 0.2)
	local clocks = UI.text({
		Text = "",
		Font = Theme.Fonts.display,
		TextSize = S(15),
		TextColor3 = Theme.Colors.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(170), S(14)),
		Size = UDim2.new(1, -S(300), 0, S(30)),
		ZIndex = 6,
		Parent = header,
	})
	UI.stroke(clocks, Color3.new(0, 0, 0), S(1.5), 0.3)
	task.spawn(function()
		while clocks.Parent do
			local t = ClientState.fakeNow()
			clocks.Text = string.format(
				"NEW JOBS IN %s   ·   BOUNTY RESETS IN %s",
				Clock.span(Clock.nextDay(t) - t),
				Clock.span(Clock.nextWeek(t) - t)
			)
			task.wait(1)
		end
	end)
	local _ = now
	-- Dailies left, the bounty right.
	local dailies = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, S(72)),
		Size = UDim2.new(if mobile then 0.66 else 0.68, 0, 1, -S(140)),
		ZIndex = 5,
		Parent = b,
	})
	UI.list(dailies, Enum.FillDirection.Horizontal, S(18), Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	local canReroll = (tonumber(jobs.rerollUsed) or 0) < Config.JobRerollsPerDay
	local doneCount = 0
	for i, e in jobs.daily do
		dailyCard(dailies, i, e, canReroll, i)
		local def = JobPool.ById[e.id]
		if def and (tonumber(e.progress) or 0) >= def.target and not e.claimed then
			doneCount += 1
		end
	end
	local bounty = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(10), 0, S(64)),
		Size = UDim2.new(if mobile then 0.32 else 0.28, 0, 1, -S(130)),
		ZIndex = 5,
		Parent = b,
	})
	local be = jobs.bounty[1]
	if be then
		bountyCard(bounty, be)
		local def = JobPool.ById[be.id]
		if def and (tonumber(be.progress) or 0) >= def.target and not be.claimed then
			doneCount += 1
		end
	end
	-- Footer.
	local footer = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, S(54)),
		ZIndex = 5,
		Parent = b,
	})
	UI.list(
		footer,
		Enum.FillDirection.Horizontal,
		S(14),
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Center
	)
	if doneCount > 1 then
		local all, _ = Fx.button(
			footer,
			string.format("CLAIM ALL (%d)", doneCount),
			Color3.fromHex("2FB75A"),
			Theme.Colors.white,
			UDim2.fromOffset(S(220), S(50)),
			6
		)
		all.TextSize = S(20)
		Fx.particles(all, Color3.fromHex("FFE08A"), 5, 8)
		all.Activated:Connect(function()
			claimWith(shop("jobClaimAll", {}), "JOBS PAID")
		end)
	end
	local back, _ = Fx.button(footer, "BACK", Theme.Colors.red, Theme.Colors.white, UDim2.fromOffset(S(160), S(50)), 6)
	back.LayoutOrder = 2
	back.Activated:Connect(function()
		JobBoard.close()
	end)
end

------------------------------------------------------------------ Open / close
function JobBoard.isOpen(): boolean
	return open
end

function JobBoard.open()
	local sync = ClientState.sync
	local state = if sync then sync.waveState else "Hub"
	if state ~= "Hub" and state ~= "Summary" then
		return
	end
	if open or ClientState.downed or ClientState.spectating then
		return
	end
	ClientState.Juice:Fire("CloseStore", {})
	ClientState.Juice:Fire("CloseMeta", {})
	ClientState.Juice:Fire("ClosePass", {})
	open = true
	shop("jobsOpen", {})
	local S = UI.S
	local g = UI.new("ScreenGui", {
		Name = "JobBoard",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 24,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui
	gui = g
	local dim = UI.frame({
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = g,
	})
	UI.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.5, 0.6),
			NumberSequenceKeypoint.new(1, 0.2),
		}),
		Parent = dim,
	})
	body = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(S(30), S(20)),
		Size = UDim2.new(1, -S(60), 1, -S(40)),
		ZIndex = 5,
		Parent = g,
	})
	savedMode = ClientState.cameraMode
	savedHud = HUD.mode
	ClientState.cameraMode = "jobs"
	ClientState.setBlock("jobs", true)
	ClientState.setAds(false)
	lockedMovement = state == "Hub"
	if lockedMovement then
		ClientState.lockMovement("jobs", true)
	end
	HUD.setMode("meta")
	-- The camera pushes onto the corkboard.
	local m = boardModel()
	local cork = m and m:FindFirstChild("Cork")
	if cork and cork:IsA("BasePart") then
		local target = cork.Position
		local front = cork.CFrame.LookVector * -1 -- the board's front faces +Z: the part's back
		camFrom = camera.CFrame
		camTo = CFrame.lookAt(target + front * 7 + Vector3.new(0, 0.4, 0), target)
		camT0, camSec = os.clock(), 0.6
		RunService:BindToRenderStep("GHSJobsCamera", Enum.RenderPriority.Camera.Value + 3, function()
			local to = camTo
			if not open or not to then
				return
			end
			camera.CameraType = Enum.CameraType.Scriptable
			local s = math.clamp((os.clock() - camT0) / camSec, 0, 1)
			local k = 1 - (1 - s) ^ 3
			camera.CFrame = (camFrom or to):Lerp(to, k)
		end)
	end
	UI.sound(Fx.Sounds.whoosh, 1.1, 0.4)
	render()
	Fx.slideIn(body :: Frame, UDim2.fromOffset(0, S(40)), 0.3)
end

function JobBoard.close()
	if not open then
		return
	end
	open = false
	pcall(function()
		RunService:UnbindFromRenderStep("GHSJobsCamera")
	end)
	camFrom, camTo = nil, nil
	if gui then
		gui:Destroy()
		gui = nil
	end
	body = nil
	ClientState.setBlock("jobs", false)
	if lockedMovement then
		ClientState.lockMovement("jobs", false)
	end
	if ClientState.inHub() then
		ClientState.cameraMode = "gameplay"
		HUD.setMode(HUD.baseMode())
	else
		ClientState.cameraMode = savedMode
		HUD.setMode(savedHud)
	end
	UI.sound(Fx.Sounds.whoosh, 0.7, 0.35)
end

------------------------------------------------------------------ MARLOW's hub announcement, the beacon, the JOB toasts
local function announce(line: string)
	local S = UI.S
	local g = UI.new(
		"ScreenGui",
		{ Name = "JobsAnnounce", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 7, Parent = playerGui }
	) :: ScreenGui
	local card = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(20), 0, S(118)),
		Size = UDim2.fromOffset(S(340), S(78)),
		ZIndex = 2,
		Parent = g,
	})
	UI.corner(card, S(10))
	UI.stroke(card, Theme.Colors.gold, S(2), 0)
	local portrait = UI.frame({
		BackgroundColor3 = Color3.fromHex("3A2A1A"),
		Position = UDim2.fromOffset(S(8), S(8)),
		Size = UDim2.fromOffset(S(62), S(62)),
		ZIndex = 3,
		Parent = card,
	})
	UI.corner(portrait, S(8))
	local head = UI.frame({
		BackgroundColor3 = Color3.fromHex("C9A46A"),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.14),
		Size = UDim2.fromScale(0.44, 0.44),
		ZIndex = 4,
		Parent = portrait,
	})
	UI.corner(head, S(20))
	local sh = UI.frame({
		BackgroundColor3 = Color3.fromHex("23232B"),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(0.8, 0.34),
		ZIndex = 4,
		Parent = portrait,
	})
	UI.corner(sh, S(14))
	UI.text({
		Text = "MARLOW · JOBS",
		Font = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(80), S(8)),
		Size = UDim2.new(1, -S(90), 0, S(18)),
		ZIndex = 3,
		Parent = card,
	})
	local text = UI.text({
		Text = "",
		Font = Theme.Fonts.body,
		TextSize = S(13),
		TextColor3 = Theme.Colors.text,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(S(80), S(28)),
		Size = UDim2.new(1, -S(90), 0, S(44)),
		ZIndex = 3,
		Parent = card,
	})
	Fx.slideIn(card, UDim2.fromOffset(S(380), 0), 0.35)
	UI.sound(Theme.Sounds.call, 0.9, 0.6)
	task.spawn(function()
		for i = 1, #line do
			if not text.Parent then
				return
			end
			text.Text = string.sub(line, 1, i)
			task.wait(1 / Config.CallTypeCharsPerSec)
		end
	end)
	task.delay(Config.CallHoldSec + 1.5, function()
		if card.Parent then
			UI.tween(
				card,
				{ Position = UDim2.new(1, S(360), 0, S(118)) },
				0.3,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			)
			task.delay(0.32, function()
				g:Destroy()
			end)
		end
	end)
end

function JobBoard.init()
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "OpenJobs" then
			JobBoard.open()
		elseif name == "RunStartBegin" or name == "Downed" or name == "CloseJobs" then
			JobBoard.close()
		elseif name == "HubEnter" and open and not lockedMovement then
			lockedMovement = true
			ClientState.lockMovement("jobs", true)
			savedMode = "gameplay"
		elseif name == "JobsAnnounce" then
			announce(tostring(data and data.line or Config.JobAnnounceLine))
		elseif name == "JobToast" and typeof(data) == "table" then
			-- In a run: a small JOB toast at each quarter.
			local t = HUD.get("toast")
			if t then
				if data.done then
					t.show(
						string.format("JOB DONE · %s · CLAIM AT THE BOARD", tostring(data.title)),
						Theme.Colors.gold,
						2.2
					)
				else
					t.show(
						string.format(
							"JOB · %s %d / %d",
							tostring(data.title),
							tonumber(data.progress) or 0,
							tonumber(data.target) or 0
						),
						Theme.Colors.text,
						1.6
					)
				end
			end
		end
	end)
	ClientState.Changed:Connect(function()
		if open then
			-- Re-render only when the board itself changed.
			local p = profile()
			local jobs = p and p.jobs
			if jobs then
				local parts = { tostring(jobs.dailyResetDay), tostring(jobs.rerollUsed) }
				for _, list in { jobs.daily, jobs.bounty } do
					for _, e in list do
						table.insert(parts, e.id .. ":" .. tostring(e.progress) .. ":" .. tostring(e.claimed))
					end
				end
				local stamp = table.concat(parts, "|")
				if stamp ~= (JobBoard :: any)._stamp then
					(JobBoard :: any)._stamp = stamp
					render()
				end
			end
		end
	end)
	-- The beacon pulses while today's board has not been opened.
	task.spawn(function()
		while true do
			local m = boardModel()
			local beacon = m and m:FindFirstChild("Beacon")
			local light = beacon and beacon:FindFirstChild("BeaconLight")
			local p = profile()
			local fresh = p and p.jobs and (tonumber(p.jobs.boardSeenDay) or 0) < Clock.day(ClientState.fakeNow())
			if beacon and beacon:IsA("BasePart") and light and light:IsA("PointLight") then
				if fresh then
					local k = (math.sin(os.clock() * 4) + 1) / 2
					light.Brightness = 1 + k * 4
					beacon.Transparency = 0.4 * (1 - k)
				else
					light.Brightness = 0.6
					beacon.Transparency = 0.5
				end
			end
			task.wait(0.05)
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if open and input.KeyCode == Enum.KeyCode.Escape and not gameProcessed then
			JobBoard.close()
		end
	end)
end

return JobBoard
