--!strict
-- Weapon roll with pity, ground loot spawn, swap. Also the ground-gun factory used by the big crate.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)
local Rarity = require(Shared.Rarity)
local Remotes = require(Shared.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local Economy = require(script.Parent.Economy)
local Stats = require(script.Parent.Stats)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)

export type SpawnOpts = {
	weaponId: string,
	rarity: number,
	cframe: CFrame,
	dmg: number,
	dps: number?, -- shown on the tag; defaults to the weapon at no upgrades
	lifetime: number?, -- nil = Config.GroundWeaponLifetime, 0 = never
	crateId: string?,
	slot: number?,
	promptText: string?,
	dropFrom: number?, -- fall in from this height and bounce on the floor
}

local WeaponRoll = {}

-- BigCrate installs this so the two modules never require each other: (player, crateId, slot).
WeaponRoll.CrateGunTakenHandler = nil :: ((Player, string, number) -> ())?

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
	ring.CFrame = CFrame.new(position.X, 0.3, position.Z) * CFrame.Angles(0, 0, math.rad(90))
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
	gun:SetAttribute("Dps", math.round(opts.dps or Stats.weaponDps(opts.weaponId, opts.rarity, {})))
	if opts.crateId then
		gun:SetAttribute("CrateId", opts.crateId)
		gun:SetAttribute("Slot", opts.slot)
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

	local dropFrom = opts.dropFrom
	if dropFrom and dropFrom > 0 then
		local final = opts.cframe
		gun.CFrame = final + Vector3.new(0, dropFrom, 0)
		local fall = TweenService:Create(
			gun,
			TweenInfo.new(Config.GunDropSec, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
			{ CFrame = final }
		)
		fall:Play()
		fall.Completed:Once(function()
			if gun.Parent then
				WeaponRoll.dustRing(final.Position, 8, Rarity.color(opts.rarity))
				Remotes.Juice:FireAllClients("GunLanded", { position = final.Position, rarity = opts.rarity })
			end
		end)
	end
	return gun
end

-- Ground CFrame a few studs in front of a character, lying flat at a random slight angle.
function WeaponRoll.groundCFrameInFront(char: Model, distance: number): CFrame
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local base = if root then root.CFrame else char:GetPivot()
	local flat = CFrame.new(base.Position) * CFrame.Angles(0, select(2, base:ToEulerAnglesYXZ()), 0)
	local pos = (flat * CFrame.new(0, 0, -distance)).Position
	pos = Vector3.new(pos.X, 0.35, pos.Z)
	return CFrame.new(pos)
		* CFrame.Angles(0, math.random() * math.pi * 2, 0)
		* CFrame.Angles(0, 0, math.rad(math.random(-12, 12)))
end

function WeaponRoll.onPrompt(player: Player, gun: BasePart)
	WeaponRoll.swap(player, gun)
end

-- Drop the held gun as ground loot at a CFrame (used by swap and crate take).
function WeaponRoll.dropHeld(state: PlayerState.State, cframe: CFrame): BasePart
	local held = state.held
	return WeaponRoll.spawnGun({
		weaponId = held.weaponId,
		rarity = held.rarity,
		cframe = cframe,
		dmg = Stats.weaponDamage(held.weaponId, held.rarity, PlayerState.damagePct(state)),
		dps = Stats.weaponDps(held.weaponId, held.rarity, state.upgrades),
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
	local crateId = gun:GetAttribute("CrateId")
	local slot = gun:GetAttribute("Slot")
	local oldId, oldRarity = state.held.weaponId, state.held.rarity
	expireTokens[gun] = nil
	gun:Destroy()
	-- The old gun lands where the new one was, with a fresh timer.
	WeaponRoll.dropHeld(state, cf)
	PlayerState.setHeld(state, newId, newRarity)
	local handler = WeaponRoll.CrateGunTakenHandler
	if handler and typeof(crateId) == "string" and typeof(slot) == "number" then
		handler(player, crateId, slot)
	end
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

-- Rarity with pity. Returns rarity and a short pity description for the log.
function WeaponRoll.rollRarity(state: PlayerState.State, wave: number, weights: { number }): (number, string)
	local note = ""
	local rarity: number
	if state.forcedRarity then
		rarity = state.forcedRarity
		state.forcedRarity = nil
		note = "forced by debug"
	else
		local floor: number? = nil
		if state.pityStreak >= Config.MaxConsecutiveNonUpgrades then
			floor = state.held.rarity
			note = string.format("pity floor %s", Rarity.name(floor))
		end
		rarity = Rarity.roll(wave, floor, weights)
		if floor then
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

function WeaponRoll.buy(player: Player): any
	local state = PlayerState.get(player)
	if state.downed or state.bledOut then
		return { ok = false, reason = "downed" }
	end
	local price = Economy.weaponPrice(state)
	if not Economy.tryCharge(state, price) then
		return { ok = false, reason = "cash", price = price }
	end
	state.weaponsBought += 1
	local weapon = Weapons.List[math.random(#Weapons.List)]
	local rarity, note = WeaponRoll.rollRarity(state, World.wave, weapon.rarityWeights)
	local dmg = Stats.weaponDamage(weapon.id, rarity, PlayerState.damagePct(state))
	local dps = Stats.weaponDps(weapon.id, rarity, state.upgrades)
	state.dirty = true
	Log.event(
		"Roll",
		"%s paid $%d, rolled %s %s (DMG %d). Pity streak %d/%d%s",
		player.Name,
		price,
		Rarity.name(rarity),
		weapon.id,
		math.round(dmg),
		state.pityStreak,
		Config.MaxConsecutiveNonUpgrades,
		if note ~= "" then ", " .. note else ""
	)

	-- The gun starts falling when the client reel ejects, and lands 4 studs in front of the player.
	task.delay(Config.RollDurationSec + Config.RollLandHoldSec, function()
		local char = player.Character
		if not player.Parent or not char then
			return
		end
		WeaponRoll.spawnGun({
			weaponId = weapon.id,
			rarity = rarity,
			cframe = WeaponRoll.groundCFrameInFront(char, 4),
			dmg = Stats.weaponDamage(weapon.id, rarity, PlayerState.damagePct(state)),
			dps = Stats.weaponDps(weapon.id, rarity, state.upgrades),
			dropFrom = Config.GunDropHeight,
		})
	end)

	return {
		ok = true,
		weapon = {
			weaponId = weapon.id,
			displayName = weapon.displayName,
			archetype = weapon.archetype,
			rarity = rarity,
			rarityName = Rarity.name(rarity),
			dmg = math.round(dmg),
			dps = math.round(dps),
			pellets = weapon.pellets,
			fireRate = weapon.fireRate, -- base; the client applies its own fire-rate multiplier
		},
		pityStreak = state.pityStreak,
	}
end

function WeaponRoll.clearAll()
	for _, gun in lootFolder:GetChildren() do
		gun:Destroy()
	end
end

function WeaponRoll.init()
	Remotes.BuyWeapon.OnServerInvoke = WeaponRoll.buy
	Remotes.SwapWeapon.OnServerEvent:Connect(function(player: Player, gun: any)
		if typeof(gun) == "Instance" and gun:IsA("BasePart") then
			WeaponRoll.onPrompt(player, gun)
		end
	end)
	Players.PlayerRemoving:Connect(function() end)
end

return WeaponRoll
