--!strict
-- Round 19d: lockdown gas on this client (ZoneGas mode "force"). While a door objective is overdue the building
-- floods; this pins a short red line under the objective pill (the door's name and where the clean air is) and,
-- whenever the door is off screen, a blue arrow at the screen edge pointing at it. The floor chevrons and the
-- door's loud beacon come from the server (VaultArrows / DoorPing). Everything goes on the clear (or the hub).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Lines = require(Shared:WaitForChild("CrewCall"):WaitForChild("Lines"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local LockdownUI = {}

local player = Players.LocalPlayer
local target: Vector3? = nil
local gui: ScreenGui
local banner: Frame
local title: TextLabel
local sub: TextLabel
local arrow: Frame
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
		Font = Theme.Fonts.display,
		TextSize = S(16),
		TextColor3 = Theme.Colors.red,
		Size = UDim2.new(1, 0, 0, S(18)),
		Parent = banner,
	})
	UI.stroke(title, Theme.Colors.black, S(1.5), 0.2)
	sub = UI.text({
		Text = "",
		Font = Theme.Fonts.body,
		TextSize = S(10),
		TextColor3 = Theme.Colors.text,
		Position = UDim2.fromOffset(0, S(18)),
		Size = UDim2.new(1, 0, 0, S(14)),
		Parent = banner,
	})
	UI.stroke(sub, Theme.Colors.black, S(1), 0.3)
	-- The edge arrow: a ▲ (the house marker glyph) on a dark disc, turned to point at the door.
	arrow = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.25,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(S(40), S(40)),
		Visible = false,
		Parent = gui,
	})
	UI.corner(arrow, S(20))
	UI.stroke(arrow, Theme.Colors.blue, S(2))
	local glyph = UI.text({
		Text = "▲",
		Font = Theme.Fonts.body,
		TextSize = S(22),
		TextColor3 = Theme.Colors.blue,
		Size = UDim2.fromScale(1, 1),
		Parent = arrow,
	})
	local _ = glyph
end

local function stop()
	target = nil
	banner.Visible = false
	arrow.Visible = false
	if conn then
		conn:Disconnect()
		conn = nil
	end
end

-- Off screen (or behind the camera): the arrow sits on an inset ellipse round the screen centre, pointing out.
local function step()
	local t = target
	local cam = Workspace.CurrentCamera
	if not t or not cam then
		arrow.Visible = false
		return
	end
	local view = cam.ViewportSize
	local p, onScreen = cam:WorldToViewportPoint(t)
	if onScreen and p.Z > 0 then
		arrow.Visible = false
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
		elseif name == "HubEnter" then
			stop()
		end
	end)
end

return LockdownUI
