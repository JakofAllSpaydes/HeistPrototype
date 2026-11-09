--!strict
-- Brief 12: what every explosion does after its damage. Knockback: a radial shove from the centre, KnockbackStuds at
-- the centre falling to 0 at the edge, x the archetype's KnockbackMult (x EliteKnockbackMult on elites; TITAN 0),
-- moved on the server over KnockbackSec (root movement, no physics force), clamped by a wall raycast so nobody leaves
-- the map, interrupting a wind-up or swing in progress (KnockbackInterrupt). Only enemies that survived the blast are
-- shoved (a kill ragdolls as before); players and placeables never move. Then the Explosion event: the client's
-- ExplosionFx draws the flash, the shock ring, dust and debris and the shooter's camera punch.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Enemy = require(script.Parent.Enemy)
local World = require(script.Parent.World)

local Explosion = {}

-- Debug `Combat log`: `[GHS Combat] knockback <archetype> <studs>` per shove.
Explosion.logEnabled = false

local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude

local function refreshWalls()
	local list: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, name in { "Enemies", "Structures", "Effects", "Corpses" } do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	wallParams.FilterDescendantsInstances = list
end

local function multFor(model: Model): number
	local d = Enemy.data(model)
	if not d then
		return 0
	end
	if d.row.boss == true then
		return (Config.KnockbackMult :: any).TITAN or 0
	end
	local m = (Config.KnockbackMult :: any)[d.row.id] or 1
	if d.elite then
		m *= Config.EliteKnockbackMult
	end
	return m
end

-- Shove one surviving enemy out of a blast at `at` of `radius`.
function Explosion.knock(model: Model, at: Vector3, radius: number)
	local d = Enemy.data(model)
	if not d then
		return
	end
	local m = multFor(model)
	if m <= 0 then
		return
	end
	local pos = d.root.Position
	local flat = Vector3.new(pos.X - at.X, 0, pos.Z - at.Z)
	local dist = flat.Magnitude
	local t = 1 - math.clamp(dist / math.max(radius, 0.1), 0, 1)
	local studs = Config.KnockbackStuds * t * m
	if studs < 0.2 then
		return
	end
	local dir = if dist > 0.05 then flat.Unit else Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
	-- Stop short of walls, pillars and props.
	local hit = Workspace:Raycast(pos, dir * (studs + 1.5), wallParams)
	if hit then
		studs = math.max(0, (hit.Position - pos).Magnitude - 1.5)
	end
	if studs < 0.2 then
		return
	end
	Enemy.shove(model, dir * studs, Config.KnockbackSec)
	if Config.KnockbackInterrupt and d.row.boss ~= true then
		Enemy.stun(model, Config.KnockbackStunSec)
	end
	if Explosion.logEnabled then
		print(string.format("[GHS Combat] knockback %s %.1f", tostring(d.row.id), studs))
	end
end

-- After an explosion's damage: shove the survivors among `victims`, then the look (everyone in the run sees it; the
-- owner's client adds the camera punch).
function Explosion.after(owner: Player?, at: Vector3, radius: number, color: Color3, victims: { Model }, shake: number?)
	refreshWalls()
	for _, model in victims do
		if Enemy.data(model) then
			Explosion.knock(model, at, radius)
		end
	end
	World.fireRun("Explosion", {
		position = at,
		radius = radius,
		color = color,
		owner = if owner then owner.UserId else 0,
		shake = shake,
	})
end

return Explosion
