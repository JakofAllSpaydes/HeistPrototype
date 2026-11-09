--!strict
-- Round 19d: lockdown gas on this client (ZoneGas mode "force"). While a door objective is overdue the building
-- floods; this pins a short red line under the objective pill (the door's name and where the clean air is) and,
-- whenever the door is off screen, a blue arrow at the screen edge pointing at it. The floor chevrons and the
-- door's loud beacon come from the server (VaultArrows / DoorPing). Everything goes on the clear (or the hub).
-- Round 19g: a door called for the first time (DoorGuide) gets the same edge arrow, no banner, for its guide window
-- or until it opens; a lockdown's target wins while both run.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Lines = require(Shared:WaitForChild("CrewCall"):WaitForChild("Lines"))
local Config = require(Shared:WaitForChild("Config"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local LockdownUI = {}

local player = Players.LocalPlayer
local target: Vector3? = nil
local guideTarget: Vector3? = nil -- Round 19g: a newly called door
local guideGroup: string? = nil
local guideUntil = 0
local gui: ScreenGui
local banner: Frame
local title: TextLabel
local sub: TextLabel
local arrow: Frame
local arrowStroke: UIStroke
local dist: TextLabel
local conn: RBXScriptConnection? = nil

local function build()
	local S = UI.S
	gui = UI.new("ScreenGui", {
		Name = "Lockdown",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 5,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	banner = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(152)),
		Size = UDim2.fromOffset(S(420), S(34)),
		Visible = false,
		Parent = gui,
	})
	title = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(16),
		TextColor3 = Theme.Colors.red,
		Size = UDim2.new(1, 0, 0, S(18)),
		Parent = banner,
	})
	UI.stroke(title, Theme.Colors.black, S(1.5), 0.2)
	sub = UI.text({
		Text = "",
		FontFace = Theme.Fonts.body,
		TextSize = S(10),
		TextColor3 = Theme.Colors.text,
		Position = UDim2.fromOffset(0, S(18)),
		Size = UDim2.new(1, 0, 0, S(14)),
		Parent = banner,
	})
	UI.stroke(sub, Theme.Colors.black, S(1), 0.3)
	-- The edge arrow: a ▲ (the house marker glyph) on a dark disc, turned to point at the door.
	-- Round 30d: amber like every objective (side jobs are the blue ones), bigger, pulsing, with the live distance.
	arrow = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.15,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(S(52), S(52)),
		Visible = false,
		Parent = gui,
	})
	UI.corner(arrow, S(26))
	arrowStroke = UI.stroke(arrow, Theme.Colors.amber, S(3))
	UI.text({
		Text = "▲",
		FontFace = Theme.Fonts.body,
		TextSize = S(28),
		TextColor3 = Theme.Colors.amber,
		Size = UDim2.fromScale(1, 1),
		Parent = arrow,
	})
	-- The distance sits under the disc and never turns with it.
	dist = UI.text({
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(16),
		TextColor3 = Theme.Colors.amber,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(S(80), S(18)),
		Visible = false,
		Parent = gui,
	})
	UI.stroke(dist, Theme.Colors.black, S(1.5), 0.2)
end

local function disconnectIfIdle()
	if target == nil and guideTarget == nil and conn then
		conn:Disconnect()
		conn = nil
		arrow.Visible = false
		dist.Visible = false
	end
end

local function stop()
	target = nil
	banner.Visible = false
	arrow.Visible = false
	dist.Visible = false
	disconnectIfIdle()
end

local function stopGuide()
	guideTarget = nil
	guideGroup = nil
	disconnectIfIdle()
end

-- Off screen (or behind the camera): the arrow sits on an inset ellipse round the screen centre, pointing out.
local function step()
	if guideTarget and os.clock() > guideUntil then
		stopGuide()
		return
	end
	local t = target or guideTarget
	local cam = Workspace.CurrentCamera
	if not t or not cam then
		arrow.Visible = false
		dist.Visible = false
		return
	end
	local view = cam.ViewportSize
	local p, onScreen = cam:WorldToViewportPoint(t)
	if onScreen and p.Z > 0 then
		arrow.Visible = false
		dist.Visible = false
		return
	end
	local center = view / 2
	local d = Vector2.new(p.X, p.Y) - center
	if p.Z < 0 then
		d = -d -- behind: mirror through the centre
	end
	if d.Magnitude < 1 then
		d = Vector2.new(0, 1)
	end
	local dir = d.Unit
	local inset = UI.S(70)
	local rx, ry = math.max(center.X - inset, 10), math.max(center.Y - inset, 10)
	local pos = center + Vector2.new(dir.X * rx, dir.Y * ry)
	arrow.Position = UDim2.fromOffset(pos.X, pos.Y)
	arrow.Rotation = math.deg(math.atan2(dir.X, -dir.Y)) -- ▲ points up at 0
	arrow.Visible = true
	-- A slow breathe so it reads from the corner of your eye, and how far it is.
	local beat = 0.5 + 0.5 * math.sin(os.clock() * 5)
	arrowStroke.Thickness = UI.S(2 + 2 * beat)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and Config.DoorGuideEdgeDistance then
		dist.Text = string.format("%dm", math.round((t - root.Position).Magnitude))
		dist.Position = UDim2.fromOffset(pos.X, pos.Y + UI.S(28))
		dist.Visible = true
	else
		dist.Visible = false
	end
end

local function start(data: any)
	if typeof(data.position) == "Vector3" then
		target = data.position
	end
	title.Text = string.format(Lines.zoneGas.forceBanner, tostring(data.title or ""))
	sub.Text = string.format(Lines.zoneGas.forceBannerSub, tostring(data.safeLabel or ""))
	if not banner.Visible then
		banner.Visible = true
		UI.punch(banner, 1.08, 0.2)
	end
	if not conn then
		conn = RunService.RenderStepped:Connect(step)
	end
end

function LockdownUI.init()
	build()
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "ZoneGas" and data.force == true then
			if data.phase == "clear" then
				stop()
			else
				start(data)
			end
		elseif name == "DoorGuide" and typeof(data.position) == "Vector3" then
			guideTarget = data.position
			guideGroup = tostring(data.group)
			guideUntil = os.clock() + (tonumber(data.sec) or 20)
			if not conn then
				conn = RunService.RenderStepped:Connect(step)
			end
		elseif name == "DoorOpened" and guideGroup and tostring(data.group) == guideGroup then
			stopGuide()
		elseif name == "HubEnter" then
			stop()
			stopGuide()
		end
	end)
end

return LockdownUI
