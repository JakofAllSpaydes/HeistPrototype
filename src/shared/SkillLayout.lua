--!strict
-- Brief 9: where every Skill Web node sits. A regular hex grid in axial coordinates (q, r), START at (0, 0), five
-- rings. Ring N has exactly 6N cells, so each of the six branches (60 degree wedges) holds N cells in ring N.
-- Deterministic: wedge k owns the sector from 60k to 60(k+1) degrees, measured clockwise from straight up; a ring's
-- cells in that sector are ordered by angle and slot j takes cell j (slot 1 is the wedge's corner cell). Positions
-- are never hand-authored: the client draws from this table and the server validates adjacency from it.
--
-- Flat-top hexes: a cell's centre is x = 1.5 q, y = sqrt(3) (r + q / 2) in hex radii (y grows downward, as on
-- screen). The six neighbours of (q, r) are the DIRS offsets.
local SkillLayout = {}

export type Cell = { q: number, r: number, ring: number, wedge: number, slot: number }

SkillLayout.Rings = 5
SkillLayout.DIRS = {
	{ 1, 0 },
	{ 1, -1 },
	{ 0, -1 },
	{ -1, 0 },
	{ -1, 1 },
	{ 0, 1 },
} :: { { number } }

local SQRT3 = math.sqrt(3)

-- The cell's centre in hex radii (flat-top, y down).
function SkillLayout.toXY(q: number, r: number): (number, number)
	return 1.5 * q, SQRT3 * (r + q / 2)
end

function SkillLayout.key(q: number, r: number): string
	return q .. "," .. r
end

-- Hex distance between two cells (the ring of a cell is its distance to START).
function SkillLayout.distance(q1: number, r1: number, q2: number, r2: number): number
	local dq, dr = q1 - q2, r1 - r2
	return (math.abs(dq) + math.abs(dr) + math.abs(dq + dr)) / 2
end

-- Degrees clockwise from straight up, 0 <= a < 360.
local function angleOf(q: number, r: number): number
	local x, y = SkillLayout.toXY(q, r)
	local a = math.deg(math.atan2(x, -y))
	if a < 0 then
		a += 360
	end
	if a >= 360 - 1e-6 then
		a = 0
	end
	return a
end

-- Every ring's cells, wedge and slot assigned: { [ring] = { [wedge] = { Cell, ... in slot order } } }. Wedge 1 is the
-- one that starts straight up (the brief's wedge 0).
local cache: { [number]: { [number]: { Cell } } }? = nil
function SkillLayout.rings(): { [number]: { [number]: { Cell } } }
	local c = cache
	if c then
		return c
	end
	local out: { [number]: { [number]: { Cell } } } = {}
	for ring = 1, SkillLayout.Rings do
		local wedges: { [number]: { { cell: Cell, a: number } } } = {}
		for w = 1, 6 do
			wedges[w] = {}
		end
		for q = -ring, ring do
			for r = -ring, ring do
				if SkillLayout.distance(q, r, 0, 0) == ring then
					local a = angleOf(q, r)
					local w = (math.floor((a + 1e-6) / 60) % 6) + 1
					table.insert(wedges[w], { cell = { q = q, r = r, ring = ring, wedge = w, slot = 0 }, a = a })
				end
			end
		end
		out[ring] = {}
		for w = 1, 6 do
			local list = wedges[w]
			table.sort(list, function(x, y)
				return x.a < y.a
			end)
			local cells: { Cell } = {}
			for j, e in list do
				e.cell.slot = j
				cells[j] = e.cell
			end
			out[ring][w] = cells
		end
	end
	cache = out
	return out
end

return SkillLayout
