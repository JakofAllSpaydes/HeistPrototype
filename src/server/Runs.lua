--!strict
-- Brief 8: concurrent runs on one server. Every run-scoped module lives under Run/ (World, the spawner, heat,
-- bags, the boss, the dealer, the pause, doors, the vault, the run start and end ...). Run/ itself is the HUB slot
-- (World.state is Hub forever; the shared modules require it directly) and Runs clones it once per live map
-- (`Run_<map>`): each clone is a full, independent run with its own World and module state, driven by its own
-- Run/Main loop. A party belongs to the slot of its map while its run cycle is on; its remotes are routed there
-- (RemoteRouter), its sync reads that slot's World (PlayerState), and everyone else stays in the hub slot.
-- `MapInstancesPerMap` caps the runs per map at once; the map geometry is one copy (doors, windows and the vault
-- are stateful parts), so it is capped at 1 until maps can be cloned.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Maps = require(ReplicatedStorage.Shared.Maps)
local RemoteRouter = require(script.Parent.RemoteRouter)
local Log = require(script.Parent.Log)

local template = script.Parent:WaitForChild("Run")

export type Slot = {
	id: string,
	mapId: string,
	isHub: boolean,
	folder: Instance,
	World: any,
}

local Runs = {}

Runs.hub = {
	id = "hub",
	mapId = "Hub",
	isHub = true,
	folder = template,
	World = require(template:WaitForChild("World")) :: any,
} :: Slot

Runs.slots = {} :: { Slot } -- the map slots, in Maps order

-- The hub slot and every map slot.
function Runs.allSlots(): { Slot }
	local out = { Runs.hub }
	for _, s in Runs.slots do
		table.insert(out, s)
	end
	return out
end

-- The slot whose party holds this player (from the queue start to the hub again), else the hub.
function Runs.slotOf(player: Player): Slot
	local id = player.UserId
	for _, s in Runs.slots do
		if table.find(s.World.party, id) then
			return s
		end
	end
	return Runs.hub
end

function Runs.worldOf(player: Player): any
	return Runs.slotOf(player).World
end

-- A module of a slot (cached by require; cheap).
function Runs.mod(slot: Slot, name: string): any
	return require(slot.folder:FindFirstChild(name) :: ModuleScript)
end

function Runs.modOf(player: Player, name: string): any
	return Runs.mod(Runs.slotOf(player), name)
end

-- In a party whose run cycle is on (the old World.inRunCycle() and World.isInParty(player)).
function Runs.inRunCycle(player: Player): boolean
	local s = Runs.slotOf(player)
	return not s.isHub and s.World.inRunCycle()
end

-- In a party whose run is live (the old World.inRun() and World.isInParty(player)).
function Runs.inRun(player: Player): boolean
	local s = Runs.slotOf(player)
	return not s.isHub and s.World.inRun()
end

function Runs.forMap(mapId: string): { Slot }
	local out = {}
	for _, s in Runs.slots do
		if s.mapId == mapId then
			table.insert(out, s)
		end
	end
	return out
end

local function idle(s: Slot): boolean
	local w = s.World
	return w.state == "Hub" and not w.runRequested and #w.party == 0
end

-- A slot on this map with no party: where a new run can start.
function Runs.freeSlot(mapId: string): Slot?
	for _, s in Runs.forMap(mapId) do
		if idle(s) then
			return s
		end
	end
	return nil
end

-- Who is inside a busy map (the first member of the run holding it), for MAP BUSY · <name> IS INSIDE.
function Runs.busyBy(mapId: string): string?
	for _, s in Runs.forMap(mapId) do
		if not idle(s) then
			local first = s.World.party[1]
			local p = first and Players:GetPlayerByUserId(first)
			return if p then p.Name else "A CREW"
		end
	end
	return nil
end

-- Runs in progress (any map).
function Runs.active(): { Slot }
	local out = {}
	for _, s in Runs.slots do
		if not idle(s) then
			table.insert(out, s)
		end
	end
	return out
end

-- Clone Run/ once per live map, configure each clone, then start every slot's Main (the hub's first).
function Runs.start()
	-- The shared world folders exist before any run module loads: several wait on them at require time (Bags,
	-- WeaponRoll, Combat wait for Effects / GroundLoot), and Room.build only runs inside Main.start, after those
	-- requires. Without this the first require of Run/Main hangs forever.
	for _, name in { "Enemies", "GroundLoot", "Effects" } do
		local existing = Workspace:FindFirstChild(name)
		if not (existing and existing:IsA("Folder")) then
			local f = Instance.new("Folder")
			f.Name = name
			f.Parent = Workspace
		end
	end
	RemoteRouter.slotOf = function(player: Player): string
		return Runs.slotOf(player).id
	end
	local per = math.max(1, math.floor(Config.MapInstancesPerMap or 1))
	if per > 1 then
		warn(
			string.format(
				"[GHS Runs] MapInstancesPerMap %d needs a copy of each map (out of scope): capped to 1 run per map",
				per
			)
		)
	end
	for _, m in Maps.live() do
		local clone = template:Clone()
		clone.Name = "Run_" .. m.id
		local id = string.lower(m.id)
		require(clone:WaitForChild("Slot") :: ModuleScript).configure(id, m.id)
		clone.Parent = script.Parent
		local slot: Slot = {
			id = id,
			mapId = m.id,
			isHub = false,
			folder = clone,
			World = require(clone:WaitForChild("World") :: ModuleScript),
		}
		slot.World.map = m.id
		table.insert(Runs.slots, slot)
	end
	require(template:WaitForChild("Main") :: ModuleScript).start()
	for _, s in Runs.slots do
		require(s.folder:WaitForChild("Main") :: ModuleScript).start()
	end
	Log.event(
		"Runs",
		"%d run slot%s: %s",
		#Runs.slots,
		if #Runs.slots == 1 then "" else "s",
		(function()
			local ids = {}
			for _, s in Runs.slots do
				table.insert(ids, s.mapId)
			end
			return table.concat(ids, ", ")
		end)()
	)
end

return Runs
