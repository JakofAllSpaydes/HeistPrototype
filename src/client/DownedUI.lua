--!strict
-- Downed on the local screen: crawl animation, the bleed bar and SELF-REVIVE (BottomCenter), the revive
-- hold on a downed teammate (F, or the touch button) with the ring on the crosshair, world markers over
-- downed teammates, and the REVIVED BY / REVIVED THE CREW notices.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local HUD = require(script.Parent:WaitForChild("HUD"))

local DownedUI = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

type Mark = { userId: number, name: string, bleedEndsAt: number, gui: BillboardGui?, seconds: TextLabel? }
local marks: { [number]: Mark } = {}
local crawl: AnimationTrack? = nil
local holdingKey = false
local holdingTouch = false
local sentHold = false
local nearbyName: string? = nil
local promptGui: ScreenGui? = nil
local promptLabel: TextLabel? = nil
local touchButton: TextButton? = nil

local function stopCrawl()
	if crawl then
		crawl:Stop(0.2)
		crawl = nil
	end
end

local function playCrawl()
	stopCrawl()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = Config.DownedAnimationId
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		track:Play(0.2)
		crawl = track
	end
end

local function removeMark(userId: number)
	local m = marks[userId]
	if not m then
		return
	end
	marks[userId] = nil
	if m.gui then
		m.gui:Destroy()
	end
end

-- Marker over a downed teammate: red cross, name, bleed seconds, REVIVE. Not shown over yourself.
local function addMark(userId: number, name: string, bleedEndsAt: number)
	removeMark(userId)
	local m: Mark = { userId = userId, name = name, bleedEndsAt = bleedEndsAt, gui = nil, seconds = nil }
	marks[userId] = m
	if userId == player.UserId then
		return
	end
	task.spawn(function()
		local p = Players:GetPlayerByUserId(userId)
		if not p then
			return
		end
		local char = p.Character or p.CharacterAdded:Wait()
		local root = char:WaitForChild("HumanoidRootPart", 5)
		if not root or marks[userId] ~= m then
			return
		end
		local S = UI.S
		local gui = Instance.new("BillboardGui")
		gui.Name = "DownedMarker"
		gui.Adornee = root
		gui.AlwaysOnTop = true
		gui.Size = UDim2.fromOffset(S(150), S(74))
		gui.StudsOffset = Vector3.new(0, 4.5, 0)
		gui.MaxDistance = 500
		gui.LightInfluence = 0
		gui.Parent = playerGui
		local frame = UI.frame({
			BackgroundColor3 = Theme.Colors.panel,
			BackgroundTransparency = 0.15,
			Size = UDim2.fromScale(1, 1),
			Parent = gui,
		})
		UI.corner(frame, S(10))
		UI.stroke(frame, Theme.Colors.red, S(2))
		-- Red cross.
		local cross = UI.frame({
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(S(8), S(8)),
			Size = UDim2.fromOffset(S(26), S(26)),
			Parent = frame,
		})
		UI.frame({
			BackgroundColor3 = Theme.Colors.red,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 0, 0, S(8)),
			Parent = cross,
		})
		UI.frame({
			BackgroundColor3 = Theme.Colors.red,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, S(8), 1, 0),
			Parent = cross,
		})
		UI.text({
			Text = string.upper(name),
			Font = Theme.Fonts.display,
			TextSize = S(16),
			TextColor3 = Theme.Colors.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(S(42), S(6)),
			Size = UDim2.new(1, -S(48), 0, S(20)),
			Parent = frame,
		})
		local seconds = UI.text({
			Text = "",
			Font = Theme.Fonts.display,
			TextSize = S(18),
			TextColor3 = Theme.Colors.red,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(S(42), S(26)),
			Size = UDim2.new(1, -S(48), 0, S(22)),
			Parent = frame,
		})
		local pill = UI.pill(frame, "REVIVE", Theme.Colors.red, Theme.Colors.bg, S(16), S(10))
		pill.AnchorPoint = Vector2.new(0.5, 1)
		pill.Position = UDim2.new(0.5, 0, 1, -S(6))
		m.gui = gui
		m.seconds = seconds
		UI.punch(frame, 1.3, 0.4)
	end)
end

local function clearMarks()
	for userId in table.clone(marks) do
		removeMark(userId)
	end
	ClientState.downedPlayers = {}
end

-- The "HOLD F · REVIVE" prompt (desktop) or the hold button (mobile). Built once, shown when in reach.
local function buildPrompt()
	if promptGui then
		promptGui:Destroy()
	end
	local S = UI.S
	local gui = UI.new("ScreenGui", {
		Name = "RevivePrompt",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 3,
		Parent = playerGui,
	}) :: ScreenGui
	promptGui = gui
	if ClientState.isMobile then
		local button = UI.button({
			Name = "ReviveButton",
			Text = "REVIVE",
			Font = Theme.Fonts.display,
			TextSize = S(20),
			TextColor3 = Theme.Colors.bg,
			BackgroundColor3 = Theme.Colors.cash,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -S(150)),
			Size = UDim2.fromOffset(S(220), S(56)),
			Visible = false,
			Parent = gui,
		})
		UI.corner(button, S(14))
		UI.stroke(button, Theme.Colors.black, S(2), 0.4)
		UI.text({
			Text = "HOLD",
			TextSize = S(10),
			TextColor3 = Theme.Colors.bg,
			Position = UDim2.new(0, 0, 1, -S(14)),
			Size = UDim2.new(1, 0, 0, S(12)),
			Parent = button,
		})
		local function isTouch(input: InputObject): boolean
			return input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
		end
		button.InputBegan:Connect(function(input)
			if isTouch(input) then
				holdingTouch = true
				button.BackgroundColor3 = Theme.Colors.gold
			end
		end)
		button.InputEnded:Connect(function(input)
			if isTouch(input) then
				holdingTouch = false
				button.BackgroundColor3 = Theme.Colors.cash
			end
		end)
		touchButton = button
	else
		local label = UI.text({
			Name = "RevivePromptLabel",
			Text = "HOLD F · REVIVE",
			Font = Theme.Fonts.display,
			TextSize = S(18),
			TextColor3 = Theme.Colors.cash,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, S(64)),
			Size = UDim2.fromOffset(S(320), S(26)),
			Visible = false,
			Parent = gui,
		})
		UI.stroke(label, Theme.Colors.black, S(2), 0.3)
		promptLabel = label
	end
end

local function setPrompt(name: string?)
	if name == nearbyName then
		return
	end
	nearbyName = name
	ClientState.reviveNearby = name ~= nil
	local text = if name then string.format("REVIVE %s", string.upper(name)) else ""
	if touchButton then
		touchButton.Visible = name ~= nil
		touchButton.Text = text
		if name then
			UI.punch(touchButton, 1.15, 0.3)
		end
	end
	if promptLabel then
		promptLabel.Visible = name ~= nil
		promptLabel.Text = if name then "HOLD F · " .. text else ""
		if name then
			UI.punch(promptLabel, 1.2, 0.3)
		end
	end
end

local function sendHold(on: boolean)
	if on == sentHold then
		return
	end
	sentHold = on
	Remotes.ReviveHold:FireServer(on)
	if not on then
		ClientState.reviveProgress = 0
	end
end

local function onDowned(data: any)
	ClientState.downed = true
	ClientState.downedPlayers[player.UserId] = true
	ClientState.setAds(false)
	HUD.setMode("downed")
	local bottom = HUD.get("bottom")
	if bottom then
		bottom.setDowned(tonumber(data.bleedEndsAt) or 0, tonumber(data.selfRevives))
	end
	playCrawl()
	HUD.get("toast").show("DOWNED · CRAWL TO COVER", Theme.Colors.malus, 1.5)
	UI.sound(Theme.Sounds.hurt, 0.7, 0.6)
	ClientState.Juice:Fire("Shake", { amp = 0.4, dur = 0.35 })
	sendHold(false)
end

local function clearLocal()
	if not ClientState.downed then
		return
	end
	ClientState.downed = false
	ClientState.downedPlayers[player.UserId] = nil
	local bottom = HUD.get("bottom")
	if bottom then
		bottom.clearDowned()
	end
	stopCrawl()
	if HUD.mode == "downed" then
		HUD.setMode("gameplay")
	end
end

function DownedUI.init()
	buildPrompt()
	HUD.Rebuilt:Connect(function()
		nearbyName = nil
		buildPrompt()
	end)

	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "Downed" then
			onDowned(data)
		elseif name == "Revived" then
			clearLocal()
			local by = tostring(data.by or "")
			HUD.get("toast")
				.show(if by == "self" then "SELF-REVIVED" else "REVIVED BY " .. string.upper(by), Theme.Colors.cash, 1.5)
			UI.sound(Theme.Sounds.legendary, 1.3, 0.5)
			ClientState.Juice:Fire("RarityFlash", { color = Theme.Colors.cash, alpha = 0.25 })
		elseif name == "BledOut" then
			-- Spectate takes over; the bar and crawl go away.
			ClientState.downed = false
			ClientState.downedPlayers[player.UserId] = nil
			local bottom = HUD.get("bottom")
			if bottom then
				bottom.clearDowned()
			end
			stopCrawl()
		elseif name == "PlayerDowned" then
			local userId = tonumber(data.userId) or 0
			ClientState.downedPlayers[userId] = true
			addMark(userId, tostring(data.name), tonumber(data.bleedEndsAt) or 0)
			if userId ~= player.UserId then
				HUD.get("callSlot")
					.toast(string.format("%s IS DOWN", string.upper(tostring(data.name))), Theme.Colors.red, 1.2)
			end
		elseif name == "PlayerRevived" or name == "PlayerBledOut" then
			local userId = tonumber(data.userId) or 0
			ClientState.downedPlayers[userId] = nil
			removeMark(userId)
			if name == "PlayerRevived" and userId ~= player.UserId then
				local by = tostring(data.by or "")
				HUD.get("callSlot").toast(
					string.format(
						"%s %s",
						string.upper(tostring(data.name)),
						if by == "self" then "SELF-REVIVED" else "REVIVED BY " .. string.upper(by)
					),
					Theme.Colors.cash,
					1.2
				)
			end
		elseif name == "ReviveProgress" then
			local progress = tonumber(data.progress) or 0
			if data.userId == player.UserId then
				local bottom = HUD.get("bottom")
				if bottom then
					bottom.setReviveRing(progress, data.reviver)
				end
			end
			if data.reviverId == player.UserId then
				ClientState.reviveProgress = progress
			end
		elseif name == "CrewRevived" then
			HUD.get("callSlot")
				.toast(string.format("%s REVIVED THE CREW", string.upper(tostring(data.name))), Theme.Colors.gold, 1.8)
			UI.sound(Theme.Sounds.legendary, 1, 0.6)
		elseif name == "StagingEnter" then
			clearLocal()
			clearMarks()
			sendHold(false)
			if HUD.mode ~= "gameplay" and not ClientState.spectating then
				HUD.setMode("gameplay")
			end
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F then
			holdingKey = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.F then
			holdingKey = false
		end
	end)

	-- Bleed seconds on the markers, the nearest downed teammate in reach, and the hold itself.
	RunService.Heartbeat:Connect(function()
		local now = ClientState.serverNow()
		local char = player.Character
		local myRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local nearest: Mark? = nil
		local nearestDist = Config.ReviveRadius
		for userId, m in marks do
			if m.seconds then
				m.seconds.Text = string.format("%ds", math.max(0, math.ceil(m.bleedEndsAt - now)))
			end
			if userId == player.UserId or not myRoot then
				continue
			end
			local p = Players:GetPlayerByUserId(userId)
			local pchar = p and p.Character
			local root = pchar and pchar:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local d = (root.Position - myRoot.Position).Magnitude
				if d <= nearestDist then
					nearestDist = d
					nearest = m
				end
			end
		end
		local canRevive = nearest ~= nil
			and not ClientState.downed
			and not ClientState.spectating
			and HUD.mode == "gameplay"
		setPrompt(if canRevive and nearest then nearest.name else nil)
		local hold = canRevive and (holdingKey or holdingTouch) and not ClientState.blocked()
		sendHold(hold)
	end)
end

return DownedUI
