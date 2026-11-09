--!strict
-- Element upgrades on enemies (brief 5, Round 15e). Every held element goes on every bullet that lands (each pellet
-- counts); the upgrade's power (1 on the first take, + the card's share after) sets the strength.
--   INCENDIARY: each hit adds a stack (up to IncendiaryMaxStacks) and refreshes the burn: IncendiaryDps x power per
--     stack for IncendiaryBurnSec, ticking every FieldTickSec, faster by IncendiaryTickRatePerPower per extra power;
--     kill cash to the shooter.
--   CRYO: walk speed down CryoSlowPct x power (cap CryoSlowCap) for CryoSlowSec; CryoStacksToFreeze hits inside that
--     window freeze the enemy for CryoFreezeSec x power (an ice-blue stun: no move, no attack).
--   CONCUSSIVE: a ConcussiveStuds x power slide along the shot (Heavy and the boss ConcussiveHeavyMult of it) and a
--     ConcussiveStunSec interrupt at most every ConcussiveInterruptSec (never on the boss); a white ring at the hit.
-- The look is the client's (StatusFx.lua) off the Burning / Chilled / Frozen attributes on the enemy model.
-- Synergy upgrades (conditional cards) hook in here too: WILDFIRE (Elements.onKill), SHATTER (Elements.shatterMult,
-- read by Combat) and AFTERSHOCK (on the CONCUSSIVE interrupt). ELEMENTAL POWER is in the powers (Stats.lua).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(script.Parent.SlotRemotes)
local Types = require(Shared.Types)
local PlayerState = require(script.Parent.Parent.PlayerState)
local Stats = require(script.Parent.Parent.Stats)
local Economy = require(script.Parent.Parent.Economy)
local Enemy = require(script.Parent.Enemy)
local World = require(script.Parent.World)
local Pause = require(script.Parent.Pause)

type Status = {
	model: Model,
	burnUntil: number,
	burnDps: number,
	burnOwner: Player?,
	burnRate: number, -- tick-rate multiplier from INCENDIARY power
	burnStacks: number, -- hits stacked on the running burn (IncendiaryMaxStacks)
	nextBurn: number,
	chillUntil: number,
	chillProcs: { number },
	frozenUntil: number,
	lastInterrupt: number, -- CONCUSSIVE's interrupt cooldown
	lastFreeze: number, -- CRYO's freeze cooldown
}

export type Procs = { incendiary: boolean, cryo: boolean, concussive: boolean, any: boolean }

local Elements = {}

-- Mastery hooks (Mastery.lua installs them): how much faster a player's burns tick (TORCH SLOW BURN 2x).
Elements.burnRateFor = function(_owner: Player?): number
	return 1
end

local statuses: { [Model]: Status } = {}

local function statusOf(model: Model): Status
	local s = statuses[model]
	if not s then
		s = {
			model = model,
			burnUntil = 0,
			burnDps = 0,
			burnOwner = nil,
			burnRate = 1,
			burnStacks = 0,
			nextBurn = 0,
			chillUntil = 0,
			chillProcs = {},
			frozenUntil = 0,
			lastInterrupt = -math.huge,
			lastFreeze = -math.huge,
		}
		statuses[model] = s
	end
	return s :: Status
end

function Elements.isBurning(model: Model): boolean
	local s = statuses[model]
	return s ~= nil and s.burnUntil > os.clock()
end

function Elements.burnOwnerOf(model: Model): Player?
	local s = statuses[model]
	return if s and s.burnUntil > os.clock() then s.burnOwner else nil
end

-- Standing in a fire field (molotov, drum fire) or a flame stream: burning for the look and for BACKDRAFT, with no
-- extra damage of its own (the field does the damage).
function Elements.markBurning(model: Model, owner: Player?, seconds: number)
	if not Enemy.data(model) then
		return
	end
	local s = statusOf(model)
	local now = os.clock()
	if s.burnUntil <= now then
		s.burnDps = 0
	end
	s.burnUntil = math.max(s.burnUntil, now + seconds)
	if s.burnDps <= 0 or not s.burnOwner then
		s.burnOwner = owner
	end
	model:SetAttribute("Burning", true)
end

-- Every held element goes on every shot (Round 15b: no chance roll; upgrades raise the power instead).
function Elements.roll(st: Types.Computed): Procs
	local inc = st.incendiaryPower > 0
	local cryo = st.cryoPower > 0
	local con = st.concussivePower > 0
	return { incendiary = inc, cryo = cryo, concussive = con, any = inc or cryo or con }
end

-- Ticks per FieldTickSec for a burn: the owner's mastery rate x the INCENDIARY power's tick rate.
local function burnInterval(s: Status): number
	local rate = Elements.burnRateFor(s.burnOwner) * s.burnRate
	return Config.FieldTickSec / math.max(0.1, rate)
end

-- A burn: refreshes the timer and keeps the stronger DPS / tick rate. `tickRate` 1 = every FieldTickSec.
function Elements.burn(model: Model, owner: Player?, dps: number, seconds: number, tickRate: number?)
	if not Enemy.data(model) then
		return
	end
	local s = statusOf(model)
	local now = os.clock()
	-- Each hit adds a stack (up to IncendiaryMaxStacks); the burn deals `dps` per stack, so a shotgun blast that
	-- lands every pellet stacks it at once and a fast gun builds it quickly.
	if s.burnUntil <= now then
		s.burnStacks = 0
		s.burnDps = 0
		s.burnRate = tickRate or 1
		s.nextBurn = now + burnInterval(s)
	else
		s.burnRate = math.max(s.burnRate, tickRate or 1)
	end
	s.burnOwner = owner
	s.burnStacks = math.min(Config.IncendiaryMaxStacks, s.burnStacks + 1)
	s.burnDps = math.max(s.burnDps, dps * s.burnStacks)
	s.burnUntil = now + seconds
	model:SetAttribute("Burning", true)
end

-- Brief 12: a burn at a set strength (Inferno's ring): no stacking; keeps the stronger of this and what's there.
function Elements.burnAt(model: Model, owner: Player?, dps: number, seconds: number)
	if not Enemy.data(model) then
		return
	end
	local s = statusOf(model)
	local now = os.clock()
	if s.burnUntil <= now then
		s.burnStacks = 1
		s.burnDps = 0
		s.burnRate = 1
		s.burnOwner = owner
		s.nextBurn = now + burnInterval(s)
	end
	if dps >= s.burnDps then
		s.burnDps = dps
		s.burnOwner = owner
	end
	s.burnUntil = math.max(s.burnUntil, now + seconds)
	model:SetAttribute("Burning", true)
end

-- Damage on a player's behalf from an element (a burn tick, an AFTERSHOCK): kill cash with their CASH GAIN, the
-- Hit juice to them. `dmg` is final (boosts already in).
local function ownedHit(owner: Player?, model: Model, dmg: number, pos: Vector3)
	local live = owner ~= nil and owner.Parent ~= nil
	local killed, killCash =
		Enemy.damage(model, dmg, if live then owner else nil, { force = Config.RagdollTickForce, tick = true })
	if live and owner then
		local state = PlayerState.get(owner)
		local cash = 0
		if killed then
			cash = math.round(killCash * PlayerState.computed(state).cashGain)
			Economy.addCash(state, cash)
		end
		Remotes.Juice:FireClient(owner, "Hit", {
			position = pos,
			amount = dmg,
			headshot = false,
			crit = false,
			killed = killed,
			model = model,
			cash = cash,
			secondary = true,
		})
	end
end

-- A burn handed over whole (WILDFIRE): `totalDps` is the burn's full strength, not a per-stack share. Keeps the
-- stronger burn if one is already running; later Fire Ammo hits stack on it as usual.
local function ignite(model: Model, owner: Player, totalDps: number, seconds: number, tickRate: number)
	if not Enemy.data(model) then
		return
	end
	local s = statusOf(model)
	local now = os.clock()
	local fresh = s.burnUntil <= now
	if fresh then
		s.burnStacks = 0
		s.burnDps = 0
	end
	if totalDps >= s.burnDps then
		s.burnDps = totalDps
		s.burnOwner = owner
	end
	s.burnRate = if fresh then tickRate else math.max(s.burnRate, tickRate)
	if fresh then
		s.nextBurn = now + burnInterval(s)
	end
	s.burnUntil = math.max(s.burnUntil, now + seconds)
	model:SetAttribute("Burning", true)
end

-- WILDFIRE (synergy): an enemy dying with its burner's Fire Ammo burn on it hands the burn to every enemy within
-- WildfireRadius at the burner's WILDFIRE share. Fire fields alone (no ammo burn) do not spread. Enemy.onDeath.
function Elements.onKill(model: Model, at: Vector3)
	local s = statuses[model]
	if not s or s.burnUntil <= os.clock() or s.burnDps <= 0 then
		return
	end
	local owner = s.burnOwner
	if not owner or not owner.Parent then
		return
	end
	local share = PlayerState.computed(PlayerState.get(owner)).wildfire / 100
	if share <= 0 then
		return
	end
	local victims = Enemy.within(at, Config.WildfireRadius, model)
	if #victims == 0 then
		return
	end
	for _, victim in victims do
		ignite(victim, owner, s.burnDps * share, Config.IncendiaryBurnSec, s.burnRate)
	end
	World.fireRun(
		"Blast",
		{ position = at, radius = Config.WildfireRadius, color = Color3.fromRGB(255, 140, 40), shake = 0, pitch = 1.3 }
	)
end

-- SHATTER (synergy): the bullet damage multiplier against this enemy: chilled +shatter%, frozen
-- ShatterFrozenMult x that. Read before this shot's own chill lands.
function Elements.shatterMult(model: Model, st: Types.Computed): number
	if st.shatter <= 0 then
		return 1
	end
	local s = statuses[model]
	if not s then
		return 1
	end
	local now = os.clock()
	if s.frozenUntil > now then
		return 1 + st.shatter / 100 * Config.ShatterFrozenMult
	elseif s.chillUntil > now then
		return 1 + st.shatter / 100
	end
	return 1
end

-- AFTERSHOCK (synergy): a Stun Ammo stagger sends `dmg` to every other enemy within AftershockRadius. The ring is
-- drawn at most every AFTERSHOCK_FX_SEC so a crowd of staggers stays quiet.
local AFTERSHOCK_FX_SEC = 0.2
local lastShockFx = -math.huge
local function aftershock(owner: Player, source: Model, dmg: number, at: Vector3)
	local victims = Enemy.within(at, Config.AftershockRadius, source)
	if #victims == 0 then
		return
	end
	local now = os.clock()
	if now - lastShockFx >= AFTERSHOCK_FX_SEC then
		lastShockFx = now
		World.fireRun(
			"Blast",
			{ position = at, radius = Config.AftershockRadius, color = Color3.new(1, 1, 1), shake = 0, pitch = 1.6 }
		)
	end
	local amount = math.max(1, math.round(dmg))
	for _, victim in victims do
		ownedHit(owner, victim, amount, Enemy.rootPosition(victim) or at)
	end
end

local function chill(model: Model, power: number)
	local d = Enemy.data(model)
	if not d then
		return
	end
	local boss = d.row.boss == true
	local s = statusOf(model)
	local now = os.clock()
	-- The boss takes CryoBossSlowMult of the slow and never freezes (a freeze is a stun: it would cancel its
	-- attacks over and over).
	local slowPct = math.clamp(Config.CryoSlowPct * power, 0, Config.CryoSlowCap)
		* (if boss then Config.CryoBossSlowMult else 1)
	Enemy.slow(model, 1 - slowPct, Config.CryoSlowSec)
	s.chillUntil = now + Config.CryoSlowSec
	model:SetAttribute("Chilled", true)
	if boss then
		return
	end
	-- Stacks inside the window: the Nth freezes, at most once per CryoFreezeCooldownSec so nothing is frozen for good.
	local kept = {}
	for _, t in s.chillProcs do
		if now - t <= Config.CryoSlowSec then
			table.insert(kept, t)
		end
	end
	table.insert(kept, now)
	s.chillProcs = kept
	if #kept >= Config.CryoStacksToFreeze and now - s.lastFreeze >= Config.CryoFreezeCooldownSec then
		s.chillProcs = {}
		s.lastFreeze = now
		local sec = Config.CryoFreezeSec * power
		s.frozenUntil = now + sec
		Enemy.stun(model, sec, Color3.fromHex("BFE6FF"))
		model:SetAttribute("Frozen", true)
	end
end

-- Round 24v: the cryo sprayer chills directly (the same slow / stack-to-freeze as a CRYO proc).
function Elements.chillOn(model: Model, power: number)
	chill(model, power)
end

local function knockback(model: Model, power: number, dir: Vector3?, at: Vector3, owner: Player, st: Types.Computed)
	local d = Enemy.data(model)
	if not d then
		return
	end
	World.fireRun("ElementShock", { position = at })
	local flat = if dir then Vector3.new(dir.X, 0, dir.Z) else Vector3.zero
	if flat.Magnitude < 0.05 then
		return
	end
	flat = flat.Unit
	local heavy = d.row.boss == true or d.row.attack == "heavy"
	local dist = Config.ConcussiveStuds * power * (if heavy then Config.ConcussiveHeavyMult else 1)
	-- Stop short of walls and pillars.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local room = Workspace:FindFirstChild("Room")
	params.FilterDescendantsInstances = if room then { room } else {}
	local start = d.root.Position
	local hit = Workspace:Raycast(start, flat * dist, params)
	if hit then
		dist = math.max(0, (hit.Position - start).Magnitude - 1.5)
	end
	-- The interrupt: at most once per ConcussiveInterruptSec per enemy (every shot lands now), never the boss.
	local s = statusOf(model)
	local now = os.clock()
	if not d.row.boss and now - s.lastInterrupt >= Config.ConcussiveInterruptSec then
		s.lastInterrupt = now
		Enemy.stun(model, Config.ConcussiveStunSec)
		if st.aftershock > 0 then
			aftershock(owner, model, st.damage * st.aftershock / 100, at)
		end
	end
	if dist <= 0.2 then
		return
	end
	task.spawn(function()
		local slide = math.max(0.03, Config.ConcussiveSlideSec)
		local moved = 0
		local t = 0
		while t < slide do
			local dt = RunService.Heartbeat:Wait()
			t += dt
			if not model.Parent or not Enemy.data(model) then
				return
			end
			local target = dist * math.clamp(t / slide, 0, 1)
			local step = target - moved
			moved = target
			model:PivotTo(model:GetPivot() + flat * step)
		end
	end)
end

-- Apply this shot's procs to one enemy it hit.
function Elements.apply(owner: Player, st: Types.Computed, model: Model, procs: Procs, dir: Vector3?, at: Vector3)
	if not Enemy.data(model) then
		return
	end
	if procs.incendiary then
		local p = st.incendiaryPower
		Elements.burn(
			model,
			owner,
			Config.IncendiaryDps * p,
			Config.IncendiaryBurnSec,
			1 + Config.IncendiaryTickRatePerPower * (p - 1)
		)
	end
	if procs.cryo then
		chill(model, st.cryoPower)
	end
	if procs.concussive then
		knockback(model, st.concussivePower, dir, at, owner, st)
	end
end

-- A burn tick on the owner's behalf: kill cash with their CASH GAIN, the Hit juice to them.
local function burnTick(s: Status)
	local owner = s.burnOwner
	local dmg = math.max(1, math.round(s.burnDps * Config.FieldTickSec * Stats.mult(owner, "elementDamage"))) -- POWER (brief 6; brief 12: a source)
	ownedHit(owner, s.model, dmg, Enemy.rootPosition(s.model) or Vector3.zero)
end

function Elements.clearAll()
	table.clear(statuses)
end

function Elements.init()
	-- Paused: burns, chills and freezes hold their remaining time.
	Pause.onTick(function(dt)
		for _, s in statuses do
			if s.burnUntil > 0 then
				s.burnUntil += dt
				s.nextBurn += dt
			end
			if s.chillUntil > 0 then
				s.chillUntil += dt
			end
			if s.frozenUntil > 0 then
				s.frozenUntil += dt
			end
		end
	end)
	RunService.Heartbeat:Connect(function()
		if Enemy.frozen or Enemy.paused or Pause.active() then
			return
		end
		local now = os.clock()
		for model, s in statuses do
			if not model.Parent or not Enemy.data(model) then
				statuses[model] = nil
				continue
			end
			if s.burnUntil > 0 then
				if now >= s.burnUntil then
					s.burnUntil = 0
					model:SetAttribute("Burning", nil)
				elseif s.burnDps > 0 and now >= s.nextBurn then
					s.nextBurn = now + burnInterval(s)
					burnTick(s)
				end
			end
			if s.chillUntil > 0 and now >= s.chillUntil then
				s.chillUntil = 0
				model:SetAttribute("Chilled", nil)
			end
			if s.frozenUntil > 0 and now >= s.frozenUntil then
				s.frozenUntil = 0
				model:SetAttribute("Frozen", nil)
			end
		end
	end)
end

return Elements
