--!strict
-- Round 24v: the Explosive and Elemental weapons. Combat hands every shot from a weapon with a `mode` here instead
-- of the hitscan path. Damage still goes through Combat's dealDamage (kill cash, mastery, lifesteal, the Hit juice).
--   projectile (Explosive): a server part flies with gravity. fuse 0 = it blows on contact (RPG); otherwise it stops
--     where it lands and blows after `fuse` seconds (grenade 0.25, cluster 0.5 then splits into bomblets, TNT 1);
--     a grenade that hits an enemy directly blows at once (directDetonate).
--   charge (plasma): the client holds the trigger; `charge` 0..1 scales the bolt's size, damage and blast.
--   stream (flamethrower / cryo): each tick hits every enemy in a short cone with line of sight, and burns / chills.
--   chain (arc gun): each tick locks the enemy nearest the aim in a narrow cone and arcs on to `chains` more.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Enemy = require(script.Parent.Enemy)
local Elements = require(script.Parent.Elements)
local World = require(script.Parent.World)
local Pause = require(script.Parent.Pause)
local Remotes = require(script.Parent.SlotRemotes)

-- Round 24ab: a held plasma beam steers: the shooter's latest cursor point (BeamAim) re-aims every tick.
local beamAims: { [Player]: { aim: Vector3, at: number } } = {}

local SpecialFire = {}

-- Combat installs its dealDamage(shooter, model, dmg, position, info, allowSplash) here (no require cycle).
SpecialFire.deal = nil :: any

local effects: Instance? = nil
local groundLoot: Instance? = nil

local function deal(shooter: any, model: Model, dmg: number, pos: Vector3, info: { [string]: any })
	local fn = SpecialFire.deal
	if fn then
		fn(shooter, model, dmg, pos, info, false)
	end
end

local function filterFor(shooter: any): { Instance }
	local f: { Instance } = { shooter.char }
	if effects then
		table.insert(f, effects)
	end
	if groundLoot then
		table.insert(f, groundLoot)
	end
	return f
end

-- Clear line from `a` to the enemy (map geometry only blocks; other enemies don't).
local function clearTo(shooter: any, a: Vector3, model: Model, b: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local f = filterFor(shooter)
	local folder = Workspace:FindFirstChild("Enemies")
	if folder then
		table.insert(f, folder)
	end
	params.FilterDescendantsInstances = f
	return Workspace:Raycast(a, b - a, params) == nil
end

------------------------------------------------------------------ explosions
local function explode(shooter: any, pos: Vector3, radius: number, dmg: number, color: Color3, shake: number)
	World.fireRun("Blast", { position = pos, radius = radius, color = color, shake = shake, pitch = 0.6 })
	for _, model in Enemy.within(pos, radius) do
		local ep = Enemy.rootPosition(model) or pos
		local away = ep - pos
		local t = 1 - math.clamp(away.Magnitude / radius, 0, 1)
		-- Full damage in the inner part of the blast, down to ExplosiveEdgeDmg at the rim.
		local fall = Config.ExplosiveEdgeDmg + (1 - Config.ExplosiveEdgeDmg) * math.clamp(t / 0.6, 0, 1)
		deal(shooter, model, dmg * fall, ep, {
			dir = if away.Magnitude > 0.1 then away.Unit else nil,
			blast = true,
			blastT = t,
		})
	end
end

------------------------------------------------------------------ projectiles
type ProjSpec = {
	kind: string,
	speed: number,
	gravity: number,
	fuse: number,
	radius: number,
	directDetonate: boolean?,
	bomblets: number?,
	bombletRadius: number?,
	bombletDmgMult: number?,
	bounce: number?, -- Round 24aa: share of speed kept on each touch after landing (rolling)
}

local LOOK = {
	rocket = {
		size = Vector3.new(0.6, 0.6, 2.1), -- Round 24aa: bigger so it reads in flight
		color = Color3.fromHex("5C6B3A"),
		trail = "smoke",
	},
	grenade = { size = Vector3.new(0.4, 0.4, 0.55), color = Color3.fromHex("4F5B3A"), trail = "none" },
	cluster = { size = Vector3.new(0.45, 0.45, 0.6), color = Color3.fromHex("C2672A"), trail = "none" },
	bomblet = { size = Vector3.new(0.25, 0.25, 0.25), color = Color3.fromHex("E8A33A"), trail = "none" },
	tnt = { size = Vector3.new(0.55, 0.45, 0.8), color = Color3.fromHex("B3261E"), trail = "spark" },
	plasma = { size = Vector3.new(0.5, 0.5, 0.5), color = Color3.fromHex("5BFF9A"), trail = "glow" },
}

local function projectilePart(kind: string, at: CFrame, scale: number): BasePart
	local look = (LOOK :: any)[kind] or LOOK.grenade
	local p = Instance.new("Part")
	p.Name = "Projectile_" .. kind
	p.Size = look.size * scale
	p.CFrame = at
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Color = look.color
	p.Material = if kind == "plasma" then Enum.Material.Neon else Enum.Material.SmoothPlastic
	if kind == "grenade" or kind == "cluster" or kind == "bomblet" or kind == "plasma" then
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * math.max(p.Size.X, p.Size.Z)
	end
	if look.trail == "smoke" then
		local s = Instance.new("Smoke")
		s.Size = 0.6
		s.RiseVelocity = 0.5
		s.Opacity = 0.25
		s.Parent = p
		local f = Instance.new("Fire")
		f.Size = 1.5
		f.Heat = 0
		f.Parent = p
	elseif look.trail == "spark" then
		local sp = Instance.new("Sparkles")
		sp.SparkleColor = Color3.fromHex("FFB13B")
		sp.Parent = p
	elseif look.trail == "glow" then
		local l = Instance.new("PointLight")
		l.Color = look.color
		l.Range = 8 * scale
		l.Brightness = 3
		l.Parent = p
	end
	p.Parent = effects
	return p
end

local lobVelocity: (from: Vector3, target: Vector3, speed: number, g: number, aimDir: Vector3) -> Vector3
local beamHits: (
	origin: Vector3,
	dir: Vector3,
	range: number,
	radius: number
) -> { { model: Model, part: BasePart, pos: Vector3 } }
local launch: (shooter: any, origin: Vector3, velocity: Vector3, spec: ProjSpec, dmg: number, scale: number) -> ()

local function detonate(shooter: any, spec: ProjSpec, pos: Vector3, dmg: number, scale: number)
	local color = if spec.kind == "plasma" then Color3.fromHex("5BFF9A") else Color3.fromHex("FF8A2A")
	local radius = spec.radius * scale
	explode(shooter, pos, radius, dmg, color, if spec.kind == "tnt" or spec.kind == "rocket" then 0.45 else 0.25)
	-- Cluster: the shell splits and throws bomblets that each blow where they land.
	local n = spec.bomblets or 0
	if n > 0 then
		local bomb: ProjSpec = {
			kind = "bomblet",
			speed = 0,
			gravity = spec.gravity,
			fuse = 0,
			radius = spec.bombletRadius or 4,
		}
		for i = 1, n do
			local a = (i / n) * math.pi * 2 + math.random() * 0.4
			local out = Vector3.new(math.cos(a), 0, math.sin(a)) * (Config.ClusterScatter * (0.6 + math.random() * 0.6))
			local up = Vector3.yAxis * (Config.ClusterScatterUp * (0.7 + math.random() * 0.5))
			launch(shooter, pos + Vector3.new(0, 0.6, 0), out + up, bomb, dmg * (spec.bombletDmgMult or 0.5), 1)
		end
	end
end

launch = function(shooter: any, origin: Vector3, velocity: Vector3, spec: ProjSpec, dmg: number, scale: number)
	local p = projectilePart(spec.kind, CFrame.lookAt(origin, origin + velocity), scale)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filterFor(shooter)
	task.spawn(function()
		local pos, vel = origin, velocity
		local alive = 0
		local landedAt: number? = nil
		while p.Parent do
			local dt = RunService.Heartbeat:Wait()
			if Pause.active() then
				continue
			end
			alive += dt
			if landedAt and alive - landedAt >= spec.fuse then
				break
			end
			if alive > Config.ProjectileMaxLife then
				break
			end
			vel -= Vector3.yAxis * spec.gravity * dt
			local step = vel * dt
			local hit = Workspace:Raycast(pos, step, params)
			if hit then
				pos = hit.Position + hit.Normal * 0.2
				local onEnemy = Enemy.fromPart(hit.Instance) ~= nil
				if spec.fuse <= 0 or (onEnemy and spec.directDetonate) then
					break
				end
				-- Round 24aa: the first touch starts the fuse; then it bounces and rolls (spec.bounce), losing speed
				-- on every touch, until the fuse runs out. TNT barely moves.
				if not landedAt then
					landedAt = alive
				end
				local n = hit.Normal
				local bounce = spec.bounce or 0.3
				vel = (vel - 2 * vel:Dot(n) * n) * bounce
				vel = Vector3.new(vel.X * Config.GrenadeRollKeep, vel.Y, vel.Z * Config.GrenadeRollKeep)
				if vel.Magnitude < 1.5 then
					vel = Vector3.zero
				end
				p.CFrame = CFrame.new(pos) * CFrame.Angles(alive * 9, 0, alive * 5)
				continue
			end
			if landedAt and vel.Magnitude < 0.01 then
				-- At rest on its fuse.
				continue
			end
			pos += step
			if landedAt then
				p.CFrame = CFrame.new(pos) * CFrame.Angles(alive * 9, 0, alive * 5) -- tumbling as it rolls
			elseif vel.Magnitude > 0.1 then
				p.CFrame = CFrame.lookAt(pos, pos + vel)
			end
		end
		if p.Parent then
			p:Destroy()
			detonate(shooter, spec, pos, dmg, scale)
		end
	end)
end

------------------------------------------------------------------ streams / chain
local function inCone(
	origin: Vector3,
	dir: Vector3,
	range: number,
	halfAngleDeg: number
): { { model: Model, pos: Vector3, dist: number } }
	local out = {}
	local cosA = math.cos(math.rad(halfAngleDeg))
	for _, d in Enemy.all() do
		local model = d.model
		local ep = Enemy.rootPosition(model)
		if ep then
			local v = ep - origin
			local dist = v.Magnitude
			if dist <= range and dist > 0.01 and v.Unit:Dot(dir) >= cosA then
				table.insert(out, { model = model, pos = ep, dist = dist })
			end
		end
	end
	table.sort(out, function(a, b)
		return a.dist < b.dist
	end)
	return out
end

local function streamTick(shooter: any, origin: Vector3, dir: Vector3, spec: any)
	local st = shooter.stats
	local hits = 0
	for _, e in inCone(origin, dir, spec.range, spec.angle) do
		if hits >= Config.StreamMaxTargets then
			break
		end
		if clearTo(shooter, origin, e.model, e.pos) then
			hits += 1
			local fall = 1 - Config.StreamFalloff * (e.dist / spec.range)
			if spec.element == "fire" then
				Elements.burn(e.model, shooter.player, st.damage * Config.FlameBurnDpsMult, Config.FlameBurnSec)
			elseif spec.element == "frost" then
				Elements.chillOn(e.model, Config.CryoSprayPower)
			end
			deal(shooter, e.model, st.damage * fall, e.pos, { dir = dir })
		end
	end
	World.fireRun("StreamTick", { userId = shooter.player.UserId, element = spec.element })
end

local function chainTick(shooter: any, origin: Vector3, dir: Vector3, spec: any)
	local st = shooter.stats
	local first: { model: Model, pos: Vector3, dist: number }? = nil
	for _, e in inCone(origin, dir, spec.range, spec.angle) do
		if clearTo(shooter, origin, e.model, e.pos) then
			first = e
			break
		end
	end
	local points: { Vector3 } = {}
	if not first then
		-- A miss still crackles out to where you aimed.
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = filterFor(shooter)
		local r = Workspace:Raycast(origin, dir * spec.range, params)
		table.insert(points, if r then r.Position else origin + dir * spec.range)
		World.fireRun("Lightning", { userId = shooter.player.UserId, points = points })
		return
	end
	local hitSet: { [Model]: boolean } = {}
	local cur = first :: any
	local dmg = st.damage
	for i = 0, spec.chains do
		hitSet[cur.model] = true
		table.insert(points, cur.pos)
		deal(shooter, cur.model, dmg, cur.pos, { dir = dir, secondary = i > 0 })
		if i == spec.chains then
			break
		end
		-- Arc on to the nearest enemy not yet hit.
		local nextE = nil
		local best = spec.chainRange
		for _, d in Enemy.all() do
			if not hitSet[d.model] then
				local ep = Enemy.rootPosition(d.model)
				if ep then
					local dd = (ep - cur.pos).Magnitude
					if dd < best then
						best = dd
						nextE = { model = d.model, pos = ep }
					end
				end
			end
		end
		if not nextE then
			break
		end
		cur = nextE
		dmg *= spec.decay
	end
	World.fireRun("Lightning", { userId = shooter.player.UserId, points = points })
end

------------------------------------------------------------------ beam hits
-- Round 24ag: every enemy a beam of radius r touches along origin -> dir x range, by its real body parts (a sphere
-- swept through everything but the enemies, so walls never stop it), each enemy once, with the part it touched first
-- (Head = a headshot). The old test measured to each enemy's root alone and missed heads and limbs on thin beams.
beamHits = function(
	origin: Vector3,
	dir: Vector3,
	range: number,
	radius: number
): { { model: Model, part: BasePart, pos: Vector3 } }
	local out = {}
	local folder = Workspace:FindFirstChild("Enemies")
	if not folder then
		return out
	end
	-- Exclude every top-level thing but the Enemies folder (map, effects, players), then each enemy once it is hit.
	local ex: { Instance } = {}
	for _, c0 in Workspace:GetChildren() do
		if c0 ~= folder then
			table.insert(ex, c0)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local from = origin
	local left = range
	local r = math.clamp(radius, 0.1, 20)
	for _ = 1, 24 do
		params.FilterDescendantsInstances = ex
		local hit = Workspace:Spherecast(from, r, dir * left, params)
		if not hit then
			break
		end
		local model = Enemy.fromPart(hit.Instance)
		if not model then
			break
		end
		table.insert(out, { model = model, part = hit.Instance :: BasePart, pos = hit.Position })
		table.insert(ex, model)
		local travelled = math.max(0, (hit.Position - from):Dot(dir) - r)
		from += dir * travelled
		left -= travelled
		if left <= 0 then
			break
		end
	end
	return out
end

------------------------------------------------------------------ entry
-- The velocity at `speed` that lands a lob (gravity `g`) on `target`: the low-arc solution, or 45 degrees when
-- the target is out of reach.
lobVelocity = function(from: Vector3, target: Vector3, speed: number, g: number, aimDir: Vector3): Vector3
	local d = target - from
	local flat = Vector3.new(d.X, 0, d.Z)
	local x = flat.Magnitude
	if x < 0.5 then
		return aimDir * speed
	end
	local y = d.Y
	local v2 = speed * speed
	local disc = v2 * v2 - g * (g * x * x + 2 * y * v2)
	local angle = if disc >= 0 then math.atan((v2 - math.sqrt(disc)) / (g * x)) else math.rad(45)
	local h = flat.Unit
	return h * speed * math.cos(angle) + Vector3.yAxis * speed * math.sin(angle)
end

function SpecialFire.fire(shooter: any, origin: Vector3, dir: Vector3, extra: any)
	local w = shooter.weapon
	local st = shooter.stats
	local mode = w.mode
	if mode == "projectile" then
		local spec = w.proj :: ProjSpec
		local start = origin + dir * 1.5
		local vel = dir * spec.speed
		-- Round 24aa: lobbed rounds land on the crosshair. The client sends its aim point; the launch angle is solved
		-- (low arc) at the gun's speed so the arc comes down there. Out of reach: the 45-degree max-range throw.
		local target = if typeof(extra) == "table" then extra.target else nil
		if
			spec.gravity > 10
			and typeof(target) == "Vector3"
			and (target - origin).Magnitude < Config.LobMaxTargetStuds
		then
			vel = lobVelocity(start, target, spec.speed, spec.gravity, dir)
		end
		launch(shooter, start, vel, spec, st.damage, 1)
	elseif mode == "charge" then
		-- Round 24aa: the charged plasma BEAM. A set, long range (c.range) straight through walls and every enemy on
		-- its line. The charge thickens it (minWidth..maxWidth) and holds it longer (minDur..maxDur): no charge is a
		-- quick zap (one hit), a full charge a thick ray that holds about a second and hits maxTicks times. The total
		-- damage (up to maxDmgMult) is split across the ticks; the beam leaves from the shooter's head each tick.
		local c = w.charge
		local t = math.clamp(tonumber(typeof(extra) == "table" and extra.charge or 0) or 0, 0, 1)
		local width = c.minWidth + (c.maxWidth - c.minWidth) * t
		local dur = c.minDur + (c.maxDur - c.minDur) * t
		local ticks = 1 + math.floor(t * (c.maxTicks - 1) + 0.5)
		local perTick = st.damage * (1 + (c.maxDmgMult - 1) * t) / ticks
		World.fireRun("PlasmaBeam", {
			userId = shooter.player.UserId,
			dir = dir,
			-- Round 24ab: the cursor's world point, so the beam is drawn from the muzzle THROUGH it (a beam parallel
			-- to the head ray ran beside the cursor and read as slanted).
			aim = if typeof(extra) == "table" and typeof(extra.target) == "Vector3" then extra.target else nil,
			range = c.range,
			width = width,
			dur = dur,
			charge = t,
			color = c.color, -- Round 24ad: the Railcaster's blue (nil = plasma green)
		})
		beamAims[shooter.player] = nil
		task.spawn(function()
			for i = 1, ticks do
				local head = shooter.char:FindFirstChild("Head")
				local o = if head and head:IsA("BasePart") then head.Position else origin
				local ba = beamAims[shooter.player]
				if ba and os.clock() - ba.at < 0.4 and (ba.aim - o).Magnitude > 1 then
					dir = (ba.aim - o).Unit
				end
				for _, h in beamHits(o, dir, c.range, width / 2 + Config.PlasmaBeamHitPad) do
					local headshot = h.part.Name == "Head"
					deal(
						shooter,
						h.model,
						perTick * (if headshot then st.headshotMult else 1),
						h.pos,
						{ dir = dir, headshot = headshot }
					)
				end
				if i < ticks then
					task.wait(dur / ticks)
				end
			end
		end)
	elseif mode == "stream" then
		streamTick(shooter, origin, dir, w.stream)
	elseif mode == "chain" then
		chainTick(shooter, origin, dir, w.chain)
	end
end

function SpecialFire.init()
	Remotes.BeamAim.OnServerEvent:Connect(function(player: Player, aim: any)
		if typeof(aim) ~= "Vector3" then
			return
		end
		beamAims[player] = { aim = aim, at = os.clock() }
		World.fireRun("PlasmaBeamAim", { userId = player.UserId, aim = aim })
	end)
	effects = Workspace:WaitForChild("Effects")
	groundLoot = Workspace:WaitForChild("GroundLoot")
end

return SpecialFire
