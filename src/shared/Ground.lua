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

-- Round 25: studs of clear air above `position` (map geometry only), up to `max`. Beacon columns stop here so a
-- bag or gun on a lower floor never pokes up through the floor above. Glass, see-through and non-colliding
-- pieces don't stop it (a beam still shows through a skylight).
function Ground.ceiling(position: Vector3, max: number): number
	refreshFilter()
	local from = position + Vector3.new(0, 0.5, 0)
	local left = max
	local travelled = 0.5
	for _ = 1, 6 do
		local hit = Workspace:Raycast(from, Vector3.new(0, left, 0), params)
		if not hit then
			return max
		end
		local p = hit.Instance
		travelled += hit.Position.Y - from.Y
		if p.CanCollide and p.Transparency < 0.5 then
			return math.clamp(travelled - 0.2, 1, max)
		end
		left = max - travelled - 0.05
		if left <= 0 then
			return max
		end
		from = hit.Position + Vector3.new(0, 0.05, 0)
		travelled += 0.05
	end
	return max
end

-- Round 25: where things may stand. Each map with zone volumes (THE BANK) registers a check that answers true
-- (inside a zone), false (inside its outer bounds but outside every zone: a ledge, the street side of a wall) or
-- nil (not this map). A point is in play unless some check says false. MapLoader installs them (server only).
local areaChecks: { (Vector3) -> boolean? } = {}
function Ground.addPlayArea(check: (Vector3) -> boolean?)
	table.insert(areaChecks, check)
end

function Ground.inPlayArea(point: Vector3): boolean
	for _, check in areaChecks do
		if check(point) == false then
			return false
		end
	end
	return true
end

-- Round 25: is a `radius`-wide, `height`-tall column standing on `foot` free of solid map geometry?
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
function Ground.isClear(foot: Vector3, radius: number, height: number): boolean
	refreshFilter()
	overlap.FilterDescendantsInstances = params.FilterDescendantsInstances
	local center = CFrame.new(foot + Vector3.new(0, 0.3 + height / 2, 0))
	for _, p in Workspace:GetPartBoundsInBox(center, Vector3.new(radius * 2, height, radius * 2), overlap) do
		if p.CanCollide and p.Transparency < 0.95 then
			return false
		end
	end
	return true
end

-- Round 25: `position` dropped on the floor and nudged out of any wall it sits in: rings of candidates out to
-- `search` studs, on a floor within 3 studs of the original height and reachable in a straight line at waist
-- height. Returns the spot and whether it had to move (unchanged when nothing better is found).
function Ground.clearSpot(position: Vector3, radius: number, height: number, search: number?): (Vector3, boolean)
	local foot = Ground.at(position)
	local up = Vector3.new(0, 2, 0)
	if Ground.isClear(foot, radius, height) and Ground.inPlayArea(foot + up) then
		return foot, false
	end
	local maxR = search or 12
	local r = 1.5
	while r <= maxR do
		local n = math.max(8, math.floor(r * 4))
		for i = 0, n - 1 do
			local a = i / n * math.pi * 2
			local cand = foot + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			local y = Ground.y(cand, foot.Y - 100, 3, 6)
			if math.abs(y - foot.Y) <= 3 then
				local spot = Vector3.new(cand.X, y, cand.Z)
				if Ground.isClear(spot, radius, height) and Ground.inPlayArea(spot + up) then
					local waist = Vector3.new(0, 1.5, 0)
					local hit = Workspace:Raycast(foot + waist, spot - foot, params)
					if not hit then
						return spot, true
					end
				end
			end
		end
		r += 1.5
	end
	return foot, false
end

-- The raycast params (map geometry only), for callers that cast their own rays.
function Ground.params(): RaycastParams
	refreshFilter()
	return params
end

return Ground
