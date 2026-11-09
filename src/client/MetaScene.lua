--!strict
-- The customization scene, styled to the reference boards: a panel on the right ~58% of the screen with a
-- blue header bar (title, the red X), the Gold pill and a dock (WEAPONS · CLASSES · AVATAR as icon tiles
-- with labels) bottom-left that never hides, and a "customize" mode where the panel goes away and the
-- camera centers on the gun (tabs draw their strips into a full-screen overlay). Movement is locked while
-- the scene is open; selections preview live on the character; nothing is saved until a purchase or equip.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Classes = require(Shared:WaitForChild("Classes"))
local Masks = require(Shared:WaitForChild("Masks"))
local MaskShapes = require(Shared:WaitForChild("MaskShapes"))
local Wraps = require(Shared:WaitForChild("Wraps"))
local GunModels = require(Shared:WaitForChild("GunModels"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local CloseButton = require(script.Parent:WaitForChild("UI"):WaitForChild("CloseButton"))
local HUD = require(script.Parent:WaitForChild("HUD"))
local PurchaseSheet = require(script.Parent:WaitForChild("PurchaseSheet"))
local GamepadNav = require(script.Parent:WaitForChild("GamepadNav"))
local RunStartUI = require(script.Parent:WaitForChild("RunStartUI"))
local Nameplates = require(script.Parent:WaitForChild("Nameplates"))
local SceneIsolation = require(script.Parent:WaitForChild("SceneIsolation"))
local MetaFolder = script.Parent:WaitForChild("Meta")
local GunPreview = require(MetaFolder:WaitForChild("GunPreview"))
local MetaUI = require(MetaFolder:WaitForChild("MetaUI"))

local MetaScene = {}

export type Scene = {
	panel: Frame, -- the tab's content area under the header bar (cleared on every render)
	overlay: Frame, -- full-screen layer for customize-mode strips (cleared on every render)
	title: TextLabel,
	toast: (string, string?) -> (), -- text, kind (celebrate | error | click)
	request: (string, any) -> any, -- Remotes.Meta round trip with the toast + SFX applied
	profile: () -> any,
	sync: () -> any,
	refresh: () -> (), -- rebuild the current tab
	preview: Preview,
	mobile: boolean,
	setCustomize: (boolean) -> (), -- true: panel hidden, camera centered on the gun
}

-- Live preview on the character: wrap color on the grip, mask, class idle. Nothing here is saved.
export type Preview = {
	wrap: (string?) -> (), -- hex color or nil = clear
	mask: (string?, string?, string?) -> (), -- color hex, shape, mask id (nil = the equipped one from the server)
	weapon: (string?) -> (), -- weapon id held in the avatar's hand (nil, or the gun already held = the real one)
	classIdle: (string) -> (),
	reset: () -> (),
	commit: () -> (), -- after an equip landed on the server: forget the old baseline
	emote: (string, number?) -> (), -- play an emote once on the avatar (animation id, hold seconds)
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera :: Camera

local tabs: { [string]: any } = {}
local gui: ScreenGui? = nil
local panelRoot: Frame? = nil
local panelFrame: Frame? = nil
local overlayFrame: Frame? = nil
local titleLabel: TextLabel? = nil
local toastLabel: TextLabel? = nil
local toastToken = 0
local dockTiles: { [string]: TextButton } = {}
local goldLabel: TextLabel? = nil
local currentTab: string? = nil
local open = false
local customize = false
local idleTrack: AnimationTrack? = nil
local emoteTrack: AnimationTrack? = nil -- the Avatar tab's emote preview playing now
local previewMask: BasePart? = nil
local savedHeadColor: Color3? = nil
local savedWrap: GunModels.Snapshot? = nil -- the target gun's worn wrap, while a wrap preview is painted on it
local previewGun: Model? = nil -- GunPreview model in the hand while a different gun than the held one is selected
local previewGunKey: string? = nil -- weapon id | applied wrap the preview was built for
-- Round 19h: CUSTOMIZE shows the gun alone (the avatar hides locally), close and side-on, spinning in as it opens.
local stage: Model? = nil -- the local showcase gun (anchored, parented to the camera)
local stageId: string? = nil
local stageCenter = CFrame.identity -- its bounding-box centre, in root space
local stageSize = Vector3.one
local stageAt = Vector3.zero -- where it floats: in front of the avatar
local stageForward = Vector3.zAxis -- from the gun toward the camera (flat)
local stageT0 = 0
local stageYaw = 0 -- the player's drag spin
local previewWeaponId: string? = nil -- the gun the Weapons tab last previewed (the one CUSTOMIZE shows)

local TABS = { "WEAPONS", "CLASSES", "AVATAR" }
local PANEL_W = 0.58 -- share of the viewport the panel takes (62% on mobile)

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

-- The gun the wrap preview paints (art pass: every Wrap part of it): the preview gun when one is in the hand, else
-- the real held one.
local function wrapTarget(): BasePart?
	local st = stage
	if st and st.PrimaryPart then
		return st.PrimaryPart -- CUSTOMIZE: the showcase gun
	end
	local pg = previewGun
	local root = if pg and pg.Parent then pg.PrimaryPart else nil
	if not root then
		local c = char()
		local held = c and c:FindFirstChild("HeldGun")
		root = if held and held:IsA("BasePart") then held else nil
	end
	return root
end

-- Put the gun back to its worn wrap and forget the baseline (before the target gun changes).
local function restoreWrap()
	if savedWrap then
		GunModels.restore(savedWrap)
	end
	savedWrap = nil
end

local function heldWeaponId(): string?
	local sync = ClientState.sync
	return if sync and sync.held then sync.held.weaponId else nil
end

-- Drop the preview gun and show the real held one again.
local function clearGunPreview()
	if previewGun then
		restoreWrap()
		previewGun:Destroy()
		previewGun = nil
	end
	previewGunKey = nil
	local c = char()
	if c then
		GunPreview.setServerGunHidden(c, false)
	end
end

local preview: Preview = {
	wrap = function(hex: string?)
		local root = wrapTarget()
		if not root then
			return
		end
		if not savedWrap then
			savedWrap = GunModels.snapshot(root)
		end
		if not hex then
			GunModels.restore(savedWrap :: GunModels.Snapshot)
			return
		end
		-- Brief 6: a wrap with its own material (the Legendary pass wraps glow) previews in it.
		local wrapDef: Wraps.Wrap? = nil
		for _, w in Wraps.List do
			if w.color == hex then
				wrapDef = w
				break
			end
		end
		GunModels.paint(
			root,
			Color3.fromHex(hex),
			if wrapDef then Wraps.material(wrapDef) else Enum.Material.SmoothPlastic
		)
	end,
	-- Round 18c: the selected gun in the avatar's hand, like the mask preview. The gun already held needs no copy
	-- (the real model is exact); any other gets a local GunPreview model with the real one hidden.
	weapon = function(id: string?)
		previewWeaponId = id
		local c = char()
		if not Config.MetaWeaponPreview or not id or not c or id == heldWeaponId() then
			clearGunPreview()
			return
		end
		local sync = ClientState.sync
		local weapons = sync and sync.profile and sync.profile.weapons
		local entry = weapons and weapons[id]
		local wrapId: string? = if entry then entry.wrap else nil
		local key = id .. "|" .. tostring(wrapId)
		local pg = previewGun
		if pg and pg.Parent and previewGunKey == key then
			GunPreview.setServerGunHidden(c, true)
			return
		end
		restoreWrap()
		clearGunPreview()
		previewGun = GunPreview.build(c, id, wrapId)
		previewGunKey = if previewGun then key else nil
		GunPreview.setServerGunHidden(c, previewGun ~= nil)
	end,
	-- `hex` / `shape` preview a mask (nil restores the worn one); `id` (brief 6) previews a Masks.lua mask with its
	-- accent through the shared shape builder.
	mask = function(hex: string?, shape: string?, id: string?)
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
			for _, p in MaskShapes.parts(serverMask) do
				p.LocalTransparencyModifier = 0
			end
			return
		end
		head.Color = Color3.fromHex(hex)
		for _, p in MaskShapes.parts(serverMask) do
			p.LocalTransparencyModifier = 1
		end
		local m = if id then Masks.ById[id] else nil
		local spec = if m then m else { color = hex, shape = shape or "none", accent = nil }
		previewMask = MaskShapes.build(head, spec :: any, "PreviewMask", c)
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
	reset = function()
		stopIdle()
		local c = char()
		local head = c and c:FindFirstChild("Head")
		if head and head:IsA("BasePart") and savedHeadColor then
			head.Color = savedHeadColor
		end
		for _, p in MaskShapes.parts(c and c:FindFirstChild("MaskPart")) do
			p.LocalTransparencyModifier = 0
		end
		if previewMask then
			previewMask:Destroy()
			previewMask = nil
		end
		restoreWrap()
		clearGunPreview()
		savedHeadColor = nil
	end,
	emote = function(animationId: string, holdSec: number?)
		-- The idle keeps looping underneath (Action); the emote plays on top one priority higher, so it shows at
		-- full strength, and stops after hold. A new tap cuts the previous preview, or the two blend into mush.
		local prev = emoteTrack
		if prev and prev.IsPlaying then
			prev:Stop(0.1)
		end
		emoteTrack = RunStartUI.playAnim(char(), animationId, holdSec or 2, RunStartUI.EMOTE_PRIORITY)
		UI.sound(Theme.Sounds.toast, 1.2, 0.3)
	end,
	commit = function()
		if previewMask then
			previewMask:Destroy()
			previewMask = nil
		end
		local c = char()
		for _, p in MaskShapes.parts(c and c:FindFirstChild("MaskPart")) do
			p.LocalTransparencyModifier = 0
		end
		savedHeadColor = nil
		savedWrap = nil
	end,
}

------------------------------------------------------------------ Camera
-- Hub shot: the character on the left third, facing the camera, with the panel side free. Customize shot:
-- the gun dead center, close, so the wrap reads.
------------------------------------------------------------------ Customize showcase
local function hideCharacter()
	local c = char()
	if not c then
		return
	end
	for _, d in c:GetDescendants() do
		if (d:IsA("BasePart") or d:IsA("Decal")) and d.LocalTransparencyModifier < 1 then
			d.LocalTransparencyModifier = 1
		end
	end
end

local function clearStage()
	if stage then
		stage:Destroy()
		stage = nil
		savedWrap = nil -- it pointed at the showcase gun
	end
	stageId = nil
end

local function stageWeaponId(): string?
	return previewWeaponId or heldWeaponId()
end

-- The showcase gun for the selected weapon (wearing its wrap): local, anchored, floating in front of the avatar.
local function buildStage()
	clearStage()
	local id = stageWeaponId()
	local c = char()
	local root = c and c:FindFirstChild("HumanoidRootPart")
	if not id or not root or not root:IsA("BasePart") then
		return
	end
	local sync = ClientState.sync
	local weapons = sync and sync.profile and sync.profile.weapons
	local entry = weapons and weapons[id]
	local gun = GunModels.build(id, { wrapId = if entry then entry.wrap else nil })
	local m = Instance.new("Model")
	m.Name = "CustomizeGun"
	gun.Parent = m
	m.PrimaryPart = gun
	for _, p in GunModels.parts(gun) do
		p.Anchored = true
	end
	m.Parent = camera
	local bb, size = m:GetBoundingBox()
	stageCenter = bb -- the root sits at the origin, so this is in root space
	stageSize = size
	local base = root.CFrame
	local flat = Vector3.new(base.LookVector.X, 0, base.LookVector.Z)
	stageForward = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
	stageAt = base.Position + stageForward * Config.MetaGunStageForward + Vector3.new(0, Config.MetaGunStageHeight, 0)
	stageT0 = os.clock()
	stageYaw = 0
	stage = m
	stageId = id
end

-- Side-on and as close as the gun's length allows (MetaGunStagePad of margin), the gun lifted above the strip.
local function stageCamera(): CFrame
	local fov = math.rad(camera.FieldOfView)
	local vp = camera.ViewportSize
	local aspect = if vp.Y > 0 then vp.X / vp.Y else 16 / 9
	local pad = Config.MetaGunStagePad
	local halfV = math.tan(fov / 2)
	local halfH = halfV * aspect
	local length = stageSize.Z
	local height = math.max(stageSize.Y, stageSize.X)
	local dist = math.max(length / 2 * pad / halfH, height / 2 * pad / halfV, Config.MetaGunStageMinDistance)
	local pos = stageAt + stageForward * dist
	return CFrame.lookAt(pos, stageAt - Vector3.yAxis * (dist * halfV * Config.MetaGunStageLift))
end

-- Every frame in CUSTOMIZE: rebuild on a gun change, keep the avatar hidden, spin the gun in, then hold it side-on
-- (muzzle to the left) with a slow bob and whatever the player has dragged it round by.
-- Returns true when it rebuilt (the caller re-frames the camera).
local function updateStage(): boolean
	local rebuilt = false
	if stageWeaponId() ~= stageId then
		buildStage()
		rebuilt = stage ~= nil
	end
	local m = stage
	if not m or not m.PrimaryPart then
		return rebuilt
	end
	hideCharacter()
	local s = math.clamp((os.clock() - stageT0) / Config.MetaGunSpinSec, 0, 1)
	local e = 1 - (1 - s) ^ 3
	local spin = (1 - e) * math.pi * 2 * Config.MetaGunSpinTurns
	local bob = math.sin(os.clock() * 1.6) * Config.MetaGunStageBob
	local rest = CFrame.lookAt(Vector3.zero, stageForward:Cross(Vector3.yAxis))
	local centre = CFrame.new(stageAt + Vector3.new(0, bob, 0)) * CFrame.Angles(0, spin + stageYaw, 0) * rest
	m:PivotTo(centre * stageCenter:Inverse())
	return rebuilt
end

local function shot(push: boolean): CFrame
	local c = char()
	local root = c and c:FindFirstChild("HumanoidRootPart")
	local base = if root and root:IsA("BasePart") then root.CFrame else CFrame.new(0, 3, 150)
	local forward = base.LookVector
	local right = base.RightVector
	if push and stage then
		return stageCamera()
	end
	if push then
		local pg = previewGun
		local gun = if pg and pg.Parent then pg.PrimaryPart else (c and c:FindFirstChild("HeldGun"))
		local target = if gun and gun:IsA("BasePart") then gun.Position else base.Position + right * 1
		local pos = target + forward * Config.MetaWrapZoomDistance + Vector3.new(0, 0.4, 0)
		return CFrame.lookAt(pos, target)
	end
	-- The camera stands in front of the character and off to its right, looking straight ahead (parallel to
	-- the character's facing), so the character lands about a fifth of the way in from the left edge, in
	-- the space beside the panel.
	local d = Config.MetaCameraDistance
	local look = base.Position + Vector3.new(0, 0.3, 0)
	-- The camera looks back at the character, so its screen-right is the character's left: stand off to the
	-- character's LEFT so the avatar reads on the left of the screen, beside the panel.
	local side = right * (-d * Config.MetaCameraSideShare)
	local pos = look + forward * d + side + Vector3.new(0, Config.MetaCameraHeight, 0)
	return CFrame.lookAt(pos, look + side + Vector3.new(0, Config.MetaCameraAim, 0))
end

-- The scene drives the camera itself every frame (bound above the gameplay camera's priority) so nothing
-- else can leave it where it was: it eases from wherever it is to the shot over `sec`.
local camFrom: CFrame? = nil
local camTo: CFrame? = nil
local camT0 = 0
local camSec = 0.4

local function tweenCamera(cf: CFrame, sec: number)
	camFrom = camera.CFrame
	camTo = cf
	camT0 = os.clock()
	camSec = math.max(sec, 0.01)
end

local function stepCamera()
	local to = camTo
	if not to then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local s = math.clamp((os.clock() - camT0) / camSec, 0, 1)
	local k = 1 - (1 - s) * (1 - s)
	local from = camFrom or to
	local cf = from:Lerp(to, k)
	camera.CFrame = cf
	camera.Focus = cf
end

-- Every part of the character visible on this client (first-person zoom hides it locally).
local function showCharacter()
	local c = char()
	if not c then
		return
	end
	for _, d in c:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = 0
		end
	end
end

-- The avatar faces the camera, plus whatever the player has dragged it round by (dragYaw).
local dragYaw = 0
local dragging = false
local dragLastX = 0

local function faceCamera()
	local c = char()
	local root = c and c:FindFirstChild("HumanoidRootPart")
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and hum then
		hum.AutoRotate = false
		local to = camera.CFrame.Position - root.Position
		local flat = Vector3.new(to.X, 0, to.Z)
		if flat.Magnitude > 0.1 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit) * CFrame.Angles(0, dragYaw, 0)
		end
	end
end

-- Drag starts only over the avatar side of the screen: not on the panel (when shown), the dock, the gold
-- pill or the bottom strip area the customize layer uses.
local function overAvatarArea(x: number, y: number): boolean
	local g = gui
	if not g then
		return false
	end
	local function inside(f: GuiObject?): boolean
		if not f or not f.Visible then
			return false
		end
		local p, s = f.AbsolutePosition, f.AbsoluteSize
		return x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y
	end
	if inside(panelRoot) then
		return false
	end
	for _, name in { "Dock", "Gold" } do
		if inside(g:FindFirstChild(name) :: GuiObject?) then
			return false
		end
	end
	local overlay = overlayFrame
	if overlay then
		for _, c in overlay:GetChildren() do
			if c:IsA("GuiObject") and inside(c) then
				return false
			end
		end
	end
	return true
end

-- The hub nameplate over the local character hides while the scene is up (it would sit in the shot).
local function setHubTagVisible(visible: boolean)
	Nameplates.setLocalHidden(not visible)
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

-- Round 25: the actions that get the success burst (true = the bigger one: an unlock).
local JUICY: { [string]: boolean } = {
	upgradeWeapon = false,
	upgradeAbility = false,
	unlockWeapon = true,
	unlockClass = true,
	buyMask = true,
	buyEmote = true,
	buyWrap = true,
}

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
	-- Round 25: upgrades, unlocks and buys burst off the button that did it.
	local juice = JUICY[action]
	if result.ok and juice ~= nil then
		MetaUI.successJuice(juice)
	end
	return result
end

local scene: Scene

local function clear(f: Frame?)
	if not f then
		return
	end
	for _, c in f:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function refreshTab()
	if not currentTab then
		return
	end
	clear(panelFrame)
	clear(overlayFrame)
	local mod = tabs[currentTab]
	if mod then
		mod.render(scene)
	end
end

local function setCustomize(on: boolean)
	if on == customize then
		return
	end
	customize = on
	if panelRoot then
		panelRoot.Visible = not on
	end
	-- Both customize layers own the bottom of the screen (category strip, wraps row): the dock and the gold
	-- pill step out so nothing overlaps. BACK on the strip is the way out; Esc still closes the scene.
	local g = gui
	if g then
		for _, name in { "Dock", "Gold" } do
			local f = g:FindFirstChild(name)
			if f and f:IsA("GuiObject") then
				f.Visible = not on
			end
		end
	end

	-- Round 19h: the gun alone. In: the avatar hides and the showcase gun spins in; out: back to the avatar.
	restoreWrap()
	if on then
		buildStage()
	else
		clearStage()
		showCharacter()
	end
	tweenCamera(shot(on), Config.MetaCameraTweenSec)
end

local function paintDock()
	for tab, tile in dockTiles do
		local on = tab == currentTab
		local stroke = tile:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if on then Theme.Colors.gold else Theme.Colors.black
			stroke.Thickness = UI.S(if on then 3 else 1.5)
		end
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
		titleLabel.Text = string.sub(tab, 1, 1) .. string.lower(string.sub(tab, 2))
	end
	paintDock()
	setCustomize(false)
	refreshTab()
	UI.sound(Theme.Sounds.toast, 1.2, 0.3)
end

-- Icon tile with a label under it (reference dock style). Returns the button.
local function dockTile(
	parent: Instance,
	order: number,
	label: string,
	glyph: string,
	bg: Color3,
	fg: Color3,
	size: number
): TextButton
	local S = UI.S
	local holder = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size + S(16)),
		LayoutOrder = order,
		Parent = parent,
	})
	local b = UI.button({
		Name = label,
		Text = "",
		BackgroundColor3 = bg,
		Size = UDim2.fromOffset(size, size),
		ZIndex = 6,
		Parent = holder,
	})
	UI.corner(b, S(10))
	UI.stroke(b, Theme.Colors.black, S(1.5), 0.3)
	if glyph == "gun" then
		local icon = UI.gunIcon(b, fg, math.floor(size * 0.8))
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.ZIndex = 7
		for _, c in icon:GetChildren() do
			if c:IsA("GuiObject") then
				c.ZIndex = 7
			end
		end
	else
		-- A pictogram (UI/Icons.lua) for the dock's glyph ids (X / CLS / MSK); the glyph is the text fallback.
		-- Cut-outs take the tile's colour; the icon's ZIndex follows the button (7 and up).
		local Icons = require(script.Parent:WaitForChild("UI"):WaitForChild("Icons"))
		local ids = { X = "close", CLS = "classes", MSK = "avatar" } :: { [string]: string }
		local icon = Icons.draw(b, ids[glyph] or glyph, math.floor(size * 0.62), fg, bg, glyph)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
	end
	local l = UI.text({
		Text = label,
		FontFace = Theme.Fonts.display,
		TextSize = S(13),
		TextColor3 = Theme.Colors.text,
		Position = UDim2.fromOffset(0, size + S(1)),
		Size = UDim2.new(1, 0, 0, S(14)),
		ZIndex = 6,
		Parent = holder,
	})
	UI.stroke(l, Theme.Colors.black, S(1.5), 0.3)
	b.MouseEnter:Connect(function()
		UI.punch(b, 1.06, 0.15)
	end)
	return b
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
	dockTiles = {}

	-- Overlay for customize-mode strips (under the dock, over the world).
	overlayFrame = UI.frame({
		Name = "Overlay",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = g,
	})

	-- Panel: right share of the screen, header bar with title and X, content below.
	local panelW = if mobile then 0.62 else PANEL_W
	local root = UI.frame({
		Name = "Panel",
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.04,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -S(14), 0.5, 0),
		Size = UDim2.new(panelW, 0, if mobile then 0.94 else 0.9, 0),
		ClipsDescendants = true,
		Active = true,
		ZIndex = 3,
		Parent = g,
	})
	UI.corner(root, S(12))
	UI.stroke(root, Theme.Colors.black, S(2), 0.3)
	panelRoot = root
	local closeSize = CloseButton.size()
	local headerH = math.max(S(60), closeSize + S(12))
	local header = UI.frame({
		Name = "Header",
		BackgroundColor3 = Theme.Colors.blue,
		Size = UDim2.new(1, 0, 0, headerH),
		ZIndex = 4,
		Parent = root,
	})
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromHex("2B6FB8"), Color3.fromHex("153A66")),
		Rotation = 0,
		Parent = header,
	})
	titleLabel = UI.text({
		Text = "Weapons",
		FontFace = Theme.Fonts.body,
		TextSize = S(28),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(24), 0),
		Size = UDim2.new(1, -S(100), 1, 0),
		ZIndex = 5,
		Parent = header,
	})
	-- The shared red X (UI/CloseButton), vertically centred in the header bar.
	CloseButton.new(header, function()
		MetaScene.close()
	end, { margin = S(14), top = (headerH - closeSize) // 2, z = 5 })
	panelFrame = UI.frame({
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(S(14), headerH + S(10)),
		Size = UDim2.new(1, -S(28), 1, -headerH - S(20)),
		ZIndex = 4,
		Parent = root,
	})
	toastLabel = UI.text({
		Name = "Toast",
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.cash,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(60)),
		Size = UDim2.new(0.6, 0, 0, S(26)),
		Visible = false,
		ZIndex = 30,
		Parent = g,
	})
	UI.stroke(toastLabel :: TextLabel, Theme.Colors.black, S(2), 0.2)

	-- Gold pill and dock, bottom-left (reference layout). The dock never hides.
	local tile = if mobile then S(64) else S(96) -- the dock fills the bottom-left corner (reference box)
	local dock = UI.frame({
		Name = "Dock",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, S(20), 1, -S(16)),
		Size = UDim2.fromOffset(tile * 3 + S(24), tile + S(18)),
		ZIndex = 6,
		Parent = g,
	})
	UI.list(dock, Enum.FillDirection.Horizontal, S(12))
	-- Round 29b: no LEAVE tile in the dock: the header's red X closes (one close control per window).
	local glyphs = { WEAPONS = "gun", CLASSES = "CLS", AVATAR = "MSK" }
	local colors = { WEAPONS = Theme.Colors.blue, CLASSES = Theme.Colors.grey, AVATAR = Theme.Colors.gold }
	local labels = { WEAPONS = "Weapons", CLASSES = "Classes", AVATAR = "Avatar" }
	for i, tab in TABS do
		local b = dockTile(dock, i, labels[tab], glyphs[tab], Theme.Colors.panel, colors[tab], tile)
		b.Activated:Connect(function()
			UI.punch(b, 0.92, 0.15)
			selectTab(tab)
		end)
		dockTiles[tab] = b
	end
	local gold = UI.frame({
		Name = "Gold",
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, S(20), 1, -S(16) - tile - S(30)),
		Size = UDim2.fromOffset(tile * 4 + S(36), S(46)),
		ZIndex = 6,
		Parent = g,
	})
	UI.corner(gold, S(8))
	UI.stroke(gold, Theme.Colors.black, S(1.5), 0.3)
	local bar = UI.frame({
		BackgroundColor3 = Theme.Colors.gold,
		Size = UDim2.fromOffset(S(30), S(15)),
		Position = UDim2.fromOffset(S(12), S(16)),
		Rotation = -8,
		ZIndex = 7,
		Parent = gold,
	})
	UI.corner(bar, S(3))
	local syncNow = ClientState.sync
	local goldNow = if syncNow
			and syncNow.profile
			and typeof(syncNow.profile.gold) == "number"
		then syncNow.profile.gold
		else 0
	goldLabel = UI.text({
		Text = UI.fmtNum(goldNow),
		FontFace = Theme.Fonts.display,
		TextSize = S(26),
		TextColor3 = Theme.Colors.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(50), 0),
		Size = UDim2.new(1, -S(100), 1, 0),
		ZIndex = 7,
		Parent = gold,
	})
	local plus = UI.button({
		Text = "+",
		FontFace = Theme.Fonts.display,
		TextSize = S(22),
		TextColor3 = Theme.Colors.bg,
		BackgroundColor3 = Theme.Colors.cash,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -S(6), 0.5, 0),
		Size = UDim2.fromOffset(S(34), S(34)),
		ZIndex = 7,
		Parent = gold,
	})
	UI.corner(plus, S(6))
	plus.Activated:Connect(function()
		UI.punch(plus, 0.9, 0.15)
		-- Round 28e: + goes to the store's GOLD packs, like the hub and Skill Web pills (the store closes this screen).
		ClientState.Juice:Fire("OpenStore", { tab = "GOLD" })
	end)
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
	-- One premium scene at a time (brief 6): the store closes first.
	ClientState.Juice:Fire("CloseStore", {})
	open = true
	customize = false
	build()
	ClientState.setAds(false)
	ClientState.setBlock("meta", true)
	ClientState.lockMovement("meta", true)
	ClientState.cameraMode = "meta"
	HUD.setMode("meta")
	-- Out of first person (the character would be locally invisible), character shown, then the shot.
	ClientState.Juice:Fire("CameraZoomReset", {})
	showCharacter()
	setHubTagVisible(false)
	SceneIsolation.set(true) -- brief 8: no prompts, nobody else in the shot
	dragYaw = 0
	dragging = false
	faceCamera()
	camera.CameraType = Enum.CameraType.Scriptable
	tweenCamera(shot(false), Config.MetaCameraTweenSec)
	RunService:BindToRenderStep("GHSMetaCamera", Enum.RenderPriority.Camera.Value + 1, function()
		if open then
			faceCamera()
			setHubTagVisible(false) -- the server rebuilds the tag on class changes; keep it off while the scene is up
			-- A preview gun keeps the real one hidden, even when the server rebuilds it (equip, wrap); a respawn drops it.
			local pg = previewGun
			if pg then
				local c = char()
				if pg.Parent and c and pg:IsDescendantOf(c) then
					GunPreview.setServerGunHidden(c, true)
				else
					pg:Destroy()
					previewGun = nil
					previewGunKey = nil
					savedWrap = nil
				end
			end
			if customize and updateStage() then
				tweenCamera(stageCamera(), Config.MetaCameraTweenSec)
			end
			stepCamera()
		end
	end)
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
	customize = false
	dragging = false
	preview.reset()
	clearStage()
	previewWeaponId = nil
	setHubTagVisible(true)
	SceneIsolation.set(false)
	if gui then
		gui:Destroy()
		gui = nil
	end
	panelRoot = nil
	panelFrame = nil
	overlayFrame = nil
	titleLabel = nil
	toastLabel = nil
	pcall(function()
		RunService:UnbindFromRenderStep("GHSMetaCamera")
	end)
	camFrom = nil
	camTo = nil
	ClientState.cameraMode = "gameplay"
	ClientState.requestCameraYaw = 0
	ClientState.setBlock("meta", false)
	ClientState.lockMovement("meta", false)
	HUD.setMode(HUD.baseMode())
	UI.sound(Theme.Sounds.swap, 0.9, 0.4)
end

function MetaScene.init()
	-- Brief 11: on a pad L2 / R2 walk the big categories (WEAPONS / CLASSES / AVATAR), L1 / R1 the small ones in
	-- each (weapon types, classes, avatar categories).
	GamepadNav.register("meta", {
		pages = function(dir: number)
			local i = table.find(TABS, currentTab or TABS[1]) or 1
			selectTab(TABS[(i - 1 + dir) % #TABS + 1])
		end,
		tabs = function(dir: number)
			local mod = currentTab and tabs[currentTab]
			if mod and mod.cycle and scene then
				mod.cycle(scene, dir)
			end
		end,
	})
	tabs = {
		WEAPONS = require(MetaFolder:WaitForChild("WeaponsTab")),
		CLASSES = require(MetaFolder:WaitForChild("ClassesTab")),
		AVATAR = require(MetaFolder:WaitForChild("AvatarTab")),
	}
	scene = {
		panel = nil :: any,
		overlay = nil :: any,
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
		setCustomize = setCustomize,
	}
	setmetatable(scene :: any, {
		__index = function(_, k)
			if k == "panel" then
				return panelFrame
			elseif k == "overlay" then
				return overlayFrame
			elseif k == "title" then
				return titleLabel
			end
			return nil
		end,
	})

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
		elseif name == "RunStartBegin" or name == "Downed" or name == "BledOut" or name == "CloseMeta" then
			MetaScene.close()
		end
	end)
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
		local stamp = ""
		if p then
			local n = 0
			for id, w in p.weapons do
				n += (w.level or 0) * 97 + #id + (if w.wrap then #w.wrap * 7 else 0)
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
			-- Emotes count too, or a bought / equipped emote never re-renders the Avatar tab.
			local em = ""
			if p.emotes then
				local owned = 0
				for id in p.emotes.owned do
					owned += #id
				end
				em = string.format("%d:%s:%s", owned, tostring(p.emotes.squad), tostring(p.emotes.mvp))
			end
			-- Round 25: both starter slots (slot 2 was missing, so equipping into it waited for the next tap).
			stamp = string.format(
				"%d|%d|%d|%d|%d|%s|%s|%s|%s|%s",
				n,
				a,
				m,
				c,
				wr,
				tostring(p.starterWeaponId),
				tostring(p.starterWeaponId2),
				tostring(p.classes.equipped),
				tostring(p.masks.equipped),
				em
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
		if not open then
			return
		end
		local back = (input.KeyCode == Enum.KeyCode.Escape and not gameProcessed)
			or input.KeyCode == Enum.KeyCode.ButtonB
		if back and not PurchaseSheet.isOpen() then
			MetaScene.close()
			return
		end
		-- Drag on the avatar side of the screen turns the avatar round; the UI side is left alone.
		local press = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		if press and not gameProcessed and overAvatarArea(input.Position.X, input.Position.Y) then
			dragging = true
			dragLastX = input.Position.X
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if not open or not dragging then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			local dx = input.Position.X - dragLastX
			dragLastX = input.Position.X
			if customize then
				stageYaw += dx * Config.MetaDragSensitivity -- CUSTOMIZE: the drag turns the gun (Round 24: was reversed)
			else
				dragYaw += dx * Config.MetaDragSensitivity
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)
end

return MetaScene
