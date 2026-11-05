--!strict
-- The in-run scoreboard: hold Tab on PC, or tap the wave bar on mobile (tap again or anywhere outside to
-- close). A translucent panel over the game (which keeps running, nothing is blocked): header WAVE N ·
-- TIME · stars · ◆ BANKED · $ CASH, then one row per party member in MVP order (level and class icon,
-- state dot, kills, cash, bags, jobs, downs, revives, MVP score), your own row highlighted. Reads
-- StateSync.roster, which the server rebuilds every RosterSyncSec.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(Shared:WaitForChild("Classes"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local Scoreboard = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui: ScreenGui? = nil
local panel: Frame? = nil
local header: TextLabel? = nil
local rowsFrame: Frame? = nil
local open = false
local rowH = 0

local COLS = {
	{ title = "CREW", w = 0.30, align = Enum.TextXAlignment.Left },
	{ title = "KILLS", w = 0.10, align = Enum.TextXAlignment.Center },
	{ title = "CASH", w = 0.14, align = Enum.TextXAlignment.Center },
	{ title = "BAGS", w = 0.09, align = Enum.TextXAlignment.Center },
	{ title = "JOBS", w = 0.09, align = Enum.TextXAlignment.Center },
	{ title = "DOWNS", w = 0.09, align = Enum.TextXAlignment.Center },
	{ title = "REVIVES", w = 0.09, align = Enum.TextXAlignment.Center },
	{ title = "MVP", w = 0.10, align = Enum.TextXAlignment.Right },
}

local function fmtClock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function stars(heat: number): string
	local full = math.floor(heat)
	local half = heat - full >= 0.5
	return string.rep("★", full)
		.. (if half then "½" else "")
		.. string.rep("☆", 5 - full - (if half then 1 else 0))
end

local function build()
	if gui then
		gui:Destroy()
	end
	local S = UI.S
	local g = UI.new("ScreenGui", {
		Name = "Scoreboard",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 8,
		Enabled = false,
		Parent = playerGui,
	}) :: ScreenGui
	gui = g
	-- Phone width: the panel never runs past the screen.
	local vp = (game:GetService("Workspace").CurrentCamera :: Camera).ViewportSize
	local W = math.min(S(620), math.floor(vp.X * 0.94))
	local p = UI.frame({
		Name = "Panel",
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.25,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromOffset(W, S(120)),
		Active = false,
		Parent = g,
	})
	UI.corner(p, S(14))
	UI.stroke(p, Theme.Colors.gold, S(2), 0.3)
	panel = p
	header = UI.text({
		Text = "",
		Font = Theme.Fonts.display,
		TextSize = S(15),
		TextColor3 = Theme.Colors.text,
		Position = UDim2.fromOffset(0, S(10)),
		Size = UDim2.new(1, 0, 0, S(22)),
		Parent = p,
	})
	UI.stroke(header :: TextLabel, Theme.Colors.black, S(1.5), 0.3)
	-- Column titles.
	local titles = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(S(16), S(38)),
		Size = UDim2.new(1, -S(32), 0, S(16)),
		Parent = p,
	})
	local x = 0
	local tableW = W - S(32)
	for _, col in COLS do
		UI.text({
			Text = col.title,
			TextSize = S(10),
			TextColor3 = Theme.Colors.grey,
			TextXAlignment = col.align,
			Position = UDim2.fromOffset(x + (if col.align == Enum.TextXAlignment.Left then S(8) else 0), 0),
			Size = UDim2.new(col.w, 0, 1, 0),
			Parent = titles,
		})
		x += math.floor(tableW * col.w)
	end
	rowsFrame = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(S(16), S(58)),
		Size = UDim2.new(1, -S(32), 0, 0),
		Parent = p,
	})
	UI.list(rowsFrame :: Frame, Enum.FillDirection.Vertical, S(4))
	rowH = S(28)
	UI.text({
		Text = if ClientState.isMobile then "TAP TO CLOSE" else "RELEASE TAB TO CLOSE",
		TextSize = S(9),
		TextColor3 = Theme.Colors.grey,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(4)),
		Size = UDim2.new(1, 0, 0, S(12)),
		Parent = p,
	})
end

local function paint()
	local sync = ClientState.sync
	local p, hdr, rf = panel, header, rowsFrame
	if not sync or not p or not hdr or not rf then
		return
	end
	local roster: any = sync.roster
	local S = UI.S
	hdr.Text = string.format(
		"WAVE %d  ·  TIME %s  ·  %s  ·  ◆ BANKED %s  ·  $ CASH %s",
		tonumber(sync.wave) or 1,
		fmtClock(if roster then tonumber(roster.survivedSec) or 0 else 0),
		stars(tonumber(sync.heat) or 0),
		UI.fmtNum(if roster then tonumber(roster.banked) or 0 else tonumber(sync.banked) or 0),
		string.sub(UI.fmtCash(if roster then tonumber(roster.cash) or 0 else 0), 2)
	)
	for _, c in rf:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local rows: { any } = if roster then roster.rows or {} else {}
	local tableW = p.AbsoluteSize.X - S(32)
	if tableW <= 0 then
		tableW = S(620) - S(32)
	end
	for i, row in rows do
		local mine = row.userId == player.UserId
		local frame = UI.frame({
			BackgroundColor3 = if mine then Theme.Colors.panel2 else Theme.Colors.panel,
			BackgroundTransparency = if mine then 0.1 else 0.4,
			Size = UDim2.new(1, 0, 0, rowH - S(4)),
			LayoutOrder = i,
			Parent = rf,
		})
		UI.corner(frame, S(6))
		if mine then
			UI.stroke(frame, Theme.Colors.gold, S(1.5), 0.2)
		end
		local class = Classes.ById[tostring(row.classId)] or Classes.ById[Classes.Default]
		local x = 0
		-- Name cell: state dot, class circle with the initial, LV n NAME.
		local dot = UI.frame({
			BackgroundColor3 = if row.state == "standing"
				then Theme.Colors.cash
				elseif row.state == "downed" then Theme.Colors.red
				else Theme.Colors.grey,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, S(6), 0.5, 0),
			Size = UDim2.fromOffset(S(8), S(8)),
			Parent = frame,
		})
		UI.corner(dot, S(4))
		local circle = UI.frame({
			BackgroundColor3 = Color3.fromHex(class.color),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, S(18), 0.5, 0),
			Size = UDim2.fromOffset(S(16), S(16)),
			Parent = frame,
		})
		UI.corner(circle, S(8))
		UI.text({
			Text = class.glyph,
			Font = Theme.Fonts.display,
			TextSize = S(11),
			TextColor3 = Theme.Colors.bg,
			Size = UDim2.fromScale(1, 1),
			Parent = circle,
		})
		UI.text({
			Text = string.format("LV %d  %s", tonumber(row.level) or 1, string.upper(tostring(row.name))),
			Font = Theme.Fonts.display,
			TextSize = S(12),
			TextColor3 = if mine then Theme.Colors.gold else Theme.Colors.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(S(40), 0),
			Size = UDim2.new(COLS[1].w, -S(40), 1, 0),
			Parent = frame,
		})
		x += math.floor(tableW * COLS[1].w)
		local values = {
			{ tostring(row.kills or 0), Theme.Colors.text },
			{ UI.fmtCash(tonumber(row.cash) or 0), Theme.Colors.cash },
			{ tostring(row.bags or 0), Theme.Colors.gold },
			{ tostring(row.jobs or 0), Theme.Colors.blue },
			{ tostring(row.downs or 0), Theme.Colors.malus },
			{ tostring(row.revives or 0), Theme.Colors.text },
			{ tostring(math.round(tonumber(row.score) or 0)), Theme.Colors.gold },
		}
		for k, v in values do
			local col = COLS[k + 1]
			UI.text({
				Text = v[1],
				TextSize = S(12),
				TextColor3 = v[2],
				TextXAlignment = col.align,
				Position = UDim2.fromOffset(x - (if col.align == Enum.TextXAlignment.Right then S(8) else 0), 0),
				Size = UDim2.new(col.w, 0, 1, 0),
				Parent = frame,
			})
			x += math.floor(tableW * col.w)
		end
	end
	p.Size = UDim2.fromOffset(p.Size.X.Offset, S(58) + rowH * math.max(#rows, 1) + S(18))
end

function Scoreboard.setOpen(on: boolean)
	if open == on then
		return
	end
	if on and ClientState.inHub() then
		return
	end
	open = on
	local g = gui
	if not g then
		return
	end
	g.Enabled = on
	if on then
		paint()
		local p = panel
		if p then
			UI.punch(p, 1.04, 0.2)
		end
		UI.sound(Theme.Sounds.toast, 1.1, 0.25)
	end
end

function Scoreboard.isOpen(): boolean
	return open
end

function Scoreboard.init()
	build()
	local HUD = require(script.Parent:WaitForChild("HUD"))
	HUD.Rebuilt:Connect(function()
		build()
		if open then
			local g = gui
			if g then
				g.Enabled = true
			end
			paint()
		end
	end)
	ClientState.Changed:Connect(function()
		if open then
			paint()
		end
	end)
	-- PC: hold Tab. Mobile: the wave bar fires ToggleScoreboard; a tap anywhere else closes it.
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if input.KeyCode == Enum.KeyCode.Tab and not gameProcessed then
			Scoreboard.setOpen(true)
		elseif open and ClientState.isMobile and input.UserInputType == Enum.UserInputType.Touch then
			-- A tap outside the panel closes it (the wave bar's own tap toggles through the juice event).
			local p = panel
			if p then
				local pos = input.Position
				local a, b = p.AbsolutePosition, p.AbsolutePosition + p.AbsoluteSize
				if pos.X < a.X or pos.X > b.X or pos.Y < a.Y or pos.Y > b.Y then
					task.defer(Scoreboard.setOpen, false)
				end
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Tab then
			Scoreboard.setOpen(false)
		end
	end)
	ClientState.Juice:Connect(function(name: string)
		if name == "ToggleScoreboard" then
			Scoreboard.setOpen(not open)
		elseif name == "HubEnter" or name == "RunEndBegin" then
			Scoreboard.setOpen(false)
		end
	end)
end

return Scoreboard
