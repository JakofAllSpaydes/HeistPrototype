--!strict
-- Round 19: THE BANK's glass breaks. A player bullet or an enemy shot that lands on a window pane
-- (Config.BreakableNames: the builder's `bankwindow` parts), or a blast within reach of one, shatters it: the pane
-- goes (no collision, no query), a burst of shards falls, and from then on players and enemies walk, jump and shoot
-- through the gap (paths take it the next time they plan). Every pane is whole again at run start.
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

type Pane = { part: BasePart, transparency: number, collide: boolean, query: boolean, broken: boolean }

local panes: { [BasePart]: Pane } = {}
local list: { Pane } = {}
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

function Windows.breakPane(part: BasePart): boolean
	local p = panes[part]
	if not p or p.broken then
		return false
	end
	p.broken = true
	brokenThisRun += 1
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	shards(part)
	World.fireRun("WindowBreak", { position = part.Position })
	return true
end

-- A shot landed on geometry: break it if it is a pane.
function Windows.hit(part: BasePart, _position: Vector3)
	if panes[part] then
		Windows.breakPane(part)
	end
end

-- A blast: every pane within its radius (measured to the pane's surface) breaks.
function Windows.breakNear(position: Vector3, radius: number)
	for _, p in list do
		if not p.broken then
			local local_ = p.part.CFrame:PointToObjectSpace(position)
			local h = p.part.Size / 2
			local out = Vector3.new(
				math.max(0, math.abs(local_.X) - h.X),
				math.max(0, math.abs(local_.Y) - h.Y),
				math.max(0, math.abs(local_.Z) - h.Z)
			)
			if out.Magnitude <= radius then
				Windows.breakPane(p.part)
			end
		end
	end
end

-- Run start / hub: every pane whole.
function Windows.resetRun()
	if brokenThisRun > 0 then
		Log.event("Map", "%d window%s broken last run", brokenThisRun, if brokenThisRun == 1 then "" else "s")
	end
	brokenThisRun = 0
	for _, p in list do
		if p.broken and p.part.Parent then
			p.broken = false
			p.part.Transparency = p.transparency
			p.part.CanCollide = p.collide
			p.part.CanQuery = p.query
		end
	end
end

function Windows.init()
	local bank = MapLoader.bank
	local geo = bank and bank:FindFirstChild("Geometry")
	if not geo then
		return
	end
	for _, d in geo:GetDescendants() do
		if d:IsA("BasePart") and table.find(Config.BreakableNames, d.Name) then
			local p =
				{ part = d, transparency = d.Transparency, collide = d.CanCollide, query = d.CanQuery, broken = false }
			panes[d] = p
			table.insert(list, p)
		end
	end
	Combat.onWorldHit = Windows.hit
	Enemy.onWorldHit = Windows.hit
	Hazards.onBlast = Windows.breakNear
	Log.event("Map", "%d breakable window panes", #list)
end

return Windows
