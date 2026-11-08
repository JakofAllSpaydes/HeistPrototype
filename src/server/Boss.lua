--!strict
-- The boss shell: a registry of boss modules (id, name, subtitle, row, brain) and the pre-wave cutscene.
-- Boss waves (World.isBossWave) run the cutscene in the intermission: the game pauses (no brains, players
-- invulnerable and input-locked, AUTO SKIP ignored), MARLOW calls it, the wall by the marker farthest from
-- the crew blows, the boss steps through, the camera pushes in on the gun with the name card, snaps back
-- and the bar slides in; then the wave starts. A second boss id drops in here without changes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Lines = require(Shared.CrewCall.Lines)
local Enemy = require(script.Parent.Enemy)
local Room = require(script.Parent.Room)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
local PlayerState = require(script.Parent.PlayerState)

local Boss = {}

Boss.registry = {
	Titan = require(script.Parent.Bosses.Titan),
} :: { [string]: any }

local activeModel: Model? = nil

function Boss.isActive(): boolean
	local m = activeModel
	return m ~= nil and m.Parent ~= nil and m:FindFirstChildOfClass("Humanoid") ~= nil and Enemy.data(m) ~= nil
end

function Boss.module(id: string?): any?
	return Boss.registry[id or Config.BossId]
end

-- Spawn a boss at a floor point, tagged with `wave`.
function Boss.spawn(id: string, wave: number, position: Vector3): Model?
	local mod = Boss.registry[id]
	if not mod then
		Log.event("Boss", "no boss module for %s", id)
		return nil
	end
	local model = Enemy.spawn(id, wave, position, { row = mod.row(), brain = mod })
	activeModel = model
	Log.event("Boss", "%s entered at wave %d with %d HP", mod.name, wave, math.round(Enemy.data(model).maxHP))
	return model
end

-- The marker farthest from the crew, and the wall point behind it.
local function entrance(): (Vector3, Vector3)
	local points = {}
	for _, box in Room.current().spawnBoxes do
		table.insert(points, box.cframe.Position)
	end
	local best = points[1] or Vector3.zero
	local bestDist = -1
	for _, p in points do
		local nearest = math.huge
		for _, player in World.runAudience() do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				nearest = math.min(nearest, (root.Position - p).Magnitude)
			end
		end
		if nearest == math.huge then
			nearest = p.Magnitude
		end
		if nearest > bestDist then
			bestDist = nearest
			best = p
		end
	end
	local out = Vector3.new(best.X, 0, best.Z)
	local dir = if out.Magnitude > 0.1 then out.Unit else Vector3.zAxis
	local wall = dir * (Config.RoomSize / 2 - 0.5)
	return best, Vector3.new(wall.X, Config.FloorTop, wall.Z)
end

-- Debris off the wall: a few dark chunks flung into the room.
local function blowWall(wallPoint: Vector3)
	local effects = Workspace:FindFirstChild("Effects") or Workspace
	local inward = -Vector3.new(wallPoint.X, 0, wallPoint.Z).Unit
	for _ = 1, 10 do
		local chunk = Instance.new("Part")
		chunk.Size = Vector3.new(1 + math.random() * 1.5, 1 + math.random() * 1.5, 0.8)
		chunk.Color = Color3.fromRGB(44, 44, 50)
		chunk.Material = Enum.Material.Concrete
		chunk.CFrame = CFrame.new(wallPoint + Vector3.new((math.random() - 0.5) * 8, 2 + math.random() * 8, 0))
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.CollisionGroup = "Corpse"
		chunk.Parent = effects
		chunk.AssemblyLinearVelocity = inward * (18 + math.random() * 14)
			+ Vector3.new((math.random() - 0.5) * 10, 10 + math.random() * 10, (math.random() - 0.5) * 10)
		task.delay(3 + math.random(), function()
			chunk:Destroy()
		end)
	end
	World.fireRun("BossWallBlow", { position = wallPoint })
end

-- Yields BossCutsceneSec. The boss steps in during it, tagged with `wave`.
function Boss.cutscene(wave: number)
	local mod = Boss.module()
	if not mod then
		return
	end
	local beats = Config.BossCutsceneBeats
	local sec = Config.BossCutsceneSec
	local marker, wallPoint = entrance()
	local startedAt = Workspace:GetServerTimeNow()
	Enemy.paused = true
	for _, player in World.runAudience() do
		local state = PlayerState.get(player)
		state.invulnUntil = math.max(state.invulnUntil, startedAt + sec + 1)
	end
	World.fireRun("BossCutscene", {
		startedAt = startedAt,
		sec = sec,
		beats = beats,
		bossId = mod.id,
		name = mod.name,
		subtitle = mod.subtitle,
		marker = marker,
		wallPoint = wallPoint,
		crewLead = Lines.boss.crewLead,
		typeLabel = Lines.boss.typeLabel,
		text = Lines.boss.text,
		kind = Lines.boss.kind,
	})
	Log.event(
		"Boss",
		"cutscene for %s (%.1fs), entrance at (%d, %d)",
		mod.name,
		sec,
		math.round(marker.X),
		math.round(marker.Z)
	)
	task.wait(math.max(0, beats.blow))
	if World.runOver then
		Enemy.paused = false
		return
	end
	blowWall(wallPoint)
	-- Steps through the wall onto the marker: spawned in the gap, walked in by its brain while paused.
	local inside = wallPoint + (marker - wallPoint).Unit * 2
	local model = Boss.spawn(mod.id, wave, Vector3.new(inside.X, Config.FloorTop, inside.Z))
	local d = model and Enemy.data(model)
	if d then
		d.mem.cutsceneTarget = marker
		d.root.CFrame = CFrame.lookAt(d.root.Position, Vector3.new(0, d.root.Position.Y, 0))
	end
	task.wait(math.max(0, sec - beats.blow))
	if d then
		d.mem.cutsceneTarget = nil
	end
	Enemy.paused = false
end

function Boss.clear()
	activeModel = nil
	World.bossView = nil
end

return Boss
