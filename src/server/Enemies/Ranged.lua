--!strict
-- Shared movement for the ranged kinds (Shooter, Marksman, Grenadier): pick the nearest standing player
-- (one with line of sight when any has it), walk until within the row's range with a clear line, then hold
-- and face the target. Losing line of sight means walking again (the repath).
local Ranged = {}

-- Returns the target player and root (nil when nobody stands) and whether the enemy is in range with LoS.
function Ranged.approach(d: any, api: any, now: number): (Player?, BasePart?, boolean)
	if now - d.lastRetarget >= api.retargetInterval then
		d.lastRetarget = now
		local player, root = api.nearestPlayer(d.root.Position, true)
		if not player then
			player, root = api.nearestPlayer(d.root.Position, false)
		end
		d.mem.targetPlayer = player
		d.target = root
	end
	local player: Player? = d.mem.targetPlayer
	local root: BasePart? = d.target
	if not player or not root or not root.Parent then
		api.hold(d)
		return nil, nil, false
	end
	local dist = (root.Position - d.root.Position).Magnitude
	local ready = dist <= d.row.range and api.hasLos(d, root)
	if ready then
		api.hold(d)
		api.face(d, root.Position)
	else
		api.chase(d, root, now)
	end
	return player, root, ready
end

return Ranged
