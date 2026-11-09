--!strict
-- Brief 11: small pad geometry shared with tests/input.spec.luau: GamepadNav's D-pad neighbours and the Safe dial's
-- stick angle.
local NavMath = {}

export type Rect = { x: number, y: number, w: number, h: number }

local DIRS: { [string]: { number } } = {
	up = { 0, -1 },
	down = { 0, 1 },
	left = { -1, 0 },
	right = { 1, 0 },
}

-- The gap between two spans on one axis (0 when they overlap).
local function gap(a0: number, a1: number, b0: number, b1: number): number
	if b0 >= a1 then
		return b0 - a1
	elseif a0 >= b1 then
		return a0 - b1
	end
	return 0
end

-- The button to go to from `from` in `dir` (screen px, y down), or nil. Only rects ahead count; a rect that shares the
-- current one's column (up / down) or row (left / right) always beats one off to the side, then the nearest edge
-- wins. So down from a chip lands on the button directly under it, not on a closer one diagonally.
function NavMath.pick(from: Rect, dir: string, rects: { Rect }): number?
	local d = DIRS[dir]
	if not d then
		return nil
	end
	local dx, dy = d[1], d[2]
	local cx, cy = from.x + from.w / 2, from.y + from.h / 2
	local best, bestScore = nil, math.huge
	for i, r in rects do
		local rx, ry = r.x + r.w / 2, r.y + r.h / 2
		local along = (rx - cx) * dx + (ry - cy) * dy
		if along > 2 then
			local side, edge
			if dx ~= 0 then
				side = gap(from.y, from.y + from.h, r.y, r.y + r.h)
				edge = gap(from.x, from.x + from.w, r.x, r.x + r.w)
			else
				side = gap(from.x, from.x + from.w, r.x, r.x + r.w)
				edge = gap(from.y, from.y + from.h, r.y, r.y + r.h)
			end
			local perp = math.abs((rx - cx) * dy - (ry - cy) * dx)
			local score = edge + side * 2 + perp * 0.1
			if side == 0 then
				score -= 1e5
			end
			if score < bestScore then
				best, bestScore = i, score
			end
		end
	end
	return best
end

-- A stick as a dial angle: degrees clockwise from straight up (the Safe dial's pad path).
function NavMath.stickAngle(x: number, y: number): number
	return math.deg(math.atan2(x, y))
end

-- The signed turn from angle a to angle b, the short way round (-180..180).
function NavMath.angleDelta(a: number, b: number): number
	return (b - a + 540) % 360 - 180
end

return NavMath
