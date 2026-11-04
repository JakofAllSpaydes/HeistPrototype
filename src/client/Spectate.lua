--!strict
-- Bled out: the camera rides living teammates (arrows / A / D or the on-screen arrows cycle), their name
-- and HP sit top-center, REVIVE EVERYBODY sits bottom-center. Solo: the camera holds where you fell.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local HUD = require(script.Parent:WaitForChild("HUD"))

local Spectate = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera :: Camera

local active = false
local index = 1
local gui: ScreenGui? = nil
local nameLabel: TextLabel? = nil
local reviveHint: TextLabel? = nil
local windowEndsAt = -1 -- os.clock when the run-over revive window shuts
local angle = 0
local lastCF: CFrame? = nil

local function living(): { Player }
	local out = {}
	for _, p in Players:GetPlayers() do
		if p == player then
			continue
		end
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if hum and root and hum.Health > 0 and not ClientState.downedPlayers[p.UserId] then
			table.insert(out, p)
		end
	end
	table.sort(out, function(a, b)
		return a.UserId < b.UserId
	end)
	return out
end

local function cycle(dir: number)
	index += dir
	local g = gui
	if g then
		local label = g:FindFirstChild("Name", true)
		if label and label:IsA("GuiObject") then
			UI.punch(label, 1.15, 0.2)
		end
	end
	UI.sound(Theme.Sounds.reelTick, 1.2, 0.3)
end

local function build()
	if gui then
		gui:Destroy()
	end
	local S = UI.S
	local g = UI.new("ScreenGui", {
		Name = "Spectate",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 4,
		Parent = playerGui,
	}) :: ScreenGui
	gui = g

	local top = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(104)),
		Size = UDim2.fromOffset(S(420), S(44)),
		Parent = g,
	})
	UI.corner(top, S(12))
	UI.stroke(top, Theme.Colors.grey, S(2))
	UI.text({
		Text = "SPECTATING",
		TextSize = S(10),
		TextColor3 = Theme.Colors.grey,
		Position = UDim2.fromOffset(0, S(2)),
		Size = UDim2.new(1, 0, 0, S(12)),
		Parent = top,
	})
	local label = UI.text({
		Name = "Name",
		Text = "",
		Font = Theme.Fonts.display,
		TextSize = S(20),
		Position = UDim2.fromOffset(0, S(12)),
		Size = UDim2.new(1, 0, 0, S(28)),
		Parent = top,
	})
	nameLabel = label
	for _, side in { -1, 1 } do
		local arrow = UI.button({
			Text = if side < 0 then "◀" else "▶",
			Font = Theme.Fonts.display,
			TextSize = S(20),
			TextColor3 = Theme.Colors.text,
			BackgroundColor3 = Theme.Colors.panel2,
			AnchorPoint = Vector2.new(if side < 0 then 0 else 1, 0.5),
			Position = UDim2.new(if side < 0 then 0 else 1, side * S(6), 0.5, 0),
			Size = UDim2.fromOffset(S(36), S(36)),
			Parent = top,
		})
		UI.corner(arrow, S(8))
		arrow.Activated:Connect(function()
			UI.punch(arrow, 0.9, 0.15)
			cycle(side)
		end)
	end
	UI.text({
		Text = if ClientState.isMobile then "TAP THE ARROWS TO CYCLE" else "A / D OR ARROWS TO CYCLE",
		TextSize = S(11),
		TextColor3 = Theme.Colors.grey,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, S(4)),
		Size = UDim2.fromOffset(S(300), S(14)),
		Parent = top,
	})

	local revive = UI.button({
		Text = "REVIVE EVERYBODY",
		Font = Theme.Fonts.display,
		TextSize = S(22),
		TextColor3 = Theme.Colors.bg,
		BackgroundColor3 = Theme.Colors.gold,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(40)),
		Size = UDim2.fromOffset(S(300), S(60)),
		Parent = g,
	})
	UI.corner(revive, S(14))
	UI.stroke(revive, Theme.Colors.black, S(2), 0.4)
	reviveHint = UI.text({
		Text = "FREE IN THE PROTOTYPE · STANDS THE WHOLE CREW UP",
		TextSize = S(10),
		TextColor3 = Theme.Colors.bg,
		Position = UDim2.new(0, 0, 1, -S(15)),
		Size = UDim2.new(1, 0, 0, S(12)),
		Parent = revive,
	})
	revive.Activated:Connect(function()
		UI.punch(revive, 0.9, 0.2)
		UI.sound(Theme.Sounds.toast, 1.3, 0.5)
		Remotes.ReviveEverybody:FireServer()
	end)
	UI.punch(revive, 1.2, 0.5)
end

local function step(dt: number)
	-- Run over: the button counts down the window in which it still saves the run.
	local hint = reviveHint
	if hint and windowEndsAt >= 0 then
		local left = windowEndsAt - os.clock()
		if left > 0 then
			hint.Text = string.format("%d s TO SAVE THE RUN", math.ceil(left))
			hint.TextColor3 = Theme.Colors.red
		else
			hint.Text = "TOO LATE"
		end
	end
	local list = living()
	local label = nameLabel
	if #list == 0 then
		if label then
			label.Text = "NO ONE LEFT STANDING"
			label.TextColor3 = Theme.Colors.red
		end
		if lastCF then
			camera.CFrame = lastCF
		end
		return
	end
	index = ((index - 1) % #list) + 1
	local target = list[index]
	local char = target.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return
	end
	angle += dt * 0.25
	local pos = root.Position + Vector3.new(math.sin(angle) * 11, 6, math.cos(angle) * 11)
	camera.CFrame = CFrame.lookAt(pos, root.Position + Vector3.new(0, 1.5, 0))
	lastCF = camera.CFrame
	if label then
		label.Text = string.format("%s · %d HP", string.upper(target.Name), math.ceil(hum.Health))
		label.TextColor3 = if hum.Health / math.max(hum.MaxHealth, 1) < 0.3 then Theme.Colors.red else Theme.Colors.text
	end
end

function Spectate.isActive(): boolean
	return active
end

function Spectate.enter()
	if active then
		return
	end
	active = true
	index = 1
	angle = 0
	windowEndsAt = -1
	lastCF = camera.CFrame
	ClientState.spectating = true
	ClientState.cameraMode = "spectate"
	ClientState.setBlock("spectate", true)
	ClientState.setAds(false)
	HUD.setMode("spectate")
	build()
	RunService:BindToRenderStep("GHSSpectate", Enum.RenderPriority.Camera.Value + 1, step)
	HUD.get("toast").show("BLED OUT · SPECTATING", Theme.Colors.red, 1.8)
	UI.sound(Theme.Sounds.deny, 0.6, 0.6)
end

-- Leave spectate. `keepCamera` hands the camera to a sequence instead of the gameplay camera.
function Spectate.exit(keepCamera: boolean?)
	if not active then
		return
	end
	active = false
	ClientState.spectating = false
	ClientState.setBlock("spectate", false)
	pcall(function()
		RunService:UnbindFromRenderStep("GHSSpectate")
	end)
	if gui then
		gui:Destroy()
		gui = nil
	end
	nameLabel = nil
	if not keepCamera then
		ClientState.cameraMode = "gameplay"
		HUD.setMode(HUD.baseMode())
	end
end

function Spectate.init()
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "BledOut" then
			Spectate.enter()
		elseif name == "Revived" then
			Spectate.exit()
		elseif name == "HubEnter" then
			Spectate.exit()
		elseif name == "RunOver" and active then
			windowEndsAt = os.clock() + (tonumber(data.reviveWindowSec) or 0)
			local hint = reviveHint
			if hint then
				UI.punch(hint.Parent :: GuiObject, 1.2, 0.4)
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or not active then
			return
		end
		if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.A then
			cycle(-1)
		elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.D then
			cycle(1)
		end
	end)
	HUD.Rebuilt:Connect(function()
		if active then
			build()
		end
	end)
end

return Spectate
