--!strict
-- Center crosshair with fire kick and a hitmarker that flashes on Hit (gold on headshot, red on kill).
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ClientState = require(Client:WaitForChild("ClientState"))
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))
local Players = game:GetService("Players")

local Crosshair = {}

function Crosshair.build(gui: ScreenGui, track: (RBXScriptConnection) -> ())
	local S = UI.S
	local root = UI.frame({
		Name = "Crosshair",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(S(40), S(40)),
		Parent = gui,
	})
	local HIP_GAP, ADS_GAP = S(5), S(2)
	local HIP_LEN, ADS_LEN = S(9), S(6)
	local gap = HIP_GAP
	local len = HIP_LEN
	local thick = S(2)
	local lines: { Frame } = {}
	local offsets = {
		{ Vector2.new(0, -1), UDim2.fromOffset(thick, len) },
		{ Vector2.new(0, 1), UDim2.fromOffset(thick, len) },
		{ Vector2.new(-1, 0), UDim2.fromOffset(len, thick) },
		{ Vector2.new(1, 0), UDim2.fromOffset(len, thick) },
	}
	for i, o in offsets do
		local dir = o[1] :: Vector2
		local line = UI.frame({
			BackgroundColor3 = Theme.Colors.text,
			AnchorPoint = Vector2.new(0.5 - dir.X * 0.5, 0.5 - dir.Y * 0.5),
			Position = UDim2.new(0.5, dir.X * gap, 0.5, dir.Y * gap),
			Size = o[2] :: UDim2,
			Parent = root,
		})
		UI.stroke(line, Theme.Colors.black, 1, 0.5)
		lines[i] = line
	end
	local dot = UI.frame({
		BackgroundColor3 = Theme.Colors.text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(S(3), S(3)),
		Parent = root,
	})
	UI.corner(dot, S(2))

	-- Round 24n: the optic reticle. Aiming an optic in first person fades the optic's body, so it needs an aim
	-- guide: a red dot for red-dot sights, fine black crosshair lines plus the red dot for scopes.
	local RED = Color3.fromHex("FF2A1A")
	local reticle = UI.frame({
		Name = "OpticReticle",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(S(4), S(4)),
		Visible = false,
		Parent = root,
	})
	local reticleDot = UI.frame({
		BackgroundColor3 = RED,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(S(3), S(3)), -- Round 24r: smaller (was 5)
		ZIndex = 3,
		Parent = reticle,
	})
	UI.corner(reticleDot, S(2))
	UI.stroke(reticleDot, Theme.Colors.black, 1, 0.4)
	local scopeLines: { Frame } = {}
	local RLEN, RGAP, RTHICK = S(160), S(10), math.max(1, S(1.5))
	for _, dir in { Vector2.new(0, -1), Vector2.new(0, 1), Vector2.new(-1, 0), Vector2.new(1, 0) } do
		local vertical = dir.X == 0
		local l = UI.frame({
			BackgroundColor3 = Theme.Colors.black,
			BackgroundTransparency = 0.1,
			AnchorPoint = Vector2.new(
				if dir.X < 0 then 1 elseif dir.X > 0 then 0 else 0.5,
				if dir.Y < 0 then 1 elseif dir.Y > 0 then 0 else 0.5
			),
			Position = UDim2.new(0.5, dir.X * RGAP, 0.5, dir.Y * RGAP),
			Size = if vertical then UDim2.fromOffset(RTHICK, RLEN) else UDim2.fromOffset(RLEN, RTHICK),
			ZIndex = 2,
			Parent = reticle,
		})
		table.insert(scopeLines, l)
	end
	-- Round 24r: the holo's ring round the dot, the ACOG's chevron, and the sniper scope's ring with a dark
	-- (not black) surround outside it (Config.ScopeRingPct / ScopeSurroundAlpha).
	local holoRing = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(S(30), S(30)),
		Visible = false,
		Parent = reticle,
	})
	UI.corner(holoRing, S(15))
	UI.stroke(holoRing, RED, math.max(1, S(1.5)), 0.1)
	local chevron = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(S(24), S(40)),
		Visible = false,
		Parent = reticle,
	})
	local AMBER = Color3.fromHex("FF7A2A")
	for _, side in { -1, 1 } do
		UI.frame({
			BackgroundColor3 = AMBER,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, side * S(4), 0, S(1)),
			Size = UDim2.fromOffset(math.max(1, S(2)), S(11)),
			Rotation = side * -35,
			Parent = chevron,
		})
	end
	UI.frame({
		BackgroundColor3 = Theme.Colors.black,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(12)),
		Size = UDim2.fromOffset(math.max(1, S(1.5)), S(26)),
		Parent = chevron,
	})
	local scopeRing = UI.frame({
		Name = "ScopeRing",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(Config.ScopeRingPct, Config.ScopeRingPct),
		Visible = false,
		ZIndex = 0,
		Parent = gui,
	})
	UI.new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height, Parent = scopeRing })
	UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = scopeRing })
	-- The surround: a stroke far wider than the screen, drawn outward from the circle's edge.
	local surround = UI.new("UIStroke", {
		Color = Color3.new(0, 0, 0),
		Thickness = 4000,
		Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = scopeRing,
	}) :: UIStroke
	local rim = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = scopeRing,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = rim })
	local rimStroke = UI.new("UIStroke", {
		Color = Color3.new(0, 0, 0),
		Thickness = math.max(2, S(5)),
		Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = rim,
	}) :: UIStroke

	local function heldSight(): string?
		local char = Players.LocalPlayer.Character
		local gun = char and char:FindFirstChild("HeldGun")
		local v = gun and gun:GetAttribute("Sight")
		return if typeof(v) == "string" then v else nil
	end

	-- Reload ring: 24 ticks around the crosshair that light up clockwise as the reload progresses.
	local TICKS = 24
	local ringRadius = S(26)
	local ticks: { Frame } = {}
	for i = 1, TICKS do
		local angle = (i - 1) / TICKS * math.pi * 2 - math.pi / 2
		local tick = UI.frame({
			BackgroundColor3 = Theme.Colors.gold,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(angle) * ringRadius, 0.5, math.sin(angle) * ringRadius),
			Size = UDim2.fromOffset(S(3), S(6)),
			Rotation = math.deg(angle) + 90,
			Visible = false,
			Parent = root,
		})
		UI.corner(tick, S(2))
		ticks[i] = tick
	end
	local ringShown = false
	local followingCursor = false
	local aimHidden = false
	track(RunService.Heartbeat:Connect(function()
		-- Round 24l: aiming down sights in first person, the sights are the crosshair: the lines and dot hide
		-- (the hitmarker and the reload ring stay).
		local adsHide = ClientState.firstPerson == true and ClientState.ads and heldSight() ~= "bare" -- Round 24aa: sightless guns keep it
		local sight = if adsHide then heldSight() else nil
		local hide = adsHide or ClientState.sprinting -- brief 11 step 3: no crosshair while sprinting
		local optic = sight == "red" or sight == "holo" or sight == "acog" or sight == "medium" or sight == "scope"
		reticle.Visible = optic
		if optic then
			for _, l in scopeLines do
				l.Visible = sight == "scope" or sight == "medium"
			end
			holoRing.Visible = sight == "holo"
			chevron.Visible = sight == "acog"
			reticleDot.Visible = sight ~= "acog"
		end
		-- The scope surround fades in over the last part of the aim-in.
		local scopeK = if sight == "scope" then math.clamp((ClientState.fpAdsT - 0.6) / 0.4, 0, 1) else 0
		scopeRing.Visible = scopeK > 0
		if scopeK > 0 then
			surround.Transparency = 1 - Config.ScopeSurroundAlpha * scopeK
			rimStroke.Transparency = 1 - 0.85 * scopeK
		end
		if hide ~= aimHidden then
			aimHidden = hide
			for _, line in lines do
				line.Visible = not hide
			end
			dot.Visible = not hide
		end
		-- Cursor unlocked (Ctrl / Alt): the crosshair rides the cursor, since that is where shots go.
		if ClientState.isMouseFree() and not ClientState.blocked() then
			local m = UserInputService:GetMouseLocation()
			root.Position = UDim2.fromOffset(m.X, m.Y)
			followingCursor = true
		elseif followingCursor then
			root.Position = UDim2.fromScale(0.5, 0.5)
			followingCursor = false
		end
		local a = ClientState.ammo
		local progress: number? = nil
		local ringColor = Theme.Colors.gold
		if a.reloading and a.reloadEndsAt > a.reloadStartedAt then
			progress = math.clamp((os.clock() - a.reloadStartedAt) / (a.reloadEndsAt - a.reloadStartedAt), 0, 1)
		elseif ClientState.chargeProgress > 0 then
			-- Round 24v: the plasma charge.
			progress = ClientState.chargeProgress
			ringColor = Color3.fromHex(Config.PlasmaChargeColor)
		elseif ClientState.reviveProgress > 0 then
			-- Holding a revive on a teammate: the same ring fills green.
			progress = ClientState.reviveProgress
			ringColor = Theme.Colors.cash
		end
		if progress then
			ringShown = true
			local lit = math.floor(progress * TICKS + 0.5)
			for i, tick in ticks do
				tick.Visible = true
				tick.BackgroundColor3 = if i <= lit then ringColor else Theme.Colors.panel2
				tick.BackgroundTransparency = if i <= lit then 0 else 0.4
			end
		elseif ringShown then
			-- Reload done: flash full, then hide.
			ringShown = false
			for _, tick in ticks do
				tick.BackgroundColor3 = Theme.Colors.cash
				tick.BackgroundTransparency = 0
				UI.tween(tick, { BackgroundTransparency = 1 }, 0.25)
			end
			UI.punch(root, 1.3, 0.25)
			task.delay(0.26, function()
				if not ringShown then
					for _, tick in ticks do
						tick.Visible = false
						tick.BackgroundTransparency = 0
					end
				end
			end)
		end
	end))

	local marker = UI.frame({
		Name = "Hitmarker",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(S(26), S(26)),
		Visible = false,
		Parent = root,
	})
	local markerLines: { Frame } = {}
	for i = 1, 4 do
		local angle = 45 + (i - 1) * 90
		local l = UI.frame({
			BackgroundColor3 = Theme.Colors.text,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(S(2), S(26)),
			Rotation = angle,
			Parent = marker,
		})
		local cover = UI.frame({
			BackgroundColor3 = Theme.Colors.text,
			Size = UDim2.fromScale(1, 0.35),
			Position = UDim2.fromScale(0, 0.325),
			BackgroundTransparency = 1,
			Parent = l,
		})
		cover.Visible = false
		markerLines[i] = l
	end

	local markerToken = 0
	local function flash(color: Color3)
		markerToken += 1
		local token = markerToken
		for _, l in markerLines do
			l.BackgroundColor3 = color
			l.BackgroundTransparency = 0
		end
		marker.Visible = true
		UI.punch(marker, 1.5, 0.15)
		task.delay(0.12, function()
			if token ~= markerToken then
				return
			end
			for _, l in markerLines do
				UI.tween(l, { BackgroundTransparency = 1 }, 0.12)
			end
			task.delay(0.13, function()
				if token == markerToken then
					marker.Visible = false
				end
			end)
		end)
	end

	local function kick()
		for i, line in lines do
			local dir = offsets[i][1] :: Vector2
			line.Position = UDim2.new(0.5, dir.X * (gap + S(5)), 0.5, dir.Y * (gap + S(5)))
			UI.tween(line, { Position = UDim2.new(0.5, dir.X * gap, 0.5, dir.Y * gap) }, 0.12)
		end
	end

	-- ADS: lines pull in and shorten, dot goes gold.
	local function setAds(on: boolean)
		gap = if on then ADS_GAP else HIP_GAP
		len = if on then ADS_LEN else HIP_LEN
		for i, line in lines do
			local dir = offsets[i][1] :: Vector2
			local size = if dir.X == 0 then UDim2.fromOffset(thick, len) else UDim2.fromOffset(len, thick)
			UI.tween(line, { Position = UDim2.new(0.5, dir.X * gap, 0.5, dir.Y * gap), Size = size }, 0.12)
		end
		UI.tween(dot, { BackgroundColor3 = if on then Theme.Colors.gold else Theme.Colors.text }, 0.12)
	end
	if ClientState.ads then
		setAds(true)
	end

	local component = {}
	component.frame = root

	function component.onJuice(name: string, data: any)
		if name == "LocalFire" then
			kick()
		elseif name == "Ads" then
			setAds(data.on == true)
		elseif name == "Hit" then
			flash(
				if data.killed then Theme.Colors.red elseif data.headshot then Theme.Colors.gold else Theme.Colors.text
			)
		end
	end

	return component
end

return Crosshair
