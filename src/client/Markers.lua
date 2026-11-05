--!strict
-- World markers: a fixed-size billboard over the side job beacon with a name, status line, timer and
-- distance, so it is findable from across the room. Fed by the crew call juice events; the crate has
-- none on purpose (the fanned guns already read from a distance).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
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
}

local Markers = {}

local player = Players.LocalPlayer
local markers: { [string]: Marker } = {}

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
	glyph: string?
)
	Markers.remove(id)
	local S = UI.S
	local att = Instance.new("Attachment")
	att.Name = "Marker_" .. id
	att.WorldPosition = position + Vector3.new(0, 7.5, 0)
	att.Parent = Workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Adornee = att
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(S(176), S(76))
	gui.MaxDistance = 500
	gui.LightInfluence = 0
	gui.Parent = att
	local frame = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.15,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	UI.corner(frame, S(10))
	local stroke = UI.stroke(frame, color, S(2))
	local title = UI.text({
		Text = titleText,
		Font = Theme.Fonts.display,
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
		Font = Theme.Fonts.display,
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
		Font = Theme.Fonts.display,
		TextSize = S(20),
		TextColor3 = Theme.Colors.bg,
		Size = UDim2.fromScale(1, 1),
		Parent = compact,
	})
	local compactLabel = UI.text({
		Text = "",
		Font = Theme.Fonts.display,
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
	}
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

function Markers.init()
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "CallStart" and typeof(data.position) == "Vector3" then
			local capture = data.jobKind == "capture"
			Markers.add(
				"job",
				data.position,
				Theme.Colors.blue,
				tostring(data.name),
				if typeof(data.markerHint) == "string"
					then data.markerHint
					elseif capture then Lines.capture.markerHint
					else Lines.hackMarkerHint,
				data.endsAt or 0
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
		elseif name == "CallEnd" or name == "CallCleared" then
			Markers.remove("job")
		elseif name == "BagSpawned" and typeof(data.position) == "Vector3" then
			-- Bag beacons read through walls: kind, the hold hint and the value; a $ / ◆ badge far away.
			local gold = data.kind == "gold"
			local value = tonumber(data.value) or 0
			Markers.add(
				"bag" .. tostring(data.id),
				data.position,
				if gold then Theme.Colors.gold else Theme.Colors.cash,
				if gold then "GOLD BAG" else "CASH BAG",
				string.format("HOLD F · %s", if gold then "◆ " .. tostring(value) else "$" .. tostring(value)),
				0,
				if gold then "◆" else "$"
			)
		elseif name == "BagCollected" or name == "BagFizzled" then
			Markers.remove("bag" .. tostring(data.id))
		elseif name == "VaultOpen" and typeof(data.position) == "Vector3" then
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
		elseif name == "VaultSealed" or name == "HubEnter" then
			Markers.remove("vault")
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
				local wantCompact = d > limit
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
