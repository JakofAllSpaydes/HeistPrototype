--!strict
-- Brief 13: the Job and Loot tiers of the marker hierarchy (Markers.lua keeps the Objective tier and feeds this).
--
-- Job (the side job, at most one): the prop itself outlined in the job blue through walls at any distance (a
-- Highlight, fill JobHighlightFill so it never reads as a solid block), a waypoint pill over it with the job's name
-- and, beyond JobNearRange, a live distance; a soft guide: one chevron pulse along the floor from you toward the
-- prop every JobPulseSec (not a standing strip). Inside JobNearRange the distance goes and the pulse stops; the
-- hint line (the key, through InputGlyphs) shows instead.
--
-- Loot (bags, gun crates, floor guns): small, no label unless the camera is on it, through walls only within
-- BagWallRange (the whole map during an intermission), gone beyond BagMarkerRange; 3+ bags within LootClusterRadius
-- collapse into one ×N marker; only the nearest LootMarkerCap show. Bags are drawn here; gun crates and floor guns
-- keep their own tags and register them (TierMarkers.loot), reading TierMarkers.hidden(gui) when they set Enabled.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Ground = require(Shared:WaitForChild("Ground"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local Hint = require(script.Parent:WaitForChild("Hint"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local TierMarkers = {}

local player = Players.LocalPlayer
local JOB_BLUE = Color3.fromHex(Config.JobHighlightColor)

local function rootPos(): Vector3?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if root then root.Position else nil
end

local function camera(): Camera?
	return Workspace.CurrentCamera
end

-- Degrees between the camera's look and the direction to `p` (180 when there is no camera).
local function lookAngle(p: Vector3): number
	local cam = camera()
	if not cam then
		return 180
	end
	local to = p - cam.CFrame.Position
	if to.Magnitude < 0.01 then
		return 0
	end
	return math.deg(math.acos(math.clamp(cam.CFrame.LookVector:Dot(to.Unit), -1, 1)))
end

local function cinematic(): boolean
	return ClientState.cameraMode == "cinematic"
end

local fxFolder: Folder? = nil
local function fx(): Folder
	local f = fxFolder
	if f and f.Parent then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "TierMarkers"
	nf.Parent = Workspace.CurrentCamera or Workspace
	fxFolder = nf
	return nf
end

------------------------------------------------------------------ Debug: Marker debug
-- Over every marker a small line: its tier, distance and what the rules decided (SHOW, CAP, FAR, CLUSTER, WALL).
local debugOn = false
local debugMarks: { [string]: { att: Attachment, label: TextLabel, tick: number } } = {}
local debugTick = 0

function TierMarkers.debugMark(key: string, position: Vector3, text: string)
	if not debugOn then
		return
	end
	local d = debugMarks[key]
	if not d then
		local att = Instance.new("Attachment")
		att.Name = "MarkerDebug"
		att.Parent = Workspace.Terrain
		local gui = Instance.new("BillboardGui")
		gui.Adornee = att
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.Size = UDim2.fromOffset(220, 16)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 1.2, 0)
		gui.Parent = att
		local label = Instance.new("TextLabel")
		label.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
		label.BackgroundTransparency = 0.3
		label.BorderSizePixel = 0
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 11
		label.TextColor3 = Color3.fromHex("E86FF2")
		label:SetAttribute("FixedTextSize", true)
		label.Parent = gui
		d = { att = att, label = label, tick = 0 }
		debugMarks[key] = d
	end
	d.att.WorldPosition = position
	d.label.Text = text
	d.tick = debugTick
end

function TierMarkers.setDebug(on: boolean)
	debugOn = on
	if not on then
		for _, d in debugMarks do
			d.att:Destroy()
		end
		debugMarks = {}
	end
end

function TierMarkers.debugEnabled(): boolean
	return debugOn
end

local function sweepDebug()
	for key, d in debugMarks do
		if d.tick ~= debugTick then
			d.att:Destroy()
			debugMarks[key] = nil
		end
	end
end

------------------------------------------------------------------ Job
type Job = {
	id: any,
	position: Vector3,
	startedAt: number,
	seen: boolean,
	att: Attachment,
	gui: BillboardGui,
	pill: Frame,
	nameLabel: TextLabel,
	distLabel: TextLabel,
	hint: TextLabel,
	hintText: string,
	bar: Frame,
	barFill: Frame,
	highlight: Highlight?,
	nextPulse: number,
	near: boolean?,
	faded: boolean,
	tierHidden: boolean,
	mini: Frame, -- Round 30d: the minimized waypoint (a blue ! and the distance) while a main objective is up
	miniDist: TextLabel,
	minimized: boolean,
}
local job: Job? = nil
-- Round 30d: a main objective (a called door, the vault) is up: the side job steps back to a small waypoint.
local mainActive = false

function TierMarkers.setMainObjective(on: boolean)
	mainActive = on
end

local function findProp(id: any): Instance?
	local effects = Workspace:FindFirstChild("Effects")
	if not effects then
		return nil
	end
	for _, m in effects:GetChildren() do
		if m:GetAttribute("JobId") == id then
			-- The prop, not the tall beacon column: the terminal (hack, minigame, alarm, office) or the ring (capture).
			return m:FindFirstChild("Terminal") or m:FindFirstChild("Rim") or m
		end
	end
	return nil
end

function TierMarkers.clearJob()
	local j = job
	if not j then
		return
	end
	job = nil
	if j.highlight then
		j.highlight:Destroy()
	end
	UI.tween(j.pill, { BackgroundTransparency = 1 }, 0.2)
	for _, d in j.gui:GetDescendants() do
		if d:IsA("TextLabel") then
			UI.tween(d, { TextTransparency = 1 }, 0.2)
		elseif d:IsA("UIStroke") then
			UI.tween(d, { Transparency = 1 }, 0.2)
		end
	end
	task.delay(0.25, function()
		j.att:Destroy()
	end)
end

-- A side job's CallStart: the pill, the outline (once the beacon replicates) and the pulse clock.
function TierMarkers.setJob(id: any, position: Vector3, name: string, hint: string)
	TierMarkers.clearJob()
	local scale = if ClientState.isMobile then Config.MarkerMobileWorldScale * Config.JobPillMobileScale else 1
	local function S(n: number): number
		return UI.S(n * scale)
	end
	local att = Instance.new("Attachment")
	att.Name = "JobMarker"
	att.WorldPosition = position + Vector3.new(0, 6, 0) -- under the Objective tier's 7.5
	att.Parent = Workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Adornee = att
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 1e5
	gui.Size = UDim2.fromOffset(S(240), S(64))
	gui.ClipsDescendants = false
	gui.Parent = att
	local pillH = S(30)
	local pill = UI.frame({
		Name = "JobPill",
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(S(120), pillH),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = gui,
	})
	UI.corner(pill, pillH / 2)
	UI.stroke(pill, JOB_BLUE, S(2))
	UI.pad(pill, S(5), 0, S(12), 0)
	UI.list(pill, Enum.FillDirection.Horizontal, S(8), Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local icon = UI.frame({
		BackgroundColor3 = JOB_BLUE,
		Size = UDim2.fromOffset(S(20), S(20)),
		LayoutOrder = 1,
		Parent = pill,
	})
	UI.corner(icon, S(5))
	UI.text({
		Text = "!",
		FontFace = Theme.Fonts.display,
		TextSize = S(15),
		TextColor3 = Theme.Colors.bg,
		Size = UDim2.fromScale(1, 1),
		Parent = icon,
	})
	local nameLabel = UI.text({
		Text = string.upper(name),
		FontFace = Theme.Fonts.display,
		TextSize = S(17),
		TextColor3 = Theme.Colors.text,
		Size = UDim2.fromOffset(0, pillH),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = pill,
	})
	-- The wave bar's digit style.
	local distLabel = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(17),
		TextColor3 = JOB_BLUE,
		Size = UDim2.fromOffset(0, pillH),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 3,
		Parent = pill,
	})
	local hintLabel = UI.text({
		Text = Hint.swap(hint),
		FontFace = Theme.Fonts.display,
		TextSize = S(12),
		TextColor3 = Theme.Colors.text,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, pillH + S(3)),
		Size = UDim2.new(1, 0, 0, S(14)),
		Visible = false,
		Parent = gui,
	})
	UI.stroke(hintLabel, Theme.Colors.black, S(1.5), 0.3)
	local bar = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, pillH + S(20)),
		Size = UDim2.fromOffset(S(120), S(5)),
		Visible = false,
		Parent = gui,
	})
	UI.corner(bar, S(3))
	local barFill = UI.frame({ BackgroundColor3 = Theme.Colors.cash, Size = UDim2.fromScale(0, 1), Parent = bar })
	UI.corner(barFill, S(3))
	UI.punch(pill, 1.3, 0.35)
	-- Round 30d: the minimized waypoint: a small blue ! with the distance under it.
	local mini = UI.frame({
		Name = "JobMini",
		BackgroundColor3 = JOB_BLUE,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(S(24), S(24)),
		Visible = false,
		Parent = gui,
	})
	UI.corner(mini, S(5))
	UI.stroke(mini, Theme.Colors.black, S(1.5), 0.4)
	UI.text({
		Text = "!",
		FontFace = Theme.Fonts.display,
		TextSize = S(17),
		TextColor3 = Theme.Colors.bg,
		Size = UDim2.fromScale(1, 1),
		Parent = mini,
	})
	local miniDist = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = JOB_BLUE,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, S(2)),
		Size = UDim2.fromOffset(S(80), S(16)),
		Parent = mini,
	})
	UI.stroke(miniDist, Theme.Colors.black, S(1.5), 0.3)
	local j: Job = {
		id = id,
		position = position,
		startedAt = os.clock(),
		seen = false,
		att = att,
		gui = gui,
		pill = pill,
		nameLabel = nameLabel,
		distLabel = distLabel,
		hint = hintLabel,
		hintText = hint,
		bar = bar,
		barFill = barFill,
		highlight = nil,
		nextPulse = os.clock() + 0.6,
		near = nil,
		faded = false,
		tierHidden = false,
		mini = mini,
		miniDist = miniDist,
		minimized = false,
	}
	job = j
	-- The outline: the beacon is server-built, so wait for it to replicate.
	task.spawn(function()
		local t0 = os.clock()
		while job == j and os.clock() - t0 < 4 do
			local prop = findProp(id)
			if prop then
				local h = Instance.new("Highlight")
				h.Name = "JobOutline"
				h.Adornee = prop
				h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				h.FillColor = JOB_BLUE
				h.FillTransparency = 1 - math.clamp(Config.JobHighlightFill, 0, 1)
				h.OutlineColor = JOB_BLUE
				h.OutlineTransparency = if j.minimized then 0.55 else 0
				if j.minimized then
					h.FillTransparency = 1
				end
				h.Parent = fx()
				j.highlight = h
				return
			end
			task.wait(0.2)
		end
	end)
end

-- Capture progress / the job's sub line (the hint text and its colour while near).
function TierMarkers.jobProgress(progress: number, active: boolean)
	local j = job
	if not j then
		return
	end
	j.bar.Visible = true
	j.barFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
	j.barFill.BackgroundColor3 = if active then Theme.Colors.cash else Theme.Colors.malus
end

function TierMarkers.jobHint(text: string, color: Color3?)
	local j = job
	if not j then
		return
	end
	j.hintText = text
	j.hint.Text = Hint.swap(text)
	j.hint.TextColor3 = color or Theme.Colors.text
end

function TierMarkers.jobId(): any
	return if job then job.id else nil
end

-- One pulse: a short run of chevrons lighting up in turn along the floor from you toward the job.
local function pulse(from: Vector3, to: Vector3)
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local len = math.min(flat.Magnitude - 4, Config.JobPulseLength)
	if len < 4 then
		return
	end
	local dir = flat.Unit
	local yaw = math.atan2(-dir.X, -dir.Z)
	local folder = Instance.new("Folder")
	folder.Name = "JobPulse"
	folder.Parent = fx()
	local rows: { { BasePart } } = {}
	local d = 3
	while d <= len do
		local p = from + dir * d
		local base = CFrame.new(p.X, Ground.y(p + Vector3.new(0, 1, 0), from.Y - 3) + 0.06, p.Z)
			* CFrame.Angles(0, yaw, 0)
		local pair = {}
		for _, side in { -1, 1 } do
			local bar = Instance.new("Part")
			bar.Anchored = true
			bar.CanCollide = false
			bar.CanQuery = false
			bar.CanTouch = false
			bar.CastShadow = false
			bar.Size = Vector3.new(0.45, 0.08, 1.9)
			bar.CFrame = base * CFrame.new(side * 0.6, 0, 0.3) * CFrame.Angles(0, side * math.rad(40), 0)
			bar.Color = JOB_BLUE
			bar.Material = Enum.Material.Neon
			bar.Transparency = 1
			bar.Parent = folder
			table.insert(pair, bar)
		end
		table.insert(rows, pair)
		d += 3
	end
	task.spawn(function()
		local t0 = os.clock()
		local runSec = 0.9
		while folder.Parent do
			local t = os.clock() - t0
			if t > runSec + 0.5 then
				break
			end
			local head = t / runSec * (#rows + 1)
			for i, pair in rows do
				local k = math.clamp(1 - math.abs(i - head) / 1.6, 0, 1)
				for _, bar in pair do
					bar.Transparency = 1 - 0.75 * k
				end
			end
			task.wait(1 / 30)
		end
		folder:Destroy()
	end)
end

------------------------------------------------------------------ Loot
type Loot = {
	gui: BillboardGui,
	part: BasePart?,
	position: Vector3?,
	kind: string, -- bag | crate | gun
	refresh: (() -> ())?,
	own: boolean,
	gold: boolean,
	label: TextLabel?,
	labelUntil: number,
	att: Attachment?,
}
local loot: { [string]: Loot } = {}
local hiddenGuis: { [BillboardGui]: boolean } = {}
local lastShown, lastHidden = 0, 0

local function lootPos(l: Loot): Vector3?
	local p = l.part
	if p then
		return if p.Parent then p.Position else nil
	end
	return l.position
end

-- Register a loot tag someone else draws (gun crates, floor guns). `refresh` re-applies its own Enabled logic,
-- which must AND in `not TierMarkers.hidden(gui)`.
function TierMarkers.loot(id: string, gui: BillboardGui, part: BasePart?, kind: string, refresh: (() -> ())?)
	loot[id] = {
		gui = gui,
		part = part,
		position = nil,
		kind = kind,
		refresh = refresh,
		own = false,
		gold = false,
		label = nil,
		labelUntil = 0,
		att = nil,
	}
end

function TierMarkers.unloot(id: string)
	local l = loot[id]
	if not l then
		return
	end
	loot[id] = nil
	hiddenGuis[l.gui] = nil
	if l.own then
		local att = l.att
		UI.tween(l.gui:FindFirstChildWhichIsA("Frame") :: Frame, { BackgroundTransparency = 1 }, 0.2)
		task.delay(0.25, function()
			if att then
				att:Destroy()
			end
		end)
	end
end

-- Back in the hub: every bag icon goes (registered tags go with their owners).
function TierMarkers.clearLoot()
	for id, l in table.clone(loot) do
		if l.own then
			TierMarkers.unloot(id)
		end
	end
end

-- Is this registered tag held back by the tier rules (range, cap)?
function TierMarkers.hidden(gui: BillboardGui): boolean
	return hiddenGuis[gui] == true
end

-- A small round icon with a glyph and a label that only shows while looked at.
local function icon(
	position: Vector3,
	color: Color3,
	glyph: string,
	labelText: string
): (Attachment, BillboardGui, TextLabel)
	local scale = if ClientState.isMobile then Config.MarkerMobileWorldScale * Config.LootIconMobileScale else 1
	local function S(n: number): number
		return UI.S(n * scale)
	end
	local att = Instance.new("Attachment")
	att.Name = "LootMarker"
	-- Round 30d: the icon sits above this point (SizeOffset), clear of the bag model; still under the other tiers.
	att.WorldPosition = position + Vector3.new(0, Config.LootIconLift, 0)
	att.Parent = Workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Adornee = att
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(S(120), S(54))
	gui.SizeOffset = Vector2.new(0, 0.5) -- the billboard grows up from its point, never down over the bag
	gui.ClipsDescendants = false
	gui.Parent = att
	local dot = UI.frame({
		Name = "Dot",
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(S(26), S(26)),
		Parent = gui,
	})
	UI.corner(dot, S(13))
	UI.stroke(dot, Theme.Colors.black, S(1.5), 0.35)
	UI.text({
		Name = "Glyph",
		Text = glyph,
		FontFace = Theme.Fonts.display,
		TextSize = S(17),
		TextColor3 = Theme.Colors.bg,
		Size = UDim2.fromScale(1, 1),
		Parent = dot,
	})
	local label = UI.text({
		Name = "Label",
		Text = labelText,
		FontFace = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = color,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(29)),
		Size = UDim2.new(1, 0, 0, S(18)),
		Visible = false,
		Parent = gui,
	})
	UI.stroke(label, Theme.Colors.black, S(1.5), 0.3)
	UI.punch(dot, 1.4, 0.3)
	return att, gui, label
end

-- A cash / gold bag on the floor.
function TierMarkers.bag(id: string, position: Vector3, gold: boolean, labelText: string)
	TierMarkers.unloot(id)
	local att, gui, label =
		icon(position, if gold then Theme.Colors.gold else Theme.Colors.cash, if gold then "◆" else "$", labelText)
	loot[id] = {
		gui = gui,
		part = nil,
		position = position,
		kind = "bag",
		refresh = nil,
		own = true,
		gold = gold,
		label = label,
		labelUntil = 0,
		att = att,
	}
end

-- The ×N cluster markers (a small pool, reused tick to tick).
type Cluster = { att: Attachment, gui: BillboardGui, count: TextLabel }
local clusters: { Cluster } = {}
local function clusterMarker(i: number): Cluster
	local c = clusters[i]
	if c then
		return c
	end
	local scale = if ClientState.isMobile then Config.MarkerMobileWorldScale * Config.LootIconMobileScale else 1
	local function S(n: number): number
		return UI.S(n * scale)
	end
	local att = Instance.new("Attachment")
	att.Name = "LootCluster"
	att.Parent = Workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Adornee = att
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(S(64), S(30))
	gui.SizeOffset = Vector2.new(0, 0.5)
	gui.Enabled = false
	gui.Parent = att
	local chip = UI.frame({
		BackgroundColor3 = Theme.Colors.cash,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(S(26), S(26)),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = gui,
	})
	UI.corner(chip, S(13))
	UI.stroke(chip, Theme.Colors.black, S(1.5), 0.35)
	UI.pad(chip, S(7), 0, S(7), 0)
	-- Readable at phone size: the count is the biggest thing on it.
	local count = UI.text({
		Text = "×3",
		FontFace = Theme.Fonts.display,
		TextSize = S(17),
		TextColor3 = Theme.Colors.bg,
		Size = UDim2.fromOffset(0, S(26)),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = chip,
	})
	local made: Cluster = { att = att, gui = gui, count = count }
	clusters[i] = made
	return made
end

local function setHidden(l: Loot, hidden: boolean)
	if (hiddenGuis[l.gui] == true) == hidden then
		return
	end
	if hidden then
		hiddenGuis[l.gui] = true
	else
		hiddenGuis[l.gui] = nil
	end
	if l.own then
		l.gui.Enabled = not hidden and not cinematic()
	elseif l.refresh then
		l.refresh()
	end
end

local function intermission(): boolean
	local sync = ClientState.sync
	return sync ~= nil and sync.waveState == "Intermission"
end

local function tickLoot()
	local me = rootPos()
	if not me then
		return
	end
	local sweep = intermission()
	local wallRange = if sweep then math.huge else Config.BagWallRange
	local farRange = if sweep then math.huge else Config.BagMarkerRange
	local now = os.clock()
	-- Live entries with a position.
	local live: { { id: string, l: Loot, p: Vector3, d: number } } = {}
	for id, l in loot do
		local p = lootPos(l)
		if not p or not l.gui.Parent then
			if l.own or not l.gui.Parent then
				loot[id] = nil
				hiddenGuis[l.gui] = nil
			end
			continue
		end
		table.insert(live, { id = id, l = l, p = p, d = (p - me).Magnitude })
	end
	-- Bags close together collapse into one ×N.
	local inCluster: { [string]: boolean } = {}
	local groups: { { p: Vector3, d: number, n: number, gold: boolean } } = {}
	local r = Config.LootClusterRadius
	for i, a in live do
		if a.l.kind ~= "bag" or inCluster[a.id] then
			continue
		end
		local members = { a }
		for k = i + 1, #live do
			local b = live[k]
			if b.l.kind == "bag" and not inCluster[b.id] and (b.p - a.p).Magnitude <= r then
				table.insert(members, b)
			end
		end
		if #members >= Config.LootClusterMin then
			local sum = Vector3.zero
			local gold = false
			for _, m in members do
				inCluster[m.id] = true
				sum += m.p
				gold = gold or m.l.gold
			end
			local c = sum / #members
			table.insert(groups, { p = c, d = (c - me).Magnitude, n = #members, gold = gold })
		end
	end
	-- Candidates in range, nearest first; the first LootMarkerCap show.
	type Cand = { kind: string, d: number, entry: any }
	local cands: { Cand } = {}
	for _, e in live do
		if not inCluster[e.id] and e.d <= farRange then
			table.insert(cands, { kind = "loot", d = e.d, entry = e })
		end
	end
	for gi, g in groups do
		if g.d <= farRange then
			table.insert(cands, { kind = "cluster", d = g.d, entry = gi })
		end
	end
	table.sort(cands, function(a, b)
		return a.d < b.d
	end)
	local show: { [string]: boolean } = {}
	local showCluster: { [number]: boolean } = {}
	for i, c in cands do
		if i > Config.LootMarkerCap then
			break
		end
		if c.kind == "loot" then
			show[c.entry.id] = true
		else
			showCluster[c.entry] = true
		end
	end
	local shown, hidden = 0, 0
	local cine = cinematic()
	for _, e in live do
		local on = show[e.id] == true
		setHidden(e.l, not on)
		if e.l.own then
			e.l.gui.Enabled = on and not cine -- cutscenes show no world markers
		end
		if on then
			shown += 1
			-- Through walls only when close (or sweeping in the intermission).
			e.l.gui.AlwaysOnTop = e.d <= wallRange
			-- The label on a bag shows while you look at it, and holds a moment.
			local label = e.l.label
			if label then
				if lookAngle(e.p) <= Config.LootLookAngle then
					e.l.labelUntil = now + Config.LootLookLabelSec
				end
				label.Visible = now < e.l.labelUntil
			end
		else
			hidden += 1
		end
		if debugOn then
			local why = if inCluster[e.id]
				then "CLUSTER"
				elseif e.d > farRange then "FAR"
				elseif not on then "CAP"
				elseif e.l.gui.AlwaysOnTop then "SHOW · WALL"
				else "SHOW"
			TierMarkers.debugMark(
				"loot" .. e.id,
				e.p + Vector3.new(0, 1.5, 0),
				string.format("LOOT %s %dm %s", e.l.kind, math.round(e.d), why)
			)
		end
	end
	for i = 1, math.max(#clusters, #groups) do
		local g = groups[i]
		local on = g ~= nil and showCluster[i] == true and not cine
		local c = if on then clusterMarker(i) else clusters[i]
		if c then
			c.gui.Enabled = on
		end
		if on and g and c then
			shown += 1
			c.att.WorldPosition = g.p + Vector3.new(0, Config.LootIconLift, 0)
			local text = "×" .. tostring(g.n)
			if c.count.Text ~= text then
				c.count.Text = text
				UI.punch(c.count.Parent :: Frame, 1.2, 0.2)
			end
			local chip = c.count.Parent :: Frame
			chip.BackgroundColor3 = if g.gold then Theme.Colors.gold else Theme.Colors.cash
			c.gui.AlwaysOnTop = g.d <= wallRange
		end
	end
	lastShown, lastHidden = shown, hidden
end

-- [GHS Markers] loot shown <n> hidden <n> (Markers prints it once per wave).
function TierMarkers.lootStats(): (number, number)
	return lastShown, lastHidden
end

------------------------------------------------------------------ The tick
local function tickJob()
	local j = job
	if not j then
		return
	end
	local me = rootPos()
	local hide = cinematic() or j.tierHidden
	if j.gui.Enabled == hide then
		j.gui.Enabled = not hide
	end
	if j.highlight then
		j.highlight.Enabled = not hide
	end
	if not me then
		return
	end
	local d = (j.position - me).Magnitude
	local near = d <= Config.JobNearRange
	TierMarkers.debugMark(
		"job",
		j.position + Vector3.new(0, 1.5, 0),
		string.format(
			"JOB %dm %s%s",
			math.round(d),
			if near then "NEAR" else "FAR · PULSE",
			if hide then " · HIDDEN" else ""
		)
	)
	j.distLabel.Text = if near then "" else string.format("%dm", math.round(d))
	j.distLabel.Visible = not near
	-- Round 30d: while a main objective is up the side job is a small waypoint (unless you are right at it).
	local mini = mainActive and not near
	if mini ~= j.minimized then
		j.minimized = mini
		j.pill.Visible = not mini
		j.mini.Visible = mini
		j.hint.Visible = near and not mini
		j.bar.Visible = j.bar.Visible and not mini
		UI.punch(if mini then j.mini else j.pill, 1.2, 0.25)
		local h = j.highlight
		if h then
			-- The outline stays (so it can still be found) but steps back.
			h.OutlineTransparency = if mini then 0.55 else 0
			h.FillTransparency = if mini then 1 else 1 - math.clamp(Config.JobHighlightFill, 0, 1)
		end
	end
	if mini then
		j.miniDist.Text = string.format("%dm", math.round(d))
	end
	if near ~= j.near then
		j.near = near
		j.hint.Visible = near
		if near then
			UI.punch(j.pill, 1.12, 0.2)
		end
	end
	-- [GHS Markers] job <id> seen <sec>: how long from the job's spawn to this player first looking at it.
	if not j.seen and lookAngle(j.position) <= 12 then
		j.seen = true
		print(string.format("[GHS Markers] job %s seen %.1f", tostring(j.id), os.clock() - j.startedAt))
	end
	-- Never over the crosshair: the pill fades when it sits near the screen centre.
	local cam = camera()
	if cam then
		local sp, on = cam:WorldToViewportPoint(j.att.WorldPosition)
		local centre = cam.ViewportSize / 2
		local close = on and (Vector2.new(sp.X, sp.Y) - centre).Magnitude < UI.S(Config.MarkerCrosshairClearPx)
		if close ~= j.faded then
			j.faded = close
			UI.tween(j.pill, { BackgroundTransparency = if close then 0.75 else 0.1 }, 0.15)
			for _, t in { j.nameLabel, j.distLabel, j.hint } do
				UI.tween(t, { TextTransparency = if close then 0.7 else 0 }, 0.15)
			end
		end
	end
	-- The soft guide.
	local now = os.clock()
	if not near and not hide and not j.minimized and now >= j.nextPulse then
		j.nextPulse = now + Config.JobPulseSec
		pulse(me, j.position)
	end
end

-- Markers installs this: marks its Objective markers on the debug overlay (prio, SHOW / CAP).
TierMarkers.objectiveDebug = nil :: (() -> ())?

function TierMarkers.setJobHidden(on: boolean)
	local j = job
	if j then
		j.tierHidden = on
	end
end

function TierMarkers.init()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		debugTick += 1
		tickJob()
		tickLoot()
		local objective = TierMarkers.objectiveDebug
		if debugOn and objective then
			objective()
		end
		sweepDebug()
	end)
end

return TierMarkers
