--!strict
-- Round 19: THE BANK's glass breaks. A player bullet or an enemy shot that lands on a window, or a blast within
-- reach of one, shatters it: the whole window goes (no collision, no query), a burst of shards falls, and from
-- then on players and enemies walk, jump and shoot through the gap (paths take it the next time they plan).
-- Every window is whole again at run start.
--
-- Round 19c: a window is a unit. The builder's pane mesh (Config.BreakableNames) only collides along its centre
-- strip, and the glass sheet in front of it (a see-through Ice part elsewhere in the hierarchy) and the frame bars
-- are separate parts, so a shot off the strip stopped on the glass and a broken pane left the rest standing. Each
-- pane now gets an invisible hit box the size of the pane (shots and bodies stop on it anywhere), and its group is
-- the pane's own window model (WindowGroupMaxParts or fewer parts: the mesh and its bars) plus every see-through
-- part inside the pane's box. Hitting any of them breaks them all; the opaque trim and the wall stay.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
local MapLoader = require(script.Parent.MapLoader)
local Combat = require(script.Parent.Combat)
local Enemy = require(script.Parent.Enemy)
local Hazards = require(script.Parent.Enemies.Hazards)

local Windows = {}

type Saved = { part: BasePart, transparency: number, collide: boolean, query: boolean }
type Window = {
	pane: BasePart, -- the builder's pane (shards and the blast reach measure from it)
	hitbox: BasePart,
	parts: { Saved }, -- everything that goes when it breaks (the hit box included)
	broken: boolean,
}

local byPart: { [BasePart]: Window } = {}
local list: { Window } = {}
local brokenThisRun = 0

local function shards(part: BasePart)
	local effects = Workspace:FindFirstChild("Effects") or Workspace
	local cf, size = part.CFrame, part.Size
	for _ = 1, Config.WindowShards do
		local s = Instance.new("Part")
		s.Size = Vector3.new(0.2 + math.random() * 0.6, 0.2 + math.random() * 0.6, 0.08)
		s.CFrame = cf
			* CFrame.new((math.random() - 0.5) * size.X, (math.random() - 0.5) * size.Y, (math.random() - 0.5) * size.Z)
			* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		s.Color = Color3.fromRGB(200, 225, 240)
		s.Material = Enum.Material.Glass
		s.Transparency = 0.3
		s.CanQuery = false
		s.CanTouch = false
		s.CollisionGroup = "Corpse"
		s.Parent = effects
		s.AssemblyLinearVelocity =
			Vector3.new((math.random() - 0.5) * 10, math.random() * 6, (math.random() - 0.5) * 10)
		TweenService:Create(s, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.4), {
			Transparency = 1,
		}):Play()
		task.delay(2.1, function()
			s:Destroy()
		end)
	end
end

local function breakWindow(w: Window): boolean
	if w.broken then
		return false
	end
	w.broken = true
	brokenThisRun += 1
	for _, s in w.parts do
		s.part.Transparency = 1
		s.part.CanCollide = false
		s.part.CanQuery = false
	end
	shards(w.pane)
	World.fireRun("WindowBreak", { position = w.pane.Position })
	return true
end

function Windows.breakPane(part: BasePart): boolean
	local w = byPart[part]
	return if w then breakWindow(w) else false
end

-- A shot landed on geometry: break it if it is any part of a window.
function Windows.hit(part: BasePart, _position: Vector3)
	local w = byPart[part]
	if w then
		breakWindow(w)
	end
end

-- A blast: every window within its radius (measured to the pane's surface) breaks.
function Windows.breakNear(position: Vector3, radius: number)
	for _, w in list do
		if not w.broken then
			local local_ = w.pane.CFrame:PointToObjectSpace(position)
			local h = w.pane.Size / 2
			local out = Vector3.new(
				math.max(0, math.abs(local_.X) - h.X),
				math.max(0, math.abs(local_.Y) - h.Y),
				math.max(0, math.abs(local_.Z) - h.Z)
			)
			if out.Magnitude <= radius then
				breakWindow(w)
			end
		end
	end
end

-- Run start / hub: every window whole.
function Windows.resetRun()
	if brokenThisRun > 0 then
		Log.event("Map", "%d window%s broken last run", brokenThisRun, if brokenThisRun == 1 then "" else "s")
	end
	brokenThisRun = 0
	for _, w in list do
		if w.broken then
			w.broken = false
			for _, s in w.parts do
				if s.part.Parent then
					s.part.Transparency = s.transparency
					s.part.CanCollide = s.collide
					s.part.CanQuery = s.query
				end
			end
		end
	end
end

local function save(part: BasePart): Saved
	return { part = part, transparency = part.Transparency, collide = part.CanCollide, query = part.CanQuery }
end

-- Small parts of one window beside the pane: inside its box (plus a margin) and no bigger than it.
local function inPane(pane: BasePart, part: BasePart): boolean
	local p = pane.CFrame:PointToObjectSpace(part.Position)
	local h = pane.Size / 2
	local m = Config.WindowGroupMargin
	if math.abs(p.X) > h.X + m or math.abs(p.Y) > h.Y + m or math.abs(p.Z) > h.Z + m then
		return false
	end
	local biggest = math.max(pane.Size.X, pane.Size.Y, pane.Size.Z)
	return math.max(part.Size.X, part.Size.Y, part.Size.Z) <= biggest * 1.25
end

function Windows.init()
	local bank = MapLoader.bank
	local geo = bank and bank:FindFirstChild("Geometry")
	if not geo then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "WindowHitboxes"
	folder.Parent = bank
	local grouped = 0
	local glass: { BasePart } = {}
	for _, d in geo:GetDescendants() do
		if
			d:IsA("BasePart")
			and (d.Material == Enum.Material.Glass or d.Material == Enum.Material.Ice or d.Transparency >= 0.3)
			and d.Transparency < 1
		then
			table.insert(glass, d)
		end
	end
	for _, d in geo:GetDescendants() do
		if not (d:IsA("BasePart") and table.find(Config.BreakableNames, d.Name)) or byPart[d] then
			continue
		end
		local pane = d :: BasePart
		local members: { [BasePart]: boolean } = { [pane] = true }
		local parent = pane.Parent
		if parent and parent ~= geo and parent:IsA("Model") then
			local own = {}
			for _, c in parent:GetDescendants() do
				if c:IsA("BasePart") then
					table.insert(own, c)
				end
			end
			if #own <= Config.WindowGroupMaxParts then
				for _, c in own do
					members[c] = true
				end
			end
		end
		-- The glass sheet (and any other see-through part) inside the pane's box, wherever it sits in the
		-- hierarchy: shots used to stop on it. The frame trim and the wall around the hole are opaque and stay.
		for _, c in glass do
			if not members[c] and not byPart[c] and inPane(pane, c) then
				members[c] = true
			end
		end
		-- The hit box: the pane's own box, a touch thicker so a grazing shot still lands on it.
		local hitbox = Instance.new("Part")
		hitbox.Name = "WindowHitbox"
		hitbox.Anchored = true
		hitbox.CanCollide = true
		hitbox.CanQuery = true
		hitbox.CanTouch = false
		hitbox.CastShadow = false
		hitbox.Transparency = 1
		local s = pane.Size
		local thin = math.min(s.X, s.Y, s.Z)
		local pad = math.max(0, Config.WindowHitboxThickness - thin)
		hitbox.Size = Vector3.new(
			if s.X == thin then s.X + pad else s.X,
			if s.Y == thin then s.Y + pad else s.Y,
			if s.Z == thin then s.Z + pad else s.Z
		)
		hitbox.CFrame = pane.CFrame
		hitbox.Parent = folder
		members[hitbox] = true
		local w: Window = { pane = pane, hitbox = hitbox, parts = {}, broken = false }
		for part in members do
			table.insert(w.parts, save(part))
			byPart[part] = w
		end
		grouped += #w.parts - 2
		table.insert(list, w)
	end
	Combat.onWorldHit = Windows.hit
	Enemy.onWorldHit = Windows.hit
	Hazards.onBlast = Windows.breakNear
	Log.event("Map", "%d breakable windows (%d frame / glass parts grouped with them)", #list, grouped)
end

return Windows
