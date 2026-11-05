--!strict
-- Hitscan validation, damage, kill cash. Raycasts from the server-side head along the client direction.
-- Upgrade effects resolved here: crit, headshot, pierce, ricochet, splash, multishot, lifesteal, CASH GAIN, and the
-- element procs (rolled once per shot, applied through Elements to every enemy the shot hits directly).
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
local Elements = require(script.Parent.Elements)
local Mastery = require(script.Parent.Mastery)
local Pause = require(script.Parent.Pause)
local World = require(script.Parent.World)

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
	procs: Elements.Procs, -- this shot's element rolls (one per element per trigger pull)
	procced: { [Model]: boolean }, -- enemies this shot already applied its elements to (pellets, pierce)
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
	local ed = Enemy.data(model)
	local elite = ed ~= nil and ed.elite
	local boss = ed ~= nil and ed.row.boss == true
	local killed, killCash = Enemy.damage(model, dmg, shooter.player, {
		dir = info.dir,
		headshot = info.headshot == true,
		-- A direct hit throws with the gun's force; a splash victim is thrown out of the blast instead.
		force = if info.secondary
			then Config.RagdollTickForce * 2
			else Config.RagdollForceByArchetype[shooter.weapon.archetype] or 1,
		blast = info.blast == true,
		blastT = info.blastT,
	})
	local cash = 0
	if killed then
		-- The archetype's cash (x wave, x elite, x heat) x CASH GAIN.
		cash = math.round(killCash * shooter.stats.cashGain)
		Economy.addCash(shooter.state, cash)
		Mastery.onGunKill(shooter.player, shooter.state.held.weaponId, elite, boss)
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
		World.fireRun("Splash", { position = position, radius = Config.SplashRadius, hits = #victims })
		for _, victim in victims do
			local vp = Enemy.rootPosition(victim) or position
			local away = vp - position
			dealDamage(shooter, victim, splashDmg, vp, {
				secondary = true,
				dir = if away.Magnitude > 0.1 then away.Unit else nil,
				blast = true,
				blastT = 1 - math.clamp(away.Magnitude / Config.SplashRadius, 0, 1),
			}, false)
		end
	end
end

-- A direct bullet hit on an enemy part: falloff by distance from the muzzle, crit/headshot roll, then ricochet.
local function bulletHit(
	shooter: Shooter,
	model: Model,
	part: BasePart?,
	position: Vector3,
	origin: Vector3,
	scale: number
)
	local st = shooter.stats
	local headshot = part ~= nil and part.Name == "Head"
	local crit = math.random() * 100 < st.critChance
	local travel = position - origin
	local dmg = st.damage
		* scale
		* falloff(shooter, travel.Magnitude)
		* (if headshot then st.headshotMult else 1)
		* (if crit then Config.CritDmgMult else 1)
	local dir = if travel.Magnitude > 0.1 then travel.Unit else nil
	-- Elements go on before the damage so a burn or freeze lands even when the hit is not the kill.
	if shooter.procs.any and not shooter.procced[model] then
		shooter.procced[model] = true
		Elements.apply(shooter.player, st, model, shooter.procs, dir, position)
	end
	dealDamage(shooter, model, dmg, position, { headshot = headshot, crit = crit, dir = dir }, true)
	-- DEAD EYE OVERDRIVE (SHARPSHOOTER III): a headshot during Dead Eye puts a round back and trims its cooldown.
	local state = shooter.state
	if headshot and state.buffId == "deadeye" and PlayerState.passive(state, "SHARPSHOOTER", 3) then
		if PlayerState.buffActive(state) then
			Remotes.Juice:FireClient(shooter.player, "MagAdd", { n = 1 })
			local cd = state.cooldowns.deadeye
			if cd then
				state.cooldowns.deadeye = cd - Config.DeadEyeHeadshotCdr
				state.dirty = true
				Remotes.Juice:FireClient(
					shooter.player,
					"CooldownTrim",
					{ id = "deadeye", sec = Config.DeadEyeHeadshotCdr }
				)
			end
		end
	end

	if st.ricochet > 0 and math.random() * 100 < st.ricochet then
		local target = Enemy.nearest(position, Config.RicochetRange, model)
		if target then
			local tp = Enemy.rootPosition(target) or position
			local hop = tp - position
			World.fireRun("Ricochet", { from = position, to = tp })
			dealDamage(shooter, target, dmg * Config.RicochetDmgRatio, tp, {
				secondary = true,
				crit = crit,
				dir = if hop.Magnitude > 0.1 then hop.Unit else nil,
			}, true)
		end
	end
end

-- One bullet: raycast, hit, then keep going through `pierce` more enemies. A fractional pierce adds one
-- more enemy that only takes that fraction of the damage (2.2 = two full hits past the first, then one at 20%).
-- Returns where the bullet stopped (for the teammates' tracer).
local function fireBullet(
	shooter: Shooter,
	origin: Vector3,
	dir: Vector3,
	baseFilter: { Instance },
	pierce: number
): Vector3
	local filter = table.clone(baseFilter)
	local from = origin
	local remaining = Config.MaxShotRange
	local full = math.floor(pierce)
	local frac = pierce - full
	local extra = if frac > 0.001 then 1 else 0
	-- Point blank: an enemy standing in the shooter sits inside the ray's start, so it takes the first hit here
	-- and uses up the first pierce step.
	local first = 0
	local close = Enemy.nearestInCone(origin, dir, Config.PointBlankRange, Config.PointBlankAngle)
	if close then
		local root = close:FindFirstChild("HumanoidRootPart")
		local pos = Enemy.rootPosition(close) or origin
		bulletHit(shooter, close, (if root and root:IsA("BasePart") then root else nil) :: any, pos, origin, 1)
		table.insert(filter, close)
		first = 1
		if first > full + extra then
			return pos
		end
	end
	for i = first, full + extra do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = filter
		local result = Workspace:Raycast(from, dir * remaining, params)
		if not result then
			return from + dir * remaining
		end
		local model = Enemy.fromPart(result.Instance)
		if not model then
			return result.Position -- wall, pillar, floor: the bullet stops
		end
		bulletHit(shooter, model, result.Instance :: BasePart, result.Position, origin, if i > full then frac else 1)
		table.insert(filter, model)
		remaining -= (result.Position - from).Magnitude
		from = result.Position
		if remaining <= 0 then
			return from
		end
	end
	return from + dir * remaining
end

-- Rounds left in the held mag, as the client counts it. The server never simulates the mag; it only keeps
-- the number with the gun so a swap, stow or floor pickup hands it back.
local function rememberMag(state: PlayerState.State, mag: any)
	if typeof(mag) ~= "number" or mag ~= mag then
		return
	end
	local st = PlayerState.computed(state)
	state.held.mag = math.clamp(math.floor(mag), 0, st.magSize)
end

function Combat.init()
	local groundLoot = Workspace:WaitForChild("GroundLoot")
	local effects = Workspace:WaitForChild("Effects")

	Remotes.AmmoReport.OnServerEvent:Connect(function(player: Player, mag: any)
		rememberMag(PlayerState.get(player), mag)
	end)

	Remotes.FireShot.OnServerEvent:Connect(
		function(player: Player, origin: any, direction: any, _clientTime: any, mag: any)
			if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
				return
			end
			rememberMag(PlayerState.get(player), mag)
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
			-- Downed players shoot the sidearm (Config.DownedCanShoot); bled-out spectators never fire; nobody
			-- fires while the run is paused.
			if state.bledOut or (state.downed and not Config.DownedCanShoot) or Pause.active() then
				return
			end
			local st = PlayerState.computed(state)
			local now = os.clock()
			if now - state.lastShotAt < 1 / (st.fireRate * Config.FireRateTolerance) then
				return
			end
			state.lastShotAt = now

			local weapon = Weapons.ById[state.held.weaponId]
			local shooter: Shooter = {
				player = player,
				state = state,
				stats = st,
				char = char,
				weapon = weapon,
				procs = Elements.roll(st),
				procced = {},
			}
			local dir = direction.Unit
			local baseFilter: { Instance } = { char, groundLoot, effects }
			local spread = weapon.spread * st.spreadMult * (if state.downed then Config.DownedSpreadMult else 1)

			local ends: { Vector3 } = {}
			for _ = 1, weapon.pellets do
				local d = if weapon.pellets > 1 then coneSpread(dir, spread) else dir
				table.insert(ends, fireBullet(shooter, head.Position, d, baseFilter, st.pierce))
			end
			if st.multishot > 0 and math.random() * 100 < st.multishot then
				table.insert(
					ends,
					fireBullet(
						shooter,
						head.Position,
						coneSpread(dir, spread + Config.MultishotSpread),
						baseFilter,
						st.pierce
					)
				)
				Remotes.Juice:FireClient(player, "Multishot", {})
			end
			-- Teammates see the shot: the same tracer from this gun's muzzle to where each bullet stopped, and the
			-- shot sound at the gun. The shooter already drew its own.
			if Config.RemoteTracers then
				local payload =
					{ userId = player.UserId, from = head.Position, ends = ends, archetype = weapon.archetype }
				for _, other in World.runAudience() do
					if other ~= player then
						Remotes.Juice:FireClient(other, "RemoteShot", payload)
					end
				end
			end
		end
	)
end

return Combat
