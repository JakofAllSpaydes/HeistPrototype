--!strict
-- Hitscan validation, damage, kill cash. Raycasts from the server-side head along the client direction.
-- Upgrade effects resolved here: crit, headshot, pierce, ricochet, splash, multishot, lifesteal, greed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local PlayerState = require(script.Parent.PlayerState)
local Economy = require(script.Parent.Economy)
local Enemy = require(script.Parent.Enemy)

local Combat = {}

local function coneSpread(direction: Vector3, halfAngleDeg: number): Vector3
	if halfAngleDeg <= 0 then
		return direction
	end
	local angle = math.rad(halfAngleDeg) * math.sqrt(math.random())
	local roll = math.random() * math.pi * 2
	local cf = CFrame.lookAt(Vector3.zero, direction)
	local offset = cf * CFrame.Angles(0, 0, roll) * CFrame.Angles(angle, 0, 0)
	return offset.LookVector
end

type Shooter = {
	player: Player,
	state: PlayerState.State,
	stats: Types.Computed,
	char: Model,
	weapon: Weapons.Weapon,
}

-- Distance falloff multiplier for the shooter's archetype (Config.FalloffByArchetype).
local function falloff(shooter: Shooter, distance: number): number
	local f = Config.FalloffByArchetype[shooter.weapon.archetype]
	if not f or distance <= f.start then
		return 1
	end
	if distance >= f.finish then
		return f.min
	end
	local t = (distance - f.start) / math.max(f.finish - f.start, 0.01)
	return 1 + (f.min - 1) * t
end

local function heal(shooter: Shooter, amount: number)
	if amount <= 0 then
		return
	end
	local hum = shooter.char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		hum.Health = math.min(hum.MaxHealth, hum.Health + amount)
	end
end

-- Apply one damage instance to an enemy. Handles kill cash, lifesteal, splash-on-kill and the Hit juice.
local function dealDamage(
	shooter: Shooter,
	model: Model,
	dmg: number,
	position: Vector3,
	info: { [string]: any },
	allowSplash: boolean
)
	dmg = math.max(1, math.round(dmg))
	local killed = Enemy.damage(model, dmg, shooter.player)
	local cash = 0
	if killed then
		cash = math.round(Config.CashPerKill * shooter.stats.greed)
		Economy.addCash(shooter.state, cash)
	end
	heal(shooter, dmg * shooter.stats.lifesteal / 100)
	Remotes.Juice:FireClient(shooter.player, "Hit", {
		position = position,
		amount = dmg,
		headshot = info.headshot == true,
		crit = info.crit == true,
		killed = killed,
		model = model,
		cash = cash,
		secondary = info.secondary == true,
	})
	if killed and allowSplash and shooter.stats.splash > 0 then
		local splashDmg = dmg * shooter.stats.splash / 100
		local victims = Enemy.within(position, Config.SplashRadius, model)
		Remotes.Juice:FireAllClients("Splash", { position = position, radius = Config.SplashRadius, hits = #victims })
		for _, victim in victims do
			local vp = Enemy.rootPosition(victim) or position
			dealDamage(shooter, victim, splashDmg, vp, { secondary = true }, false)
		end
	end
end

-- A direct bullet hit on an enemy part: falloff by distance from the muzzle, crit/headshot roll, then ricochet.
local function bulletHit(shooter: Shooter, model: Model, part: BasePart, position: Vector3, origin: Vector3)
	local st = shooter.stats
	local headshot = part.Name == "Head"
	local crit = math.random() * 100 < st.critChance
	local dmg = st.damage
		* falloff(shooter, (position - origin).Magnitude)
		* (if headshot then st.headshotMult else 1)
		* (if crit then Config.CritDmgMult else 1)
	dealDamage(shooter, model, dmg, position, { headshot = headshot, crit = crit }, true)

	if st.ricochet > 0 and math.random() * 100 < st.ricochet then
		local target = Enemy.nearest(position, Config.RicochetRange, model)
		if target then
			local tp = Enemy.rootPosition(target) or position
			Remotes.Juice:FireAllClients("Ricochet", { from = position, to = tp })
			dealDamage(shooter, target, dmg * Config.RicochetDmgRatio, tp, { secondary = true, crit = crit }, true)
		end
	end
end

-- One bullet: raycast, hit, then keep going through up to `pierce` more enemies.
local function fireBullet(shooter: Shooter, origin: Vector3, dir: Vector3, baseFilter: { Instance }, pierce: number)
	local filter = table.clone(baseFilter)
	local from = origin
	local remaining = Config.MaxShotRange
	for _ = 0, pierce do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = filter
		local result = Workspace:Raycast(from, dir * remaining, params)
		if not result then
			return
		end
		local model = Enemy.fromPart(result.Instance)
		if not model then
			return -- wall, pillar, floor: the bullet stops
		end
		bulletHit(shooter, model, result.Instance :: BasePart, result.Position, origin)
		table.insert(filter, model)
		remaining -= (result.Position - from).Magnitude
		from = result.Position
		if remaining <= 0 then
			return
		end
	end
end

function Combat.init()
	local groundLoot = Workspace:WaitForChild("GroundLoot")
	local effects = Workspace:WaitForChild("Effects")

	Remotes.FireShot.OnServerEvent:Connect(function(player: Player, origin: any, direction: any, _clientTime: any)
		if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
			return
		end
		if direction.Magnitude < 0.5 then
			return
		end
		local char = player.Character
		local head = char and char:FindFirstChild("Head") :: BasePart?
		if not char or not head then
			return
		end
		if (origin - head.Position).Magnitude > Config.MaxOriginDriftStuds then
			return
		end

		local state = PlayerState.get(player)
		local st = PlayerState.computed(state)
		local now = os.clock()
		if now - state.lastShotAt < 1 / (st.fireRate * Config.FireRateTolerance) then
			return
		end
		state.lastShotAt = now

		local weapon = Weapons.ById[state.held.weaponId]
		local shooter: Shooter = { player = player, state = state, stats = st, char = char, weapon = weapon }
		local dir = direction.Unit
		local baseFilter: { Instance } = { char, groundLoot, effects }
		local spread = weapon.spread * st.spreadMult

		for _ = 1, weapon.pellets do
			local d = if weapon.pellets > 1 then coneSpread(dir, spread) else dir
			fireBullet(shooter, head.Position, d, baseFilter, st.pierce)
		end
		if st.multishot > 0 and math.random() * 100 < st.multishot then
			fireBullet(shooter, head.Position, coneSpread(dir, spread + Config.MultishotSpread), baseFilter, st.pierce)
			Remotes.Juice:FireClient(player, "Multishot", {})
		end
	end)
end

return Combat
