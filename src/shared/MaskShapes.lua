--!strict
-- Mask geometry (brief 6): one builder for every mask shape, used by the server (the worn mask), the
-- customization preview and the store / pass mannequins. The main piece is a Part named `name` welded to the
-- head; extra pieces are child Parts of it, welded to the head too, so one Destroy removes the whole mask.
-- Shapes: none, visor, bandana (the originals) and goggles, skull, halfmask, mono, horns, helmet, crown, hood.
local MaskShapes = {}

type MaskLike = { color: string, accent: string?, shape: string }

local function piece(
	parent: Instance?,
	head: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	if shape then
		p.Shape = shape
	end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	p.CastShadow = false
	p.CFrame = head.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = p
	weld.Parent = p
	p.Parent = parent
	return p
end

-- Builds the mask on `head` and returns its main Part (parented to `parent`), or nil for shape "none".
function MaskShapes.build(head: BasePart, mask: MaskLike, name: string, parent: Instance): BasePart?
	local main = Color3.fromHex(mask.color)
	local accent = if mask.accent then Color3.fromHex(mask.accent) else main
	local shape = mask.shape
	local M = Enum.Material
	if shape == "none" or shape == nil then
		return nil
	elseif shape == "visor" then
		local p = piece(nil, head, name, Vector3.new(1.3, 0.35, 0.3), CFrame.new(0, 0.1, -0.55), main, M.Neon)
		if mask.accent then
			-- Gold trim along the visor's top and bottom edge.
			piece(p, head, "Trim", Vector3.new(1.36, 0.06, 0.34), CFrame.new(0, 0.29, -0.55), accent, M.Neon)
			piece(p, head, "Trim", Vector3.new(1.36, 0.06, 0.34), CFrame.new(0, -0.09, -0.55), accent, M.Neon)
		end
		p.Parent = parent
		return p
	elseif shape == "bandana" then
		local p = piece(nil, head, name, Vector3.new(1.25, 0.5, 1.25), CFrame.new(0, -0.25, 0), main, M.Fabric)
		if mask.accent then
			for i = -1, 1 do
				piece(
					p,
					head,
					"Stripe",
					Vector3.new(0.12, 0.52, 1.27),
					CFrame.new(i * 0.35, -0.25, 0) * CFrame.Angles(0, 0, math.rad(18)),
					accent,
					M.Fabric
				)
			end
		end
		p.Parent = parent
		return p
	elseif shape == "goggles" then
		local p = piece(nil, head, name, Vector3.new(1.3, 0.16, 1.28), CFrame.new(0, 0.12, 0), main, M.Leather)
		for _, x in { -0.27, 0.27 } do
			piece(
				p,
				head,
				"Lens",
				Vector3.new(0.18, 0.42, 0.42),
				CFrame.new(x, 0.12, -0.58) * CFrame.Angles(0, math.rad(90), 0),
				accent,
				M.Glass,
				Enum.PartType.Cylinder
			)
		end
		p.Parent = parent
		return p
	elseif shape == "skull" then
		local p = piece(nil, head, name, Vector3.new(1.1, 1.1, 0.16), CFrame.new(0, 0, -0.56), main, M.SmoothPlastic)
		for _, x in { -0.24, 0.24 } do
			piece(p, head, "Eye", Vector3.new(0.26, 0.2, 0.06), CFrame.new(x, 0.14, -0.64), accent, M.SmoothPlastic)
		end
		for i = -2, 2 do
			piece(
				p,
				head,
				"Vent",
				Vector3.new(0.06, 0.16, 0.06),
				CFrame.new(i * 0.12, -0.3, -0.64),
				accent,
				M.SmoothPlastic
			)
		end
		p.Parent = parent
		return p
	elseif shape == "halfmask" then
		local p =
			piece(nil, head, name, Vector3.new(1.18, 0.5, 0.2), CFrame.new(0, -0.24, -0.55), main, M.SmoothPlastic)
		piece(p, head, "Grin", Vector3.new(0.8, 0.08, 0.06), CFrame.new(0, -0.22, -0.67), accent, M.SmoothPlastic)
		p.Parent = parent
		return p
	elseif shape == "mono" then
		local p = piece(nil, head, name, Vector3.new(1.24, 0.5, 0.22), CFrame.new(0, 0.1, -0.54), main, M.Metal)
		piece(p, head, "Slit", Vector3.new(1.0, 0.09, 0.06), CFrame.new(0, 0.12, -0.66), accent, M.Neon)
		p.Parent = parent
		return p
	elseif shape == "horns" then
		local p = piece(nil, head, name, Vector3.new(1.26, 0.2, 1.26), CFrame.new(0, 0.5, 0), main, M.Leather)
		for _, side in { -1, 1 } do
			piece(
				p,
				head,
				"Horn",
				Vector3.new(0.22, 0.7, 0.22),
				CFrame.new(side * 0.55, 0.85, 0) * CFrame.Angles(0, 0, math.rad(-side * 30)),
				accent,
				M.SmoothPlastic
			)
		end
		p.Parent = parent
		return p
	elseif shape == "helmet" then
		local p = piece(
			nil,
			head,
			name,
			Vector3.new(1.45, 1.45, 1.45),
			CFrame.new(0, 0.18, 0.05),
			main,
			M.Metal,
			Enum.PartType.Ball
		)
		piece(p, head, "Visor", Vector3.new(1.1, 0.3, 0.2), CFrame.new(0, 0.06, -0.66), accent, M.Neon)
		p.Parent = parent
		return p
	elseif shape == "crown" then
		local p = piece(nil, head, name, Vector3.new(1.3, 0.22, 1.3), CFrame.new(0, 0.62, 0), accent, M.Metal)
		for i = 0, 4 do
			local a = math.rad(i * 72)
			piece(
				p,
				head,
				"Point",
				Vector3.new(0.18, 0.36, 0.18),
				CFrame.new(math.sin(a) * 0.55, 0.88, math.cos(a) * 0.55) * CFrame.Angles(0, a, math.rad(45)),
				accent,
				M.Metal
			)
		end
		piece(
			p,
			head,
			"Gem",
			Vector3.new(0.16, 0.16, 0.08),
			CFrame.new(0, 0.62, -0.68),
			Color3.fromHex("E8554D"),
			M.Neon
		)
		p.Parent = parent
		return p
	elseif shape == "hood" then
		local p = piece(nil, head, name, Vector3.new(1.5, 1.4, 1.5), CFrame.new(0, 0.12, 0.1), main, M.Grass)
		piece(p, head, "Shade", Vector3.new(1.2, 0.5, 0.12), CFrame.new(0, -0.18, -0.6), accent, M.Fabric)
		p.Parent = parent
		return p
	end
	return nil
end

-- Every BasePart of a built mask (the main piece and its children), for local transparency or glow.
function MaskShapes.parts(main: Instance?): { BasePart }
	local out: { BasePart } = {}
	if main and main:IsA("BasePart") then
		table.insert(out, main)
		for _, d in main:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
	end
	return out
end

return MaskShapes
