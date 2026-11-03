--!strict
-- Billboard tags over dropped guns (name + DMG vs held), beam fade near despawn, crate prompt hiding.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rarity = require(Shared:WaitForChild("Rarity"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type Tag = { gui: BillboardGui, dmgLabel: TextLabel, frame: Frame, beam: Beam?, prompt: ProximityPrompt? }

local GroundLoot = {}

local lootFolder = Workspace:WaitForChild("GroundLoot")
local tags: { [BasePart]: Tag } = {}

local function heldDmg(): number
	local sync = ClientState.sync
	return if sync then sync.held.dmg else 0
end

local function refreshTag(gun: BasePart, tag: Tag)
	local dmg = gun:GetAttribute("Dmg") :: number? or 0
	local held = heldDmg()
	tag.dmgLabel.Text = string.format("DMG %d", dmg)
	tag.dmgLabel.TextColor3 = if dmg > held
		then Theme.Colors.cash
		elseif dmg < held then Theme.Colors.malus
		else Theme.Colors.text
	local sync = ClientState.sync
	local crateId = gun:GetAttribute("CrateId")
	local prompt = tag.prompt
	if prompt then
		if crateId and sync and table.find(sync.cratesTaken, crateId) then
			prompt.Enabled = false
		else
			prompt.Enabled = true
		end
	end
end

local function addTag(gun: BasePart)
	if tags[gun] then
		return
	end
	if gun:GetAttribute("WeaponId") == nil then
		gun:GetAttributeChangedSignal("WeaponId"):Once(function()
			addTag(gun)
		end)
		return
	end
	local S = UI.S
	local rarity = gun:GetAttribute("Rarity") :: number? or 1
	local color = Rarity.color(rarity)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Adornee = gun
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(S(150), S(44))
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	gui.Parent = gun

	local frame = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.15,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	UI.corner(frame, S(8))
	UI.stroke(frame, color, S(2))
	local nameText = string.upper(tostring(gun:GetAttribute("DisplayName") or gun:GetAttribute("WeaponId")))
	UI.text({
		Text = nameText,
		Font = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = color,
		Size = UDim2.new(1, 0, 0, S(22)),
		Parent = frame,
	})
	local dmgLabel = UI.text({
		Text = "DMG",
		TextSize = S(12),
		Position = UDim2.fromOffset(0, S(22)),
		Size = UDim2.new(1, 0, 0, S(18)),
		Parent = frame,
	})
	local tag: Tag = {
		gui = gui,
		dmgLabel = dmgLabel,
		frame = frame,
		beam = gun:FindFirstChild("Beam") :: Beam?,
		prompt = gun:FindFirstChild("Prompt") :: ProximityPrompt?,
	}
	tags[gun] = tag
	refreshTag(gun, tag)
	gun.AttributeChanged:Connect(function()
		if tags[gun] then
			refreshTag(gun, tag)
		end
	end)
end

function GroundLoot.init()
	for _, gun in lootFolder:GetChildren() do
		if gun:IsA("BasePart") then
			addTag(gun)
		end
	end
	lootFolder.ChildAdded:Connect(function(gun)
		if gun:IsA("BasePart") then
			addTag(gun)
		end
	end)
	lootFolder.ChildRemoved:Connect(function(gun)
		if gun:IsA("BasePart") then
			tags[gun] = nil
		end
	end)
	ClientState.Changed:Connect(function()
		for gun, tag in tags do
			if gun.Parent then
				refreshTag(gun, tag)
			end
		end
	end)

	-- Beam fades over the last seconds of lifetime.
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		local now = ClientState.serverNow()
		for gun, tag in tags do
			local beam = tag.beam
			local lifetime = gun:GetAttribute("Lifetime") :: number? or 0
			local spawnedAt = gun:GetAttribute("SpawnedAt") :: number? or now
			if beam and lifetime > 0 then
				local remaining = spawnedAt + lifetime - now
				local fade = Config.GroundWeaponFadeSec
				local alpha = if remaining < fade then math.clamp(1 - remaining / fade, 0, 1) else 0
				beam.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.2 + 0.8 * alpha),
					NumberSequenceKeypoint.new(1, 1),
				})
				tag.frame.BackgroundTransparency = 0.15 + 0.6 * alpha
			end
		end
	end)
end

return GroundLoot
