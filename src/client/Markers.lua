--!strict
-- World markers: a fixed-size billboard over the side job beacon with a name, status line, timer and
-- distance, so it is findable from across the room. Fed by the crew call juice events; the crate has
-- none on purpose (the fanned guns already read from a distance).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Ground = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ground"))
local Lines = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CrewCall"):WaitForChild("Lines"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local Hint = require(script.Parent:WaitForChild("Hint"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local TierMarkers = require(script.Parent:WaitForChild("TierMarkers")) -- brief 13: the Job and Loot tiers

type Marker = {
	att: Attachment,
	frame: Frame,
	stroke: UIStroke,
	title: TextLabel,
	sub: TextLabel,
	timer: TextLabel,
	dist: TextLabel,
	bar: Frame,
	barFill: Frame,
	compact: Frame,
	compactLabel: TextLabel,
	isCompact: boolean,
	color: Color3,
	endsAt: number,
	position: Vector3,
	wasInside: boolean?,
	noCompact: boolean, -- the vault job's beacon never shrinks to a badge
	diamond: Frame?, -- a rotating diamond over the box (the vault job)
	prio: number, -- brief 13: Objective tier urgency (1 = most); only the top ObjectiveMarkerCap show
	group: string, -- Round 30d: the objective it belongs to (the cap counts these)
	tierHidden: boolean, -- brief 13: held back by the Objective cap
	glow: Frame, -- Round 30d: the halo behind the pill
	tick: Frame,
	urgent: boolean, -- Round 30d: prio 1-2 breathe harder
	strokeBase: number,
}

-- Optional look for a marker: `scale` multiplies every size, `noCompact` keeps the full box at any distance,
-- `diamond` puts a rotating diamond in the marker color over it. Brief 13: every marker drawn here is the Objective
-- tier; `prio` ranks them for the cap (1 the vault job / open vault, 2 a called door, 3 an office, 4 the hatch, 5 a
-- closed door's sign). Side jobs and loot are drawn by TierMarkers.
-- Round 30d: `group` ties markers that are one objective (a door group's parts): the cap counts groups, so every
-- way to do the objective shows (both stair chains), never just the nearer one.
export type Opts = {
	scale: number?,
	noCompact: boolean?,
	diamond: boolean?,
	maxDistance: number?,
	prio: number?,
	group: string?,
}

local Markers = {}

local player = Players.LocalPlayer
local markers: { [string]: Marker } = {}
local jobMarkerId: any = nil -- the side job call the "job" marker belongs to
local peakShown, peakHidden = 0, 0 -- brief 13: loot markers at the wave's busiest tick ([GHS Markers] log)

local function fmtTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

function Markers.remove(id: string)
	local m = markers[id]
	if not m then
		return
	end
	markers[id] = nil
	UI.tween(m.frame, { BackgroundTransparency = 1 }, 0.25)
	UI.tween(m.glow, { BackgroundTransparency = 1 }, 0.25)
	UI.tween(m.tick, { BackgroundTransparency = 1 }, 0.25)
	UI.tween(m.sub, { TextTransparency = 1 }, 0.25)
	UI.tween(m.compact, { BackgroundTransparency = 1 }, 0.25)
	for _, d in m.compact:GetDescendants() do
		if d:IsA("TextLabel") then
			UI.tween(d, { TextTransparency = 1 }, 0.25)
		end
	end
	for _, d in m.frame:GetDescendants() do
		if d:IsA("TextLabel") then
			UI.tween(d, { TextTransparency = 1 }, 0.25)
		elseif d:IsA("UIStroke") then
			UI.tween(d, { Transparency = 1 }, 0.25)
		end
	end
	task.delay(0.3, function()
		m.att:Destroy()
	end)
end

-- Round 30d: the Objective marker is a compact pill, not a box: an icon square, the name, and the distance in big
-- digits (a timer beside it when the objective has one), a halo that breathes behind it (harder for the urgent ones:
-- prio 1-2), and a pointer tick. The key hint (E · CUT) shows under it only once you are within ObjectiveHintRange,
-- so far off it is small enough not to hide the outlined prop. Far away it still shrinks to the badge.
function Markers.add(
	id: string,
	position: Vector3,
	color: Color3,
	titleText: string,
	subText: string,
	endsAt: number,
	glyph: string?,
	opts: Opts?
)
	Markers.remove(id)
	local scale = (opts and opts.scale) or 1
	local function S(n: number): number
		return UI.S(n * scale)
	end
	local diamondH = if opts and opts.diamond then S(26) else 0
	local pillH = S(34)
	local halo = S(8)
	local att = Instance.new("Attachment")
	att.Name = "Marker_" .. id
	att.WorldPosition = position + Vector3.new(0, 7.5, 0)
	att.Parent = Workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Adornee = att
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(S(320), diamondH + halo + pillH + halo + S(22))
	gui.MaxDistance = (opts and opts.maxDistance) or 1e5 -- Round 30d: an objective reads from anywhere
	gui.LightInfluence = 0
	gui.ClipsDescendants = false
	gui.Parent = att
	local diamond: Frame? = nil
	if opts and opts.diamond then
		local dm = UI.frame({
			Name = "Diamond",
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, diamondH / 2),
			Size = UDim2.fromOffset(diamondH * 0.6, diamondH * 0.6),
			Rotation = 45,
			Parent = gui,
		})
		UI.corner(dm, S(3))
		UI.stroke(dm, Theme.Colors.white, S(2), 0.2)
		diamond = dm
	end
	local pillY = diamondH + halo
	-- The halo: a soft block of the marker colour behind the pill, sized to it (it follows the pill's width).
	local glow = UI.frame({
		Name = "Glow",
		BackgroundColor3 = color,
		BackgroundTransparency = 0.7,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, pillY + pillH / 2),
		Size = UDim2.fromOffset(S(140), pillH + halo * 2),
		ZIndex = 1,
		Parent = gui,
	})
	UI.corner(glow, (pillH + halo * 2) / 2)
	local frame = UI.frame({
		Name = "Pill",
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.05,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, pillY),
		Size = UDim2.fromOffset(0, pillH),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 2,
		Parent = gui,
	})
	UI.corner(frame, pillH / 2)
	local stroke = UI.stroke(frame, color, S(2.5))
	UI.pad(frame, S(5), 0, S(12), 0)
	UI.list(frame, Enum.FillDirection.Horizontal, S(8), Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local icon = UI.frame({
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(pillH - S(10), pillH - S(10)),
		LayoutOrder = 1,
		ZIndex = 3,
		Parent = frame,
	})
	UI.corner(icon, S(5))
	UI.text({
		Text = glyph or "!",
		FontFace = Theme.Fonts.display,
		TextSize = S(17),
		TextColor3 = Theme.Colors.bg,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = icon,
	})
	local title = UI.text({
		Text = titleText,
		FontFace = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.text,
		Size = UDim2.fromOffset(0, pillH),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		ZIndex = 3,
		Parent = frame,
	})
	-- A timer (the vault, an office) and the distance: big, in the marker colour, the wave bar's digits.
	local timer = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = color,
		Size = UDim2.fromOffset(0, pillH),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = endsAt > 0,
		LayoutOrder = 3,
		ZIndex = 3,
		Parent = frame,
	})
	local dist = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(20),
		TextColor3 = color,
		Size = UDim2.fromOffset(0, pillH),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 4,
		ZIndex = 3,
		Parent = frame,
	})
	-- The pointer tick under the pill.
	local tick = UI.frame({
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, pillY + pillH),
		Size = UDim2.fromOffset(S(9), S(9)),
		Rotation = 45,
		ZIndex = 3,
		Parent = gui,
	})
	UI.corner(tick, S(2))
	-- The key hint, under it, only when close (the refresh loop shows it).
	local sub = UI.text({
		Text = Hint.swap(subText), -- brief 11: HOLD E reads HOLD □ on a pad
		FontFace = Theme.Fonts.display,
		TextSize = S(13),
		TextColor3 = Theme.Colors.text,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, pillY + pillH + halo),
		Size = UDim2.new(1, 0, 0, S(16)),
		Visible = false,
		ZIndex = 3,
		Parent = gui,
	})
	UI.stroke(sub, Theme.Colors.black, S(1.5), 0.3)
	-- Progress bar under the pill (setProgress); hidden until used.
	local bar = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, pillY + pillH + S(4)),
		Size = UDim2.fromOffset(S(120), S(5)),
		Visible = false,
		ZIndex = 3,
		Parent = gui,
	})
	UI.corner(bar, S(3))
	local barFill = UI.frame({
		BackgroundColor3 = Theme.Colors.cash,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 4,
		Parent = bar,
	})
	UI.corner(barFill, S(3))
	-- The halo follows the pill's width as its text changes.
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		glow.Size = UDim2.fromOffset(frame.AbsoluteSize.X + halo * 2, pillH + halo * 2)
	end)
	UI.punch(frame, 1.35, 0.4)

	-- Compact form for far away: a small badge with the distance (and timer) under it, readable.
	local compact = UI.frame({
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(22)),
		Size = UDim2.fromOffset(S(30), S(30)),
		Visible = false,
		ZIndex = 3,
		Parent = gui,
	})
	UI.corner(compact, S(15))
	UI.stroke(compact, Theme.Colors.black, S(1.5), 0.4)
	UI.text({
		Text = glyph or "!",
		FontFace = Theme.Fonts.display,
		TextSize = S(20),
		TextColor3 = Theme.Colors.bg,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = compact,
	})
	local compactLabel = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(16),
		TextColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, S(2)),
		Size = UDim2.fromOffset(S(120), S(18)),
		ZIndex = 4,
		Parent = compact,
	})
	UI.stroke(compactLabel, Theme.Colors.black, S(1.5), 0.3)

	local prio = (opts and opts.prio) or 3
	markers[id] = {
		att = att,
		frame = frame,
		stroke = stroke,
		title = title,
		sub = sub,
		timer = timer,
		dist = dist,
		bar = bar,
		barFill = barFill,
		compact = compact,
		compactLabel = compactLabel,
		isCompact = false,
		color = color,
		endsAt = endsAt,
		position = position,
		-- Round 30d: the objective pill never shrinks to the far badge (only a closed door's sign may).
		noCompact = prio <= 4 or (opts ~= nil and opts.noCompact == true),
		diamond = diamond,
		prio = prio,
		group = (opts and opts.group) or id,
		tierHidden = false,
		glow = glow,
		tick = tick,
		urgent = prio <= 2,
		strokeBase = S(2.5),
	}
end

-- CRACK THE VAULT: a chevron strip on the floor from the crew to the door for VaultArrowSec, lit in a running
-- wave toward the door (the FTUE arrows will use the same look).
-- Round 19: `points` is the walking route the server planned (stairs and floors included); without it the strip
-- is the straight line. Chevrons sit every 4 studs along the route, on the floor under each point.
-- Round 30d: a `key`ed strip (the door guide, re-planned as you move) replaces your previous one with the same key,
-- and chevrons you have walked past go out, so the strip always starts at your feet.
local keyedArrows: { [string]: Folder } = {}
local function floorArrows(from: Vector3, to: Vector3, seconds: number, points: { Vector3 }?, key: string?)
	local route: { Vector3 } = if points and #points >= 2 then points else { from, to }
	if key then
		local old = keyedArrows[key]
		if old then
			old:Destroy()
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = "VaultArrows"
	folder.Parent = Workspace:FindFirstChild("Effects") or Workspace
	if key then
		keyedArrows[key] = folder
	end
	local chevrons: { BasePart } = {}
	local step = 4
	-- Walk the polyline: a chevron every `step` studs (measured in the flat), facing along its segment.
	local samples: { { p: Vector3, dir: Vector3 } } = {}
	local carry = 4
	for i = 1, #route - 1 do
		local a, b = route[i], route[i + 1]
		local seg = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local len = seg.Magnitude
		if len < 0.05 then
			continue
		end
		local dir = seg.Unit
		local d = carry
		while d < len do
			local t = d / len
			table.insert(samples, { p = a:Lerp(b, t), dir = dir })
			d += step
		end
		carry = d - len
	end
	-- Stop short of the target so the last chevron does not sit in the door.
	while #samples > 0 and Vector3.new(samples[#samples].p.X - to.X, 0, samples[#samples].p.Z - to.Z).Magnitude < 3 do
		table.remove(samples)
	end
	if #samples == 0 then
		folder:Destroy()
		return
	end
	for _, s in samples do
		local p, dir = s.p, s.dir
		local yaw = math.atan2(-dir.X, -dir.Z)
		local base = CFrame.new(p.X, Ground.y(p + Vector3.new(0, 1, 0), p.Y) + 0.06, p.Z) * CFrame.Angles(0, yaw, 0)
		-- A chevron: two thin bars meeting at the front.
		for _, side in { -1, 1 } do
			local bar = Instance.new("Part")
			bar.Anchored = true
			bar.CanCollide = false
			bar.CanQuery = false
			bar.CanTouch = false
			bar.Size = Vector3.new(0.5, 0.08, 2.2)
			bar.CFrame = base * CFrame.new(side * 0.7, 0, 0.35) * CFrame.Angles(0, side * math.rad(40), 0)
			bar.Color = Theme.Colors.amber
			bar.Material = Enum.Material.Neon
			bar.Transparency = 0.6
			bar.Parent = folder
			table.insert(chevrons, bar)
		end
	end
	task.spawn(function()
		local t0 = os.clock()
		local count = #chevrons // 2
		local passed = 0 -- chevrons behind you (keyed strips only)
		while os.clock() - t0 < seconds and folder.Parent do
			local t = os.clock() - t0
			if key then
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					-- The sample nearest you (ahead of what is already passed) is where the strip now starts.
					local best, bestD = passed, math.huge
					for k = passed + 1, math.min(#samples, passed + 12) do
						local s = samples[k].p
						local d = Vector3.new(s.X - root.Position.X, 0, s.Z - root.Position.Z).Magnitude
						if d < bestD then
							best, bestD = k, d
						end
					end
					if bestD < 3.5 then
						passed = best
					end
				end
			end
			local head = passed + (t * 6) % math.max(count - passed, 1)
			for i, bar in chevrons do
				local k = (i + 1) // 2
				if k <= passed then
					bar.Transparency = 1
					continue
				end
				local near = math.abs(k - head) < 1.5
				local fade = math.clamp((seconds - t) / 1.5, 0, 1)
				-- Round 30d: keyed guides read stronger (they are the one thing to follow).
				local base = if key then 0.55 else 0.35
				bar.Transparency = 1 - (if near then 0.95 else base) * fade
			end
			task.wait(1 / 30)
		end
		if keyedArrows[key or ""] == folder then
			keyedArrows[key :: string] = nil
		end
		folder:Destroy()
	end)
end

-- `punch` defaults to true; pass false for text that ticks every frame (capture percent) so the box holds still.
function Markers.setSub(id: string, text: string, color: Color3?, punch: boolean?)
	local m = markers[id]
	if not m then
		return
	end
	text = Hint.swap(text)
	if m.sub.Text ~= text then
		m.sub.Text = text
		if punch ~= false then
			UI.punch(m.frame, 1.12, 0.2)
		end
	end
	m.sub.TextColor3 = color or Theme.Colors.text
end

function Markers.setProgress(id: string, progress: number, active: boolean)
	local m = markers[id]
	if not m then
		return
	end
	m.bar.Visible = true
	m.barFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
	m.barFill.BackgroundColor3 = if active then Theme.Colors.cash else Theme.Colors.malus
end

-- Brief 7: door beacons on THE BANK. Closed: amber, the door's label and its UNLOCKS line, a ▲ badge far off.
-- Called: job blue with the objective's name and HOLD F (a turning diamond for DoorGuideSec). Open: gone.
local doorPing: { [string]: number } = {} -- group -> os.clock() the loud pulse ends
local doorList: { any } = {}

-- Round 30d: the called objective's prop itself (the front doors, the stair chains, the shutters) outlined in amber
-- through walls, the way the side job's prop is outlined blue: the thing to go and open.
local doorOutlines: { [string]: Highlight } = {}
local function outlineDoors()
	local want: { [string]: boolean } = {}
	local bank = Workspace:FindFirstChild("Bank")
	local props = bank and bank:FindFirstChild("DoorProps")
	for _, d in doorList do
		if d.state ~= "called" or not props then
			continue
		end
		local name = tostring(d.name)
		local model = props:FindFirstChild("DoorProp_" .. name)
		if not model then
			continue
		end
		want[name] = true
		local h = doorOutlines[name]
		if not h or not h.Parent or h.Adornee ~= model then
			if h then
				h:Destroy()
			end
			local nh = Instance.new("Highlight")
			nh.Name = "ObjectiveOutline"
			nh.Adornee = model
			nh.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			nh.FillColor = Theme.Colors.amber
			nh.FillTransparency = 1 - math.clamp(Config.ObjectiveHighlightFill, 0, 1)
			nh.OutlineColor = Theme.Colors.amber
			nh.OutlineTransparency = 0
			nh.Parent = Workspace.CurrentCamera or Workspace
			doorOutlines[name] = nh
		end
	end
	for name, h in table.clone(doorOutlines) do
		if not want[name] then
			h:Destroy()
			doorOutlines[name] = nil
		end
	end
end

local function drawDoors()
	outlineDoors()
	local live: { [string]: boolean } = {}
	for _, d in doorList do
		local id = "door_" .. tostring(d.name)
		if d.state == "open" then
			continue
		end
		live[id] = true
		local called = d.state == "called"
		local loud = called and (doorPing[d.group] or 0) > os.clock()
		local m = markers[id]
		local want = if called then (if loud then "loud" else "called") else "closed"
		if m and (m :: any).doorState == want then
			continue
		end
		Markers.add(
			id,
			d.position,
			-- Round 30d: a called door is amber (objectives; side jobs are blue), a door still locked is grey.
			if called then Theme.Colors.amber else Theme.Colors.grey,
			if called then tostring(d.ping) else tostring(d.label),
			if called then tostring(d.hint or Lines.door.markerHint) else tostring(d.sign),
			0,
			"▲",
			-- Phones read the closed doors' UNLOCKS line at full size (brief 7 mobile pass).
			{
				scale = if called or ClientState.isMobile then 1 else 0.8,
				diamond = loud,
				noCompact = loud,
				-- Round 19: a closed door's beacon reads only within DoorBeaconRange; a called one from anywhere.
				maxDistance = if called then nil else Config.DoorBeaconRange,
				prio = if called then 2 else 5,
				group = "door:" .. tostring(d.group),
			}
		);
		(markers[id] :: any).doorState = want
	end
	for id in table.clone(markers) do
		if string.sub(id, 1, 5) == "door_" and not live[id] then
			Markers.remove(id)
		end
	end
end

function Markers.init()
	TierMarkers.init()
	TierMarkers.objectiveDebug = function()
		for id, m in markers do
			TierMarkers.debugMark(
				"obj" .. id,
				m.position + Vector3.new(0, 1.5, 0),
				string.format("OBJECTIVE p%d %s", m.prio, if m.tierHidden then "CAP" else "SHOW")
			)
		end
	end
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "DoorState" and typeof(data.doors) == "table" then
			doorList = data.doors
			drawDoors()
		elseif name == "OfficeState" and typeof(data.position) == "Vector3" then
			-- Round 19f: an open office counts down at its door: the loot window, then the gas.
			local id = "office_" .. tostring(data.id)
			local o = Lines.office
			if data.phase == "open" then
				Markers.add(
					id,
					data.position,
					Theme.Colors.amber,
					tostring(data.label or o.markerTitle),
					o.markerOpen,
					tonumber(data.endsAt) or 0,
					nil,
					{ prio = 3 }
				)
			elseif data.phase == "warn" or data.phase == "gas" then
				local m = markers[id]
				if m then
					m.endsAt = tonumber(data.endsAt) or 0
					m.color = Theme.Colors.red
					m.stroke.Color = Theme.Colors.red
					Markers.setSub(id, if data.phase == "warn" then o.markerWarn else o.markerGas, Theme.Colors.red)
				end
			else
				Markers.remove(id)
			end
		elseif name == "DoorPing" then
			local sec = tonumber(data.sec) or Config.DoorGuideSec
			doorPing[tostring(data.group)] = os.clock() + sec
			drawDoors()
			task.delay(sec + 0.05, drawDoors)
		elseif name == "CallStart" and data.jobKind == "door" then
			-- The door's own beacons turn blue (DoorState); no separate job marker.
			return
		elseif name == "CallStart" and typeof(data.position) == "Vector3" then
			jobMarkerId = data.id -- Round 24: a door call ending must not take the side job's beacon with it
			local capture = data.jobKind == "capture"
			local vault = data.jobKind == "vault"
			local hint = if typeof(data.markerHint) == "string"
				then data.markerHint
				elseif capture then Lines.capture.markerHint
				else Lines.hackMarkerHint
			if vault then
				-- CRACK THE VAULT is the Objective tier: the normal marker (amber); the floor chevrons are its guide.
				Markers.add(
					"job",
					data.position,
					Theme.Colors.amber,
					tostring(data.name),
					hint,
					data.endsAt or 0,
					nil,
					{ prio = 1 }
				)
			else
				-- Brief 13: a side job is the Job tier (the outlined prop, the pill, the soft pulse).
				Markers.remove("job")
				TierMarkers.setJob(data.id, data.position, tostring(data.name), hint)
			end
		elseif name == "Resumed" then
			local d = tonumber(data and data.duration) or 0
			for _, m in markers do
				if m.endsAt > 0 then
					m.endsAt += d
				end
			end
		elseif name == "VaultArrows" and typeof(data.from) == "Vector3" and typeof(data.to) == "Vector3" then
			floorArrows(
				data.from,
				data.to,
				tonumber(data.sec) or Config.VaultArrowSec,
				if typeof(data.points) == "table" then data.points else nil,
				if typeof(data.key) == "string" then data.key else nil
			)
		elseif name == "DoorOpened" then
			-- Round 30d: the door is open: its guide strip goes at once.
			local strip = keyedArrows.door
			if strip then
				strip:Destroy()
				keyedArrows.door = nil
			end
		elseif name == "JobProgress" then
			-- Brief 13: the capture job is the Job tier: its pill carries the bar and the hint line.
			local pct = math.floor((data.progress or 0) * 100 + 0.5)
			local inside = data.inside == true
			TierMarkers.jobProgress(data.progress or 0, inside)
			if inside then
				TierMarkers.jobHint(string.format(Lines.capture.holdingHint, pct), Theme.Colors.cash)
			elseif pct > 0 then
				TierMarkers.jobHint(string.format(Lines.capture.leftHint, pct), Theme.Colors.malus)
			else
				TierMarkers.jobHint(Lines.capture.markerHint, nil)
			end
		elseif (name == "CallEnd" or name == "CallCleared") and (data.id == jobMarkerId or jobMarkerId == nil) then
			jobMarkerId = nil
			Markers.remove("job")
			TierMarkers.clearJob()
		elseif name == "BagSpawned" and typeof(data.position) == "Vector3" then
			-- Brief 13: bags are the Loot tier (TierMarkers): a small $ / ◆ icon, its name only while looked at,
			-- through walls only when close. No key hint: walking up to a bag picks it up (BagChannel.lua).
			local gold = data.kind == "gold"
			TierMarkers.bag("bag" .. tostring(data.id), data.position, gold, if gold then "GOLD BAG" else "CASH BAG")
		elseif name == "BagCollected" or name == "BagFizzled" then
			TierMarkers.unloot("bag" .. tostring(data.id))
		elseif name == "Intermission" then
			-- [GHS Markers] loot shown / hidden at the wave's busiest moment, once per wave.
			print(string.format("[GHS Markers] loot shown %d hidden %d", peakShown, peakHidden))
			peakShown, peakHidden = 0, 0
		elseif name == "VaultOpen" and typeof(data.position) == "Vector3" then
			-- Brief 7: on THE BANK the hatch gets a blue beacon on the street side for the window.
			if typeof(data.hatch) == "Vector3" then
				Markers.add(
					"hatch",
					data.hatch,
					Theme.Colors.blue,
					Lines.vault.hatchTitle,
					Lines.vault.hatchHint,
					0,
					"▲",
					{ prio = 4 }
				)
			end
			Markers.add(
				"vault",
				data.position,
				Theme.Colors.amber,
				tostring(data.name or "VAULT"),
				tostring(data.hint or Lines.vault.lootHint),
				tonumber(data.endsAt) or 0,
				"◆",
				{ prio = 1 }
			)
		elseif name == "VaultGas" then
			if data.phase == "warn" then
				local left = math.max(0, math.ceil((tonumber(data.endsAt) or 0) - ClientState.serverNow()))
				Markers.setSub("vault", string.format(Lines.vault.gasWarnHint, left), Theme.Colors.red)
			else
				Markers.setSub("vault", Lines.vault.gasHint, Theme.Colors.red)
			end
		elseif name == "VaultLooted" then
			Markers.remove("vault") -- Round 19c: nothing left inside, nothing to point at
		elseif name == "VaultSealed" or name == "HubEnter" then
			Markers.remove("vault")
			Markers.remove("hatch")
			if name == "HubEnter" then
				for id in table.clone(markers) do
					Markers.remove(id)
				end
				TierMarkers.clearJob()
				TierMarkers.clearLoot()
			end
		end
	end)

	-- Timer and distance refresh.
	local acc = 0
	local pulse = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		pulse += dt * 6
		-- The vault diamond turns every frame; the rest refreshes ten times a second.
		-- Round 24: cutscenes (run start / end, the boss) show no world markers.
		local hide = ClientState.cameraMode == "cinematic"
		for _, h in doorOutlines do
			if h.Enabled == hide then
				h.Enabled = not hide
			end
		end
		for _, m in markers do
			local bb = m.att:FindFirstChildOfClass("BillboardGui")
			local off = hide or m.tierHidden -- brief 13: the Objective cap holds the rest back
			if bb and bb.Enabled == off then
				bb.Enabled = not off
			end
			local dm = m.diamond
			if dm then
				dm.Rotation = (dm.Rotation + dt * 120) % 360
			end
			-- Round 30d: the halo breathes (the urgent ones harder, with the outline swelling in time).
			if not m.isCompact then
				local beat = 0.5 + 0.5 * math.sin(os.clock() * (if m.urgent then 4 else 2))
				m.glow.BackgroundTransparency = if m.urgent then 0.4 + 0.4 * beat else 0.75 + 0.15 * beat
				if m.urgent then
					m.stroke.Thickness = m.strokeBase * (1 + 0.8 * beat)
				end
			end
		end
		if acc < 0.1 then
			return
		end
		acc = 0
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local now = ClientState.serverNow()
		-- Brief 13: the Objective cap. The most urgent (lowest prio), then the nearest, ObjectiveMarkerCap of them.
		local ranked: { Marker } = {}
		for _, m in markers do
			table.insert(ranked, m)
		end
		local here = if root then root.Position else Vector3.zero
		table.sort(ranked, function(a, b)
			if a.prio ~= b.prio then
				return a.prio < b.prio
			end
			return (a.position - here).Magnitude < (b.position - here).Magnitude
		end)
		local mainUp = false
		local groupsShown: { [string]: boolean } = {}
		local nGroups = 0
		for _, m in ranked do
			if not groupsShown[m.group] and nGroups < Config.ObjectiveMarkerCap then
				groupsShown[m.group] = true
				nGroups += 1
			end
			m.tierHidden = not groupsShown[m.group]
			mainUp = mainUp or m.prio <= 2 -- a called door, the vault job, the open vault
		end
		-- Round 30d: with a main objective up, the side job shows as a small waypoint.
		TierMarkers.setMainObjective(mainUp)
		local shownNow, hiddenNow = TierMarkers.lootStats()
		peakShown = math.max(peakShown, shownNow)
		peakHidden = math.max(peakHidden, hiddenNow)
		for _, m in markers do
			local timeText = ""
			local warn = false
			if m.endsAt > 0 then
				local remaining = m.endsAt - now
				timeText = fmtTime(remaining)
				warn = remaining < Config.CallPillWarnSec
				m.timer.Text = timeText
				if warn then
					m.timer.TextColor3 = Theme.Colors.red
					m.stroke.Color = Theme.Colors.red
					m.stroke.Transparency = 0.25 + 0.25 * math.sin(pulse)
				else
					m.timer.TextColor3 = m.color
				end
			end
			if root then
				local d = (m.position - root.Position).Magnitude
				m.dist.Text = string.format("%dm", math.round(d))
				m.dist.TextColor3 = if d < 12 then Theme.Colors.cash else m.color
				-- Far away: the pill gives way to the badge (5 stud hysteresis so it never flickers).
				local limit = Config.MarkerCompactDistance + (if m.isCompact then -5 else 0)
				local wantCompact = d > limit and not m.noCompact
				if wantCompact ~= m.isCompact then
					m.isCompact = wantCompact
					m.frame.Visible = not wantCompact
					m.glow.Visible = not wantCompact
					m.tick.Visible = not wantCompact
					m.compact.Visible = wantCompact
					UI.punch(if wantCompact then m.compact else m.frame, 1.25, 0.3)
				end
				-- Round 30d: the key hint only once you are close enough to use it.
				m.sub.Visible = not m.isCompact and d <= Config.ObjectiveHintRange
				if m.isCompact then
					m.compactLabel.Text = if timeText ~= ""
						then string.format("%dm · %s", math.round(d), timeText)
						else string.format("%dm", math.round(d))
					m.compactLabel.TextColor3 = if warn then Theme.Colors.red else m.color
					m.compact.BackgroundColor3 = if warn then Theme.Colors.red else m.color
				end
			end
		end
	end)
end

return Markers
