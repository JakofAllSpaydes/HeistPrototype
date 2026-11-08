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
local Ground = require(Shared.Ground)
local Weapons = require(Shared.Weapons)
local Rarity = require(Shared.Rarity)
local CrateReel = require(Shared.CrateReel)
local PlayerState = require(script.Parent.Parent.PlayerState)
local WeaponRoll = require(script.Parent.WeaponRoll)
local AllyCallout = require(script.Parent.AllyCallout)
local World = require(script.Parent.World)
local Room = require(script.Parent.Room)
local Log = require(script.Parent.Parent.Log)
local Pause = require(script.Parent.Pause)

type Entry = { weapon: Weapons.Weapon }

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

-- The crate pool: every weapon owned by someone in the run. Round 16: no level rides along; whoever picks the
-- gun up holds it at their own Armory level for that weapon (WeaponRoll.swap).
local function partyPool(): { Entry }
	local owned: { [string]: boolean } = {}
	for _, p in World.runAudience() do
		local state = PlayerState.get(p)
		for _, w in PlayerState.ownedWeapons(state) do
			owned[w.id] = true
		end
	end
	local out = {}
	for _, w in Weapons.List do
		if owned[w.id] then
			table.insert(out, { weapon = w })
		end
	end
	if #out == 0 then
		table.insert(out, { weapon = Weapons.ById[Weapons.Starter] })
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
		prompt.ObjectText = "GUN CRATE"
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

local function eject(crate: Crate, entry: Entry, rarity: number, _roller: PlayerState.State)
	local weapon = entry.weapon
	local spot = freeSpot(crate)
	local start = CFrame.new(crate.landPos + Vector3.new(0, crate.body.Size.Y + 0.6, 0))
	local gun = WeaponRoll.spawnGun({
		weaponId = weapon.id,
		rarity = rarity,
		cframe = start,
		lifetime = Config.GroundWeaponLifetime,
	})
	-- No pickup mid-arc: the prompt comes on once the gun is on the floor.
	local prompt = gun:FindFirstChild("Prompt") :: ProximityPrompt?
	if prompt then
		prompt.Enabled = false
	end
	gun:SetAttribute("Landing", true) -- WeaponRoll.swap and the client tag both respect it
	local a = math.atan2(spot.Z - crate.landPos.Z, spot.X - crate.landPos.X)
	local settle = CFrame.new(spot.X, Ground.y(spot) + 0.35, spot.Z)
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
		gun.CFrame = settle
		gun:SetAttribute("Landing", nil)
		if prompt then
			prompt.Enabled = true
		end
		WeaponRoll.alignBeam(gun)
		WeaponRoll.dustRing(settle.Position, 8, Rarity.color(rarity))
		World.fireRun("GunLanded", { position = settle.Position, rarity = rarity })
	end
end

-- One roll of the chain: the reel for everyone, then (after its land) the gun ejects. Yields for the roll.
local function rollOnce(player: Player, state: PlayerState.State, crate: Crate)
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
	-- Filler rarities for the row of icons; the landed gun sits at CrateReel.Land.
	local fillers = {}
	for i = 1, CrateReel.Cells do
		fillers[i] = if i == CrateReel.Land then rarity else math.random(1, 5)
	end
	World.fireRun("CrateRoll", {
		crateId = crate.id,
		by = player.UserId,
		fillers = fillers,
		weaponId = weapon.id,
		displayName = weapon.displayName,
		rarity = rarity,
		rarityName = Rarity.name(rarity),
		pellets = weapon.pellets, -- each client computes DMG / RATE at its own level (ClientState.gunAsMine)
		left = crate.rolls,
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

	Pause.wait(CrateReel.ejectSec(rarity))
	-- A Legendary landed: the crew hears who pulled it (after the reel, so it never spoils the land).
	if rarity >= Rarity.Legendary then
		AllyCallout.send(player, "legendary", string.upper(weapon.displayName))
	end
	if crate.model.Parent then
		-- The lid kicks as the gun leaves; the clients burst it in the gun's rarity.
		TweenService:Create(crate.lid, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = crate.lidClosed * CFrame.new(0, 1.6, 0) * CFrame.Angles(math.rad(-25), 0, 0),
		}):Play()
		task.delay(0.14, function()
			if crate.model.Parent then
				TweenService:Create(crate.lid, TweenInfo.new(0.3, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
					CFrame = crate.lidClosed * CFrame.new(0, 0.6, 0) * CFrame.Angles(math.rad(-8), 0, 0),
				}):Play()
			end
		end)
		World.fireRun("CrateEject", {
			crateId = crate.id,
			position = crate.landPos + Vector3.new(0, crate.body.Size.Y + 0.6, 0),
			rarity = rarity,
			by = player.UserId,
		})
		task.spawn(eject, crate, entry, rarity, state)
	end
	Pause.wait(Config.RollEjectSec + Config.CrateRollGapSec)
end

-- F on a crate: every roll it holds plays back to back (pity and the bracket floor for whoever pressed it), then
-- the crate closes.
function BigCrate.open(player: Player, crate: Crate)
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
	syncAttributes(crate)
	World.fireRun("CrateOpened", {
		crateId = crate.id,
		position = crate.landPos + Vector3.new(0, crate.body.Size.Y, 0),
		by = player.UserId,
		rolls = crate.rolls,
	})
	-- The lid pops up for the whole chain and settles back after the last eject.
	TweenService:Create(crate.lid, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		CFrame = crate.lidClosed * CFrame.new(0, 0.6, 0) * CFrame.Angles(math.rad(-8), 0, 0),
	}):Play()
	task.spawn(function()
		while crate.rolls > 0 and crate.model.Parent do
			rollOnce(player, state, crate)
		end
		if crate.model.Parent then
			TweenService:Create(crate.lid, TweenInfo.new(0.25), { CFrame = crate.lidClosed }):Play()
		end
		crate.busy = false
		task.delay(0.3, function()
			BigCrate.finish(crate)
		end)
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
		landPos = Ground.at(at)
	elseif World.map == "Arena" then
		local angle = math.random() * math.pi * 2
		landPos = Vector3.new(
			math.cos(angle) * Config.BigCrateDistanceFromCenter,
			Config.FloorTop,
			math.sin(angle) * Config.BigCrateDistanceFromCenter
		)
	else
		-- Brief 7: a map without a center drops it on a free bag spot in the crew's zone (else beside the crew).
		local crew, n = Vector3.zero, 0
		for _, p in World.runAudience() do
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				crew += root.Position
				n += 1
			end
		end
		crew = if n > 0 then crew / n else Room.current().floorTop * Vector3.yAxis
		local best, bestDist = nil, math.huge
		for _, s in Room.current().bagSpots do
			local dist = (s.position - crew).Magnitude
			if s.zone == World.crewZone and dist < bestDist and dist > 8 then
				best, bestDist = s.position, dist
			end
		end
		landPos = Ground.at(best or (crew + Vector3.new(6, 0, 6)))
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
	Pause.delay(Config.CrateLifetimeSec, function()
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
			BigCrate.open(player, crate)
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
	-- Round 19c: the free intro crate is the arena's only (BigCrateIntroDropOnMaps for THE BANK and later maps).
	if Config.BigCrateIntroDrop and (World.map == "Arena" or Config.BigCrateIntroDropOnMaps) then
		-- Brief 7: on a map with a van node the intro crate lands in front of the crew's line.
		local lineup = Room.current().lineup
		BigCrate.drop(if lineup then (lineup * CFrame.new(0, 0, -8)).Position else Config.BigCrateIntroPosition)
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

function BigCrate.init()
	-- After a pause the crates' countdowns pick up where they stopped.
	Pause.onResume(function(duration: number)
		for _, crate in crates do
			crate.endsAt += duration
			crate.model:SetAttribute("EndsAt", crate.endsAt)
		end
	end)
end

return BigCrate
