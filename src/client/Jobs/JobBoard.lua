--!strict
-- Brief 6: the JOBS board. Opens from the hub HUD JOBS button, F at MARLOW's corkboard in the yard, or a finished
-- Job on the summary; the camera pushes onto the corkboard and the HUD hides.
--   header   JOBS · NEW JOBS IN (over the dailies) · BOUNTY RESETS IN (over the poster)
--   dailies  three pinned paper cards filling the board, slightly rotated: DAILY JOB tag, title, MARLOW's line, the
--            state area (progress / DONE + CLAIM / PAID + NEW JOB), the reward row along the bottom
--   bounty   a WANTED poster: WEEKLY BOUNTY tag, MARLOW's portrait, title, line, progress or CLAIM, the reward row
--   footer   CLAIM ALL when more than one is done, BACK
-- States: in progress (a dark inset bar with the count), complete (a red DONE stamp slams on, the sheet glows, CLAIM
-- pops), claimed (the sheet settles flat and greys, a blue PAID stamp, NEW JOB until the reset). Round 17d polish:
-- dark ink on light paper, the shadow and glow sit behind the paper, cards cascade in on open. Also here: MARLOW's
-- hub announcement card, the board's beacon pulse, the in-run JOB toasts.
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
local ItemArt = require(Client:WaitForChild("Store"):WaitForChild("ItemArt"))

local JobBoard = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera :: Camera

-- Paper and ink. Text on paper is always dark ink; color lives in the stamps, the bar fill and the reward rims.
local PAPER = Color3.fromHex("F4EBD3")
local POSTER = Color3.fromHex("EAD7AC")
local SETTLED = Color3.fromHex("C9C4B8") -- a claimed sheet greys toward this
local INK = Color3.fromHex("241C16")
local INK_SOFT = Color3.fromHex("4E3D2C")
local SIGN = Color3.fromHex("8A2A1A")
local STAMP = Color3.fromHex("C8323C")
local PAID = Color3.fromHex("2B4C8C")
local GREEN = Color3.fromHex("2FB75A")
local FILL = Color3.fromHex("F0A02E")
local FILL_DONE = Color3.fromHex("3FC060")
local TRACK = Color3.fromHex("3A2E24")
local SPARK = Color3.fromHex("FFE08A")

local open = false
local gui: ScreenGui? = nil
local body: Frame? = nil
local fxLayer: Frame? = nil -- claim sparks live here so a re-render does not cut them off
local entrance = false -- the next render cascades the sheets in (only the first one after opening)
local camFrom: CFrame? = nil
local camTo: CFrame? = nil
local camT0, camSec = 0, 0.6
local savedMode = "gameplay"
local savedHud = "hub"
local lockedMovement = false
local seenDone: { [string]: boolean } = {} -- entry ids already shown as DONE (the stamp slams once)
local justClaimed: { [string]: boolean } = {} -- board keys claimed from this screen (their PAID stamp slams once)

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

------------------------------------------------------------------ Small pieces
-- Text scales down to fit its box, never above `max`.
local function fit(label: TextLabel | TextButton, max: number, min: number?)
	(label :: any).TextScaled = true
	UI.new("UITextSizeConstraint", { MaxTextSize = max, MinTextSize = min or 8, Parent = label })
end

local function italic(): Font
	return Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium, Enum.FontStyle.Italic)
end

-- A label-tape tag (DAILY JOB / WEEKLY BOUNTY): paper-colored caps on an ink strip.
local function tag(parent: Instance, text: string, order: number): Frame
	local S = UI.S
	local p, l = UI.pill(nil, text, INK, PAPER, S(22), S(13))
	l.FontFace = Theme.Fonts.display
	l.ZIndex = 9
	local corner = p:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, S(4))
	end
	p.LayoutOrder = order
	p.ZIndex = 8
	p.Parent = parent
	return p
end

-- MARLOW's line in italic dark ink, signed underneath.
local function quote(
	parent: Instance,
	flavor: string,
	height: number,
	size: number,
	inkT: number,
	centered: boolean
): Frame
	local S = UI.S
	local align = if centered then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
	local f = UI.frame({
		Name = "Quote",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = 3,
		ZIndex = 8,
		Parent = parent,
	})
	local q = UI.text({
		Text = '"' .. flavor .. '"',
		TextColor3 = INK_SOFT,
		TextTransparency = inkT,
		TextWrapped = true,
		TextXAlignment = align,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 1, -S(17)),
		ZIndex = 8,
		Parent = f,
	})
	q.FontFace = italic()
	fit(q, size, S(11))
	UI.text({
		Text = "— MARLOW",
		FontFace = Theme.Fonts.display,
		TextSize = S(13),
		TextColor3 = SIGN,
		TextTransparency = inkT,
		TextXAlignment = align,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, S(15)),
		ZIndex = 8,
		Parent = f,
	})
	return f
end

-- The rewards as icon tiles filling the width: XP, Gold, pass XP (and the bounty's tokens), each with its amount.
-- Anchored to the bottom of `parent`. A claimed sheet's tiles fade under a paper veil.
local function rewardTiles(parent: Instance, weekly: boolean, height: number, settled: boolean): Frame
	local S = UI.S
	local list = {
		{
			kind = "xp",
			amount = if weekly then Config.WeeklyXp else Config.DailyXp,
			label = "XP",
			color = Theme.Colors.blue,
		},
		{
			kind = "gold",
			amount = if weekly then Config.WeeklyGold else Config.DailyGold,
			label = "GOLD",
			color = Theme.Colors.gold,
		},
		{
			kind = "passxp",
			amount = if weekly then Config.WeeklyPassXp else Config.DailyPassXp,
			label = "PASS XP",
			color = Color3.fromHex("E8792A"),
		},
	}
	if weekly then
		table.insert(
			list,
			{ kind = "tokens", amount = Config.WeeklyTokens, label = "TOKENS", color = Color3.fromHex("3FD47A") }
		)
	end
	local row = UI.frame({
		Name = "Rewards",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, height),
		ZIndex = 8,
		Parent = parent,
	})
	local gap = S(6)
	UI.list(row, Enum.FillDirection.Horizontal, gap, Enum.HorizontalAlignment.Center)
	for i, r in list do
		local tile = UI.frame({
			BackgroundColor3 = Color3.fromHex("2B241D"),
			Size = UDim2.new(1 / #list, -math.ceil(gap * (#list - 1) / #list), 1, 0),
			LayoutOrder = i,
			ZIndex = 9,
			Parent = row,
		})
		UI.corner(tile, S(10))
		UI.stroke(tile, r.color, S(2), 0)
		UI.new("UIGradient", {
			Color = ColorSequence.new(Fx.shade(r.color, -0.4), Color3.fromHex("1A1511")),
			Rotation = 90,
			Parent = tile,
		})
		local art = ItemArt.draw(tile, { kind = r.kind, amount = r.amount }, math.floor(height * 0.4), 10)
		art.AnchorPoint = Vector2.new(0.5, 0)
		art.Position = UDim2.new(0.5, 0, 0, S(5))
		local amount = UI.text({
			Text = "+" .. UI.fmtInt(r.amount),
			FontFace = Theme.Fonts.display,
			TextColor3 = Theme.Colors.white,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -S(16)),
			Size = UDim2.new(1, -S(6), 0, S(22)),
			ZIndex = 10,
			Parent = tile,
		})
		fit(amount, S(20), S(10))
		UI.stroke(amount, Color3.new(0, 0, 0), S(1.5), 0.2)
		UI.text({
			Text = r.label,
			FontFace = Theme.Fonts.display,
			TextSize = S(11),
			TextColor3 = Fx.shade(r.color, 0.35),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -S(3)),
			Size = UDim2.new(1, 0, 0, S(13)),
			ZIndex = 10,
			Parent = tile,
		})
		if settled then
			local veil = UI.frame({
				BackgroundColor3 = SETTLED,
				BackgroundTransparency = 0.3,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 30,
				Parent = tile,
			})
			UI.corner(veil, S(10))
		end
	end
	return row
end

-- A dark inset track with a saturated fill. `hero` puts a big ink count above the bar (the daily cards); otherwise the
-- count sits inside it (the poster). With `delay` the fill grows in from empty (the board's entrance).
local function progressBar(
	parent: Instance,
	progress: number,
	target: number,
	barH: number,
	hero: boolean,
	delay: number?
): Frame
	local S = UI.S
	local countH = if hero then S(56) else 0
	local gap = if hero then S(4) else 0
	local root = UI.frame({
		Name = "Progress",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, countH + gap + barH),
		ZIndex = 8,
		Parent = parent,
	})
	local count = UI.fmtInt(progress)
	local total = UI.fmtInt(target)
	if hero then
		UI.text({
			RichText = true,
			Text = string.format('%s<font size="%d" color="#%s"> / %s</font>', count, S(26), INK_SOFT:ToHex(), total),
			FontFace = Theme.Fonts.display,
			TextSize = S(52),
			TextColor3 = INK,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			Size = UDim2.new(1, 0, 0, countH),
			ZIndex = 9,
			Parent = root,
		})
	end
	local track = UI.frame({
		Name = "Track",
		BackgroundColor3 = TRACK,
		Position = UDim2.fromOffset(0, countH + gap),
		Size = UDim2.new(1, 0, 0, barH),
		ZIndex = 9,
		Parent = root,
	})
	UI.corner(track, barH // 2)
	UI.stroke(track, Color3.fromHex("140F0B"), S(2), 0)
	-- The inset: a shadow along the top edge of the track.
	local inset = UI.frame({
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Size = UDim2.fromScale(1, 0.5),
		ZIndex = 10,
		Parent = track,
	})
	UI.corner(inset, barH // 2)
	UI.new("UIGradient", { Transparency = NumberSequence.new(0, 1), Rotation = 90, Parent = inset })
	local k = math.clamp(progress / math.max(target, 1), 0, 1)
	-- Any progress at all shows at least a round nub.
	local size = if k > 0 then UDim2.new(k, math.floor(barH * (1 - k)), 1, 0) else UDim2.fromScale(0, 1)
	local fill = UI.frame({
		Name = "Fill",
		BackgroundColor3 = if k >= 1 then FILL_DONE else FILL,
		Size = if delay then UDim2.fromScale(0, 1) else size,
		ZIndex = 11,
		Parent = track,
	})
	UI.corner(fill, barH // 2)
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)),
		Rotation = 90,
		Parent = fill,
	})
	if delay then
		UI.tween(fill, { Size = size }, Config.JobBarFillSec, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, delay)
	end
	if not hero then
		local l = UI.text({
			Text = count .. " / " .. total,
			FontFace = Theme.Fonts.display,
			TextSize = math.floor(barH * 0.62),
			TextColor3 = Theme.Colors.white,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 12,
			Parent = track,
		})
		UI.stroke(l, Color3.new(0, 0, 0), S(1.5), 0.1)
	end
	return root
end

local function pin(parent: Instance, z: number)
	local S = UI.S
	local shadow = UI.frame({
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, S(2), 0, S(11)),
		Size = UDim2.fromOffset(S(14), S(14)),
		ZIndex = z,
		Parent = parent,
	})
	UI.corner(shadow, S(7))
	local p = UI.frame({
		BackgroundColor3 = Color3.fromHex("E8554D"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, S(8)),
		Size = UDim2.fromOffset(S(18), S(18)),
		ZIndex = z + 1,
		Parent = parent,
	})
	UI.corner(p, S(9))
	UI.stroke(p, Color3.fromHex("7A1E1A"), S(1.5), 0)
	local hi = UI.frame({
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.35,
		Position = UDim2.fromScale(0.22, 0.18),
		Size = UDim2.fromScale(0.32, 0.32),
		ZIndex = z + 2,
		Parent = p,
	})
	UI.corner(hi, S(3))
end

-- A rubber stamp: double-ruled box, display caps, a faint ink wash. With `slamDelay` it slams on after that many
-- seconds (scale in, thump, `shaker` jolts).
local function stamp(parent: Instance, shaker: GuiObject, text: string, color: Color3, z: number, slamDelay: number?)
	local S = UI.S
	local s = UI.frame({
		Name = "Stamp",
		BackgroundColor3 = color,
		BackgroundTransparency = 0.9,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(S(170), S(64)),
		Rotation = -12,
		ZIndex = z,
		Parent = parent,
	})
	UI.corner(s, S(8))
	UI.stroke(s, color, S(4), 0.05)
	local ring = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -S(12), 1, -S(12)),
		ZIndex = z + 1,
		Parent = s,
	})
	UI.corner(ring, S(5))
	UI.stroke(ring, color, S(1.5), 0.15)
	UI.text({
		Text = text,
		FontFace = Theme.Fonts.display,
		TextSize = S(42),
		TextColor3 = color,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 2,
		Parent = s,
	})
	if slamDelay then
		s.Visible = false
		local sc = UI.new("UIScale", { Scale = 2.4, Parent = s })
		task.delay(slamDelay, function()
			if not s.Parent then
				return
			end
			s.Visible = true
			UI.tween(sc, { Scale = 1 }, Config.JobStampSec, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(Config.JobStampSec, function()
				if not s.Parent then
					return
				end
				UI.sound(Fx.Sounds.stamp, 0.7, 0.7)
				Fx.haptic(0.5)
				UI.shake(shaker, S(4), 0.15)
			end)
		end)
	end
	return s
end

-- A pinned sheet. holder (the layout owns it) > Lift (rotated; the entrance moves it) > Shadow, Glow slot, Paper.
-- The shadow sits BEHIND the paper (a child would draw over it). Hover lifts the sheet off the board by growing the
-- shadow only, so nothing slides out from under the cursor. A settled (claimed) sheet lies flat.
local function sheet(holder: Frame, color: Color3, tint: Color3, rotation: number, settled: boolean): (Frame, Frame)
	local S = UI.S
	local lift = UI.frame({
		Name = "Lift",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Rotation = rotation,
		ZIndex = 5,
		Parent = holder,
	})
	local shadow = UI.frame({
		Name = "Shadow",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = if settled then 0.7 else 0.5,
		Position = if settled then UDim2.fromOffset(S(3), S(4)) else UDim2.fromOffset(S(6), S(9)),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = lift,
	})
	UI.corner(shadow, S(6))
	local paper = UI.frame({
		Name = "Paper",
		BackgroundColor3 = color,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = lift,
	})
	UI.corner(paper, S(6))
	UI.stroke(paper, Fx.shade(color, -0.35), S(1.5), 0.3)
	UI.new("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), tint), Rotation = 90, Parent = paper })
	pin(paper, 40)
	if not settled and not UserInputService.TouchEnabled then
		local rest, restT = shadow.Position, shadow.BackgroundTransparency
		holder.MouseEnter:Connect(function()
			UI.tween(
				shadow,
				{ Position = rest + UDim2.fromOffset(S(4), S(6)), BackgroundTransparency = restT - 0.12 },
				0.15
			)
		end)
		holder.MouseLeave:Connect(function()
			UI.tween(shadow, { Position = rest, BackgroundTransparency = restT }, 0.15)
		end)
	end
	return lift, paper
end

-- A claimable sheet breathes a warm glow behind its paper.
local function claimGlow(lift: Frame)
	local _g, setGlow = Fx.glow(lift, SPARK, UI.S(6), 2)
	Fx.pulse(setGlow, function()
		return lift.Parent ~= nil
	end, Config.JobClaimPulseSec, 0.9, 1.7)
end

-- MARLOW: a dummy bust in a sepia frame (hat, domino mask, coat and tie). Square, fits inside `parent`, at most
-- `maxW` of its width.
local function portrait(parent: Instance, z: number, maxW: number): Frame
	local S = UI.S
	local box = UI.frame({
		Name = "Portrait",
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(maxW, 1),
		ZIndex = z,
		Parent = parent,
	})
	UI.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = box })
	UI.corner(box, S(4))
	UI.stroke(box, INK, S(3), 0)
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromHex("9A7046"), Color3.fromHex("3E2A16")),
		Rotation = 90,
		Parent = box,
	})
	local function part(
		color: string,
		ax: number,
		ay: number,
		x: number,
		y: number,
		w: number,
		h: number,
		dz: number,
		round: number?
	): Frame
		local f = UI.frame({
			BackgroundColor3 = Color3.fromHex(color),
			AnchorPoint = Vector2.new(ax, ay),
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromScale(w, h),
			ZIndex = z + dz,
			Parent = box,
		})
		if round then
			UI.new("UICorner", { CornerRadius = UDim.new(round, 0), Parent = f })
		end
		return f
	end
	local skin = "C9A46A"
	-- Everything stays inside the box: clipping is ignored under a rotated sheet.
	part("2B2B33", 0.5, 1, 0.5, 1, 0.86, 0.3, 1, 0.3) -- coat
	part(skin, 0.5, 0.5, 0.5, 0.7, 0.14, 0.12, 1) -- neck
	part("E8E0CC", 0.5, 1, 0.5, 1, 0.18, 0.26, 2) -- shirt
	part("C8323C", 0.5, 1, 0.5, 1, 0.06, 0.24, 3) -- tie
	part(skin, 0.5, 0.5, 0.5, 0.52, 0.36, 0.4, 3, 0.5) -- head
	part("6A4A2A", 0.5, 0.5, 0.53, 0.63, 0.12, 0.022, 4) -- the smirk
	part("1A1A1E", 0.5, 0.5, 0.5, 0.49, 0.44, 0.1, 4, 0.5) -- mask
	part("F2E6C8", 0.5, 0.5, 0.42, 0.49, 0.06, 0.05, 5, 0.5) -- eyes
	part("F2E6C8", 0.5, 0.5, 0.58, 0.49, 0.06, 0.05, 5, 0.5)
	part("1E1E24", 0.5, 1, 0.5, 0.35, 0.36, 0.18, 5, 0.15) -- hat crown
	part("C8323C", 0.5, 1, 0.5, 0.34, 0.36, 0.045, 6) -- hat band
	part("1E1E24", 0.5, 0.5, 0.5, 0.35, 0.62, 0.06, 6, 0.5) -- hat brim
	return box
end

------------------------------------------------------------------ Actions
local render: () -> ()

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

-- CLAIM: shines, sparks burst from it on press, and the claimed keys' PAID stamps slam on the re-render.
local function claimButton(
	parent: Instance,
	text: string,
	size: UDim2,
	keys: { string },
	action: string,
	args: any,
	title: string
): TextButton
	local S = UI.S
	local b, _ = Fx.button(parent, text, GREEN, Theme.Colors.white, size, 12)
	b.TextSize = S(26)
	Fx.shine(b, 2.2)
	local busy = false
	b.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		-- Marked before the call: the sync that re-renders the board can land before the reply.
		for _, k in keys do
			justClaimed[k] = true
		end
		local layer = fxLayer
		if layer then
			local c = b.AbsolutePosition + b.AbsoluteSize / 2
			Fx.burst(layer, UDim2.fromOffset(c.X, c.Y), SPARK, 18, 60)
		end
		local res = shop(action, args)
		if not res.ok then
			for _, k in keys do
				justClaimed[k] = nil
			end
			busy = false
		end
		claimWith(res, title)
	end)
	return b
end

-- A claimed Job: NEW JOB swaps it for a fresh one for a little fake Robux.
local function refreshButton(parent: Instance, key: string, weekly: boolean, size: UDim2): TextButton
	local S = UI.S
	local pid = if weekly then "job_refresh_bounty" else "job_refresh_daily"
	local price = JobPool.RefreshPrice[if weekly then "bounty" else "daily"]
	local b, _ = Fx.button(
		parent,
		string.format("%s · R$ %d", if weekly then "NEW BOUNTY" else "NEW JOB", price),
		Color3.fromHex("4D9FE8"),
		Theme.Colors.white,
		size,
		12
	)
	UI.pad(b, S(8), 0, S(8), 0)
	fit(b, S(20), S(10))
	Fx.shine(b, 2.6)
	b.Activated:Connect(function()
		PurchaseSheet.open(pid, {
			context = "jobs refresh " .. key,
			args = { key = key },
			note = "Swaps this finished Job for a fresh one with its own rewards.",
			onSuccess = function()
				UI.sound(Fx.Sounds.tear, 0.8, 0.5)
			end,
		})
	end)
	return b
end

-- Round 19c: the small R in a sheet's corner swaps any unfinished Job (a solo player's REVIVE 3 TEAMMATES). Blue
-- while today's free reroll is left (Config.JobFreeRerollsPerDay); after that it opens the fake-Robux REFRESH.
local function rerollButton(parent: Instance, key: string, weekly: boolean): TextButton
	local S = UI.S
	local p = profile()
	local used = tonumber(p and p.jobs and p.jobs.rerollUsed) or 0
	local free = used < Config.JobFreeRerollsPerDay
	local size = S(30)
	local b = UI.button({
		Name = "Reroll",
		Text = "R",
		FontFace = Theme.Fonts.display,
		TextSize = S(17),
		TextColor3 = Theme.Colors.white,
		BackgroundColor3 = if free then Color3.fromHex("4D9FE8") else Color3.fromHex("6E7C8C"),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(8), 0, S(8)),
		Size = UDim2.fromOffset(size, size),
		ZIndex = 20,
		Parent = parent,
	})
	UI.corner(b, size / 2)
	UI.stroke(b, INK, S(1.5), 0.4)
	local busy = false
	b.Activated:Connect(function()
		if busy then
			return
		end
		UI.punch(b, 0.85, 0.15)
		if free then
			busy = true
			local res = shop("jobReroll", { key = key })
			busy = false
			if res.ok then
				UI.sound(Fx.Sounds.tear, 0.8, 0.5)
			else
				PurchaseSheet.toast(tostring(res.reason or "Not now"), Theme.Colors.malus, false)
			end
			return
		end
		PurchaseSheet.open(if weekly then "job_refresh_bounty" else "job_refresh_daily", {
			context = "jobs reroll " .. key,
			args = { key = key },
			note = "Today's free reroll is used. Swap this Job for a fresh one with its own rewards.",
			onSuccess = function()
				UI.sound(Fx.Sounds.tear, 0.8, 0.5)
			end,
		})
	end)
	return b
end

------------------------------------------------------------------ Cards
-- One daily card, a third of the dailies' width and their full height:
--   tag, title, MARLOW's line (top) · the state area (flexes) · the reward row (bottom)
local function dailyCard(parent: Frame, slot: number, e: any, order: number): Frame?
	local S = UI.S
	local def = JobPool.ById[e.id]
	if not def then
		return nil
	end
	local key = "d" .. slot
	local progress = tonumber(e.progress) or 0
	local done = progress >= def.target
	local claimed = e.claimed == true
	local at = if entrance then (order - 1) * Config.JobBoardStaggerSec else nil -- this card's cascade start
	local holder = UI.frame({
		Name = "Daily" .. slot,
		BackgroundTransparency = 1,
		Size = UDim2.new(1 / 3, -S(15), 1, 0),
		LayoutOrder = order,
		ZIndex = 5,
		Parent = parent,
	})
	local lift, paper = sheet(
		holder,
		if claimed then PAPER:Lerp(SETTLED, 0.6) else PAPER,
		Color3.fromHex("E2E2E2"),
		-- A finished sheet is pulled straight (and its CLAIM shine needs an unrotated ancestor to clip).
		if claimed or done then 0 else (({ -1.6, 1.2, -0.8 })[slot] or 0),
		claimed
	)
	local inner = UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 7, Parent = paper })
	UI.pad(inner, S(20), S(28), S(20), S(18))
	local inkT = if claimed then 0.35 else 0
	-- Top: tag, title, line.
	local gap = S(6)
	local titleH, quoteH = S(72), S(60)
	local topH = S(22) + titleH + quoteH + gap * 2
	local top = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, topH),
		ZIndex = 7,
		Parent = inner,
	})
	UI.list(top, Enum.FillDirection.Vertical, gap)
	tag(top, "DAILY JOB", 1)
	local title = UI.text({
		Text = def.title,
		FontFace = Theme.Fonts.display,
		TextColor3 = INK,
		TextTransparency = inkT,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, titleH),
		LayoutOrder = 2,
		ZIndex = 8,
		Parent = top,
	})
	fit(title, S(32), S(18))
	quote(top, def.flavor, quoteH, S(16), inkT, false)
	-- Bottom: the rewards.
	local rewardsH = S(80)
	rewardTiles(inner, false, rewardsH, claimed)
	-- Between them: the state.
	local space = S(12)
	local mid = UI.frame({
		Name = "State",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, topH + space),
		Size = UDim2.new(1, 0, 1, -(topH + rewardsH + space * 2)),
		ZIndex = 9,
		Parent = inner,
	})
	if claimed or done then
		local btnH = if claimed then S(48) else S(56)
		-- The stamp lands in the space above the button (it may overlap the line above, like a real stamp).
		local upper = UI.frame({
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -(btnH + S(8))),
			ZIndex = 9,
			Parent = mid,
		})
		local b: TextButton
		if claimed then
			stamp(upper, lift, "PAID", PAID, 20, if justClaimed[key] then (at or 0) + 0.1 else nil)
			justClaimed[key] = nil
			b = refreshButton(mid, key, false, UDim2.new(1, 0, 0, btnH))
		else
			local first = not seenDone[e.id]
			seenDone[e.id] = true
			stamp(upper, lift, "DONE", STAMP, 20, if first then (at or 0) + 0.35 else nil)
			b = claimButton(mid, "CLAIM", UDim2.new(1, 0, 0, btnH), { key }, "jobClaim", { key = key }, def.title)
			Fx.particles(mid, SPARK, 4, 15)
			claimGlow(lift)
		end
		b.AnchorPoint = Vector2.new(0.5, 1)
		b.Position = UDim2.fromScale(0.5, 1)
	else
		local bar = progressBar(mid, progress, def.target, S(24), true, if at then at + 0.25 else nil)
		bar.AnchorPoint = Vector2.new(0, 0.5)
		bar.Position = UDim2.fromScale(0, 0.5)
		rerollButton(paper, key, false)
	end
	return holder
end

-- The WANTED poster: WANTED, tag (top) · MARLOW's portrait (flexes) · title, line, progress or the action, the reward
-- row (bottom).
local function bountyCard(parent: Frame, e: any, order: number): Frame?
	local S = UI.S
	local def = JobPool.ById[e.id]
	if not def then
		return nil
	end
	local key = "b1"
	local progress = tonumber(e.progress) or 0
	local done = progress >= def.target
	local claimed = e.claimed == true
	local at = if entrance then (order - 1) * Config.JobBoardStaggerSec else nil
	local holder = UI.frame({
		Name = "Bounty",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = parent,
	})
	local lift, paper = sheet(
		holder,
		if claimed then POSTER:Lerp(SETTLED, 0.5) else POSTER,
		Color3.fromHex("D6D6D6"),
		if claimed or done then 0 else 1.2,
		claimed
	)
	local inner = UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 7, Parent = paper })
	UI.pad(inner, S(18), S(26), S(18), S(16))
	local inkT = if claimed then 0.35 else 0
	-- Top: WANTED and the tag.
	local wantedH = S(46)
	local topH = wantedH + S(4) + S(22)
	local top = UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, topH), ZIndex = 7, Parent = inner })
	UI.list(top, Enum.FillDirection.Vertical, S(4), Enum.HorizontalAlignment.Center)
	UI.text({
		Text = "WANTED",
		FontFace = Theme.Fonts.display,
		TextSize = S(46),
		TextColor3 = Color3.fromHex("5A1E10"),
		TextTransparency = inkT,
		Size = UDim2.new(1, 0, 0, wantedH),
		LayoutOrder = 1,
		ZIndex = 8,
		Parent = top,
	})
	tag(top, "WEEKLY BOUNTY", 2)
	-- Bottom, stacked up from the edge: rewards, the slot (progress / CLAIM / NEW BOUNTY), the line, the title.
	local gap = S(10)
	local rewardsH, slotH, quoteH, titleH = S(80), S(48), S(52), S(54)
	rewardTiles(inner, true, rewardsH, claimed)
	local slot = UI.frame({
		Name = "Slot",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -(rewardsH + gap)),
		Size = UDim2.new(1, 0, 0, slotH),
		ZIndex = 9,
		Parent = inner,
	})
	local q = quote(inner, def.flavor, quoteH, S(15), inkT, true)
	q.AnchorPoint = Vector2.new(0, 1)
	q.Position = UDim2.new(0, 0, 1, -(rewardsH + slotH + gap * 2))
	local title = UI.text({
		Text = def.title,
		FontFace = Theme.Fonts.display,
		TextColor3 = INK,
		TextTransparency = inkT,
		TextWrapped = true,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -(rewardsH + slotH + quoteH + gap * 2 + S(4))),
		Size = UDim2.new(1, 0, 0, titleH),
		ZIndex = 8,
		Parent = inner,
	})
	fit(title, S(28), S(16))
	local lowerH = rewardsH + slotH + quoteH + titleH + gap * 2 + S(4)
	-- Between: MARLOW's portrait, as big as the poster allows.
	local mid = UI.frame({
		Name = "Mid",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, topH + S(8)),
		Size = UDim2.new(1, 0, 1, -(topH + lowerH + S(16))),
		ZIndex = 9,
		Parent = inner,
	})
	local face = portrait(mid, 9, 0.8)
	if claimed then
		face.BackgroundTransparency = 0.4
		stamp(mid, lift, "PAID", PAID, 30, if justClaimed[key] then (at or 0) + 0.1 else nil)
		justClaimed[key] = nil
		refreshButton(slot, key, true, UDim2.fromScale(1, 1))
	elseif done then
		local first = not seenDone[e.id]
		seenDone[e.id] = true
		stamp(mid, lift, "DONE", STAMP, 30, if first then (at or 0) + 0.35 else nil)
		claimButton(slot, "CLAIM", UDim2.fromScale(1, 1), { key }, "jobClaim", { key = key }, def.title)
		Fx.particles(slot, SPARK, 3, 15)
		claimGlow(lift)
	else
		local bar = progressBar(slot, progress, def.target, S(32), false, if at then at + 0.25 else nil)
		bar.AnchorPoint = Vector2.new(0, 0.5)
		bar.Position = UDim2.fromScale(0, 0.5)
		rerollButton(paper, key, true)
	end
	return holder
end

-- A framed countdown: small caps label over a big ticking value.
local function timerChip(parent: Instance, label: string, color: Color3, anchor: Vector2, pos: UDim2): TextLabel
	local S = UI.S
	local fr = UI.frame({
		BackgroundColor3 = Color3.fromHex("15121A"),
		BackgroundTransparency = 0.08,
		AnchorPoint = anchor,
		Position = pos,
		Size = UDim2.fromOffset(S(230), S(50)),
		ZIndex = 6,
		Parent = parent,
	})
	UI.corner(fr, S(10))
	UI.stroke(fr, color, S(2), 0.15)
	UI.text({
		Text = label,
		FontFace = Theme.Fonts.display,
		TextSize = S(12),
		TextColor3 = Fx.shade(color, 0.35),
		Position = UDim2.fromOffset(0, S(5)),
		Size = UDim2.new(1, 0, 0, S(13)),
		ZIndex = 7,
		Parent = fr,
	})
	local v = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(26),
		TextColor3 = Theme.Colors.white,
		Position = UDim2.fromOffset(0, S(17)),
		Size = UDim2.new(1, 0, 0, S(30)),
		ZIndex = 7,
		Parent = fr,
	})
	UI.stroke(v, Color3.new(0, 0, 0), S(1.5), 0.2)
	return v
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
	-- Columns: the dailies left, the poster right; the countdowns sit over the column they count for.
	local posterW = if mobile then 0.31 else 0.27
	local colGap = S(28)
	local headerH, footerH = S(56), S(54)
	local boardTop, boardBottom = headerH + S(10), footerH + S(14)
	local header = UI.frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, headerH), ZIndex = 5, Parent = b })
	local title = UI.text({
		Text = "JOBS",
		FontFace = Theme.Fonts.display,
		TextSize = S(44),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0, S(160), 1, 0),
		ZIndex = 6,
		Parent = header,
	})
	UI.stroke(title, Color3.new(0, 0, 0), S(2), 0.2)
	local daily = timerChip(
		header,
		"NEW JOBS IN",
		Theme.Colors.gold,
		Vector2.new(0.5, 0.5),
		UDim2.new((1 - posterW) / 2, -colGap / 2, 0.5, 0) -- centered over the three dailies
	)
	local weekly =
		timerChip(header, "BOUNTY RESETS IN", STAMP, Vector2.new(0.5, 0.5), UDim2.new(1 - posterW / 2, -S(3), 0.5, 0))
	task.spawn(function()
		while daily.Parent do
			local t = ClientState.fakeNow()
			daily.Text = Clock.hms(Clock.nextDay(t) - t)
			weekly.Text = Clock.dhm(Clock.nextWeek(t) - t)
			task.wait(0.25)
		end
	end)
	local dailies = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, boardTop),
		Size = UDim2.new(1 - posterW, -colGap, 1, -(boardTop + boardBottom)),
		ZIndex = 5,
		Parent = b,
	})
	UI.list(dailies, Enum.FillDirection.Horizontal, S(22), Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	local sheets: { GuiObject } = {}
	local claimable: { string } = {}
	for i, e in jobs.daily do
		local card = dailyCard(dailies, i, e, i)
		if card then
			table.insert(sheets, card)
		end
		local def = JobPool.ById[e.id]
		if def and (tonumber(e.progress) or 0) >= def.target and not e.claimed then
			table.insert(claimable, "d" .. i)
		end
	end
	local bounty = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(6), 0, boardTop),
		Size = UDim2.new(posterW, 0, 1, -(boardTop + boardBottom)),
		ZIndex = 5,
		Parent = b,
	})
	local be = jobs.bounty[1]
	if be then
		local card = bountyCard(bounty, be, #sheets + 1)
		if card then
			table.insert(sheets, card)
		end
		local def = JobPool.ById[be.id]
		if def and (tonumber(be.progress) or 0) >= def.target and not be.claimed then
			table.insert(claimable, "b1")
		end
	end
	-- Footer.
	local footer = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, footerH),
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
	if #claimable > 1 then
		local all = claimButton(
			footer,
			string.format("CLAIM ALL (%d)", #claimable),
			UDim2.fromOffset(S(230), S(50)),
			claimable,
			"jobClaimAll",
			{},
			"JOBS PAID"
		)
		all.TextSize = S(20)
	end
	local back, _ = Fx.button(footer, "BACK", Theme.Colors.red, Theme.Colors.white, UDim2.fromOffset(S(160), S(50)), 6)
	back.TextSize = S(20)
	back.LayoutOrder = 2
	back.Activated:Connect(function()
		JobBoard.close()
	end)
	if entrance then
		entrance = false
		Fx.cascade(sheets, Config.JobBoardStaggerSec, 30)
	end
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
		Position = UDim2.fromOffset(S(30), Fx.topInset()),
		Size = UDim2.new(1, -S(60), 1, -Fx.topInset() - S(16)),
		ZIndex = 5,
		Parent = g,
	})
	fxLayer = UI.frame({
		Name = "Fx",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
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
	entrance = true
	render()
	Fx.slideIn(body :: Frame, UDim2.fromOffset(0, S(24)), 0.3)
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
	fxLayer = nil
	entrance = false
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
	local slot = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(S(8), S(8)),
		Size = UDim2.fromOffset(S(62), S(62)),
		ZIndex = 3,
		Parent = card,
	})
	portrait(slot, 3, 1)
	UI.text({
		Text = "MARLOW · JOBS",
		FontFace = Theme.Fonts.display,
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
		FontFace = Theme.Fonts.body,
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
