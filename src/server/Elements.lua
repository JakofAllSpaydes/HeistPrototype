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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local PlayerState = require(script.Parent.PlayerState)
local Economy = require(script.Parent.Economy)
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

local function chill(model: Model, power: number)
	local s = statusOf(model)
	local now = os.clock()
	local slowPct = math.clamp(Config.CryoSlowPct * power, 0, Config.CryoSlowCap)
	Enemy.slow(model, 1 - slowPct, Config.CryoSlowSec)
	s.chillUntil = now + Config.CryoSlowSec
	model:SetAttribute("Chilled", true)
	-- Stacks inside the window: the Nth freezes.
	local kept = {}
	for _, t in s.chillProcs do
		if now - t <= Config.CryoSlowSec then
			table.insert(kept, t)
		end
	end
	table.insert(kept, now)
	s.chillProcs = kept
	if #kept >= Config.CryoStacksToFreeze then
		s.chillProcs = {}
		local sec = Config.CryoFreezeSec * power
		s.frozenUntil = now + sec
		Enemy.stun(model, sec, Color3.fromHex("BFE6FF"))
		model:SetAttribute("Frozen", true)
	end
end

local function knockback(model: Model, power: number, dir: Vector3?, at: Vector3)
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
		knockback(model, st.concussivePower, dir, at)
	end
end

-- A burn tick on the owner's behalf: kill cash with their CASH GAIN, the Hit juice to them.
local function burnTick(s: Status)
	local model = s.model
	local dmg = math.max(1, math.round(s.burnDps * Config.FieldTickSec))
	local owner = s.burnOwner
	local live = owner ~= nil and owner.Parent ~= nil
	local pos = Enemy.rootPosition(model) or Vector3.zero
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
