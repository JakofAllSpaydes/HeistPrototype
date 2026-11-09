--!strict
-- Round 27c: you can't miss a ready daily crate. While your crate is ready and you are walking the hub (no menu, no
-- scene, no streak modal), a trail of glowing chevrons runs along the floor from you to the podium, flowing toward
-- it (DailyCrateGuideSpacing apart, stopping DailyCrateGuideNear short), and a gold arrow sits on the screen edge
-- whenever the podium is off screen. Both go the moment it is opened. Once per fake day per session, MARLOW's hub card
-- nudges you (DailyCrateMarlowLine, DailyCrateNudgeSec after you land), unless you already tapped the summary's
-- crate card (the podium opens by itself then).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Clock = require(Shared:WaitForChild("Clock"))

local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local CameraShots = require(Client:WaitForChild("CameraShots"))

local DailyGuide = {}

local player = Players.LocalPlayer
local MAX_CHEVRONS = 24

local folder: Folder? = nil
local chevrons: { Model } = {}
local edge: Frame? = nil
local nudgedDay = -1
local readySince = 0 -- os.clock when the crate was first seen ready in the hub (the nudge counts from it)

local function ready(): boolean
	return player:GetAttribute("DailyCrate") == "ready"
end

local function guiding(): boolean
	return Config.DailyCrateEnabled
		and ready()
		and ClientState.inHub()
		and not ClientState.inRange()
		and ClientState.cameraMode == "gameplay"
		and not ClientState.streakOpen
end

local function chevron(parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = "Chevron"
	local gold = Color3.fromHex("FFD34D")
	for _, side in { -1, 1 } do
		local p = Instance.new("Part")
		p.Name = "Bar"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = gold
		p.Size = Vector3.new(0.28, 0.05, 1.4)
		-- A V pointing along -Z (the model's look): each bar runs from a back corner to the front tip.
		p.CFrame = CFrame.new(side * 0.35, 0, 0) * CFrame.Angles(0, math.rad(side * 35), 0)
		p.Parent = m
	end
	-- No PrimaryPart: the pivot is the V's centre (the origin the bars were placed around).
	m.WorldPivot = CFrame.new()
	m.Parent = parent
	return m
end

local function buildEdge()
	local S = UI.S
	local g = UI.new("ScreenGui", {
		Name = "DailyGuide",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 6,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	local disc = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.2,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(S(46), S(46)),
		Visible = false,
		Parent = g,
	})
	UI.corner(disc, S(23))
	UI.stroke(disc, Theme.Colors.gold, S(2.5), 0)
	-- A chevron pointing up at rotation 0 (two bars).
	for _, side in { -1, 1 } do
		local bar = UI.frame({
			BackgroundColor3 = Theme.Colors.gold,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, side * S(5), 0.5, 0),
			Size = UDim2.fromOffset(S(16), S(5)),
			Rotation = side * 40,
			Parent = disc,
		})
		UI.corner(bar, S(2))
	end
	edge = disc
end

local function hideAll()
	for _, c in chevrons do
		c.Parent = nil
	end
	local e = edge
	if e then
		e.Visible = false
	end
end

local function step()
	local spot = CameraShots.dailySpot()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not spot or not root or not root:IsA("BasePart") or not guiding() then
		hideAll()
		return
	end
	local f = folder :: Folder
	-- The floor under the podium (the pedestal's base).
	local podium = spot.Parent
	local pedestal = podium and podium:FindFirstChild("Pedestal")
	local floorY = if pedestal and pedestal:IsA("BasePart")
		then pedestal.Position.Y - pedestal.Size.Y / 2 + 0.06
		else spot.Position.Y - 1.5
	local from = Vector3.new(root.Position.X, floorY, root.Position.Z)
	local to = Vector3.new(spot.Position.X, floorY, spot.Position.Z)
	local delta = to - from
	local dist = delta.Magnitude
	local spacing = math.max(1, Config.DailyCrateGuideSpacing)
	local t = os.clock()
	local used = 0
	if dist > Config.DailyCrateGuideNear + 2 then
		local dir = delta.Unit
		local flow = (t * 6) % spacing
		local d = 2.5 + flow
		while d < dist - Config.DailyCrateGuideNear and used < MAX_CHEVRONS do
			used += 1
			local c = chevrons[used]
			if not c then
				c = chevron(f)
				chevrons[used] = c
			end
			c.Parent = f
			local pos = from + dir * d
			c:PivotTo(CFrame.lookAt(pos, pos + dir))
			-- A bright pulse runs down the trail toward the crate; the far end fades out.
			local wave = (math.sin(d * 0.6 - t * 7) + 1) / 2
			local fadeIn = math.clamp((d - 2.5) / 3, 0, 1)
			for _, p in c:GetChildren() do
				if p:IsA("BasePart") then
					p.Transparency = 1 - fadeIn * (0.35 + wave * 0.6)
				end
			end
			d += spacing
		end
	end
	for i = used + 1, #chevrons do
		chevrons[i].Parent = nil
	end
	-- The edge arrow while the podium is off screen.
	local e = edge
	local cam = Workspace.CurrentCamera
	if e and cam then
		local p, onScreen = cam:WorldToViewportPoint(spot.Position + Vector3.new(0, 3, 0))
		if onScreen and p.Z > 0 then
			e.Visible = false
		else
			local view = cam.ViewportSize
			local center = view / 2
			local dv = Vector2.new(p.X, p.Y) - center
			if p.Z < 0 then
				dv = -dv
			end
			if dv.Magnitude < 1 then
				dv = Vector2.new(0, 1)
			end
			local dir = dv.Unit
			local inset = UI.S(80)
			local rx, ry = math.max(center.X - inset, 10), math.max(center.Y - inset, 10)
			local pos = center + Vector2.new(dir.X * rx, dir.Y * ry)
			e.Position = UDim2.fromOffset(pos.X, pos.Y)
			e.Rotation = math.deg(math.atan2(dir.X, -dir.Y))
			e.Visible = true
			local s = e:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = e });
			(s :: UIScale).Scale = 1 + (math.sin(t * 5) + 1) * 0.06
		end
	end
	-- MARLOW's nudge, once per fake day per session.
	if readySince == 0 then
		readySince = t
	end
	local day = Clock.day(ClientState.fakeNow())
	if nudgedDay ~= day and t - readySince >= Config.DailyCrateNudgeSec then
		nudgedDay = day
		if not ClientState.dailyOpenOnArrival then
			ClientState.Juice:Fire(
				"JobsAnnounce",
				{ line = Config.DailyCrateMarlowLine, title = "MARLOW · DAILY CRATE" }
			)
		end
	end
end

function DailyGuide.init()
	local f = Instance.new("Folder")
	f.Name = "DailyGuide"
	f.Parent = Workspace
	folder = f
	buildEdge()
	ClientState.Juice:Connect(function(name: string)
		if name == "HubEnter" then
			readySince = 0
		end
	end)
	RunService.Heartbeat:Connect(function()
		if not guiding() then
			readySince = 0
		end
		step()
	end)
end

return DailyGuide
