--!strict
-- Brief 6: 2D art for anything the store, sheets, the pass and the reveals show: a Rewards.Reward (weapon, mask,
-- wrap, pose, class, Gold, tokens, crate opens, boost, mastery, XP) or a product icon (cash, pass, skip, restock,
-- Robux). Built from frames in the house style (shapes plus 3-letter caps or a letter in a circle), sized to fit
-- a square `size`. ItemArt.draw returns the root frame (transparent background, centered by the caller).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Weapons = require(Shared:WaitForChild("Weapons"))
local Masks = require(Shared:WaitForChild("Masks"))
local Wraps = require(Shared:WaitForChild("Wraps"))
local Emotes = require(Shared:WaitForChild("Emotes"))
local Classes = require(Shared:WaitForChild("Classes"))
local Crates = require(Shared:WaitForChild("Crates"))
local BoostDefs = require(Shared:WaitForChild("BoostDefs"))
local Rarity = require(Shared:WaitForChild("Rarity"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))

local ItemArt = {}

local function lighten(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), k)
end

local function block(
	parent: Instance,
	color: Color3,
	x: number,
	y: number,
	w: number,
	h: number,
	z: number,
	r: number?
): Frame
	local f = UI.frame({
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(w, h),
		ZIndex = z,
		Parent = parent,
	})
	if r then
		UI.new("UICorner", { CornerRadius = UDim.new(r, 0), Parent = f })
	end
	return f
end

local function glyph(parent: Instance, text: string, color: Color3, size: number, z: number, y: number?, h: number?)
	local l = UI.text({
		Text = text,
		Font = Theme.Fonts.display,
		TextScaled = true,
		TextColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, y or 0.5),
		Size = UDim2.fromScale(0.8, h or 0.42),
		ZIndex = z,
		Parent = parent,
	})
	UI.stroke(l, Color3.new(0, 0, 0), math.max(1, size // 40), 0.4)
	return l
end

-- A gun drawn from its look (or the generic silhouette).
local function weaponArt(root: Frame, id: string, size: number, z: number, tint: Color3?)
	local w = Weapons.ById[id]
	local look = w and w.look
	local body = tint or Rarity.color(if w then w.rarity else 1)
	if not look then
		local icon = UI.gunIcon(root, body, size)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		for _, c in icon:GetChildren() do
			if c:IsA("GuiObject") then
				c.ZIndex = z
			end
		end
		return
	end
	local accent = Color3.fromHex(look.color)
	local total = look.body + look.barrel + (if look.stock then 0.45 else 0)
	local unit = 0.86 / math.max(total, 1.2)
	local bodyW = look.body * unit
	local left = 0.5 - (total * unit) / 2
	local x = left
	if look.stock then
		block(root, accent, x + 0.45 * unit / 2, 0.5, 0.45 * unit, 0.16, z, 0.2)
		x += 0.45 * unit
	end
	block(root, body, x + bodyW / 2, 0.46, bodyW, 0.16, z + 1, 0.15)
	local barrelX = x + bodyW
	block(root, accent, barrelX + look.barrel * unit / 2, 0.44, look.barrel * unit, 0.07, z, 0.3)
	-- Grip under the back of the body.
	local grip = block(root, accent, x + bodyW * 0.28, 0.6, 0.09, 0.2, z, 0.2)
	grip.Rotation = -12
	if look.mag == "box" then
		block(root, accent, x + bodyW * 0.58, 0.6, 0.08, 0.18, z, 0.15)
	elseif look.mag == "drum" then
		block(root, accent, x + bodyW * 0.58, 0.6, 0.16, 0.16, z, 0.5)
	elseif look.mag == "tube" then
		block(root, accent, x + bodyW * 0.6 + look.barrel * unit * 0.3, 0.52, bodyW * 0.8, 0.05, z, 0.4)
	end
	if look.scope then
		block(root, Color3.fromHex("1A1A20"), x + bodyW * 0.55, 0.34, bodyW * 0.5, 0.07, z + 1, 0.4)
	end
end

-- A head with the mask's shape drawn flat.
local function maskArt(root: Frame, id: string, z: number)
	local m = Masks.ById[id]
	if not m then
		return
	end
	local main = Color3.fromHex(m.color)
	local accent = if m.accent then Color3.fromHex(m.accent) else main
	-- The head takes the mask color in-game, so the art does too.
	block(root, main, 0.5, 0.52, 0.62, 0.62, z, 0.5)
	local s = m.shape
	if s == "visor" or s == "mono" then
		block(root, if s == "mono" then main else main, 0.5, 0.46, 0.66, 0.16, z + 1, 0.4)
		if s == "mono" or m.accent then
			block(root, accent, 0.5, 0.46, 0.5, 0.05, z + 2, 0.5)
		end
	elseif s == "bandana" then
		block(root, main, 0.5, 0.64, 0.64, 0.24, z + 1, 0.3)
		if m.accent then
			for i = -1, 1 do
				local st = block(root, accent, 0.5 + i * 0.16, 0.64, 0.05, 0.24, z + 2)
				st.Rotation = 18
			end
		end
	elseif s == "goggles" then
		block(root, main, 0.5, 0.44, 0.66, 0.07, z + 1)
		for _, x in { 0.38, 0.62 } do
			block(root, accent, x, 0.44, 0.2, 0.2, z + 2, 0.5)
		end
	elseif s == "skull" then
		block(root, main, 0.5, 0.52, 0.5, 0.56, z + 1, 0.35)
		for _, x in { 0.4, 0.6 } do
			block(root, accent, x, 0.46, 0.12, 0.09, z + 2, 0.3)
		end
		for i = -2, 2 do
			block(root, accent, 0.5 + i * 0.05, 0.66, 0.025, 0.06, z + 2)
		end
	elseif s == "halfmask" then
		block(root, main, 0.5, 0.64, 0.56, 0.22, z + 1, 0.3)
		block(root, accent, 0.5, 0.64, 0.36, 0.035, z + 2)
	elseif s == "horns" then
		for _, side in { -1, 1 } do
			local h = block(root, accent, 0.5 + side * 0.26, 0.2, 0.09, 0.3, z + 1, 0.4)
			h.Rotation = -side * 30
		end
	elseif s == "helmet" then
		block(root, main, 0.5, 0.46, 0.72, 0.6, z + 1, 0.5)
		block(root, accent, 0.5, 0.5, 0.5, 0.12, z + 2, 0.4)
	elseif s == "crown" then
		block(root, accent, 0.5, 0.24, 0.5, 0.1, z + 1)
		for i = -2, 2 do
			local p = block(root, accent, 0.5 + i * 0.1, 0.16, 0.08, 0.08, z + 1)
			p.Rotation = 45
		end
	elseif s == "hood" then
		block(root, main, 0.5, 0.48, 0.76, 0.74, z - 1, 0.45)
		block(root, accent, 0.5, 0.6, 0.48, 0.14, z + 1, 0.3)
	end
end

local function wrapArt(root: Frame, id: string, z: number)
	local w = Wraps.ById[id]
	local c = if w then Color3.fromHex(w.color) else Theme.Colors.grey
	local sw = block(root, c, 0.5, 0.5, 0.62, 0.62, z, 0.18)
	sw.Rotation = 8
	UI.stroke(sw, Color3.new(1, 1, 1), 1, 0.6)
	local shine = block(root, Color3.new(1, 1, 1), 0.42, 0.4, 0.3, 0.06, z + 1, 0.5)
	shine.BackgroundTransparency = 0.6
	shine.Rotation = -30
	if w and w.material == "Neon" then
		UI.new("UIGradient", {
			Color = ColorSequence.new(c, Color3.fromHex("FFE08A")),
			Rotation = 45,
			Parent = sw,
		})
	elseif w and w.material == "Glass" then
		sw.BackgroundTransparency = 0.25
	end
end

local function emoteArt(root: Frame, id: string, z: number, size: number)
	local e = Emotes.ById[id]
	local c = Rarity.color(if e then e.rarity else 1)
	-- A stick figure mid-pose: head, body, raised arm.
	block(root, c, 0.5, 0.24, 0.18, 0.18, z, 0.5)
	block(root, c, 0.5, 0.5, 0.12, 0.32, z, 0.3)
	local arm = block(root, c, 0.62, 0.32, 0.07, 0.26, z, 0.4)
	arm.Rotation = 35
	local arm2 = block(root, c, 0.38, 0.46, 0.07, 0.24, z, 0.4)
	arm2.Rotation = -20
	block(root, c, 0.44, 0.78, 0.07, 0.26, z, 0.4)
	block(root, c, 0.56, 0.78, 0.07, 0.26, z, 0.4)
	glyph(root, if e and e.slot == "mvp" then "MVP" else "POS", Theme.Colors.white, size, z + 1, 0.9, 0.2)
end

local function classArt(root: Frame, id: string, z: number, size: number)
	local c = Classes.ById[id]
	local col = if c then Color3.fromHex(c.color) else Theme.Colors.grey
	local circle = block(root, col, 0.5, 0.5, 0.72, 0.72, z, 0.5)
	UI.stroke(circle, Color3.new(1, 1, 1), math.max(1, size // 30), 0.3)
	glyph(root, if c then c.glyph else "?", Theme.Colors.bg, size, z + 1, 0.5, 0.36)
end

local function goldArt(root: Frame, amount: number, z: number)
	local n = if amount >= 16000
		then 5
		elseif amount >= 5000 then 4
		elseif amount >= 2000 then 3
		elseif amount >= 700 then 2
		else 1
	local gold = Theme.Colors.gold
	for i = 1, n do
		local row = (i - 1) // 2
		local col = (i - 1) % 2
		local bar = block(
			root,
			gold,
			0.38 + col * 0.24 - (if n % 2 == 1 and i == n then -0.12 else 0),
			0.68 - row * 0.15,
			0.3,
			0.14,
			z + i,
			0.15
		)
		UI.stroke(bar, Color3.fromHex("8A5A12"), 1, 0.2)
		bar.Rotation = -6
	end
	glyph(root, "◆", Color3.fromHex("FFF1C4"), 40, z + 10, 0.24, 0.3)
end

local function tokenArt(root: Frame, amount: number, z: number, size: number)
	local stack = math.clamp(math.ceil(math.log(math.max(amount, 1) + 1, 3)), 1, 4)
	for i = stack, 1, -1 do
		local c = block(
			root,
			Color3.fromHex("3FD47A"),
			0.5 + (i - 1) * 0.06,
			0.52 - (i - 1) * 0.06,
			0.6,
			0.6,
			z + (stack - i),
			0.5
		)
		UI.stroke(c, Color3.fromHex("0F5A2C"), math.max(1, size // 30), 0)
	end
	glyph(root, "+", Theme.Colors.white, size, z + 6, 0.5, 0.5)
end

-- A crate box: body, lid band, trim, a lock plate.
local function crateArt(root: Frame, crateId: string, z: number, size: number)
	local c = Crates.ById[crateId]
	local body = if c then Color3.fromHex(c.color) else Theme.Colors.panel2
	local trim = if c then Color3.fromHex(c.trim) else Theme.Colors.gold
	local box = block(root, body, 0.5, 0.58, 0.74, 0.5, z, 0.1)
	UI.stroke(box, trim, math.max(1, size // 34), 0)
	block(root, lighten(body, 0.15), 0.5, 0.33, 0.8, 0.14, z + 1, 0.15)
	block(root, trim, 0.5, 0.42, 0.76, 0.04, z + 2)
	block(root, trim, 0.5, 0.54, 0.14, 0.16, z + 2, 0.2)
	glyph(root, if c and c.kind == "mask" then "MSK" else "ARM", Theme.Colors.white, size, z + 3, 0.72, 0.16)
end

local function boostArt(root: Frame, boostId: string, z: number, size: number)
	local b = BoostDefs.ById[boostId]
	local col = if b then Color3.fromHex(b.color) else Theme.Colors.amber
	local chip = block(root, Theme.Colors.panel, 0.5, 0.5, 0.74, 0.74, z, 0.22)
	UI.stroke(chip, col, math.max(2, size // 22), 0)
	local bolt = block(root, col, 0.5, 0.5, 0.16, 0.5, z + 1, 0.2)
	bolt.Rotation = 20
	glyph(root, if b then b.glyph else "BST", Theme.Colors.white, size, z + 2, 0.5, 0.3)
end

local function textBadge(root: Frame, text: string, bg: Color3, fg: Color3, z: number, size: number, round: number?)
	local b = block(root, bg, 0.5, 0.5, 0.74, 0.74, z, round or 0.22)
	UI.stroke(b, lighten(bg, 0.4), math.max(1, size // 30), 0.1)
	glyph(root, text, fg, size, z + 1, 0.5, 0.34)
end

-- Draws `r` into a new square frame of `size` px. `tint` overrides a weapon's body color (the crate reveal).
function ItemArt.draw(
	parent: Instance?,
	r: { kind: string, id: string?, amount: number?, sec: number? },
	size: number,
	z: number?,
	tint: Color3?
): Frame
	local zz = z or 5
	local root = UI.frame({
		Name = "ItemArt",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		ZIndex = zz,
	})
	local k, id, n = r.kind, r.id or "", r.amount or 0
	if k == "weapon" then
		weaponArt(root, id, size, zz, tint)
	elseif k == "mask" then
		maskArt(root, id, zz)
	elseif k == "wrap" then
		wrapArt(root, id, zz)
	elseif k == "emote" then
		emoteArt(root, id, zz, size)
	elseif k == "class" then
		classArt(root, id, zz, size)
	elseif k == "gold" then
		goldArt(root, n, zz)
	elseif k == "tokens" then
		tokenArt(root, n, zz, size)
	elseif k == "crate" then
		crateArt(root, id, zz, size)
	elseif k == "boost" then
		boostArt(root, id, zz, size)
	elseif k == "mastery" then
		textBadge(root, "MST", Color3.fromHex("6A4BC4"), Theme.Colors.white, zz, size, 0.5)
	elseif k == "xp" then
		textBadge(root, "XP", Theme.Colors.blue, Theme.Colors.white, zz, size, 0.5)
	elseif k == "passxp" then
		textBadge(root, "PXP", Color3.fromHex("E8792A"), Theme.Colors.white, zz, size, 0.5)
	elseif k == "cash" then
		textBadge(root, "$", Theme.Colors.cash, Theme.Colors.bg, zz, size, 0.25)
	elseif k == "pass" then
		textBadge(root, if n >= 2 then "P+" else "P", Color3.fromHex("E8792A"), Theme.Colors.white, zz, size, 0.5)
	elseif k == "passskip" then
		textBadge(root, ">>", Color3.fromHex("E8792A"), Theme.Colors.white, zz, size, 0.3)
	elseif k == "restock" then
		textBadge(root, "RST", Theme.Colors.panel2, Theme.Colors.gold, zz, size, 0.25)
	elseif k == "robux" then
		textBadge(root, "R$", Color3.fromHex("2FD46A"), Color3.fromHex("0E2A17"), zz, size, 0.3)
	else
		textBadge(root, "?", Theme.Colors.panel2, Theme.Colors.text, zz, size)
	end
	if parent then
		root.Parent = parent
	end
	return root
end

return ItemArt
