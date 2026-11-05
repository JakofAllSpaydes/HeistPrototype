--!strict
-- The boss cutscene (Config.BossCutsceneBeats, off the server clock in BossCutscene): MARLOW's call in
-- the crew-call slot and a low shot of the entrance wall; the wall blows (flash, shake) and the boss steps
-- through; the camera pushes in on the gun while the name card slams in bottom-third; the camera snaps
-- back to the player (the bar slides in on its own) and the wave starts. Input locked throughout.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local HUD = require(script.Parent:WaitForChild("HUD"))

local BossCutscene = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera :: Camera

local data: any = nil
local fired: { [string]: boolean } = {}
local gui: ScreenGui? = nil
local gunCF: CFrame? = nil

local function once(beat: string, fn: () -> ())
	if not fired[beat] then
		fired[beat] = true
		fn()
	end
end

local function bossModel(): Model?
	local enemies = Workspace:FindFirstChild("Enemies")
	if not enemies then
		return nil
	end
	for _, m in enemies:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("Boss") == true then
			return m
		end
	end
	return nil
end

local function finish()
	if not data then
		return
	end
	data = nil
	pcall(function()
		RunService:UnbindFromRenderStep("GHSBossCutscene")
	end)
	if gui then
		gui:Destroy()
		gui = nil
	end
	ClientState.cameraMode = "gameplay"
	ClientState.setBlock("cinematic", false)
	HUD.setMode(HUD.baseMode())
end

local function nameCard(d: any)
	local g = gui
	if not g then
		return
	end
	local S = UI.S
	local card = UI.frame({
		Name = "NameCard",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.7, 0),
		Size = UDim2.fromOffset(S(600), S(130)),
		ZIndex = 5,
		Parent = g,
	})
	local name = UI.text({
		Text = string.upper(tostring(d.name or "BOSS")),
		Font = Theme.Fonts.display,
		TextSize = S(92),
		TextColor3 = Theme.Colors.red,
		Size = UDim2.new(1, 0, 0, S(96)),
		Rotation = -4,
		ZIndex = 6,
		Parent = card,
	})
	UI.stroke(name, Theme.Colors.black, S(4), 0.1)
	local sub = UI.text({
		Text = "· " .. string.upper(tostring(d.subtitle or "")) .. " ·",
		Font = Theme.Fonts.display,
		TextSize = S(22),
		TextColor3 = Theme.Colors.text,
		Position = UDim2.fromOffset(0, S(98)),
		Size = UDim2.new(1, 0, 0, S(28)),
		ZIndex = 6,
		Parent = card,
	})
	UI.stroke(sub, Theme.Colors.black, S(2), 0.2)
	UI.punch(card, 2.6, 0.5)
	ClientState.Juice:Fire("RarityFlash", { color = Theme.Colors.red, alpha = 0.35 })
	ClientState.Juice:Fire("Shake", { amp = 0.5, dur = 0.4 })
	UI.sound(Theme.Sounds.legendary, 0.6, 0.8)
	UI.sound(Theme.Sounds.wave, 0.4, 0.7)
end

local function step(dt: number)
	local d = data
	if not d then
		return
	end
	local t = ClientState.serverNow() - d.startedAt
	local beats = d.beats
	local wall: Vector3 = d.wallPoint
	local marker: Vector3 = d.marker
	local toCenter = -Vector3.new(wall.X, 0, wall.Z)
	toCenter = if toCenter.Magnitude > 0.1 then toCenter.Unit else Vector3.zAxis
	if t >= beats.blow then
		once("blow", function()
			ClientState.Juice:Fire("RarityFlash", { color = Theme.Colors.white, alpha = 0.6 })
			ClientState.Juice:Fire("Shake", { amp = 0.9, dur = 0.5 })
			UI.sound(Theme.Sounds.crate, 0.45, 0.9)
			UI.sound(Theme.Sounds.crunch, 0.5, 0.8)
		end)
	end
	local cf: CFrame
	if t < beats.gun then
		-- Low shot of the entrance wall from inside the arena, rising a little as the boss steps through.
		local rise = math.clamp((t - beats.blow) / 1.2, 0, 1)
		local eye = marker + toCenter * 20 + Vector3.new(0, 2.2 + rise * 2, 0)
		cf = CFrame.lookAt(eye, wall + Vector3.new(0, 4 + rise * 1.5, 0))
		gunCF = nil
	elseif t < beats.back then
		once("gun", function()
			nameCard(d)
		end)
		-- Push in on the gun.
		local boss = bossModel()
		local root = boss and boss:FindFirstChild("HumanoidRootPart")
		local gun = boss and boss:FindFirstChild("Gun")
		if root and root:IsA("BasePart") then
			local look = if gun and gun:IsA("BasePart") then gun.Position else root.Position
			local want = CFrame.lookAt(
				root.Position + root.CFrame.RightVector * 9 + root.CFrame.LookVector * 10 + Vector3.new(0, 3, 0),
				look
			)
			local prev = gunCF
			gunCF = if prev then prev:Lerp(want, math.min(1, dt * 6)) else want
			cf = gunCF :: CFrame
		else
			cf = CFrame.lookAt(marker + toCenter * 14 + Vector3.new(0, 4, 0), marker + Vector3.new(0, 4, 0))
		end
	else
		finish()
		return
	end
	camera.CFrame = cf
	camera.Focus = cf
end

local function begin(d: any)
	finish()
	data = d
	fired = {}
	gunCF = nil
	ClientState.setAds(false)
	ClientState.cameraMode = "cinematic"
	ClientState.setBlock("cinematic", true)
	HUD.setMode("boss")
	gui = UI.new("ScreenGui", {
		Name = "BossCutscene",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 12,
		Parent = playerGui,
	}) :: ScreenGui
	-- MARLOW's call in the crew-call slot.
	ClientState.Juice:Fire("CrewLine", {
		crewLead = d.crewLead,
		typeLabel = d.typeLabel,
		text = d.text,
		kind = d.kind or "door",
	})
	RunService:BindToRenderStep("GHSBossCutscene", Enum.RenderPriority.Camera.Value + 1, step)
	UI.sound(Theme.Sounds.call, 0.8, 0.6)
end

function BossCutscene.init()
	ClientState.Juice:Connect(function(name: string, d: any)
		if name == "BossCutscene" then
			begin(d)
		elseif name == "HubEnter" or name == "RunOver" then
			finish()
		end
	end)
	local _ = Config
end

return BossCutscene
