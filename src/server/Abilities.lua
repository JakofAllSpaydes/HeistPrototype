--!strict
-- The fifteen class abilities (Classes.lua), server side. Brief 5 adds INITIATE's Frag (thrown, fused blast),
-- ENGINEER's Overclock (team-wide placeable rate + barricade shields) and SHARPSHOOTER's Eagle Eye (marks).
--   Placeables stand StructurePlaceDistance in front of the player: turret, barricade, healing turret, flame
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
local Remotes = require(Shared.Remotes)
local Classes = require(Shared.Classes)
local AbilityGrowth = require(Shared.AbilityGrowth)
local PlayerState = require(script.Parent.PlayerState)
local Economy = require(script.Parent.Economy)
local Enemy = require(script.Parent.Enemy)
local Elements = require(script.Parent.Elements)
local Downed = require(script.Parent.Downed)
local Pause = require(script.Parent.Pause)
local Log = require(script.Parent.Log)
local AllyCallout = require(script.Parent.AllyCallout)
local World = require(script.Parent.World)
local Boosts = require(script.Parent.Boosts)

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
	range: number, -- healing turret reach (DOC I: WIDE NET)
	repair: boolean, -- ENGINEER II: FIELD REPAIR
	triage: boolean, -- healing turret of a DOC II: downed allies in range stand up on their own
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
	return CFrame.new(pos.X, Config.FloorTop, pos.Z) * CFrame.Angles(0, yaw, 0)
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
	dmg = math.max(1, math.round(dmg * Boosts.damageMult(owner))) -- POWER boost (brief 6)
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
	if World.crewOverclockUntil > 0 then
		World.crewOverclockUntil = 0
		PlayerState.markAllDirty()
	end
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
		expiresAt = now() + lifetime,
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
	}
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
	World.fireRun("StructurePlaced", { kind = s.kind, position = s.hitPart.Position, color = color, radius = radius })
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
	s.dmg = grown("turret", "Damage", Config.TurretDmg, lv) * pw
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
	Remotes.Juice:FireClient(player, "StimStart", { id = id, duration = duration, until_ = state.buffUntil })
	local b = PlayerState.buffFor(state, id)
	Log.event(
		"Ability",
		"%s used %s (LV %d: +%d HP, %ds, x%.2f dmg, x%.2f speed, x%.2f fire rate, x%.2f reload)",
		player.Name,
		id,
		level(state, id),
		math.round(healed),
		duration,
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
	startBuff(player, state, "stim", Config.AdrenalineDuration, heal)
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
		CFrame = CFrame.new(position.X, Config.FloorTop + 0.1, position.Z) * CFrame.Angles(0, 0, math.rad(90)),
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
				Config.FloorTop + 0.14,
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
				CFrame = CFrame.new(position.X, Config.FloorTop + 0.3, position.Z) * CFrame.new(offset),
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
		-- The bag: a green box with a white cross.
		local bag = part({
			Name = "Bag",
			Size = Vector3.new(1.6, 1, 1.2),
			CFrame = CFrame.new(position.X, Config.FloorTop + 0.5, position.Z),
			CanCollide = false,
			CanQuery = false,
			Color = COLOR.green,
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
		part({
			Name = "CrossA",
			Size = Vector3.new(1.0, 0.05, 0.3),
			CFrame = bag.CFrame * CFrame.new(0, 0.52, 0),
			CanCollide = false,
			CanQuery = false,
			Color = COLOR.white,
			Material = Enum.Material.Neon,
			Parent = model,
		})
		part({
			Name = "CrossB",
			Size = Vector3.new(0.3, 0.05, 1.0),
			CFrame = bag.CFrame * CFrame.new(0, 0.52, 0),
			CanCollide = false,
			CanQuery = false,
			Color = COLOR.white,
			Material = Enum.Material.Neon,
			Parent = model,
		})
	end
	model.PrimaryPart = disc
	model.Parent = folder
	local os_ = PlayerState.get(owner)
	fields[model] = {
		kind = kind,
		owner = owner,
		model = model,
		position = Vector3.new(position.X, Config.FloorTop, position.Z),
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
	local to = Vector3.new(target.X, Config.FloorTop + 0.4, target.Z)
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
				to = Vector3.new(lp.X, Config.FloorTop + 0.4, lp.Z)
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
		Config.StimShotDuration,
		grown("stimshot", "Heal", Config.StimShotHeal, level(state, "stimshot")) * PlayerState.abilityPower(state)
	)
end

local function placeMedBag(player: Player, state: PlayerState.State, char: Model)
	local lv = level(state, "medbag")
	local pos = placementCFrame(char, Config.StructurePlaceDistance).Position
	-- WIDE NET (DOC I) and FIELD HOSPITAL (DOC III) widen it; FIELD HOSPITAL heals harder.
	local radius = Config.MedBagRadius
	local heal = grown("medbag", "HealPerSec", Config.MedBagHealPerSec, lv) * PlayerState.abilityPower(state)
	if PlayerState.passive(state, "DOC", 1) then
		radius *= 1 + Config.DocReachPct
	end
	if PlayerState.passive(state, "DOC", 3) then
		radius *= Config.FieldHospitalRadiusMult
		heal *= Config.FieldHospitalHealMult
	end
	placeField("medbag", player, pos, radius, Config.MedBagLifetime, heal, 1)
	World.fireRun("StructurePlaced", { kind = "medbag", position = pos, color = COLOR.green, radius = radius })
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
	s.heal = grown("healturret", "BeamHeal", Config.HealTurretBeamHeal, lv) * pw
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
	s.dmg = grown("claymore", "ClaymoreDamage", Config.ClaymoreDamage, lv) * PlayerState.abilityPower(state)
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
	local victims = Enemy.within(pos, Config.ClaymoreBlastRadius)
	World.fireRun(
		"Blast",
		{ position = pos, radius = Config.ClaymoreBlastRadius, color = COLOR.red, shake = 0.3, pitch = 0.8 }
	)
	local kills = 0
	for _, model in victims do
		local ep = Enemy.rootPosition(model) or pos
		-- Thrown out of the blast, hardest at the center.
		local away = ep - pos
		local hit: Enemy.Hit = {
			dir = if away.Magnitude > 0.1 then away.Unit else nil,
			blast = true,
			blastT = 1 - math.clamp(away.Magnitude / Config.ClaymoreBlastRadius, 0, 1),
		}
		if hitEnemy(s.owner, model, s.dmg, ep, false, hit) then
			kills += 1
		end
	end
	if kills >= Config.CalloutMultiKill then
		AllyCallout.send(s.owner, "multiKill", kills)
	end
	Log.event("Ability", "%s's claymore went off: %d hit, %d killed", s.owner.Name, #victims, kills)
	destroyStructure(s, "detonated")
end

local function deadEye(player: Player, state: PlayerState.State, _char: Model)
	startBuff(player, state, "deadeye", Config.DeadEyeDuration, 0)
end

local function throwFlashbang(player: Player, state: PlayerState.State, char: Model, aim: Vector3?)
	local lv = level(state, "flashbang")
	local radius = grown("flashbang", "FlashRadius", Config.FlashRadius, lv)
	local stunSec = grown("flashbang", "StunDuration", Config.StunDuration, lv)
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
	local burn = grown("molotov", "BurnPerSec", Config.MolotovBurnPerSec, lv) * PlayerState.abilityPower(state)
	local slowPct = math.min(90, grown("molotov", "MoveSlowPct", Config.MolotovMoveSlowPct, lv))
	throw(char, COLOR.allyFire, true, function(pos: Vector3)
		placeField("molotov", player, pos, Config.MolotovRadius, Config.MolotovLifetime, burn, 1 - slowPct / 100)
		World.fireRun(
			"Blast",
			{ position = pos, radius = Config.MolotovRadius, color = COLOR.allyFire, shake = 0.1, pitch = 1.2 }
		)
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
	s.dmg = grown("flameturret", "FlameDps", Config.FlameTurretDps, lv) * pw
	s.head = head
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
	local target = Enemy.nearest(head.Position, Config.FlameTurretRange, nil)
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
	s.dmg = grown("oildrum", "DrumBurnPerSec", Config.OilDrumBurnPerSec, lv) * pw
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
	local target = Enemy.nearest(head.Position, Config.TurretRange, nil)
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
	local dmg = grown("frag", "FragDamage", Config.FragDamage, lv) * PlayerState.abilityPower(state)
	local radius = Config.FragRadius
	throw(char, Color3.fromRGB(60, 70, 50), false, function(pos: Vector3)
		do
			local victims = Enemy.within(pos, radius)
			World.fireRun("Blast", { position = pos, radius = radius, color = COLOR.fire, shake = 0.35, pitch = 0.7 })
			local kills = 0
			for _, model in victims do
				local ep = Enemy.rootPosition(model) or pos
				local away = ep - pos
				local hit: Enemy.Hit = {
					dir = if away.Magnitude > 0.1 then away.Unit else nil,
					blast = true,
					blastT = 1 - math.clamp(away.Magnitude / radius, 0, 1),
				}
				if hitEnemy(player, model, dmg, ep, false, hit) then
					kills += 1
				end
			end
			if kills >= Config.CalloutMultiKill then
				AllyCallout.send(player, "multiKill", kills)
			end
			Log.event(
				"Ability",
				"%s's frag (LV %d, %d dmg): %d hit, %d killed",
				player.Name,
				lv,
				math.round(dmg),
				#victims,
				kills
			)
		end
	end, aim)
end

------------------------------------------------------------------ ENGINEER: Overclock (brief 5)
local function startOverclock(player: Player, state: PlayerState.State, _char: Model)
	local lv = level(state, "overclock")
	local mult = 1 + grown("overclock", "RatePct", (Config.OverclockRateMult - 1) * 100, lv) / 100
	local shield = grown("overclock", "ShieldHp", Config.OverclockShieldHp, lv) * PlayerState.abilityPower(state)
	local untilT = now() + Config.OverclockSec
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
		Config.OverclockSec
	)
end

------------------------------------------------------------------ SHARPSHOOTER: Eagle Eye (brief 5)
-- Every enemy within EagleEyeRadius is marked through walls and slowed by EagleEyeSlowPct for EagleEyeSec
-- (Round 16: a slow replaced the old bonus damage). The boss takes EagleEyeBossSlowMult of the slow.
local function eagleEye(player: Player, state: PlayerState.State, char: Model)
	local lv = level(state, "eagleeye")
	local radius = grown("eagleeye", "EagleEyeRadius", Config.EagleEyeRadius, lv)
	local slow =
		math.min(grown("eagleeye", "EagleEyeSlowPct", Config.EagleEyeSlowPct * 100, lv) / 100, Config.EagleEyeSlowCap)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local victims = Enemy.within(root.Position, radius)
	for _, model in victims do
		Enemy.mark(model, Config.EagleEyeSec)
		local d = Enemy.data(model)
		local boss = d ~= nil and d.row.boss == true
		Enemy.slow(model, 1 - slow * (if boss then Config.EagleEyeBossSlowMult else 1), Config.EagleEyeSec)
	end
	state.abilityActive.eagleeye = now() + Config.EagleEyeSec
	state.dirty = true
	World.fireRun("EagleEye", { position = root.Position, radius = radius, owner = player.UserId })
	Log.event(
		"Ability",
		"%s's eagle eye (LV %d): %d marked for %ds, slowed %d%% (r%d)",
		player.Name,
		lv,
		#victims,
		Config.EagleEyeSec,
		math.round(slow * 100),
		math.round(radius)
	)
end

------------------------------------------------------------------ Use
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
}

local TICK: { [string]: (Structure, number) -> () } = {
	turret = turretTick,
	healturret = healTurretTick,
	flameturret = flameTurretTick,
	claymore = claymoreTick,
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
	for _, state in PlayerState.all() do
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
		or not World.inRun()
		or not World.isInParty(player)
	then
		return
	end
	-- Only the equipped class's abilities can fire.
	local ability = Classes.AbilityById[id]
	local handler = USE[id]
	if not ability or not handler or Classes.ClassOfAbility[id] ~= PlayerState.classOf(state) then
		return
	end
	if onCooldown(state, id) then
		Remotes.Juice:FireClient(player, "AbilityDenied", { id = id })
		return
	end
	handler(player, state, char, aimPoint)
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
		if overclock.untilT > 0 then
			overclock.untilT += dt
		end
		if World.crewOverclockUntil > 0 then
			World.crewOverclockUntil += dt
		end
		for _, state in PlayerState.all() do
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
		for _, f in table.clone(fields) do
			if t >= f.expiresAt then
				removeField(f, "burned out")
			else
				fieldTick(f, t)
			end
		end
		-- Self buff expiry: drop the multipliers and resync.
		for player, state in PlayerState.all() do
			if state.buffId and t >= state.buffUntil then
				local id = state.buffId
				state.buffId = nil
				state.buffUntil = 0
				PlayerState.applyCharacterStats(state)
				state.dirty = true
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
end

return Abilities
