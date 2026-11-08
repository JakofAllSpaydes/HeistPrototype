--!strict
-- Brief 8 follow-up: while the customization scene (WEAPONS / CLASSES / AVATAR, the gun close-up included) is open,
-- the shot is yours alone: proximity prompts are off and every other character on this client is hidden (other
-- players and their nameplates, the booth mannequins and rigs, the range dummies and any enemy or squad dummy).
-- Local only; everything comes back as it was when the scene closes.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Nameplates = require(script.Parent:WaitForChild("Nameplates"))

local SceneIsolation = {}

local player = Players.LocalPlayer
local on = false
local savedLtm: { [Instance]: number } = {} -- part / decal -> its LocalTransparencyModifier before
local savedGui: { [BillboardGui]: boolean } = {}
local conn: RBXScriptConnection? = nil

local function hideModel(model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			if savedLtm[d] == nil then
				savedLtm[d] = (d :: any).LocalTransparencyModifier
			end
			(d :: any).LocalTransparencyModifier = 1
		elseif d:IsA("BillboardGui") then
			if savedGui[d] == nil then
				savedGui[d] = d.Enabled
			end
			d.Enabled = false
		end
	end
end

-- Everyone but you.
local function others(): { Instance }
	local out = {}
	for _, p in Players:GetPlayers() do
		if p ~= player and p.Character then
			table.insert(out, p.Character)
		end
	end
	for _, name in { "Enemies", "Squad" } do
		local f = Workspace:FindFirstChild(name)
		if f then
			for _, c in f:GetChildren() do
				table.insert(out, c)
			end
		end
	end
	local hub = Workspace:FindFirstChild("Hub")
	if hub then
		for _, d in hub:GetDescendants() do
			if d:IsA("Model") and (d.Name == "BoothMannequin" or d:GetAttribute("BoothTab") ~= nil) then
				table.insert(out, d)
			end
		end
	end
	return out
end

local function sweep()
	for _, m in others() do
		hideModel(m)
	end
end

function SceneIsolation.set(want: boolean)
	if want == on then
		return
	end
	on = want
	ProximityPromptService.Enabled = not want
	Nameplates.setOthersHidden(want)
	if want then
		sweep()
		-- Characters that spawn or respawn while the scene is up are hidden too.
		local acc = 0
		conn = RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc >= 0.5 then
				acc = 0
				sweep()
			end
		end)
		return
	end
	local c = conn
	if c then
		c:Disconnect()
		conn = nil
	end
	for d, v in savedLtm do
		if d.Parent then
			(d :: any).LocalTransparencyModifier = v
		end
	end
	for g, v in savedGui do
		if g.Parent then
			g.Enabled = v
		end
	end
	savedLtm = {}
	savedGui = {}
end

return SceneIsolation
