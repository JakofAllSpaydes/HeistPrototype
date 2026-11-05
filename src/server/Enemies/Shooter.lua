--!strict
-- Shooter: advances to range of the nearest visible player, holds, and fires every cooldown. Each shot
-- lands with Config.ShooterHitChance; a miss cracks a tracer past the player. Muzzle flash and tracer are
-- drawn by every client from the EnemyShot event.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Ranged = require(script.Parent.Ranged)

local Shooter = {}

function Shooter.tick(d: any, api: any, now: number)
	local player, root, ready = Ranged.approach(d, api, now)
	if not ready or not player or not root then
		return
	end
	if now - d.lastAttack < d.row.cooldown then
		return
	end
	d.lastAttack = now
	local from = api.muzzle(d)
	local char = player.Character
	local head = char and char:FindFirstChild("Head") :: BasePart?
	local aim = if head then head.Position else root.Position + Vector3.new(0, 1.5, 0)
	local hit = math.random() < Config.ShooterHitChance
	local to: Vector3
	if hit then
		to = aim
		api.damagePlayer(player, d.dmg, "shot")
	else
		-- The line keeps going past the player, offset to one side so it visibly cracks by.
		local dir = (aim - from)
		local flatDir = Vector3.new(dir.X, 0, dir.Z)
		local side = if flatDir.Magnitude > 0.1 then Vector3.new(-flatDir.Z, 0, flatDir.X).Unit else Vector3.xAxis
		local miss = aim
			+ side * (2 + math.random() * 2) * (if math.random() < 0.5 then 1 else -1)
			+ Vector3.new(0, (math.random() - 0.3) * 2, 0)
		to = from + (miss - from).Unit * math.min(d.row.range * 1.6, (miss - from).Magnitude + 25)
	end
	api.fire("EnemyShot", { from = from, to = to, hit = hit, userId = player.UserId, archetype = d.archetype })
end

return Shooter
