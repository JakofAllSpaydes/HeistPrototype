--!strict
-- Shared arms drop: scheduled crate with N guns fanned around it, one take per player.
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
	takenBy: { [Player]: boolean },
	active: boolean,
}

local BigCrate = {}

local template = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("CrateTemplate") :: Model
local effects = Workspace:WaitForChild("Effects")
local current: Crate? = nil
local nextId = 0

local function weaponCount(): number
	return math.max(Config.BigCrateWeaponCount.min, #Players:GetPlayers() + Config.BigCrateWeaponCount.plus)
end

local function tagDamagePct(): number
	local first = Players:GetPlayers()[1]
	return if first then PlayerState.damagePct(PlayerState.get(first)) else 0
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

function BigCrate.drop()
	if current then
		BigCrate.finish(current)
	end
	nextId += 1
	local id = "crate" .. nextId
	local n = weaponCount()
	local angle = math.random() * math.pi * 2
	local landPos = Vector3.new(
		math.cos(angle) * Config.BigCrateDistanceFromCenter,
		0,
		math.sin(angle) * Config.BigCrateDistanceFromCenter
	)

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

	local crate: Crate = { id = id, model = model, glow = nil, guns = {}, left = n, takenBy = {}, active = true }
	current = crate
	Remotes.Juice:FireAllClients("CrateIncoming", { crateId = id, left = n, total = n })
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
		glow.CFrame = CFrame.new(landPos + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90))
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
		TweenService
			:Create(lid, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = openCF })
			:Play()
		Remotes.Juice:FireAllClients("CrateLand", { crateId = id, left = crate.left, total = n, position = landPos })

		-- Guns eject in an arc and settle in a fan.
		local wave = World.wave
		local floor = Config.BigCrateRarityFloorByBracket[Rarity.bracketIndex(wave)]
		local dmgPct = tagDamagePct()
		for slot = 1, n do
			local weapon = Weapons.List[math.random(#Weapons.List)]
			local rarity = Rarity.roll(wave, floor, weapon.rarityWeights)
			local a = (slot - 1) / n * math.pi * 2 + (math.random() - 0.5) * 0.4
			local dist = Config.BigCrateFanMin + math.random() * (Config.BigCrateFanMax - Config.BigCrateFanMin)
			local target = landPos + Vector3.new(math.cos(a) * dist, 0.35, math.sin(a) * dist)
			local gun = WeaponRoll.spawnGun({
				weaponId = weapon.id,
				rarity = rarity,
				cframe = CFrame.new(landPos + Vector3.new(0, body.Size.Y + 0.5, 0)),
				dmg = Stats.weaponDamage(weapon.id, rarity, dmgPct),
				lifetime = 0,
				crateId = id,
				slot = slot,
				promptText = "TAKE",
			})
			crate.guns[slot] = gun
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
				if gun.Parent then
					TweenService:Create(
						gun,
						TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
						{ CFrame = settle }
					):Play()
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

function BigCrate.take(player: Player, gun: BasePart)
	local crate = current
	if not crate or not crate.active or gun:GetAttribute("CrateId") ~= crate.id then
		return
	end
	if crate.takenBy[player] then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not root or (root.Position - gun.Position).Magnitude > Config.InteractRadius + 2 then
		return
	end
	local state = PlayerState.get(player)
	local slot = gun:GetAttribute("Slot") :: number
	local weaponId = gun:GetAttribute("WeaponId") :: string
	local rarity = gun:GetAttribute("Rarity") :: number

	WeaponRoll.dropHeld(state, WeaponRoll.groundCFrameInFront(char, 2))
	PlayerState.setHeld(state, weaponId, rarity)
	crate.takenBy[player] = true
	state.cratesTaken[crate.id] = true
	state.dirty = true
	crate.guns[slot] = nil
	gun:Destroy()
	crate.left -= 1
	Remotes.Juice:FireAllClients("CrateCount", { crateId = crate.id, left = crate.left })
	Remotes.Juice:FireClient(player, "Swap", { weaponId = weaponId, rarity = rarity, fromCrate = true })
	Log.event(
		"Crate",
		"%s took %s %s from %s, %d left",
		player.Name,
		Rarity.name(rarity),
		weaponId,
		crate.id,
		crate.left
	)
	if crate.left <= 0 then
		BigCrate.finish(crate)
	end
end

function BigCrate.finish(crate: Crate)
	if not crate.active then
		return
	end
	crate.active = false
	if current == crate then
		current = nil
	end
	-- Leftover guns become ordinary ground loot with the normal lifetime.
	for _, gun in crate.guns do
		if gun.Parent then
			gun:SetAttribute("CrateId", nil)
			gun:SetAttribute("Slot", nil)
			local prompt = gun:FindFirstChild("Prompt")
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.ActionText = "SWAP"
			end
			WeaponRoll.setLifetime(gun, Config.GroundWeaponLifetime)
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
	Remotes.Juice:FireAllClients("CrateEnd", { crateId = crate.id })
	Log.event("Crate", "%s closed", crate.id)
end

function BigCrate.finishCurrent()
	if current then
		BigCrate.finish(current)
	end
end

function BigCrate.onWaveStart(wave: number)
	if wave > 0 and wave % Config.BigCrateWaveInterval == 0 then
		BigCrate.drop()
	end
end

function BigCrate.onWaveEnd()
	BigCrate.finishCurrent()
end

function BigCrate.init()
	WeaponRoll.CrateTakeHandler = BigCrate.take
	Remotes.TakeCrateWeapon.OnServerEvent:Connect(function(player: Player, crateId: any, slot: any)
		local crate = current
		if not crate or crate.id ~= crateId or typeof(slot) ~= "number" then
			return
		end
		local gun = crate.guns[slot]
		if gun then
			BigCrate.take(player, gun)
		end
	end)
end

return BigCrate
