--!strict
-- Debug commands, server side. Only honoured in Studio or when Config.DebugEnabled.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(script.Parent.SlotRemotes)
local Rarity = require(Shared.Rarity)
local Enemies = require(Shared.Enemies)
local Classes = require(Shared.Classes)
local Room = require(script.Parent.Room)
local PlayerState = require(script.Parent.Parent.PlayerState)
local Stats = require(script.Parent.Parent.Stats)
local Economy = require(script.Parent.Parent.Economy)
local Enemy = require(script.Parent.Enemy)
local WeaponRoll = require(script.Parent.WeaponRoll)
local BigCrate = require(script.Parent.BigCrate)
local CrewCall = require(script.Parent.CrewCall)
local Abilities = require(script.Parent.Abilities)
local Explosion = require(script.Parent.Explosion) -- brief 12
local World = require(script.Parent.World)

-- Brief 8: the players this run slot looks after (its party; the hub slot: everyone not in a run).
local function mine(): { [Player]: PlayerState.State }
	local out = {}
	for _, p in World.runAudience() do
		out[p] = PlayerState.get(p)
	end
	return out
end
local Log = require(script.Parent.Parent.Log)
local Hub = require(script.Parent.Parent.Hub)
local Minigames = require(script.Parent.Minigames)
local Downed = require(script.Parent.Downed)
local Profiles = require(script.Parent.Parent.Profiles)
local Queue = require(script.Parent.Parent.Queue)
local Heat = require(script.Parent.Heat)
local Bags = require(script.Parent.Bags)
local VaultJob = require(script.Parent.VaultJob)
local ZoneGas = require(script.Parent.ZoneGas) -- Round 19c
local Offices = require(script.Parent.Offices) -- Round 19f
local Boss = require(script.Parent.Boss)
local Progression = require(script.Parent.Parent.Progression)
local Mastery = require(script.Parent.Mastery)
local Dealer = require(script.Parent.Dealer)
local Pause = require(script.Parent.Pause)
local Purchases = require(script.Parent.Parent.Purchases)
local CrateOpen = require(script.Parent.Parent.CrateOpen)
local Pass = require(script.Parent.Parent.Pass)
local Jobs = require(script.Parent.Parent.Jobs)
local MapLoader = require(script.Parent.MapLoader)
local Doors = require(script.Parent.Doors)
local Spawner = require(script.Parent.Spawner)
local EnemyPath = require(script.Parent.EnemyPath)
local Runs = require(script.Parent.Parent.Runs)
local HubMap = require(script.Parent.Parent.HubMap)
local SkillService = require(script.Parent.Parent.SkillService)
local Streak = require(script.Parent.Parent.Streak)
local DailyCrate = require(script.Parent.Parent.DailyCrate)

local Debug = {}

local pathDebug: { [Player]: boolean } = {}

local function toast(player: Player, text: string)
	Remotes.Juice:FireClient(player, "Toast", { text = text })
end

-- Brief 8: the hub slot's range (the debug range commands always act on the hub's range).
local function range(): any
	return Runs.mod(Runs.hub, "Range")
end

local handlers: { [string]: (Player, PlayerState.State, any) -> () } = {
	-- Brief 8 HUB: teleports, the dummies, the garage, the pads, a moving target in the range.
	TeleportHub = function(player, _state, _args)
		if Runs.inRunCycle(player) then
			toast(player, "IN A RUN")
			return
		end
		local cf = Hub.spawnCFrame(player)
		if cf and player.Character then
			player.Character:PivotTo(cf)
		end
	end,
	TeleportRange = function(player, _state, _args)
		if Runs.inRunCycle(player) then
			toast(player, "IN A RUN")
			return
		end
		local r = HubMap.view and HubMap.view.range
		if not r or not player.Character then
			toast(player, "NO RANGE NODE")
			return
		end
		-- Just inside the door, facing the dummies.
		local door = HubMap.view and HubMap.view.rangeDoor
		local at = if door then door.part.Position + door.part.CFrame.LookVector * 8 else r.cframe.Position
		local floor = r.cframe.Position.Y - r.size.Y / 2
		local p = Vector3.new(at.X, floor + 3, at.Z)
		local look = if door then door.part.CFrame.LookVector else Vector3.new(-1, 0, 0)
		player.Character:PivotTo(CFrame.lookAt(p, p + look * Vector3.new(1, 0, 1)))
	end,
	ResetDummies = function(player, _state, _args)
		range().resetAll(player.Name)
	end,
	OpenGarage = function(_player, _state, _args)
		Hub.openGarage()
	end,
	ForcePad = function(_player, _state, args)
		Queue.forcePad(math.clamp(math.floor(tonumber(args) or 1), 1, 4))
	end,
	RangeSpawn = function(player, _state, args)
		local s = tostring(args)
		local model: Model? = nil
		if s == "boss" then
			model = range().spawnBoss()
		else
			local elite = string.sub(s, 1, 6) == "elite:"
			model = range().spawnEnemy(if elite then string.sub(s, 7) else s, elite)
		end
		if not model then
			toast(player, "NO RANGE NODE")
		end
	end,
	-- Brief 7 MAP: re-read Workspace.Bank.Nodes after a Studio drag, without restarting.
	-- Brief 7 MAP: stand on the zone's first bag spot (THE BANK; works in the hub or a run on any map).
	TeleportZone = function(player, _state, args)
		local zone = tostring(args)
		local char = player.Character
		for _, s in MapLoader.bagSpots do
			if s.zone == zone and char then
				char:PivotTo(CFrame.new(s.position + Vector3.new(0, 3, 0)))
				return
			end
		end
		toast(player, "NO SPOT IN ZONE " .. zone)
	end,
	-- Brief 7 MAP: complete a door group's objective at once (D4 opens the vault, step 6).
	OpenDoor = function(player, _state, args)
		local group = tostring(args)
		if not MapLoader.doors[group] then
			toast(player, "NO DOOR " .. group)
			return
		end
		-- The vault's wheel door opens through the vault job (its window, burst, gas and seal).
		if MapLoader.vaultRoom and group == MapLoader.vaultRoom.door then
			if VaultJob.phase == "job" then
				CrewCall.finish(true)
			elseif VaultJob.phase == "closed" then
				VaultJob.open()
			else
				toast(player, "VAULT IS " .. string.upper(VaultJob.phase))
			end
			return
		end
		Doors.open(group, nil)
	end,
	-- Back to the wave 1 state: every door closed, the hatch shut, nothing queued.
	CloseAllDoors = function(_player, _state, _args)
		CrewCall.clearAll()
		VaultJob.resetRun()
		Doors.resetRun()
	end,
	RecomputeNodes = function(player, _state, _args)
		MapLoader.read()
		toast(
			player,
			string.format("NODES RE-READ · %d ERROR%s", MapLoader.errors, if MapLoader.errors == 1 then "" else "S")
		)
	end,
	AddCash = function(_player, state, args)
		Economy.addCash(state, tonumber(args) or 0)
	end,
	SkipWave = function(_player, _state, _args)
		World.skipRequested = true
	end,
	SetWave = function(player, _state, args)
		local n = tonumber(args)
		if n and n >= 1 then
			World.pendingWave = math.floor(n)
			World.skipRequested = true
		else
			toast(player, "SET WAVE: enter a number")
		end
	end,
	PauseSpawns = function(player, _state, _args)
		World.spawnsPaused = not World.spawnsPaused
		PlayerState.markAllDirty()
		toast(player, if World.spawnsPaused then "SPAWNS PAUSED" else "SPAWNS RESUMED")
	end,
	KillAll = function(_player, _state, _args)
		Enemy.killAll()
	end,
	-- Spawn one archetype (args = id, "elite:<id>" for an elite) at the marker nearest the player.
	SpawnEnemy = function(player, _state, args)
		local id = tostring(args)
		local elite = false
		if string.sub(id, 1, 6) == "elite:" then
			elite = true
			id = string.sub(id, 7)
		end
		-- Brief 7: "<id>@<box>" spawns at a named spawn box (THE BANK's or the current map's).
		local boxName = string.match(id, "@(.+)$")
		id = string.gsub(id, "@.*$", "")
		if not Enemies.ById[id] then
			toast(player, "NO SUCH ENEMY: " .. id)
			return
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local box, best = Room.nearestBox(if root then root.Position else nil)
		if boxName then
			for _, b in MapLoader.boxes do
				if b.name == boxName then
					box, best = b, Room.pointInBox(b)
				end
			end
			for _, b in Room.current().spawnBoxes do
				if b.name == boxName then
					box, best = b, Room.pointInBox(b)
				end
			end
		end
		Enemy.spawn(id, World.wave, best, { elite = elite, box = box })
		World.enemiesLeft = math.max(World.enemiesLeft, Enemy.count())
		PlayerState.markAllDirty()
	end,
	ForceRarity = function(player, state, args)
		local r = if typeof(args) == "number" then args else Rarity.fromLetter(tostring(args))
		if r then
			state.forcedRarity = r
			CrateOpen.forced[player] = r -- brief 6: the next paid / free crate open too
			toast(player, "NEXT ROLL: " .. string.upper(Rarity.name(r)))
		end
	end,
	------------------------------------------------------------------ Brief 6 (monetization)
	SetRobux = function(player, _state, args)
		Purchases.setBalance(player, tonumber(args) or 0)
		toast(player, "R$ BALANCE SET")
	end,
	SetTokens = function(player, state, args)
		local p = Profiles.get(player)
		if p then
			p.reviveTokens = math.max(0, math.floor(tonumber(args) or 0))
			Profiles.markDirty(player)
			state.dirty = true
			Log.event("Tokens", "%s set to %d (debug)", player.Name, p.reviveTokens)
		end
	end,
	CrateCredits = function(player, _state, args)
		CrateOpen.grantCredits(player, tostring(args), 10)
		toast(player, "+10 FREE " .. string.upper(tostring(args)) .. " OPENS")
	end,
	AdvanceDay = function(player, _state, args)
		Pass.advanceDay(player, math.max(1, math.floor(tonumber(args) or 1)))
		Jobs.normalize(player)
		Streak.offer(player) -- brief 10: the new day's streak modal
		toast(player, "FAKE CLOCK +" .. math.max(1, math.floor(tonumber(args) or 1)) .. " DAY")
	end,
	------------------------------------------------------------------ Brief 10 (retention)
	SetStreakDay = function(player, _state, args)
		Streak.debugSetDay(player, tonumber(args) or 1)
		toast(player, "STREAK · NEXT CLAIM DAY " .. math.clamp(math.floor(tonumber(args) or 1), 1, 28))
	end,
	BreakStreak = function(player, _state, _args)
		Streak.debugBreak(player)
		toast(player, "STREAK BROKEN")
	end,
	UnlockDailyCrate = function(player, _state, _args)
		DailyCrate.debugUnlock(player)
		toast(player, "DAILY CRATE UNLOCKED")
	end,
	ResetDailyCrate = function(player, _state, _args)
		DailyCrate.debugReset(player)
		toast(player, "DAILY CRATE RESET · NEVER OPENED")
	end,
	ForceDailyTier = function(player, _state, args)
		DailyCrate.debugForceTier(player, tostring(args))
		toast(player, "DAILY TIER · " .. string.upper(tostring(args)))
	end,
	AddPassXp = function(player, _state, args)
		Pass.addXp(player, tonumber(args) or 1000, "debug")
	end,
	ResetJobs = function(player, _state, _args)
		Jobs.reset(player)
		toast(player, "JOBS RESET")
	end,
	-- The purchase log readout: every fake purchase on the profile, totals per kind.
	PurchaseLog = function(player, _state, _args)
		local p = Profiles.get(player)
		if not p then
			return
		end
		local total = 0
		local byId: { [string]: { n: number, spent: number } } = {}
		print(
			string.format(
				"[GHS Purchase] readout for %s: %d purchases, balance R$ %d, %d tokens",
				player.Name,
				#p.purchases,
				p.fakeRobux,
				p.reviveTokens
			)
		)
		for _, e in p.purchases do
			total += e.price
			local row = byId[e.id] or { n = 0, spent = 0 }
			row.n += 1
			row.spent += e.price
			byId[e.id] = row
			print(string.format(
				"  %s  %-22s R$%d",
				(function()
					local t = os.date("!*t", e.at) :: any
					return string.format("%04d-%02d-%02d %02d:%02d", t.year, t.month, t.day, t.hour, t.min)
				end)(),
				e.id,
				e.price
			))
		end
		for id, row in byId do
			print(string.format("  total %-22s x%d  R$%d", id, row.n, row.spent))
		end
		print(string.format("  spent R$%d in all", total))
		toast(player, "PURCHASE LOG PRINTED")
	end,
	ForceTradeoff = function(player, state, _args)
		state.forceTradeoff = true
		toast(player, "NEXT PICK-3 HAS A TRADEOFF")
	end,
	OpenDealer = function(player, _state, _args)
		if Dealer.isActive() then
			toast(player, "DEALER ALREADY OPEN")
			return
		end
		Dealer.requested = true
		toast(player, if World.state == "Intermission" then "DEALER OPENING" else "DEALER OPENS AFTER THIS WAVE")
	end,
	TogglePause = function(player, _state, _args)
		Pause.debugToggle(player)
	end,
	AddMastery = function(player, _state, _args)
		Mastery.debugAdd(player, 100)
		toast(player, "+100 MASTERY · GUN AND CLASS")
	end,
	ForceElement = function(player, state, _args)
		state.forceElement = true
		toast(player, "NEXT PICK-3 HAS AN ELEMENT")
	end,
	ForceSynergy = function(player, state, _args)
		state.forceSynergy = true
		toast(player, "NEXT PICK-3 HAS A SYNERGY (IF ONE QUALIFIES)")
	end,
	DropCrate = function(_player, _state, _args)
		BigCrate.drop()
	end,
	TriggerCall = function(_player, _state, _args)
		CrewCall.trigger()
	end,
	GodMode = function(player, state, _args)
		state.god = not state.god
		toast(player, if state.god then "GOD MODE ON" else "GOD MODE OFF")
	end,
	-- Round 18: abilities fire back to back (no charge spent, no recharge); clears any cooldown already running.
	NoCooldowns = function(player, state, _args)
		state.noCooldowns = not state.noCooldowns
		if state.noCooldowns then
			state.charges = {}
			state.cooldowns = {}
		end
		state.dirty = true
		toast(player, if state.noCooldowns then "NO COOLDOWNS ON" else "NO COOLDOWNS OFF")
	end,
	ResetRun = function(_player, _state, _args)
		for _, s in mine() do
			PlayerState.reset(s, if World.inRun() then Config.StartingCash else Config.HubCash)
			if World.inRun() or s.inRange then
				PlayerState.armSkills(s, "debug reset run") -- brief 9
				if World.inRun() then
					s.cash += Stats.resolve(s.player, "startCash")
				end
			end
		end
		BigCrate.finishAll()
		CrewCall.clearAll()
		WeaponRoll.clearAll()
		Abilities.clearAll()
		Enemy.killAll()
		World.spawnsPaused = false
		World.pendingWave = 1
		World.skipRequested = true
	end,
	-- Force a run: the player's party (or a party of just them) starts now, whatever the countdown says.
	StartRun = function(player, _state, _args)
		if World.state == "Hub" then
			Queue.forceStart(player)
		else
			toast(player, "ALREADY IN A RUN")
		end
	end,
	AddGold = function(player, _state, args)
		Profiles.addGold(player, tonumber(args) or 1000, "debug")
	end,
	ResetProfile = function(player, state, _args)
		Profiles.reset(player)
		PlayerState.applyProfile(state)
		toast(player, "PROFILE RESET")
	end,
	UnlockAll = function(player, state, _args)
		Profiles.unlockAll(player)
		PlayerState.applyProfile(state)
		toast(player, "EVERYTHING UNLOCKED")
	end,
	-- Brief 9: the Skill Web.
	UnlockSkills = function(player, _state, _args)
		SkillService.unlockAll(player)
		toast(player, "ALL SKILLS UNLOCKED")
	end,
	ResetSkills = function(player, _state, _args)
		SkillService.reset(player)
		toast(player, "SKILLS RESET")
	end,
	GrantSkill = function(player, _state, args)
		local branch = if typeof(args) == "table" then tostring(args.branch) else ""
		local ring = if typeof(args) == "table" then tonumber(args.ring) or 1 else 1
		local id = SkillService.grant(player, branch, ring)
		toast(player, if id then "GRANTED " .. string.upper(id) else "NOTHING LEFT IN " .. branch .. " RING " .. ring)
	end,
	EndRun = function(player, _state, _args)
		if World.inRun() then
			World.runOver = true
			World.skipRequested = true
		else
			toast(player, "NO RUN TO END")
		end
	end,
	SetTier = function(player, _state, args)
		Hub.setTier(tonumber(args) or 1, player.Name)
	end,
	OpenMinigame = function(player, _state, args)
		Minigames.open(player, tostring(args))
	end,
	MinigameStats = function(player, _state, _args)
		Minigames.printStats()
		Heat.printStats()
		Economy.printStats()
		MapLoader.printStats(Doors.openedLog, Spawner.contactRun, EnemyPath.history)
		SkillService.printStats(player) -- brief 9: owned per branch and the modifier table
		Stats.print(player) -- brief 12: every resolved stat, its mode and its sources
		Streak.printStats(player) -- brief 10
		DailyCrate.printStats(player)
	end,
	-- Brief 7 MAP: pin the crew zone (spawns, bursts, the boss wall and the dealer follow it); "auto" unpins.
	SetCrewZone = function(player, _state, args)
		local z = tostring(args)
		if z == "auto" then
			MapLoader.pinnedZone = nil
			toast(player, "CREW ZONE · AUTO")
		elseif MapLoader.zones[z] then
			MapLoader.pinnedZone = z
			toast(player, "CREW ZONE · " .. string.upper(z))
		end
	end,
	-- Path debug: this player gets every pathing enemy's route twice a second.
	PathDebug = function(player, _state, _args)
		pathDebug[player] = if pathDebug[player] then nil else true
		toast(player, if pathDebug[player] then "PATH DEBUG ON" else "PATH DEBUG OFF")
		if not pathDebug[player] then
			Remotes.Juice:FireClient(player, "PathDebug", { paths = {} })
		end
	end,
	-- The boss without the cutscene, at the marker nearest the player.
	SpawnBoss = function(player, _state, _args)
		if not World.inRun() then
			toast(player, "NO RUN")
			return
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local _, best = Room.nearestBox(if root then root.Position else nil)
		Boss.spawn(Config.BossId, World.wave, best)
		World.enemiesLeft = math.max(World.enemiesLeft, Enemy.count())
		PlayerState.markAllDirty()
	end,
	SpawnBag = function(player, _state, args)
		Bags.debugSpawn(player, tostring(args))
	end,
	-- Loot Rush: a bag burst round the player (bypasses the cap), to test a pile of pickups at once.
	LootRush = function(player, _state, _args)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or not World.inRun() then
			toast(player, "NO RUN")
			return
		end
		Bags.burstAround(root.Position, Config.LootRushCash, Config.LootRushGold, Config.LootRushRadius)
		toast(player, "LOOT RUSH")
	end,
	OpenVault = function(player, _state, _args)
		if VaultJob.phase == "closed" or VaultJob.phase == "job" then
			if VaultJob.phase == "job" then
				CrewCall.finish(true)
			else
				VaultJob.open()
			end
		else
			toast(player, "VAULT IS " .. string.upper(VaultJob.phase))
		end
	end,
	-- Brief 7: the seal waits for an empty room as always: this brings the gas in now.
	SealVault = function(player, _state, _args)
		if VaultJob.phase == "open" or VaultJob.phase == "warn" then
			VaultJob.debugGas()
		end
		toast(player, "VAULT SEALS WHEN EMPTY")
	end,
	-- Round 19c: the zone gas on the crew zone now; the two new side jobs on demand.
	ZoneGasNow = function(player, _state, _args)
		if World.map == "Arena" then
			toast(player, "ZONE GAS IS THE BANK ONLY")
			return
		end
		ZoneGas.debugNow()
	end,
	-- Round 19d: lockdown gas on the called door now (call one first: Open D-row / wait for its wave).
	LockdownNow = function(player, _state, _args)
		if World.map == "Arena" or not ZoneGas.debugForce() then
			toast(player, "NO DOOR CALLED")
		end
	end,
	AlarmJob = function(_player, _state, _args)
		CrewCall.trigger("alarm")
	end,
	-- Round 19f: RAID THE OFFICE now (an office in an open zone), or blow the nearest office open with no job.
	OfficeJob = function(player, _state, _args)
		local off = CrewCall.office
		if not (off and off.available()) then
			toast(player, "NO OFFICE OPEN TO RAID")
			return
		end
		CrewCall.trigger("office")
	end,
	OpenOffice = function(player, _state, _args)
		if not Offices.debugOpen(player) then
			toast(player, "NO CLOSED OFFICE")
		end
	end,
	CutJob = function(_player, _state, _args)
		CrewCall.trigger("Cut")
	end,
	GasVault = function(player, _state, _args)
		if VaultJob.phase == "open" or VaultJob.phase == "warn" then
			VaultJob.debugGas()
		else
			toast(player, "VAULT IS " .. string.upper(VaultJob.phase))
		end
	end,
	AddXp = function(player, state, args)
		Progression.addXp(player, tonumber(args) or 500)
		Hub.refreshTag(player)
		state.dirty = true
	end,
	SetLevel = function(player, state, args)
		local n = tonumber(args)
		if n then
			Progression.setLevel(player, n)
			Hub.refreshTag(player)
			state.dirty = true
		else
			toast(player, "SET LEVEL: enter a number")
		end
	end,
	-- Round 27g: the whole first-run-of-the-day state: the x2 XP flag (and with it the PLAY bar) and the daily crate
	-- (locked, never opened), so the first run of the day can be tested end to end.
	ResetDaily = function(player, _state, _args)
		Progression.resetDaily(player)
		DailyCrate.debugReset(player)
		toast(player, "DAILY RESET · X2 XP + CRATE")
	end,
	SetHeat = function(player, _state, args)
		local n = tonumber(args)
		if n then
			Heat.set(n)
			toast(player, string.format("HEAT %.1f", World.heat))
		else
			toast(player, "SET HEAT: enter a number")
		end
	end,
	DownMe = function(player, _state, _args)
		Downed.down(player)
	end,
	DownAll = function(_player, _state, _args)
		for p, s in mine() do
			if PlayerState.isStanding(s) then
				Downed.down(p)
			end
		end
	end,
	ReviveAll = function(_player, _state, _args)
		Downed.reviveEverybody(nil)
	end,
	-- Brief 12: the resolver's debug (the STATS block prints with the Stats button).
	StatsLog = function(player, _state, _args)
		Stats.logEnabled = not Stats.logEnabled
		toast(player, if Stats.logEnabled then "STATS LOG ON" else "STATS LOG OFF")
	end,
	SetHaste = function(player, state, args)
		local n = tonumber(args) or 0
		for stat, def in Config.StatDefs :: { [string]: any } do
			if def.mode == "haste" and stat ~= "typeReload" then
				Stats.add(player, "debug:haste:" .. stat, stat, n)
			end
		end
		PlayerState.applyCharacterStats(state)
		toast(player, string.format("HASTE OVERRIDE %+d", n))
	end,
	-- "claymore 3" puts Claymore on slot 3 (any ability, the unassigned pool included); "clear" drops every grant.
	GrantAbility = function(player, state, args)
		local text = string.lower(tostring(args or ""))
		local id, slotText = string.match(text, "^%s*(%S+)%s*(%d?)")
		if not id or id == "clear" then
			table.clear(state.grants)
			toast(player, "GRANTS CLEARED")
			return
		end
		if not Classes.AbilityById[id] then
			toast(player, "NO ABILITY " .. string.upper(id))
			return
		end
		local slot = math.clamp(tonumber(slotText) or 3, 1, 3)
		state.grants[slot] = id
		state.charges[id] = nil
		state.cooldowns[id] = 0
		toast(player, string.format("%s ON SLOT %d", string.upper(Classes.AbilityById[id].name), slot))
	end,
	CombatLog = function(player, _state, _args)
		Explosion.logEnabled = not Explosion.logEnabled
		toast(player, if Explosion.logEnabled then "COMBAT LOG ON" else "COMBAT LOG OFF")
	end,
	SpawnDrones = function(player, _state, args)
		local n = tonumber(args) or 10
		Abilities.spawnDrones(player, n)
		toast(player, string.format("+%d DRONES", n))
	end,
	-- Equip any class at once (owned for the test); a run in progress keeps its mastery snapshot.
	ForceClass = function(player, state, args)
		local id = string.upper(tostring(args or ""))
		local c = Classes.ById[id]
		if not c then
			for _, cl in Classes.List do
				if cl.displayName == id then
					c = cl
				end
			end
		end
		local p = state.profile
		if not c or not p then
			toast(player, "NO CLASS " .. id)
			return
		end
		p.classes.owned[c.id] = true
		p.classes.equipped = c.id
		state.cooldowns = {}
		state.charges = {}
		Profiles.markDirty(player)
		PlayerState.registerPassives(state)
		Hub.refreshTag(player)
		Log.event("Class", "%s %s forced by %s", string.lower(c.id), c.displayName, player.Name)
		toast(player, c.displayName .. " FORCED")
	end,
	SetArea = function(player, _state, args)
		local n = tonumber(args) or 0
		Stats.add(player, "debug:area", "area", n)
		toast(player, string.format("AREA OVERRIDE %+d (now %+d%%)", n, math.round(Stats.resolve(player, "area"))))
	end,
}

function Debug.init()
	-- Path debug: twice a second, the routes of the 30 pathing enemies nearest each watching player.
	task.spawn(function()
		while true do
			task.wait(0.5)
			if not next(pathDebug) then
				continue
			end
			local views = EnemyPath.debugView(Enemy.all())
			for player in table.clone(pathDebug) do
				if not player.Parent then
					pathDebug[player] = nil
					continue
				end
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local origin = if root then root.Position else Vector3.zero
				table.sort(views, function(a, b)
					return (a.from - origin).Magnitude < (b.from - origin).Magnitude
				end)
				local out = {}
				for i = 1, math.min(30, #views) do
					local v = views[i]
					local pts = {}
					for k = 1, math.min(15, #v.pts) do
						pts[k] = v.pts[k]
					end
					table.insert(out, { from = v.from, pts = pts, stuck = v.stuck })
				end
				Remotes.Juice:FireClient(player, "PathDebug", { paths = out })
			end
		end
	end)
	Remotes.Debug.OnServerEvent:Connect(function(player: Player, command: any, args: any)
		if not (Config.DebugEnabled or RunService:IsStudio()) then
			return
		end
		local handler = handlers[tostring(command)]
		if not handler then
			return
		end
		local state = PlayerState.get(player)
		handler(player, state, args)
		state.dirty = true
		Log.event("Debug", "%s ran %s %s", player.Name, tostring(command), if args ~= nil then tostring(args) else "")
	end)
end

return Debug
