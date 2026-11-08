--!strict
-- Brief 8: the warehouse booths' mannequins. Each booth's rig (the server tags it with a BoothTab attribute) is
-- shown, on this client only, as a copy of your own character: your mask, your class idle, your starter gun in hand
-- with its wrap, the way the store's mannequin is dressed. Two players each see their own loadout on the same rig.
-- Re-dressed when the character loads and whenever the equipped class, mask, starter gun or wrap changes in the hub.
-- Config.BoothMannequin false leaves the asset's rigs as they are.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Classes = require(Shared:WaitForChild("Classes"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local RunStartUI = require(script.Parent:WaitForChild("RunStartUI"))

local BoothMannequins = {}

local player = Players.LocalPlayer
local copies: { [Model]: Model } = {} -- booth rig -> this client's copy standing in for it
local token = 0

local function rigs(): { Model }
	local out = {}
	local hub = Workspace:FindFirstChild("Hub")
	if not hub then
		return out
	end
	for _, d in hub:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("BoothTab") ~= nil then
			table.insert(out, d)
		end
	end
	return out
end

-- The asset rig disappears locally (the copy stands where it stood).
local function hideRig(rig: Model)
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
		elseif d:IsA("Decal") then
			d.Transparency = 1
		end
	end
end

local function copyCharacter(): Model?
	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then
		return nil
	end
	char.Archivable = true
	local ok, clone = pcall(function()
		return char:Clone()
	end)
	char.Archivable = false
	if not ok or not clone then
		return nil
	end
	local model = clone :: Model
	model.Name = "BoothMannequin"
	for _, d in model:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("BillboardGui") or d:IsA("ForceField") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.LocalTransparencyModifier = 0
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.PlatformStand = false
	end
	return model
end

local function dress()
	token += 1
	for rig, copy in copies do
		copy:Destroy()
		copies[rig] = nil
	end
	if not Config.BoothMannequin then
		return
	end
	local sync = ClientState.sync
	local classId = (sync and sync.classId) or Classes.Default
	for _, rig in rigs() do
		local rigRoot = rig:FindFirstChild("HumanoidRootPart")
		if not rigRoot or not rigRoot:IsA("BasePart") then
			continue
		end
		local copy = copyCharacter()
		if not copy then
			return
		end
		hideRig(rig)
		local hrp = copy:FindFirstChild("HumanoidRootPart") :: BasePart
		hrp.Anchored = true
		copy.PrimaryPart = hrp
		-- Feet on the rig's floor, facing the way the rig faces.
		local box, size = rig:GetBoundingBox()
		local floor = box.Position.Y - size.Y / 2
		local hum = copy:FindFirstChildOfClass("Humanoid")
		local height = if hum then hum.HipHeight + hrp.Size.Y / 2 else 3
		local look = rigRoot.CFrame.LookVector * Vector3.new(1, 0, 1)
		local at = Vector3.new(rigRoot.Position.X, floor + height, rigRoot.Position.Z)
		copy:PivotTo(CFrame.lookAt(at, at + (if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, 1))))
		copy.Parent = rig.Parent
		copies[rig] = copy
		local id = Config.ClassIdleAnimationId[classId] or Config.ClassIdleAnimationId[Classes.Default]
		if id then
			local track = RunStartUI.playAnim(copy, id, nil)
			if track then
				track.Looped = true
				track.Priority = Enum.AnimationPriority.Idle
			end
		end
	end
end

-- Re-dress a moment after a change (the server puts the new mask and gun on the character first).
local function soon()
	token += 1
	local my = token
	task.delay(0.6, function()
		if my == token and ClientState.inHub() then
			dress()
		end
	end)
end

local function loadoutKey(): string
	local sync = ClientState.sync :: any
	if not sync then
		return ""
	end
	local profile = sync.profile
	local held = sync.held
	return table.concat({
		tostring(sync.classId),
		tostring(held and held.weaponId),
		tostring(held and held.wrapColor),
		tostring(profile and profile.masks and profile.masks.equipped),
		tostring(sync.waveState == "Hub"),
	}, "|")
end

function BoothMannequins.init()
	local last = ""
	ClientState.Changed:Connect(function()
		local key = loadoutKey()
		if key ~= last then
			last = key
			soon()
		end
	end)
	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("HumanoidRootPart", 10)
		task.wait(1)
		soon()
	end)
	if player.Character then
		soon()
	end
end

return BoothMannequins
