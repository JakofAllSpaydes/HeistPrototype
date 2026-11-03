--!strict
-- Dummy crew for the run start / end line-ups, so the squad moments are designed for a party of
-- Config.SquadSize even when one person is testing. Default R15 rigs, anchored, mask color and pose like
-- a real player; they exist only during the two sequences.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Squad = {}

export type Dummy = { model: Model, name: string, pose: number, maskColor: string }

local dummies: { Dummy } = {}

local function folder(): Folder
	local existing = Workspace:FindFirstChild("Squad")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = "Squad"
	f.Parent = Workspace
	return f
end

local function rig(name: string): Model?
	local ok, model = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		warn("[GHS Squad] could not build a dummy rig: " .. tostring(model))
		return nil
	end
	model.Name = name
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Player"
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	return model
end

-- `count` dummies at line slots firstIndex.., placed by cframeFor(slot). Returns the new list.
function Squad.spawn(count: number, firstIndex: number, cframeFor: (number) -> CFrame): { Dummy }
	Squad.clear()
	local parent = folder()
	for k = 1, count do
		local i = firstIndex + k - 1
		local name = "DUMMY " .. i
		local model = rig(name)
		if not model then
			continue
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.Anchored = true
		end
		model:PivotTo(cframeFor(i))
		model.Parent = parent
		table.insert(dummies, {
			model = model,
			name = name,
			pose = math.random(#Config.Poses),
			maskColor = Config.MaskColors[((i - 1) % #Config.MaskColors) + 1],
		})
	end
	return dummies
end

function Squad.list(): { Dummy }
	return dummies
end

function Squad.clear()
	for _, d in dummies do
		if d.model.Parent then
			d.model:Destroy()
		end
	end
	dummies = {}
end

return Squad
