--!strict
-- The boss bar under the wave bar: name, HP with the number, three phase pips at 100 / 66 / 33, slides in
-- when the cutscene hands the camera back and drops when the boss dies. Also the through-wall marker on
-- the boss (a red Highlight and a name / distance tag on its head) and its stomps.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Client = script.Parent.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))

local BossBar = {}

local BAR_Y = 100
local BAR_H = 34

function BossBar.build(gui: ScreenGui, track: (RBXScriptConnection) -> ())
	local S = UI.S
	local root = UI.frame({
		Name = "BossBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(BAR_Y)),
		Size = UDim2.fromOffset(S(460), S(BAR_H)),
		Visible = false,
		Parent = gui,
	})
	local name = UI.text({
		Text = "TITAN",
		Font = Theme.Fonts.display,
		TextSize = S(15),
		TextColor3 = Theme.Colors.red,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(4), 0),
		Size = UDim2.new(0.5, 0, 0, S(18)),
		Parent = root,
	})
	UI.stroke(name, Theme.Colors.black, S(1.5), 0.3)
	local hpText = UI.text({
		Text = "",
		Font = Theme.Fonts.display,
		TextSize = S(13),
		TextColor3 = Theme.Colors.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(4), 0, S(1)),
		Size = UDim2.new(0.5, 0, 0, S(18)),
		Parent = root,
	})
	UI.stroke(hpText, Theme.Colors.black, S(1.5), 0.3)
	local bar = UI.frame({
		BackgroundColor3 = Theme.Colors.panel2,
		Position = UDim2.fromOffset(0, S(20)),
		Size = UDim2.new(1, 0, 0, S(11)),
		Parent = root,
	})
	UI.corner(bar, S(5))
	UI.stroke(bar, Theme.Colors.black, S(1), 0.4)
	local fill = UI.frame({
		BackgroundColor3 = Theme.Colors.red,
		Size = UDim2.fromScale(1, 1),
		Parent = bar,
	})
	UI.corner(fill, S(5))
	-- Phase pips: diamonds on the bar at 100 / 66 / 33, lit until crossed.
	local pips: { Frame } = {}
	local pipShares = { 1, 0.66, 0.33 }
	for i, share in pipShares do
		local pip = UI.frame({
			BackgroundColor3 = Theme.Colors.gold,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(share, if i == 1 then -S(5) else 0, 0.5, 0),
			Size = UDim2.fromOffset(S(9), S(9)),
			Rotation = 45,
			ZIndex = 3,
			Parent = bar,
		})
		UI.stroke(pip, Theme.Colors.black, S(1), 0.3)
		pips[i] = pip
	end

	local component = {}
	component.frame = root

	local shown = false
	local holdUntil = 0 -- server time before which the bar stays hidden (the cutscene's back beat)
	local pending: any = nil
	local lastPhase = 1
	local marker: BillboardGui? = nil
	local glow: Highlight? = nil
	local markerModel: Model? = nil
	local distLabel: TextLabel? = nil

	local function callSlotOffset(on: boolean)
		local slot = gui:FindFirstChild("CallSlot")
		if slot and slot:IsA("GuiObject") then
			slot.Position = UDim2.new(0.5, 0, 0, S(104 + (if on then BAR_H + 6 else 0)))
		end
	end

	local function bossModel(): Model?
		local enemies = Workspace:FindFirstChild("Enemies")
		if not enemies then
			return nil
		end
		for _, m in enemies:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("Boss") == true and m:FindFirstChildOfClass("Humanoid") then
				return m
			end
		end
		return nil
	end

	local function clearMarker()
		if marker then
			marker:Destroy()
			marker = nil
		end
		if glow then
			glow:Destroy()
			glow = nil
		end
		markerModel = nil
		distLabel = nil
	end

	local function addMarker(model: Model, label: string)
		clearMarker()
		markerModel = model
		local h = Instance.new("Highlight")
		h.Name = "BossGlow"
		h.FillColor = Theme.Colors.red
		h.FillTransparency = 0.85
		h.OutlineColor = Theme.Colors.red
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.Parent = model
		glow = h
		local head = model:FindFirstChild("Head")
		if head then
			local b = Instance.new("BillboardGui")
			b.Name = "BossTag"
			b.Adornee = head
			b.AlwaysOnTop = true
			b.Size = UDim2.fromOffset(S(140), S(34))
			b.StudsOffset = Vector3.new(0, 3.2, 0)
			b.MaxDistance = 600
			b.LightInfluence = 0
			b.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
			local t = UI.text({
				Text = label,
				Font = Theme.Fonts.display,
				TextSize = S(15),
				TextColor3 = Theme.Colors.red,
				Size = UDim2.new(1, 0, 0, S(18)),
				Parent = b,
			})
			UI.stroke(t, Theme.Colors.black, S(1.5), 0.2)
			distLabel = UI.text({
				Text = "",
				Font = Theme.Fonts.display,
				TextSize = S(11),
				TextColor3 = Theme.Colors.text,
				Position = UDim2.fromOffset(0, S(18)),
				Size = UDim2.new(1, 0, 0, S(14)),
				Parent = b,
			})
			UI.stroke(distLabel :: TextLabel, Theme.Colors.black, S(1.5), 0.3)
			marker = b
		end
	end

	local function paint(boss: any)
		local hp = tonumber(boss.hp) or 0
		local maxHP = math.max(1, tonumber(boss.maxHP) or 1)
		local share = math.clamp(hp / maxHP, 0, 1)
		name.Text = tostring(boss.name or "BOSS")
		hpText.Text = string.format("%s / %s", UI.fmtNum(hp), UI.fmtNum(maxHP))
		fill.Size = UDim2.fromScale(share, 1)
		-- Pips at 100 / 66 / 33: a pip stays lit until its phase is reached.
		local phase = tonumber(boss.phase) or 1
		for i, pip in pips do
			pip.BackgroundColor3 = if i == 1 or phase < i then Theme.Colors.gold else Theme.Colors.panel2
		end
		lastPhase = phase
	end

	local function show(boss: any)
		shown = true
		root.Visible = true
		root.Position = UDim2.new(0.5, 0, 0, S(BAR_Y - 30))
		UI.tween(
			root,
			{ Position = UDim2.new(0.5, 0, 0, S(BAR_Y)) },
			0.4,
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out
		)
		UI.punch(root, 1.08, 0.4)
		callSlotOffset(true)
		paint(boss)
		local m = bossModel()
		if m then
			addMarker(m, tostring(boss.name or "BOSS"))
		end
		UI.sound(Theme.Sounds.wave, 0.5, 0.5)
	end

	local function hide(drop: boolean)
		if not shown then
			return
		end
		shown = false
		pending = nil
		clearMarker()
		callSlotOffset(false)
		if drop then
			UI.tween(
				root,
				{ Position = UDim2.new(0.5, 0, 0, S(BAR_Y + 40)) },
				0.45,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			)
			task.delay(0.5, function()
				if not shown then
					root.Visible = false
				end
			end)
		else
			root.Visible = false
		end
	end

	function component.update(sync: any)
		local boss = sync.boss
		if boss then
			if shown then
				paint(boss)
			elseif ClientState.serverNow() >= holdUntil then
				show(boss)
			else
				pending = boss
			end
		elseif shown then
			-- Gone without a BossDown (a clear, the run ending): just drop it.
			hide(true)
		end
	end

	local lastStomp = 0
	track(RunService.Heartbeat:Connect(function()
		if pending and ClientState.serverNow() >= holdUntil then
			local boss = pending
			pending = nil
			show(boss)
		end
		local model = markerModel or (if shown then nil else bossModel())
		if not model or not model.Parent then
			if markerModel then
				clearMarker()
			end
			return
		end
		local root3 = model:FindFirstChild("HumanoidRootPart")
		local char = Players.LocalPlayer.Character
		local myRoot = char and char:FindFirstChild("HumanoidRootPart")
		if root3 and root3:IsA("BasePart") then
			if distLabel and myRoot and myRoot:IsA("BasePart") then
				distLabel.Text = string.format("%dm", math.round((root3.Position - myRoot.Position).Magnitude))
			end
			-- A stomp per step: the floor shakes when it is close.
			local speed = Vector3.new(root3.AssemblyLinearVelocity.X, 0, root3.AssemblyLinearVelocity.Z).Magnitude
			local now = os.clock()
			if speed > 2 and now - lastStomp >= 0.55 then
				lastStomp = now
				local s = Instance.new("Sound")
				s.SoundId = Theme.Sounds.crunch
				s.PlaybackSpeed = 0.35
				s.Volume = 0.8
				s.RollOffMode = Enum.RollOffMode.InverseTapered
				s.RollOffMinDistance = 15
				s.RollOffMaxDistance = 160
				s.Parent = root3
				s:Play()
				s.Ended:Once(function()
					s:Destroy()
				end)
				if myRoot and myRoot:IsA("BasePart") and (root3.Position - myRoot.Position).Magnitude < 45 then
					ClientState.Juice:Fire("Shake", { amp = 0.12, dur = 0.12 })
				end
			end
		end
	end))

	function component.onJuice(juiceName: string, data: any)
		if juiceName == "BossCutscene" then
			local beats = data.beats or Config.BossCutsceneBeats
			holdUntil = (tonumber(data.startedAt) or 0) + (tonumber(beats.back) or 3.4)
		elseif juiceName == "BossPhase" then
			UI.punch(root, 1.12, 0.4)
			local phase = tonumber(data.phase) or 2
			local pip = pips[phase]
			if pip then
				UI.punch(pip, 2.4, 0.5)
				pip.BackgroundColor3 = Theme.Colors.white
				UI.tween(pip, { BackgroundColor3 = Theme.Colors.panel2 }, 0.5, nil, nil, 0.2)
			end
			fill.BackgroundColor3 = Theme.Colors.white
			UI.tween(fill, { BackgroundColor3 = Theme.Colors.red }, 0.5)
			UI.sound(Theme.Sounds.legendary, 0.7, 0.5)
		elseif juiceName == "BossDown" then
			fill.BackgroundColor3 = Theme.Colors.white
			fill.Size = UDim2.fromScale(0, 1)
			hpText.Text = "0"
			UI.punch(root, 1.3, 0.5)
			task.delay(0.6, function()
				hide(true)
			end)
		elseif juiceName == "HubEnter" or juiceName == "RunOver" then
			hide(false)
		end
	end

	return component
end

return BossBar
