--!strict
-- Rarity with pity, ground loot spawn, swap. The ground-gun factory the arms crate (BigCrate) ejects through.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)
local Rarity = require(Shared.Rarity)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local PlayerState = require(script.Parent.PlayerState)
local Stats = require(script.Parent.Stats)
local Log = require(script.Parent.Log)

export type SpawnOpts = {
	weaponId: string,
	rarity: number,
	level: number?, -- Armory level the gun carries (nil = 0)
	cframe: CFrame,
	dmg: number,
	dps: number?, -- shown on the tag; defaults to the weapon at no upgrades
	lifetime: number?, -- nil = Config.GroundWeaponLifetime, 0 = never
	promptText: string?,
	mag: number?, -- rounds left in the mag (a dropped gun); nil = full
}

local WeaponRoll = {}

local assets = ReplicatedStorage:WaitForChild("Assets")
local gunTemplate = assets:WaitForChild("GunTemplate") :: BasePart
local beamTemplate = assets:WaitForChild("BeamTemplate") :: Beam
local lootFolder = Workspace:WaitForChild("GroundLoot")

local nextGunId = 0
local expireTokens: { [BasePart]: number } = {}

local function withinReach(player: Player, gun: BasePart): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	return (root.Position - gun.Position).Magnitude <= Config.InteractRadius + 2
end

function WeaponRoll.setLifetime(gun: BasePart, lifetime: number)
	gun:SetAttribute("SpawnedAt", Workspace:GetServerTimeNow())
	gun:SetAttribute("Lifetime", lifetime)
	local token = (expireTokens[gun] or 0) + 1
	expireTokens[gun] = token
	if lifetime > 0 then
		task.delay(lifetime, function()
			if gun.Parent and expireTokens[gun] == token then
				expireTokens[gun] = nil
				gun:Destroy()
			end
		end)
	end
end

-- Flat expanding ring on the floor. Used by gun drops and the crate landing.
function WeaponRoll.dustRing(position: Vector3, size: number, color: Color3?)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.CFrame = CFrame.new(position.X, Config.FloorTop + 0.3, position.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Color = color or Color3.fromRGB(160, 150, 130)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.3
	ring.Parent = Workspace:WaitForChild("Effects")
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, size, size),
		Transparency = 1,
	}):Play()
	task.delay(0.6, function()
		ring:Destroy()
	end)
end

-- Keep the beam world-vertical whatever angle the gun lies at. Call again after moving a gun.
function WeaponRoll.alignBeam(gun: BasePart)
	local a0 = gun:FindFirstChild("BeamBottom") :: Attachment?
	local a1 = gun:FindFirstChild("BeamTop") :: Attachment?
	if not a0 or not a1 then
		return
	end
	a0.Position = gun.CFrame:PointToObjectSpace(gun.Position + Vector3.new(0, 0.2, 0))
	a1.Position = gun.CFrame:PointToObjectSpace(gun.Position + Vector3.new(0, 14, 0))
end

-- A ground gun: rarity-colored Part, vertical beam, ProximityPrompt. Tags are drawn by the client.
function WeaponRoll.spawnGun(opts: SpawnOpts): BasePart
	nextGunId += 1
	local weapon = Weapons.ById[opts.weaponId]
	local gun = gunTemplate:Clone()
	gun.Name = "Gun_" .. nextGunId
	gun.Color = Rarity.color(opts.rarity)
	gun.CFrame = opts.cframe
	gun:SetAttribute("GunId", nextGunId)
	gun:SetAttribute("WeaponId", opts.weaponId)
	gun:SetAttribute("DisplayName", weapon.displayName)
	gun:SetAttribute("Rarity", opts.rarity)
	gun:SetAttribute("Dmg", math.round(opts.dmg))
	gun:SetAttribute("Dps", math.round(opts.dps or Stats.weaponDps(opts.weaponId, opts.rarity, {}, opts.level)))
	gun:SetAttribute("Level", opts.level or 0)
	gun:SetAttribute("RateMult", Weapons.levelRateMult(opts.level or 0))
	if opts.mag ~= nil then
		gun:SetAttribute("Mag", opts.mag)
	end

	local a0 = Instance.new("Attachment")
	a0.Name = "BeamBottom"
	a0.Parent = gun
	local a1 = Instance.new("Attachment")
	a1.Name = "BeamTop"
	a1.Parent = gun
	WeaponRoll.alignBeam(gun)
	local beam = beamTemplate:Clone()
	beam.Name = "Beam"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(Rarity.color(opts.rarity))
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Parent = gun

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	prompt.ActionText = opts.promptText or "SWAP"
	prompt.ObjectText = string.format("%s · %s", weapon.displayName, Rarity.name(opts.rarity))
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.MaxActivationDistance = Config.InteractRadius
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = gun
	prompt.Triggered:Connect(function(player)
		WeaponRoll.onPrompt(player, gun)
	end)

	gun.Parent = lootFolder
	WeaponRoll.setLifetime(gun, if opts.lifetime ~= nil then opts.lifetime else Config.GroundWeaponLifetime)
	return gun
end

-- Ground CFrame a few studs in front of a character, lying flat at a random slight angle.
function WeaponRoll.groundCFrameInFront(char: Model, distance: number): CFrame
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local base = if root then root.CFrame else char:GetPivot()
	local flat = CFrame.new(base.Position) * CFrame.Angles(0, select(2, base:ToEulerAnglesYXZ()), 0)
	local pos = (flat * CFrame.new(0, 0, -distance)).Position
	pos = Vector3.new(pos.X, Config.FloorTop + 0.35, pos.Z)
	return CFrame.new(pos)
		* CFrame.Angles(0, math.random() * math.pi * 2, 0)
		* CFrame.Angles(0, 0, math.rad(math.random(-12, 12)))
end

function WeaponRoll.onPrompt(player: Player, gun: BasePart)
	WeaponRoll.swap(player, gun)
end

-- Drop the held gun as ground loot at a CFrame (used by swap and crate take).
function WeaponRoll.dropHeld(state: PlayerState.State, cframe: CFrame): BasePart
	return WeaponRoll.dropGun(state, state.held, cframe)
end

-- Drop any gun record (held or stowed) as ground loot at a CFrame.
function WeaponRoll.dropGun(state: PlayerState.State, gun: Types.Held, cframe: CFrame): BasePart
	return WeaponRoll.spawnGun({
		weaponId = gun.weaponId,
		rarity = gun.rarity,
		level = gun.level,
		cframe = cframe,
		dmg = Stats.weaponDamage(gun.weaponId, gun.rarity, PlayerState.damagePct(state), gun.level),
		dps = Stats.weaponDps(gun.weaponId, gun.rarity, state.upgrades, gun.level),
		mag = gun.mag, -- the floor gun keeps whatever was in the mag
	})
end

function WeaponRoll.swap(player: Player, gun: BasePart)
	if not gun.Parent or gun.Parent ~= lootFolder then
		return
	end
	if not withinReach(player, gun) then
		return
	end
	local state = PlayerState.get(player)
	local now = os.clock()
	if now - state.lastSwapAt < Config.SwapCooldownSec or state.downed then
		return
	end
	state.lastSwapAt = now
	local cf = gun.CFrame
	local newId = gun:GetAttribute("WeaponId") :: string
	local newRarity = gun:GetAttribute("Rarity") :: number
	local newLevel = tonumber(gun:GetAttribute("Level")) or 0
	local floorMag = gun:GetAttribute("Mag")
	local oldId, oldRarity = state.held.weaponId, state.held.rarity
	expireTokens[gun] = nil
	gun:Destroy()
	-- The old gun lands where the new one was, with a fresh timer and the rounds it had left; the new one
	-- comes up with whatever was in its mag (full for a fresh roll or crate gun).
	WeaponRoll.dropHeld(state, cf)
	PlayerState.setHeld(state, newId, newRarity, newLevel, if typeof(floorMag) == "number" then floorMag else nil)
	Remotes.Juice:FireClient(player, "Swap", { weaponId = newId, rarity = newRarity, position = cf.Position })
	Log.event(
		"Swap",
		"%s picked up %s %s, dropped %s %s",
		player.Name,
		Rarity.name(newRarity),
		newId,
		Rarity.name(oldRarity),
		oldId
	)
end

-- Rarity with pity for the player who opened the crate. `minRarity` is the crate's bracket floor; the pity floor
-- (the held rarity after MaxConsecutiveNonUpgrades rolls below it) raises it further. Returns rarity and a short
-- note for the log.
function WeaponRoll.rollRarity(
	state: PlayerState.State,
	wave: number,
	weights: { number },
	minRarity: number?
): (number, string)
	local note = ""
	local rarity: number
	if state.forcedRarity then
		rarity = state.forcedRarity
		state.forcedRarity = nil
		note = "forced by debug"
	else
		local floor: number = minRarity or 1
		local pity = state.pityStreak >= Config.MaxConsecutiveNonUpgrades and state.held.rarity > floor
		if pity then
			floor = state.held.rarity
			note = string.format("pity floor %s", Rarity.name(floor))
		end
		rarity = Rarity.roll(wave, floor, weights)
		if pity then
			state.pityStreak = 0
			return rarity, note
		end
	end
	if rarity < state.held.rarity then
		state.pityStreak += 1
	else
		state.pityStreak = 0
	end
	return rarity, note
end

function WeaponRoll.clearAll()
	for _, gun in lootFolder:GetChildren() do
		gun:Destroy()
	end
end

function WeaponRoll.init()
	Remotes.SwapWeapon.OnServerEvent:Connect(function(player: Player, gun: any)
		if typeof(gun) == "Instance" and gun:IsA("BasePart") then
			WeaponRoll.onPrompt(player, gun)
		end
	end)
end

return WeaponRoll
