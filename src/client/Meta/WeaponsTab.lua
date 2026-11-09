--!strict
-- Weapons tab, to the reference: filter pills (ALL · PISTOL · SMG · RIFLE · SHOTGUN · SNIPER · LMG) with a
-- search box, OWNED and UNOWNED sections of rarity tiles 4 per row, and a detail card on the right (art box with the
-- rarity on it, name, `PISTOL · SEMI-AUTO`, mastery, the level over the stat rows with » next, UPGRADE green, EQUIP /
-- CUSTOMIZE). Tapping a gun puts it in the avatar's hand (scene.preview.weapon); the equipped gun wears a big
-- check. CUSTOMIZE switches the scene to the center-zoom view: a category strip bottom-center (SKIN · WRAP · CHARM,
-- only WRAP live) and the wraps row with Back, a price label over the selection and APPLY / BUY.
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
local Icons = require(Client:WaitForChild("UI"):WaitForChild("Icons"))
local MetaUI = require(script.Parent:WaitForChild("MetaUI"))
local ModelIcon = require(Client:WaitForChild("UI"):WaitForChild("ModelIcon"))

local WeaponsTab = {}

local selected: string? = nil
local filter = "ALL"
local pickFirst = false -- Round 24aa: a category switch selects the first gun shown (owned first)
local search = ""
local customize = false
local wrapsOpen = false
local wrapPreview: string? = nil
-- One-shot juice: the tile just tapped pops on the next render; the gun just equipped pops its check in on the first
-- render that shows it equipped (the profile sync can land a beat after the remote returns).
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

-- Round 24x: icon tiles (a representative gun per type) so every category fits the row at one size.
local FILTERS = {
	{ id = "ALL", name = "ALL" },
	{ id = "FAV", name = "FAVORITES", glyph = "heart" }, -- Round 24y
	{ id = "Pistol", name = "PISTOL", weaponId = "M1911" },
	{ id = "SMG", name = "SMG", weaponId = "UZI" },
	{ id = "Rifle", name = "RIFLE", weaponId = "AK-47" },
	{ id = "Shotgun", name = "SHOTGUN", weaponId = "SPAS-12" },
	{ id = "Sniper", name = "SNIPER", weaponId = "AWP" },
	{ id = "LMG", name = "LMG", weaponId = "M249" },
	{ id = "Explosive", name = "EXPLOSIVE", weaponId = "RPG7" },
	{ id = "Elemental", name = "ELEMENTAL", weaponId = "Flamethrower" },
}
local FILTER_H = 60 -- the filter row's height (pre-scale)

-- Actions the stats can't tell apart (a bolt sniper and a semi-auto one share every flag).
local FIRE_MODE_BY_ID = {
	AWP = "BOLT-ACTION",
	Mosin = "BOLT-ACTION",
	Model1887 = "LEVER-ACTION",
	Kar98k = "BOLT-ACTION", -- Round 24s
	Python = "REVOLVER",
	SVD = "SEMI-AUTO",
	RPG7 = "ROCKET",
	M32 = "GRENADE · 0.25s FUSE",
	ClusterLauncher = "CLUSTER · 0.5s FUSE",
	TNT = "THROWN · 1s FUSE",
	Flamethrower = "FLAME STREAM",
	CryoSprayer = "FROST STREAM",
	ArcGun = "CHAIN LIGHTNING",
	PlasmaCaster = "CHARGE BEAM",
	Railcaster = "CHARGED RAIL", -- Round 24ad
	Exogun = "ENERGY · FULL-AUTO",
	SawedOff = "DOUBLE-BARREL",
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

-- The wrap applied to an owned gun (its model icon wears it).
local function wrapIdOf(profile: any, id: string): string?
	local e = profile and profile.weapons and profile.weapons[id]
	local wrapId = e and e.wrap
	return if typeof(wrapId) == "string" and Wraps.ById[wrapId] then wrapId else nil
end

local function fmtReload(t: number): string
	return string.format("%.2fs", t)
end

-- Round 24y: favourites. The heart flips at once here (optimistic) and the server saves it to the profile.
local favLocal: { [string]: boolean } = {}
local function isFav(profile: any, id: string): boolean
	local v = favLocal[id]
	if v ~= nil then
		return v
	end
	return profile ~= nil and profile.favorites ~= nil and profile.favorites[id] == true
end

local function passes(name: string, archetype: string, id: string?, profile: any): boolean
	if filter == "FAV" then
		if not (id and isFav(profile, id)) then
			return false
		end
	elseif filter ~= "ALL" and archetype ~= filter then
		return false
	end
	if search ~= "" and not string.find(string.lower(name), string.lower(search), 1, true) then
		return false
	end
	return true
end

-- The fire mode for the detail line ("SEMI-AUTO", "FULL-AUTO", "3-ROUND BURST", "PUMP", ...).
local function fireMode(w: Weapons.Weapon): string
	local named = FIRE_MODE_BY_ID[w.id]
	if named then
		return named
	elseif w.burst > 1 then
		return string.format("%d-ROUND BURST", w.burst)
	elseif w.auto then
		return "FULL-AUTO"
	elseif w.shellReload then
		return "PUMP"
	end
	return "SEMI-AUTO"
end

local function isEquipped(profile: any, id: string): boolean
	return profile ~= nil and (profile.starterWeaponId == id or profile.starterWeaponId2 == id)
end

-- Round 24z: both starter slots are full: a popup with the two equipped guns; tap the one to replace.
local function pickSlot(scene: any, anchor: Instance, w: Weapons.Weapon, profile: any)
	local S = UI.S
	local gui = anchor:FindFirstAncestorOfClass("ScreenGui")
	if not gui then
		return
	end
	local dim = UI.button({
		Name = "SlotPicker",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Parent = gui,
	})
	local function close()
		dim:Destroy()
	end
	dim.Activated:Connect(close)
	local box = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(S(460), S(270)),
		ZIndex = 51,
		Parent = dim,
	})
	UI.corner(box, S(6))
	UI.stroke(box, Theme.Colors.white, S(1.5), 0.6)
	UI.punch(box, 1.06, 0.2)
	UI.text({
		Text = "REPLACE WHICH SLOT?",
		FontFace = Theme.Fonts.display,
		TextSize = S(22),
		TextColor3 = Theme.Colors.white,
		Position = UDim2.fromOffset(0, S(12)),
		Size = UDim2.new(1, 0, 0, S(28)),
		ZIndex = 52,
		Parent = box,
	})
	UI.text({
		Text = "EQUIPPING " .. w.displayName,
		FontFace = Theme.Fonts.body,
		TextSize = S(13),
		TextColor3 = Theme.Colors.grey,
		Position = UDim2.fromOffset(0, S(40)),
		Size = UDim2.new(1, 0, 0, S(18)),
		ZIndex = 52,
		Parent = box,
	})
	for slot = 1, 2 do
		local id = if slot == 1 then profile.starterWeaponId else profile.starterWeaponId2
		local cur = id and Weapons.ById[id]
		local b = UI.button({
			Text = "",
			BackgroundColor3 = if cur then Rarity.color(cur.rarity) else Theme.Colors.panel,
			AnchorPoint = Vector2.new(if slot == 1 then 1 else 0, 0),
			Position = UDim2.new(0.5, if slot == 1 then -S(8) else S(8), 0, S(70)),
			Size = UDim2.fromOffset(S(200), S(150)),
			ZIndex = 52,
			Parent = box,
		})
		UI.corner(b, S(4))
		MetaUI.hover(b, 1.04)
		if cur then
			local vp = ModelIcon.weapon(b, cur.id, UDim2.new(1, -S(16), 0, S(90)), {})
			vp.AnchorPoint = Vector2.new(0.5, 0)
			vp.Position = UDim2.new(0.5, 0, 0, S(8))
			vp.ZIndex = 53
		end
		UI.text({
			Text = string.format("SLOT %d · %s", slot, if cur then cur.displayName else "EMPTY"),
			FontFace = Theme.Fonts.display,
			TextSize = S(15),
			TextColor3 = Theme.Colors.white,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -S(10)),
			Size = UDim2.new(1, -S(12), 0, S(22)),
			ZIndex = 53,
			Parent = b,
		})
		b.Activated:Connect(function()
			close()
			local r = scene.request("equipStarter", { weaponId = w.id, slot = slot })
			if r.ok then
				markEquipPop(w.id)
				scene.refresh()
			end
		end)
	end
end

------------------------------------------------------------------ Detail card
local function detail(scene: any, card: Frame, w: Weapons.Weapon?, show: Weapons.Showcase?)
	local S = UI.S
	local profile = scene.profile()
	local id = if w then w.id else (show and show.id or "")
	local isOwned = w ~= nil and owned(profile, w.id)
	local equipped = w ~= nil and isOwned and isEquipped(profile, w.id)
	local level = if w then levelOf(profile, w.id) else 0
	-- Art box in the rarity color, the rarity on it top-left, the equipped check top-right.
	local rarity = if w then w.rarity else (show and show.rarity or 1)
	-- The gun itself (wearing its wrap), turning slowly in the well.
	local ic = MetaUI.well(card, 1, Rarity.color(rarity), "gun", nil, nil, {
		id = id,
		rarity = rarity,
		wrapId = if w then wrapIdOf(profile, w.id) else nil,
		archetype = if show then show.archetype else nil,
	})
	local well = ic.Parent :: Frame
	well.Size = UDim2.new(1, 0, 0, S(if scene.mobile then 80 else 88)) -- Round 24aa: shorter so the panel fits unscrolled
	if not ic:IsA("ViewportFrame") then
		ic.Size = UDim2.fromOffset(S(if scene.mobile then 96 else 110), S(if scene.mobile then 96 else 110))
	end
	MetaUI.rarityChip(well, rarity)
	MetaUI.wellSource(well, if w then w.saleType else (show and show.saleType or nil)) -- Round 24af
	if equipped then
		MetaUI.wellCheck(well, equipPopFor(id))
	end
	-- Name, then what kind of gun it is: archetype · fire mode.
	MetaUI.heading(
		card,
		2,
		if w then w.displayName else (show and show.displayName or "?"),
		if w
			then string.upper(w.archetype) .. " · " .. fireMode(w)
			else string.upper(show and show.archetype or "") .. " · " .. string.upper(show and show.hint or "")
	)
	if w and isOwned then
		MetaUI.masteryPanel(card, 4, Config.WeaponMasteryTiers, masteryXp(profile, w.id), "KILLS", "UNLOCK SKIN")
		-- The level heads the stat rows it drives (their » next is the next level).
		MetaUI.levelRow(card, 9, level, true)
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
					markEquipPop(w.id) -- unlocking equips it
					scene.refresh()
				end
			end)
		else
			MetaUI.sourceButton(scene, card, 20, "weapon", w.id, w.saleType)
		end
		-- The FAL and the Mosin also come in a bundle.
		local Bundles =
			require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Bundles")) :: any
		if w.saleType ~= "Bundle" and #Bundles.containing("weapon", w.id) > 0 then
			MetaUI.sourceButton(scene, card, 21, "weapon", w.id, "Bundle")
		end
		return
	end
	MetaUI.button(card, 20, "UPGRADE - " .. MetaUI.fmtGold(Weapons.upgradeCost(w, level)), "green", function()
		local r = scene.request("upgradeWeapon", { weaponId = w.id })
		if r.ok then
			scene.refresh()
		end
	end)
	-- EQUIP (or the equipped check) and CUSTOMIZE share one row so the column never runs past the panel.
	local pair = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(44)),
		LayoutOrder = 21,
		Parent = card,
	})
	UI.list(pair, Enum.FillDirection.Horizontal, S(8))
	local equip = if equipped
		then MetaUI.equippedButton(pair, 1)
		else MetaUI.button(pair, 1, "EQUIP", "blue", function()
			local r = scene.request("equipStarter", { weaponId = w.id })
			if r.ok then
				markEquipPop(w.id)
				scene.refresh()
			elseif r.needSlot then
				pickSlot(scene, card, w, scene.profile())
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
	glyph: string, -- 3-letter caps, or "back" / "lock" for the drawn glyphs
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
		BackgroundTransparency = if locked then 0.3 else 0,
		Size = UDim2.fromOffset(size, size),
		Parent = holder,
	})
	UI.corner(b, S(10))
	UI.stroke(b, if active then Theme.Colors.white else Theme.Colors.black, S(1.5), 0.3)
	if glyph == "back" then
		local a = MetaUI.backArrow(b, math.floor(size * 0.7), Theme.Colors.white)
		a.AnchorPoint = Vector2.new(0.5, 0.5)
		a.Position = UDim2.fromScale(0.5, 0.5)
	elseif locked then
		local l = MetaUI.lock(b, math.floor(size * 0.5), Theme.Colors.grey)
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromScale(0.5, 0.5)
	else
		UI.text({
			Text = glyph,
			FontFace = Theme.Fonts.display,
			TextSize = math.floor(size * 0.36),
			TextColor3 = Theme.Colors.white,
			Size = UDim2.fromScale(1, 1),
			Parent = b,
		})
	end
	local l = UI.text({
		Text = label,
		FontFace = Theme.Fonts.display,
		TextSize = S(11),
		TextColor3 = if locked then Theme.Colors.grey else Theme.Colors.text,
		Position = UDim2.fromOffset(0, size + S(1)),
		Size = UDim2.new(1, 0, 0, S(14)),
		Parent = holder,
	})
	UI.stroke(l, Theme.Colors.black, S(1.5), 0.3)
	b.Activated:Connect(function()
		UI.punch(b, 0.92, 0.15)
	end)
	MetaUI.hover(b)
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
	scene.preview.weapon(w.id) -- the gun being customized is the one in the hand (the wraps paint it)
	local size = if scene.mobile then S(52) else S(62)

	-- Name over the gun.
	UI.text({
		Text = string.upper(w.displayName),
		FontFace = Theme.Fonts.display,
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
		local back = stripTile(strip, 0, "Back", "back", false, false, size)
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
	local back = stripTile(list, -1, "Back", "back", false, false, size)
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
		source: string? -- where a locked wrap comes from (Mastery, a saleType): a small chip on the swatch
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
			if isApplied then MetaUI.Green elseif isSelected then Theme.Colors.white else Theme.Colors.black,
			S(if isApplied or isSelected then 3 else 1.5),
			if isApplied or isSelected then 0 else 0.4
		)
		if lockedText then
			-- Dimmed under a padlock.
			local veil = UI.frame({
				BackgroundColor3 = Theme.Colors.black,
				BackgroundTransparency = 0.55,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 2,
				Parent = b,
			})
			UI.corner(veil, S(8))
			local l = MetaUI.lock(b, math.floor(size * 0.42), Theme.Colors.white, 3)
			l.AnchorPoint = Vector2.new(0.5, 0.5)
			l.Position = UDim2.fromScale(0.5, 0.5)
		elseif isApplied then
			local c = MetaUI.check(b, math.floor(size * 0.42), 4)
			c.AnchorPoint = Vector2.new(1, 0)
			c.Position = UDim2.new(1, -S(3), 0, S(3))
		end
		if source and lockedText then
			local chip, chipLabel = UI.pill(
				b,
				MetaUI.sourceGlyph(source),
				MetaUI.SourceColors[source] or Theme.Colors.gold,
				Theme.Colors.bg,
				S(14),
				S(9)
			)
			chip.AnchorPoint = Vector2.new(0.5, 1)
			chip.Position = UDim2.new(0.5, 0, 1, -S(3))
			chip.ZIndex = 6
			chipLabel.ZIndex = 6
			chipLabel.FontFace = Theme.Fonts.display
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
			tagLabel.FontFace = Theme.Fonts.display
		end
		if isSelected and popSelect == name then
			UI.punch(b, Config.MetaSelectPopScale, 0.25)
		end
		MetaUI.hover(b)
		return b
	end
	local none = swatch(0, "None", Theme.Colors.panel2, nil, wrapPreview == "none", applied == nil)
	none.Activated:Connect(function()
		wrapPreview = "none"
		popSelect = "None"
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
			if isOwned
				then nil
				elseif mt then "MASTERY " .. MasteryCopy.Roman[mt]
				elseif wrap.saleType ~= "Direct" then string.upper(wrap.saleType)
				else MetaUI.fmtGold(Prices.wrap),
			wrapPreview == wrap.id,
			applied == wrap.id,
			if mt then "Mastery" elseif wrap.saleType ~= "Direct" then wrap.saleType else nil
		)
		b.Activated:Connect(function()
			wrapPreview = wrap.id
			popSelect = wrap.name
			scene.preview.wrap(wrap.color)
			UI.sound(Theme.Sounds.toast, 1.3, 0.3)
			scene.refresh()
		end)
	end
	popSelect = nil
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
				FontFace = Theme.Fonts.display,
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
		elseif not isOwned and pw.saleType ~= "Direct" then
			MetaUI.sourceButton(scene, action, 1, "wrap", pw.id, pw.saleType)
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
	-- The selected gun in the avatar's hand (the real one when it is the equipped gun).
	scene.preview.weapon(selected)

	-- Filters and search.
	local pills = MetaUI.iconPills(panel, FILTERS :: any, filter, function(id)
		if filter ~= id then
			pickFirst = true
		end
		filter = id
		UI.sound(Theme.Sounds.toast, 1.2, 0.3)
		scene.refresh()
	end, S(FILTER_H))
	pills.Size = UDim2.new(1, -S(180), 0, S(FILTER_H))
	local searchBox = UI.new("TextBox", {
		PlaceholderText = "Search…",
		Text = search,
		FontFace = Theme.Fonts.body,
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
	local grid, card = MetaUI.columns(panel, rightW, S(FILTER_H + 10), "weapons")
	UI.list(grid, Enum.FillDirection.Vertical, S(8))
	local perRow = 4
	local tileW = MetaUI.tileWidth(grid, perRow)

	local ownedList: { any }, unownedList: { any } = {}, {}
	for _, w in Weapons.List do
		if passes(w.displayName, w.archetype, w.id, profile) then
			table.insert(if owned(profile, w.id) then ownedList else unownedList, { weapon = w })
		end
	end
	for _, s in Weapons.Showcase do
		if passes(s.displayName, s.archetype, s.id, profile) then
			table.insert(unownedList, { showcase = s })
		end
	end
	-- Round 24y: favourites first (highest rarity first), then everything else lowest rarity to highest.
	local function sortKey(e: any): (string, number, string)
		local id = if e.weapon then e.weapon.id else e.showcase.id
		local rarity = if e.weapon then e.weapon.rarity else e.showcase.rarity
		local name = if e.weapon then e.weapon.displayName else e.showcase.displayName
		return id, rarity, name
	end
	local function byFavThenRarity(a: any, b: any): boolean
		local ia, ra, na = sortKey(a)
		local ib, rb, nb = sortKey(b)
		local fa, fb = isFav(profile, ia), isFav(profile, ib)
		if fa ~= fb then
			return fa
		end
		if ra ~= rb then
			return if fa then ra > rb else ra < rb
		end
		return na < nb
	end
	table.sort(ownedList, byFavThenRarity)
	table.sort(unownedList, byFavThenRarity)
	if pickFirst then
		pickFirst = false
		local first = ownedList[1] or unownedList[1]
		if first then
			selected = if first.weapon then first.weapon.id else first.showcase.id
			popSelect = selected
			scene.preview.weapon(selected)
		end
	end

	-- Round 25: a tap re-styles the two tiles and rebuilds the detail card only (rebuilding the whole grid made
	-- every viewport blink out on each tap).
	local tiles: { [string]: { b: TextButton, equipped: boolean } } = {}
	local function renderDetail()
		for _, c in card:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local dw = selected and Weapons.ById[selected]
		local dshow: Weapons.Showcase? = nil
		if not dw then
			for _, s in Weapons.Showcase do
				if s.id == selected then
					dshow = s
				end
			end
		end
		detail(scene, card, dw, dshow)
	end

	local function tilesFor(list: { any }, header: string, order: number)
		MetaUI.header(grid, order, header, #list)
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
			local saleType = if w then w.saleType else (s :: Weapons.Showcase).saleType
			local equipped = isOwned and isEquipped(profile, id)
			local b = MetaUI.tile(row, {
				name = name,
				color = Rarity.color(rarity),
				owned = isOwned,
				selected = selected == id,
				equipped = equipped,
				icon = "gun",
				iconModel = {
					id = id,
					rarity = rarity,
					wrapId = if w then wrapIdOf(profile, w.id) else nil,
					archetype = if s then s.archetype else nil,
				},
				size = tileW,
				order = i,
				-- Owned: the level rides in the top bar next to the name; the bottom is the mastery bar.
				nameTag = if isOwned and w then string.format("LV %d", levelOf(profile, w.id)) else nil,
				price = if w and not isOwned and saleType == "Direct" then Weapons.unlockCost(w) else nil,
				source = if not isOwned then saleType else nil,
				pop = if equipped and equipPopFor(id) then "equip" elseif popSelect == id then "select" else nil,
			})
			tiles[id] = { b = b, equipped = equipped }
			if w and isOwned then
				MetaUI.masteryBar(b, "weapon", w.id, masteryXp(profile, w.id))
			end
			-- Round 24y: the favourite heart, top-right. Hearted: solid red; not: a faint outline-grey heart.
			local fav = isFav(profile, id)
			local heartBtn = UI.button({
				Name = "Favorite",
				Text = "",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -S(3), 0, S(3)),
				Size = UDim2.fromOffset(S(24), S(24)),
				ZIndex = 20,
				Parent = b,
			})
			local glyph = Icons.fit(
				heartBtn,
				"heart",
				0.8,
				if fav then Theme.Colors.red else Theme.Colors.white,
				Theme.Colors.white
			)
			if not fav then
				Icons.setTransparency(glyph, 0.55)
			end
			heartBtn.Activated:Connect(function()
				local now = not isFav(profile, id)
				favLocal[id] = now
				UI.punch(heartBtn, if now then 1.35 else 0.85, 0.2)
				UI.sound(Theme.Sounds.toast, if now then 1.5 else 1.0, 0.3)
				task.spawn(function()
					local r = scene.request("toggleFavorite", { weaponId = id })
					if not (r and r.ok) then
						favLocal[id] = nil
						scene.refresh()
					end
				end)
				scene.refresh()
			end)
			b.Activated:Connect(function()
				UI.sound(Theme.Sounds.toast, 1.25, 0.3)
				if selected == id then
					return
				end
				local old = selected and tiles[selected]
				if old and old.b.Parent then
					MetaUI.tileState(old.b, false, old.equipped)
				end
				selected = id
				MetaUI.tileState(b, true, equipped)
				UI.punch(b, Config.MetaSelectPopScale, 0.25)
				scene.preview.weapon(id)
				renderDetail()
			end)
		end
	end
	tilesFor(ownedList, "OWNED", 1)
	tilesFor(unownedList, "UNOWNED", 10)
	renderDetail()
	popSelect = nil
	if popEquip and isEquipped(profile, popEquip) then
		popEquip = nil -- played
	end
end

-- Brief 11: L1 / R1 on a pad walk the weapon categories (the filter pills).
function WeaponsTab.cycle(scene: any, dir: number)
	local i = 1
	for k, f in FILTERS do
		if f.id == filter then
			i = k
		end
	end
	filter = FILTERS[(i - 1 + dir) % #FILTERS + 1].id
	pickFirst = true
	UI.sound(Theme.Sounds.toast, 1.2, 0.3)
	scene.refresh()
end

function WeaponsTab.onProfile(scene: any)
	scene.refresh()
end

function WeaponsTab.leave(scene: any)
	customize = false
	wrapsOpen = false
	wrapPreview = nil
	popSelect = nil
	popEquip = nil
	scene.preview.wrap(nil)
	scene.preview.weapon(nil)
	scene.setCustomize(false)
end

return WeaponsTab
