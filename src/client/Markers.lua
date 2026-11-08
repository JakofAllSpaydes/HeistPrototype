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
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

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
}

-- Optional look for a marker: `scale` multiplies every size, `noCompact` keeps the full box at any distance,
-- `diamond` puts a rotating diamond in the marker color over it.
export type Opts = { scale: number?, noCompact: boolean?, diamond: boolean?, maxDistance: number? }

local Markers = {}

local player = Players.LocalPlayer
local markers: { [string]: Marker } = {}
local jobMarkerId: any = nil -- the side job call the "job" marker belongs to

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
	local diamondH = if opts and opts.diamond then S(34) else 0
	local att = Instance.new("Attachment")
	att.Name = "Marker_" .. id
	att.WorldPosition = position + Vector3.new(0, 7.5, 0)
	att.Parent = Workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Adornee = att
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(S(176), S(76) + diamondH)
	gui.MaxDistance = (opts and opts.maxDistance) or 500
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
			Size = UDim2.fromOffset(diamondH * 0.62, diamondH * 0.62),
			Rotation = 45,
			Parent = gui,
		})
		UI.corner(dm, S(3))
		UI.stroke(dm, Theme.Colors.white, S(2), 0.2)
		diamond = dm
	end
	local frame = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.15,
		Position = UDim2.fromOffset(0, diamondH),
		Size = UDim2.new(1, 0, 1, -diamondH),
		Parent = gui,
	})
	UI.corner(frame, S(10))
	local stroke = UI.stroke(frame, color, S(2))
	local title = UI.text({
		Text = titleText,
		FontFace = Theme.Fonts.display,
		TextSize = S(17),
		TextColor3 = color,
		Position = UDim2.fromOffset(0, S(4)),
		Size = UDim2.new(1, 0, 0, S(22)),
		Parent = frame,
	})
	local sub = UI.text({
		Text = subText,
		TextSize = S(11),
		TextColor3 = Theme.Colors.text,
		Position = UDim2.fromOffset(0, S(25)),
		Size = UDim2.new(1, 0, 0, S(16)),
		Parent = frame,
	})
	local timer = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(16),
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(12), S(44)),
		Size = UDim2.new(0.5, -S(12), 0, S(22)),
		Parent = frame,
	})
	local dist = UI.text({
		Text = "",
		TextSize = S(12),
		TextColor3 = Theme.Colors.grey,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0.5, 0, 0, S(46)),
		Size = UDim2.new(0.5, -S(12), 0, S(18)),
		Parent = frame,
	})
	-- Progress bar along the bottom edge (capture point); hidden until setProgress is called.
	local bar = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		Position = UDim2.new(0, S(12), 1, -S(10)),
		Size = UDim2.new(1, -S(24), 0, S(5)),
		Visible = false,
		Parent = frame,
	})
	UI.corner(bar, S(3))
	local barFill = UI.frame({
		BackgroundColor3 = Theme.Colors.cash,
		Size = UDim2.fromScale(0, 1),
		Parent = bar,
	})
	UI.corner(barFill, S(3))
	-- Pointer tick under the box.
	local tick = UI.frame({
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, -S(2)),
		Size = UDim2.fromOffset(S(10), S(10)),
		Rotation = 45,
		Parent = frame,
	})
	UI.corner(tick, S(2))
	UI.punch(frame, 1.35, 0.4)

	-- Compact form for far away: a small badge with the distance and timer under it.
	local compact = UI.frame({
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(18)),
		Size = UDim2.fromOffset(S(30), S(30)),
		Visible = false,
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
		Parent = compact,
	})
	local compactLabel = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(12),
		TextColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, S(2)),
		Size = UDim2.fromOffset(S(120), S(16)),
		Parent = compact,
	})
	UI.stroke(compactLabel, Theme.Colors.black, S(1.5), 0.3)

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
		noCompact = opts ~= nil and opts.noCompact == true,
		diamond = diamond,
	}
end

-- CRACK THE VAULT: a chevron strip on the floor from the crew to the door for VaultArrowSec, lit in a running
-- wave toward the door (the FTUE arrows will use the same look).
-- Round 19: `points` is the walking route the server planned (stairs and floors included); without it the strip
-- is the straight line. Chevrons sit every 4 studs along the route, on the floor under each point.
local function floorArrows(from: Vector3, to: Vector3, seconds: number, points: { Vector3 }?)
	local route: { Vector3 } = if points and #points >= 2 then points else { from, to }
	local folder = Instance.new("Folder")
	folder.Name = "VaultArrows"
	folder.Parent = Workspace:FindFirstChild("Effects") or Workspace
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
		while os.clock() - t0 < seconds and folder.Parent do
			local t = os.clock() - t0
			local head = (t * 6) % math.max(count, 1)
			for i, bar in chevrons do
				local k = (i + 1) // 2
				local near = math.abs(k - head) < 1.5
				local fade = math.clamp((seconds - t) / 1.5, 0, 1)
				bar.Transparency = 1 - (if near then 0.9 else 0.35) * fade
			end
			task.wait(1 / 30)
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

local function drawDoors()
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
			if called then Theme.Colors.blue else Theme.Colors.amber,
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
					tonumber(data.endsAt) or 0
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
			Markers.add(
				"job",
				data.position,
				if vault then Theme.Colors.amber else Theme.Colors.blue,
				tostring(data.name),
				if typeof(data.markerHint) == "string"
					then data.markerHint
					elseif capture then Lines.capture.markerHint
					else Lines.hackMarkerHint,
				data.endsAt or 0,
				nil,
				nil -- the vault job keeps the normal marker (amber); the floor chevrons are its extra guide
			)
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
				if typeof(data.points) == "table" then data.points else nil
			)
			if capture then
				Markers.setProgress("job", 0, true)
			end
		elseif name == "JobProgress" then
			local pct = math.floor((data.progress or 0) * 100 + 0.5)
			local inside = data.inside == true
			Markers.setProgress("job", data.progress or 0, inside)
			-- Only a step in / step out pops the box; the percent ticks quietly.
			local m = markers.job
			local flipped = m ~= nil and m.wasInside ~= inside
			if m then
				m.wasInside = inside
			end
			if inside then
				Markers.setSub("job", string.format(Lines.capture.holdingHint, pct), Theme.Colors.cash, flipped)
			elseif pct > 0 then
				Markers.setSub("job", string.format(Lines.capture.leftHint, pct), Theme.Colors.malus, flipped)
			else
				Markers.setSub("job", Lines.capture.markerHint, nil, flipped)
			end
		elseif (name == "CallEnd" or name == "CallCleared") and (data.id == jobMarkerId or jobMarkerId == nil) then
			jobMarkerId = nil
			Markers.remove("job")
		elseif name == "BagSpawned" and typeof(data.position) == "Vector3" then
			-- Bag beacons read through walls: kind and value; a $ / ◆ badge far away. No key hint: walking up
			-- to a bag picks it up (BagChannel.lua draws the fill).
			local gold = data.kind == "gold"
			local value = tonumber(data.value) or 0
			Markers.add(
				"bag" .. tostring(data.id),
				data.position,
				if gold then Theme.Colors.gold else Theme.Colors.cash,
				if gold then "GOLD BAG" else "CASH BAG",
				if gold then "◆ " .. tostring(value) else "$" .. tostring(value),
				0,
				if gold then "◆" else "$"
			)
		elseif name == "BagCollected" or name == "BagFizzled" then
			Markers.remove("bag" .. tostring(data.id))
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
					"▲"
				)
			end
			Markers.add(
				"vault",
				data.position,
				Theme.Colors.amber,
				tostring(data.name or "VAULT"),
				tostring(data.hint or Lines.vault.lootHint),
				tonumber(data.endsAt) or 0,
				"◆"
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
		for _, m in markers do
			local bb = m.att:FindFirstChildOfClass("BillboardGui")
			if bb and bb.Enabled == hide then
				bb.Enabled = not hide
			end
			local dm = m.diamond
			if dm then
				dm.Rotation = (dm.Rotation + dt * 120) % 360
			end
		end
		if acc < 0.1 then
			return
		end
		acc = 0
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local now = ClientState.serverNow()
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
				m.dist.TextColor3 = if d < 12 then Theme.Colors.cash else Theme.Colors.grey
				-- Far away: the full panel gives way to the badge (5 stud hysteresis so it never flickers).
				local limit = Config.MarkerCompactDistance + (if m.isCompact then -5 else 0)
				local wantCompact = d > limit and not m.noCompact
				if wantCompact ~= m.isCompact then
					m.isCompact = wantCompact
					m.frame.Visible = not wantCompact
					m.compact.Visible = wantCompact
					UI.punch(if wantCompact then m.compact else m.frame, 1.25, 0.3)
				end
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
