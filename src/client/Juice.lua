--!strict
-- Rarity-scaled feedback shared by the weapon reel, the upgrade overlay and swaps.
-- Higher tier = bigger punch, camera shake, screen flash, ray burst, louder and higher sound.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local HUD = require(script.Parent:WaitForChild("HUD"))

export type Tier = {
	tier: number,
	punch: number,
	shake: number,
	shakeDur: number,
	flash: number,
	rays: boolean,
	rayCount: number,
	raySize: number,
	volume: number,
	pitch: number,
	hold: number,
}

local Juice = {}

function Juice.tier(tier: number): Tier
	local t = math.clamp(math.floor(tier), 1, 5)
	return {
		tier = t,
		punch = 1.04 + t * 0.035,
		shake = Config.JuiceShakeByTier[t],
		shakeDur = Config.JuiceShakeDurByTier[t],
		flash = Config.JuiceFlashByTier[t],
		rays = t >= 3,
		rayCount = 4 + t * 2,
		raySize = 120 + t * 50,
		volume = 0.35 + t * 0.09,
		pitch = 0.55 + t * 0.15,
		hold = if t >= 4 then 0.3 else 0,
	}
end

-- Radial ray burst behind a screen point.
function Juice.rays(center: Vector2, color: Color3, count: number, size: number, duration: number)
	local S = UI.S
	local gui = HUD.gui
	if not gui then
		return
	end
	local rays = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = UDim2.fromOffset(S(10), S(10)),
		ZIndex = 0,
		Parent = gui,
	})
	for i = 1, count do
		local ray = UI.frame({
			BackgroundColor3 = color,
			BackgroundTransparency = 0.25,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(S(16), S(size)),
			Rotation = (i - 1) * (360 / count),
			Parent = rays,
		})
		UI.tween(ray, { BackgroundTransparency = 1, Size = UDim2.fromOffset(S(4), S(size * 1.7)) }, duration)
	end
	UI.tween(rays, { Rotation = 35 }, duration)
	task.delay(duration + 0.05, function()
		rays:Destroy()
	end)
end

-- The full burst for a tier at a screen point (rays), plus shake and flash through the Juice signal.
function Juice.burst(tier: number, color: Color3, center: Vector2?): Tier
	local j = Juice.tier(tier)
	if j.rays and center then
		Juice.rays(center, color, j.rayCount, j.raySize, 0.6)
	end
	if j.flash > 0 then
		ClientState.Juice:Fire("RarityFlash", { color = color, alpha = j.flash })
	end
	if j.shake > 0 then
		ClientState.Juice:Fire("Shake", { amp = j.shake, dur = j.shakeDur })
	end
	if j.tier == 5 then
		UI.sound(Theme.Sounds.legendary, 1, 0.75)
	end
	return j
end

return Juice
