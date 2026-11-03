--!strict
-- Per-player authoritative state: cash, upgrades, held gun, pity, debug flags. Builds StateSync.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)
local Rarity = require(Shared.Rarity)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Stats = require(script.Parent.Stats)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)

export type State = {
	player: Player,
	cash: number,
	upgradesBought: number,
	weaponsBought: number,
	upgrades: { [string]: Types.TrackerItem },
	upgradeOrder: { string },
	openPick3: { Types.Card }?,
	held: Types.Held,
	pityStreak: number,
	forcedRarity: number?,
	forceTradeoff: boolean,
	god: boolean,
	cratesTaken: { [string]: boolean },
	lastShotAt: number,
	nextUid: number,
	dirty: boolean,
	cooldowns: { [string]: number }, -- ability id -> server time the cooldown ends
	stimUntil: number, -- server time the stim buff ends, 0 = inactive
}

local states: { [Player]: State } = {}

local PlayerState = {}

local function freshState(player: Player): State
	return {
		player = player,
		cash = Config.StartingCash,
		upgradesBought = 0,
		weaponsBought = 0,
		upgrades = {},
		upgradeOrder = {},
		openPick3 = nil,
		held = { weaponId = Weapons.Starter, rarity = Rarity.Common, uid = 1 },
		pityStreak = 0,
		forcedRarity = nil,
		forceTradeoff = false,
		god = false,
		cratesTaken = {},
		lastShotAt = 0,
		nextUid = 2,
		dirty = true,
		cooldowns = {},
		stimUntil = 0,
	}
end

function PlayerState.get(player: Player): State
	local s = states[player]
	if not s then
		s = freshState(player)
		states[player] = s
	end
	return s
end

function PlayerState.all(): { [Player]: State }
	return states
end

function PlayerState.markDirty(player: Player)
	local s = states[player]
	if s then
		s.dirty = true
	end
end

function PlayerState.markAllDirty()
	for _, s in states do
		s.dirty = true
	end
end

function PlayerState.stimActive(state: State): boolean
	return state.stimUntil > Workspace:GetServerTimeNow()
end

function PlayerState.computed(state: State): Types.Computed
	local buffs: Stats.Buffs? = nil
	if PlayerState.stimActive(state) then
		buffs = { fireRateMult = Config.StimFireRateMult, moveSpeedMult = Config.StimMoveMult }
	end
	return Stats.compute(state.upgrades, state.held, buffs)
end

function PlayerState.damagePct(state: State): number
	local u = state.upgrades.Damage
	return if u then u.pct / 100 else 0
end

-- Held gun visual: a Part welded to the right hand so tracers have a muzzle. Rarity color only.
function PlayerState.refreshHeldVisual(state: State)
	local char = state.player.Character
	if not char then
		return
	end
	local old = char:FindFirstChild("HeldGun")
	if old then
		old:Destroy()
	end
	local hand = (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")) :: BasePart?
	if not hand then
		return
	end
	local gun = Instance.new("Part")
	gun.Name = "HeldGun"
	gun.Size = Vector3.new(0.35, 0.5, 1.6)
	gun.Color = Rarity.color(state.held.rarity)
	gun.Material = Enum.Material.Metal
	gun.CanCollide = false
	gun.CanQuery = false
	gun.CanTouch = false
	gun.Massless = true
	gun.CFrame = hand.CFrame * CFrame.new(0, -0.25, -0.9)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = gun
	weld.Parent = gun
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0, -0.8)
	muzzle.Parent = gun
	gun.Parent = char
end

function PlayerState.setHeld(state: State, weaponId: string, rarity: number)
	state.held = { weaponId = weaponId, rarity = rarity, uid = state.nextUid }
	state.nextUid += 1
	PlayerState.refreshHeldVisual(state)
	state.dirty = true
end

function PlayerState.applyCharacterStats(state: State)
	local char = state.player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local st = PlayerState.computed(state)
	local oldMax = hum.MaxHealth
	hum.MaxHealth = st.maxHP
	if oldMax > 0 and st.maxHP > oldMax then
		hum.Health = math.min(hum.Health + (st.maxHP - oldMax), st.maxHP)
	else
		hum.Health = math.clamp(hum.Health, 1, st.maxHP)
	end
	hum.WalkSpeed = st.moveSpeed
end

function PlayerState.reset(state: State)
	local fresh = freshState(state.player)
	for k, v in fresh do
		(state :: any)[k] = v
	end
	local char = state.player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.MaxHealth = Config.PlayerMaxHP
		hum.Health = Config.PlayerMaxHP
	end
	PlayerState.applyCharacterStats(state)
	PlayerState.refreshHeldVisual(state)
	state.dirty = true
end

-- Downed / revive is out of scope: hitting 0 resets health and prints.
function PlayerState.damage(player: Player, amount: number, source: string?)
	local state = states[player]
	if not state or state.god then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
	end
	local newHP = hum.Health - amount
	Remotes.Juice:FireClient(player, "PlayerHit", { amount = amount, source = source })
	if newHP <= 0 then
		hum.Health = hum.MaxHealth
		Log.event("Player", "%s reached 0 HP (downed flow is stubbed): health reset to %d", player.Name, hum.MaxHealth)
		Remotes.Juice:FireClient(player, "Downed", {})
		World.addHeat(Config.HeatDowned, player.Name .. " downed")
	else
		hum.Health = newHP
	end
end

function PlayerState.buildSync(state: State): Types.Sync
	local st = PlayerState.computed(state)
	local w = Weapons.ById[state.held.weaponId]
	local cratesTaken = {}
	for id in state.cratesTaken do
		table.insert(cratesTaken, id)
	end
	local total = 0
	for _, item in state.upgrades do
		total += item.count
	end
	return {
		wave = World.wave,
		waveState = World.state,
		intermissionEndsAt = World.intermissionEndsAt,
		heat = World.heat,
		cash = state.cash,
		gold = 0,
		maxHP = st.maxHP,
		held = {
			weaponId = w.id,
			displayName = w.displayName,
			archetype = w.archetype,
			rarity = state.held.rarity,
			rarityName = Rarity.name(state.held.rarity),
			dmg = st.damage,
			dps = Stats.weaponDps(w.id, state.held.rarity, state.upgrades),
			fireRate = st.fireRate,
			magSize = st.magSize,
			reloadTime = st.reloadTime,
			spread = w.spread * st.spreadMult,
			pellets = w.pellets,
			auto = w.auto,
			uid = state.held.uid,
		},
		stats = st,
		prices = {
			upgrade = Stats.upgradePrice(state.upgradesBought),
			weapon = Stats.weaponPrice(state.weaponsBought),
		},
		tracker = { order = state.upgradeOrder, items = state.upgrades, total = total },
		openPick3 = state.openPick3,
		cratesTaken = cratesTaken,
		god = state.god,
		abilities = {
			turret = { cooldown = Config.TurretCooldown, cooldownEndsAt = state.cooldowns.turret or 0 },
			barricade = { cooldown = Config.BarricadeCooldown, cooldownEndsAt = state.cooldowns.barricade or 0 },
			stim = {
				cooldown = Config.StimCooldown,
				cooldownEndsAt = state.cooldowns.stim or 0,
				activeUntil = state.stimUntil,
			},
		},
		spawnsPaused = World.spawnsPaused,
		debugEnabled = Config.DebugEnabled or RunService:IsStudio(),
		playerCount = #Players:GetPlayers(),
	}
end

-- Collision groups: enemies never body-block players (or each other) unless Config says so.
function PlayerState.setupCollisionGroups()
	for _, name in { "Player", "Enemy" } do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	PhysicsService:CollisionGroupSetCollidable("Enemy", "Player", Config.EnemyCollidesWithPlayers)
	PhysicsService:CollisionGroupSetCollidable("Enemy", "Enemy", Config.EnemyCollidesWithPlayers)
end

local function onCharacter(player: Player, char: Model)
	local state = PlayerState.get(player)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	for _, p in char:GetDescendants() do
		if p:IsA("BasePart") then
			p.CollisionGroup = "Player"
		end
	end
	char.DescendantAdded:Connect(function(p)
		if p:IsA("BasePart") then
			p.CollisionGroup = "Player"
		end
	end)
	-- Kill the default regen script; HP Regen is an upgrade stat here.
	local health = char:FindFirstChild("Health")
	if health then
		health:Destroy()
	end
	char.ChildAdded:Connect(function(c)
		if c.Name == "Health" and c:IsA("Script") then
			c:Destroy()
		end
	end)
	hum.MaxHealth = Config.PlayerMaxHP
	hum.Health = Config.PlayerMaxHP
	PlayerState.applyCharacterStats(state)
	task.spawn(function()
		char:WaitForChild("RightHand", 5)
		PlayerState.refreshHeldVisual(state)
	end)
	state.dirty = true
end

function PlayerState.init()
	PlayerState.setupCollisionGroups()
	local function onPlayer(player: Player)
		PlayerState.get(player)
		player.CharacterAdded:Connect(function(char)
			onCharacter(player, char)
		end)
		if player.Character then
			onCharacter(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	local acc = 0
	local forceAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		-- Regen
		for player, state in states do
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and hum.Health < hum.MaxHealth then
				local st = PlayerState.computed(state)
				hum.Health = math.min(hum.MaxHealth, hum.Health + st.hpRegen * dt)
			end
		end
		-- Flush dirty syncs at most 10x per second.
		acc += dt
		forceAcc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		-- A full resend every 2s covers a client that loaded after its first sync.
		local force = forceAcc >= 2 or World.heatDirty
		if force then
			forceAcc = 0
			World.heatDirty = false
		end
		for player, state in states do
			if state.dirty or force then
				state.dirty = false
				Remotes.StateSync:FireClient(player, PlayerState.buildSync(state))
			end
		end
	end)
end

return PlayerState
