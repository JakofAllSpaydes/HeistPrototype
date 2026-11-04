--!strict
-- Shared arms drop: a crate with N guns fanned around it, one take per player per crate.
-- Several crates can be live at once (intro crate + per-wave crate); all close at wave end.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)
local Rarity = require(Shared.Rarity)
local Remotes = require(Shared.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local WeaponRoll = require(script.Parent.WeaponRoll)
local Stats = require(script.Parent.Stats)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)

type Crate = {
	id: string,
	model: Model,
	glow: BasePart?,
	guns: { [number]: BasePart },
	left: number,
	active: boolean,
}

local BigCrate = {}

local template = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("CrateTemplate") :: Model
local effects = Workspace:WaitForChild("Effects")
local crates: { [string]: Crate } = {}
local nextId = 0

local function weaponCount(): number
	return math.max(Config.BigCrateWeaponCount.min, #World.runAudience() + Config.BigCrateWeaponCount.plus)
end

local function tagUpgrades(): { [string]: any }
	local first = World.runAudience()[1]
	return if first then PlayerState.get(first).upgrades else {}
end

local function tagDamagePct(): number
	local first = World.runAudience()[1]
	return if first then PlayerState.damagePct(PlayerState.get(first)) else 0
end

-- The crate pool: every weapon owned by someone in the run, carrying the highest Armory level among its owners.
local function partyPool(): { { weapon: Weapons.Weapon, level: number } }
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

-- Drop a crate. `at` overrides the landing spot (default: a random point BigCrateDistanceFromCenter out).
function BigCrate.drop(at: Vector3?)
	nextId += 1
	local id = "crate" .. nextId
	local n = weaponCount()
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
	model.Parent = effects

	local crate: Crate = { id = id, model = model, glow = nil, guns = {}, left = n, active = true }
	crates[id] = crate
	local endsAt = if Config.BigCrateLifetime > 0 then Workspace:GetServerTimeNow() + Config.BigCrateLifetime else 0
	if Config.BigCrateLifetime > 0 then
		task.delay(Config.BigCrateLifetime, function()
			if crate.active then
				BigCrate.finish(crate)
			end
		end)
	end
	World.fireRun("CrateIncoming", { crateId = id, left = n, total = n })
	Log.event("Crate", "Arms drop %s incoming at wave %d with %d guns", id, World.wave, n)

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
		glow.Size = Vector3.new(0.1, 16, 16)
		glow.CFrame = CFrame.new(landPos + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
		glow.Anchored = true
		glow.CanCollide = false
		glow.CanQuery = false
		glow.Color = Color3.fromHex("E8B64C")
		glow.Material = Enum.Material.Neon
		glow.Transparency = 0.65
		glow.Parent = effects
		crate.glow = glow

		-- Lid swings open on its back hinge.
		local hinge = bodyLand * CFrame.new(0, body.Size.Y / 2, -body.Size.Z / 2)
		local openCF = hinge * CFrame.Angles(math.rad(-110), 0, 0) * CFrame.new(0, lid.Size.Y / 2, body.Size.Z / 2)
		TweenService:Create(lid, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			CFrame = openCF,
		}):Play()
		World.fireRun("CrateLand", { crateId = id, left = crate.left, total = n, position = landPos, endsAt = endsAt })

		-- Guns eject in an arc and settle in a fan.
		local wave = World.wave
		local floor = Config.BigCrateRarityFloorByBracket[Rarity.bracketIndex(wave)]
		local dmgPct = tagDamagePct()
		-- Distinct weapon types per crate: shuffle the owned pool and deal from the top.
		local deck = partyPool()
		for i = #deck, 2, -1 do
			local k = math.random(i)
			deck[i], deck[k] = deck[k], deck[i]
		end
		for slot = 1, n do
			local entry = deck[((slot - 1) % #deck) + 1]
			local weapon = entry.weapon
			local rarity = Rarity.roll(wave, floor, weapon.rarityWeights)
			local a = (slot - 1) / n * math.pi * 2 + (math.random() - 0.5) * 0.4
			local dist = Config.BigCrateFanMin + math.random() * (Config.BigCrateFanMax - Config.BigCrateFanMin)
			local target = landPos + Vector3.new(math.cos(a) * dist, 0.35, math.sin(a) * dist)
			local gun = WeaponRoll.spawnGun({
				weaponId = weapon.id,
				rarity = rarity,
				level = entry.level,
				cframe = CFrame.new(landPos + Vector3.new(0, body.Size.Y + 0.5, 0)),
				dmg = Stats.weaponDamage(weapon.id, rarity, dmgPct, entry.level),
				dps = Stats.weaponDps(weapon.id, rarity, tagUpgrades(), entry.level),
				lifetime = Config.GroundWeaponLifetime,
				crateId = id,
				slot = slot,
				promptText = "SWAP",
			})
			crate.guns[slot] = gun
			gun.Destroying:Connect(function()
				BigCrate.onGunGone(id, slot, nil)
			end)
			local settle = CFrame.new(target)
				* CFrame.Angles(0, a, 0)
				* CFrame.Angles(0, 0, math.rad(math.random(-12, 12)))
			local apex = CFrame.new((landPos + target) / 2 + Vector3.new(0, 7, 0))
			task.delay(0.05 * slot, function()
				if not gun.Parent then
					return
				end
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
				end
			end)
		end
		Log.event(
			"Crate",
			"%s landed at (%d, %d), floor %s",
			id,
			math.round(landPos.X),
			math.round(landPos.Z),
			Rarity.name(floor)
		)
	end)
end

-- Crate guns are ordinary swaps (you only hold one gun, so the old one lands on the floor anyway).
-- WeaponRoll calls this after a crate gun is picked up so the banner count and the crate follow.
-- A crate gun left the floor (taken or expired). The crate closes once none are left.
function BigCrate.onGunGone(crateId: string, slot: number, takenBy: Player?)
	local crate = crates[crateId]
	if not crate or not crate.active or not crate.guns[slot] then
		return
	end
	crate.guns[slot] = nil
	crate.left = 0
	for _ in crate.guns do
		crate.left += 1
	end
	World.fireRun("CrateCount", { crateId = crate.id, left = crate.left })
	if takenBy then
		Log.event("Crate", "%s took a gun from %s, %d left", takenBy.Name, crate.id, crate.left)
	end
	if crate.left <= 0 then
		BigCrate.finish(crate)
	end
end

function BigCrate.onGunTaken(player: Player, crateId: string, slot: number)
	BigCrate.onGunGone(crateId, slot, player)
end

function BigCrate.finish(crate: Crate)
	if not crate.active then
		return
	end
	crate.active = false
	crates[crate.id] = nil
	-- Leftover guns become ordinary ground loot and keep their remaining lifetime.
	for _, gun in crate.guns do
		if gun.Parent then
			gun:SetAttribute("CrateId", nil)
			gun:SetAttribute("Slot", nil)
			local prompt = gun:FindFirstChild("Prompt")
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.ActionText = "SWAP"
			end
		end
	end
	crate.guns = {}
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
	Log.event("Crate", "%s closed", crate.id)
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

function BigCrate.init()
	WeaponRoll.CrateGunTakenHandler = BigCrate.onGunTaken
	Remotes.TakeCrateWeapon.OnServerEvent:Connect(function(player: Player, crateId: any, slot: any)
		local crate = if typeof(crateId) == "string" then crates[crateId] else nil
		if not crate or typeof(slot) ~= "number" then
			return
		end
		local gun = crate.guns[slot]
		if gun then
			WeaponRoll.swap(player, gun)
		end
	end)
end

return BigCrate
