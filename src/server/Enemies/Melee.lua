--!strict
-- Henchman and Runner: walk at the nearest player (or the placeable in the way), melee on reach.
-- The Runner is the same brain at its own row numbers; its shrill approach is a client sound keyed on the
-- Archetype attribute.
local Melee = {}

function Melee.tick(d: any, api: any, now: number)
	if now - d.lastRetarget >= api.retargetInterval then
		d.lastRetarget = now
		d.target = api.nearestTarget(d.root.Position)
	end
	local target = d.target
	if not target or not target.Parent then
		api.hold(d)
		return
	end
	api.chase(d, target, now)
	api.swing(d, target, now, 1)
end

return Melee
