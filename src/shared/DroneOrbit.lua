--!strict
-- Brief 12: where a drone sits relative to its caster. The server (targeting, line of sight, shots) and every client
-- (the mesh) evaluate the same orbit from the same spec and the shared server clock, so a swarm needs no physics,
-- no pathfinding and no per-frame replication: drones are maths around the caster's root.
local DroneOrbit = {}

export type Spec = {
	radius: number, -- studs from the caster's root (0 = sits on them: AEGIS)
	height: number, -- studs above the root
	phase: number, -- radians: where on the circle it starts
	speed: number, -- radians per second (the sign is the direction)
	bob: number, -- studs of up / down sway
}

-- Attack drones: radius 4..6, height 3, each its own phase and speed so a swarm looks alive.
function DroneOrbit.attack(index: number): Spec
	local golden = 2.39996 -- the golden angle spreads any count evenly round the circle
	local rng = Random.new(index * 7919 + 17)
	local dir = if index % 2 == 0 then 1 else -1
	return {
		radius = rng:NextNumber(4, 6),
		height = 3 + rng:NextNumber(-0.4, 0.6),
		phase = index * golden,
		speed = dir * rng:NextNumber(0.7, 1.3),
		bob = 0.35,
	}
end

-- DOC's heal drone: at the caster's shoulder, a slow small circle.
function DroneOrbit.shoulder(index: number): Spec
	return { radius = 1.9, height = 2.4, phase = index * 2.1, speed = 0.6, bob = 0.2 }
end

-- AEGIS: radius 0 over the caster.
function DroneOrbit.center(): Spec
	return { radius = 0, height = 1, phase = 0, speed = 0, bob = 0 }
end

function DroneOrbit.offset(spec: Spec, t: number): Vector3
	local a = spec.phase + spec.speed * t
	return Vector3.new(
		math.cos(a) * spec.radius,
		spec.height + math.sin(t * 2.1 + spec.phase) * spec.bob,
		math.sin(a) * spec.radius
	)
end

return DroneOrbit
