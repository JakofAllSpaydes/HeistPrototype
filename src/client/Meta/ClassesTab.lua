--!strict
-- Classes tab: the category pills ARE the classes (icon + name; a green check on the equipped one, a padlock on
-- unowned); below them the selected class's three ability rows, sized to fill the panel (big icon well with the
-- in-match $ price, name and hotkey, description, stats as current » next, UPGRADE), and the detail column on the
-- right (class well with the equipped check or a padlock, name, the kit, mastery, EQUIP or UNLOCK). The preview
-- plays the class idle.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(Shared:WaitForChild("Classes"))
local AbilityGrowth = require(Shared:WaitForChild("AbilityGrowth"))
local Prices = require(Shared:WaitForChild("Prices"))
local Config = require(Shared:WaitForChild("Config"))
local MasteryCopy = require(Shared:WaitForChild("MasteryCopy"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local Icons = require(Client:WaitForChild("UI"):WaitForChild("Icons"))
local MetaUI = require(script.Parent:WaitForChild("MetaUI"))
local InputGlyphs = require(Client:WaitForChild("InputGlyphs"))

local ClassesTab = {}

local selected: string? = nil
local lastIdle: string? = nil
-- One-shot juice: the pill just tapped pops; the class just equipped pops its check in once the profile shows it.
local popSelect: string? = nil
local popEquip: string? = nil
local popEquipAt = 0

local function equipPopFor(id: string): boolean
	return popEquip == id and os.clock() - popEquipAt < 3
end

local function markEquipPop(id: string)
	popEquip = id
	popEquipAt = os.clock()
end

local function fmtVar(v: Classes.Var, value: number): string
	local s = if value == math.floor(value) then string.format("%d", value) else string.format("%.1f", value)
	return s .. v.unit
end

-- The four classes plus the FUTURE pill share the row.
local PILL_COUNT = #Classes.List + 1

-- FUTURE: a greyed pill at the end of the row, so the four read as the first of more. Pressing it toasts.
local function futurePill(parent: Instance, order: number, onPick: () -> ()): TextButton
	local S = UI.S
	local b = UI.button({
		Text = "",
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = 0.4,
		Size = UDim2.new(1 / PILL_COUNT, -S(5), 0, S(48)),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.corner(b, S(6))
	MetaUI.hover(b)
	local circle = UI.frame({
		BackgroundColor3 = Theme.Colors.panel2,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, S(8), 0.5, 0),
		Size = UDim2.fromOffset(S(32), S(32)),
		Parent = b,
	})
	UI.corner(circle, 999)
	UI.text({
		Text = "+",
		FontFace = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.grey,
		Size = UDim2.fromScale(1, 1),
		Parent = circle,
	})
	UI.text({
		Text = "FUTURE",
		FontFace = Theme.Fonts.body,
		TextSize = S(13),
		TextColor3 = Theme.Colors.grey,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(S(48), 0),
		Size = UDim2.new(1, -S(52), 1, 0),
		Parent = b,
	})
	b.Activated:Connect(function()
		UI.punch(b, 0.95, 0.15)
		onPick()
	end)
	return b
end

-- Class mastery in the detail column: `MASTERY II` with the waves to the next tier and a bar, then one card per
-- tier (numeral badge, passive name, what it does); earned tiers are gold, the next one is outlined green.
local function masteryBlock(parent: Instance, order: number, classId: string, xp: number)
	local S = UI.S
	local tiers = Config.ClassMasteryTiers
	local tier = MasteryCopy.progress(xp, tiers)
	MetaUI.masteryPanel(parent, order, tiers, xp, "WAVES", nil) -- the next tier is the green-outlined card below
	for t = 1, #tiers do
		local earned = tier >= t
		local isNext = t == tier + 1
		local name, line = MasteryCopy.classReward(classId, t)
		local row = UI.frame({
			BackgroundColor3 = Theme.Colors.panel,
			BackgroundTransparency = if earned or isNext then 0 else 0.4,
			Size = UDim2.new(1, 0, 0, S(50)),
			LayoutOrder = order + t,
			Parent = parent,
		})
		UI.corner(row, S(6))
		UI.stroke(
			row,
			if earned then Theme.Colors.gold elseif isNext then MetaUI.Green else Theme.Colors.black,
			S(if earned or isNext then 2 else 1),
			if earned or isNext then 0 else 0.5
		)
		local badge = UI.frame({
			BackgroundColor3 = if earned then Theme.Colors.gold else Theme.Colors.panel2,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, S(8), 0.5, 0),
			Size = UDim2.fromOffset(S(32), S(32)),
			Parent = row,
		})
		UI.corner(badge, S(6))
		UI.text({
			Text = MasteryCopy.Roman[t],
			FontFace = Theme.Fonts.display,
			TextSize = S(16),
			TextColor3 = if earned then Theme.Colors.bg else Theme.Colors.textDim,
			Size = UDim2.fromScale(1, 1),
			Parent = badge,
		})
		local textX = S(48)
		UI.text({
			Text = name,
			FontFace = Theme.Fonts.display,
			TextSize = S(13),
			TextColor3 = if earned then Theme.Colors.white else Theme.Colors.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(textX, S(5)),
			Size = UDim2.new(1, -textX - S(6), 0, S(16)),
			Parent = row,
		})
		UI.text({
			Text = line,
			FontFace = Theme.Fonts.body,
			TextSize = S(10),
			TextColor3 = if earned then Theme.Colors.text else Theme.Colors.grey,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			Position = UDim2.fromOffset(textX, S(22)),
			Size = UDim2.new(1, -textX - S(6), 0, S(26)),
			Parent = row,
		})
	end
end

-- Class pill: colored circle with the initial and the name; blue when selected. State without words (Round 18c):
-- equipped = a green check on the circle and a green outline, unowned = a grey circle and a small padlock.
local function classPill(
	parent: Instance,
	order: number,
	c: Classes.Class,
	own: boolean,
	on: boolean,
	equipped: boolean,
	pop: string?, -- "select" | "equip"
	onPick: () -> ()
): TextButton
	local S = UI.S
	local b = UI.button({
		Text = "",
		BackgroundColor3 = if on then Theme.Colors.blue else Theme.Colors.panel,
		BackgroundTransparency = if own or on then 0 else 0.25,
		Size = UDim2.new(1 / PILL_COUNT, -S(5), 0, S(48)),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.corner(b, S(6))
	UI.stroke(
		b,
		if equipped then MetaUI.Green elseif on then Theme.Colors.white else Theme.Colors.black,
		S(if equipped then 3 elseif on then 2 else 1),
		if equipped or on then 0 else 0.5
	)
	local circle = UI.frame({
		BackgroundColor3 = if own then Color3.fromHex(c.color) else Theme.Colors.panel2,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, S(8), 0.5, 0),
		Size = UDim2.fromOffset(S(32), S(32)),
		Parent = b,
	})
	UI.corner(circle, 999)
	UI.stroke(circle, Theme.Colors.bg, S(1.5), 0.3)
	-- The class emblem (Icons.lua, keyed by class id); its cut-outs take the circle's colour.
	Icons.fit(
		circle,
		c.id,
		0.64,
		if own then Theme.Colors.bg else Theme.Colors.grey,
		if own then Color3.fromHex(c.color) else Theme.Colors.panel2,
		c.glyph
	)
	if equipped then
		local check = MetaUI.check(circle, S(18), 4)
		check.AnchorPoint = Vector2.new(0.5, 0.5)
		check.Position = UDim2.new(1, -S(2), 0, S(2))
		if pop == "equip" then
			MetaUI.popIn(check, nil)
		end
	elseif not own then
		local lock = MetaUI.lock(circle, S(16), Theme.Colors.white, 4)
		lock.AnchorPoint = Vector2.new(0.5, 0.5)
		lock.Position = UDim2.new(1, -S(2), 1, -S(3))
	end
	UI.text({
		Text = string.upper(c.name),
		FontFace = Theme.Fonts.body,
		TextSize = S(13),
		TextColor3 = if own then Theme.Colors.white else Theme.Colors.grey,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(S(48), 0),
		Size = UDim2.new(1, -S(52), 1, 0),
		Parent = b,
	})
	b.Activated:Connect(function()
		UI.punch(b, 0.95, 0.15)
		onPick()
	end)
	if pop == "select" then
		UI.punch(b, Config.MetaSelectPopScale, 0.25)
	end
	MetaUI.hover(b)
	return b
end

-- One ability row at a fixed height: icon well left, name / description / stats in the middle, LV and
-- UPGRADE on the right.
local function abilityRow(
	scene: any,
	parent: Instance,
	order: number,
	rowH: number,
	class: Classes.Class,
	a: Classes.Ability,
	isOwned: boolean
)
	local S = UI.S
	local profile = scene.profile()
	local level = if profile then (profile.abilities[a.id] or 0) else 0
	local row = UI.frame({
		BackgroundColor3 = Theme.Colors.panel,
		Size = UDim2.new(1, -S(8), 0, rowH),
		LayoutOrder = order,
		Parent = parent,
	})
	UI.corner(row, S(8))
	UI.stroke(row, Theme.Colors.black, S(1), 0.5)
	local pad = S(12)
	local wellSize = math.min(rowH - pad * 2, S(110))
	local well = UI.frame({
		BackgroundColor3 = Color3.fromHex(class.color),
		BackgroundTransparency = if isOwned then 0 else 0.45, -- an ability of a class you don't own reads dimmed
		Position = UDim2.fromOffset(pad, pad),
		Size = UDim2.fromOffset(wellSize, wellSize),
		Parent = row,
	})
	UI.corner(well, S(8))
	-- The ability's pictogram (Icons.lua, keyed by Classes.lua `icon`), a little above centre to clear the price.
	-- Cut-outs take the well's colour (as it reads over the row when dimmed).
	local classColor = Color3.fromHex(class.color)
	local ic = Icons.draw(
		well,
		a.icon,
		math.floor(wellSize * 0.56),
		Theme.Colors.bg,
		if isOwned then classColor else classColor:Lerp(Theme.Colors.panel, 0.45),
		a.icon
	)
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.new(0.5, 0, 0.5, -S(8))
	local pricePill, priceLabel = UI.pill(well, "$" .. a.price, Theme.Colors.bg, Theme.Colors.cash, S(20), S(12))
	pricePill.AnchorPoint = Vector2.new(0.5, 1)
	pricePill.Position = UDim2.new(0.5, 0, 1, -S(6))
	pricePill.BackgroundTransparency = 0.15
	priceLabel.FontFace = Theme.Fonts.display
	-- Hotkey on the icon's top-left corner.
	-- Brief 11: the current device's glyph (Q on keyboard, L1 on a pad, none on touch).
	InputGlyphs.chip("ability" .. (order - 1), S(24), {
		Name = "Hotkey",
		Position = UDim2.fromOffset(S(5), S(5)),
		ZIndex = 3,
		Parent = well,
	}, { context = "run", keyboardText = a.hotkey })
	local textX = pad + wellSize + S(14)
	local rightW = S(170)
	UI.text({
		Text = a.name,
		FontFace = Theme.Fonts.body,
		TextSize = S(20),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(textX, pad),
		Size = UDim2.new(1, -textX - rightW, 0, S(24)),
		Parent = row,
	})
	-- The whole description, wrapped onto up to two lines under the name.
	UI.text({
		Text = a.description,
		TextSize = S(12),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Position = UDim2.fromOffset(textX, pad + S(26)),
		Size = UDim2.new(1, -textX - rightW, 0, S(32)),
		Parent = row,
	})
	-- Stats fill the rest of the middle column.
	local statsY = pad + S(62)
	local stats = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(textX, statsY),
		Size = UDim2.new(1, -textX - rightW, 1, -statsY - pad),
		Parent = row,
	})
	UI.list(stats, Enum.FillDirection.Vertical, S(4))
	for k, v in a.vars do
		local cur = AbilityGrowth.at(a.id, v.id, v.base, level)
		local nxt = AbilityGrowth.at(a.id, v.id, v.base, level + 1)
		MetaUI.statRow(stats, k, v.label, fmtVar(v, cur), if isOwned then fmtVar(v, nxt) else nil)
	end
	-- Right: level on top, UPGRADE at the bottom.
	local lv, lvLabel = UI.pill(row, string.format("LV %d", level), Theme.Colors.gold, Theme.Colors.bg, S(30), S(16))
	lv.AnchorPoint = Vector2.new(1, 0)
	lv.Position = UDim2.new(1, -pad, 0, pad)
	lvLabel.FontFace = Theme.Fonts.display
	local btnHolder = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -pad, 1, -pad),
		Size = UDim2.fromOffset(rightW - S(12), S(44)),
		Parent = row,
	})
	UI.list(btnHolder, Enum.FillDirection.Vertical, 0)
	if isOwned then
		MetaUI.button(btnHolder, 1, "UPGRADE - " .. MetaUI.fmtGold(Prices.ability), "green", function()
			local r = scene.request("upgradeAbility", { abilityId = a.id })
			if r.ok then
				scene.refresh()
			end
		end)
	else
		MetaUI.lockedButton(btnHolder, 1)
	end
end

function ClassesTab.render(scene: any)
	local S = UI.S
	local panel: Frame = scene.panel
	if not panel then
		return
	end
	scene.setCustomize(false)
	local profile = scene.profile()
	local equipped = if profile then profile.classes.equipped else Classes.Default
	if not selected then
		selected = equipped
	end
	local class = Classes.ById[selected :: string] or Classes.ById[Classes.Default]
	local isOwned = profile ~= nil and profile.classes.owned[class.id] == true
	if lastIdle ~= class.id then
		lastIdle = class.id
		scene.preview.classIdle(class.id)
	end

	-- Class pills across the full width.
	local pills = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(48)),
		Parent = panel,
	})
	UI.list(pills, Enum.FillDirection.Horizontal, S(6))
	for i, c in Classes.List do
		local own = profile ~= nil and profile.classes.owned[c.id] == true
		local pop = if equipped == c.id and equipPopFor(c.id)
			then "equip"
			elseif popSelect == c.id then "select"
			else nil
		classPill(pills, i, c, own, selected == c.id, equipped == c.id, pop, function()
			if selected ~= c.id then
				popSelect = c.id
			end
			selected = c.id
			UI.sound(Theme.Sounds.toast, 1.25, 0.3)
			scene.refresh()
		end)
	end
	futurePill(pills, #Classes.List + 1, function()
		scene.toast("MORE CLASSES COMING", "click")
	end)

	local rightW = if scene.mobile then S(200) else S(260)
	local grid, card = MetaUI.columns(panel, rightW, S(58), "classes")
	UI.list(grid, Enum.FillDirection.Vertical, S(8))

	-- Three rows share the column's height (no dead space), with a floor so stats never clip.
	local n = #class.abilities
	local available = grid.AbsoluteSize.Y - S(26) - S(8) * (n + 1)
	local rowH = math.max(S(150), math.floor(available / math.max(n, 1)))
	MetaUI.header(grid, 1, string.upper(class.name) .. " · ABILITIES")
	for i, a in class.abilities do
		abilityRow(scene, grid, 1 + i, rowH, class, a, isOwned)
	end

	-- Detail: a shorter well (the equipped check on it, a dim well + padlock when locked), name, the kit, the class
	-- mastery (bar + three tier cards), action. State is the check / lock / dimming, never a word.
	local ic = MetaUI.well(card, 1, Color3.fromHex(class.color), "class", class.id, Theme.Colors.white)
	local well = ic.Parent :: Frame
	well.Size = UDim2.new(1, 0, 0, S(scene.mobile and 96 or 130))
	ic.Size = UDim2.fromOffset(S(scene.mobile and 92 or 120), S(scene.mobile and 92 or 120))
	if equipped == class.id then
		MetaUI.wellCheck(well, equipPopFor(class.id))
	elseif not isOwned then
		well.BackgroundTransparency = 0.45
		local lock = MetaUI.lock(well, S(30), Theme.Colors.white, 6)
		lock.AnchorPoint = Vector2.new(1, 0)
		lock.Position = UDim2.new(1, -S(10), 0, S(10))
	end
	-- Round 25: the name alone (the three abilities are already the rows on the left).
	MetaUI.heading(card, 2, class.name, "")
	local m = profile and profile.mastery and profile.mastery.classes and profile.mastery.classes[class.id]
	masteryBlock(card, 5, class.id, if m then (tonumber(m.xp) or 0) else 0)
	if equipped == class.id then
		MetaUI.equippedButton(card, 20)
	elseif isOwned then
		MetaUI.button(card, 20, "EQUIP", "green", function()
			local r = scene.request("equipClass", { classId = class.id })
			if r.ok then
				markEquipPop(class.id)
				scene.refresh()
			end
		end)
	else
		MetaUI.button(card, 20, "UNLOCK - " .. MetaUI.fmtGold(Prices.class), "green", function()
			local r = scene.request("unlockClass", { classId = class.id })
			if r.ok then
				markEquipPop(class.id) -- unlocking equips it
				scene.refresh()
			end
		end)
		-- Brief 6: a class that comes in a bundle links to it too.
		local Bundles =
			require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Bundles")) :: any
		if #Bundles.containing("class", class.id) > 0 then
			MetaUI.sourceButton(scene, card, 21, "class", class.id, "Bundle")
		end
	end
	popSelect = nil
	if popEquip and popEquip == equipped then
		popEquip = nil -- played
	end
end

-- Brief 11: L1 / R1 on a pad walk the classes (the class pills).
function ClassesTab.cycle(scene: any, dir: number)
	local list = Classes.List
	local i = 1
	for k, c in list do
		if c.id == selected then
			i = k
		end
	end
	local c = list[(i - 1 + dir) % #list + 1]
	popSelect = c.id
	selected = c.id
	UI.sound(Theme.Sounds.toast, 1.25, 0.3)
	scene.refresh()
end

function ClassesTab.onProfile(scene: any)
	scene.refresh()
end

function ClassesTab.leave(scene: any)
	-- Back to the equipped class's idle for the other tabs.
	lastIdle = nil
	popSelect = nil
	popEquip = nil
	local sync = scene.sync()
	scene.preview.classIdle(if sync then sync.classId else Classes.Default)
end

return ClassesTab
