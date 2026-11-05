--!strict
-- Grenadier: holds at range and lobs a shell at the target's position every cooldown. A red circle grows
-- on the floor from nothing to GrenadierRadius over GrenadierTelegraphSec while the shell arcs in, then
-- the burst hits players (and placeables) in the circle and leaves a fire patch for GrenadierFireSec.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Ranged = require(script.Parent.Ranged)

local Grenadier = {}

local FIRE = Color3.fromRGB(255, 140, 40)

-- Lob a shell from `from` to the floor at `target`; the burst lands when the telegraph finishes.
function Grenadier.lob(api: any, from: Vector3, target: Vector3, dmg: number, archetype: string)
	local to = Vector3.new(target.X, Config.FloorTop + 0.4, target.Z)
	local flight = math.max(0.05, Config.GrenadierTelegraphSec)
	api.telegraph(to, Config.GrenadierRadius, flight)
	api.fire("EnemyLob", { from = from, to = to, sec = flight, archetype = archetype })
	local shell = Instance.new("Part")
	shell.Name = "Shell"
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.new(0.8, 0.8, 0.8)
	shell.Color = Color3.fromRGB(60, 66, 36)
	shell.Material = Enum.Material.Metal
	shell.Anchored = true
	shell.CanCollide = false
	shell.CanQuery = false
	shell.CanTouch = false
	shell.CFrame = CFrame.new(from)
	shell.Parent = Workspace:FindFirstChild("Effects") or Workspace
	task.spawn(function()
		local elapsed = 0
		local height = math.clamp((to - from).Magnitude * 0.35, 6, 18)
		while elapsed < flight do
			elapsed += RunService.Heartbeat:Wait()
			local a = math.clamp(elapsed / flight, 0, 1)
			shell.CFrame = CFrame.new(from:Lerp(to, a) + Vector3.new(0, height * 4 * a * (1 - a), 0))
		end
		shell:Destroy()
		api.blast(to, Config.GrenadierRadius, dmg, dmg, "grenade")
		api.fire("Blast", { position = to, radius = Config.GrenadierRadius, color = FIRE, shake = 0.25, pitch = 0.8 })
		api.fireField(to, Config.GrenadierRadius, Config.GrenadierFireSec, Config.GrenadierFireDps)
	end)
end

function Grenadier.tick(d: any, api: any, now: number)
	local player, root, ready = Ranged.approach(d, api, now)
	if not ready or not player or not root then
		return
	end
	if now - d.lastAttack < d.row.cooldown then
		return
	end
	d.lastAttack = now
	Grenadier.lob(api, api.muzzle(d), root.Position, d.dmg, d.archetype)
end

return Grenadier
