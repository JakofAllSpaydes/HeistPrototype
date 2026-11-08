--!strict
-- Round 24i: the one bullet-line look, for the local player's shots (Gun.client) and teammates' (WorldFx).
-- Feedback only: hits are decided by the head-origin raycasts, never by this line. When `from` is the gun's Muzzle
-- attachment the beam starts ON it (Beam.Attachment0), so the line stays on the barrel tip while recoil and the
-- pose move the gun; a fixed start point was left beside the gun after the kick and read as coming from the chest.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Tracer = {}

Tracer.Color = Color3.fromHex("FFE2A0")
local LIFE = 0.05
local serial = 0

-- `from` may also be a function returning the start each frame (first person: a point fixed in camera space,
-- so the line moves with the view but not with the viewmodel's recoil flip).
function Tracer.draw(
	from: Attachment | Vector3 | () -> Vector3,
	to: Vector3,
	color: Color3?,
	thin: boolean?,
	life: number?,
	aimed: boolean?
)
	local a1 = Instance.new("Attachment")
	a1.WorldPosition = to
	a1.Parent = Workspace.Terrain
	local temp: Attachment? = nil
	local a0: Attachment
	local follow: string? = nil -- the render-step binding that moves a camera-space start
	if typeof(from) == "Instance" then
		a0 = from
	else
		local t = Instance.new("Attachment")
		if typeof(from) == "function" then
			local fn = from :: () -> Vector3
			t.WorldPosition = fn()
			-- After the camera has moved this frame (Camera.client binds at RenderPriority.Camera).
			serial += 1
			local name = "GHSTracerFollow" .. serial
			follow = name
			RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 2, function()
				t.WorldPosition = fn()
			end)
		else
			t.WorldPosition = from :: Vector3
		end
		t.Parent = Workspace.Terrain
		temp = t
		a0 = t
	end
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	-- First person: the start is a lens-width from the eye, so the line is drawn thin.
	beam.Width0 = if thin then 0.035 else 0.12
	beam.Width1 = if thin then 0.03 else 0.05
	if aimed then
		-- Round 25: an aimed first-person tracer widens with distance, so it still reads through a magnified scope.
		local startPos = (a0 :: Attachment).WorldPosition
		beam.Width0 = 0.03
		beam.Width1 = math.clamp((to - startPos).Magnitude * 0.005, 0.05, 0.6)
	end
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Color = ColorSequence.new(color or Tracer.Color)
	beam.Transparency = NumberSequence.new(0.1)
	beam.Parent = a1
	task.delay(life or LIFE, function()
		if follow then
			RunService:UnbindFromRenderStep(follow)
		end
		a1:Destroy()
		if temp then
			temp:Destroy()
		end
	end)
end

-- The muzzle a character's shots visibly leave: its HeldGun's Muzzle attachment, or nil.
function Tracer.muzzleOf(char: Model?): Attachment?
	local gun = char and char:FindFirstChild("HeldGun")
	local att = gun and gun:FindFirstChild("Muzzle")
	return if att and att:IsA("Attachment") then att else nil
end

return Tracer
