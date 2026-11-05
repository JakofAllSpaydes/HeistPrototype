--!strict
-- Tags over teammates' heads: what they are busy with right now (LOCKPICK / HACKING / CAPTURING), from the
-- server's PlayerBusy events (Minigames, CrewCall). Never shown over yourself: your own panel or the circle
-- already says it. One small blue pill, Config.BusyTagOffset above the head.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local PlayerTags = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local tags: { [number]: BillboardGui } = {}

local function remove(userId: number)
	local gui = tags[userId]
	if not gui then
		return
	end
	tags[userId] = nil
	local pill = gui:FindFirstChild("Pill")
	if pill and pill:IsA("GuiObject") then
		UI.tween(pill, { BackgroundTransparency = 1 }, 0.2)
		for _, d in pill:GetDescendants() do
			if d:IsA("TextLabel") then
				UI.tween(d, { TextTransparency = 1 }, 0.2)
			end
		end
	end
	task.delay(0.25, function()
		gui:Destroy()
	end)
end

local function show(userId: number, label: string)
	remove(userId)
	if userId == player.UserId then
		return
	end
	local p = Players:GetPlayerByUserId(userId)
	local char = p and p.Character
	local head = char and char:FindFirstChild("Head")
	if not head then
		return
	end
	local S = UI.S
	local gui = Instance.new("BillboardGui")
	gui.Name = "BusyTag"
	gui.Adornee = head
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(S(140), S(26))
	gui.StudsOffset = Vector3.new(0, Config.BusyTagOffset, 0)
	gui.MaxDistance = 400
	gui.LightInfluence = 0
	gui.Parent = playerGui
	local pill = UI.pill(gui, label, Theme.Colors.blue, Theme.Colors.bg, S(22), S(13))
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromScale(0.5, 0.5)
	UI.stroke(pill, Theme.Colors.black, S(1.5), 0.4)
	UI.punch(pill, 1.3, 0.35)
	tags[userId] = gui
end

local function clear()
	for userId in table.clone(tags) do
		remove(userId)
	end
end

function PlayerTags.init()
	ClientState.Juice:Connect(function(name: string, data: any)
		if name == "PlayerBusy" then
			local userId = tonumber(data.userId) or 0
			if data.on == true then
				show(userId, tostring(data.label or "BUSY"))
			else
				remove(userId)
			end
		elseif name == "PlayerDowned" or name == "PlayerBledOut" then
			remove(tonumber(data.userId) or 0)
		elseif name == "HubEnter" or name == "RunOver" then
			clear()
		end
	end)
	-- A character that goes away takes its tag with it.
	local function watch(p: Player)
		p.CharacterRemoving:Connect(function()
			remove(p.UserId)
		end)
	end
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(p)
		remove(p.UserId)
	end)
end

return PlayerTags
