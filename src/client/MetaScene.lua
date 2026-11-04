--!strict
-- The customization scene (canvas board "Customization scene — Weapons tab", GDD_7 Main UI Layout).
-- Opened from a dock tile or a station prompt on a tab: the camera tweens to a fixed hub shot with the
-- character on the left third facing the camera, the hub HUD hides, the tab's panel takes the right two
-- thirds, Gold stays top-right with +, SHOP stays left-center, and a dock bottom-left holds LEAVE and the
-- three tabs. Selections preview live on the character; nothing is saved until a purchase or equip.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Classes = require(Shared:WaitForChild("Classes"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local HUD = require(script.Parent:WaitForChild("HUD"))
local RunStartUI = require(script.Parent:WaitForChild("RunStartUI"))
local MetaFolder = script.Parent:WaitForChild("Meta")

local MetaScene = {}

export type Scene = {
	panel: Frame, -- the tab's content area (dark frame, right two thirds)
	title: TextLabel,
	toast: (string, string?) -> (), -- text, kind (celebrate | error | click)
	request: (string, any) -> any, -- Remotes.Meta round trip with the toast + SFX applied
	profile: () -> any,
	sync: () -> any,
	refresh: () -> (), -- rebuild the current tab (after a sync change)
	preview: Preview,
	mobile: boolean,
	pushCamera: (boolean) -> (), -- CUSTOMIZE: push in on the gun (true) or back to the hub shot (false)
	hideHud: (boolean) -> (), -- the scene chrome (dock, gold) hides for the wraps sub-panel
}

-- Live preview on the character: gun body / wrap colors, mask, class idle. Nothing here is saved.
export type Preview = {
	wrap: (string?) -> (), -- hex color or nil = clear
	mask: (string?, string?) -> (), -- color hex, shape (nil = the equipped one from the server)
	classIdle: (string) -> (),
	weapon: (string?) -> (), -- weapon id to show in the hand (recolors the body by rarity Common)
	reset: () -> (),
	commit: () -> (), -- after an equip landed on the server: forget the old baseline so reset keeps the new look
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera :: Camera

local tabs: { [string]: any } = {}
local gui: ScreenGui? = nil
local panelFrame: Frame? = nil
local titleLabel: TextLabel? = nil
local toastLabel: TextLabel? = nil
local toastToken = 0
local chrome: { GuiObject } = {}
local dockTiles: { [string]: TextButton } = {}
local goldLabel: TextLabel? = nil
local currentTab: string? = nil
local open = false
local idleTrack: AnimationTrack? = nil
local previewMask: BasePart? = nil
local savedHeadColor: Color3? = nil
local savedWrapColor: Color3? = nil
local cameraTween: Tween? = nil
local pushed = false

local TABS = { "WEAPONS", "CLASSES", "AVATAR" }

local function char(): Model?
	return player.Character
end

------------------------------------------------------------------ Preview
local function stopIdle()
	if idleTrack then
		idleTrack:Stop(0.2)
		idleTrack = nil
	end
end

local preview: Preview = {
	wrap = function(hex: string?)
		local c = char()
		local grip = c and c:FindFirstChild("HeldGunWrap")
		if grip and grip:IsA("BasePart") then
			if not savedWrapColor then
				savedWrapColor = grip.Color
			end
			grip.Color = if hex then Color3.fromHex(hex) else savedWrapColor :: Color3
			grip.Material = if hex then Enum.Material.SmoothPlastic else Enum.Material.Metal
		end
	end,
	mask = function(hex: string?, shape: string?)
		local c = char()
		local head = c and c:FindFirstChild("Head")
		if not c or not head or not head:IsA("BasePart") then
			return
		end
		if not savedHeadColor then
			savedHeadColor = head.Color
		end
		local serverMask = c:FindFirstChild("MaskPart")
		if previewMask then
			previewMask:Destroy()
			previewMask = nil
		end
		if not hex then
			head.Color = savedHeadColor :: Color3
			if serverMask and serverMask:IsA("BasePart") then
				serverMask.LocalTransparencyModifier = 0
			end
			return
		end
		head.Color = Color3.fromHex(hex)
		if serverMask and serverMask:IsA("BasePart") then
			serverMask.LocalTransparencyModifier = 1
		end
		if shape == "none" or shape == nil then
			return
		end
		local part = Instance.new("Part")
		part.Name = "PreviewMask"
		part.CanCollide = false
		part.CanQuery = false
		part.Massless = true
		part.Color = Color3.fromHex(hex)
		if shape == "visor" then
			part.Size = Vector3.new(1.3, 0.35, 0.3)
			part.Material = Enum.Material.Neon
			part.CFrame = head.CFrame * CFrame.new(0, 0.1, -0.55)
		else
			part.Size = Vector3.new(1.25, 0.5, 1.25)
			part.Material = Enum.Material.Fabric
			part.CFrame = head.CFrame * CFrame.new(0, -0.25, 0)
		end
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = part
		weld.Parent = part
		part.Parent = c
		previewMask = part
	end,
	classIdle = function(classId: string)
		stopIdle()
		local id = Config.ClassIdleAnimationId[classId] or Config.ClassIdleAnimationId[Classes.Default]
		if id then
			idleTrack = RunStartUI.playAnim(char(), id, nil)
			if idleTrack then
				idleTrack.Looped = true
			end
		end
	end,
	weapon = function(_weaponId: string?)
		-- The held visual is one Part; the weapon's identity reads from the detail card. Nothing to swap here.
	end,
	reset = function()
		stopIdle()
		local c = char()
		local head = c and c:FindFirstChild("Head")
		if head and head:IsA("BasePart") and savedHeadColor then
			head.Color = savedHeadColor
		end
		local serverMask = c and c:FindFirstChild("MaskPart")
		if serverMask and serverMask:IsA("BasePart") then
			serverMask.LocalTransparencyModifier = 0
		end
		if previewMask then
			previewMask:Destroy()
			previewMask = nil
		end
		local grip = c and c:FindFirstChild("HeldGunWrap")
		if grip and grip:IsA("BasePart") and savedWrapColor then
			grip.Color = savedWrapColor
		end
		savedHeadColor = nil
		savedWrapColor = nil
	end,
	commit = function()
		if previewMask then
			previewMask:Destroy()
			previewMask = nil
		end
		local c = char()
		local serverMask = c and c:FindFirstChild("MaskPart")
		if serverMask and serverMask:IsA("BasePart") then
			serverMask.LocalTransparencyModifier = 0
		end
		savedHeadColor = nil
		savedWrapColor = nil
	end,
}

------------------------------------------------------------------ Camera
-- Fixed hub shot: the character on the left third, lit, facing the camera. The camera sits in front of
-- the character (south of it, since the hub faces north) and looks slightly past it so the panel side is free.
local function hubShot(push: boolean): CFrame
	local c = char()
	local root = c and c:FindFirstChild("HumanoidRootPart")
	local base = if root and root:IsA("BasePart") then root.CFrame else CFrame.new(0, 3, 150)
	local forward = base.LookVector
	local right = base.RightVector
	if push then
		-- CUSTOMIZE: on the gun in the right hand.
		local gun = c and c:FindFirstChild("HeldGun")
		local target = if gun and gun:IsA("BasePart")
			then gun.Position
			else base.Position + right * 1 + Vector3.new(0, -0.3, 0)
		local pos = target + forward * Config.MetaWrapZoomDistance + right * 1.2 + Vector3.new(0, 0.6, 0)
		return CFrame.lookAt(pos, target)
	end
	local d = Config.MetaCameraDistance
	local look = base.Position + Vector3.new(0, 0.2, 0)
	-- Offset the camera to the character's right so the character lands on the left third of the screen.
	local pos = look + forward * d + right * (d * 0.55) + Vector3.new(0, 1.2, 0)
	return CFrame.lookAt(pos, look + right * (d * 0.45))
end

local function tweenCamera(cf: CFrame, sec: number)
	if cameraTween then
		cameraTween:Cancel()
	end
	cameraTween = TweenService:Create(camera, TweenInfo.new(sec, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = cf,
	})
	cameraTween:Play()
end

local function faceCamera()
	local c = char()
	local root = c and c:FindFirstChild("HumanoidRootPart")
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and hum then
		hum.AutoRotate = false
		-- Turn toward the camera (the shot looks back at the character along its own forward).
		local to = camera.CFrame.Position - root.Position
		local flat = Vector3.new(to.X, 0, to.Z)
		if flat.Magnitude > 0.1 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
		end
	end
end

------------------------------------------------------------------ Scene chrome
local function toast(text: string, kind: string?)
	local label = toastLabel
	if not label then
		return
	end
	toastToken += 1
	local token = toastToken
	local color = if kind == "celebrate"
		then Theme.Colors.cash
		elseif kind == "error" then Theme.Colors.malus
		else Theme.Colors.gold
	label.Text = text
	label.TextColor3 = color
	label.Visible = true
	UI.punch(label, 1.2, 0.3)
	if kind == "celebrate" then
		UI.sound(Theme.Sounds.legendary, 1.2, 0.5)
	elseif kind == "error" then
		UI.sound(Theme.Sounds.deny, 1, 0.4)
	else
		UI.sound(Theme.Sounds.toast, 1.3, 0.35)
	end
	task.delay(1.6, function()
		if token == toastToken and label.Parent then
			label.Visible = false
		end
	end)
end

local function request(action: string, args: any): any
	local ok, result = pcall(function()
		return Remotes.Meta:InvokeServer(action, args)
	end)
	if not ok or typeof(result) ~= "table" then
		toast("SERVER ERROR", "error")
		return { ok = false }
	end
	if result.toast then
		toast(tostring(result.toast), if result.ok then (result.kind or "click") else "error")
	end
	return result
end

local scene: Scene

local function refreshTab()
	local p = panelFrame
	if not p or not currentTab then
		return
	end
	for _, c in p:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local mod = tabs[currentTab]
	if mod then
		mod.render(scene)
	end
end

local function paintDock()
	for tab, tile in dockTiles do
		local on = tab == currentTab
		local stroke = tile:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if on then Theme.Colors.gold else Theme.Colors.grey
		end
		tile.BackgroundColor3 = if on then Theme.Colors.panel2 else Theme.Colors.panel
	end
end

local function selectTab(tab: string)
	if currentTab ~= tab then
		local old = currentTab and tabs[currentTab]
		if old and old.leave then
			old.leave(scene)
		end
	end
	currentTab = tab
	if titleLabel then
		titleLabel.Text = tab
	end
	paintDock()
	scene.pushCamera(false)
	scene.hideHud(false)
	refreshTab()
	UI.sound(Theme.Sounds.toast, 1.2, 0.3)
end

local function build()
	if gui then
		gui:Destroy()
	end
	local S = UI.S
	local mobile = ClientState.isMobile
	local g = UI.new("ScreenGui", {
		Name = "MetaScene",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 8,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui
	gui = g
	chrome = {}
	dockTiles = {}

	-- Panel: the right two thirds (62% on mobile), dark frame, title.
	local panelW = if mobile then 0.62 else 0.64
	local panel = UI.frame({
		Name = "Panel",
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -S(16), 0.5, 0),
		Size = UDim2.new(panelW, 0, if mobile then 0.92 else 0.84, 0),
		Active = true,
		Parent = g,
	})
	UI.corner(panel, S(16))
	UI.stroke(panel, Theme.Colors.gold, S(2))
	titleLabel = UI.text({
		Text = "WEAPONS",
		Font = Theme.Fonts.display,
		TextSize = S(26),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(20), S(10)),
		Size = UDim2.new(1, -S(40), 0, S(32)),
		Parent = panel,
	})
	local content = UI.frame({
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(S(14), S(46)),
		Size = UDim2.new(1, -S(28), 1, -S(46) - S(40)),
		ClipsDescendants = true,
		Parent = panel,
	})
	panelFrame = content
	toastLabel = UI.text({
		Name = "Toast",
		Text = "",
		Font = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.cash,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(8)),
		Size = UDim2.new(1, -S(40), 0, S(26)),
		Visible = false,
		ZIndex = 30,
		Parent = panel,
	})
	UI.stroke(toastLabel :: TextLabel, Theme.Colors.black, S(1.5), 0.3)

	-- Gold, top-right (with +), and SHOP, left-center: the hub chrome stays.
	local gold = UI.frame({
		Name = "Gold",
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(16), 0, S(12)),
		Size = UDim2.fromOffset(S(190), S(36)),
		ZIndex = 5,
		Parent = g,
	})
	UI.corner(gold, S(10))
	UI.stroke(gold, Theme.Colors.gold, S(1.5))
	local bar = UI.frame({
		BackgroundColor3 = Theme.Colors.gold,
		Size = UDim2.fromOffset(S(22), S(11)),
		Position = UDim2.fromOffset(S(10), S(13)),
		Rotation = -8,
		ZIndex = 6,
		Parent = gold,
	})
	UI.corner(bar, S(3))
	goldLabel = UI.text({
		Text = "0",
		Font = Theme.Fonts.display,
		TextSize = S(20),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(40), 0),
		Size = UDim2.new(1, -S(80), 1, 0),
		ZIndex = 6,
		Parent = gold,
	})
	local plus = UI.button({
		Text = "+",
		Font = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.gold,
		BackgroundColor3 = Theme.Colors.panel2,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -S(6), 0.5, 0),
		Size = UDim2.fromOffset(S(24), S(24)),
		ZIndex = 6,
		Parent = gold,
	})
	UI.corner(plus, S(6))
	plus.Activated:Connect(function()
		UI.punch(plus, 0.9, 0.15)
		toast("GOLD · PHASE 4", "click")
	end)
	table.insert(chrome, gold)
	local shop = UI.button({
		Name = "Shop",
		Text = "$",
		Font = Theme.Fonts.display,
		TextSize = S(30),
		TextColor3 = Theme.Colors.amber,
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, S(16), 0.5, -S(40)),
		Size = UDim2.fromOffset(S(56), S(56)),
		ZIndex = 5,
		Parent = g,
	})
	UI.corner(shop, S(10))
	UI.stroke(shop, Theme.Colors.amber, S(2))
	shop.Activated:Connect(function()
		UI.punch(shop, 0.92, 0.15)
		toast("SHOP · PHASE 4", "click")
	end)
	table.insert(chrome, shop)

	-- Dock, bottom-left: LEAVE (red X) and the three tabs.
	local dockTile = if mobile then S(60) else S(76)
	local dock = UI.frame({
		Name = "Dock",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, S(16), 1, -S(16)),
		Size = UDim2.fromOffset(dockTile * 4 + S(30), dockTile),
		ZIndex = 5,
		Parent = g,
	})
	UI.list(dock, Enum.FillDirection.Horizontal, S(10))
	table.insert(chrome, dock)
	local leave = UI.button({
		Name = "Leave",
		Text = "X",
		Font = Theme.Fonts.display,
		TextSize = S(28),
		TextColor3 = Theme.Colors.text,
		BackgroundColor3 = Theme.Colors.red,
		Size = UDim2.fromOffset(dockTile, dockTile),
		LayoutOrder = 0,
		ZIndex = 6,
		Parent = dock,
	})
	UI.corner(leave, S(10))
	UI.stroke(leave, Theme.Colors.black, S(2), 0.4)
	UI.text({
		Text = "LEAVE",
		TextSize = S(9),
		TextColor3 = Theme.Colors.text,
		Position = UDim2.new(0, 0, 1, -S(14)),
		Size = UDim2.new(1, 0, 0, S(12)),
		ZIndex = 7,
		Parent = leave,
	})
	leave.Activated:Connect(function()
		UI.punch(leave, 0.9, 0.15)
		MetaScene.close()
	end)
	local glyphs = { WEAPONS = "GUN", CLASSES = "CLS", AVATAR = "MSK" }
	for i, tab in TABS do
		local tile = UI.button({
			Name = tab,
			Text = "",
			BackgroundColor3 = Theme.Colors.panel,
			Size = UDim2.fromOffset(dockTile, dockTile),
			LayoutOrder = i,
			ZIndex = 6,
			Parent = dock,
		})
		UI.corner(tile, S(10))
		UI.stroke(tile, Theme.Colors.grey, S(2))
		UI.text({
			Text = glyphs[tab],
			Font = Theme.Fonts.display,
			TextSize = S(16),
			TextColor3 = Theme.Colors.gold,
			Position = UDim2.fromOffset(0, S(8)),
			Size = UDim2.new(1, 0, 0, S(24)),
			ZIndex = 7,
			Parent = tile,
		})
		UI.text({
			Text = tab,
			Font = Theme.Fonts.display,
			TextSize = S(10),
			TextColor3 = Theme.Colors.text,
			Position = UDim2.new(0, 0, 1, -S(18)),
			Size = UDim2.new(1, 0, 0, S(14)),
			ZIndex = 7,
			Parent = tile,
		})
		tile.Activated:Connect(function()
			UI.punch(tile, 0.92, 0.15)
			selectTab(tab)
		end)
		dockTiles[tab] = tile
	end
	paintDock()
end

------------------------------------------------------------------ Open / close
function MetaScene.isOpen(): boolean
	return open
end

function MetaScene.open(tab: string?)
	if not ClientState.inHub() or ClientState.downed or ClientState.spectating then
		return
	end
	local t = if tab and tabs[tab] then tab else "WEAPONS"
	if open then
		selectTab(t)
		return
	end
	open = true
	build()
	ClientState.setAds(false)
	ClientState.setBlock("meta", true)
	ClientState.cameraMode = "meta"
	HUD.setMode("meta")
	pushed = false
	faceCamera()
	camera.CameraType = Enum.CameraType.Scriptable
	tweenCamera(hubShot(false), Config.MetaCameraTweenSec)
	local sync = ClientState.sync
	preview.classIdle(if sync then sync.classId else Classes.Default)
	UI.sound(Theme.Sounds.call, 1.2, 0.45)
	selectTab(t)
end

function MetaScene.close()
	if not open then
		return
	end
	open = false
	local old = currentTab and tabs[currentTab]
	if old and old.leave then
		old.leave(scene)
	end
	currentTab = nil
	preview.reset()
	if gui then
		gui:Destroy()
		gui = nil
	end
	panelFrame = nil
	titleLabel = nil
	toastLabel = nil
	if cameraTween then
		cameraTween:Cancel()
		cameraTween = nil
	end
	ClientState.cameraMode = "gameplay"
	ClientState.requestCameraYaw = 0
	ClientState.setBlock("meta", false)
	HUD.setMode(HUD.baseMode())
	UI.sound(Theme.Sounds.swap, 0.9, 0.4)
end

function MetaScene.init()
	tabs = {
		WEAPONS = require(MetaFolder:WaitForChild("WeaponsTab")),
		CLASSES = require(MetaFolder:WaitForChild("ClassesTab")),
		AVATAR = require(MetaFolder:WaitForChild("AvatarTab")),
	}
	scene = {
		panel = nil :: any,
		title = nil :: any,
		toast = toast,
		request = request,
		profile = function()
			local sync = ClientState.sync
			return if sync then sync.profile else nil
		end,
		sync = function()
			return ClientState.sync
		end,
		refresh = refreshTab,
		preview = preview,
		mobile = ClientState.isMobile,
		pushCamera = function(push: boolean)
			if push == pushed then
				return
			end
			pushed = push
			tweenCamera(hubShot(push), Config.MetaCameraTweenSec)
		end,
		hideHud = function(hide: boolean)
			for _, c in chrome do
				c.Visible = not hide
			end
		end,
	}
	-- The scene table hands the live panel to the tab on each render.
	setmetatable(scene :: any, {
		__index = function(_, k)
			if k == "panel" then
				return panelFrame
			elseif k == "title" then
				return titleLabel
			end
			return nil
		end,
	})

	-- Hub HUD dock tiles and station prompts open the scene.
	local function bindDock()
		local hub = HUD.get("hub")
		if hub then
			hub.onDock = function(tab: string)
				MetaScene.open(tab)
			end
		end
	end
	bindDock()
	HUD.Rebuilt:Connect(function()
		bindDock()
		if open then
			local tab = currentTab
			MetaScene.close()
			MetaScene.open(tab)
		end
	end)
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "OpenMeta" then
			MetaScene.open(tostring(data.tab))
		elseif name == "RunStartBegin" or name == "Downed" or name == "BledOut" then
			MetaScene.close()
		end
	end)
	-- Gold and the tab refresh on sync changes (purchases land through the profile in the sync).
	local lastGold = -1
	local lastProfileStamp = ""
	ClientState.Changed:Connect(function(sync: any)
		if not open then
			return
		end
		local p = sync.profile
		local gold = if p and typeof(p.gold) == "number" then p.gold else 0
		if goldLabel and gold ~= lastGold then
			if lastGold >= 0 then
				UI.punch(goldLabel, if gold > lastGold then 1.15 else 0.95, 0.3)
			end
			lastGold = gold
			goldLabel.Text = UI.fmtNum(gold)
		end
		-- A cheap stamp of the parts of the profile the tabs draw from.
		local stamp = ""
		if p then
			local n = 0
			for id, w in p.weapons do
				n += (w.level or 0) * 97 + #id
			end
			local a = 0
			for id, lvl in p.abilities do
				a += lvl * 31 + #id
			end
			local m = 0
			for id in p.masks.owned do
				m += #id
			end
			local c = 0
			for id in p.classes.owned do
				c += #id
			end
			local wr = 0
			for id in p.wraps.owned do
				wr += #id
			end
			stamp = string.format(
				"%d|%d|%d|%d|%d|%s|%s|%s",
				n,
				a,
				m,
				c,
				wr,
				tostring(p.starterWeaponId),
				tostring(p.classes.equipped),
				tostring(p.masks.equipped)
			)
		end
		if stamp ~= lastProfileStamp then
			lastProfileStamp = stamp
			local mod = currentTab and tabs[currentTab]
			if mod and mod.onProfile then
				mod.onProfile(scene)
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or not open then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			MetaScene.close()
		end
	end)
	-- Keep the character facing the camera while the scene is open (the gameplay camera is off).
	RunService.RenderStepped:Connect(function()
		if open then
			faceCamera()
		end
	end)
end

return MetaScene
