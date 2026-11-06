--!strict
-- Billboard tags over dropped guns (name, DMG per shot and RATE each with a ▲ / ▼ vs held), beam fade near
-- despawn, crate prompt hiding.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Weapons = require(Shared:WaitForChild("Weapons"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

type Tag = {
	gui: BillboardGui,
	dmgLabel: TextLabel,
	rateLabel: TextLabel,
	timerLabel: TextLabel,
	frame: Frame,
	beam: Beam?,
	prompt: ProximityPrompt?,
}

local GroundLoot = {}

local lootFolder = Workspace:WaitForChild("GroundLoot")
local tags: { [BasePart]: Tag } = {}

-- Two rows against the held gun: damage per shot ("33x8" for pellets) and fire rate, each with its own
-- arrow, so a slow heavy gun and a fast light one read as a trade instead of one number.
local function refreshTag(gun: BasePart, tag: Tag)
	local weaponId = tostring(gun:GetAttribute("WeaponId"))
	local w = Weapons.ById[weaponId]
	local pellets = if w then w.pellets else 1
	-- Round 16: the tag shows the gun as YOU would hold it (your Armory level for this weapon, your damage
	-- upgrades), whoever dropped it; the held gun's upgrade / stim rate multiplier goes on top.
	local dmg, levelMult = ClientState.gunAsMine(weaponId, tonumber(gun:GetAttribute("Rarity")) or 1)
	local rate = if w then Weapons.effectiveRate(w, ClientState.rateMult() * levelMult) else 0
	local sync = ClientState.sync
	local held = sync and sync.held
	-- Compare at display precision (the tag's Dmg is rounded, the held one is not) so equal reads as equal.
	local heldShot = if held then math.round(held.dmg) * held.pellets else 0
	local heldRate = if held then math.round((held.displayRate or held.fireRate) * 10) / 10 else 0
	local dmgArrow, dmgColor = UI.arrow(math.round(dmg) * pellets, heldShot)
	local rateArrow, rateColor = UI.arrow(math.round(rate * 10) / 10, heldRate)
	tag.dmgLabel.Text = "DMG " .. UI.fmtDmg(dmg, pellets) .. dmgArrow
	tag.dmgLabel.TextColor3 = dmgColor
	tag.rateLabel.Text = "RATE " .. UI.fmtRate(rate) .. rateArrow
	tag.rateLabel.TextColor3 = rateColor
	local prompt = tag.prompt
	if prompt then
		-- A downed teammate in reach owns F: gun prompts step aside until they are up.
		prompt.Enabled = not ClientState.reviveNearby and gun:GetAttribute("Landing") ~= true
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
	gui.Size = UDim2.fromScale(5.5, 3.6)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.7, 0)
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	gui.Parent = gun

	local timerLabel = UI.text({
		Text = "",
		Font = Theme.Fonts.display,
		TextScaled = true,
		TextColor3 = Theme.Colors.grey,
		Size = UDim2.fromScale(1, 0.28),
		Parent = gui,
	})
	UI.stroke(timerLabel, Theme.Colors.black, 2, 0.3)
	local frame = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.15,
		Position = UDim2.fromScale(0, 0.3),
		Size = UDim2.fromScale(1, 0.7),
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
		Position = UDim2.fromScale(0.05, 0.04),
		Size = UDim2.fromScale(0.9, 0.36),
		Parent = frame,
	})
	local dmgLabel = UI.text({
		Text = "DMG",
		TextScaled = true,
		Position = UDim2.fromScale(0.05, 0.4),
		Size = UDim2.fromScale(0.9, 0.27),
		Parent = frame,
	})
	local rateLabel = UI.text({
		Text = "RATE",
		TextScaled = true,
		Position = UDim2.fromScale(0.05, 0.68),
		Size = UDim2.fromScale(0.9, 0.27),
		Parent = frame,
	})
	local tag: Tag = {
		gui = gui,
		dmgLabel = dmgLabel,
		rateLabel = rateLabel,
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
	local lastNearby = false
	RunService.Heartbeat:Connect(function(dt)
		if ClientState.reviveNearby ~= lastNearby then
			lastNearby = ClientState.reviveNearby
			for gun, tag in tags do
				if gun.Parent then
					refreshTag(gun, tag)
				end
			end
		end
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
