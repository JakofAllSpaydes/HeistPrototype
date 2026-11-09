--!strict
-- The fifteen class abilities (Classes.lua), server side. Brief 5 adds INITIATE's Frag (thrown, fused blast),
-- ENGINEER's Overclock (team-wide placeable rate + barricade shields) and SHARPSHOOTER's Eagle Eye (marks).
--   Placeables stand StructurePlaceDistance in front of the player (0: on the spot you stand on): turret, barricade, healing turret, flame
--   turret and oil drum are attackable (HP bar, enemies walk to them and hit them); med bag and claymore are not.
--   Ground fields (med bag, molotov, the fire a broken drum leaves) act on whoever stands in the circle every
--   FieldTickSec. Thrown abilities (flashbang, molotov) arc ThrowDistance over ThrowFlightSec and go off where
--   they land. Self buffs (stim, stim shot, dead eye) live in PlayerState as buffId / buffUntil.
-- Every number is in Config; the owner's ability level scales the Classes.lua `vars` through AbilityGrowth.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Ground = require(Shared.Ground)
local Remotes = require(script.Parent.SlotRemotes)
local Classes = require(Shared.Classes)
local AbilityGrowth = require(Shared.AbilityGrowth)
local PlayerState = require(script.Parent.Parent.PlayerState)
local Stats = require(script.Parent.Parent.Stats)
local Economy = require(script.Parent.Parent.Economy)
local Enemy = require(script.Parent.Enemy)
local Elements = require(script.Parent.Elements)
local Downed = require(script.Parent.Downed)
local Pause = require(script.Parent.Pause)
local Log = require(script.Parent.Parent.Log)
local AllyCallout = require(script.Parent.AllyCallout)
local World = require(script.Parent.World)
local Slot = require(script.Parent.Slot)
local Drones = require(script.Parent.Drones) -- brief 12
local Swarm = require(script.Parent.Swarm) -- brief 12
local Explosion = require(script.Parent.Explosion) -- brief 12: knockback and the explosion feel
local Mastery = require(script.Parent.Mastery) -- Round 29b: BACKDRAFT extends the Inferno

-- Brief 8: the players this run slot looks after (its party; the hub slot: everyone not in a run).
local function mine(): { [Player]: PlayerState.State }
	local out = {}
	for _, p in World.runAudience() do
		out[p] = PlayerState.get(p)
	end
	return out
end

local triageTick: (number) -> () -- below, after the fields and structures it reads

local COLOR = {
	gold = Color3.fromHex("E8B64C"),
	grey = Color3.fromHex("9BA0A8"),
	green = Color3.fromHex("8FE3A1"),
	red = Color3.fromHex("E8554D"),
	fire = Color3.fromRGB(255, 140, 40),
	white = Color3.new(1, 1, 1),
	-- Round 16: the crew's own fire (molotov, burst oil drum) burns blue with a solid rim, so it never reads as the
	-- enemies' orange-and-red patches.
	allyFire = Color3.fromHex(Config.AllyFireColor),
	allyFire2 = Color3.fromHex(Config.AllyFireSecondary),
}

-- Anything that stands in the arena: turret | barricade | healturret | flameturret | oildrum | claymore.
type Structure = {
	kind: string,
	owner: Player,
	model: Model,
	hitPart: BasePart, -- what enemies walk to and hit (attackable kinds)
	attackable: boolean, -- enemies target it, it has an HP bar
	hp: number,
	maxHP: number,
	expiresAt: number,
	fill: Frame?,
	lastTick: number, -- last shot / beam / flame tick
	lastSound: number, -- flame turret: the stream sound is sent this often, not every tick
	head: BasePart?,
	dmg: number, -- turret damage per shot, flame damage per second, claymore blast, drum burn per second
	heal: number, -- healing turret HP per second
	slowMult: number, -- drum fire walk speed multiplier
	armedAt: number, -- claymore: cannot go off before this
	shield: number, -- barricade: Overclock's shield, absorbs damage first (0 = none)
	shieldPart: BasePart?, -- its look
	rate: number, -- the owner's own fire-rate multiplier (ENGINEER I: REINFORCED)
	range: number, -- healing turret reach (DOC I: WIDE NET); claymore blast radius (BLAST RADIUS synergy)
	repair: boolean, -- ENGINEER II: FIELD REPAIR
	triage: boolean, -- healing turret of a DOC II: downed allies in range stand up on their own
	extra: { [string]: any }?, -- brief 12: kind-specific parts (the sentry's barrels and laser)
}

-- A circle on the floor that acts on whoever stands in it every FieldTickSec.
type Field = {
	kind: string, -- medbag | molotov | drumfire
	owner: Player,
	model: Model,
	position: Vector3,
	radius: number,
	expiresAt: number,
	lastTick: number,
	perSec: number, -- heal (med bag) or burn (fire) per second
	slowMult: number, -- enemy walk speed x this while inside (fire)
	shown: { [Player]: number }, -- med bag: heal shown to this player so far (floats once a second)
	shownAt: { [Player]: number },
	tickMult: number, -- the owner's tick-rate multiplier (TORCH I: fire fields tick faster)
	triage: boolean, -- med bag of a DOC II
	hospital: boolean, -- med bag of a DOC III: allies inside deal more damage
}

local Abilities = {}

local folder: Folder
local structures: { [BasePart]: Structure } = {}
local fields: { [Model]: Field } = {}

-- ENGINEER's Overclock: one team-wide window. Every friendly placeable fires / heals `mult` x faster until
-- `untilT` and barricades carry a `shieldHp` shield; placeables put down during it join in.
local overclock = { untilT = 0, mult = 1, shieldHp = 0 }

local function overclocked(): boolean
	return overclock.untilT > Workspace:GetServerTimeNow()
end

-- Rate multiplier the placeable ticks use.
local function rateMult(): number
	return if overclocked() then overclock.mult else 1
end

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function level(state: PlayerState.State, id: string): number
	return PlayerState.abilityLevel(state, id)
end

-- Classes.lua var at the owner's level.
local function grown(id: string, variable: string, base: number, lv: number): number
	return AbilityGrowth.at(id, variable, base, lv)
end

local function hpBar(part: BasePart, color: Color3): Frame
	local gui = Instance.new("BillboardGui")
	gui.Name = "HP"
	gui.Size = UDim2.fromScale(4, 0.5)
	gui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 1.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	gui.Parent = part
	local back = Instance.new("Frame")
	back.BackgroundColor3 = Color3.fromHex("23232B")
	back.BorderSizePixel = 0
	back.Size = UDim2.fromScale(1, 1)
	back.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = back
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = back
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(0.5, 0)
	c2.Parent = fill
	return fill
end

local function placementCFrame(char: Model, distance: number): CFrame
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local base = if root then root.CFrame else char:GetPivot()
	local _, yaw = base:ToEulerAnglesYXZ()
	local flat = CFrame.new(base.Position) * CFrame.Angles(0, yaw, 0)
	local pos = (flat * CFrame.new(0, 0, -distance)).Position
	return CFrame.new(pos.X, Ground.y(pos), pos.Z) * CFrame.Angles(0, yaw, 0)
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

-- Damage one enemy on the owner's behalf: kill cash with the owner's CASH GAIN, the Hit juice to the owner.
-- `hit` says how a kill throws the body (nil: the tick slump, Config.RagdollTickForce).
local function hitEnemy(
	owner: Player,
	model: Model,
	dmg: number,
	position: Vector3,
	secondary: boolean,
	hit: Enemy.Hit?
): boolean
	-- ABILITY DAMAGE (the web's nodes and the POWER boost, additive), then ELITE / BOSS DAMAGE (brief 12: resolver).
	if owner.Parent then
		local ed = Enemy.data(model)
		dmg *= Stats.mult(owner, "abilityDamage")
		if ed and ed.elite then
			dmg *= Stats.mult(owner, "eliteDamage")
		end
		if ed and ed.row.boss == true then
			dmg *= Stats.mult(owner, "bossDamage")
		end
	end
	dmg = math.max(1, math.round(dmg))
	local killed, killCash = Enemy.damage(
		model,
		dmg,
		if owner.Parent then owner else nil,
		hit or { force = Config.RagdollTickForce, tick = true }
	)
	if not owner.Parent then
		return killed
	end
	local state = PlayerState.get(owner)
	local cash = 0
	if killed then
		cash = math.round(killCash * PlayerState.computed(state).cashGain)
		Economy.addCash(state, cash)
	end
	Remotes.Juice:FireClient(owner, "Hit", {
		position = position,
		amount = dmg,
		headshot = false,
		crit = false,
		killed = killed,
		model = model,
		cash = cash,
		secondary = secondary,
		outward = if hit and hit.blast then hit.dir else nil, -- brief 12: blast numbers pop outward
	})
	return killed
end

local function healPlayer(player: Player, amount: number): number
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or amount <= 0 then
		return 0
	end
	local before = hum.Health
	hum.Health = math.min(hum.MaxHealth, hum.Health + amount)
	return hum.Health - before
end

local function headPosition(player: Player): Vector3?
	local char = player.Character
	local head = char and char:FindFirstChild("Head") :: BasePart?
	return if head then head.Position else nil
end

------------------------------------------------------------------ Overclock looks
local AMBER = Color3.fromHex("E8B64C")

local function setGlow(s: Structure, on: boolean)
	local existing = s.model:FindFirstChild("OverclockGlow")
	if on and not existing then
		local h = Instance.new("Highlight")
		h.Name = "OverclockGlow"
		h.FillColor = AMBER
		h.FillTransparency = 0.65
		h.OutlineColor = AMBER
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = s.model
	elseif not on and existing then
		existing:Destroy()
	end
end

local function setShield(s: Structure, hp: number)
	s.shield = math.max(0, hp)
	local look = s.shieldPart
	if s.shield <= 0 then
		if look then
			look:Destroy()
			s.shieldPart = nil
		end
		s.hitPart:SetAttribute("ShieldHP", nil)
		return
	end
	s.hitPart:SetAttribute("ShieldHP", s.shield)
	if not look then
		local p = Instance.new("Part")
		p.Name = "Shield"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Size = s.hitPart.Size + Vector3.new(0.6, 0.6, 0.6)
		p.CFrame = s.hitPart.CFrame
		p.Color = AMBER
		p.Material = Enum.Material.ForceField
		p.Transparency = 0.2
		p.Parent = s.model
		s.shieldPart = p
	end
end

-- A placeable joins the running Overclock: the glow, and a shield on a barricade.
local function joinOverclock(s: Structure)
	setGlow(s, true)
	if s.kind == "barricade" then
		setShield(s, overclock.shieldHp)
	end
end

local function endOverclock()
	overclock.untilT = 0
	overclock.mult = 1
	World.crewOverclockUntil = 0
	-- Round 28e: the caster's own gun boost ends too, so every state recomputes.
	for _, state in mine() do
		state.overclockGunMult = 1
	end
	PlayerState.markAllDirty()
	for _, s in structures do
		setGlow(s, false)
		if s.shield > 0 then
			setShield(s, 0)
		end
	end
	World.fireRun("OverclockEnd", {})
end

------------------------------------------------------------------ Structures
local function register(s: Structure)
	structures[s.hitPart] = s
	-- Players walk through placeables; enemies are blocked by them.
	for _, p in s.model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CollisionGroup = "Structure"
		end
	end
	if s.attackable then
		s.hitPart:SetAttribute("StructureHP", s.hp)
		s.hitPart:SetAttribute("StructureMaxHP", s.maxHP)
	end
	if overclocked() then
		joinOverclock(s)
	end
end

local placeField -- forward: a broken oil drum lights the floor

local function destroyStructure(s: Structure, reason: string)
	if not structures[s.hitPart] then
		return
	end
	structures[s.hitPart] = nil
	World.fireRun("StructureGone", { kind = s.kind, position = s.hitPart.Position, reason = reason })
	for _, p in s.model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanCollide = false
			TweenService:Create(p, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Size = Vector3.new(0.05, 0.05, 0.05),
				Transparency = 1,
			}):Play()
		end
	end
	task.delay(0.3, function()
		s.model:Destroy()
	end)
	Log.event("Ability", "%s's %s %s", s.owner.Name, s.kind, reason)
	-- An oil drum that enemies break (not one that times out) burns where it stood.
	if s.kind == "oildrum" and reason == "destroyed" then
		placeField(
			"drumfire",
			s.owner,
			s.hitPart.Position,
			Config.OilDrumBurnRadius,
			Config.OilDrumBurnSec,
			s.dmg,
			s.slowMult
		)
		World.fireRun(
			"Blast",
			{ position = s.hitPart.Position, radius = Config.OilDrumBurnRadius, color = COLOR.allyFire }
		)
	end
end

-- Enemies call this through Enemy.onStructureHit.
function Abilities.damageStructure(hit: BasePart, amount: number)
	local s = structures[hit]
	if not s or not s.attackable then
		return
	end
	-- Overclock's shield takes the hit first.
	if s.shield > 0 then
		local absorbed = math.min(s.shield, amount)
		setShield(s, s.shield - absorbed)
		amount -= absorbed
		if amount <= 0 then
			World.fireRun("StructureHit", { kind = s.kind, position = hit.Position, shield = true })
			return
		end
	end
	s.hp -= amount
	hit:SetAttribute("StructureHP", s.hp)
	local fill = s.fill
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(s.hp / s.maxHP, 0, 1), 1)
	end
	World.fireRun("StructureHit", { kind = s.kind, position = hit.Position })
	if s.hp <= 0 then
		destroyStructure(s, "destroyed")
	end
end

-- Parts enemies may target: the attackable structures.
function Abilities.targets(): { BasePart }
	local out = {}
	for hit, s in structures do
		if s.attackable then
			table.insert(out, hit)
		end
	end
	return out
end

local function newStructure(kind: string, owner: Player, model: Model, hit: BasePart, lifetime: number): Structure
	return {
		kind = kind,
		owner = owner,
		model = model,
		hitPart = hit,
		attackable = false,
		hp = 1,
		maxHP = 1,
		-- Round 18d: a lifetime of 0 (every placeable today) stands until destroyed.
		expiresAt = if lifetime > 0 then now() + lifetime else math.huge,
		fill = nil,
		lastTick = 0,
		lastSound = 0,
		head = nil,
		dmg = 0,
		heal = 0,
		slowMult = 1,
		armedAt = 0,
		shield = 0,
		shieldPart = nil,
		rate = 1,
		range = 0,
		repair = false,
		triage = false,
		extra = nil,
	}
end

-- Brief 12: one ally radio line per player per AbilityCalloutCooldownSec for the new deployables ([Copy: TBA]).
local lastCallout: { [Player]: number } = setmetatable({} :: any, { __mode = "k" })
local function abilityCallout(player: Player, event: string)
	local t = os.clock()
	if t - (lastCallout[player] or -math.huge) < Config.AbilityCalloutCooldownSec then
		return
	end
	lastCallout[player] = t
	AllyCallout.send(player, event)
end

-- Every placeable goes through here: the owner's ENGINEER passives, then the registry and the juice.
local function placed(s: Structure, color: Color3, radius: number?)
	local os_ = PlayerState.get(s.owner)
	if PlayerState.passive(os_, "ENGINEER", 1) then
		s.rate = 1 + Config.EngineerPlaceablePct
		if s.attackable then
			s.hp = math.round(s.hp * (1 + Config.EngineerPlaceablePct))
			s.maxHP = s.hp
		end
	end
	s.repair = s.attackable and PlayerState.passive(os_, "ENGINEER", 2)
	register(s)
	-- Round 30d: the model goes along so clients can play its drop-in (WorldFx); it is live where it stands at once.
	World.fireRun(
		"StructurePlaced",
		{ kind = s.kind, position = s.hitPart.Position, color = color, radius = radius, model = s.model }
	)
end

-- Turret body shared by the three turret kinds: base (the hit part), head and a welded barrel.
local function buildTurret(cf: CFrame, name: string, headColor: Color3): (Model, BasePart, BasePart, BasePart)
	local model = Instance.new("Model")
	model.Name = name
	local base = part({
		Name = "Base",
		Size = Vector3.new(2.4, 1, 2.4),
		CFrame = cf * CFrame.new(0, 0.5, 0),
		Color = Color3.fromRGB(70, 72, 80),
		Material = Enum.Material.Metal,
		Parent = model,
	})
	local head = part({
		Name = "Head",
		Size = Vector3.new(1.4, 1.2, 1.4),
		CFrame = cf * CFrame.new(0, 1.6, 0),
		CanCollide = false,
		Color = headColor,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	local barrel = part({
		Name = "Barrel",
		Size = Vector3.new(0.35, 0.35, 1.8),
		CFrame = head.CFrame * CFrame.new(0, 0, -1.2),
		CanCollide = false,
		Color = Color3.fromRGB(40, 40, 46),
		Material = Enum.Material.Metal,
		Parent = model,
	})
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = barrel
	weld.Parent = barrel
	model.PrimaryPart = base
	model.Parent = folder
	return model, base, head, barrel
end

local function aimHead(head: BasePart, at: Vector3)
	head.CFrame = CFrame.lookAt(head.Position, Vector3.new(at.X, head.Position.Y, at.Z))
end

local function muzzleOf(head: BasePart): Vector3
	return (head.CFrame * CFrame.new(0, 0, -2.1)).Position
end

------------------------------------------------------------------ INITIATE
local function placeTurret(player: Player, state: PlayerState.State, char: Model)
	local cf = placementCFrame(char, Config.StructurePlaceDistance)
	local model, base, head = buildTurret(cf, "Turret", COLOR.gold)
	local lv = level(state, "turret")
	local s = newStructure("turret", player, model, base, Config.TurretLifetime)
	s.attackable = true
	local pw = PlayerState.abilityPower(state)
	s.hp = math.round(grown("turret", "Hp", Config.TurretHP, lv) * pw)
	s.maxHP = s.hp
	-- TURRET DAMAGE (ENGINEER synergy card).
	s.dmg = grown("turret", "Damage", Config.TurretDmg, lv) * pw * PlayerState.computed(state).turretDmgMult
	s.range = Config.TurretRange * Stats.mult(player, "turretRange") -- brief 12: a softcap stat
	s.head = head
	s.fill = hpBar(base, COLOR.gold)
	placed(s, COLOR.gold)
	Log.event("Ability", "%s placed a turret (LV %d: %d HP, %d dmg)", player.Name, lv, s.hp, math.round(s.dmg))
end

local function placeBarricade(player: Player, state: PlayerState.State, char: Model)
	local cf = placementCFrame(char, Config.StructurePlaceDistance)
	local model = Instance.new("Model")
	model.Name = "Barricade"
	local wall = part({
		Name = "Wall",
		Size = Config.BarricadeSize,
		CFrame = cf * CFrame.new(0, Config.BarricadeSize.Y / 2, 0),
		Color = Color3.fromRGB(110, 112, 120),
		Material = Enum.Material.Metal,
		Parent = model,
	})
	part({
		Name = "Stripe",
		Size = Vector3.new(Config.BarricadeSize.X, 0.4, Config.BarricadeSize.Z + 0.05),
		CFrame = wall.CFrame * CFrame.new(0, Config.BarricadeSize.Y / 2 - 0.4, 0),
		CanCollide = false,
		Color = COLOR.gold,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	model.PrimaryPart = wall
	model.Parent = folder
	local lv = level(state, "barricade")
	local s = newStructure("barricade", player, model, wall, Config.BarricadeLifetime)
	s.attackable = true
	s.hp = math.round(grown("barricade", "Hp", Config.BarricadeHP, lv) * PlayerState.abilityPower(state))
	s.maxHP = s.hp
	s.fill = hpBar(wall, COLOR.grey)
	placed(s, COLOR.gold)
	Log.event("Ability", "%s placed a barricade (LV %d: %d HP)", player.Name, lv, s.hp)
end

-- A self buff: PlayerState.buffFor(id) supplies the multipliers while buffUntil runs.
local function startBuff(player: Player, state: PlayerState.State, id: string, duration: number, heal: number)
	state.buffId = id
	state.buffUntil = now() + duration
	local healed = healPlayer(player, heal)
	PlayerState.applyCharacterStats(state)
	state.dirty = true
	local char = player.Character
	if char then
		char:SetAttribute("ActiveBuff", id)
	end
	Remotes.Juice:FireClient(player, "StimStart", { id = id, duration = duration, until_ = state.buffUntil })
	local b = PlayerState.buffFor(state, id)
	Log.event(
		"Ability",
		"%s used %s (LV %d: +%d HP, %ds, x%.2f dmg, x%.2f speed, x%.2f fire rate, x%.2f reload)",
		player.Name,
		id,
		level(state, id),
		math.round(healed),
		math.round(duration),
		b.damageMult,
		b.moveSpeedMult,
		b.fireRateMult,
		b.reloadSpeedMult
	)
end

-- INITIATE's Adrenaline (ability id "stim", kept so saved ability levels carry over): fire rate, reload and move.
-- No heal (that is DOC's stim shot).
local function adrenaline(player: Player, state: PlayerState.State, char: Model)
	-- PATCHED UP (INITIATE I): it heals too.
	local heal = 0
	if PlayerState.passive(state, "INITIATE", 1) then
		local hum = char:FindFirstChildOfClass("Humanoid")
		heal = if hum then hum.MaxHealth * Config.StimMasteryHealPct else 0
	end
	state.stimExtended = 0
	startBuff(player, state, "stim", Config.AdrenalineDuration * PlayerState.abilityDurationAmp(state), heal)
end

------------------------------------------------------------------ Fields (med bag, molotov, drum fire)
placeField = function(
	kind: string,
	owner: Player,
	position: Vector3,
	radius: number,
	lifetime: number,
	perSec: number,
	slowMult: number
)
	local isFire = kind ~= "medbag"
	local color = if isFire then COLOR.allyFire else COLOR.green
	local model = Instance.new("Model")
	model.Name = if isFire then "Fire" else "MedBag"
	local disc = part({
		Name = "Disc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, radius * 2, radius * 2),
		CFrame = CFrame.new(position.X, Ground.y(position) + 0.1, position.Z) * CFrame.Angles(0, 0, math.rad(90)),
		CanCollide = false,
		CanQuery = false,
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = if isFire then Config.AllyFireDiscTransparency else 0.7,
		Parent = model,
	})
	-- A solid rim on every friendly field: the edge of the area reads at a glance, and the enemies' fire has none.
	-- Built from short segments round the circle (a filled disc underneath would light the whole patch).
	local rimW = Config.AllyFieldRimStuds
	local segments = Config.AllyFieldRimSegments
	local segLen = 2 * math.pi * radius / segments * 1.08 -- a little overlap so the ring has no gaps
	for i = 1, segments do
		local a = (i - 0.5) / segments * math.pi * 2
		part({
			Name = "Rim",
			Size = Vector3.new(rimW, 0.12, segLen),
			CFrame = CFrame.new(
				position.X + math.cos(a) * radius,
				Ground.y(position) + 0.14,
				position.Z + math.sin(a) * radius
			) * CFrame.Angles(0, -a, 0),
			CanCollide = false,
			CanQuery = false,
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = Config.AllyFieldRimTransparency,
			Parent = model,
		})
	end
	if isFire then
		-- One big flame in the middle and four round the edge, so the circle reads as burning.
		for _, offset in
			{
				Vector3.zero,
				Vector3.new(radius * 0.6, 0, 0),
				Vector3.new(-radius * 0.6, 0, 0),
				Vector3.new(0, 0, radius * 0.6),
				Vector3.new(0, 0, -radius * 0.6),
			}
		do
			local anchor = part({
				Name = "Flame",
				Size = Vector3.new(0.2, 0.2, 0.2),
				CFrame = CFrame.new(position.X, Ground.y(position) + 0.3, position.Z) * CFrame.new(offset),
				CanCollide = false,
				CanQuery = false,
				Transparency = 1,
				Parent = model,
			})
			local fire = Instance.new("Fire")
			fire.Size = if offset == Vector3.zero then radius * 1.4 else radius * 0.8
			fire.Heat = 12
			fire.Color = COLOR.allyFire
			fire.SecondaryColor = COLOR.allyFire2
			fire.Parent = anchor
		end
	else
		-- The bag (Round 30d: a proper kit, not a tiny box): a green case with a dark lid band, a carry handle and a
		-- white cross on the top and both long sides.
		local bag = part({
			Name = "Bag",
			Size = Vector3.new(2.2, 1.3, 1.5),
			CFrame = CFrame.new(position.X, Ground.y(position) + 0.65, position.Z),
			CanCollide = false,
			CanQuery = false,
			Color = COLOR.green,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
		part({
			Name = "Band",
			Size = Vector3.new(2.24, 0.16, 1.54),
			CFrame = bag.CFrame * CFrame.new(0, 0.3, 0),
			CanCollide = false,
			CanQuery = false,
			Color = Color3.fromRGB(30, 34, 40),
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
		for _, sx in { -1, 1 } do
			part({
				Name = "HandlePost",
				Size = Vector3.new(0.14, 0.4, 0.14),
				CFrame = bag.CFrame * CFrame.new(sx * 0.45, 0.85, 0),
				CanCollide = false,
				CanQuery = false,
				Color = Color3.fromRGB(30, 34, 40),
				Material = Enum.Material.SmoothPlastic,
				Parent = model,
			})
		end
		part({
			Name = "Handle",
			Size = Vector3.new(1.04, 0.14, 0.18),
			CFrame = bag.CFrame * CFrame.new(0, 1.05, 0),
			CanCollide = false,
			CanQuery = false,
			Color = Color3.fromRGB(30, 34, 40),
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
		-- Crosses: on the top (flat) and on each long side (standing).
		local faces = {
			{ CFrame.new(0, 0.66, 0), Vector3.new(0.9, 0.05, 0.28), Vector3.new(0.28, 0.05, 0.9) },
			{ CFrame.new(0, 0, 0.76), Vector3.new(0.7, 0.22, 0.05), Vector3.new(0.22, 0.7, 0.05) },
			{ CFrame.new(0, 0, -0.76), Vector3.new(0.7, 0.22, 0.05), Vector3.new(0.22, 0.7, 0.05) },
		}
		for _, f in faces do
			for i = 2, 3 do
				part({
					Name = "Cross",
					Size = f[i] :: Vector3,
					CFrame = bag.CFrame * (f[1] :: CFrame),
					CanCollide = false,
					CanQuery = false,
					Color = COLOR.white,
					Material = Enum.Material.Neon,
					Parent = model,
				})
			end
		end
	end
	model.PrimaryPart = disc
	model.Parent = folder
	local os_ = PlayerState.get(owner)
	fields[model] = {
		kind = kind,
		owner = owner,
		model = model,
		position = Ground.at(position),
		radius = radius,
		expiresAt = now() + lifetime,
		lastTick = 0,
		perSec = perSec,
		slowMult = slowMult,
		shown = {},
		shownAt = {},
		tickMult = if isFire and PlayerState.passive(os_, "TORCH", 1) then Config.TorchBurnRateMult else 1,
		triage = not isFire and PlayerState.passive(os_, "DOC", 2),
		hospital = not isFire and PlayerState.passive(os_, "DOC", 3),
	}
	Log.event(
		"Ability",
		"%s's %s lit at (%d, %d): r%d, %d/s, %ds",
		owner.Name,
		kind,
		math.round(position.X),
		math.round(position.Z),
		radius,
		math.round(perSec),
		lifetime
	)
	return model -- Round 30d: the med bag's placement juice drops it in
end

local function removeField(f: Field, reason: string)
	if not fields[f.model] then
		return
	end
	fields[f.model] = nil
	for _, p in f.model:GetDescendants() do
		if p:IsA("BasePart") then
			TweenService:Create(p, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Transparency = 1,
			}):Play()
		elseif p:IsA("Fire") then
			p.Enabled = false
		end
	end
	task.delay(0.45, function()
		f.model:Destroy()
	end)
	Log.event("Ability", "%s's %s %s", f.owner.Name, f.kind, reason)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

local function fieldTick(f: Field, t: number)
	-- Overclock: the med bag (a placeable) heals faster; fire fields tick at their owner's rate (TORCH I).
	local interval = if f.kind == "medbag"
		then Config.FieldTickSec / rateMult()
		else Config.FieldTickSec / math.max(0.1, f.tickMult)
	if t - f.lastTick < interval then
		return
	end
	f.lastTick = t
	local amount = f.perSec * Config.FieldTickSec
	if f.kind == "medbag" then
		for _, player in World.runAudience() do
			local state = PlayerState.get(player)
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root or not PlayerState.isStanding(state) then
				continue
			end
			if flatDistance(root.Position, f.position) > f.radius then
				continue
			end
			if f.hospital then
				state.fieldHospitalUntil = t + interval + 0.3 -- FIELD HOSPITAL: +damage while inside
			end
			local healed = healPlayer(player, amount)
			if healed <= 0 then
				continue
			end
			-- Floats once a second per player, so the circle stays quiet.
			f.shown[player] = (f.shown[player] or 0) + healed
			if t - (f.shownAt[player] or 0) >= 1 then
				f.shownAt[player] = t
				local shown = math.round(f.shown[player])
				f.shown[player] = 0
				if shown > 0 then
					local head = headPosition(player)
					if head then
						Remotes.Juice:FireClient(player, "Heal", { position = head, amount = shown })
					end
				end
			end
		end
	else
		for _, model in Enemy.within(f.position, f.radius) do
			local ep = Enemy.rootPosition(model)
			if not ep or flatDistance(ep, f.position) > f.radius then
				continue
			end
			Enemy.slow(model, f.slowMult, Config.FieldTickSec + 0.25)
			Elements.markBurning(model, f.owner, interval + 0.4) -- the burning look, and BACKDRAFT's credit
			hitEnemy(f.owner, model, amount, ep, true)
		end
	end
end

------------------------------------------------------------------ Thrown
-- Aim assist (Round 16). The client sends what the cursor is on: the hit point, the camera ray's origin and the
-- part it hit. In order: the enemy the cursor is on; else the enemy closest to the camera ray (within
-- ThrowAssistRayStuds of it, out to the hit point), so a near miss at head height that carried on to the far wall
-- still locks the enemy it passed; else the enemy nearest the hit point within ThrowAssistRadius. Only enemies
-- within ThrowMaxRange of the thrower count.
local assistAim: { origin: Vector3?, hit: Instance? } = {} -- set by Abilities.use for the throw it starts

local function segmentDistance(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local len2 = ab:Dot(ab)
	local t = if len2 > 0 then math.clamp((p - a):Dot(ab) / len2, 0, 1) else 0
	return (a + ab * t - p).Magnitude
end

local function assistTarget(from: Vector3, aim: Vector3): Model?
	if Config.ThrowAssistRadius <= 0 then
		return nil
	end
	local function inRange(model: Model): boolean
		local ep = Enemy.rootPosition(model)
		return ep ~= nil and flatDistance(ep, from) <= Config.ThrowMaxRange
	end
	local hit = assistAim.hit
	if typeof(hit) == "Instance" then
		local model = Enemy.fromPart(hit)
		if model and inRange(model) then
			return model
		end
	end
	local origin = assistAim.origin
	local best: Model? = nil
	local bestD = math.huge
	if typeof(origin) == "Vector3" and (origin - from).Magnitude <= Config.ThrowAssistOriginSlack then
		for _, model in Enemy.within(from, Config.ThrowMaxRange) do
			local d = Enemy.data(model)
			if d and inRange(model) then
				local dist = math.min(
					segmentDistance(d.root.Position, origin, aim),
					segmentDistance(d.head.Position, origin, aim)
				)
				if dist <= Config.ThrowAssistRayStuds and dist < bestD then
					bestD = dist
					best = model
				end
			end
		end
		if best then
			return best
		end
	end
	for _, model in Enemy.within(aim, Config.ThrowAssistRadius + 6) do
		local ep = Enemy.rootPosition(model)
		if ep and inRange(model) then
			local dist = flatDistance(ep, aim)
			if dist <= Config.ThrowAssistRadius and dist < bestD then
				bestD = dist
				best = model
			end
		end
	end
	return best
end

-- A small part arcs from the hand to the floor at the cursor's point (`aim`, clamped to ThrowMaxRange from the
-- player; ThrowDistance ahead when none came) over ThrowFlightSec, then `onLand` runs there.
-- Round 16 aim assist: the enemy nearest the aim point (within ThrowAssistRadius of it, and in range) becomes the
-- target, and the throw homes on it while in the air, so an aimed throw never lands on empty floor beside a crowd.
local function throw(char: Model, color: Color3, burning: boolean, onLand: (Vector3) -> (), aim: Vector3?)
	local hand = (char:FindFirstChild("RightHand") or char:FindFirstChild("HumanoidRootPart")) :: BasePart?
	local target = placementCFrame(char, Config.ThrowDistance).Position
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if aim and root then
		local offset = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
		if offset.Magnitude > Config.ThrowMaxRange then
			offset = offset.Unit * Config.ThrowMaxRange
		end
		target = root.Position + offset
	end
	local locked: Model? = if aim and root then assistTarget(root.Position, aim) else nil
	do
		local lockedPos = locked and Enemy.rootPosition(locked)
		if lockedPos then
			target = lockedPos
		end
	end
	local from = if hand then hand.Position else target + Vector3.new(0, 3, 0)
	local to = Vector3.new(target.X, Ground.y(target) + 0.4, target.Z)
	World.fireRun("ThrowLaunch", { position = from })
	local p = part({
		Name = "Thrown",
		Size = Vector3.new(0.7, 0.7, 0.7),
		CFrame = CFrame.new(from),
		CanCollide = false,
		CanQuery = false,
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	if burning then
		local fire = Instance.new("Fire")
		fire.Size = 2
		fire.Heat = 6
		fire.Parent = p
	end
	-- A longer throw arcs higher (ThrowArcPerStud), so a far frag reads as a lob, not a flat line.
	local span = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
	local peak = math.max(1.5, span * Config.ThrowArcPerStud)
	task.spawn(function()
		-- ThrowFlightSec up to ThrowFlightRefStuds away, then longer in proportion, so far throws do not snap.
		local flight = math.max(0.05, Config.ThrowFlightSec * math.max(1, span / Config.ThrowFlightRefStuds))
		local elapsed = 0
		while elapsed < flight do
			elapsed += RunService.Heartbeat:Wait()
			local a = math.clamp(elapsed / flight, 0, 1)
			-- Homing: the landing point follows the locked enemy until it lands (or the enemy dies).
			local lp = locked and Enemy.rootPosition(locked)
			if lp then
				to = Vector3.new(lp.X, Ground.y(lp) + 0.4, lp.Z)
			end
			local pos = from:Lerp(to, a) + Vector3.new(0, peak * 4 * a * (1 - a), 0)
			p.CFrame = CFrame.new(pos) * CFrame.Angles(a * 6, a * 4, 0)
		end
		p:Destroy()
		onLand(to)
	end)
end

------------------------------------------------------------------ DOC
local function stimShot(player: Player, state: PlayerState.State, _char: Model)
	startBuff(
		player,
		state,
		"stimshot",
		Config.StimShotDuration * PlayerState.abilityDurationAmp(state),
		grown("stimshot", "Heal", Config.StimShotHeal, level(state, "stimshot"))
			* PlayerState.abilityPower(state)
			* PlayerState.computed(state).healMult -- HEALING (DOC synergy card)
	)
end

local function placeMedBag(player: Player, state: PlayerState.State, char: Model)
	local lv = level(state, "medbag")
	local pos = placementCFrame(char, Config.StructurePlaceDistance).Position
	-- WIDE NET (DOC I) and FIELD HOSPITAL (DOC III) widen it; FIELD HOSPITAL heals harder.
	local radius = Config.MedBagRadius
	local heal = grown("medbag", "HealPerSec", Config.MedBagHealPerSec, lv)
		* PlayerState.abilityPower(state)
		* PlayerState.computed(state).healMult -- HEALING (DOC synergy card)
	if PlayerState.passive(state, "DOC", 1) then
		radius *= 1 + Config.DocReachPct
	end
	if PlayerState.passive(state, "DOC", 3) then
		radius *= Config.FieldHospitalRadiusMult
		heal *= Config.FieldHospitalHealMult
	end
	local model = placeField("medbag", player, pos, radius, Config.MedBagLifetime, heal, 1)
	-- Round 30d: like every placeable, the kit drops in (the clients play it from the model).
	World.fireRun(
		"StructurePlaced",
		{ kind = "medbag", position = pos, color = COLOR.green, radius = radius, model = model }
	)
end

local function placeHealTurret(player: Player, state: PlayerState.State, char: Model)
	local cf = placementCFrame(char, Config.StructurePlaceDistance)
	local model, base, head = buildTurret(cf, "HealTurret", COLOR.green)
	local lv = level(state, "healturret")
	local s = newStructure("healturret", player, model, base, Config.HealTurretLifetime)
	s.attackable = true
	local pw = PlayerState.abilityPower(state)
	s.hp = math.round(grown("healturret", "Hp", Config.HealTurretHP, lv) * pw)
	s.maxHP = s.hp
	s.heal = grown("healturret", "BeamHeal", Config.HealTurretBeamHeal, lv) * pw * PlayerState.computed(state).healMult
	s.range = Config.HealTurretRange * (if PlayerState.passive(state, "DOC", 1) then 1 + Config.DocReachPct else 1)
	s.triage = PlayerState.passive(state, "DOC", 2)
	s.head = head
	s.fill = hpBar(base, COLOR.green)
	placed(s, COLOR.green)
	Log.event("Ability", "%s placed a healing turret (LV %d: %d HP, %.1f HP/s)", player.Name, lv, s.hp, s.heal)
end

-- The hurt teammate in range with the lowest HP share.
local function lowestTeammate(from: Vector3, range: number): Player?
	local best: Player? = nil
	local bestShare = 1
	for _, player in World.runAudience() do
		local state = PlayerState.get(player)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not root or not hum or not PlayerState.isStanding(state) then
			continue
		end
		if (root.Position - from).Magnitude > range then
			continue
		end
		local share = hum.Health / math.max(1, hum.MaxHealth)
		if share < bestShare then
			bestShare = share
			best = player
		end
	end
	return best
end

local function healTurretTick(s: Structure, t: number)
	if t - s.lastTick < Config.HealTurretTickSec / (rateMult() * s.rate) then
		return
	end
	local head = s.head
	if not head then
		return
	end
	local target = lowestTeammate(head.Position, if s.range > 0 then s.range else Config.HealTurretRange)
	if not target then
		return
	end
	local at = headPosition(target)
	if not at then
		return
	end
	s.lastTick = t
	aimHead(head, at)
	local healed = healPlayer(target, s.heal * Config.HealTurretTickSec)
	World.fireRun(
		"AbilityBeam",
		{ from = muzzleOf(head), to = at, color = COLOR.green, life = Config.HealTurretTickSec }
	)
	if healed >= 0.5 then
		Remotes.Juice:FireClient(target, "Heal", { position = at, amount = math.round(healed) })
	end
end

------------------------------------------------------------------ SHARPSHOOTER
local function placeClaymore(player: Player, state: PlayerState.State, char: Model)
	local cf = placementCFrame(char, Config.StructurePlaceDistance)
	local model = Instance.new("Model")
	model.Name = "Claymore"
	local body = part({
		Name = "Body",
		Size = Vector3.new(1.2, 0.7, 0.3),
		CFrame = cf * CFrame.new(0, 0.5, 0),
		CanCollide = false,
		CanQuery = false,
		Color = Color3.fromRGB(70, 90, 60),
		Material = Enum.Material.Metal,
		Parent = model,
	})
	for _, x in { -0.4, 0.4 } do
		part({
			Name = "Leg",
			Size = Vector3.new(0.1, 0.5, 0.1),
			CFrame = cf * CFrame.new(x, 0.25, 0),
			CanCollide = false,
			CanQuery = false,
			Color = Color3.fromRGB(40, 40, 46),
			Material = Enum.Material.Metal,
			Parent = model,
		})
	end
	part({
		Name = "Light",
		Size = Vector3.new(0.2, 0.2, 0.1),
		CFrame = body.CFrame * CFrame.new(0, 0.2, -0.18),
		CanCollide = false,
		CanQuery = false,
		Color = COLOR.red,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	model.PrimaryPart = body
	model.Parent = folder
	local lv = level(state, "claymore")
	local s = newStructure("claymore", player, model, body, Config.ClaymoreLifetime)
	s.dmg = grown("claymore", "ClaymoreDamage", Config.ClaymoreDamage, lv)
		* PlayerState.abilityPower(state)
		* PlayerState.computed(state).explosiveDmgMult -- DEMOLITION (explosive synergy)
	s.range = Config.ClaymoreBlastRadius * PlayerState.computed(state).areaMult -- brief 12: the area stat
	s.armedAt = now() + Config.ClaymoreArmSec
	placed(s, Color3.fromHex("4D9FE8"), 3)
	Log.event("Ability", "%s planted a claymore (LV %d: %d dmg)", player.Name, lv, math.round(s.dmg))
end

local function claymoreTick(s: Structure, t: number)
	if t < s.armedAt then
		return
	end
	local pos = s.hitPart.Position
	if not Enemy.nearest(pos, Config.ClaymoreTriggerRadius, nil) then
		return
	end
	local radius = if s.range > 0 then s.range else Config.ClaymoreBlastRadius
	local n = Abilities.explode(s.owner, pos, radius, s.dmg, COLOR.red)
	Log.event("Ability", "%s's claymore went off: %d hit", s.owner.Name, n)
	destroyStructure(s, "detonated")
end

local function deadEye(player: Player, state: PlayerState.State, _char: Model)
	-- DEAD EYE TIME (SHARPSHOOTER synergy card).
	startBuff(
		player,
		state,
		"deadeye",
		Config.DeadEyeDuration * PlayerState.computed(state).deadEyeTimeMult * PlayerState.abilityDurationAmp(state),
		0
	)
end

local function throwFlashbang(player: Player, state: PlayerState.State, char: Model, aim: Vector3?)
	local lv = level(state, "flashbang")
	-- Round 25: ABILITY POWER widens the flash and lengthens the stun (soft shares, AbilityPower*Share).
	local radius = grown("flashbang", "FlashRadius", Config.FlashRadius, lv) * PlayerState.abilityRadiusAmp(state)
	local stunSec = grown("flashbang", "StunDuration", Config.StunDuration, lv) * PlayerState.abilityDurationAmp(state)
	throw(char, COLOR.grey, false, function(pos: Vector3)
		local victims = Enemy.within(pos, radius)
		for _, model in victims do
			Enemy.stun(model, stunSec)
		end
		World.fireRun("Blast", { position = pos, radius = radius, color = COLOR.white, shake = 0.2, pitch = 1.8 })
		Log.event("Ability", "%s's flashbang: %d stunned for %.1fs (r%d)", player.Name, #victims, stunSec, radius)
	end, aim)
end

------------------------------------------------------------------ TORCH
local function throwMolotov(player: Player, state: PlayerState.State, char: Model, aim: Vector3?)
	local lv = level(state, "molotov")
	local burn = grown("molotov", "BurnPerSec", Config.MolotovBurnPerSec, lv)
		* PlayerState.abilityPower(state)
		* PlayerState.computed(state).fireAbilityMult -- ACCELERANT (TORCH synergy card)
	local slowPct = math.min(90, grown("molotov", "MoveSlowPct", Config.MolotovMoveSlowPct, lv))
	local poolR = Config.MolotovRadius * Stats.mult(player, "area") -- brief 12: the area stat
	throw(char, COLOR.allyFire, true, function(pos: Vector3)
		placeField("molotov", player, pos, poolR, Config.MolotovLifetime, burn, 1 - slowPct / 100)
		World.fireRun("Blast", { position = pos, radius = poolR, color = COLOR.allyFire, shake = 0.1, pitch = 1.2 })
	end, aim)
end

local function placeFlameTurret(player: Player, state: PlayerState.State, char: Model)
	local cf = placementCFrame(char, Config.StructurePlaceDistance)
	local model, base, head, barrel = buildTurret(cf, "FlameTurret", COLOR.red)
	barrel.Size = Vector3.new(0.5, 0.5, 1.6)
	local pilot = Instance.new("Fire")
	pilot.Size = 1.5
	pilot.Heat = 4
	pilot.Parent = barrel
	local lv = level(state, "flameturret")
	local s = newStructure("flameturret", player, model, base, Config.FlameTurretLifetime)
	s.attackable = true
	local pw = PlayerState.abilityPower(state)
	s.hp = math.round(grown("flameturret", "Hp", Config.FlameTurretHP, lv) * pw)
	s.maxHP = s.hp
	s.dmg = grown("flameturret", "FlameDps", Config.FlameTurretDps, lv)
		* pw
		* PlayerState.computed(state).fireAbilityMult
	s.head = head
	s.range = Config.FlameTurretRange * Stats.mult(player, "area") -- brief 12: the cone's reach is area
	s.fill = hpBar(base, COLOR.red)
	placed(s, COLOR.fire)
	Log.event("Ability", "%s placed a flame turret (LV %d: %d HP, %d dps)", player.Name, lv, s.hp, math.round(s.dmg))
end

local function flameTurretTick(s: Structure, t: number)
	if t - s.lastTick < Config.FlameTurretTickSec / (rateMult() * s.rate) then
		return
	end
	local head = s.head
	if not head then
		return
	end
	local target = Enemy.nearest(head.Position, if s.range > 0 then s.range else Config.FlameTurretRange, nil)
	if not target then
		return
	end
	local tp = Enemy.rootPosition(target)
	if not tp then
		return
	end
	s.lastTick = t
	aimHead(head, tp)
	local sound = t - s.lastSound >= 1
	if sound then
		s.lastSound = t
	end
	World.fireRun("AbilityBeam", {
		from = muzzleOf(head),
		to = tp,
		color = COLOR.fire,
		life = Config.FlameTurretTickSec,
		sound = if sound then "flame" else nil,
	})
	Elements.markBurning(target, s.owner, Config.FlameTurretTickSec + 0.4)
	hitEnemy(s.owner, target, s.dmg * Config.FlameTurretTickSec, tp, true)
end

local function placeOilDrum(player: Player, state: PlayerState.State, char: Model)
	local cf = placementCFrame(char, Config.StructurePlaceDistance)
	local model = Instance.new("Model")
	model.Name = "OilDrum"
	local drum = part({
		Name = "Drum",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3.2, 2.6, 2.6),
		CFrame = cf * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(120, 50, 40),
		Material = Enum.Material.Metal,
		Parent = model,
	})
	for _, y in { -1.0, 0, 1.0 } do
		part({
			Name = "Ring",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.15, 2.75, 2.75),
			CFrame = drum.CFrame * CFrame.new(y, 0, 0),
			CanCollide = false,
			CanQuery = false,
			Color = COLOR.fire,
			Material = Enum.Material.Neon,
			Parent = model,
		})
	end
	model.PrimaryPart = drum
	model.Parent = folder
	local lv = level(state, "oildrum")
	local s = newStructure("oildrum", player, model, drum, Config.OilDrumLifetime)
	s.attackable = true
	local pw = PlayerState.abilityPower(state)
	s.hp = math.round(Config.OilDrumHP * pw)
	s.maxHP = s.hp
	s.dmg = grown("oildrum", "DrumBurnPerSec", Config.OilDrumBurnPerSec, lv)
		* pw
		* PlayerState.computed(state).fireAbilityMult -- ACCELERANT (TORCH synergy card)
	s.slowMult = 1 - math.min(90, grown("oildrum", "DrumMoveSlowPct", Config.OilDrumMoveSlowPct, lv)) / 100
	s.fill = hpBar(drum, COLOR.fire)
	placed(s, COLOR.fire)
	Log.event("Ability", "%s placed an oil drum (LV %d: %d HP, %d burn/s)", player.Name, lv, s.hp, math.round(s.dmg))
end

------------------------------------------------------------------ Turret (INITIATE) tick
local function turretTick(s: Structure, t: number)
	if t - s.lastTick < 1 / (Config.TurretFireRate * rateMult() * s.rate) then
		return
	end
	local head = s.head
	if not head then
		return
	end
	local target = Enemy.nearest(head.Position, if s.range > 0 then s.range else Config.TurretRange, nil)
	if not target then
		return
	end
	local tp = Enemy.rootPosition(target)
	if not tp then
		return
	end
	s.lastTick = t
	aimHead(head, tp)
	World.fireRun("TurretShot", { from = muzzleOf(head), to = tp })
	local travel = tp - head.Position
	hitEnemy(s.owner, target, s.dmg, tp, true, {
		dir = if travel.Magnitude > 0.1 then travel.Unit else nil,
		force = Config.RagdollTickForce,
		tick = true,
	})
end

------------------------------------------------------------------ INITIATE: Frag (brief 5)
-- Thrown like the flashbang; goes off the moment it lands: FragDamage x ABILITY POWER to every enemy in FragRadius,
-- thrown out of the blast.
local function throwFrag(player: Player, state: PlayerState.State, char: Model, aim: Vector3?)
	local lv = level(state, "frag")
	local dmg = grown("frag", "FragDamage", Config.FragDamage, lv)
		* PlayerState.abilityPower(state)
		* PlayerState.computed(state).explosiveDmgMult -- DEMOLITION (explosive synergy)
	local radius = Config.FragRadius * PlayerState.computed(state).areaMult -- brief 12: the area stat
	throw(char, Color3.fromRGB(60, 70, 50), false, function(pos: Vector3)
		local n = Abilities.explode(player, pos, radius, dmg, COLOR.fire)
		Log.event("Ability", "%s's frag (LV %d, %d dmg, r%.1f): %d hit", player.Name, lv, math.round(dmg), radius, n)
	end, aim)
end

------------------------------------------------------------------ ENGINEER: Overclock (brief 5)
local function startOverclock(player: Player, state: PlayerState.State, _char: Model)
	local lv = level(state, "overclock")
	local mult = 1
		+ PlayerState.abilityBuffAmp(state)
			* grown("overclock", "RatePct", (Config.OverclockRateMult - 1) * 100, lv)
			/ 100
	local shield = grown("overclock", "ShieldHp", Config.OverclockShieldHp, lv) * PlayerState.abilityPower(state)
	local ocSec = Config.OverclockSec * PlayerState.abilityDurationAmp(state)
	local untilT = now() + ocSec
	local wasOn = overclocked()
	overclock.untilT = math.max(overclock.untilT, untilT)
	overclock.mult = if wasOn then math.max(overclock.mult, mult) else mult
	overclock.shieldHp = if wasOn then math.max(overclock.shieldHp, shield) else shield
	local n = 0
	for _, s in structures do
		joinOverclock(s)
		n += 1
	end
	state.abilityActive.overclock = overclock.untilT
	state.overclockGunMult = math.max(if wasOn then state.overclockGunMult else 1, mult) -- Round 28e: own gun
	state.dirty = true
	-- CREW OVERCLOCK (ENGINEER III): every crew member's gun runs faster for the same window.
	local crew = PlayerState.passive(state, "ENGINEER", 3)
	if crew then
		World.crewOverclockUntil = math.max(World.crewOverclockUntil, overclock.untilT)
		PlayerState.markAllDirty()
	end
	World.fireRun("Overclock", { owner = player.UserId, untilT = overclock.untilT, count = n, crew = crew })
	Log.event(
		"Ability",
		"%s overclocked %d placeables (LV %d: x%.2f rate, %d shield, %ds)",
		player.Name,
		n,
		lv,
		mult,
		math.round(shield),
		math.round(ocSec)
	)
end

------------------------------------------------------------------ SHARPSHOOTER: Eagle Eye (brief 5)
-- Every enemy within EagleEyeRadius is marked through walls and slowed by EagleEyeSlowPct for EagleEyeSec
-- (Round 16: a slow replaced the old bonus damage). The boss takes EagleEyeBossSlowMult of the slow.
local function eagleEye(player: Player, state: PlayerState.State, char: Model)
	local lv = level(state, "eagleeye")
	-- Round 25: ABILITY POWER: a wider sweep, a stronger slow (still under EagleEyeSlowCap), a longer mark.
	local radius = grown("eagleeye", "EagleEyeRadius", Config.EagleEyeRadius, lv) * PlayerState.abilityRadiusAmp(state)
	local slow = math.min(
		grown("eagleeye", "EagleEyeSlowPct", Config.EagleEyeSlowPct * 100, lv) / 100 * PlayerState.abilityBuffAmp(state),
		Config.EagleEyeSlowCap
	)
	local markSec = Config.EagleEyeSec * PlayerState.abilityDurationAmp(state)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local victims = Enemy.within(root.Position, radius)
	for _, model in victims do
		Enemy.mark(model, markSec)
		local d = Enemy.data(model)
		local boss = d ~= nil and d.row.boss == true
		Enemy.slow(model, 1 - slow * (if boss then Config.EagleEyeBossSlowMult else 1), markSec)
	end
	state.abilityActive.eagleeye = now() + markSec
	state.dirty = true
	World.fireRun("EagleEye", { position = root.Position, radius = radius, owner = player.UserId })
	Log.event(
		"Ability",
		"%s's eagle eye (LV %d): %d marked for %ds, slowed %d%% (r%d)",
		player.Name,
		lv,
		#victims,
		math.round(markSec),
		math.round(slow * 100),
		math.round(radius)
	)
end

------------------------------------------------------------------ ENGINEER: Sentry (brief 12)
-- A heavy tripod: SentryScale x the turret, SentryDeploySec of leg unfold and barrel spin-up before the first shot,
-- twin barrels alternating at 2x the turret's rate (per-barrel damage keeps the total at SentryDpsMult x the
-- turret's DPS), SentryHp, SentrySec, SentryRangeMult x the turret's reach and a tracking laser on its target.
-- Overclock and ENGINEER's placeable passives apply; TURRET DAMAGE raises it. No upgrade or repair interaction.
local function buildSentry(cf: CFrame): (Model, BasePart, BasePart, { BasePart }, { BasePart }, Beam)
	local k = Config.SentryScale
	local model = Instance.new("Model")
	model.Name = "Sentry"
	local hub = part({
		Name = "Hub",
		Size = Vector3.new(1.5, 0.9, 1.5) * k,
		CFrame = cf * CFrame.new(0, 1.0 * k, 0),
		Color = Color3.fromRGB(58, 60, 68),
		Material = Enum.Material.Metal,
		Parent = model,
	})
	local legs = {}
	for i = 0, 2 do
		local yaw = math.rad(i * 120)
		local leg = part({
			Name = "Leg",
			Size = Vector3.new(0.28, 1.6, 0.28) * k,
			-- Folded: straight down under the hub. The deploy tween swings each one out.
			CFrame = cf * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 0.8 * k, 0),
			CanCollide = false,
			Color = Color3.fromRGB(40, 40, 46),
			Material = Enum.Material.Metal,
			Parent = model,
		})
		leg:SetAttribute("Yaw", yaw)
		table.insert(legs, leg)
	end
	local head = part({
		Name = "Head",
		Size = Vector3.new(1.5, 1.0, 1.7) * k,
		CFrame = cf * CFrame.new(0, 1.0 * k, 0), -- rises to 2.0k on deploy
		CanCollide = false,
		Color = Color3.fromRGB(78, 80, 90),
		Material = Enum.Material.Metal,
		Parent = model,
	})
	part({
		Name = "Stripe",
		Size = Vector3.new(1.52, 0.18, 1.72) * k,
		CFrame = head.CFrame * CFrame.new(0, 0.3 * k, 0),
		CanCollide = false,
		CanQuery = false,
		Color = Color3.fromHex("D9822B"),
		Material = Enum.Material.Neon,
		Parent = model,
	})
	local barrels = {}
	for _, x in { -0.38, 0.38 } do
		local b = part({
			Name = "Barrel",
			Size = Vector3.new(0.3, 0.3, 2.2) * k,
			CFrame = head.CFrame * CFrame.new(x * k, -0.05 * k, -1.6 * k),
			CanCollide = false,
			Color = Color3.fromRGB(30, 30, 34),
			Material = Enum.Material.Metal,
			Parent = model,
		})
		table.insert(barrels, b)
	end
	for _, p in model:GetChildren() do
		if p ~= head and p ~= hub and p.Name ~= "Leg" and p:IsA("BasePart") then
			local w = Instance.new("WeldConstraint")
			w.Part0 = head
			w.Part1 = p
			w.Parent = p
		end
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "LaserFrom"
	a0.Position = Vector3.new(0, 0.1 * k, -0.9 * k)
	a0.Parent = head
	local laser = Instance.new("Beam")
	laser.Name = "Laser"
	laser.Attachment0 = a0
	laser.Color = ColorSequence.new(Color3.fromHex(Config.SentryLaserColor))
	laser.LightEmission = 1
	laser.Width0 = 0.06
	laser.Width1 = 0.06
	laser.FaceCamera = true
	laser.Transparency = NumberSequence.new(0.25)
	laser.Enabled = false
	laser.Parent = head
	model.PrimaryPart = hub
	model.Parent = folder
	return model, hub, head, legs, barrels, laser
end

local laserTargets: { [Model]: Attachment } = setmetatable({} :: any, { __mode = "k" })
local function laserAttachment(target: Model): Attachment?
	local a = laserTargets[target]
	if a and a.Parent then
		return a
	end
	local d = Enemy.data(target)
	if not d then
		return nil
	end
	local att = Instance.new("Attachment")
	att.Name = "SentryLaserAt"
	att.Parent = d.root
	laserTargets[target] = att
	return att
end

local function placeSentry(player: Player, state: PlayerState.State, char: Model)
	local cf = placementCFrame(char, Config.StructurePlaceDistance)
	local model, hub, head, legs, barrels, laser = buildSentry(cf)
	local lv = level(state, "sentry")
	local s = newStructure("sentry", player, model, hub, Config.SentrySec * PlayerState.abilityDurationAmp(state))
	s.attackable = true
	local pw = PlayerState.abilityPower(state)
	s.hp = math.round(grown("sentry", "SentryHp", Config.SentryHp, lv) * pw)
	s.maxHP = s.hp
	s.dmg = grown("sentry", "SentryDamage", Config.TurretDmg * Config.SentryDpsMult / 2, lv)
		* pw
		* PlayerState.computed(state).turretDmgMult -- TURRET DAMAGE (ENGINEER / INITIATE synergy card)
	s.range = Config.TurretRange * Config.SentryRangeMult * Stats.mult(player, "turretRange")
	s.armedAt = now() + Config.SentryDeploySec
	s.head = head
	s.extra = { barrels = barrels, laser = laser, flip = false }
	s.fill = hpBar(hub, Color3.fromHex("D9822B"))
	placed(s, Color3.fromHex("D9822B"))
	-- The deploy: legs swing out, the head rises, then a beep (SentryReady) and it starts tracking.
	local k = Config.SentryScale
	local info = TweenInfo.new(Config.SentryDeploySec * 0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	for _, leg in legs do
		local yaw = leg:GetAttribute("Yaw") :: number
		TweenService:Create(leg, info, {
			CFrame = cf
				* CFrame.Angles(0, yaw, 0)
				* CFrame.new(0, 0.62 * k, -0.55 * k)
				* CFrame.Angles(math.rad(35), 0, 0),
		}):Play()
	end
	task.delay(Config.SentryDeploySec * 0.35, function()
		if structures[hub] then
			TweenService:Create(head, TweenInfo.new(Config.SentryDeploySec * 0.45, Enum.EasingStyle.Quad), {
				CFrame = cf * CFrame.new(0, 2.0 * k, 0),
			}):Play()
		end
	end)
	task.delay(Config.SentryDeploySec, function()
		if structures[hub] then
			World.fireRun("SentryReady", { position = head.Position })
		end
	end)
	abilityCallout(player, "sentryUp")
	Log.event(
		"Ability",
		"%s deployed a sentry (LV %d: %d HP, %d dmg x2 barrels, r%d, %ds)",
		player.Name,
		lv,
		s.hp,
		math.round(s.dmg),
		math.round(s.range),
		math.round(Config.SentrySec)
	)
end

local function sentryTick(s: Structure, t: number)
	local x = s.extra :: any
	local laser: Beam? = x and x.laser
	if t < s.armedAt then
		return
	end
	if t - s.lastTick < 1 / (Config.TurretFireRate * 2 * rateMult() * s.rate) then
		return
	end
	local head = s.head
	if not head then
		return
	end
	local target = Enemy.nearest(head.Position, s.range, nil)
	local tp = target and Enemy.rootPosition(target)
	if not target or not tp then
		if laser then
			laser.Enabled = false
		end
		return
	end
	s.lastTick = t
	aimHead(head, tp)
	if laser then
		local att = laserAttachment(target)
		laser.Attachment1 = att
		laser.Enabled = att ~= nil
	end
	-- Twin barrels: alternate muzzles.
	x.flip = not x.flip
	local barrel: BasePart = x.barrels[if x.flip then 1 else 2]
	local muzzle = (barrel.CFrame * CFrame.new(0, 0, -barrel.Size.Z / 2)).Position
	World.fireRun("TurretShot", { from = muzzle, to = tp, sentry = true })
	local travel = tp - head.Position
	hitEnemy(s.owner, target, s.dmg, tp, true, {
		dir = if travel.Magnitude > 0.1 then travel.Unit else nil,
		force = Config.RagdollTickForce,
		tick = true,
	})
end

------------------------------------------------------------------ DOC: Heal Drone (brief 12)
local function summonHealDrone(player: Player, state: PlayerState.State, _char: Model)
	local lv = level(state, "healdrone")
	local hps = grown("healdrone", "HealDroneHps", Config.HealDroneHps, lv)
		* PlayerState.abilityPower(state)
		* PlayerState.computed(state).healMult -- HEALING (DOC synergy card)
	local range = Config.HealDroneRange * (if PlayerState.passive(state, "DOC", 1) then 1 + Config.DocReachPct else 1)
	Drones.summonHealer(player, hps, range, Config.HealDroneSec * PlayerState.abilityDurationAmp(state))
	abilityCallout(player, "healDroneUp")
end

------------------------------------------------------------------ PYRO: Inferno (brief 12)
-- A ring of fire round the caster that moves with them: every FieldTickSec, enemies inside burn (the burn status,
-- so PYRO's fire mastery applies) and walk InfernoSlowPct slower (stacking with Ice Ammo's slow, never a stop).
-- Players and placeables are never touched. Recasting while one burns refreshes it.
type Aura = {
	owner: Player,
	radius: number,
	untilT: number,
	lastTick: number,
	burn: number,
	slowMult: number,
}
local auras: { [Player]: Aura } = {}

local function endInferno(a: Aura, reason: string)
	if auras[a.owner] ~= a then
		return
	end
	auras[a.owner] = nil
	World.fireRun("InfernoEnd", { owner = a.owner.UserId })
	Log.event("Ability", "%s's inferno %s", a.owner.Name, reason)
end

local function startInferno(player: Player, state: PlayerState.State, _char: Model)
	local lv = level(state, "inferno")
	local burn = grown("inferno", "InfernoBurnPerSec", Config.InfernoBurnPerSec, lv)
		* PlayerState.abilityPower(state)
		* PlayerState.computed(state).fireAbilityMult -- ACCELERANT (PYRO synergy card)
	local slowPct = math.min(90, grown("inferno", "InfernoSlowPct", Config.InfernoSlowPct, lv))
	local radius = Config.InfernoRadius * Stats.mult(player, "area")
	local sec = Config.InfernoSec * PlayerState.abilityDurationAmp(state)
	local a: Aura = {
		owner = player,
		radius = radius,
		untilT = now() + sec,
		lastTick = 0,
		burn = burn,
		slowMult = 1 - slowPct / 100,
	}
	auras[player] = a
	state.abilityActive.inferno = a.untilT
	state.dirty = true
	World.fireRun("InfernoStart", { owner = player.UserId, radius = radius, untilT = a.untilT })
	abilityCallout(player, "infernoUp")
	Log.event(
		"Ability",
		"%s lit an inferno (LV %d: r%.1f, %d burn/s, %d%% slow, %ds)",
		player.Name,
		lv,
		radius,
		math.round(burn),
		math.round(slowPct),
		math.round(sec)
	)
end

-- BACKDRAFT (PYRO III, Round 29b): a kill adds `sec` to the caster's running Inferno, uncapped.
local function extendInferno(player: Player, sec: number): boolean
	local a = auras[player]
	if not a or a.untilT <= now() then
		return false
	end
	a.untilT += sec
	local state = PlayerState.get(player)
	state.abilityActive.inferno = a.untilT
	state.dirty = true
	World.fireRun("InfernoExtend", { owner = player.UserId, untilT = a.untilT })
	return true
end

local function auraTick(a: Aura, t: number)
	if t - a.lastTick < Config.FieldTickSec then
		return
	end
	a.lastTick = t
	local char = a.owner.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local center = root.Position
	for _, model in Enemy.within(center, a.radius + 2) do
		local ep = Enemy.rootPosition(model)
		if not ep or flatDistance(ep, center) > a.radius or math.abs(ep.Y - center.Y) > Config.InfernoHeight then
			continue
		end
		Elements.burnAt(model, a.owner, a.burn, Config.InfernoBurnSec)
		Enemy.slowSource(model, "inferno", a.slowMult, Config.FieldTickSec + 0.3)
	end
end

------------------------------------------------------------------ Explosions (brief 12)
-- Every ability blast that isn't a bullet goes through here: damage x falloff-free to every enemy in the radius, the
-- body thrown out of the blast. Step 5 adds knockback and the explosion feel. Returns how many it hit.
function Abilities.explode(owner: Player, at: Vector3, radius: number, dmg: number, color: Color3): number
	local victims = Enemy.within(at, radius)
	local kills = 0
	for _, model in victims do
		local ep = Enemy.rootPosition(model) or at
		local away = ep - at
		if
			hitEnemy(owner, model, dmg, ep, false, {
				dir = if away.Magnitude > 0.1 then away.Unit else nil,
				blast = true,
				blastT = 1 - math.clamp(away.Magnitude / radius, 0, 1),
			})
		then
			kills += 1
		end
	end
	Explosion.after(owner, at, radius, color, victims, 0.3)
	if kills >= Config.CalloutMultiKill then
		AllyCallout.send(owner, "multiKill", kills)
	end
	return #victims
end

-- Debug `Spawn drones <n>`.
function Abilities.spawnDrones(player: Player, n: number)
	local state = PlayerState.get(player)
	for _ = 1, math.clamp(math.floor(n), 1, 60) do
		Swarm.summon(player, state)
	end
end

------------------------------------------------------------------ Use
-- (Cast: luau-lsp has no Roblox types here and cannot unify the handlers' inferred signatures.)
local USE: { [string]: (Player, PlayerState.State, Model, Vector3?) -> () } = {
	frag = throwFrag,
	overclock = startOverclock,
	eagleeye = eagleEye,
	turret = placeTurret,
	barricade = placeBarricade,
	stim = adrenaline,
	stimshot = stimShot,
	medbag = placeMedBag,
	healturret = placeHealTurret,
	claymore = placeClaymore,
	deadeye = deadEye,
	flashbang = throwFlashbang,
	molotov = throwMolotov,
	flameturret = placeFlameTurret,
	oildrum = placeOilDrum,
	-- Brief 12
	sentry = placeSentry,
	healdrone = summonHealDrone,
	inferno = startInferno,
	drone = function(player: Player, state: PlayerState.State, _char: Model)
		Swarm.summon(player, state)
	end,
	surge = function(player: Player, state: PlayerState.State, _char: Model)
		Swarm.surge(player, state)
	end,
	aegis = function(player: Player, state: PlayerState.State, _char: Model)
		Swarm.aegis(player, state)
	end,
} :: any

local TICK: { [string]: (Structure, number) -> () } = {
	turret = turretTick,
	healturret = healTurretTick,
	flameturret = flameTurretTick,
	claymore = claymoreTick,
	sentry = sentryTick, -- brief 12
}

-- Charges: every ability holds one; DOUBLE DOWN (INITIATE II) gives Frag and Claymore MasteryExtraCharges more.
-- A use spends a charge and starts the recharge if it is not running; charges come back one cooldown at a time.
Abilities.maxCharges = PlayerState.maxCharges
Abilities.chargesLeft = PlayerState.chargesLeft

local function onCooldown(state: PlayerState.State, id: string): boolean
	return Abilities.chargesLeft(state, id) <= 0
end

-- TRIAGE (DOC II): a downed ally inside the DOC's med bag or healing turret range stands up on their own over
-- AutoReviveSec, no hold (the bleed pauses while it fills); a bled-out ally whose body lies inside comes back too.
local function insideTriage(position: Vector3): boolean
	for _, f in fields do
		if f.triage and flatDistance(position, f.position) <= f.radius then
			return true
		end
	end
	for _, s in structures do
		if s.triage and (s.hitPart.Position - position).Magnitude <= s.range then
			return true
		end
	end
	return false
end

triageTick = function(dt: number)
	if not World.inRun() then
		return
	end
	for _, player in World.runAudience() do
		local state = PlayerState.get(player)
		if not state.downed and not state.bledOut then
			if state.triageProgress > 0 then
				state.triageProgress = 0
			end
			continue
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local pos = if state.downed and root then root.Position else state.lastPosition
		if insideTriage(pos) then
			state.triageProgress = math.min(1, state.triageProgress + dt / math.max(Config.AutoReviveSec, 0.1))
			if state.downed then
				state.bleedEndsAt += dt
			end
			Downed.triageProgress(player, state.triageProgress)
			if state.triageProgress >= 1 then
				state.triageProgress = 0
				Downed.reviveOne(player, "TRIAGE")
			end
		elseif state.triageProgress > 0 then
			state.triageProgress = 0
			Downed.triageProgress(player, 0)
		end
	end
end

-- Recharge: a finished cooldown hands one charge back and starts the next while any are missing.
local function rechargeTick(t: number)
	for _, state in mine() do
		for id, c in state.charges do
			local max = Abilities.maxCharges(state, id)
			local ends = state.cooldowns[id] or 0
			if c < max and t >= ends then
				c += 1
				state.charges[id] = c
				if c < max then
					state.cooldowns[id] = t + PlayerState.abilityCooldown(state, id)
				end
				state.dirty = true
			end
			if c >= max then
				state.charges[id] = nil
			end
		end
	end
end

-- `aim` is the point under the client's cursor (with the camera ray's `origin` and the `hit` part for the aim
-- assist); thrown abilities land there (clamped), placeables ignore it.
function Abilities.use(player: Player, id: any, aim: any, origin: any, hit: any)
	if typeof(id) ~= "string" then
		return
	end
	local aimPoint: Vector3? = if typeof(aim) == "Vector3" and aim == aim then aim else nil
	assistAim = {
		origin = if typeof(origin) == "Vector3" and origin == origin then origin else nil,
		hit = if typeof(hit) == "Instance" then hit else nil,
	}
	local state = PlayerState.get(player)
	local char = player.Character
	if
		not char
		or state.downed
		or state.bledOut
		or Pause.active()
		-- Brief 8: in a run with your party, or (the hub slot) inside the training range.
		or not ((World.inRun() and World.isInParty(player)) or (Slot.isHub and state.inRange and Config.RangeAbilities))
	then
		return
	end
	-- Only the player's kit can fire (brief 12: the class's three plus any debug grant); the unassigned pool needs a
	-- grant or Config.UnassignedAbilitiesEnabled.
	local ability = Classes.AbilityById[id]
	local handler = USE[id]
	if not ability or not handler or not table.find(PlayerState.kitOf(state), id) then
		return
	end
	if
		Classes.isUnassigned(id)
		and not Config.UnassignedAbilitiesEnabled
		and not table.find(state.grants :: { string }, id)
	then
		return
	end
	if onCooldown(state, id) then
		Remotes.Juice:FireClient(player, "AbilityDenied", { id = id })
		return
	end
	handler(player, state, char, aimPoint)
	if state.noCooldowns then
		-- Debug NO COOLDOWNS (Round 18): nothing spent, nothing to recharge.
		state.charges[id] = nil
		state.cooldowns[id] = 0
		state.dirty = true
		return
	end
	state.charges[id] = Abilities.chargesLeft(state, id) - 1
	if (state.cooldowns[id] or 0) <= now() then
		state.cooldowns[id] = now() + PlayerState.abilityCooldown(state, id)
	end
	state.dirty = true
end

function Abilities.init()
	local existing = Workspace:FindFirstChild("Structures")
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "Structures"
		folder.Parent = Workspace
	end
	Enemy.extraTargets = Abilities.targets
	Drones.hit = hitEnemy -- brief 12: drones damage through the same credit path
	Swarm.explode = Abilities.explode
	Mastery.extendInferno = extendInferno -- Round 29b: BACKDRAFT
	Drones.init()
	Swarm.init()
	Enemy.onStructureHit = Abilities.damageStructure
	Remotes.UseAbility.OnServerEvent:Connect(Abilities.use)

	-- Paused: placeables, fields, buffs, windows and cooldowns all keep what they had left.
	Pause.onTick(function(dt)
		for _, s in structures do
			s.expiresAt += dt
		end
		for _, f in fields do
			f.expiresAt += dt
		end
		for _, a in auras do
			a.untilT += dt
		end
		if overclock.untilT > 0 then
			overclock.untilT += dt
		end
		if World.crewOverclockUntil > 0 then
			World.crewOverclockUntil += dt
		end
		for _, state in mine() do
			if state.buffUntil > 0 then
				state.buffUntil += dt
			end
			for id, untilT in state.abilityActive do
				state.abilityActive[id] = untilT + dt
			end
			for id, ends in state.cooldowns do
				state.cooldowns[id] = ends + dt
			end
			state.fieldHospitalUntil += dt
			state.dirty = true
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		if Pause.active() then
			return
		end
		local t = now()
		if overclock.untilT > 0 and t >= overclock.untilT then
			endOverclock()
		end
		rechargeTick(t)
		for _, s in table.clone(structures) do
			if t >= s.expiresAt then
				destroyStructure(s, "expired")
			else
				local tick = TICK[s.kind]
				if tick then
					tick(s, t)
				end
				-- FIELD REPAIR (ENGINEER II): idle placeables mend themselves.
				if
					s.repair
					and s.hp < s.maxHP
					and not Enemy.nearest(s.hitPart.Position, Config.FieldRepairRange, nil)
				then
					s.hp = math.min(s.maxHP, s.hp + s.maxHP * Config.FieldRepairPct * dt)
					s.hitPart:SetAttribute("StructureHP", s.hp)
					local fill = s.fill
					if fill then
						fill.Size = UDim2.fromScale(math.clamp(s.hp / s.maxHP, 0, 1), 1)
					end
				end
			end
		end
		triageTick(dt)
		for _, a in table.clone(auras) do
			if t >= a.untilT or not a.owner.Parent or PlayerState.get(a.owner).downed then
				endInferno(a, if t >= a.untilT then "burned out" else "dropped")
			else
				auraTick(a, t)
			end
		end
		for _, f in table.clone(fields) do
			if t >= f.expiresAt then
				removeField(f, "burned out")
			else
				fieldTick(f, t)
			end
		end
		-- Self buff expiry: drop the multipliers and resync.
		for player, state in mine() do
			if state.buffId and t >= state.buffUntil then
				local id = state.buffId
				state.buffId = nil
				state.buffUntil = 0
				PlayerState.applyCharacterStats(state)
				state.dirty = true
				local char = player.Character
				if char then
					char:SetAttribute("ActiveBuff", nil)
				end
				Remotes.Juice:FireClient(player, "StimEnd", { id = id })
			end
		end
	end)
end

-- Everything standing where `inside(position)` says (the vault sealing): placeables break, fields go out.
function Abilities.clearWhere(inside: (Vector3) -> boolean, reason: string): number
	local n = 0
	for _, s in table.clone(structures) do
		if inside(s.hitPart.Position) then
			destroyStructure(s, reason)
			n += 1
		end
	end
	for _, f in table.clone(fields) do
		if inside(f.position) then
			removeField(f, reason)
			n += 1
		end
	end
	return n
end

-- Brief 8: leaving the range takes your placeables and fields with you. Returns how many went.
function Abilities.clearOwner(player: Player): number
	local n = 0
	for _, s in table.clone(structures) do
		if s.owner == player then
			destroyStructure(s, "left the range")
			n += 1
		end
	end
	for _, f in table.clone(fields) do
		if f.owner == player then
			removeField(f, "left the range")
			n += 1
		end
	end
	local a = auras[player]
	if a then
		endInferno(a, "left the range")
	end
	n += Drones.clearOwner(player, "left the range")
	return n
end

function Abilities.clearAll()
	if overclock.untilT > 0 then
		endOverclock()
	end
	for _, s in table.clone(structures) do
		destroyStructure(s, "cleared")
	end
	for _, f in table.clone(fields) do
		removeField(f, "cleared")
	end
	for _, a in table.clone(auras) do
		endInferno(a, "cleared")
	end
	Drones.clearAll()
end

return Abilities
