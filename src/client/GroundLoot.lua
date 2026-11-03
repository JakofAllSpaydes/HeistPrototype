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

type Tag = {
	gui: BillboardGui,
	dmgLabel: TextLabel,
	timerLabel: TextLabel,
	frame: Frame,
	beam: Beam?,
	prompt: ProximityPrompt?,
}

local GroundLoot = {}

local lootFolder = Workspace:WaitForChild("GroundLoot")
local tags: { [BasePart]: Tag } = {}

local function heldDps(): number
	local sync = ClientState.sync
	return if sync then (sync.held.dps or 0) else 0
end

-- DMG per shot and DPS; the color compares DPS against the held gun so slow heavy guns don't always win.
local function refreshTag(gun: BasePart, tag: Tag)
	local dmg = gun:GetAttribute("Dmg") :: number? or 0
	local dps = gun:GetAttribute("Dps") :: number? or 0
	local held = heldDps()
	tag.dmgLabel.Text = string.format("DMG %d  ·  DPS %d", dmg, dps)
	tag.dmgLabel.TextColor3 = if dps > held
		then Theme.Colors.cash
		elseif dps < held then Theme.Colors.malus
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
	local rarity = gun:GetAttribute("Rarity") :: number? or 1
	local color = Rarity.color(rarity)
	-- Sized in studs so the tag grows as you walk up to it. Timer sits above the box.
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Adornee = gun
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromScale(5.5, 3)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.4, 0)
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	gui.Parent = gun

	local timerLabel = UI.text({
		Text = "",
		Font = Theme.Fonts.display,
		TextScaled = true,
		TextColor3 = Theme.Colors.grey,
		Size = UDim2.fromScale(1, 0.36),
		Parent = gui,
	})
	UI.stroke(timerLabel, Theme.Colors.black, 2, 0.3)
	local frame = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.15,
		Position = UDim2.fromScale(0, 0.4),
		Size = UDim2.fromScale(1, 0.6),
		Parent = gui,
	})
	UI.new("UICorner", { CornerRadius = UDim.new(0.15, 0), Parent = frame })
	UI.stroke(frame, color, 2)
	local nameText = string.upper(tostring(gun:GetAttribute("DisplayName") or gun:GetAttribute("WeaponId")))
	UI.text({
		Text = nameText,
		Font = Theme.Fonts.display,
		TextScaled = true,
		TextColor3 = color,
		Position = UDim2.fromScale(0.05, 0.06),
		Size = UDim2.fromScale(0.9, 0.5),
		Parent = frame,
	})
	local dmgLabel = UI.text({
		Text = "DMG",
		TextScaled = true,
		Position = UDim2.fromScale(0.05, 0.56),
		Size = UDim2.fromScale(0.9, 0.36),
		Parent = frame,
	})
	local tag: Tag = {
		gui = gui,
		dmgLabel = dmgLabel,
		timerLabel = timerLabel,
		frame = frame,
		beam = gun:FindFirstChild("Beam") :: Beam?,
		prompt = gun:FindFirstChild("Prompt") :: ProximityPrompt?,
	}
	tags[gun] = tag
	refreshTag(gun, tag)
	UI.punch(frame, 1.35, 0.4)
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
			if lifetime > 0 then
				local remaining = math.max(0, spawnedAt + lifetime - now)
				local fade = Config.GroundWeaponFadeSec
				local alpha = if remaining < fade then math.clamp(1 - remaining / fade, 0, 1) else 0
				if beam then
					beam.Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.2 + 0.8 * alpha),
						NumberSequenceKeypoint.new(1, 1),
					})
				end
				tag.frame.BackgroundTransparency = 0.15 + 0.4 * alpha
				tag.timerLabel.Text = string.format("%ds", math.ceil(remaining))
				tag.timerLabel.TextColor3 = if remaining < fade then Theme.Colors.malus else Theme.Colors.text
			else
				tag.timerLabel.Text = ""
			end
		end
	end)
end

return GroundLoot
