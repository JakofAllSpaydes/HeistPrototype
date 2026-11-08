--!strict
-- Shared pieces for the three tabs, styled to the reference: filter pills, dark section bars (OWNED /
-- UNOWNED), rarity-colored item tiles with the name on top, stat rows with "42 » 54" deltas, big flat action
-- buttons, and the two-column grid + detail layout. State reads without words (Round 18c): equipped is a big
-- green check over the art plus a green outline, selected is a white outline, unowned is dimmed, and an unowned
-- item's source is a 3-letter chip (CRT / VIP / EVT ...) with the full name in the detail column.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Prices = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Prices"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MasteryCopy = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MasteryCopy"))
local Rarity = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rarity"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Icons = require(Client:WaitForChild("UI"):WaitForChild("Icons"))
local ModelIcon = require(Client:WaitForChild("UI"):WaitForChild("ModelIcon"))

local MetaUI = {}

-- UI art pass: the item a gun / mask / wrap icon shows as a live model (UI/ModelIcon). `id` is the weapon, mask or
-- wrap id; a gun's wrap and rarity, and a showcase gun's archetype, ride along.
export type IconModel = {
	id: string,
	wrapId: string?,
	rarity: number?,
	archetype: string?,
	motion: string?, -- ModelIcon motion: "hover" (default) | "always" | "none"
}

MetaUI.Prices = Prices

MetaUI.Green = Color3.fromHex("2FD46A")
MetaUI.Pink = Color3.fromHex("E8347A")

export type TileOpts = {
	name: string,
	color: Color3, -- tile background (the rarity)
	owned: boolean,
	selected: boolean,
	equipped: boolean?, -- big check over the art + green outline
	icon: string, -- gun | mask | wrap | class
	iconColor: Color3?,
	iconModel: IconModel?, -- gun / mask / wrap: the item, drawn as a live 3D model icon
	glyph: string?, -- for icon = "class": a class id (its Icons.lua emblem) or the letter in the circle
	size: number, -- tile width; height = size x 1.18
	order: number,
	nameTag: string?, -- gold text after the name in the top bar ("LV 2" on an owned weapon)
	price: number?, -- unowned and sold for Gold: the price pill at the bottom
	source: string?, -- unowned and not sold for Gold: the saleType, drawn as a small 3-letter chip
	pop: string?, -- "select" (just tapped: the tile pops) | "equip" (just equipped: the check pops in)
}

function MetaUI.fmtGold(n: number): string
	return "◆ " .. UI.fmtNum(n)
end

-- Where an item comes from (brief 6: CRATE, BUNDLE, VIP, PASS, EVENT, plus MASTERY wraps): its color, the 3-letter
-- chip on an unowned tile, and the full name for the detail column.
MetaUI.SourceColors = {
	Crate = Theme.Colors.blue,
	Event = Theme.Colors.malus,
	Bundle = Color3.fromHex("E8792A"),
	VIP = Color3.fromHex("F2C14E"),
	Pass = Color3.fromHex("FF6A3D"),
	Mastery = Theme.Colors.gold,
} :: { [string]: Color3 }

local SOURCE_GLYPHS = { Crate = "CRT", Event = "EVT", Bundle = "BND", VIP = "VIP", Pass = "PAS", Mastery = "MST" }
local SOURCE_NAMES = {
	Direct = "SHOP",
	Crate = "CRATE",
	Event = "EVENT",
	Bundle = "BUNDLE",
	VIP = "VIP",
	Pass = "BATTLE PASS",
	Mastery = "MASTERY",
}

function MetaUI.sourceGlyph(saleType: string): string
	return SOURCE_GLYPHS[saleType] or string.upper(string.sub(saleType, 1, 3))
end

-- The full source line for a detail column: the crate's own name when one drops it ("MASK CRATE").
function MetaUI.sourceName(saleType: string, kind: string?, id: string?): string
	if saleType == "Crate" and kind and id then
		local Crates = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Crates")) :: any
		local cid = Crates.crateOf(kind, id)
		local crate = cid and Crates.ById[cid]
		if crate then
			return crate.name
		end
	end
	return SOURCE_NAMES[saleType] or string.upper(saleType)
end

function MetaUI.acquisition(saleType: string, price: number): (string, Color3)
	local c = MetaUI.SourceColors[saleType]
	if c then
		return string.upper(saleType), c
	end
	return MetaUI.fmtGold(price), Theme.Colors.cash
end

------------------------------------------------------------------ Juice
-- Hover grows the object in place (the PunchScale UIScale UI.punch uses, so a press punch and the hover share one
-- scale); it never moves away from the cursor.
-- Round 24aa: the favourite heart in a tile's top-right corner (solid red when hearted). onToggle runs on a tap.
function MetaUI.favHeart(tile: GuiObject, fav: boolean, onToggle: () -> ()): GuiButton
	local S = UI.S
	local heartBtn = UI.button({
		Name = "Favorite",
		Text = "",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(3), 0, S(3)),
		Size = UDim2.fromOffset(S(24), S(24)),
		ZIndex = 20,
		Parent = tile,
	})
	local glyph =
		Icons.fit(heartBtn, "heart", 0.8, if fav then Theme.Colors.red else Theme.Colors.white, Theme.Colors.white)
	if not fav then
		Icons.setTransparency(glyph, 0.55)
	end
	heartBtn.Activated:Connect(function()
		UI.punch(heartBtn, if fav then 0.85 else 1.35, 0.2)
		UI.sound(Theme.Sounds.toast, if fav then 1.0 else 1.5, 0.3)
		onToggle()
	end)
	return heartBtn
end

function MetaUI.hover(b: GuiButton, scale: number?)
	local to = scale or Config.MetaTileHoverScale
	local function sc(): UIScale
		local s = b:FindFirstChild("PunchScale") :: UIScale?
		if not s then
			s = UI.new("UIScale", { Name = "PunchScale", Parent = b })
		end
		return s :: UIScale
	end
	b.MouseEnter:Connect(function()
		UI.tween(sc(), { Scale = to }, 0.12)
	end)
	b.MouseLeave:Connect(function()
		UI.tween(sc(), { Scale = 1 }, 0.12)
	end)
end

-- Round 25: the success moment for an upgrade / unlock / buy, on the button just pressed (MetaUI.lastPress): a
-- white flash over the button, a ring that swells off it, two waves of sparks (the button's colour and gold) and
-- the upgrade confirm. Drawn on a full-screen layer in the button's ScreenGui, so the re-render that replaces the
-- button does not cut it short.
MetaUI.lastPress = nil :: { button: GuiObject, color: Color3, at: number }?
function MetaUI.successJuice(big: boolean?)
	local lp = MetaUI.lastPress
	MetaUI.lastPress = nil
	if not lp or os.clock() - lp.at > 3 then
		return
	end
	local b = lp.button
	local gui = b:FindFirstAncestorOfClass("ScreenGui")
	if not gui then
		return
	end
	local S = UI.S
	local layer = UI.frame({
		Name = "SuccessJuice",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 300,
		Parent = gui,
	})
	local origin = layer.AbsolutePosition
	local pos = b.AbsolutePosition - origin
	local size = b.AbsoluteSize
	local center = UDim2.fromOffset(pos.X + size.X / 2, pos.Y + size.Y / 2)
	-- Flash over the button.
	local flash = UI.frame({
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.15,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = center,
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = 301,
		Parent = layer,
	})
	UI.corner(flash, S(6))
	UI.tween(flash, { BackgroundTransparency = 1, Size = UDim2.fromOffset(size.X * 1.12, size.Y * 1.4) }, 0.35)
	-- A ring swelling off it.
	local ring = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = center,
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = 301,
		Parent = layer,
	})
	UI.corner(ring, S(8))
	local st = UI.stroke(ring, Theme.Colors.gold, S(4), 0)
	UI.tween(ring, { Size = UDim2.fromOffset(size.X + S(90), size.Y + S(70)) }, 0.5, Enum.EasingStyle.Quad)
	UI.tween(st, { Transparency = 1, Thickness = S(1) }, 0.5, Enum.EasingStyle.Quad)
	local Fx = require(Client:WaitForChild("Store"):WaitForChild("Fx")) :: any
	local n = if big then Config.MetaSuccessSparks * 1.5 else Config.MetaSuccessSparks
	Fx.burst(layer, center, lp.color, math.floor(n * 0.6), 302)
	task.delay(0.06, function()
		if layer.Parent then
			Fx.burst(layer, center, Theme.Colors.gold, math.floor(n * 0.5), 302)
		end
	end)
	UI.sound(Theme.Sounds.upgrade, 1, 0.5)
	task.delay(1.2, function()
		layer:Destroy()
	end)
end

-- A badge popping in (equip): from small to full with an overshoot, plus a few green sparks.
function MetaUI.popIn(obj: GuiObject, sparksIn: GuiObject?)
	UI.punch(obj, 0.2, 0.4)
	if sparksIn then
		local Fx = require(Client:WaitForChild("Store"):WaitForChild("Fx")) :: any
		Fx.burst(sparksIn, UDim2.fromScale(0.5, 0.45), MetaUI.Green, 10, 40)
	end
end

------------------------------------------------------------------ Glyphs drawn from frames (house style, no emoji)
-- Equipped: a green disc with a white check drawn from two bars and a dark rim.
function MetaUI.check(parent: Instance, size: number, z: number?): Frame
	local zi = z or 4
	local disc = UI.frame({
		Name = "Check",
		BackgroundColor3 = MetaUI.Green,
		Size = UDim2.fromOffset(size, size),
		ZIndex = zi,
		Parent = parent,
	})
	UI.corner(disc, size)
	UI.stroke(disc, Theme.Colors.bg, math.max(2, math.floor(size * 0.07)), 0)
	local thick = 0.14
	for _, arm in
		{
			{ len = 0.3, x = 0.34, y = 0.575, rot = 45 },
			{ len = 0.54, x = 0.565, y = 0.48, rot = -50 },
		}
	do
		local bar = UI.frame({
			BackgroundColor3 = Theme.Colors.white,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(arm.x, arm.y),
			Size = UDim2.fromScale(arm.len, thick),
			Rotation = arm.rot,
			ZIndex = zi + 1,
			Parent = disc,
		})
		UI.corner(bar, math.max(1, math.floor(size * thick / 2)))
	end
	return disc
end

-- Locked: a padlock (shackle ring + body + keyhole).
function MetaUI.lock(parent: Instance, size: number, color: Color3?, z: number?): Frame
	local zi = z or 3
	local c = color or Theme.Colors.grey
	local root =
		UI.frame({ Name = "Lock", BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), ZIndex = zi })
	local shackle = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.12),
		Size = UDim2.fromScale(0.42, 0.5),
		ZIndex = zi,
		Parent = root,
	})
	UI.corner(shackle, size)
	UI.stroke(shackle, c, math.max(2, math.floor(size * 0.1)), 0)
	local body = UI.frame({
		BackgroundColor3 = c,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.92),
		Size = UDim2.fromScale(0.64, 0.46),
		ZIndex = zi + 1,
		Parent = root,
	})
	UI.corner(body, math.max(2, math.floor(size * 0.1)))
	local hole = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromScale(0.2, 0.3),
		ZIndex = zi + 2,
		Parent = body,
	})
	UI.corner(hole, size)
	root.Parent = parent
	return root
end

-- Back: a left chevron from two bars.
function MetaUI.backArrow(parent: Instance, size: number, color: Color3?, z: number?): Frame
	local zi = z or 3
	local root =
		UI.frame({ Name = "Back", BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size), ZIndex = zi })
	for _, arm in { { y = 0.4, rot = -45 }, { y = 0.6, rot = 45 } } do
		local bar = UI.frame({
			BackgroundColor3 = color or Theme.Colors.white,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.47, arm.y),
			Size = UDim2.fromScale(0.34, 0.12),
			Rotation = arm.rot,
			ZIndex = zi,
			Parent = root,
		})
		UI.corner(bar, math.max(1, math.floor(size * 0.06)))
	end
	root.Parent = parent
	return root
end

-- The rarity on an art box: a dark chip top-left with the rarity name in its color.
function MetaUI.rarityChip(parent: GuiObject, rarity: number, z: number?): Frame
	local S = UI.S
	local color = Rarity.color(rarity)
	local chip, label = UI.pill(
		parent,
		string.upper(Rarity.name(rarity)),
		Theme.Colors.bg,
		color:Lerp(Theme.Colors.white, 0.2),
		S(22),
		S(12)
	)
	chip.Position = UDim2.fromOffset(S(8), S(8))
	chip.BackgroundTransparency = 0.15
	chip.ZIndex = z or 3
	label.ZIndex = (z or 3) + 1
	label.FontFace = Theme.Fonts.display
	UI.stroke(chip, color, S(1.5), 0.2)
	return chip
end

-- The detail well's equipped check. Round 18c: the side panel carries no check (the grid tile does); kept as a
-- no-op so the tabs' calls stay put.
function MetaUI.wellCheck(_well: GuiObject, _pop: boolean?) end

-- Round 24af: where a thing comes from when Gold can't buy it: a badge in the art box's top-right corner, the
-- source's icon over a small caps tag in the source's colour (CRATE / EVENT / BUNDLE / VIP / PASS).
local SOURCE_ICONS =
	{ Crate = "crate", Event = "event", Bundle = "gift", VIP = "vip", Pass = "event", Mastery = "power" }
local SOURCE_TAGS =
	{ Crate = "CRATE", Event = "EVENT", Bundle = "BUNDLE", VIP = "VIP", Pass = "PASS", Mastery = "MASTERY" }
function MetaUI.wellSource(well: GuiObject, saleType: string?): Frame?
	if not saleType or saleType == "Direct" then
		return nil
	end
	local S = UI.S
	local color = MetaUI.SourceColors[saleType] or Theme.Colors.grey
	local badge = UI.frame({
		Name = "SourceBadge",
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.15,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(8), 0, S(8)),
		Size = UDim2.fromOffset(S(52), S(54)),
		ZIndex = 6,
		Parent = well,
	})
	UI.corner(badge, S(4))
	UI.stroke(badge, color, S(1.5), 0.1)
	local holder = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(4)),
		Size = UDim2.fromOffset(S(30), S(30)),
		ZIndex = 7,
		Parent = badge,
	})
	Icons.fit(holder, SOURCE_ICONS[saleType] or "event", 0.95, color, Theme.Colors.bg)
	local tag = UI.text({
		Text = SOURCE_TAGS[saleType] or string.upper(saleType),
		FontFace = Theme.Fonts.display,
		TextScaled = true,
		TextColor3 = color,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(3)),
		Size = UDim2.new(1, -S(6), 0, S(14)),
		ZIndex = 7,
		Parent = badge,
	})
	tag:SetAttribute("FixedTextSize", true)
	UI.new("UITextSizeConstraint", { MaxTextSize = S(12), Parent = tag })
	return badge
end

-- Deep links for an unowned item that is not Gold-priced: VIEW CRATE / VIEW BUNDLE / VIEW PASS / VIEW VIP (EVENT ONLY
-- stays disabled). `kind` is the Rewards kind (weapon | mask | wrap | emote | class).
function MetaUI.sourceButton(scene: any, card: Instance, order: number, kind: string, id: string, saleType: string)
	local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	local Crates = require(Shared:WaitForChild("Crates")) :: any
	local Bundles = require(Shared:WaitForChild("Bundles")) :: any
	local PassSeason = require(Shared:WaitForChild("PassSeason")) :: any
	local ClientState = require(script.Parent.Parent:WaitForChild("ClientState")) :: any
	if saleType == "Crate" then
		MetaUI.button(card, order, "VIEW CRATE", "blue", function()
			ClientState.Juice:Fire("OpenStore", { tab = "CRATES", arg = { crate = Crates.crateOf(kind, id) } })
		end)
	elseif saleType == "Bundle" then
		local list = Bundles.containing(kind, id)
		MetaUI.button(card, order, "VIEW BUNDLE", "blue", function()
			ClientState.Juice:Fire("OpenStore", { tab = "FEATURED", arg = { bundle = list[1] } })
		end)
	elseif saleType == "VIP" then
		MetaUI.button(card, order, "VIEW VIP", "blue", function()
			ClientState.Juice:Fire("OpenStore", { tab = "VIP" })
		end)
	elseif saleType == "Pass" then
		local season, level = PassSeason.levelOf(kind, id)
		MetaUI.button(card, order, "VIEW PASS", "blue", function()
			ClientState.Juice:Fire("OpenPass", { level = level, season = season })
		end)
	else
		MetaUI.button(card, order, "EVENT ONLY", "disabled", nil)
	end
end

-- Icon drawn into a parent: gun silhouette, mask, wrap swatch or class circle. Returns the icon root.
function MetaUI.icon(
	kind: string,
	parent: Instance,
	size: number,
	color: Color3,
	glyph: string?,
	model: IconModel?
): GuiObject
	if model and (kind == "gun" or kind == "mask" or kind == "wrap") then
		-- UI art pass: the real model (a detail well's turns all the time). Round 25: grid tiles hold still (the
		-- hover sway re-ran on every re-render and read as blinking). The drawn shapes below stay as the fallback.
		local o: ModelIcon.Opts = {
			rarity = model.rarity,
			wrapId = model.wrapId,
			archetype = model.archetype,
			motion = model.motion,
		}
		if kind == "gun" then
			return ModelIcon.weapon(parent, model.id, size, o)
		elseif kind == "mask" then
			return ModelIcon.mask(parent, model.id, size, o)
		end
		return ModelIcon.wrap(parent, model.id, size, o)
	end
	if kind == "gun" then
		return UI.gunIcon(parent, color, size)
	end
	local f = UI.frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size) })
	if kind == "mask" then
		local head = UI.frame({
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.6, 0.6),
			Parent = f,
		})
		UI.corner(head, math.floor(size * 0.18))
		local band = UI.frame({
			BackgroundColor3 = Theme.Colors.bg,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.46),
			Size = UDim2.fromScale(0.64, 0.14),
			Parent = f,
		})
		UI.corner(band, 3)
	elseif kind == "wrap" then
		local swatch = UI.frame({
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.7, 0.7),
			Parent = f,
		})
		UI.corner(swatch, math.floor(size * 0.2))
	else
		local circle = UI.frame({
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.66, 0.66),
			Parent = f,
		})
		UI.corner(circle, 999)
		UI.stroke(circle, Theme.Colors.bg, 2, 0.3)
		if glyph and Icons.has(glyph) then
			-- A class id: its emblem (Icons.lua) in the circle, cut-outs in the circle's colour.
			Icons.fit(circle, glyph, 0.64, Theme.Colors.bg, color)
		else
			UI.text({
				Text = glyph or "?",
				FontFace = Theme.Fonts.display,
				TextSize = math.floor(size * 0.34),
				TextColor3 = Theme.Colors.bg,
				Size = UDim2.fromScale(1, 1),
				Parent = circle,
			})
		end
	end
	f.Parent = parent
	return f
end

-- Mastery (brief 5): a thin bar with tier pips along the bottom of a weapon tile or class pill, and a tooltip on
-- hover / tap listing the tier rewards with the earned ones ticked. `kind` "weapon" | "class".
function MetaUI.masteryBar(parent: GuiObject, kind: string, id: string, xp: number, inset: number?)
	local S = UI.S
	local tiers = if kind == "weapon" then Config.WeaponMasteryTiers else Config.ClassMasteryTiers
	local tier, into, need = MasteryCopy.progress(xp, tiers)
	local pad = inset or S(6)
	local track = UI.frame({
		Name = "Mastery",
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.2,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(4)),
		Size = UDim2.new(1, -pad * 2, 0, S(5)),
		ZIndex = 6,
		Parent = parent,
	})
	UI.corner(track, S(2))
	local frac = if need > 0 then math.clamp(into / need, 0, 1) else 1
	local fill = UI.frame({
		BackgroundColor3 = if tier >= #tiers then Theme.Colors.gold else Theme.Colors.cash,
		Size = UDim2.fromScale(frac, 1),
		ZIndex = 6,
		Parent = track,
	})
	UI.corner(fill, S(2))
	-- Tier pips above the bar's right end: lit gold once earned.
	for t = 1, #tiers do
		local pip = UI.frame({
			BackgroundColor3 = if tier >= t then Theme.Colors.gold else Theme.Colors.panel2,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -(#tiers - t) * S(7), 0, -S(2)),
			Size = UDim2.fromOffset(S(5), S(5)),
			Rotation = 45,
			ZIndex = 6,
			Parent = track,
		})
		UI.stroke(pip, Theme.Colors.black, 1, 0.4)
	end
	local lines = MasteryCopy.tooltip(kind, id, tier)
	local tip = UI.frame({
		Name = "MasteryTip",
		BackgroundColor3 = Theme.Colors.panel2,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, S(4)),
		Size = UDim2.fromOffset(S(280), S(16) * (#lines + 1) + S(8)),
		Visible = false,
		ZIndex = 30,
		Parent = parent,
	})
	UI.corner(tip, S(6))
	UI.stroke(tip, Theme.Colors.grey, S(1))
	UI.pad(tip, S(8), S(4), S(8), S(4))
	UI.list(tip, Enum.FillDirection.Vertical, 0)
	UI.text({
		Text = string.format(
			"MASTERY %s · %s",
			if tier > 0 then MasteryCopy.Roman[tier] else "0",
			if need > 0 then string.format("%d / %d", into, need) else "MAX"
		),
		FontFace = Theme.Fonts.display,
		TextSize = S(11),
		TextColor3 = Theme.Colors.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(16)),
		ZIndex = 31,
		Parent = tip,
	})
	for i, line in lines do
		UI.text({
			Text = line,
			TextSize = S(10),
			TextColor3 = if i <= tier then Theme.Colors.cash else Theme.Colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.new(1, 0, 0, S(16)),
			LayoutOrder = i,
			ZIndex = 31,
			Parent = tip,
		})
	end
	parent.MouseEnter:Connect(function()
		tip.Visible = true
	end)
	parent.MouseLeave:Connect(function()
		tip.Visible = false
	end)
end

-- The mastery panel in a detail column (weapons and classes share it). One line: `MASTERY II` with its tier
-- diamonds on the left, the next reward on the right (`NEXT · UNLOCK SKIN`); under it a full-width bar with the
-- progress written inside it (`15 / 800 KILLS`, or MAXED).
function MetaUI.masteryPanel(
	parent: Instance,
	order: number,
	tiers: { number },
	xp: number,
	unit: string,
	nextLabel: string?
): Frame
	local S = UI.S
	local tier, into, need = MasteryCopy.progress(xp, tiers)
	local pad = S(10)
	local row = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.new(1, 0, 0, S(54)),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.corner(row, S(6))
	-- Top line.
	local line = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(pad, S(6)),
		Size = UDim2.new(1, -pad * 2, 0, S(20)),
		Parent = row,
	})
	local left = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(0.55, 0, 1, 0),
		Parent = line,
	})
	UI.list(left, Enum.FillDirection.Horizontal, S(8), Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	UI.text({
		Text = if tier > 0 then "MASTERY " .. MasteryCopy.Roman[tier] else "MASTERY",
		FontFace = Theme.Fonts.display,
		TextSize = S(15),
		TextColor3 = if tier > 0 then Theme.Colors.gold else Theme.Colors.textDim,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 1,
		Parent = left,
	})
	local pips = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(S(12) * #tiers, S(12)),
		LayoutOrder = 2,
		Parent = left,
	})
	for t = 1, #tiers do
		local d = UI.frame({
			BackgroundColor3 = if tier >= t then Theme.Colors.gold else Theme.Colors.panel2,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, S(12) * (t - 0.5), 0.5, 0),
			Size = UDim2.fromOffset(S(7), S(7)),
			Rotation = 45,
			Parent = pips,
		})
		UI.stroke(d, Theme.Colors.black, 1, 0.3)
	end
	if need > 0 and nextLabel then
		UI.text({
			Text = "NEXT · " .. nextLabel,
			FontFace = Theme.Fonts.body,
			TextSize = S(10),
			TextColor3 = Theme.Colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0.45, 0, 1, 0),
			Parent = line,
		})
	end
	-- The bar with the count inside it.
	local barH = S(16)
	local track = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, pad, 1, -S(8)),
		Size = UDim2.new(1, -pad * 2, 0, barH),
		Parent = row,
	})
	UI.corner(track, barH / 2)
	local fill = UI.frame({
		BackgroundColor3 = if need > 0 then MetaUI.Green else Theme.Colors.gold,
		Size = UDim2.fromScale(if need > 0 then math.clamp(into / need, 0, 1) else 1, 1),
		Parent = track,
	})
	UI.corner(fill, barH / 2)
	local count = UI.text({
		Text = if need > 0 then string.format("%s / %s %s", UI.fmtInt(into), UI.fmtInt(need), unit) else "MAXED",
		FontFace = Theme.Fonts.display,
		TextSize = S(11),
		TextColor3 = Theme.Colors.white,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = track,
	})
	UI.stroke(count, Theme.Colors.black, S(1.5), 0.2)
	return row
end

-- A grid tile: rarity block, name on top, icon in the middle. Owned tiles carry nothing else at the bottom (the
-- weapon tab adds its mastery bar there); unowned tiles show the Gold price or a small source chip and dim.
-- The tile's outline for its state: green when equipped (the strongest state), white when selected, a faint dark
-- edge otherwise; selected and equipped adds a white ring inside the green one. Round 25: callable on a live tile,
-- so a tap re-styles two tiles instead of rebuilding the grid.
function MetaUI.tileState(b: GuiObject, selected: boolean, equipped: boolean)
	local S = UI.S
	local stroke = b:FindFirstChild("TileOutline") :: UIStroke?
	if not stroke then
		stroke = UI.stroke(b, Theme.Colors.black, S(1.5), 0.4) :: any;
		(stroke :: UIStroke).Name = "TileOutline"
	end
	local st = stroke :: UIStroke
	st.Color = if equipped then MetaUI.Green elseif selected then Theme.Colors.white else Theme.Colors.black
	-- (UI.stroke caps text-button outlines at Theme.TextStrokeMax: same look as the tile always had)
	st.Thickness =
		math.min(S(if equipped then 3.5 elseif selected then 3 else 1.5), math.max(1, S(Theme.TextStrokeMax)))
	st.Transparency = if equipped or selected then 0 else 0.4
	local ring = b:FindFirstChild("SelectRing")
	if equipped and selected and not ring then
		local r = UI.frame({
			Name = "SelectRing",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -S(5), 1, -S(5)),
			ZIndex = 5,
			Parent = b,
		})
		UI.corner(r, S(6))
		UI.stroke(r, Theme.Colors.white, S(2), 0)
	elseif ring and not (equipped and selected) then
		ring:Destroy()
	end
end

function MetaUI.tile(parent: Instance, o: TileOpts): TextButton
	local S = UI.S
	local w = o.size
	local h = math.floor(w * 1.18)
	local b = UI.button({
		Name = o.name,
		Text = "",
		BackgroundColor3 = o.color,
		BackgroundTransparency = if o.owned then 0 else 0.45,
		Size = UDim2.fromOffset(w, h),
		LayoutOrder = o.order,
		ClipsDescendants = true,
		Parent = parent,
	})
	UI.corner(b, S(8))
	MetaUI.tileState(b, o.selected == true, o.equipped == true)
	-- A soft dark band under the name so it reads on every rarity color.
	local band = UI.frame({
		BackgroundColor3 = Theme.Colors.black,
		BackgroundTransparency = 0.78,
		Size = UDim2.new(1, 0, 0, S(22)),
		Parent = b,
	})
	band.BorderSizePixel = 0
	UI.text({
		Text = if o.nameTag then string.format('%s  <font color="#E8B64C">%s</font>', o.name, o.nameTag) else o.name,
		RichText = o.nameTag ~= nil,
		FontFace = Theme.Fonts.body,
		TextSize = S(12),
		TextColor3 = if o.owned then Theme.Colors.white else Theme.Colors.text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(6), S(3)),
		Size = UDim2.new(1, -S(12), 0, S(16)),
		ZIndex = 2,
		Parent = b,
	})
	local ic = MetaUI.icon(o.icon, b, math.floor(w * 0.74), o.iconColor or Theme.Colors.white, o.glyph, o.iconModel)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.new(0.5, 0, 0.5, S(3))
	if ic:IsA("ViewportFrame") then
		-- A model icon: guns get the tile's width (inside its padding), same height as the old square.
		if o.icon ~= "mask" then
			ic.Size = UDim2.fromOffset(w - S(10), math.floor(w * 0.74))
		end
		if not o.owned then
			ModelIcon.setState(ic, "dim")
		end
	elseif not o.owned then
		for _, c in ic:GetDescendants() do
			if c:IsA("Frame") and c.BackgroundTransparency < 1 then -- holders and outline rings stay clear
				c.BackgroundTransparency = 0.35
			end
		end
	end
	if not o.owned and o.source and o.source ~= "Direct" then
		-- Where it comes from, without words: a small 3-letter chip in the source's color.
		local c = MetaUI.SourceColors[o.source] or Theme.Colors.grey
		local chip, label = UI.pill(b, MetaUI.sourceGlyph(o.source), c, Theme.Colors.bg, S(16), S(10))
		chip.AnchorPoint = Vector2.new(1, 1)
		chip.Position = UDim2.new(1, -S(5), 1, -S(5))
		chip.ZIndex = 3
		label.ZIndex = 3
		label.FontFace = Theme.Fonts.display
	elseif not o.owned and o.price then
		local pill, label = UI.pill(b, MetaUI.fmtGold(o.price), Theme.Colors.bg, Theme.Colors.cash, S(20), S(11))
		pill.AnchorPoint = Vector2.new(0.5, 1)
		pill.Position = UDim2.new(0.5, 0, 1, -S(6))
		pill.BackgroundTransparency = 0.15
		pill.ZIndex = 3
		label.ZIndex = 3
		label.FontFace = Theme.Fonts.display
	end
	if o.equipped then
		-- The big check, centered on the art (Round 18c).
		local size = math.floor(w * Config.MetaEquipBadgeShare)
		local check = MetaUI.check(b, size, 6)
		check.AnchorPoint = Vector2.new(0.5, 0.5)
		check.Position = UDim2.new(0.5, 0, 0.5, S(2))
		if o.pop == "equip" then
			MetaUI.popIn(check, b)
		end
	end
	if o.pop == "select" then
		UI.punch(b, Config.MetaSelectPopScale, 0.25)
	end
	MetaUI.hover(b)
	return b
end

-- Section bar: "OWNED" / "UNOWNED" on a dark strip, with the count on the right.
function MetaUI.header(parent: Instance, order: number, text: string, count: number?)
	local S = UI.S
	local bar = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.new(1, -S(8), 0, S(26)),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.corner(bar, S(4))
	UI.text({
		Text = text,
		FontFace = Theme.Fonts.body,
		TextSize = S(14),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(10), 0),
		Size = UDim2.new(1, -S(10), 1, 0),
		Parent = bar,
	})
	if count then
		UI.text({
			Text = tostring(count),
			FontFace = Theme.Fonts.display,
			TextSize = S(13),
			TextColor3 = Theme.Colors.grey,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -S(10), 0, 0),
			Size = UDim2.new(0, S(40), 1, 0),
			Parent = bar,
		})
	end
end

-- A wrapping row of tiles (a little padding so a hovered tile's growth and outline never clip).
function MetaUI.row(parent: Instance, order: number, tileW: number, perRow: number): Frame
	local S = UI.S
	local f = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -S(8), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = parent,
	})
	UI.pad(f, S(4), S(4), S(4), S(4))
	UI.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(tileW, math.floor(tileW * 1.18)),
		CellPadding = UDim2.fromOffset(S(8), S(8)),
		FillDirectionMaxCells = perRow,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = f,
	})
	return f
end

-- Tile width for `perRow` tiles across a grid's width (row padding and the scroll bar taken off).
function MetaUI.tileWidth(grid: GuiObject, perRow: number): number
	local S = UI.S
	local w = math.floor((grid.AbsoluteSize.X - S(8) * (perRow - 1) - S(24)) / perRow)
	return math.clamp(w, S(64), S(110))
end

-- Stat row: label left, "current » next" right, next in green when it differs.
function MetaUI.statRow(parent: Instance, order: number, label: string, current: string, nextValue: string?): Frame
	local S = UI.S
	local row = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.new(1, 0, 0, S(28)),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.corner(row, S(4))
	UI.text({
		Text = label,
		FontFace = Theme.Fonts.body,
		TextSize = S(13),
		TextColor3 = Theme.Colors.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(S(10), 0),
		Size = UDim2.new(0.45, 0, 1, 0),
		Parent = row,
	})
	local value = UI.text({
		Text = current,
		FontFace = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S(10), 0, 0),
		Size = UDim2.new(0.55, 0, 1, 0),
		RichText = true,
		Parent = row,
	})
	if nextValue and nextValue ~= current then
		value.Text = string.format('%s <font color="#2FD46A">» %s</font>', current, nextValue)
	end
	return row
end

-- The level header over the stat rows: a gold LV badge, and what the next upgrade takes it to.
function MetaUI.levelRow(parent: Instance, order: number, level: number, showNext: boolean): Frame
	local S = UI.S
	local row = UI.frame({
		BackgroundColor3 = Theme.Colors.panel2,
		Size = UDim2.new(1, 0, 0, S(30)),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.corner(row, S(4))
	UI.stroke(row, Theme.Colors.gold, S(1), 0.6)
	local badge, label = UI.pill(row, string.format("LV %d", level), Theme.Colors.gold, Theme.Colors.bg, S(22), S(14))
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position = UDim2.new(0, S(5), 0.5, 0)
	label.FontFace = Theme.Fonts.display
	if showNext then
		UI.text({
			Text = string.format('NEXT <font color="#2FD46A">» LV %d</font>', level + 1),
			RichText = true,
			FontFace = Theme.Fonts.display,
			TextSize = S(13),
			TextColor3 = Theme.Colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -S(10), 0, 0),
			Size = UDim2.new(0.6, 0, 1, 0),
			Parent = row,
		})
	end
	return row
end

-- Big flat action button. kind: green | pink | blue | gold | disabled.
function MetaUI.button(parent: Instance, order: number, text: string, kind: string, onPress: (() -> ())?): TextButton
	local S = UI.S
	local enabled = kind ~= "disabled"
	local bg = if kind == "green"
		then MetaUI.Green
		elseif kind == "pink" then MetaUI.Pink
		elseif kind == "blue" then Theme.Colors.blue
		elseif kind == "gold" then Theme.Colors.gold
		else Theme.Colors.panel2
	local fg = if kind == "green" or kind == "gold"
		then Theme.Colors.bg
		elseif enabled then Theme.Colors.white
		else Theme.Colors.grey
	local b = UI.button({
		Text = text,
		FontFace = Theme.Fonts.body,
		TextSize = S(17),
		TextColor3 = fg,
		BackgroundColor3 = bg,
		Size = UDim2.new(1, 0, 0, S(44)),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.corner(b, S(6))
	if enabled then
		UI.new("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205)),
			Rotation = 90,
			Parent = b,
		})
	end
	if enabled and onPress then
		b.Activated:Connect(function()
			UI.punch(b, 0.95, 0.15)
			-- Round 25: remembered so a successful upgrade / unlock bursts from where it was pressed.
			MetaUI.lastPress = { button = b, color = bg, at = os.clock() }
			onPress()
		end)
		MetaUI.hover(b, 1.03)
	end
	return b
end

-- The equipped state where the EQUIP button was: the disabled EQUIPPED button (Round 18c: as before).
function MetaUI.equippedButton(parent: Instance, order: number): TextButton
	return MetaUI.button(parent, order, "EQUIPPED", "disabled", nil)
end

-- A disabled slab with a padlock (an ability of a class you don't own yet).
function MetaUI.lockedButton(parent: Instance, order: number): TextButton
	local S = UI.S
	local b = MetaUI.button(parent, order, "", "disabled", nil)
	local l = MetaUI.lock(b, S(26), Theme.Colors.grey, 3)
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, 0.5)
	return b
end

-- Every refresh rebuilds the grid, so the scroll offset is remembered per `scrollKey` (one per tab / category)
-- and put back once the new canvas has its size. Only the player's own scrolling updates the memory.
local scrollMemory: { [string]: number } = {}

-- Two-column layout: scrolling grid left, detail card (vertical list) right. The detail column scrolls too when a
-- short screen can't fit it (mobile), with the bar inset so nothing sits under it.
function MetaUI.columns(panel: Frame, rightW: number, topOffset: number?, scrollKey: string?): (ScrollingFrame, any)
	local S = UI.S
	local y = topOffset or 0
	local left = UI.new("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, -rightW - S(12), 1, -y),
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = S(6),
		ScrollBarImageColor3 = Theme.Colors.grey,
		Parent = panel,
	}) :: ScrollingFrame
	if scrollKey then
		local armed = false
		left:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			if armed then
				scrollMemory[scrollKey] = left.CanvasPosition.Y
			end
		end)
		local remembered = scrollMemory[scrollKey] or 0
		-- The canvas only knows its height after the tiles land; restore on the next frame and once more a
		-- beat later, then start recording.
		task.defer(function()
			if left.Parent then
				left.CanvasPosition = Vector2.new(0, remembered)
			end
			task.delay(0.05, function()
				if left.Parent then
					left.CanvasPosition = Vector2.new(0, remembered)
					armed = true
				end
			end)
		end)
	end
	local right = UI.new("ScrollingFrame", {
		Name = "Detail",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, y),
		Size = UDim2.new(0, rightW, 1, -y),
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		ScrollBarThickness = S(4),
		ScrollBarImageColor3 = Theme.Colors.grey,
		Parent = panel,
	})
	UI.list(right, Enum.FillDirection.Vertical, S(8))
	return left, right
end

-- The detail card's image well: a rarity block with a big icon. Returns the icon (its Parent is the well).
function MetaUI.well(
	card: Frame,
	order: number,
	color: Color3,
	icon: string,
	glyph: string?,
	iconColor: Color3?,
	iconModel: IconModel? -- gun / mask / wrap: the item as a live model, turning slowly in the well
): GuiObject
	local S = UI.S
	local well = UI.frame({
		Name = "Well",
		BackgroundColor3 = color,
		Size = UDim2.new(1, 0, 0, S(150)),
		LayoutOrder = order,
		ClipsDescendants = true,
		Parent = card,
	})
	UI.corner(well, S(8))
	UI.stroke(well, Theme.Colors.white, S(1.5), 0.6)
	-- A light sheen top to bottom so the block reads as a lit box.
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170)),
		Rotation = 90,
		Parent = well,
	})
	local model: IconModel? = nil
	if iconModel then
		model = table.clone(iconModel);
		(model :: IconModel).motion = iconModel.motion or "always"
	end
	local ic = MetaUI.icon(icon, well, S(130), iconColor or Theme.Colors.white, glyph, model)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, 0.52)
	if ic:IsA("ViewportFrame") then
		-- A model fills the well (inside a small margin) rather than a square in its middle.
		ic.Size = UDim2.new(1, -S(16), 1, -S(12))
	end
	return ic
end

-- Detail name and the small line under it.
function MetaUI.heading(card: Frame, order: number, name: string, sub: string, subColor: Color3?)
	-- Round 18c: the sub line sits beside the name on one row ("Skorpion  SMG · FULL-AUTO").
	local S = UI.S
	local row = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(36)),
		LayoutOrder = order,
		ClipsDescendants = true,
		Parent = card,
	})
	UI.list(row, Enum.FillDirection.Horizontal, S(10), Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom)
	-- Round 25: the name in the house display face (condensed caps, like MASTERY III and the HUD's gun name),
	-- not the mixed-case body face.
	UI.text({
		Text = string.upper(name),
		FontFace = Theme.Fonts.display,
		TextSize = S(28),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(0, S(34)),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
		Parent = row,
	})
	UI.text({
		Text = sub,
		FontFace = Theme.Fonts.display,
		TextSize = S(13),
		TextColor3 = subColor or Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(0, S(22)),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = row,
	})
end

-- Filter pill row (ALL · AR · SMG …). `onPick(id)` fires on press.
function MetaUI.pills(
	parent: Instance,
	entries: { { id: string, name: string, disabled: boolean? } },
	selected: string,
	onPick: (string) -> ()
): Frame
	local S = UI.S
	local row = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(34)),
		Parent = parent,
	})
	UI.list(row, Enum.FillDirection.Horizontal, S(6))
	for i, e in entries do
		local on = e.id == selected
		local b = UI.button({
			Text = e.name,
			FontFace = Theme.Fonts.body,
			TextSize = S(12),
			TextColor3 = if e.disabled then Theme.Colors.grey else Theme.Colors.white,
			BackgroundColor3 = if on then Theme.Colors.blue else Theme.Colors.panel,
			Size = UDim2.fromOffset(0, S(34)),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = i,
			Parent = row,
		})
		UI.corner(b, S(4))
		UI.pad(b, S(14), 0, S(14), 0)
		if on then
			UI.stroke(b, Theme.Colors.white, S(1.5), 0.5)
		end
		if not e.disabled then
			b.Activated:Connect(function()
				UI.punch(b, 0.94, 0.15)
				onPick(e.id)
			end)
			MetaUI.hover(b, 1.04)
		end
	end
	return row
end

-- Round 24x: filter tiles with an icon (a 3D gun, or a glyph) over a small label. Every tile takes an equal share of
-- the row, so any number of categories fits without scrolling and they all read the same size.
-- entries: { id, name, weaponId? } (no weaponId: the "all" grid glyph).
function MetaUI.iconPills(
	parent: Instance,
	entries: { { id: string, name: string, weaponId: string?, glyph: string? } },
	selected: string,
	onPick: (string) -> (),
	height: number
): Frame
	local S = UI.S
	local n = #entries
	local gap = S(6)
	local row = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height),
		Parent = parent,
	})
	UI.list(row, Enum.FillDirection.Horizontal, gap)
	for i, e in entries do
		local on = e.id == selected
		local b = UI.button({
			Name = e.id,
			Text = "",
			BackgroundColor3 = if on then Theme.Colors.blue else Theme.Colors.panel,
			Size = UDim2.new(1 / n, -gap * (n - 1) / n, 1, 0),
			LayoutOrder = i,
			Parent = row,
		})
		UI.corner(b, S(4))
		if on then
			UI.stroke(b, Theme.Colors.white, S(1.5), 0.5)
		end
		local labelH = math.floor(height * 0.26)
		local iconArea = UI.frame({
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, S(2)),
			Size = UDim2.new(1, 0, 1, -labelH - S(2)),
			Parent = b,
		})
		if e.glyph then
			Icons.fit(iconArea, e.glyph, 0.7, Theme.Colors.red, Theme.Colors.white)
		elseif e.weaponId then
			local vp = ModelIcon.weapon(iconArea, e.weaponId, UDim2.fromScale(1, 1), {}) -- Round 25: still (tiny, not worth the motion)
			vp.BackgroundTransparency = 1
		else
			-- ALL: a 2x2 grid of squares.
			local sq = math.floor((height - labelH) * 0.24)
			local grid = UI.frame({
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(sq * 2 + S(4), sq * 2 + S(4)),
				Parent = iconArea,
			})
			for k = 0, 3 do
				local c = UI.frame({
					BackgroundColor3 = Theme.Colors.white,
					Position = UDim2.fromOffset((k % 2) * (sq + S(4)), math.floor(k / 2) * (sq + S(4))),
					Size = UDim2.fromOffset(sq, sq),
					Parent = grid,
				})
				UI.corner(c, S(2))
			end
		end
		local label = UI.text({
			Text = e.name,
			FontFace = Theme.Fonts.display,
			TextScaled = true,
			TextColor3 = Theme.Colors.white,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -S(3)),
			Size = UDim2.new(1, -S(6), 0, labelH),
			Parent = b,
		})
		label:SetAttribute("FixedTextSize", true)
		UI.new("UITextSizeConstraint", { MaxTextSize = S(13), MinTextSize = 6, Parent = label })
		b.Activated:Connect(function()
			UI.punch(b, 0.94, 0.15)
			onPick(e.id)
		end)
		MetaUI.hover(b, 1.04)
	end
	return row
end

return MetaUI
