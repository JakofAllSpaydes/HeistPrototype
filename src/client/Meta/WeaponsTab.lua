--!strict
-- Weapons tab, to the reference: filter pills (ALL · PISTOL · SMG · RIFLE · SHOTGUN · SNIPER · LMG) with a
-- search box, OWNED and UNOWNED sections of colored tiles 4 per row, and a detail card on the right (big
-- image, name, firing mode, stat rows with » next, UPGRADE green, CUSTOMIZE pink). CUSTOMIZE switches the
-- scene to the center-zoom view: a category strip bottom-center (SKIN · WRAP · CHARM, only WRAP live) and
-- the wraps row with Back, a price label over the selection and APPLY / BUY.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weapons = require(Shared:WaitForChild("Weapons"))
local Wraps = require(Shared:WaitForChild("Wraps"))
local Prices = require(Shared:WaitForChild("Prices"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Config = require(Shared:WaitForChild("Config"))
local MasteryCopy = require(Shared:WaitForChild("MasteryCopy"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local MetaUI = require(script.Parent:WaitForChild("MetaUI"))

local WeaponsTab = {}

local selected: string? = nil
local filter = "ALL"
local search = ""
local customize = false
local wrapsOpen = false
local wrapPreview: string? = nil

local FILTERS = {
	{ id = "ALL", name = "ALL" },
	{ id = "Pistol", name = "PISTOL" },
	{ id = "SMG", name = "SMG" },
	{ id = "Rifle", name = "RIFLE" },
	{ id = "Shotgun", name = "SHOTGUN" },
	{ id = "Sniper", name = "SNIPER" },
	{ id = "LMG", name = "LMG" },
}

local function levelOf(profile: any, id: string): number
	local e = profile and profile.weapons and profile.weapons[id]
	return if e then (e.level or 0) else 0
end

local function owned(profile: any, id: string): boolean
	return profile ~= nil and profile.weapons ~= nil and profile.weapons[id] ~= nil
end

local function masteryXp(profile: any, id: string): number
	local m = profile and profile.mastery and profile.mastery.weapons and profile.mastery.weapons[id]
	return if m then (tonumber(m.xp) or 0) else 0
end

-- Shop wraps are owned once for every gun; a mastery wrap is owned on the gun whose mastery tier reached it.
local function wrapOwnedOn(profile: any, wrapId: string, weaponId: string): boolean
	if not profile then
		return false
	end
	local mt = MasteryCopy.wrapTier(wrapId)
	if mt then
		return MasteryCopy.weaponTier(masteryXp(profile, weaponId)) >= mt
	end
	return profile.wraps.owned[wrapId] == true
end

local function wrapColorOf(profile: any, id: string): Color3?
	local e = profile and profile.weapons and profile.weapons[id]
	local wrapId = e and e.wrap
	return if wrapId and Wraps.ById[wrapId] then Color3.fromHex(Wraps.ById[wrapId].color) else nil
end

local function fmtReload(t: number): string
	return string.format("%.2fs", t)
end

local function passes(name: string, archetype: string): boolean
	if filter ~= "ALL" and archetype ~= filter then
		return false
	end
	if search ~= "" and not string.find(string.lower(name), string.lower(search), 1, true) then
		return false
	end
	return true
end

local function modeOf(w: Weapons.Weapon): string
	if w.burst > 1 then
		return string.format("%d-round burst", w.burst)
	elseif w.auto then
		return "Automatic"
	elseif w.pellets > 1 then
		return "Pump"
	end
	return "Semi-auto"
end

-- The gun's mastery in the detail column (the shared MetaUI.masteryPanel): MASTERY II with its diamonds, the next
-- reward (a skin), the kills inside the bar.
local function masteryRow(card: Frame, order: number, _w: Weapons.Weapon, xp: number)
	MetaUI.masteryPanel(card, order, Config.WeaponMasteryTiers, xp, "KILLS", "UNLOCK SKIN")
end

------------------------------------------------------------------ Detail card
local function detail(scene: any, card: Frame, w: Weapons.Weapon?, show: Weapons.Showcase?)
	local S = UI.S
	local profile = scene.profile()
	UI.list(card, Enum.FillDirection.Vertical, S(8))
	-- Color is the Armory rarity, not the archetype.
	local rarity = if w then w.rarity else (show and show.rarity or 1)
	local color = Rarity.color(rarity)
	local well = UI.frame({
		BackgroundColor3 = color,
		Size = UDim2.new(1, 0, 0, S(130)),
		LayoutOrder = 1,
		Parent = card,
	})
	UI.corner(well, S(8))
	UI.stroke(well, Theme.Colors.white, S(1.5), 0.6)
	local ic = UI.gunIcon(well, Theme.Colors.white, S(115))
	ic.AnchorPoint = Vector2.new(0.5, 0.5)
	ic.Position = UDim2.fromScale(0.5, 0.5)
	if w then
		local wc = wrapColorOf(profile, w.id)
		if wc then
			UI.recolorIcon(ic, wc)
		end
	end
	local isOwned = w ~= nil and owned(profile, w.id)
	local level = if w then levelOf(profile, w.id) else 0
	-- The name with the info string beside it (mode · rarity · level), then the mastery bar under them.
	local nameRow = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(28)),
		LayoutOrder = 2,
		ClipsDescendants = true,
		Parent = card,
	})
	-- Both labels fill the row and center vertically, so the small info line sits on the name's middle line.
	UI.list(nameRow, Enum.FillDirection.Horizontal, S(10), Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	UI.text({
		Text = if w then w.displayName else (show and show.displayName or "?"),
		Font = Theme.Fonts.body,
		TextSize = S(24),
		TextColor3 = Theme.Colors.white,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 1,
		Parent = nameRow,
	})
	UI.text({
		Text = string.format(
			"%s · %s · %s",
			if w then modeOf(w) else (show and show.hint or ""),
			string.upper(Rarity.name(rarity)),
			if isOwned then string.format("LV %d", level) else "LOCKED"
		),
		Font = Theme.Fonts.body,
		TextSize = S(10),
		TextColor3 = if isOwned then Theme.Colors.gold else Theme.Colors.grey,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 2,
		Parent = nameRow,
	})
	if w and isOwned then
		masteryRow(card, 3, w, masteryXp(profile, w.id))
	end
	if w then
		local cur = Weapons.atLevel(w, level)
		local nxt = Weapons.atLevel(w, level + 1)
		local rate = Weapons.effectiveRate(w, Weapons.levelRateMult(level))
		local nrate = Weapons.effectiveRate(w, Weapons.levelRateMult(level + 1))
		local function dps(d: number, r: number): string
			return tostring(math.round(d * r * w.pellets))
		end
		MetaUI.statRow(card, 10, "DPS", dps(cur.dmg, rate), if isOwned then dps(nxt.dmg, nrate) else nil)
		MetaUI.statRow(
			card,
			11,
			"Damage",
			UI.fmtDmg(cur.dmg, w.pellets),
			if isOwned then UI.fmtDmg(nxt.dmg, w.pellets) else nil
		)
		MetaUI.statRow(card, 12, "Rate", UI.fmtRate(rate), if isOwned then UI.fmtRate(nrate) else nil)
		MetaUI.statRow(card, 13, "Mag Size", tostring(cur.magSize), if isOwned then tostring(nxt.magSize) else nil)
		MetaUI.statRow(
			card,
			14,
			"Reload",
			fmtReload(cur.reloadTime),
			if isOwned then fmtReload(nxt.reloadTime) else nil
		)
	elseif show then
		-- Showcase guns carry placeholder base stats so the card reads like a real one.
		MetaUI.statRow(card, 10, "DPS", tostring(math.round(show.baseDmg * show.fireRate * show.pellets)), nil)
		MetaUI.statRow(card, 11, "Damage", UI.fmtDmg(show.baseDmg, show.pellets), nil)
		MetaUI.statRow(card, 12, "Rate", UI.fmtRate(show.fireRate), nil)
		MetaUI.statRow(card, 13, "Mag Size", tostring(show.magSize), nil)
		MetaUI.statRow(card, 14, "Reload", fmtReload(show.reloadTime), nil)
	end

	-- Buttons by state.
	if not w then
		if show and show.saleType == "Crate" then
			MetaUI.button(card, 20, "VIEW CRATE", "blue", function()
				scene.toast("CRATE UI · PHASE 4", "click")
			end)
		else
			MetaUI.button(card, 20, "EVENT ONLY", "disabled", nil)
		end
		return
	end
	if not isOwned then
		if w.saleType == "Direct" then
			MetaUI.button(card, 20, "UNLOCK - " .. MetaUI.fmtGold(Weapons.unlockCost(w)), "green", function()
				local r = scene.request("unlockWeapon", { weaponId = w.id })
				if r.ok then
					scene.refresh()
				end
			end)
		elseif w.saleType == "Crate" then
			MetaUI.button(card, 20, "VIEW CRATE", "blue", function()
				scene.toast("CRATE UI · PHASE 4", "click")
			end)
		else
			MetaUI.button(card, 20, "EVENT ONLY", "disabled", nil)
		end
		return
	end
	MetaUI.button(card, 20, "UPGRADE - " .. MetaUI.fmtGold(Weapons.upgradeCost(w, level)), "green", function()
		local r = scene.request("upgradeWeapon", { weaponId = w.id })
		if r.ok then
			scene.refresh()
		end
	end)
	-- EQUIP and CUSTOMIZE share one row so the column never runs past the panel.
	local pair = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(44)),
		LayoutOrder = 21,
		Parent = card,
	})
	UI.list(pair, Enum.FillDirection.Horizontal, S(8))
	local isStarter = profile and profile.starterWeaponId == w.id
	local equip = if isStarter
		then MetaUI.button(pair, 1, "EQUIPPED", "disabled", nil)
		else MetaUI.button(pair, 1, "EQUIP", "blue", function()
			local r = scene.request("equipStarter", { weaponId = w.id })
			if r.ok then
				scene.refresh()
			end
		end)
	local custom = MetaUI.button(pair, 2, "CUSTOMIZE", "pink", function()
		customize = true
		wrapsOpen = false
		scene.refresh()
	end)
	for _, b in { equip, custom } do
		b.Size = UDim2.new(0.5, -S(4), 1, 0)
	end
end

------------------------------------------------------------------ Customize (center zoom)
local function stripTile(
	parent: Instance,
	order: number,
	label: string,
	glyph: string,
	locked: boolean,
	active: boolean,
	size: number
): TextButton
	local S = UI.S
	local holder = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size + S(16)),
		LayoutOrder = order,
		Parent = parent,
	})
	local b = UI.button({
		Text = "",
		BackgroundColor3 = if active then Theme.Colors.blue else Theme.Colors.panel,
		Size = UDim2.fromOffset(size, size),
		Parent = holder,
	})
	UI.corner(b, S(10))
	UI.stroke(b, if active then Theme.Colors.white else Theme.Colors.black, S(1.5), 0.3)
	UI.text({
		Text = if locked then "🔒" else glyph,
		Font = Theme.Fonts.display,
		TextSize = math.floor(size * 0.4),
		TextColor3 = if locked then Theme.Colors.grey else Theme.Colors.white,
		Size = UDim2.fromScale(1, 1),
		Parent = b,
	})
	local l = UI.text({
		Text = label,
		Font = Theme.Fonts.display,
		TextSize = S(11),
		TextColor3 = if locked then Theme.Colors.grey else Theme.Colors.text,
		Position = UDim2.fromOffset(0, size + S(1)),
		Size = UDim2.new(1, 0, 0, S(14)),
		Parent = holder,
	})
	UI.stroke(l, Theme.Colors.black, S(1.5), 0.3)
	return b
end

local function renderCustomize(scene: any)
	local S = UI.S
	local overlay: Frame = scene.overlay
	local profile = scene.profile()
	local w = selected and Weapons.ById[selected]
	if not w then
		customize = false
		scene.refresh()
		return
	end
	scene.setCustomize(true)
	local size = if scene.mobile then S(52) else S(62)

	-- Name over the gun.
	UI.text({
		Text = string.upper(w.displayName),
		Font = Theme.Fonts.display,
		TextSize = S(26),
		TextColor3 = Theme.Colors.white,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S(70)),
		Size = UDim2.fromOffset(S(400), S(32)),
		Parent = overlay,
	})

	if not wrapsOpen then
		-- Category strip: BACK · SKIN (locked) · WRAP · CHARM (locked).
		local strip = UI.frame({
			BackgroundColor3 = Theme.Colors.bg,
			BackgroundTransparency = 0.25,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -S(14)),
			Size = UDim2.fromOffset(size * 4 + S(60), size + S(30)),
			Parent = overlay,
		})
		UI.corner(strip, S(12))
		UI.pad(strip, S(12), S(7), S(12), S(7))
		UI.list(strip, Enum.FillDirection.Horizontal, S(12), Enum.HorizontalAlignment.Center)
		local back = stripTile(strip, 0, "Back", "◀", false, false, size)
		back.BackgroundColor3 = Theme.Colors.red
		back.Activated:Connect(function()
			customize = false
			scene.refresh()
		end)
		stripTile(strip, 1, "Skin", "SKN", true, false, size).Activated:Connect(function()
			scene.toast("SKINS · OUT OF SCOPE", "click")
		end)
		local wrap = stripTile(strip, 2, "Wrap", "WRP", false, false, size)
		wrap.Activated:Connect(function()
			wrapsOpen = true
			scene.refresh()
		end)
		stripTile(strip, 3, "Charm", "CHM", true, false, size).Activated:Connect(function()
			scene.toast("CHARMS · OUT OF SCOPE", "click")
		end)
		return
	end

	-- Wraps row: Back on the left, swatches with lock / check, the price over the selection, APPLY / BUY.
	local entry = profile and profile.weapons[w.id]
	local applied: string? = if entry then entry.wrap else nil
	local rowH = size + S(30)
	local row = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		BackgroundTransparency = 0.25,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S(14)),
		Size = UDim2.new(0.8, 0, 0, rowH),
		Parent = overlay,
	})
	UI.corner(row, S(12))
	local list = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(S(12), S(10)),
		Size = UDim2.new(1, -S(24), 0, size + S(16)),
		Parent = row,
	})
	UI.list(list, Enum.FillDirection.Horizontal, S(8), Enum.HorizontalAlignment.Center)
	-- Back is the first tile in the row, so it is always on screen with the swatches.
	local back = stripTile(list, -1, "Back", "◀", false, false, size)
	back.BackgroundColor3 = Theme.Colors.red
	back.Activated:Connect(function()
		wrapsOpen = false
		wrapPreview = nil
		scene.preview.wrap(nil)
		scene.refresh()
	end)
	-- "No wrap" first, then the six wraps.
	local function swatch(
		order: number,
		name: string,
		color: Color3,
		lockedText: string?,
		isSelected: boolean,
		isApplied: boolean,
		sourceTag: string? -- where the wrap comes from (MASTERY; EVENT later), a tag across the top of the swatch
	): TextButton
		local holder = UI.frame({
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(size, size + S(16)),
			LayoutOrder = order,
			Parent = list,
		})
		local b = UI.button({
			Text = "",
			BackgroundColor3 = color,
			Size = UDim2.fromOffset(size, size),
			Parent = holder,
		})
		UI.corner(b, S(8))
		UI.stroke(
			b,
			if isSelected then MetaUI.Green else Theme.Colors.black,
			S(if isSelected then 3 else 1.5),
			if isSelected then 0 else 0.4
		)
		if lockedText then
			UI.text({
				Text = "🔒",
				TextSize = math.floor(size * 0.4),
				Size = UDim2.fromScale(1, 1),
				Parent = b,
			})
		elseif isApplied then
			UI.text({
				Text = "✔",
				Font = Theme.Fonts.display,
				TextSize = math.floor(size * 0.45),
				TextColor3 = MetaUI.Green,
				Size = UDim2.fromScale(1, 1),
				Parent = b,
			})
		end
		if sourceTag then
			local tag, tagLabel = UI.pill(b, sourceTag, Theme.Colors.bg, Theme.Colors.gold, S(14), S(8))
			tag.AnchorPoint = Vector2.new(0.5, 0)
			tag.Position = UDim2.new(0.5, 0, 0, S(4))
			tag.BackgroundTransparency = 0.15
			tag.ZIndex = 3
			tagLabel.ZIndex = 3
			tagLabel.Font = Theme.Fonts.display
		end
		local l = UI.text({
			Text = name,
			TextSize = S(10),
			TextColor3 = Theme.Colors.text,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(0, size + S(1)),
			Size = UDim2.new(1, 0, 0, S(14)),
			Parent = holder,
		})
		UI.stroke(l, Theme.Colors.black, S(1.5), 0.3)
		if isSelected and lockedText then
			-- Price label over the selection (reference: "R$ XXX" tag).
			local tag, tagLabel = UI.pill(holder, lockedText, Theme.Colors.gold, Theme.Colors.bg, S(22), S(12))
			tag.AnchorPoint = Vector2.new(0.5, 1)
			tag.Position = UDim2.new(0.5, 0, 0, -S(8))
			tag.ZIndex = 4
			tagLabel.ZIndex = 4
			tagLabel.Font = Theme.Fonts.display
		end
		return b
	end
	local none = swatch(0, "None", Theme.Colors.panel2, nil, wrapPreview == "none", applied == nil)
	none.Activated:Connect(function()
		wrapPreview = "none"
		scene.preview.wrap(nil)
		scene.refresh()
	end)
	for i, wrap in Wraps.List do
		local isOwned = wrapOwnedOn(profile, wrap.id, w.id)
		local mt = MasteryCopy.wrapTier(wrap.id)
		local b = swatch(
			i,
			wrap.name,
			Color3.fromHex(wrap.color),
			if isOwned then nil elseif mt then "MASTERY " .. MasteryCopy.Roman[mt] else MetaUI.fmtGold(Prices.wrap),
			wrapPreview == wrap.id,
			applied == wrap.id,
			if mt then "MASTERY" else nil
		)
		b.Activated:Connect(function()
			wrapPreview = wrap.id
			scene.preview.wrap(wrap.color)
			UI.sound(Theme.Sounds.toast, 1.3, 0.3)
			scene.refresh()
		end)
	end
	-- Action for the selection, right of the row.
	local action = UI.frame({
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 0, -S(8)),
		Size = UDim2.fromOffset(S(200), S(44)),
		Parent = row,
	})
	UI.list(action, Enum.FillDirection.Vertical, 0)
	if wrapPreview == "none" and applied ~= nil then
		MetaUI.button(action, 1, "REMOVE WRAP", "blue", function()
			local r = scene.request("applyWrap", { weaponId = w.id, wrapId = nil })
			if r.ok then
				wrapPreview = nil
				scene.preview.commit()
				scene.preview.wrap(nil)
				scene.refresh()
			end
		end)
	elseif wrapPreview and wrapPreview ~= "none" and Wraps.ById[wrapPreview] then
		local pw = Wraps.ById[wrapPreview]
		local isOwned = wrapOwnedOn(profile, pw.id, w.id)
		local mt = MasteryCopy.wrapTier(pw.id)
		if not isOwned and mt then
			-- A mastery wrap: earned with kills on this gun, never sold.
			UI.text({
				Text = string.format(
					"%s MASTERY %s · %d KILLS",
					string.upper(w.displayName),
					MasteryCopy.Roman[mt],
					Config.WeaponMasteryTiers[mt] or 0
				),
				Font = Theme.Fonts.display,
				TextSize = S(12),
				TextColor3 = Theme.Colors.gold,
				TextWrapped = true,
				Size = UDim2.new(1, 0, 1, 0),
				Parent = action,
			})
		elseif isOwned and applied ~= pw.id then
			MetaUI.button(action, 1, "APPLY", "green", function()
				local r = scene.request("applyWrap", { weaponId = w.id, wrapId = pw.id })
				if r.ok then
					scene.preview.commit()
					scene.refresh()
				end
			end)
		elseif not isOwned then
			MetaUI.button(action, 1, "BUY - " .. MetaUI.fmtGold(Prices.wrap), "green", function()
				local r = scene.request("buyWrap", { wrapId = pw.id, weaponId = w.id })
				if r.ok then
					scene.preview.commit()
					scene.refresh()
				end
			end)
		end
	end
end

------------------------------------------------------------------ Grid view
function WeaponsTab.render(scene: any)
	local S = UI.S
	local panel: Frame = scene.panel
	if not panel then
		return
	end
	if customize then
		renderCustomize(scene)
		return
	end
	scene.setCustomize(false)
	local profile = scene.profile()
	if not selected then
		selected = if profile then profile.starterWeaponId else Weapons.Starter
	end

	-- Filters and search.
	local pills = MetaUI.pills(panel, FILTERS, filter, function(id)
		filter = id
		UI.sound(Theme.Sounds.toast, 1.2, 0.3)
		scene.refresh()
	end)
	pills.Size = UDim2.new(1, -S(180), 0, S(34))
	local searchBox = UI.new("TextBox", {
		PlaceholderText = "Search…",
		Text = search,
		Font = Theme.Fonts.body,
		TextSize = S(12),
		TextColor3 = Theme.Colors.white,
		PlaceholderColor3 = Theme.Colors.grey,
		BackgroundColor3 = Theme.Colors.panel,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(S(170), S(34)),
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	}) :: TextBox
	UI.corner(searchBox, S(4))
	UI.pad(searchBox, S(10), 0, S(10), 0)
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		if searchBox.Text ~= search then
			search = searchBox.Text
			scene.refresh()
		end
	end)

	local rightW = if scene.mobile then S(200) else S(250)
	local grid, card = MetaUI.columns(panel, rightW, S(44), "weapons")
	UI.list(grid, Enum.FillDirection.Vertical, S(8))
	local perRow = 4
	local tileW = math.floor((grid.AbsoluteSize.X - S(8) * (perRow - 1) - S(12)) / perRow)
	tileW = math.clamp(tileW, S(64), S(110))

	local ownedList: { any }, unownedList: { any } = {}, {}
	for _, w in Weapons.List do
		if passes(w.displayName, w.archetype) then
			table.insert(if owned(profile, w.id) then ownedList else unownedList, { weapon = w })
		end
	end
	for _, s in Weapons.Showcase do
		if passes(s.displayName, s.archetype) then
			table.insert(unownedList, { showcase = s })
		end
	end

	local function tilesFor(list: { any }, header: string, order: number)
		MetaUI.header(grid, order, header)
		if #list == 0 then
			return
		end
		local row = MetaUI.row(grid, order + 1, tileW, perRow)
		for i, e in list do
			local w: Weapons.Weapon? = e.weapon
			local s: Weapons.Showcase? = e.showcase
			local id = if w then w.id else (s :: Weapons.Showcase).id
			local name = if w then w.displayName else (s :: Weapons.Showcase).displayName
			local rarity = if w then w.rarity else (s :: Weapons.Showcase).rarity
			local isOwned = w ~= nil and owned(profile, w.id)
			local pill: string, pillColor: Color3
			if isOwned and w then
				pill = string.format("LV %d", levelOf(profile, w.id))
				pillColor = Theme.Colors.gold
			elseif w then
				pill, pillColor = MetaUI.acquisition(w.saleType, Weapons.unlockCost(w))
			else
				pill, pillColor = MetaUI.acquisition((s :: Weapons.Showcase).saleType, 0)
			end
			local tag: string? = nil
			if isOwned and profile and profile.starterWeaponId == id then
				tag = "STARTER"
			end
			local b = MetaUI.tile(row, {
				name = name,
				pill = pill,
				pillColor = pillColor,
				color = Rarity.color(rarity),
				owned = isOwned,
				selected = selected == id,
				tag = tag,
				tagColor = Theme.Colors.gold,
				icon = "gun",
				iconColor = (w and wrapColorOf(profile, w.id)) or Theme.Colors.white,
				size = tileW,
				order = i,
				-- Owned: the level rides in the top bar next to the name; the bottom is the mastery bar.
				nameTag = if isOwned and w then string.format("LV %d", levelOf(profile, w.id)) else nil,
				noPill = isOwned,
			})
			if w and isOwned then
				MetaUI.masteryBar(b, "weapon", w.id, masteryXp(profile, w.id))
			end
			b.Activated:Connect(function()
				selected = id
				UI.sound(Theme.Sounds.toast, 1.25, 0.3)
				scene.refresh()
			end)
		end
	end
	tilesFor(ownedList, "OWNED", 1)
	tilesFor(unownedList, "UNOWNED", 10)

	local w = selected and Weapons.ById[selected]
	local show: Weapons.Showcase? = nil
	if not w then
		for _, s in Weapons.Showcase do
			if s.id == selected then
				show = s
			end
		end
	end
	detail(scene, card, w, show)
end

function WeaponsTab.onProfile(scene: any)
	scene.refresh()
end

function WeaponsTab.leave(scene: any)
	customize = false
	wrapsOpen = false
	wrapPreview = nil
	scene.preview.wrap(nil)
	scene.setCustomize(false)
end

return WeaponsTab
