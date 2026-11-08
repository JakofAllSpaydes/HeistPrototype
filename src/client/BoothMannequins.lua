--!strict
-- The warehouse booth keepers' name tags. Round 25: the booths are run by three named R15 NPCs the server builds
-- (Hub.lua buildBoothNpc, Config.BoothNpcs; they replaced brief 8's copies of your own character). Each gets a
-- small tag over its head in the house style (the name in the display face, the role under it) that shows only
-- right by the stall (Config.BoothNpcTagFadeNear..Far, fading) and hides while any menu is open (weapons, classes, customize,
-- the shop: ClientState.blocked()).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local BoothMannequins = {}

local player = Players.LocalPlayer
-- Each faded piece with its own full-opacity transparency (the fade scales from there).
type Fade = { obj: Instance, prop: string, base: number }
type Tag = { gui: BillboardGui, fades: { Fade }, head: BasePart, alpha: number }
local tags: { [Model]: Tag } = {}
local pending: { [Model]: boolean } = {}

local function addTag(npc: Model)
	if tags[npc] or pending[npc] then
		return
	end
	pending[npc] = true
	local head = npc:WaitForChild("Head", 10) :: BasePart?
	pending[npc] = nil
	if not head or not npc.Parent or tags[npc] then
		return
	end
	local S = UI.S
	local gui = Instance.new("BillboardGui")
	gui.Name = "KeeperTag"
	gui.Adornee = head
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(S(260), S(64))
	gui.StudsOffset = Vector3.new(0, Config.BoothNpcTagOffset, 0)
	-- Round 25: no MaxDistance cut-off (it measured from the camera and blinked at the edge) and no CanvasGroup or
	-- Enabled toggling at the range edge (both flashed): every piece's own transparency fades with the
	-- character's distance (BoothNpcTagFadeNear..Far). Enabled only follows the menus.
	gui.MaxDistance = 10000
	gui.ResetOnSpawn = false
	local plate = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.15,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, S(58)),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = gui,
	})
	UI.corner(plate, S(3))
	UI.stroke(plate, Theme.Colors.gold, S(1), 0.5)
	UI.pad(plate, S(16), 0, S(16), 0)
	UI.list(plate, Enum.FillDirection.Vertical, 0, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	UI.text({
		Text = string.upper(tostring(npc:GetAttribute("BoothNpc") or "")),
		FontFace = Theme.Fonts.display,
		TextSize = S(28),
		TextColor3 = Theme.Colors.white,
		Size = UDim2.fromOffset(0, S(30)),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
		Parent = plate,
	})
	UI.text({
		Text = string.upper(tostring(npc:GetAttribute("BoothRole") or "")),
		FontFace = Theme.Fonts.display,
		TextSize = S(16),
		TextColor3 = Theme.Colors.gold,
		Size = UDim2.fromOffset(0, S(19)),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = plate,
	})
	local fades: { Fade } = {}
	for _, d in gui:GetDescendants() do
		if d:IsA("TextLabel") then
			table.insert(fades, { obj = d, prop = "TextTransparency", base = d.TextTransparency })
		elseif d:IsA("Frame") then
			table.insert(fades, { obj = d, prop = "BackgroundTransparency", base = d.BackgroundTransparency })
		elseif d:IsA("UIStroke") then
			table.insert(fades, { obj = d, prop = "Transparency", base = d.Transparency })
		end
	end
	for _, f in fades do
		(f.obj :: any)[f.prop] = 1
	end
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	tags[npc] = { gui = gui, fades = fades, head = head, alpha = 0 }
	npc.AncestryChanged:Connect(function()
		if not npc:IsDescendantOf(Workspace) then
			gui:Destroy()
			tags[npc] = nil
		end
	end)
end

function BoothMannequins.init()
	-- Round 25: every keeper the server tags GHSKeeper (the three booth NPCs and MARLOW at the job board).
	local function try(inst: Instance)
		if inst:IsA("Model") then
			task.spawn(addTag, inst)
		end
	end
	for _, inst in CollectionService:GetTagged("GHSKeeper") do
		try(inst)
	end
	CollectionService:GetInstanceAddedSignal("GHSKeeper"):Connect(try)
	-- Fades with your distance; hidden while a menu is open (and in a run, where the hub is far away anyway).
	RunService.RenderStepped:Connect(function()
		local show = not ClientState.blocked() and ClientState.inHub()
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local near, far = Config.BoothNpcTagFadeNear, Config.BoothNpcTagFadeFar
		for _, t in tags do
			if t.gui.Enabled ~= show then
				t.gui.Enabled = show
			end
			local alpha = 0
			if root then
				local d = (t.head.Position - root.Position).Magnitude
				alpha = 1 - math.clamp((d - near) / math.max(far - near, 0.1), 0, 1)
			end
			-- Smoothed, and only written when it moves, so nothing re-renders while you stand still.
			local a = t.alpha + (alpha - t.alpha) * 0.25
			if math.abs(a - alpha) < 0.005 then
				a = alpha
			end
			if a ~= t.alpha then
				t.alpha = a
				for _, f in t.fades do
					(f.obj :: any)[f.prop] = 1 - (1 - f.base) * a
				end
			end
		end
	end)
end

return BoothMannequins
