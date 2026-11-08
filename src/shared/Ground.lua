--!strict
-- Floor height under a point (brief 7). The arena is one flat floor (Config.FloorTop); THE BANK has a street,
-- a lobby, a mezzanine, a vault level and a tunnel, so anything that lands on "the floor" (bags, crates,
-- telegraph discs, fire patches, bodies, the dealer) asks for the ground under where it is. Only map geometry
-- counts (Workspace.Room, Workspace.Bank.Geometry and Workspace.Hub.Geometry): characters, enemies, effects and loot never do.
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)

local Ground = {}

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.IgnoreWater = true
local filterAt = -math.huge

local function refreshFilter()
	local now = os.clock()
	if now - filterAt < 2 then
		return
	end
	filterAt = now
	local list: { Instance } = {}
	local room = Workspace:FindFirstChild("Room")
	if room then
		table.insert(list, room)
	end
	for _, root in { "Bank", "Hub" } do -- brief 8: the warehouse hub too (the range)
		local m = Workspace:FindFirstChild(root)
		local geo = m and m:FindFirstChild("Geometry")
		if geo then
			table.insert(list, geo)
		end
	end
	params.FilterDescendantsInstances = list
end

-- The top of the floor under `position`: a ray from `lift` (default 3) studs above it down `depth` (default
-- 80) studs. `fallback` (default Config.FloorTop) when nothing is under it.
function Ground.y(position: Vector3, fallback: number?, lift: number?, depth: number?): number
	refreshFilter()
	local up = lift or 3
	local from = position + Vector3.new(0, up, 0)
	local hit = Workspace:Raycast(from, Vector3.new(0, -(depth or 80) - up, 0), params)
	if hit then
		return hit.Position.Y
	end
	return fallback or Config.FloorTop
end

-- `position` dropped onto the floor under it, plus `above` studs.
function Ground.at(position: Vector3, above: number?): Vector3
	return Vector3.new(position.X, Ground.y(position) + (above or 0), position.Z)
end

-- The raycast params (map geometry only), for callers that cast their own rays.
function Ground.params(): RaycastParams
	refreshFilter()
	return params
end

return Ground
