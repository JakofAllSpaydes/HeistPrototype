--!strict
-- Brief 11 step 4: GamepadNav's pure geometry, shared with tests/input.spec.luau. Rects are {x, y, w, h} tables in
-- screen px (y down); directions are "up" | "down" | "left" | "right".
local NavMath = {}

export type Rect = { x: number, y: number, w: number, h: number }

local DIRS: { [string]: { number } } = {
	up = { 0, -1 },
	down = { 0, 1 },
	left = { -1, 0 },
	right = { 1, 0 },
}
NavMath.DIRS = DIRS

local function center(r: Rect): (number, number)
	return r.x + r.w / 2, r.y + r.h / 2
end

-- The gap from rect a to rect b along an axis (0 when they overlap on it).
local function gap(a0: number, a1: number, b0: number, b1: number): number
	if b0 >= a1 then
		return b0 - a1
	elseif a0 >= b1 then
		return a0 - b1
	end
	return 0
end

-- The best rect to move to from `from` in `dir`, or nil. Candidates must lie ahead (their centre past the
-- current centre); among those the score favours small travel along the direction and penalises sideways drift,
-- with rects that overlap the current one's span (a row / a column) preferred over diagonal ones.
function NavMath.pick(from: Rect, dir: string, rects: { Rect }): number?
	local d = DIRS[dir]
	if not d then
		return nil
	end
	local dx, dy = d[1], d[2]
	local cx, cy = center(from)
	local best, bestScore = nil, math.huge
	for i, r in rects do
		local rx, ry = center(r)
		local along = (rx - cx) * dx + (ry - cy) * dy
		if along > 2 then
			local side: number
			local edge: number
			if dx ~= 0 then
				side = gap(from.y, from.y + from.h, r.y, r.y + r.h)
				edge = gap(from.x, from.x + from.w, r.x, r.x + r.w)
			else
				side = gap(from.x, from.x + from.w, r.x, r.x + r.w)
				edge = gap(from.y, from.y + from.h, r.y, r.y + r.h)
			end
			local perp = math.abs((rx - cx) * dy - (ry - cy) * dx)
			local score = edge + along * 0.25 + side * 3 + perp * 0.5
			if side == 0 then
				score -= 1e5 -- same row / column wins over any diagonal
			end
			if score < bestScore then
				best, bestScore = i, score
			end
		end
	end
	return best
end

-- The stick as a nav direction (y up, like Thumbstick1.Position) or nil inside `press`.
function NavMath.stickDir(x: number, y: number, press: number): string?
	if math.sqrt(x * x + y * y) < press then
		return nil
	end
	if math.abs(x) > math.abs(y) then
		return if x > 0 then "right" else "left"
	end
	return if y > 0 then "up" else "down"
end

-- Key repeat for a held direction: first move at once, then after `delay`, then every `every`.
-- Returns whether to move now.
function NavMath.repeatStep(heldSince: number, lastMove: number?, now: number, delay: number, every: number): boolean
	if lastMove == nil then
		return true
	end
	if now - heldSince < delay then
		return false
	end
	return now - lastMove >= (if lastMove - heldSince < delay then 0 else every)
end

-- A ScrollingFrame's new canvas Y so the rect [top, bottom] (canvas space) is in a window of `height` at `canvasY`.
function NavMath.scrollInto(canvasY: number, height: number, top: number, bottom: number, margin: number): number
	if top - margin < canvasY then
		return math.max(0, top - margin)
	elseif bottom + margin > canvasY + height then
		return bottom + margin - height
	end
	return canvasY
end

return NavMath
