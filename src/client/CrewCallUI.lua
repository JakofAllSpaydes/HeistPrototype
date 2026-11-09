--!strict
-- Crew call component. Everything lives in one box in the top-right corner: the call card slides in
-- from the right edge, collapses in place to the timer pill, expands back for the result card, then
-- slides out. Result and arms-drop toasts go to the center slot with the other system notices.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lines = require(Shared:WaitForChild("CrewCall"):WaitForChild("Lines"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local Hint = require(script.Parent:WaitForChild("Hint"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local HUD = require(script.Parent:WaitForChild("HUD"))

local CrewCallUI = {}

local KIND_COLORS = {
	job = Theme.Colors.blue,
	door = Theme.Colors.amber,
	ftue = Theme.Colors.grey,
	legendary = Theme.Colors.gold,
}

local CARD_H = 112
local PILL_H = 38
local SLIDE = 420 -- px (pre-scale) the box travels when sliding in from / out to the right edge

-- Round 24: one box per slot, stacked in the top-right column: "door" (a door objective, top), "job" (the side
-- job), "vault" (the open vault's pill), "line" (a crew line with no job). Each { data, box, inner, timerLabel,
-- stroke, token }. A door no longer ends the side job, so both pills run at once.
local slots: { [string]: any } = {}
local callToken = 0
local SLOT_ORDER = { door = 0, job = 1, vault = 1, line = 1 }

local function slotKey(data: any): string
	if data.id == "vault" then
		return "vault"
	elseif data.id == "line" then
		return "line"
	elseif data.jobKind == "door" then
		return "door"
	end
	return "job"
end

-- The slot showing call `id`, if any.
local function slotOf(id: any): string?
	for key, call in slots do
		if call.data and call.data.id == id then
			return key
		end
	end
	return nil
end

local function centerSlot()
	return HUD.get("callSlot")
end

local function home()
	return HUD.get("topRight")
end

local function fmtTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function destroySlot(key: string)
	local call = slots[key]
	if call and call.box then
		call.box:Destroy()
	end
	slots[key] = nil
end

-- The outer box clips; `inner` is what slides. Content frames are parented to inner.
local function buildBox(height: number, order: number?): (Frame, Frame)
	local S = UI.S
	local h = home()
	local box = UI.frame({
		Name = "CallBox",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(h.width, S(height)),
		ClipsDescendants = true,
	})
	local inner = UI.frame({
		Name = "Inner",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.fromOffset(0, 0),
		Parent = box,
	})
	h.add(box, order or 1)
	return box, inner
end

local function buildPill(parent: Instance, data: any, progress: number?): (Frame, TextLabel, UIStroke)
	local S = UI.S
	local color = KIND_COLORS[data.kind] or Theme.Colors.blue
	local pill = UI.frame({
		Name = "CallPill",
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.new(1, 0, 0, S(PILL_H)),
		Parent = parent,
	})
	UI.corner(pill, S(PILL_H / 2))
	local stroke = UI.stroke(pill, color, S(2))
	local icon = UI.frame({
		BackgroundColor3 = color,
		Position = UDim2.fromOffset(S(8), S(7)),
		Size = UDim2.fromOffset(S(24), S(24)),
		Parent = pill,
	})
	UI.corner(icon, S(6))
	UI.text({
		Text = "!",
		FontFace = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.bg,
		Size = UDim2.fromScale(1, 1),
		Parent = icon,
	})
	UI.text({
		Text = data.name,
		FontFace = Theme.Fonts.display,
		TextSize = S(16),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(40), 0),
		Size = UDim2.new(0.5, 0, 1, 0),
		Parent = pill,
	})
	local timer = UI.text({
		Text = "1:15",
		FontFace = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(100), 0, 0),
		Size = UDim2.fromOffset(S(70), S(PILL_H)),
		Parent = pill,
	})
	UI.text({
		Text = data.rewardShort or data.rewardLine,
		TextSize = S(12),
		TextColor3 = Theme.Colors.cash,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(12), 0, 0),
		Size = UDim2.fromOffset(S(84), S(PILL_H)),
		Parent = pill,
	})
	-- Capture point: a thin progress bar along the bottom of the pill.
	if data.jobKind == "capture" then
		local bar = UI.frame({
			Name = "Progress",
			BackgroundColor3 = Theme.Colors.bg,
			Position = UDim2.new(0, S(14), 1, -S(7)),
			Size = UDim2.new(1, -S(28), 0, S(4)),
			ZIndex = 3,
			Parent = pill,
		})
		UI.corner(bar, S(2))
		local fill = UI.frame({
			Name = "Fill",
			BackgroundColor3 = Theme.Colors.cash,
			Size = UDim2.fromScale(progress or 0, 1),
			ZIndex = 3,
			Parent = bar,
		})
		UI.corner(fill, S(2))
	end
	return pill, timer, stroke
end

local function setPillProgress(call: any, progress: number, inside: boolean)
	if not call or not call.box then
		return
	end
	local bar = call.box:FindFirstChild("Progress", true)
	local fill = bar and bar:FindFirstChild("Fill")
	if fill and fill:IsA("Frame") then
		fill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
		fill.BackgroundColor3 = if inside then Theme.Colors.cash else Theme.Colors.malus
	end
end

-- Dialogue types out character by character with a soft tick; the portrait head bobs while "talking".
local function typewrite(label: TextLabel, head: GuiObject)
	local text = label.Text
	local total = utf8.len(text) or #text
	label.MaxVisibleGraphemes = 0
	task.spawn(function()
		local shown = 0
		local perChar = 1 / math.max(Config.CallTypeCharsPerSec, 1)
		while shown < total and label.Parent do
			shown += 1
			label.MaxVisibleGraphemes = shown
			if shown % 3 == 0 and string.sub(text, shown, shown) ~= " " then
				UI.sound(Theme.Sounds.reelTick, 1.5 + math.random() * 0.5, 0.06)
			end
			if shown % 5 == 0 and head.Parent then
				UI.punch(head, 1.12, 0.14)
			end
			task.wait(perChar)
		end
		if label.Parent then
			label.MaxVisibleGraphemes = -1
		end
	end)
end

-- Player headshots for ally callouts and the completer on a finished job, cached per user.
local headshots: { [number]: string } = {}
local function headshot(userId: number): string
	local cached = headshots[userId]
	if cached then
		return cached
	end
	local ok, url = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	local img = if ok and typeof(url) == "string" then url else ""
	headshots[userId] = img
	return img
end

-- An NPC's portrait (Round 16): a blocky dummy bust in a ViewportFrame (classic head with the default face,
-- torso, shoulders, a collar in the NPC's accent color, a hair cap), colored per Lines.portraits.
local function dummyBust(parent: GuiObject, crewLead: string): ViewportFrame
	local look = Lines.portraits[crewLead] or Lines.portraits.default
	local vp = UI.new("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(150, 150, 160),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-0.4, -1, 0.6),
		Parent = parent,
	}) :: ViewportFrame
	local function block(size: Vector3, cf: CFrame, hex: string): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.Size = size
		p.CFrame = cf
		p.Color = Color3.fromHex(hex)
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = vp
		return p
	end
	block(Vector3.new(2, 2, 1), CFrame.new(0, 0, 0), look.shirt)
	block(Vector3.new(1, 2, 1), CFrame.new(1.5, 0, 0), look.shirt)
	block(Vector3.new(1, 2, 1), CFrame.new(-1.5, 0, 0), look.shirt)
	block(Vector3.new(1.1, 0.25, 1.05), CFrame.new(0, 0.95, 0), look.accent)
	local head = block(Vector3.new(2, 1, 1), CFrame.new(0, 1.5, 0), look.skin)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head
	local face = Instance.new("Decal")
	face.Face = Enum.NormalId.Front
	face.Texture = "rbxasset://textures/face.png"
	face.Parent = head
	local hair = block(Vector3.new(1.3, 0.35, 1.3), CFrame.new(0, 2.05, 0.05), look.hair)
	local hairMesh = Instance.new("SpecialMesh")
	hairMesh.MeshType = Enum.MeshType.Head
	hairMesh.Scale = Vector3.new(1, 1.2, 1)
	hairMesh.Parent = hair
	local cam = Instance.new("Camera")
	cam.FieldOfView = 34
	cam.CFrame = CFrame.lookAt(Vector3.new(0.9, 1.4, -5.2), Vector3.new(0, 1.05, 0))
	cam.Parent = vp
	vp.CurrentCamera = cam
	return vp
end

type CardSpec = {
	kind: string,
	crewLead: string,
	label: string, -- type pill text or result title
	labelColor: Color3?,
	text: { string },
	rewardLine: string,
	showTimer: boolean,
	duration: number?,
	portraitImage: string?, -- an ally callout: the player's headshot instead of MARLOW's silhouette
	noPill: boolean?, -- no type pill beside the name
}

local function buildCard(parent: Instance, spec: CardSpec): (Frame, TextLabel, UIStroke)
	local S = UI.S
	local color = spec.labelColor or KIND_COLORS[spec.kind] or Theme.Colors.blue
	local h = S(CARD_H)
	local frame = UI.frame({
		Name = "CallCard",
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.new(1, 0, 0, h),
		Parent = parent,
	})
	UI.corner(frame, S(12))
	local stroke = UI.stroke(frame, color, S(2))
	local portrait = UI.frame({
		BackgroundColor3 = Theme.Colors.panel2,
		Position = UDim2.fromOffset(S(10), S(10)),
		Size = UDim2.fromOffset(h - S(20), h - S(20)),
		Parent = frame,
	})
	UI.corner(portrait, S(10))
	local head: GuiObject
	if spec.portraitImage and spec.portraitImage ~= "" then
		local img = UI.new("ImageLabel", {
			BackgroundTransparency = 1,
			Image = spec.portraitImage,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.94, 0.94),
			Parent = portrait,
		}) :: ImageLabel
		UI.corner(img, S(9))
		head = img
	else
		portrait.ClipsDescendants = true
		head = dummyBust(portrait, spec.crewLead)
	end
	local textX = h + S(4)
	UI.text({
		Text = spec.crewLead,
		FontFace = Theme.Fonts.display,
		TextSize = S(18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(textX, S(8)),
		Size = if spec.noPill then UDim2.new(1, -textX - S(10), 0, S(24)) else UDim2.fromOffset(S(120), S(24)),
		Parent = frame,
	})
	if not spec.noPill then
		local labelPill = UI.pill(frame, spec.label, color, Theme.Colors.bg, S(16), S(10))
		labelPill.Position = UDim2.fromOffset(textX + S(96), S(12))
	end
	local timer = UI.text({
		Text = if spec.duration then fmtTime(spec.duration) else "",
		FontFace = Theme.Fonts.display,
		TextSize = S(20),
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(10), 0, S(8)),
		Size = UDim2.fromOffset(S(60), S(26)),
		Visible = spec.showTimer,
		Parent = frame,
	})
	local body = UI.text({
		Text = table.concat(spec.text, "\n"),
		TextSize = S(11),
		TextColor3 = Theme.Colors.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Position = UDim2.fromOffset(textX, S(36)),
		Size = UDim2.new(1, -textX - S(10), 0, S(46)),
		Parent = frame,
	})
	typewrite(body, head)
	UI.text({
		Text = spec.rewardLine,
		FontFace = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Theme.Colors.cash,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(textX, h - S(28)),
		Size = UDim2.new(1, -textX, 0, S(22)),
		Parent = frame,
	})
	return frame, timer, stroke
end

local function slideIn(inner: Frame)
	inner.Position = UDim2.fromOffset(UI.S(SLIDE), 0)
	UI.tween(inner, { Position = UDim2.fromOffset(0, 0) }, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

local function slideOut(inner: Frame): Tween
	return UI.tween(
		inner,
		{ Position = UDim2.fromOffset(UI.S(SLIDE), 0) },
		0.3,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
end

local function resizeBox(box: Frame, height: number): Tween
	return UI.tween(
		box,
		{ Size = UDim2.fromOffset(home().width, UI.S(height)) },
		0.25,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
end

local function onCallStart(data: any)
	local key = slotKey(data)
	destroySlot(key)
	callToken += 1
	local token = callToken
	local box, inner = buildBox(CARD_H, SLOT_ORDER[key])
	local card, timer, stroke = buildCard(inner, {
		kind = data.kind,
		crewLead = data.crewLead,
		label = data.typeLabel,
		text = data.text,
		rewardLine = data.rewardLine,
		showTimer = true,
		duration = data.duration,
	})
	local call = {
		data = data,
		box = box,
		inner = inner,
		timerLabel = timer,
		stroke = stroke,
		token = token,
		progress = 0,
		lastTick = 0,
	}
	slots[key] = call
	slideIn(inner)
	UI.sound(Theme.Sounds.call, 1, 0.6)

	task.delay(Config.CallHoldSec, function()
		if slots[key] ~= call then
			return
		end
		-- Collapse in place: shrink the box to pill height while the pill takes over.
		local pill, pillTimer, pillStroke = buildPill(inner, data, call.progress)
		pill.BackgroundTransparency = 1
		pill.ZIndex = 2
		UI.tween(card, { BackgroundTransparency = 1 }, 0.15)
		for _, d in card:GetDescendants() do
			if d:IsA("TextLabel") then
				UI.tween(d, { TextTransparency = 1 }, 0.12)
			elseif d:IsA("Frame") then
				UI.tween(d, { BackgroundTransparency = 1 }, 0.12)
			elseif d:IsA("UIStroke") then
				UI.tween(d, { Transparency = 1 }, 0.12)
			end
		end
		UI.tween(pill, { BackgroundTransparency = 0 }, 0.2, nil, nil, 0.1)
		local shrink = resizeBox(box, PILL_H)
		shrink.Completed:Wait()
		if slots[key] ~= call then
			return
		end
		card:Destroy()
		UI.punch(pill, 1.1, 0.3)
		call.timerLabel = pillTimer
		call.stroke = pillStroke
	end)
end

-- Half-time reminder: the pill expands back into a card with the nudge, then collapses again. The capture
-- progress and the timer carry over.
local function onCallReminder(data: any)
	local key = slotOf(data.id)
	local call = key and slots[key]
	if not call then
		return
	end
	local progress = call.progress or 0
	local d = table.clone(call.data)
	d.text = data.text or d.text
	d.typeLabel = data.title or d.typeLabel
	onCallStart(d)
	local now = slots[slotKey(d)]
	if now then
		now.progress = progress
		now.wasInside = call.wasInside
	end
	centerSlot().toast(tostring(data.title or "STILL OPEN"), Theme.Colors.amber, 1.2)
end

-- Result: expand from the pill into a "nice work" / "too slow" card, hold, slide out. Toast in the center.
local function onCallEnd(data: any)
	local key = slotOf(data.id) or slotKey(data)
	callToken += 1
	local token = callToken
	local color = if data.success then Theme.Colors.cash else Theme.Colors.red
	local box: Frame
	local inner: Frame
	local old = slots[key]
	if old and old.box and old.box.Parent and old.data and old.data.id == data.id then
		box = old.box
		inner = old.inner
		for _, c in inner:GetChildren() do
			c:Destroy()
		end
	else
		box, inner = buildBox(PILL_H, SLOT_ORDER[key])
		slideIn(inner)
	end
	-- Round 16: a success is the completer's card (their headshot, name, their own line), not MARLOW's.
	local by = if data.success and typeof(data.by) == "table" and #data.by > 0 then data.by else nil
	local crewLead = data.crewLead or Lines.job.crewLead
	local portraitImage: string? = nil
	local text = data.text or {}
	if by then
		crewLead = string.upper(tostring(by[1].name))
		if #by > 1 then
			crewLead ..= string.format(" + %d", #by - 1)
		end
		portraitImage = headshot(tonumber(by[1].userId) or 0)
		text = data.byText or text
	end
	local card = buildCard(inner, {
		kind = data.kind or "job",
		crewLead = crewLead,
		label = data.title or (if data.success then Lines.job.doneTitle else Lines.failToast),
		labelColor = color,
		text = text,
		rewardLine = data.rewardLine or "",
		showTimer = false,
		portraitImage = portraitImage,
	})
	local call = { data = data, box = box, inner = inner, timerLabel = nil, stroke = nil, token = token }
	slots[key] = call
	resizeBox(box, CARD_H)
	UI.sound(if data.success then Theme.Sounds.legendary else Theme.Sounds.deny, if data.success then 1.1 else 0.8, 0.6)
	if data.success then
		UI.punch(card, 1.06, 0.4)
		ClientState.Juice:Fire("Shake", { amp = 0.2, dur = 0.25 })
	else
		UI.shake(card, UI.S(3), 0.3)
	end
	centerSlot().toast(tostring(data.toast), color, 1.2)

	task.delay(Config.CallHoldSec, function()
		if not box.Parent then
			return
		end
		local out = slideOut(inner)
		out.Completed:Wait()
		if slots[key] == call then
			destroySlot(key)
		else
			box:Destroy()
		end
	end)
end

-- A line with no job behind it (MARLOW's boss call): the card slides in, holds, slides out.
local function onCrewLine(data: any)
	destroySlot("line")
	callToken += 1
	local token = callToken
	local box, inner = buildBox(CARD_H, SLOT_ORDER.line)
	buildCard(inner, {
		kind = tostring(data.kind or "door"),
		crewLead = tostring(data.crewLead or Lines.job.crewLead),
		label = tostring(data.typeLabel or ""),
		text = data.text or {},
		rewardLine = "",
		showTimer = false,
	})
	local call = { data = { id = "line" }, box = box, inner = inner, timerLabel = nil, stroke = nil, token = token }
	slots.line = call
	slideIn(inner)
	UI.sound(Theme.Sounds.call, 0.9, 0.6)
	task.delay(tonumber(data.hold) or Config.CallHoldSec, function()
		if slots.line ~= call or not box.Parent then
			return
		end
		local out = slideOut(inner)
		out.Completed:Wait()
		if slots.line == call then
			destroySlot("line")
		end
	end)
end

-- A pill with no card first (the open vault's VAULT · 0:60 timer).
local function showPill(data: any)
	local key = slotKey(data)
	destroySlot(key)
	callToken += 1
	local box, inner = buildBox(PILL_H, SLOT_ORDER[key])
	local pill, timer, stroke = buildPill(inner, data)
	slots[key] = { data = data, box = box, inner = inner, timerLabel = timer, stroke = stroke, token = callToken }
	slideIn(inner)
	UI.punch(pill, 1.1, 0.3)
end

local function slideOutSlot(key: string)
	local call = slots[key]
	if not call or not call.box or not call.box.Parent then
		return
	end
	local out = slideOut(call.inner)
	out.Completed:Wait()
	if slots[key] == call then
		destroySlot(key)
	end
end

-- The vault: VAULT pill while the loot window runs, MARLOW's gas card at the warning (collapses back
-- to the pill, red under CallPillWarnSec), gone when the room seals.
local function onVaultOpen(data: any)
	showPill({
		id = "vault",
		jobKind = "vault",
		kind = "door",
		name = tostring(data.name or Lines.vault.pillName),
		crewLead = Lines.vault.crewLead,
		typeLabel = Lines.vault.typeLabel,
		text = {},
		rewardLine = "",
		-- Brief 7: on THE BANK the pill's side line says the tunnel is open (the back way out).
		rewardShort = Hint.swap(tostring(data.tunnelText or data.hint or Lines.vault.lootHint)),
		endsAt = tonumber(data.endsAt) or 0,
		duration = tonumber(data.openSec) or Config.VaultOpenSec,
	})
end

local function onVaultGas(data: any)
	if data.phase == "warn" then
		onCallStart({
			id = "vault",
			jobKind = "vault",
			kind = "door",
			name = Lines.vault.pillName,
			crewLead = tostring(data.crewLead or Lines.vault.crewLead),
			typeLabel = tostring(data.title or Lines.vault.gasTitle),
			text = data.text or Lines.vault.gasText,
			rewardLine = "",
			rewardShort = Lines.vault.gasHint,
			endsAt = tonumber(data.endsAt) or 0,
			duration = Config.VaultGasWarnSec,
		})
	else
		local call = slots.vault
		if call and call.data and call.data.id == "vault" then
			call.data.endsAt = nil
			if call.timerLabel then
				call.timerLabel.Text = Lines.vault.gasTitle
				call.timerLabel.TextColor3 = Theme.Colors.red
			end
		end
	end
end

------------------------------------------------------------------ Ally callouts (brief 5)
-- A teammate's radio line: the crew-call shell with their Roblox headshot and name, a red frame (gold for Revive
-- Everybody), CalloutSec on screen in its own box under the job pill. Callouts queue behind a live MARLOW card
-- and wait out the boss cutscene; one older than CalloutMaxWaitSec is dropped.
local calloutQueue: { any } = {}
local calloutBusy = false
local marlowUntil = 0 -- os.clock until which MARLOW's card owns the corner

local function holdMarlow(sec: number)
	marlowUntil = math.max(marlowUntil, os.clock() + sec + 0.4)
end

local function calloutBlocked(): boolean
	return os.clock() < marlowUntil or ClientState.cameraMode == "cinematic" or HUD.mode == "cinematic"
end

local function showCallout(data: any)
	local S = UI.S
	local h = home()
	if not h then
		return
	end
	local box = UI.frame({
		Name = "CalloutBox",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(h.width, S(CARD_H)),
		ClipsDescendants = true,
	})
	local inner = UI.frame({
		Name = "Inner",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = box,
	})
	h.add(box, 2)
	local color = if data.gold then Theme.Colors.gold else Theme.Colors.red
	buildCard(inner, {
		kind = "ally",
		crewLead = (if data.vip then "VIP " else "") .. string.upper(tostring(data.name or "")),
		label = "",
		labelColor = color,
		text = { tostring(data.line or "") },
		rewardLine = "",
		showTimer = false,
		portraitImage = headshot(tonumber(data.userId) or 0),
		noPill = true,
	})
	slideIn(inner)
	if data.gold then
		UI.sound(Theme.Sounds.legendary, 1, 0.55)
	else
		UI.sound(Theme.Sounds.call, 1.2, 0.5)
	end
	task.wait(Config.CalloutSec)
	if box.Parent then
		local out = slideOut(inner)
		out.Completed:Wait()
	end
	box:Destroy()
end

local function pumpCallouts()
	if calloutBusy then
		return
	end
	calloutBusy = true
	task.spawn(function()
		while #calloutQueue > 0 do
			while calloutBlocked() do
				task.wait(0.2)
			end
			local data = table.remove(calloutQueue, 1)
			if data and os.clock() - (data.queuedAt or 0) <= Config.CalloutMaxWaitSec then
				showCallout(data)
			end
		end
		calloutBusy = false
	end)
end

function CrewCallUI.init()
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "CallStart" then
			holdMarlow(Config.CallHoldSec)
			onCallStart(data)
		elseif name == "CrewLine" then
			holdMarlow(tonumber(data.hold) or Config.CallHoldSec)
			onCrewLine(data)
		elseif name == "Resumed" then
			-- The pause stopped the job / vault clocks on the server; the pill follows.
			local d = tonumber(data and data.duration) or 0
			for _, call in slots do
				if call.data and typeof(call.data.endsAt) == "number" then
					call.data.endsAt += d
				end
			end
		elseif name == "AllyCallout" and typeof(data) == "table" then
			data.queuedAt = os.clock()
			table.insert(calloutQueue, data)
			pumpCallouts()
		elseif name == "VaultOpen" then
			-- The result card for the job is still up: the pill takes over after it has had its hold.
			task.delay(Config.CallHoldSec + 0.35, function()
				onVaultOpen(data)
			end)
		elseif name == "VaultGas" then
			onVaultGas(data)
		elseif name == "VaultSealed" then
			if slots.vault then
				task.spawn(slideOutSlot, "vault")
			end
		elseif name == "JobProgress" then
			local key = slotOf(data.id)
			local call = key and slots[key]
			if call then
				local progress = data.progress or 0
				call.progress = progress
				setPillProgress(call, progress, data.inside == true)
				-- A tick every 10% while holding, pitch climbing; a low buzz when you step off.
				local step = math.floor(progress * 10)
				if data.inside and step > (call.lastTick or 0) then
					call.lastTick = step
					UI.sound(Theme.Sounds.reelTick, 0.9 + step * 0.08, 0.35)
				elseif not data.inside and progress > 0 and progress < 1 and call.wasInside then
					UI.sound(Theme.Sounds.deny, 0.8, 0.3)
				end
				call.wasInside = data.inside == true
			end
		elseif name == "CallReminder" then
			holdMarlow(Config.CallHoldSec)
			onCallReminder(data)
		elseif name == "CallEnd" then
			holdMarlow(Config.CallHoldSec)
			onCallEnd(data)
		elseif name == "CrateIncoming" then
			centerSlot().toast("ARMS DROP INCOMING", Theme.Colors.gold, 1)
			UI.sound(Theme.Sounds.crate, 0.6, 0.6)
		elseif name == "CrateLand" then
			local rolls = tonumber(data.rolls) or 0
			centerSlot().toast(
				string.format("ARMS CRATE · %d ROLL%s", rolls, if rolls == 1 then "" else "S"),
				Theme.Colors.gold,
				1.2
			)
			UI.sound(Theme.Sounds.crate, 0.9, 0.7)
			ClientState.Juice:Fire("Shake", { amp = 0.35, dur = 0.3 })
		elseif name == "CallCleared" then
			-- The run ended (or debug reset) with a job open: no result card, the box just goes.
			local key = slotOf(data.id)
			if key then
				destroySlot(key)
			end
		end
	end)

	HUD.Rebuilt:Connect(function()
		-- The HUD was rebuilt; re-add every live pill.
		local old = slots
		slots = {}
		for key, call in old do
			if call.data and call.data.endsAt and (call.data.noTimer or call.data.endsAt > ClientState.serverNow()) then
				local box, inner = buildBox(PILL_H, SLOT_ORDER[key])
				local _, timer, stroke = buildPill(inner, call.data, call.progress)
				slots[key] = {
					data = call.data,
					box = box,
					inner = inner,
					timerLabel = timer,
					stroke = stroke,
					token = call.token,
					progress = call.progress,
				}
			end
		end
	end)

	-- Timer tick, every live pill.
	local pulse = 0
	RunService.Heartbeat:Connect(function(dt)
		pulse += dt * 6
		for _, call in slots do
			if not call.timerLabel or not call.box.Parent or not call.data.endsAt then
				continue
			end
			if call.data.noTimer then
				-- Brief 7: a door objective never expires: the clock reads ∞.
				call.timerLabel.Text = "∞"
				continue
			end
			local remaining = call.data.endsAt - ClientState.serverNow()
			call.timerLabel.Text = fmtTime(remaining)
			if remaining < Config.CallPillWarnSec then
				call.timerLabel.TextColor3 = Theme.Colors.red
				local stroke = call.stroke
				if stroke then
					stroke.Color = Theme.Colors.red
					stroke.Transparency = 0.25 + 0.25 * math.sin(pulse)
					stroke.Thickness = UI.S(2) + UI.S(1.5) * (0.5 + 0.5 * math.sin(pulse))
				end
			end
		end
	end)
end

return CrewCallUI
