--!strict
-- Round 19: the floor chevrons that guide the crew to an objective follow a walking route, not a straight line:
-- a player-sized PathfindingService path from the crew to the target (stairs, floors and the ladder included),
-- sent with the VaultArrows event. A route that cannot be planned falls back to the straight strip.
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ground = require(ReplicatedStorage.Shared.Ground)
local World = require(script.Parent.World)

local GuidePath = {}

-- Plans in the background and fires VaultArrows { from, to, sec, points? } to the run.
function GuidePath.arrows(from: Vector3, to: Vector3, sec: number)
	task.spawn(function()
		local start = Ground.at(from)
		local points: { Vector3 }? = nil
		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = true,
			WaypointSpacing = 4,
			Costs = { Door = math.huge },
		})
		local ok = pcall(function()
			path:ComputeAsync(start, to)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			local list = {}
			for _, w in path:GetWaypoints() do
				table.insert(list, w.Position)
			end
			points = list
		end
		World.fireRun("VaultArrows", { from = start, to = to, sec = sec, points = points })
	end)
end

return GuidePath
