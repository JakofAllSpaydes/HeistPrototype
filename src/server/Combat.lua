--!strict
-- Hitscan validation, damage, kill cash. Raycasts from the server-side head along the client direction.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Weapons = require(Shared.Weapons)
local Remotes = require(Shared.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local Economy = require(script.Parent.Economy)
local Enemy = require(script.Parent.Enemy)

local Combat = {}

local function coneSpread(direction: Vector3, halfAngleDeg: number): Vector3
	if halfAngleDeg <= 0 then
		return direction
	end
	local angle = math.rad(halfAngleDeg) * math.sqrt(math.random())
	local roll = math.random() * math.pi * 2
	local cf = CFrame.lookAt(Vector3.zero, direction)
	local offset = cf * CFrame.Angles(0, 0, roll) * CFrame.Angles(angle, 0, 0)
	return offset.LookVector
end

function Combat.init()
	local groundLoot = Workspace:WaitForChild("GroundLoot")
	local effects = Workspace:WaitForChild("Effects")

	Remotes.FireShot.OnServerEvent:Connect(function(player: Player, origin: any, direction: any, _clientTime: any)
		if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
			return
		end
		if direction.Magnitude < 0.5 then
			return
		end
		local char = player.Character
		local head = char and char:FindFirstChild("Head") :: BasePart?
		if not char or not head then
			return
		end
		if (origin - head.Position).Magnitude > Config.MaxOriginDriftStuds then
			return
		end

		local state = PlayerState.get(player)
		local st = PlayerState.computed(state)
		local now = os.clock()
		if now - state.lastShotAt < 1 / (st.fireRate * Config.FireRateTolerance) then
			return
		end
		state.lastShotAt = now

		local weapon = Weapons.ById[state.held.weaponId]
		local dir = direction.Unit
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char, groundLoot, effects }

		for _ = 1, weapon.pellets do
			local d = if weapon.pellets > 1 then coneSpread(dir, weapon.spread) else dir
			local result = Workspace:Raycast(head.Position, d * Config.MaxShotRange, params)
			if not result then
				continue
			end
			local model = Enemy.fromPart(result.Instance)
			if not model then
				continue
			end
			local headshot = result.Instance.Name == "Head"
			local crit = math.random() * 100 < st.critChance
			local dmg = st.damage * (if headshot then st.headshotMult else 1) * (if crit then Config.CritDmgMult else 1)
			dmg = math.max(1, math.round(dmg))
			local killed = Enemy.damage(model, dmg, player)
			local cash = 0
			if killed then
				cash = math.round(Config.CashPerKill * st.greed)
				Economy.addCash(state, cash)
			end
			Remotes.Juice:FireClient(player, "Hit", {
				position = result.Position,
				amount = dmg,
				headshot = headshot,
				crit = crit,
				killed = killed,
				model = model,
				cash = cash,
			})
		end
	end)
end

return Combat
