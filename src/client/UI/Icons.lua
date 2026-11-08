--!strict
-- Pictogram icons drawn from frames (house style: flat, bold, two-tone; no image ids, no emoji, no unicode).
--
--   Icons.draw(parent, id, size, color, detail?, fallback?) -> Frame
--       draws `id` into a square, transparent root of `size` px (parented to `parent`) and returns the root.
--   Icons.fit(parent, id, frac, color, detail?, fallback?) -> Frame
--       the same, sized to `frac` of the parent's shorter side and centred in it (follows the parent's size).
--   Icons.has(id) -> boolean
--
-- `color` is the silhouette; `detail` is the second tone for cut-outs and inner lines (pass the colour behind the
-- icon so cut-outs read as holes; defaults to a darkened `color`). Every part is scale-based inside the root, so
-- resizing the root rescales the icon; ring strokes follow the root's AbsoluteSize. An unknown id draws `fallback`
-- (or the id itself) as text, so nothing ever renders blank.
--
-- Ids, keyed by the data that already exists:
--   abilities  Classes.lua `icon`: FRG ADR CLM TRT WAL OVC SHT BAG HTR EGV EYE FLS MOL FTR OIL
--   classes    Classes.lua `id`: INITIATE ENGINEER DOC SHARPSHOOTER TORCH (the emblem inside the class circle)
--   boosts     BoostDefs.lua `id`: power cash lucky
--   upgrades   Upgrades.lua stat `id`: Damage FireRate MagSize ... BlastRadius
--   UI         classes avatar shop close plus revive vip gift
local Theme = require(script.Parent:WaitForChild("Theme"))

local Icons = {}

type Stroke = { stroke: UIStroke, frac: number }
-- A drawing context: local unit coords (0..1, y down) map to the root as ox + x * s, oy + y * s.
type Ctx = {
	root: Frame,
	ox: number,
	oy: number,
	s: number,
	z: number,
	fg: Color3,
	dt: Color3,
	strokes: { Stroke },
}

------------------------------------------------------------------ Primitives
-- A filled part centred at (x, y), w x h, turned `rot` degrees clockwise, corner radius `round` (UDim scale).
local function rect(
	c: Ctx,
	x: number,
	y: number,
	w: number,
	h: number,
	layer: number,
	color: Color3,
	round: number?,
	rot: number?
): Frame
	local f = Instance.new("Frame")
	f.Name = "Part"
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(c.ox + x * c.s, c.oy + y * c.s)
	f.Size = UDim2.fromScale(w * c.s, h * c.s)
	f.Rotation = rot or 0
	f.ZIndex = c.z + layer
	if round and round > 0 then
		local k = Instance.new("UICorner")
		k.CornerRadius = UDim.new(round, 0)
		k.Parent = f
	end
	f.Parent = c.root
	return f
end

local function circle(c: Ctx, x: number, y: number, d: number, layer: number, color: Color3): Frame
	return rect(c, x, y, d, d, layer, color, 0.5)
end

-- A stroke of thickness t from (x1, y1) to (x2, y2). cap "round" (default): rounded ends centred on the points;
-- "square": square ends t/2 past the points; "butt": square ends on the points. `round` overrides the corner.
local function bar(
	c: Ctx,
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	t: number,
	layer: number,
	color: Color3,
	cap: string?,
	round: number?
): Frame
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	local mode = cap or "round"
	local ext = if mode == "butt" then 0 else t
	local r = round or (if mode == "round" then 0.5 else 0)
	return rect(c, (x1 + x2) / 2, (y1 + y2) / 2, len + ext, t, layer, color, r, math.deg(math.atan2(dy, dx)))
end

-- An outline of thickness t (fraction of the box) around a part; the stroke sits outside the part's edge.
local function outline(c: Ctx, f: GuiObject, t: number, color: Color3)
	local st = Instance.new("UIStroke")
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Color = color
	st.Thickness = 1
	st.Parent = f
	table.insert(c.strokes, { stroke = st, frac = t * c.s })
end

-- A hollow rounded outline whose OUTER edge is w x h at (x, y).
local function loop(
	c: Ctx,
	x: number,
	y: number,
	w: number,
	h: number,
	t: number,
	layer: number,
	color: Color3,
	round: number
): Frame
	local f = rect(c, x, y, w - 2 * t, h - 2 * t, layer, color, round)
	f.BackgroundTransparency = 1
	outline(c, f, t, color)
	return f
end

-- A ring of outer diameter d and thickness t.
local function ring(c: Ctx, x: number, y: number, d: number, t: number, layer: number, color: Color3): Frame
	return loop(c, x, y, d, d, t, layer, color, 0.5)
end

-- An arc of radius r (to the stroke's centre line) from angle a0 to a1 in degrees (0 = right, 90 = down), as
-- round-capped segments (no clipping needed).
local function arc(
	c: Ctx,
	cx: number,
	cy: number,
	r: number,
	a0: number,
	a1: number,
	t: number,
	layer: number,
	color: Color3
)
	local n = math.max(3, math.ceil(math.abs(a1 - a0) / 15))
	local px, py = cx + r * math.cos(math.rad(a0)), cy + r * math.sin(math.rad(a0))
	for i = 1, n do
		local a = math.rad(a0 + (a1 - a0) * i / n)
		local qx, qy = cx + r * math.cos(a), cy + r * math.sin(a)
		bar(c, px, py, qx, qy, t, layer, color)
		px, py = qx, qy
	end
end

-- An open arrowhead (two round arms) with its tip at (tx, ty) pointing along (dx, dy).
local function arrowHead(
	c: Ctx,
	tx: number,
	ty: number,
	dx: number,
	dy: number,
	len: number,
	t: number,
	layer: number,
	color: Color3
)
	local m = math.sqrt(dx * dx + dy * dy)
	local bx, by = -dx / m, -dy / m
	local a = math.rad(42)
	for _, sgn in { 1, -1 } do
		local ca, sa = math.cos(a * sgn), math.sin(a * sgn)
		local vx, vy = bx * ca - by * sa, bx * sa + by * ca
		bar(c, tx, ty, tx + vx * len, ty + vy * len, t, layer, color)
	end
end

-- A teardrop: a circle of diameter a at (cx, cy) with its point up, leaning `tilt` degrees clockwise. The point
-- sits 0.707a from the centre; the bottom 0.5a.
local function drop(c: Ctx, cx: number, cy: number, a: number, tilt: number, layer: number, color: Color3)
	circle(c, cx, cy, a, layer, color)
	local k = 0.3536 * a
	local r = math.rad(tilt)
	rect(c, cx + k * math.sin(r), cy - k * math.cos(r), a / 2, a / 2, layer, color, 0, 45 + tilt)
end

-- A flame: a teardrop with a tongue licking up on its left and an inner tongue in the detail tone. (x, y) is the
-- main circle's centre; it spans y - 0.71a .. y + 0.5a.
local function flame(c: Ctx, x: number, y: number, a: number, layer: number?)
	local l = layer or 1
	drop(c, x, y, a, 0, l, c.fg)
	drop(c, x - 0.36 * a, y + 0.12 * a, 0.5 * a, -35, l, c.fg)
	drop(c, x, y + 0.16 * a, 0.45 * a, 0, l + 1, c.dt)
end

-- A cartridge from its base (bx, by) to its tip (tx, ty), w wide.
local function bullet(c: Ctx, bx: number, by: number, tx: number, ty: number, w: number, layer: number)
	local dx, dy = tx - bx, ty - by
	bar(c, bx, by, bx + dx * 0.62, by + dy * 0.62, w, layer, c.fg, "butt", 0.08)
	bar(c, bx + dx * 0.4, by + dy * 0.4, tx, ty, w, layer, c.fg, "butt", 0.5)
	bar(c, bx - dx * 0.03, by - dy * 0.03, bx + dx * 0.07, by + dy * 0.07, w * 1.2, layer, c.fg, "butt", 0.2)
	bar(c, bx + dx * 0.6, by + dy * 0.6, bx + dx * 0.65, by + dy * 0.65, w, layer + 1, c.dt, "butt")
end

-- A chevron with its point at (px, py) opening toward (dx, dy), arms `len` long.
local function chevron(c: Ctx, px: number, py: number, dx: number, dy: number, len: number, t: number, layer: number)
	arrowHead(c, px, py, -dx, -dy, len, t, layer, c.fg)
end

-- A sub-box of the current context: local (x, y) is its top-left, s its size; dz lifts its layers.
local function sub(c: Ctx, x: number, y: number, s: number, dz: number?): Ctx
	return {
		root = c.root,
		ox = c.ox + x * c.s,
		oy = c.oy + y * c.s,
		s = c.s * s,
		z = c.z + (dz or 0),
		fg = c.fg,
		dt = c.dt,
		strokes = c.strokes,
	}
end

------------------------------------------------------------------ Drawings (unit box, y down)
local DRAW: { [string]: (Ctx) -> () } = {}

-- Shared pieces.
local function tripod(c: Ctx, top: number)
	local fg = c.fg
	bar(c, 0.5, top, 0.5, 0.66, 0.1, 1, fg, "butt")
	bar(c, 0.5, 0.64, 0.24, 0.9, 0.08, 1, fg)
	bar(c, 0.5, 0.64, 0.76, 0.9, 0.08, 1, fg)
	bar(c, 0.5, 0.64, 0.5, 0.9, 0.07, 1, fg)
end

local function plusMark(c: Ctx, x: number, y: number, len: number, t: number, layer: number, color: Color3)
	rect(c, x, y, len, t, layer, color, 0.2)
	rect(c, x, y, t, len, layer, color, 0.2)
end

local function bolt(c: Ctx)
	local fg = c.fg
	bar(c, 0.66, 0.06, 0.36, 0.5, 0.2, 1, fg, "butt")
	bar(c, 0.28, 0.5, 0.72, 0.5, 0.14, 1, fg, "butt")
	bar(c, 0.64, 0.5, 0.34, 0.94, 0.14, 1, fg, "butt")
end

local function crosshair(c: Ctx)
	local fg = c.fg
	ring(c, 0.5, 0.5, 0.62, 0.09, 1, fg)
	bar(c, 0.5, 0.06, 0.5, 0.32, 0.09, 1, fg, "butt")
	bar(c, 0.5, 0.68, 0.5, 0.94, 0.09, 1, fg, "butt")
	bar(c, 0.06, 0.5, 0.32, 0.5, 0.09, 1, fg, "butt")
	bar(c, 0.68, 0.5, 0.94, 0.5, 0.09, 1, fg, "butt")
	circle(c, 0.5, 0.5, 0.12, 1, fg)
end

local function cross(c: Ctx)
	plusMark(c, 0.5, 0.5, 0.72, 0.26, 1, c.fg)
end

local function heart(c: Ctx)
	local fg = c.fg
	local s = 0.47
	rect(c, 0.5, 0.535, s, s, 1, fg, 0.08, 45)
	circle(c, 0.334, 0.369, s, 1, fg)
	circle(c, 0.666, 0.369, s, 1, fg)
end

local function bigFlame(c: Ctx)
	flame(c, 0.53, 0.56, 0.62)
end

local function turret(c: Ctx)
	local fg = c.fg
	tripod(c, 0.48)
	rect(c, 0.42, 0.42, 0.42, 0.26, 1, fg, 0.3)
	bar(c, 0.6, 0.4, 0.86, 0.4, 0.1, 1, fg, "butt")
	rect(c, 0.87, 0.4, 0.06, 0.16, 1, fg, 0.2)
	rect(c, 0.38, 0.26, 0.14, 0.08, 1, fg, 0.2)
	rect(c, 0.4, 0.44, 0.24, 0.05, 2, c.dt, 0.5)
end

local function gear(c: Ctx)
	local fg = c.fg
	for _, rot in { 0, 45, 90, 135 } do
		rect(c, 0.5, 0.5, 0.86, 0.17, 1, fg, 0.15, rot)
	end
	circle(c, 0.5, 0.5, 0.64, 1, fg)
end

local function eye(c: Ctx)
	local fg = c.fg
	rect(c, 0.5, 0.5, 0.7, 0.5, 1, fg, 0.5)
	rect(c, 0.24, 0.5, 0.3, 0.3, 1, fg, 0.1, 45)
	rect(c, 0.76, 0.5, 0.3, 0.3, 1, fg, 0.1, 45)
	circle(c, 0.5, 0.5, 0.4, 2, c.dt)
	circle(c, 0.5, 0.5, 0.18, 3, fg)
end

local function stopwatch(c: Ctx)
	local fg = c.fg
	ring(c, 0.5, 0.56, 0.72, 0.1, 1, fg)
	rect(c, 0.5, 0.13, 0.18, 0.08, 1, fg, 0.3)
	bar(c, 0.5, 0.15, 0.5, 0.22, 0.08, 1, fg, "butt")
	bar(c, 0.75, 0.25, 0.8, 0.2, 0.08, 1, fg)
	bar(c, 0.5, 0.56, 0.62, 0.4, 0.08, 1, fg)
	circle(c, 0.5, 0.56, 0.12, 1, fg)
end

local function snowflake(c: Ctx)
	local fg = c.fg
	for k = 0, 2 do
		local a = math.rad(90 + 60 * k)
		local ux, uy = math.cos(a), math.sin(a)
		bar(c, 0.5 - 0.4 * ux, 0.5 - 0.4 * uy, 0.5 + 0.4 * ux, 0.5 + 0.4 * uy, 0.08, 1, fg)
	end
	for k = 0, 5 do
		local a = 90 + 60 * k
		local px = 0.5 + 0.25 * math.cos(math.rad(a))
		local py = 0.5 + 0.25 * math.sin(math.rad(a))
		for _, side in { 45, -45 } do
			local b = math.rad(a + side)
			bar(c, px, py, px + 0.13 * math.cos(b), py + 0.13 * math.sin(b), 0.07, 1, fg)
		end
	end
end

local function burst(c: Ctx)
	for _, rot in { 0, 30, 60 } do
		rect(c, 0.5, 0.5, 0.58, 0.58, 1, c.fg, 0.06, rot)
	end
	for _, rot in { 15, 45, 75 } do
		rect(c, 0.5, 0.5, 0.3, 0.3, 2, c.dt, 0.06, rot)
	end
end

local function coins(c: Ctx)
	local fg, dt = c.fg, c.dt
	for i, y in { 0.8, 0.66, 0.52 } do
		local p = rect(c, 0.38, y, 0.56, 0.18, i, fg, 0.5)
		outline(c, p, 0.03, dt)
	end
	local coin = circle(c, 0.68, 0.42, 0.48, 4, fg)
	outline(c, coin, 0.03, dt)
	ring(c, 0.68, 0.42, 0.3, 0.045, 5, dt)
end

-- Abilities (Classes.lua `icon`).
DRAW.FRG = function(c: Ctx) -- frag grenade: ribbed body, fuse cap, spoon, pin ring
	local fg, dt = c.fg, c.dt
	rect(c, 0.46, 0.6, 0.5, 0.58, 1, fg, 0.5)
	rect(c, 0.46, 0.27, 0.22, 0.12, 1, fg, 0.25)
	bar(c, 0.55, 0.24, 0.74, 0.5, 0.09, 1, fg)
	ring(c, 0.27, 0.22, 0.2, 0.05, 1, fg)
	rect(c, 0.46, 0.6, 0.48, 0.045, 2, dt)
	rect(c, 0.46, 0.6, 0.045, 0.54, 2, dt)
end

DRAW.ADR = function(c: Ctx) -- adrenaline: a syringe, needle down-left
	local fg, dt = c.fg, c.dt
	bar(c, 0.68, 0.32, 0.34, 0.66, 0.22, 1, fg, "butt", 0.15)
	bar(c, 0.6, 0.4, 0.42, 0.58, 0.08, 2, dt)
	bar(c, 0.35, 0.65, 0.27, 0.73, 0.11, 1, fg, "butt")
	bar(c, 0.28, 0.72, 0.12, 0.88, 0.045, 1, fg)
	bar(c, 0.6, 0.22, 0.78, 0.4, 0.07, 1, fg, "butt", 0.3)
	bar(c, 0.7, 0.3, 0.84, 0.16, 0.07, 1, fg, "butt")
	bar(c, 0.78, 0.1, 0.9, 0.22, 0.075, 1, fg, "butt", 0.3)
end

DRAW.CLM = function(c: Ctx) -- claymore: the mine on its two legs, a sight on top
	local fg = c.fg
	rect(c, 0.5, 0.46, 0.72, 0.38, 1, fg, 0.22)
	rect(c, 0.5, 0.24, 0.12, 0.08, 1, fg, 0.2)
	bar(c, 0.3, 0.6, 0.2, 0.88, 0.07, 1, fg)
	bar(c, 0.7, 0.6, 0.8, 0.88, 0.07, 1, fg)
	rect(c, 0.5, 0.4, 0.56, 0.07, 2, c.dt, 0.5)
end

DRAW.TRT = turret -- turret: a gun head on a tripod

DRAW.WAL = function(c: Ctx) -- barricade: a brick wall
	local dt = c.dt
	rect(c, 0.5, 0.56, 0.78, 0.6, 1, c.fg, 0.06)
	rect(c, 0.5, 0.46, 0.78, 0.04, 2, dt)
	rect(c, 0.5, 0.66, 0.78, 0.04, 2, dt)
	rect(c, 0.5, 0.36, 0.04, 0.2, 2, dt)
	rect(c, 0.31, 0.56, 0.04, 0.2, 2, dt)
	rect(c, 0.69, 0.56, 0.04, 0.2, 2, dt)
	rect(c, 0.5, 0.76, 0.04, 0.2, 2, dt)
end

DRAW.OVC = function(c: Ctx) -- overclock: a gear with a bolt in its hub
	gear(c)
	circle(c, 0.5, 0.5, 0.36, 2, c.dt)
	bolt(sub(c, 0.36, 0.36, 0.28, 2))
end

DRAW.SHT = function(c: Ctx) -- stim shot: a medical auto-injector pen with a cross
	local fg, dt = c.fg, c.dt
	bar(c, 0.24, 0.76, 0.66, 0.34, 0.26, 1, fg, "butt", 0.3)
	bar(c, 0.64, 0.36, 0.82, 0.18, 0.2, 1, fg, "butt", 0.35)
	bar(c, 0.22, 0.78, 0.12, 0.88, 0.05, 1, fg)
	bar(c, 0.62, 0.38, 0.66, 0.34, 0.26, 2, dt, "butt")
	plusMark(c, 0.43, 0.57, 0.17, 0.06, 2, dt)
end

DRAW.BAG = function(c: Ctx) -- med bag: a bag with a handle and a cross
	local fg = c.fg
	loop(c, 0.5, 0.33, 0.34, 0.26, 0.065, 1, fg, 0.4)
	rect(c, 0.5, 0.62, 0.78, 0.5, 2, fg, 0.2)
	plusMark(c, 0.5, 0.62, 0.3, 0.1, 3, c.dt)
end

DRAW.HTR = function(c: Ctx) -- healing turret: a cross-marked head on a tripod
	tripod(c, 0.5)
	rect(c, 0.5, 0.38, 0.46, 0.4, 1, c.fg, 0.3)
	plusMark(c, 0.5, 0.38, 0.26, 0.08, 2, c.dt)
end

DRAW.EGV = function(c: Ctx) -- eagle vision: binoculars
	local fg, dt = c.fg, c.dt
	rect(c, 0.3, 0.56, 0.32, 0.5, 1, fg, 0.35)
	rect(c, 0.7, 0.56, 0.32, 0.5, 1, fg, 0.35)
	rect(c, 0.5, 0.46, 0.22, 0.14, 1, fg, 0.2)
	rect(c, 0.3, 0.27, 0.2, 0.12, 1, fg, 0.3)
	rect(c, 0.7, 0.27, 0.2, 0.12, 1, fg, 0.3)
	circle(c, 0.3, 0.66, 0.18, 2, dt)
	circle(c, 0.7, 0.66, 0.18, 2, dt)
end

DRAW.EYE = eye -- dead eye: an eye

DRAW.FLS = function(c: Ctx) -- flashbang: a starburst
	local fg = c.fg
	bar(c, 0.5, 0.07, 0.5, 0.93, 0.11, 1, fg)
	bar(c, 0.07, 0.5, 0.93, 0.5, 0.11, 1, fg)
	bar(c, 0.22, 0.22, 0.78, 0.78, 0.1, 1, fg)
	bar(c, 0.78, 0.22, 0.22, 0.78, 0.1, 1, fg)
	circle(c, 0.5, 0.5, 0.44, 1, fg)
	circle(c, 0.5, 0.5, 0.2, 2, c.dt)
end

DRAW.MOL = function(c: Ctx) -- molotov: a bottle with a lit rag
	local fg = c.fg
	rect(c, 0.5, 0.69, 0.4, 0.42, 1, fg, 0.3)
	rect(c, 0.5, 0.42, 0.15, 0.2, 1, fg, 0.2)
	rect(c, 0.5, 0.35, 0.22, 0.06, 1, fg, 0.5)
	rect(c, 0.5, 0.7, 0.4, 0.1, 2, c.dt)
	flame(c, 0.5, 0.2, 0.2)
end

DRAW.FTR = function(c: Ctx) -- flame turret: a flame on a tripod
	tripod(c, 0.6)
	rect(c, 0.5, 0.62, 0.32, 0.1, 1, c.fg, 0.3)
	flame(c, 0.52, 0.36, 0.4)
end

DRAW.OIL = function(c: Ctx) -- oil drum: a ribbed barrel with an oil drop
	local fg, dt = c.fg, c.dt
	rect(c, 0.5, 0.53, 0.56, 0.72, 1, fg, 0.12)
	rect(c, 0.5, 0.19, 0.62, 0.06, 1, fg, 0.5)
	rect(c, 0.5, 0.87, 0.62, 0.06, 1, fg, 0.5)
	rect(c, 0.5, 0.39, 0.56, 0.04, 2, dt)
	rect(c, 0.5, 0.67, 0.56, 0.04, 2, dt)
	drop(c, 0.5, 0.56, 0.14, 0, 2, dt)
end

-- Class emblems (Classes.lua `id`), drawn inside the class's coloured circle.
DRAW.INITIATE = function(c: Ctx) -- rank chevrons
	chevron(c, 0.5, 0.22, 0, 1, 0.34, 0.13, 1)
	chevron(c, 0.5, 0.52, 0, 1, 0.34, 0.13, 1)
end

DRAW.ENGINEER = function(c: Ctx) -- a wrench
	local fg, dt = c.fg, c.dt
	bar(c, 0.24, 0.76, 0.6, 0.4, 0.15, 1, fg)
	circle(c, 0.66, 0.34, 0.4, 1, fg)
	bar(c, 0.66, 0.34, 0.8, 0.2, 0.15, 2, dt, "butt")
	circle(c, 0.27, 0.73, 0.07, 2, dt)
end

DRAW.DOC = cross -- a medical cross
DRAW.SHARPSHOOTER = crosshair -- a crosshair
DRAW.TORCH = bigFlame -- a flame

-- Boosts (BoostDefs.lua `id`).
DRAW.power = bolt -- a lightning bolt
DRAW.cash = coins -- a coin stack and a coin

DRAW.lucky = function(c: Ctx) -- a four-leaf clover
	local fg, dt = c.fg, c.dt
	bar(c, 0.56, 0.6, 0.7, 0.92, 0.07, 1, fg)
	for _, p in { { 0.36, 0.3 }, { 0.64, 0.3 }, { 0.36, 0.58 }, { 0.64, 0.58 } } do
		circle(c, p[1], p[2], 0.36, 1, fg)
	end
	circle(c, 0.5, 0.44, 0.14, 1, fg)
	rect(c, 0.5, 0.44, 0.04, 0.5, 2, dt)
	rect(c, 0.5, 0.44, 0.5, 0.04, 2, dt)
end

-- Upgrade stats (Upgrades.lua stat `id`).
DRAW.Damage = function(c: Ctx) -- a skull
	local fg, dt = c.fg, c.dt
	circle(c, 0.5, 0.42, 0.66, 1, fg)
	rect(c, 0.5, 0.72, 0.4, 0.26, 1, fg, 0.25)
	circle(c, 0.37, 0.45, 0.18, 2, dt)
	circle(c, 0.63, 0.45, 0.18, 2, dt)
	rect(c, 0.5, 0.6, 0.08, 0.08, 2, dt, 0, 45)
	rect(c, 0.44, 0.78, 0.035, 0.12, 2, dt)
	rect(c, 0.56, 0.78, 0.035, 0.12, 2, dt)
end

DRAW.FireRate = function(c: Ctx) -- three bullets with speed lines
	for _, y in { 0.24, 0.5, 0.76 } do
		bullet(c, 0.4, y, 0.9, y, 0.15, 1)
		bar(c, if y == 0.5 then 0.05 else 0.1, y, 0.26, y, 0.05, 1, c.fg)
	end
end

DRAW.MagSize = function(c: Ctx) -- a magazine with a round on top
	local fg, dt = c.fg, c.dt
	bar(c, 0.43, 0.2, 0.55, 0.84, 0.34, 1, fg, "butt", 0.12)
	bar(c, 0.545, 0.8, 0.555, 0.86, 0.42, 1, fg, "butt", 0.2)
	bar(c, 0.435, 0.2, 0.415, 0.08, 0.14, 1, fg, "round")
	bar(c, 0.602, 0.196, 0.268, 0.256, 0.03, 2, dt, "butt")
	for _, t in { 0.35, 0.5, 0.65 } do
		circle(c, 0.43 + 0.12 * t, 0.2 + 0.64 * t, 0.07, 2, dt)
	end
end

DRAW.ReloadSpeed = function(c: Ctx) -- a circular arrow
	local fg = c.fg
	local cx, cy, r = 0.5, 0.52, 0.32
	arc(c, cx, cy, r, 30, 296, 0.11, 1, fg)
	local tip = math.rad(305)
	arrowHead(c, cx + r * math.cos(tip), cy + r * math.sin(tip), -math.sin(tip), math.cos(tip), 0.2, 0.11, 1, fg)
end

DRAW.CritChance = function(c: Ctx) -- a bullseye
	local fg = c.fg
	ring(c, 0.5, 0.5, 0.86, 0.1, 1, fg)
	ring(c, 0.5, 0.5, 0.52, 0.1, 1, fg)
	circle(c, 0.5, 0.5, 0.18, 1, fg)
end

DRAW.HeadshotMult = function(c: Ctx) -- a head and shoulders with a crosshair on the head
	local fg, dt = c.fg, c.dt
	circle(c, 0.5, 0.34, 0.42, 1, fg)
	rect(c, 0.5, 0.6, 0.16, 0.12, 1, fg)
	rect(c, 0.5, 0.8, 0.74, 0.3, 1, fg, 0.5)
	ring(c, 0.5, 0.34, 0.24, 0.035, 2, dt)
	circle(c, 0.5, 0.34, 0.06, 2, dt)
end

DRAW.MoveSpeed = function(c: Ctx) -- fast-forward chevrons
	chevron(c, 0.47, 0.5, -1, 0, 0.36, 0.14, 1)
	chevron(c, 0.79, 0.5, -1, 0, 0.36, 0.14, 1)
end

DRAW.Accuracy = crosshair

DRAW.Pierce = function(c: Ctx) -- an arrow punched through a plate
	local fg = c.fg
	rect(c, 0.46, 0.22, 0.12, 0.3, 1, fg, 0.15)
	rect(c, 0.46, 0.78, 0.12, 0.3, 1, fg, 0.15)
	rect(c, 0.6, 0.36, 0.07, 0.07, 1, fg, 0, 30)
	rect(c, 0.62, 0.65, 0.06, 0.06, 1, fg, 0, 15)
	bar(c, 0.1, 0.5, 0.86, 0.5, 0.08, 1, fg, "butt")
	arrowHead(c, 0.92, 0.5, 1, 0, 0.2, 0.1, 1, fg)
	bar(c, 0.16, 0.5, 0.07, 0.37, 0.06, 1, fg)
	bar(c, 0.16, 0.5, 0.07, 0.63, 0.06, 1, fg)
end

DRAW.Ricochet = function(c: Ctx) -- a path bouncing off a surface
	local fg = c.fg
	bar(c, 0.24, 0.88, 0.76, 0.88, 0.06, 1, fg)
	bar(c, 0.12, 0.16, 0.5, 0.76, 0.09, 1, fg)
	bar(c, 0.5, 0.76, 0.84, 0.24, 0.09, 1, fg)
	arrowHead(c, 0.87, 0.19, 0.34, -0.52, 0.2, 0.09, 1, fg)
end

DRAW.Splash = burst -- an explosion

DRAW.Multishot = function(c: Ctx) -- three bullets fanning out
	bullet(c, 0.42, 0.4, 0.84, 0.18, 0.14, 1)
	bullet(c, 0.46, 0.5, 0.92, 0.5, 0.14, 1)
	bullet(c, 0.42, 0.6, 0.84, 0.82, 0.14, 1)
	bar(c, 0.08, 0.5, 0.28, 0.5, 0.05, 1, c.fg)
	bar(c, 0.14, 0.36, 0.3, 0.44, 0.05, 1, c.fg)
	bar(c, 0.14, 0.64, 0.3, 0.56, 0.05, 1, c.fg)
end

DRAW.Lifesteal = function(c: Ctx) -- a blood drop with a cross
	drop(c, 0.5, 0.6, 0.56, 0, 1, c.fg)
	plusMark(c, 0.5, 0.62, 0.26, 0.08, 2, c.dt)
end

DRAW.Incendiary = bigFlame -- fire ammo: a flame
DRAW.Cryo = snowflake -- ice ammo: a snowflake

DRAW.Concussive = function(c: Ctx) -- impact ammo: an impact star with shockwaves
	local fg = c.fg
	rect(c, 0.36, 0.5, 0.42, 0.42, 1, fg, 0.04, 0)
	rect(c, 0.36, 0.5, 0.42, 0.42, 1, fg, 0.04, 45)
	circle(c, 0.36, 0.5, 0.16, 2, c.dt)
	arc(c, 0.36, 0.5, 0.38, -45, 45, 0.07, 1, fg)
	arc(c, 0.36, 0.5, 0.52, -45, 45, 0.07, 1, fg)
end

DRAW.AbilityCooldown = stopwatch -- a stopwatch
DRAW.AbilityPower = bolt
DRAW.CashGain = coins

DRAW.Wildfire = function(c: Ctx) -- flames spreading: one big, two small
	flame(c, 0.18, 0.66, 0.26, 3)
	flame(c, 0.84, 0.66, 0.26, 3)
	flame(c, 0.53, 0.5, 0.44, 1)
end

DRAW.Shatter = function(c: Ctx) -- a cracked ice shard with flying chips
	local fg, dt = c.fg, c.dt
	rect(c, 0.5, 0.5, 0.46, 0.46, 1, fg, 0.06, 45)
	bar(c, 0.5, 0.2, 0.44, 0.4, 0.045, 2, dt)
	bar(c, 0.44, 0.4, 0.56, 0.56, 0.045, 2, dt)
	bar(c, 0.56, 0.56, 0.48, 0.78, 0.045, 2, dt)
	rect(c, 0.16, 0.26, 0.12, 0.12, 1, fg, 0.1, 30)
	rect(c, 0.85, 0.74, 0.1, 0.1, 1, fg, 0.1, 15)
	rect(c, 0.84, 0.22, 0.07, 0.07, 1, fg, 0.1, 40)
end

DRAW.Aftershock = function(c: Ctx) -- shockwaves rising off cracked ground
	local fg = c.fg
	bar(c, 0.08, 0.76, 0.92, 0.76, 0.07, 1, fg)
	arc(c, 0.5, 0.76, 0.22, 180, 360, 0.07, 1, fg)
	arc(c, 0.5, 0.76, 0.4, 180, 360, 0.07, 1, fg)
	circle(c, 0.5, 0.74, 0.14, 1, fg)
	bar(c, 0.42, 0.78, 0.36, 0.92, 0.05, 1, fg)
	bar(c, 0.6, 0.78, 0.66, 0.92, 0.05, 1, fg)
end

DRAW.ElementalPower = function(c: Ctx) -- all three elements: a flame, a snowflake, an impact star
	bigFlame(sub(c, 0.27, 0.0, 0.46))
	snowflake(sub(c, 0.02, 0.5, 0.46))
	local s = sub(c, 0.52, 0.5, 0.46)
	rect(s, 0.5, 0.5, 0.6, 0.6, 1, s.fg, 0.04, 0)
	rect(s, 0.5, 0.5, 0.6, 0.6, 1, s.fg, 0.04, 45)
	circle(s, 0.5, 0.5, 0.24, 2, s.dt)
end

DRAW.Accelerant = function(c: Ctx) -- a jerrycan
	local fg, dt = c.fg, c.dt
	rect(c, 0.46, 0.58, 0.58, 0.66, 1, fg, 0.12)
	bar(c, 0.64, 0.3, 0.8, 0.12, 0.11, 1, fg, "butt", 0.2)
	rect(c, 0.38, 0.36, 0.22, 0.09, 2, dt, 0.5)
	bar(c, 0.3, 0.52, 0.62, 0.82, 0.045, 2, dt)
	bar(c, 0.62, 0.52, 0.3, 0.82, 0.045, 2, dt)
end

DRAW.TurretDamage = turret
DRAW.HealPower = cross

DRAW.DeadEyeTime = function(c: Ctx) -- the dead eye with a stopwatch
	eye(sub(c, 0.0, 0.02, 0.72))
	local s = sub(c, 0.5, 0.48, 0.5, 4)
	circle(s, 0.5, 0.56, 0.86, 0, c.dt)
	stopwatch(s)
end

DRAW.BlastRadius = function(c: Ctx) -- an explosion inside its radius ring
	ring(c, 0.5, 0.5, 0.94, 0.06, 1, c.fg)
	burst(sub(c, 0.2, 0.2, 0.6))
end

-- UI ids.
DRAW.classes = function(c: Ctx) -- a shield with a chevron (the class tab)
	local fg = c.fg
	rect(c, 0.5, 0.34, 0.62, 0.36, 1, fg, 0.15)
	rect(c, 0.5, 0.52, 0.4384, 0.4384, 1, fg, 0.06, 45)
	arrowHead(c, 0.5, 0.38, 0, -1, 0.24, 0.09, 2, c.dt)
end

DRAW.avatar = function(c: Ctx) -- a heist mask (the avatar tab)
	local dt = c.dt
	rect(c, 0.5, 0.52, 0.62, 0.78, 1, c.fg, 0.45)
	rect(c, 0.37, 0.44, 0.18, 0.1, 2, dt, 0.5, 12)
	rect(c, 0.63, 0.44, 0.18, 0.1, 2, dt, 0.5, -12)
	rect(c, 0.5, 0.72, 0.22, 0.06, 2, dt, 0.5)
end

DRAW.shop = function(c: Ctx) -- a shopping cart
	local fg, dt = c.fg, c.dt
	bar(c, 0.08, 0.2, 0.2, 0.2, 0.07, 1, fg)
	bar(c, 0.2, 0.2, 0.32, 0.66, 0.07, 1, fg)
	rect(c, 0.56, 0.42, 0.52, 0.3, 1, fg, 0.1)
	bar(c, 0.32, 0.66, 0.78, 0.66, 0.07, 1, fg)
	circle(c, 0.38, 0.82, 0.15, 1, fg)
	circle(c, 0.72, 0.82, 0.15, 1, fg)
	rect(c, 0.47, 0.42, 0.04, 0.22, 2, dt)
	rect(c, 0.65, 0.42, 0.04, 0.22, 2, dt)
end

DRAW.close = function(c: Ctx) -- an X
	bar(c, 0.26, 0.26, 0.74, 0.74, 0.15, 1, c.fg)
	bar(c, 0.74, 0.26, 0.26, 0.74, 0.15, 1, c.fg)
end

DRAW.plus = function(c: Ctx) -- a plus
	bar(c, 0.22, 0.5, 0.78, 0.5, 0.15, 1, c.fg)
	bar(c, 0.5, 0.22, 0.5, 0.78, 0.15, 1, c.fg)
end

DRAW.revive = function(c: Ctx) -- a revive token: a heart with a cross
	heart(c)
	plusMark(c, 0.5, 0.48, 0.26, 0.08, 2, c.dt)
end

DRAW.vip = function(c: Ctx) -- a crown
	local fg, dt = c.fg, c.dt
	rect(c, 0.5, 0.58, 0.72, 0.3, 1, fg, 0.08)
	rect(c, 0.28, 0.43, 0.2, 0.2, 1, fg, 0, 45)
	rect(c, 0.72, 0.43, 0.2, 0.2, 1, fg, 0, 45)
	rect(c, 0.5, 0.43, 0.26, 0.26, 1, fg, 0, 45)
	circle(c, 0.28, 0.29, 0.1, 1, fg)
	circle(c, 0.72, 0.29, 0.1, 1, fg)
	circle(c, 0.5, 0.25, 0.1, 1, fg)
	rect(c, 0.5, 0.76, 0.78, 0.08, 1, fg, 0.4)
	for _, x in { 0.32, 0.5, 0.68 } do
		circle(c, x, 0.59, 0.08, 2, dt)
	end
end

DRAW.gift = function(c: Ctx) -- a gift box with a bow
	local fg, dt = c.fg, c.dt
	rect(c, 0.5, 0.66, 0.62, 0.42, 1, fg, 0.08)
	rect(c, 0.5, 0.4, 0.72, 0.16, 1, fg, 0.15)
	rect(c, 0.4, 0.25, 0.16, 0.16, 1, fg, 0.2, 45)
	rect(c, 0.6, 0.25, 0.16, 0.16, 1, fg, 0.2, 45)
	circle(c, 0.5, 0.3, 0.1, 1, fg)
	rect(c, 0.5, 0.475, 0.62, 0.035, 2, dt)
	rect(c, 0.5, 0.605, 0.1, 0.53, 2, dt)
end

------------------------------------------------------------------ API
function Icons.has(id: string?): boolean
	return id ~= nil and DRAW[id] ~= nil
end

-- px: the root's size in pixels now (stroke widths until the root reports its AbsoluteSize); 0 when unknown
-- (fit before layout), which also makes a fallback label scale with the root.
local function build(root: Frame, id: string, color: Color3, detail: Color3?, fallback: string?, px: number)
	local fn = DRAW[id]
	if not fn then
		local text = fallback or id
		local label = Instance.new("TextLabel")
		label.Name = "Fallback"
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.Font = Theme.Fonts.display
		label.Text = text
		label.TextColor3 = color
		if px > 0 then
			label.TextSize = math.max(8, math.floor(px * (if #text <= 1 then 0.6 else 0.34)))
		else
			label.TextScaled = true
		end
		label.Size = UDim2.fromScale(1, 1)
		label.ZIndex = root.ZIndex + 1
		label.Parent = root
		return
	end
	local c: Ctx = {
		root = root,
		ox = 0,
		oy = 0,
		s = 1,
		z = root.ZIndex,
		fg = color,
		dt = detail or color:Lerp(Color3.new(0, 0, 0), 0.55),
		strokes = {},
	}
	fn(c)
	if #c.strokes > 0 then
		local strokes = c.strokes
		local function paint(w: number)
			for _, s in strokes do
				s.stroke.Thickness = math.max(1, s.frac * w)
			end
		end
		paint(px)
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if root.AbsoluteSize.X > 0 then
				paint(root.AbsoluteSize.X)
			end
		end)
	end
end

local function newRoot(parent: Instance?, id: string): Frame
	local root = Instance.new("Frame")
	root.Name = "Icon_" .. id
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ZIndex = if parent and parent:IsA("GuiObject") then parent.ZIndex + 1 else 1
	return root
end

-- Draws `id` into a square, transparent root of `size` px parented to `parent`; returns the root.
function Icons.draw(
	parent: Instance?,
	id: string,
	size: number,
	color: Color3,
	detail: Color3?,
	fallback: string?
): Frame
	local root = newRoot(parent, id)
	root.Size = UDim2.fromOffset(size, size)
	build(root, id, color, detail, fallback, size)
	if parent then
		root.Parent = parent
	end
	return root
end

-- Draws `id` at `frac` of the parent's shorter side, centred, following the parent's size; returns the root.
function Icons.fit(
	parent: GuiObject,
	id: string,
	frac: number,
	color: Color3,
	detail: Color3?,
	fallback: string?
): Frame
	local root = newRoot(parent, id)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(frac, frac)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = root
	local abs = parent.AbsoluteSize
	local px = math.min(abs.X, abs.Y) * frac
	build(root, id, color, detail, fallback, px)
	root.Parent = parent
	return root
end

-- Fades every drawn part (ghost states); 0 restores.
function Icons.setTransparency(root: Frame, t: number)
	for _, d in root:GetDescendants() do
		if d:IsA("Frame") and d.BackgroundTransparency < 1 then
			d.BackgroundTransparency = t
		elseif d:IsA("UIStroke") then
			d.Transparency = t
		elseif d:IsA("TextLabel") then
			d.TextTransparency = t
		end
	end
end

return Icons
