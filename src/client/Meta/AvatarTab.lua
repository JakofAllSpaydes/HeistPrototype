--!strict
-- Avatar tab in the shared format with three categories: MASKS (OWNED / UNOWNED mask tiles, live preview on
-- the head), SQUAD (the pose struck in the run start / run end line-ups) and MVP (the flex played alone
-- under the MVP stamp). Tapping an emote plays it on the avatar; the detail column equips or buys. State reads
-- without words (Round 18c): the equipped item wears a big check, unowned tiles dim and carry a 3-letter source
-- chip (or their Gold price); the full source ("MASK CRATE") is in the detail column.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Masks = require(Shared:WaitForChild("Masks"))
local Emotes = require(Shared:WaitForChild("Emotes"))
local Prices = require(Shared:WaitForChild("Prices"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Config = require(Shared:WaitForChild("Config"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local MetaUI = require(script.Parent:WaitForChild("MetaUI"))
local Icons = require(Client:WaitForChild("UI"):WaitForChild("Icons"))

local AvatarTab = {}

local category = "MASKS" -- MASKS | SQUAD | MVP
local selectedMask: string? = nil
local selectedEmote: { [string]: string? } = {} -- per category
-- One-shot juice: the tile just tapped pops; the item just equipped pops its check in once the profile shows it.
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

local CATEGORIES = {
	{ id = "MASKS", name = "MASKS" },
	{ id = "SQUAD", name = "SQUAD" },
	{ id = "MVP", name = "MVP" },
}

local SLOT_COLORS = { SQUAD = Color3.fromHex("3FA873"), MVP = Color3.fromHex("E8B64C") }

-- Round 24aa: favourites (hearts on the tiles, saved to the profile as "mask:<id>" / "emote:<id>"), sorted first
-- (highest rarity first; the rest lowest first), and a FAV toggle that shows only the current category's favourites.
local favOnly = false
local favLocal: { [string]: boolean } = {}
local function isFav(profile: any, key: string): boolean
	local v = favLocal[key]
	if v ~= nil then
		return v
	end
	return profile ~= nil and profile.favorites ~= nil and profile.favorites[key] == true
end
local function toggleFav(scene: any, profile: any, kind: string, id: string)
	local key = kind .. ":" .. id
	favLocal[key] = not isFav(profile, key)
	task.spawn(function()
		local r = scene.request("toggleFavorite", { kind = kind, id = id })
		if not (r and r.ok) then
			favLocal[key] = nil
			scene.refresh()
		end
	end)
	scene.refresh()
end
-- Favourites first (highest rarity first), then the rest lowest rarity first; name breaks ties.
local function favSort(profile: any, kind: string, list: { any })
	table.sort(list, function(a, b)
		local fa, fb = isFav(profile, kind .. ":" .. a.id), isFav(profile, kind .. ":" .. b.id)
		if fa ~= fb then
			return fa
		end
		if a.rarity ~= b.rarity then
			return if fa then a.rarity > b.rarity else a.rarity < b.rarity
		end
		return a.name < b.name
	end)
end
local function favFilter(profile: any, kind: string, list: { any }): { any }
	if not favOnly then
		return list
	end
	local out = {}
	for _, e in list do
		if isFav(profile, kind .. ":" .. e.id) then
			table.insert(out, e)
		end
	end
	return out
end

local function pills(scene: any, panel: Frame)
	-- The FAV toggle sits right of the category pills: a heart, red and lit when on.
	local S = UI.S
	local favBtn = UI.button({
		Name = "FavToggle",
		Text = "",
		BackgroundColor3 = if favOnly then Theme.Colors.red else Theme.Colors.panel,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(S(72), S(34)),
		Parent = panel,
	})
	UI.corner(favBtn, S(4))
	local heartHolder = UI.frame({
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(S(6), S(5)),
		Size = UDim2.fromOffset(S(24), S(24)),
		Parent = favBtn,
	})
	Icons.fit(heartHolder, "heart", 0.9, if favOnly then Theme.Colors.white else Theme.Colors.red, Theme.Colors.white)
	UI.text({
		Text = "FAV",
		FontFace = Theme.Fonts.display,
		TextSize = S(14),
		TextColor3 = Theme.Colors.white,
		Position = UDim2.fromOffset(S(32), 0),
		Size = UDim2.new(1, -S(36), 1, 0),
		Parent = favBtn,
	})
	favBtn.Activated:Connect(function()
		favOnly = not favOnly
		UI.punch(favBtn, 0.94, 0.15)
		UI.sound(Theme.Sounds.toast, if favOnly then 1.5 else 1.1, 0.3)
		scene.refresh()
	end)
	MetaUI.pills(panel, CATEGORIES, category, function(id)
		if id ~= category then
			category = id
			UI.sound(Theme.Sounds.toast, 1.2, 0.3)
			scene.preview.mask(nil, nil)
			scene.refresh()
		end
	end)
end

-- Emote tiles: the emote's initial in the circle (house style), not a play symbol.
local function initial(name: string): string
	return string.upper(string.sub(name, 1, 1))
end

------------------------------------------------------------------ Masks
local function renderMasks(scene: any, panel: Frame)
	local S = UI.S
	local profile = scene.profile()
	local equipped = if profile then profile.masks.equipped else Masks.Default
	if not selectedMask then
		selectedMask = equipped
	end
	local first = Masks.ById[selectedMask :: string] or Masks.ById[Masks.Default]
	scene.preview.mask(first.color, first.shape, first.id)

	local rightW = if scene.mobile then S(200) else S(250)
	local grid, card = MetaUI.columns(panel, rightW, S(44), "masks")
	UI.list(grid, Enum.FillDirection.Vertical, S(8))
	local perRow = 4
	local tileW = MetaUI.tileWidth(grid, perRow)

	local ownedList, unownedList = {}, {}
	for _, m in Masks.List do
		local own = profile ~= nil and profile.masks.owned[m.id] == true
		table.insert(if own then ownedList else unownedList, m)
	end
	ownedList, unownedList = favFilter(profile, "mask", ownedList), favFilter(profile, "mask", unownedList)
	favSort(profile, "mask", ownedList)
	favSort(profile, "mask", unownedList)
	-- Round 25: a tap re-styles two tiles and rebuilds the detail card only (no grid rebuild, no blink).
	local tiles: { [string]: { b: TextButton, equipped: boolean } } = {}
	local renderDetail: () -> ()
	local function tilesFor(list: { Masks.Mask }, header: string, order: number)
		MetaUI.header(grid, order, header, #list)
		if #list == 0 then
			return
		end
		local row = MetaUI.row(grid, order + 1, tileW, perRow)
		for i, m in list do
			local own = profile ~= nil and profile.masks.owned[m.id] == true
			local isEq = own and equipped == m.id
			local b = MetaUI.tile(row, {
				name = m.name,
				color = Rarity.color(m.rarity), -- tile color is the rarity; the mask's own color is on the icon
				owned = own,
				selected = selectedMask == m.id,
				equipped = isEq,
				icon = "mask",
				iconColor = Color3.fromHex(m.color),
				iconModel = { id = m.id }, -- the mask on its bust
				size = tileW,
				order = i,
				price = if not own and m.saleType == "Direct" then (m.price or Prices.mask) else nil,
				source = if not own then m.saleType else nil,
				pop = if isEq and equipPopFor(m.id) then "equip" elseif popSelect == m.id then "select" else nil,
			})
			tiles[m.id] = { b = b, equipped = isEq }
			MetaUI.favHeart(b, isFav(profile, "mask:" .. m.id), function()
				toggleFav(scene, profile, "mask", m.id)
			end)
			b.Activated:Connect(function()
				UI.sound(Theme.Sounds.toast, 1.25, 0.3)
				if selectedMask == m.id then
					return
				end
				local old = selectedMask and tiles[selectedMask :: string]
				if old and old.b.Parent then
					MetaUI.tileState(old.b, false, old.equipped)
				end
				selectedMask = m.id
				MetaUI.tileState(b, true, isEq)
				UI.punch(b, Config.MetaSelectPopScale, 0.25)
				scene.preview.mask(m.color, m.shape, m.id)
				renderDetail()
			end)
		end
	end
	-- Detail: the art box (rarity on it, the equipped check), name, the accessory type, where it comes from.
	renderDetail = function()
		for _, c in card:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local mask = Masks.ById[selectedMask :: string] or Masks.ById[Masks.Default]
		local isOwned = profile ~= nil and profile.masks.owned[mask.id] == true
		local ic =
			MetaUI.well(card, 1, Rarity.color(mask.rarity), "mask", nil, Color3.fromHex(mask.color), { id = mask.id })
		local well = ic.Parent :: Frame
		MetaUI.rarityChip(well, mask.rarity)
		MetaUI.wellSource(well, mask.saleType) -- Round 24af
		if equipped == mask.id then
			MetaUI.wellCheck(well, equipPopFor(mask.id))
		end
		MetaUI.heading(card, 2, mask.name, string.upper(mask.type) .. " ACCESSORY")
		MetaUI.statRow(card, 10, "From", MetaUI.sourceName(mask.saleType, "mask", mask.id), nil)
		if equipped == mask.id then
			MetaUI.equippedButton(card, 20)
		elseif isOwned then
			MetaUI.button(card, 20, "EQUIP", "green", function()
				local r = scene.request("equipMask", { maskId = mask.id })
				if r.ok then
					markEquipPop(mask.id)
					scene.preview.commit()
					scene.refresh()
				end
			end)
		elseif mask.saleType == "Direct" then
			MetaUI.button(card, 20, "UNLOCK - " .. MetaUI.fmtGold(mask.price or Prices.mask), "green", function()
				local r = scene.request("buyMask", { maskId = mask.id })
				if r.ok then
					markEquipPop(mask.id) -- buying equips it
					scene.preview.commit()
					scene.refresh()
				end
			end)
		else
			MetaUI.sourceButton(scene, card, 20, "mask", mask.id, mask.saleType)
		end
	end
	tilesFor(ownedList, "OWNED", 1)
	tilesFor(unownedList, "UNOWNED", 10)
	renderDetail()
	popSelect = nil
	if popEquip and popEquip == equipped then
		popEquip = nil -- played
	end
end

------------------------------------------------------------------ Emotes (SQUAD / MVP)
local function renderEmotes(scene: any, panel: Frame, slot: string)
	local S = UI.S
	local profile = scene.profile()
	local equipped = if profile and profile.emotes
		then (if slot == "mvp" then profile.emotes.mvp else profile.emotes.squad)
		else (if slot == "mvp" then Emotes.DefaultMvp else Emotes.DefaultSquad)
	local sel = selectedEmote[category]
	if not sel then
		sel = equipped
		selectedEmote[category] = sel
	end
	local emote = Emotes.ById[sel :: string] or Emotes.ById[equipped] or Emotes.ById[Emotes.DefaultSquad]
	local isOwned = profile ~= nil and profile.emotes ~= nil and profile.emotes.owned[emote.id] == true
	local color = SLOT_COLORS[category] or Theme.Colors.grey

	local rightW = if scene.mobile then S(200) else S(250)
	local grid, card = MetaUI.columns(panel, rightW, S(44), "emote:" .. slot)
	UI.list(grid, Enum.FillDirection.Vertical, S(8))
	local perRow = 4
	local tileW = MetaUI.tileWidth(grid, perRow)

	local ownedList, unownedList = {}, {}
	for _, e in Emotes.forSlot(slot) do
		local own = profile ~= nil and profile.emotes ~= nil and profile.emotes.owned[e.id] == true
		table.insert(if own then ownedList else unownedList, e)
	end
	ownedList, unownedList = favFilter(profile, "emote", ownedList), favFilter(profile, "emote", unownedList)
	favSort(profile, "emote", ownedList)
	favSort(profile, "emote", unownedList)
	local function tilesFor(list: { Emotes.Emote }, header: string, order: number)
		MetaUI.header(grid, order, header, #list)
		if #list == 0 then
			return
		end
		local row = MetaUI.row(grid, order + 1, tileW, perRow)
		for i, e in list do
			local own = profile ~= nil and profile.emotes ~= nil and profile.emotes.owned[e.id] == true
			local isEq = own and equipped == e.id
			local b = MetaUI.tile(row, {
				name = e.name,
				color = Rarity.color(e.rarity),
				owned = own,
				selected = sel == e.id,
				equipped = isEq,
				icon = "class",
				iconColor = Theme.Colors.white,
				glyph = initial(e.name),
				size = tileW,
				order = i,
				price = if not own and e.saleType == "Direct" then (e.price or Prices.emote) else nil,
				source = if not own then e.saleType else nil,
				pop = if isEq and equipPopFor(e.id) then "equip" elseif popSelect == e.id then "select" else nil,
			})
			MetaUI.favHeart(b, isFav(profile, "emote:" .. e.id), function()
				toggleFav(scene, profile, "emote", e.id)
			end)
			b.Activated:Connect(function()
				if selectedEmote[category] ~= e.id then
					popSelect = e.id
				end
				selectedEmote[category] = e.id
				-- Tap = preview: the emote plays on the avatar right away.
				scene.preview.emote(e.animationId, e.holdSec)
				scene.refresh()
			end)
		end
	end
	tilesFor(ownedList, "OWNED", 1)
	tilesFor(unownedList, "UNOWNED", 10)

	local ic = MetaUI.well(card, 1, Rarity.color(emote.rarity), "class", initial(emote.name), color)
	local well = ic.Parent :: Frame
	MetaUI.rarityChip(well, emote.rarity)
	MetaUI.wellSource(well, emote.saleType)
	if equipped == emote.id then
		MetaUI.wellCheck(well, equipPopFor(emote.id))
	end
	MetaUI.heading(card, 2, emote.name, if slot == "mvp" then "MVP FLEX" else "SQUAD POSE")
	MetaUI.statRow(card, 10, "From", MetaUI.sourceName(emote.saleType, "emote", emote.id), nil)
	MetaUI.button(card, 15, "PREVIEW", "blue", function()
		scene.preview.emote(emote.animationId, emote.holdSec)
	end)
	if equipped == emote.id then
		MetaUI.equippedButton(card, 20)
	elseif isOwned then
		MetaUI.button(card, 20, "EQUIP", "green", function()
			local r = scene.request("equipEmote", { emoteId = emote.id })
			if r.ok then
				markEquipPop(emote.id)
				scene.refresh()
			end
		end)
	elseif emote.saleType == "Direct" then
		MetaUI.button(card, 20, "UNLOCK - " .. MetaUI.fmtGold(emote.price or Prices.emote), "green", function()
			local r = scene.request("buyEmote", { emoteId = emote.id })
			if r.ok then
				markEquipPop(emote.id) -- buying equips it
				scene.refresh()
			end
		end)
	else
		MetaUI.sourceButton(scene, card, 20, "emote", emote.id, emote.saleType)
	end
	popSelect = nil
	if popEquip and popEquip == equipped then
		popEquip = nil -- played
	end
end

function AvatarTab.render(scene: any)
	local panel: Frame = scene.panel
	if not panel then
		return
	end
	scene.setCustomize(false)
	pills(scene, panel)
	if category == "SQUAD" then
		renderEmotes(scene, panel, "squad")
	elseif category == "MVP" then
		renderEmotes(scene, panel, "mvp")
	else
		renderMasks(scene, panel)
	end
end

function AvatarTab.onProfile(scene: any)
	scene.refresh()
end

function AvatarTab.leave(scene: any)
	popSelect = nil
	popEquip = nil
	scene.preview.mask(nil, nil)
end

return AvatarTab
