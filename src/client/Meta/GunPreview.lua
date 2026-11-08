--!strict
-- The Weapons tab's live preview (Round 18c): a local copy of the held-gun model — the same GunModels stand-in the
-- server builds in PlayerState.refreshHeldVisual (rarity strips in the hub's Common colour, the wrap on the
-- furniture) — carried in the right hand while the real held gun hides locally. Nothing replicates.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GunModels = require(Shared:WaitForChild("GunModels"))
local Weapons = require(Shared:WaitForChild("Weapons"))
local Rarity = require(Shared:WaitForChild("Rarity"))

local GunPreview = {}

GunPreview.Name = "MetaPreviewGun"

-- Builds the preview gun for `weaponId` (a showcase gun gets its archetype's shape) in `char`'s right hand.
-- Returns the model (PrimaryPart "Body" = the gun's root, its Wrap parts take wraps) or nil without a hand.
function GunPreview.build(char: Model, weaponId: string, wrapId: string?): Model?
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return nil
	end
	local archetype: string? = nil
	if not Weapons.ById[weaponId] then
		for _, s in Weapons.Showcase do
			if s.id == weaponId then
				archetype = s.archetype
			end
		end
	end
	local root = GunModels.build(weaponId, { rarity = Rarity.Common, wrapId = wrapId, archetype = archetype })
	local m = Instance.new("Model")
	m.Name = GunPreview.Name
	root.Parent = m
	m.PrimaryPart = root
	GunModels.mountToHand(root, hand)
	m.Parent = char
	return m
end

-- Hide (or show again) the server's held gun on this client only.
function GunPreview.setServerGunHidden(char: Model, hidden: boolean)
	local v = if hidden then 1 else 0
	for _, name in { "HeldGun", "HeldGunWrap" } do
		local p = char:FindFirstChild(name)
		if p then
			if p:IsA("BasePart") then
				p.LocalTransparencyModifier = v
			end
			for _, d in p:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = v
				end
			end
		end
	end
end

return GunPreview
