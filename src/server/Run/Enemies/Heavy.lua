--!strict
-- Heavy: slow, walks at the nearest player and stomps any placeable in its path (HeavyPlaceableMult x
-- damage). A melee hit throws the player back HeavyKnockback studs. Its two armor plates detach and fall
-- at the HeavyPlateHpPcts shares of HP, each with a crunch.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Heavy = {}

function Heavy.tick(d: any, api: any, now: number)
	if now - d.lastRetarget >= api.retargetInterval then
		d.lastRetarget = now
		local _, root = api.nearestPlayer(d.root.Position, false)
		d.target = root
	end
	local target = d.target
	if not target or not target.Parent then
		api.hold(d)
		return
	end
	api.chase(d, target, now)
	api.swing(d, target, now, 1, Config.HeavyPlaceableMult, Config.HeavyKnockback)
end

-- A plate flies off each time the HP share crosses one of the thresholds.
function Heavy.onDamaged(d: any, api: any)
	local share = d.hp / math.max(d.maxHP, 1)
	local plates: { BasePart } = d.plates
	for i, pct in Config.HeavyPlateHpPcts do
		local plate = plates[i]
		if plate and share <= pct then
			plates[i] = nil
			api.dropPlate(d, plate)
		end
	end
end

return Heavy
