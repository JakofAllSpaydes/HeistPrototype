--!strict
-- The arms crate (brief 5): the only in-run weapon source. It lands closed with CrateRolls = party size +
-- CrateRollsExtra and a `N ROLLS LEFT` tag; F (OPEN) by any party member spends one roll and plays the reel on a
-- billboard above the crate for everyone (CrateReelUI on the client, timing in CrateReel). On the land the gun
-- ejects in an arc to a free spot CrateDropRadius out as ordinary floor loot. The crate closes when the rolls are
-- gone or after CrateLifetimeSec; guns already on the floor keep their own timers.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)
local Rarity = require(Shared.Rarity)
local CrateReel = require(Shared.CrateReel)
local PlayerState = require(script.Parent.PlayerState)
local WeaponRoll = require(script.Parent.WeaponRoll)
local Stats = require(script.Parent.Stats)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)

type Entry = { weapon: Weapons.Weapon, level: number }

type Crate = {
	id: string,
	model: Model,
	body: BasePart,
	lid: BasePart,
	lidClosed: CFrame,
	landPos: Vector3,
	glow: BasePart?,
	prompt: ProximityPrompt?,
	rolls: number,
	total: number,
	rolled: number,
	busy: boolean,
	expired: boolean,
	active: boolean,
	guaranteed: boolean,
	deck: { Entry },
	endsAt: number,
}

local BigCrate = {}

local template = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("CrateTemplate") :: Model
local effects = Workspace:WaitForChild("Effects")
local lootFolder = Workspace:WaitForChild("GroundLoot")
local crates: { [string]: Crate } = {}
local nextId = 0

BigCrate.Tag = "GHSCrate" -- CollectionService tag the client's CrateReelUI watches

local function rollCount(): number
	return math.max(1, #World.runAudience() + Config.CrateRollsExtra)
end

-- The crate pool: every weapon owned by someone in the run, carrying the highest Armory level among its owners.
local function partyPool(): { Entry }
	local levels: { [string]: number } = {}
	for _, p in World.runAudience() do
		local state = PlayerState.get(p)
		for _, w in PlayerState.ownedWeapons(state) do
			levels[w.id] = math.max(levels[w.id] or 0, PlayerState.weaponLevel(state, w.id))
		end
	end
	local out = {}
	for _, w in Weapons.List do
		if levels[w.id] then
			table.insert(out, { weapon = w, level = levels[w.id] })
		end
	end
	if #out == 0 then
		table.insert(out, { weapon = Weapons.ById[Weapons.Starter], level = 0 })
	end
	return out
end

local function shuffled(list: { Entry }): { Entry }
	local deck = table.clone(list)
	for i = #deck, 2, -1 do
		local k = math.random(i)
		deck[i], deck[k] = deck[k], deck[i]
	end
	return deck
end

-- Distinct weapon types per crate while the pool lasts: deal from a shuffled deck, reshuffle when it runs out.
local function deal(crate: Crate): Entry
	if #crate.deck == 0 then
		crate.deck = shuffled(partyPool())
	end
	return table.remove(crate.deck, 1) :: Entry
end

local function dustRing(position: Vector3)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 2, 2)
	ring.CFrame = CFrame.new(position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Color = Color3.fromRGB(160, 150, 130)
	ring.Material = Enum.Material.SmoothPlastic
	ring.Transparency = 0.3
	ring.Parent = effects
	TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, 22, 22),
		Transparency = 1,
	}):Play()
	task.delay(0.7, function()
		ring:Destroy()
	end)
end

local function syncAttributes(crate: Crate)
	crate.model:SetAttribute("RollsLeft", crate.rolls)
	crate.model:SetAttribute("Busy", crate.busy)
	local prompt = crate.prompt
	if prompt then
		prompt.Enabled = crate.active and not crate.busy and crate.rolls > 0
		prompt.ObjectText = string.format("%d ROLL%s LEFT", crate.rolls, if crate.rolls == 1 then "" else "S")
	end
end

-- A free floor spot CrateDropRadius out: clear line from the crate (no pillar in the way) and no other floor gun
-- within a couple of studs, so two guns never stack.
local function freeSpot(crate: Crate): Vector3
	local center = crate.landPos
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local room = Workspace:FindFirstChild("Room")
	params.FilterDescendantsInstances = if room then { room } else {}
	local best: Vector3? = nil
	local base = math.random() * math.pi * 2
	for i = 0, 11 do
		local a = base + i * (math.pi * 2 / 12) + (math.random() - 0.5) * 0.3
		local dist = Config.CrateDropRadius * (0.8 + math.random() * 0.2)
		local target = center + Vector3.new(math.cos(a) * dist, 0, math.sin(a) * dist)
		local from = center + Vector3.new(0, 1.5, 0)
		local to = target + Vector3.new(0, 1.5, 0)
		local hit = Workspace:Raycast(from, to - from, params)
		if not hit then
			local crowded = false
			for _, gun in lootFolder:GetChildren() do
				if gun:IsA("BasePart") then
					local d = Vector3.new(gun.Position.X - target.X, 0, gun.Position.Z - target.Z).Magnitude
					if d < 2.5 then
						crowded = true
						break
					end
				end
			end
			if not crowded then
				return target
			end
			best = best or target
		end
	end
	return best or (center + Vector3.new(Config.CrateDropRadius, 0, 0))
end

local function eject(crate: Crate, entry: Entry, rarity: number, roller: PlayerState.State)
	local weapon = entry.weapon
	local spot = freeSpot(crate)
	local start = CFrame.new(crate.landPos + Vector3.new(0, crate.body.Size.Y + 0.6, 0))
	local gun = WeaponRoll.spawnGun({
		weaponId = weapon.id,
		rarity = rarity,
		level = entry.level,
		cframe = start,
		dmg = Stats.weaponDamage(weapon.id, rarity, PlayerState.damagePct(roller), entry.level),
		dps = Stats.weaponDps(weapon.id, rarity, roller.upgrades, entry.level),
		lifetime = Config.GroundWeaponLifetime,
	})
	local a = math.atan2(spot.Z - crate.landPos.Z, spot.X - crate.landPos.X)
	local settle = CFrame.new(spot.X, Config.FloorTop + 0.35, spot.Z)
		* CFrame.Angles(0, a, 0)
		* CFrame.Angles(0, 0, math.rad(math.random(-12, 12)))
	local apex = CFrame.new((start.Position + settle.Position) / 2 + Vector3.new(0, 6, 0))
	local up = TweenService:Create(
		gun,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = apex }
	)
	up:Play()
	up.Completed:Wait()
	if not gun.Parent then
		return
	end
	local down = TweenService:Create(
		gun,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = settle }
	)
	down:Play()
	down.Completed:Wait()
	if gun.Parent then
		WeaponRoll.alignBeam(gun)
		WeaponRoll.dustRing(settle.Position, 8, Rarity.color(rarity))
		World.fireRun("GunLanded", { position = settle.Position, rarity = rarity })
	end
end

-- F on a crate: one roll, the reel for everyone, then the gun ejects.
function BigCrate.roll(player: Player, crate: Crate)
	if not crate.active or crate.busy or crate.rolls <= 0 then
		return
	end
	if not World.inRun() or not World.isInParty(player) then
		return
	end
	local state = PlayerState.get(player)
	if state.downed or state.bledOut then
		return
	end
	crate.busy = true
	crate.rolls -= 1
	crate.rolled += 1
	syncAttributes(crate)

	local entry = deal(crate)
	local weapon = entry.weapon
	local wave = World.wave
	local floor = Config.BigCrateRarityFloorByBracket[Rarity.bracketIndex(wave)]
	local rarity: number
	local note = ""
	if crate.guaranteed and crate.rolled == 1 then
		rarity = Rarity.Legendary
		note = "boss Legendary"
	else
		rarity, note = WeaponRoll.rollRarity(state, wave, weapon.rarityWeights, floor)
	end
	-- Filler icons for the reel: other guns from the pool at random rarities, the landed gun last.
	local pool = partyPool()
	local reel = {}
	for i = 1, math.max(1, Config.CrateReelSteps) - 1 do
		local other = pool[math.random(#pool)].weapon
		reel[i] = { name = other.displayName, rarity = math.random(1, 5) }
	end
	table.insert(reel, { name = weapon.displayName, rarity = rarity })
	World.fireRun("CrateRoll", {
		crateId = crate.id,
		by = player.UserId,
		reel = reel,
		weaponId = weapon.id,
		rarity = rarity,
		position = crate.landPos,
	})
	Log.event(
		"Crate",
		"%s opened %s: %s %s (floor %s%s), %d rolls left",
		player.Name,
		crate.id,
		Rarity.name(rarity),
		weapon.id,
		Rarity.name(floor),
		if note ~= "" then ", " .. note else "",
		crate.rolls
	)

	-- The lid pops up a little while the reel spins and settles back after the eject.
	TweenService:Create(crate.lid, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		CFrame = crate.lidClosed * CFrame.new(0, 0.6, 0) * CFrame.Angles(math.rad(-8), 0, 0),
	}):Play()
	task.delay(CrateReel.ejectSec(), function()
		if not crate.model.Parent then
			return
		end
		TweenService:Create(crate.lid, TweenInfo.new(0.25), { CFrame = crate.lidClosed }):Play()
		task.spawn(eject, crate, entry, rarity, state)
		crate.busy = false
		syncAttributes(crate)
		if crate.rolls <= 0 or crate.expired then
			task.delay(0.4, function()
				BigCrate.finish(crate)
			end)
		end
	end)
end

export type DropOpts = { legendary: boolean? }

-- Drop a crate. `at` overrides the landing spot (default: a random point BigCrateDistanceFromCenter out).
-- opts.legendary makes the first roll a guaranteed Legendary (the boss crate).
function BigCrate.drop(at: Vector3?, opts: DropOpts?)
	nextId += 1
	local id = "crate" .. nextId
	local rolls = rollCount()
	local landPos: Vector3
	if at then
		landPos = Vector3.new(at.X, Config.FloorTop, at.Z)
	else
		local angle = math.random() * math.pi * 2
		landPos = Vector3.new(
			math.cos(angle) * Config.BigCrateDistanceFromCenter,
			Config.FloorTop,
			math.sin(angle) * Config.BigCrateDistanceFromCenter
		)
	end

	local model = template:Clone()
	model.Name = id
	local body = model:WaitForChild("Body") :: BasePart
	local lid = model:WaitForChild("Lid") :: BasePart
	model.PrimaryPart = body
	local bodyLand = CFrame.new(landPos + Vector3.new(0, body.Size.Y / 2, 0))
	local lidLand = bodyLand * CFrame.new(0, body.Size.Y / 2 + lid.Size.Y / 2, 0)
	local lift = Vector3.new(0, Config.BigCrateDropHeight, 0)
	body.CFrame = bodyLand + lift
	lid.CFrame = lidLand + lift
	model:SetAttribute("CrateId", id)
	model:SetAttribute("RollsLeft", rolls)
	model:SetAttribute("Busy", false)
	model:SetAttribute("Landed", false)

	local endsAt = Workspace:GetServerTimeNow() + Config.CrateLifetimeSec
	model:SetAttribute("EndsAt", endsAt)
	local crate: Crate = {
		id = id,
		model = model,
		body = body,
		lid = lid,
		lidClosed = lidLand,
		landPos = landPos,
		glow = nil,
		prompt = nil,
		rolls = rolls,
		total = rolls,
		rolled = 0,
		busy = false,
		expired = false,
		active = true,
		guaranteed = opts ~= nil and opts.legendary == true,
		deck = shuffled(partyPool()),
		endsAt = endsAt,
	}
	crates[id] = crate
	model.Parent = effects
	CollectionService:AddTag(model, BigCrate.Tag)
	task.delay(Config.CrateLifetimeSec, function()
		if not crate.active then
			return
		end
		if crate.busy then
			crate.expired = true -- the roll in flight lands first, then the crate closes
		else
			BigCrate.finish(crate)
		end
	end)
	World.fireRun("CrateIncoming", { crateId = id, rolls = rolls })
	Log.event("Crate", "Arms crate %s incoming at wave %d with %d rolls", id, World.wave, rolls)

	task.spawn(function()
		local fall = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(body, fall, { CFrame = bodyLand }):Play()
		local lidTween = TweenService:Create(lid, fall, { CFrame = lidLand })
		lidTween:Play()
		lidTween.Completed:Wait()
		if not crate.active then
			return
		end
		dustRing(landPos)

		-- Gold glow on the floor.
		local glow = Instance.new("Part")
		glow.Shape = Enum.PartType.Cylinder
		glow.Size = Vector3.new(0.1, 12, 12)
		glow.CFrame = CFrame.new(landPos + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
		glow.Anchored = true
		glow.CanCollide = false
		glow.CanQuery = false
		glow.Color = Color3.fromHex("E8B64C")
		glow.Material = Enum.Material.Neon
		glow.Transparency = 0.65
		glow.Parent = effects
		crate.glow = glow

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Prompt"
		prompt.ActionText = "OPEN"
		prompt.KeyboardKeyCode = Enum.KeyCode.F
		prompt.MaxActivationDistance = Config.InteractRadius
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Parent = body
		prompt.Triggered:Connect(function(player)
			BigCrate.roll(player, crate)
		end)
		crate.prompt = prompt
		model:SetAttribute("Landed", true)
		syncAttributes(crate)
		World.fireRun("CrateLand", { crateId = id, rolls = rolls, position = landPos, endsAt = endsAt })
		Log.event(
			"Crate",
			"%s landed at (%d, %d), floor %s%s",
			id,
			math.round(landPos.X),
			math.round(landPos.Z),
			Rarity.name(Config.BigCrateRarityFloorByBracket[Rarity.bracketIndex(World.wave)]),
			if crate.guaranteed then ", first roll a guaranteed Legendary" else ""
		)
	end)
end

function BigCrate.finish(crate: Crate)
	if not crate.active then
		return
	end
	crate.active = false
	crates[crate.id] = nil
	local prompt = crate.prompt
	if prompt then
		prompt:Destroy()
	end
	crate.model:SetAttribute("RollsLeft", 0)
	for _, p in crate.model:GetDescendants() do
		if p:IsA("BasePart") then
			TweenService:Create(p, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
				Size = Vector3.new(0.05, 0.05, 0.05),
			}):Play()
		end
	end
	local glow = crate.glow
	if glow then
		TweenService:Create(glow, TweenInfo.new(0.3), { Transparency = 1 }):Play()
	end
	task.delay(0.35, function()
		crate.model:Destroy()
		if glow then
			glow:Destroy()
		end
	end)
	World.fireRun("CrateEnd", { crateId = crate.id, remaining = BigCrate.liveCount() })
	Log.event("Crate", "%s closed (%d of %d rolls used)", crate.id, crate.rolled, crate.total)
end

function BigCrate.liveCount(): number
	local n = 0
	for _ in crates do
		n += 1
	end
	return n
end

function BigCrate.finishAll()
	for _, crate in table.clone(crates) do
		BigCrate.finish(crate)
	end
end

function BigCrate.onIntro()
	if Config.BigCrateIntroDrop then
		BigCrate.drop(Config.BigCrateIntroPosition)
	end
end

function BigCrate.onWaveStart(wave: number)
	local interval = Config.BigCrateWaveInterval
	if interval > 0 and wave > 0 and wave % interval == 0 then
		BigCrate.drop()
	end
end

function BigCrate.onWaveEnd()
	if Config.BigCrateDespawnOnWaveEnd then
		BigCrate.finishAll()
	end
end

function BigCrate.init() end

return BigCrate
