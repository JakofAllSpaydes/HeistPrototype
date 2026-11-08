--!strict
-- Marksman: the nearest player with line of sight gets a red laser painted on them for MarksmanAimSec.
-- The line locks where it was painted; at the end of the aim the shot goes down that line and only hits
-- a player who is still in it. A stun or the Marksman's death cancels the aim.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Ranged = require(script.Parent.Ranged)

local Marksman = {}

local RED = Color3.fromHex("E8554D")

local function clearBeam(d: any)
	local beam = d.mem.beam
	if beam then
		for _, inst in beam do
			if inst.Parent then
				inst:Destroy()
			end
		end
	end
	d.mem.beam = nil
	d.mem.aimUntil = nil
	d.mem.aimDir = nil
end

local function paint(d: any, api: any, from: Vector3, dir: Vector3)
	local gun = d.model:FindFirstChild("Gun")
	local muzzle = gun and gun:FindFirstChild("Muzzle")
	local a0: Attachment
	if muzzle and muzzle:IsA("Attachment") then
		a0 = muzzle
	else
		a0 = Instance.new("Attachment")
		a0.WorldPosition = from
		a0.Parent = Workspace.Terrain
	end
	local a1 = Instance.new("Attachment")
	a1.WorldPosition = from + dir * d.row.range
	a1.Parent = Workspace.Terrain
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 0.12
	beam.Width1 = 0.12
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Color = ColorSequence.new(RED)
	beam.Transparency = NumberSequence.new(0.15)
	beam.Parent = a1
	local dot = Instance.new("Part")
	dot.Shape = Enum.PartType.Ball
	dot.Size = Vector3.new(0.5, 0.5, 0.5)
	dot.Color = RED
	dot.Material = Enum.Material.Neon
	dot.Anchored = true
	dot.CanCollide = false
	dot.CanQuery = false
	dot.CanTouch = false
	dot.CFrame = CFrame.new(from + dir * (d.target and (d.target.Position - from).Magnitude or 10))
	dot.Parent = Workspace:FindFirstChild("Effects") or Workspace
	d.mem.beam = { a1, dot, if a0.Parent == Workspace.Terrain then a0 else nil }
	api.fire("EnemyLaser", { position = from, sec = Config.MarksmanAimSec, archetype = d.archetype })
end

function Marksman.tick(d: any, api: any, now: number)
	local aimUntil: number? = d.mem.aimUntil
	if aimUntil then
		-- Mid-aim: stand still on the painted line, then fire down it.
		api.hold(d)
		local dir: Vector3 = d.mem.aimDir
		api.face(d, d.root.Position + dir * 10)
		if now < aimUntil then
			return
		end
		local from = api.muzzle(d)
		local hitPlayer, hitPos = api.rayPlayers(from, dir, d.row.range, Config.MarksmanHitRadius)
		local to = hitPos or (from + dir * d.row.range)
		if hitPlayer then
			api.damagePlayer(hitPlayer, d.dmg, "shot")
		end
		api.fire("EnemyShot", {
			from = from,
			to = to,
			hit = hitPlayer ~= nil,
			userId = if hitPlayer then hitPlayer.UserId else nil,
			archetype = d.archetype,
			heavy = true,
		})
		clearBeam(d)
		d.lastAttack = now
		return
	end
	local player, root, ready = Ranged.approach(d, api, now)
	if not ready or not player or not root then
		return
	end
	if now - d.lastAttack < d.row.cooldown then
		return
	end
	local from = api.muzzle(d)
	local char = player.Character
	local head = char and char:FindFirstChild("Head") :: BasePart?
	local aim = if head then head.Position else root.Position + Vector3.new(0, 1.2, 0)
	local dir = (aim - from)
	if dir.Magnitude < 0.5 then
		return
	end
	d.mem.aimDir = dir.Unit
	d.mem.aimUntil = now + Config.MarksmanAimSec
	paint(d, api, from, dir.Unit)
end

-- A stun breaks the aim; so does death or a clear.
function Marksman.onStun(d: any)
	clearBeam(d)
end

function Marksman.cleanup(d: any)
	clearBeam(d)
end

return Marksman
