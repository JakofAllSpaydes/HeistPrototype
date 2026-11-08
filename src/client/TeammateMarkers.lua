--!strict
-- Round 25: where the crew is, at any distance. In a run every other party member (the scoreboard roster) gets a
-- marker over their head drawn on a ScreenGui, so walls and range never hide it: a class-coloured diamond, the
-- name in the display face and the distance under it (DOWN in red while they are downed). Off screen it moves to
-- an inset ellipse round the screen centre as a disc with a ▲ turned toward them (the LockdownUI edge arrow look).
-- Close by and on screen it fades out (Config.TeammateMarkerHideNear): you can see them.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Classes = require(Shared:WaitForChild("Classes"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local TeammateMarkers = {}

local player = Players.LocalPlayer

type Marker = {
	root: Frame, -- on-screen marker (diamond, name, distance)
	diamond: Frame,
	name: TextLabel,
	dist: TextLabel,
	edge: Frame, -- off-screen arrow disc
	edgeStroke: UIStroke,
	edgeGlyph: TextLabel,
	edgeName: TextLabel,
	color: Color3,
}

local gui: ScreenGui
local markers: { [number]: Marker } = {}

local function build(userId: number, name: string, color: Color3): Marker
	local S = UI.S
	local root = UI.frame({
		Name = "Mate_" .. userId,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(S(160), S(58)),
		Visible = false,
		Parent = gui,
	})
	local nameLabel = UI.text({
		Text = string.upper(name),
		FontFace = Theme.Fonts.display,
		TextSize = S(16),
		TextColor3 = Theme.Colors.white,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, S(20)),
		Parent = root,
	})
	UI.stroke(nameLabel, Theme.Colors.black, S(1.5), 0.2)
	local dist = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(12),
		TextColor3 = Theme.Colors.text,
		Position = UDim2.fromOffset(0, S(19)),
		Size = UDim2.new(1, 0, 0, S(15)),
		Parent = root,
	})
	UI.stroke(dist, Theme.Colors.black, S(1.5), 0.3)
	local diamond = UI.frame({
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(4)),
		Size = UDim2.fromOffset(S(14), S(14)),
		Rotation = 45,
		Parent = root,
	})
	UI.stroke(diamond, Theme.Colors.black, S(2), 0.1)

	local edge = UI.frame({
		Name = "Edge_" .. userId,
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.2,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(S(38), S(38)),
		Visible = false,
		Parent = gui,
	})
	UI.corner(edge, S(19))
	local edgeStroke = UI.stroke(edge, color, S(2.5), 0)
	local glyph = UI.text({
		Text = "▲",
		FontFace = Theme.Fonts.body,
		TextSize = S(20),
		TextColor3 = color,
		Size = UDim2.fromScale(1, 1),
		Parent = edge,
	})
	local edgeName = UI.text({
		Text = string.upper(name),
		FontFace = Theme.Fonts.display,
		TextSize = S(13),
		TextColor3 = Theme.Colors.white,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(S(140), S(16)),
		Parent = gui,
		Visible = false,
	})
	UI.stroke(edgeName, Theme.Colors.black, S(1.5), 0.2)
	return {
		root = root,
		diamond = diamond,
		name = nameLabel,
		dist = dist,
		edge = edge,
		edgeStroke = edgeStroke,
		edgeGlyph = glyph,
		edgeName = edgeName,
		color = color,
	}
end

local function destroy(userId: number)
	local m = markers[userId]
	if m then
		m.root:Destroy()
		m.edge:Destroy()
		m.edgeName:Destroy()
		markers[userId] = nil
	end
end

local function hideAll()
	for userId in table.clone(markers) do
		destroy(userId)
	end
end

local function step()
	local sync = ClientState.sync :: any
	local roster = sync and sync.roster
	local cam = Workspace.CurrentCamera
	if
		not Config.TeammateMarkers
		or not roster
		or not cam
		or ClientState.inHub()
		or ClientState.cameraMode ~= "gameplay"
	then
		if next(markers) then
			hideAll()
		end
		return
	end
	local myChar = player.Character
	local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	local seen: { [number]: boolean } = {}
	local view = cam.ViewportSize
	local center = view / 2
	for _, row in roster.rows or {} do
		local userId = tonumber(row.userId)
		if not userId or userId == player.UserId or row.state == "spectating" then
			continue
		end
		local p = Players:GetPlayerByUserId(userId)
		local char = p and p.Character
		local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")) :: BasePart?
		if not head then
			continue
		end
		seen[userId] = true
		local class = Classes.ById[tostring(row.classId)] or Classes.ById[Classes.Default]
		local m = markers[userId]
		if not m then
			m = build(userId, tostring(row.name or (p :: Player).Name), Color3.fromHex(class.color))
			markers[userId] = m
		end
		local mk = m :: Marker
		local downed = row.state == "downed"
		local color = if downed then Theme.Colors.red else mk.color
		mk.diamond.BackgroundColor3 = color
		mk.edgeStroke.Color = color
		mk.edgeGlyph.TextColor3 = color
		local at = head.Position + Vector3.new(0, Config.TeammateMarkerOffset, 0)
		local d = if myRoot then (at - myRoot.Position).Magnitude else 0
		mk.dist.Text = if downed then "DOWN" else string.format("%dM", math.round(d))
		mk.dist.TextColor3 = if downed then Theme.Colors.red else Theme.Colors.text
		local sp, onScreen = cam:WorldToViewportPoint(at)
		if onScreen and sp.Z > 0 then
			mk.edge.Visible = false
			mk.edgeName.Visible = false
			-- Right beside you and in view: you can see them, the marker steps aside (a downed one never does).
			mk.root.Visible = downed or d > Config.TeammateMarkerHideNear
			mk.root.Position = UDim2.fromOffset(sp.X, sp.Y)
		else
			mk.root.Visible = false
			local dv = Vector2.new(sp.X, sp.Y) - center
			if sp.Z < 0 then
				dv = -dv
			end
			if dv.Magnitude < 1 then
				dv = Vector2.new(0, 1)
			end
			local dir = dv.Unit
			local inset = UI.S(80)
			local rx, ry = math.max(center.X - inset, 10), math.max(center.Y - inset, 10)
			local pos = center + Vector2.new(dir.X * rx, dir.Y * ry)
			mk.edge.Position = UDim2.fromOffset(pos.X, pos.Y)
			mk.edge.Rotation = math.deg(math.atan2(dir.X, -dir.Y))
			mk.edge.Visible = true
			mk.edgeName.Position = UDim2.fromOffset(pos.X, pos.Y + UI.S(30))
			mk.edgeName.Visible = true
		end
	end
	for userId in table.clone(markers) do
		if not seen[userId] then
			destroy(userId)
		end
	end
end

function TeammateMarkers.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "TeammateMarkers"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2
	gui.Parent = player:WaitForChild("PlayerGui")
	RunService:BindToRenderStep("GHSTeammateMarkers", Enum.RenderPriority.Camera.Value + 5, step)
end

return TeammateMarkers
