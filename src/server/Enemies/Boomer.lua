--!strict
-- Boomer: runs at the nearest placeable within BoomerPlaceableSearch, else the nearest player. Once in
-- range it stops, beeps rising and swells for BoomerFuseSec, then bursts: BoomerDamage to players and
-- BoomerPlaceableMult x that to structures in BoomerRadius. Killed by damage it still goes off, smaller.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local Boomer = {}

local ORANGE = Color3.fromRGB(255, 140, 40)

local function explode(d: any, api: any, radiusMult: number)
	if d.mem.exploded then
		return
	end
	d.mem.exploded = true
	local radius = Config.BoomerRadius * radiusMult
	local pos = d.root.Position
	api.blast(pos, radius, Config.BoomerDamage, Config.BoomerDamage * Config.BoomerPlaceableMult, "boomer")
	api.fire("Blast", { position = pos, radius = radius, color = ORANGE, shake = 0.35, pitch = 0.7, boomer = true })
end

function Boomer.tick(d: any, api: any, now: number)
	local fuseAt: number? = d.mem.fuseAt
	if fuseAt then
		api.hold(d)
		if now >= fuseAt then
			explode(d, api, 1)
			api.selfDestruct(d)
		end
		return
	end
	if now - d.lastRetarget >= api.retargetInterval then
		d.lastRetarget = now
		local structure = api.nearestStructure(d.root.Position, Config.BoomerPlaceableSearch)
		if structure then
			d.target = structure
		else
			local _, root = api.nearestPlayer(d.root.Position, false)
			d.target = root
		end
	end
	local target = d.target
	if not target or not target.Parent then
		api.hold(d)
		return
	end
	local reach = d.row.range + math.max(target.Size.X, target.Size.Z) / 2
	if (target.Position - d.root.Position).Magnitude <= reach then
		-- In range: the fuse starts, the belly swells, everyone hears the beeps.
		d.mem.fuseAt = now + Config.BoomerFuseSec
		api.hold(d)
		local belly = d.model:FindFirstChild("Belly")
		if belly and belly:IsA("BasePart") then
			TweenService
				:Create(belly, TweenInfo.new(Config.BoomerFuseSec, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Size = belly.Size * 1.7,
					Color = Color3.fromRGB(255, 220, 120),
				})
				:Play()
		end
		api.fire("BoomerFuse", { model = d.model, sec = Config.BoomerFuseSec })
		return
	end
	api.chase(d, target, now)
end

-- Killed by a player's damage: a smaller burst where it fell. A clear (kill all, run reset) never bursts.
function Boomer.onDeath(d: any, api: any, attacker: Player?)
	if attacker and not d.mem.exploded then
		explode(d, api, Config.BoomerDeathRadiusMult)
	end
end

return Boomer
