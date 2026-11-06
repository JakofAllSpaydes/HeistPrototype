--!strict
-- Avatar tab in the shared format with three categories: MASKS (OWNED / UNOWNED mask tiles, live preview on
-- the head), SQUAD (the pose struck in the run start / run end line-ups) and MVP (the flex played alone
-- under the MVP stamp). Tapping an emote plays it on the avatar; the detail column equips or buys.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Masks = require(Shared:WaitForChild("Masks"))
local Emotes = require(Shared:WaitForChild("Emotes"))
local Prices = require(Shared:WaitForChild("Prices"))
local Rarity = require(Shared:WaitForChild("Rarity"))

local Client = script.Parent.Parent
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local MetaUI = require(script.Parent:WaitForChild("MetaUI"))

local AvatarTab = {}

local category = "MASKS" -- MASKS | SQUAD | MVP
local selectedMask: string? = nil
local selectedEmote: { [string]: string? } = {} -- per category

local CATEGORIES = {
	{ id = "MASKS", name = "MASKS" },
	{ id = "SQUAD", name = "SQUAD" },
	{ id = "MVP", name = "MVP" },
}

local SLOT_COLORS = { SQUAD = Color3.fromHex("3FA873"), MVP = Color3.fromHex("E8B64C") }

local function pills(scene: any, panel: Frame)
	MetaUI.pills(panel, CATEGORIES, category, function(id)
		if id ~= category then
			category = id
			UI.sound(Theme.Sounds.toast, 1.2, 0.3)
			scene.preview.mask(nil, nil)
			scene.refresh()
		end
	end)
end

------------------------------------------------------------------ Masks
local function renderMasks(scene: any, panel: Frame)
	local S = UI.S
	local profile = scene.profile()
	local equipped = if profile then profile.masks.equipped else Masks.Default
	if not selectedMask then
		selectedMask = equipped
	end
	local mask = Masks.ById[selectedMask :: string] or Masks.ById[Masks.Default]
	local isOwned = profile ~= nil and profile.masks.owned[mask.id] == true
	scene.preview.mask(mask.color, mask.shape, mask.id)

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
	local function tilesFor(list: { Masks.Mask }, header: string, order: number)
		MetaUI.header(grid, order, header)
		if #list == 0 then
			return
		end
		local row = MetaUI.row(grid, order + 1, tileW, perRow)
		for i, m in list do
			local own = profile ~= nil and profile.masks.owned[m.id] == true
			local pill: string, pillColor: Color3
			if own then
				pill = if equipped == m.id then "EQUIPPED" else "OWNED"
				pillColor = if equipped == m.id then MetaUI.Green else Theme.Colors.grey
			else
				pill, pillColor = MetaUI.acquisition(m.saleType, m.price or Prices.mask)
			end
			local b = MetaUI.tile(row, {
				name = m.name,
				pill = pill,
				pillColor = pillColor,
				color = Rarity.color(m.rarity), -- tile color is the rarity; the mask's own color is on the icon
				owned = own,
				selected = selectedMask == m.id,
				tag = if own and m.saleType ~= "Direct" then string.upper(m.saleType) else nil,
				tagColor = Theme.Colors.blue,
				icon = "mask",
				iconColor = Color3.fromHex(m.color),
				size = tileW,
				order = i,
			})
			b.Activated:Connect(function()
				selectedMask = m.id
				UI.sound(Theme.Sounds.toast, 1.25, 0.3)
				scene.refresh()
			end)
		end
	end
	tilesFor(ownedList, "OWNED", 1)
	tilesFor(unownedList, "UNOWNED", 10)

	MetaUI.well(card, 1, Rarity.color(mask.rarity), "mask", nil, Color3.fromHex(mask.color))
	MetaUI.heading(
		card,
		2,
		mask.name,
		string.format(
			"%s · %s · %s",
			string.upper(mask.type),
			string.upper(Rarity.name(mask.rarity)),
			if isOwned then "OWNED" else string.upper(mask.saleType)
		),
		if isOwned then Theme.Colors.gold else Theme.Colors.grey
	)
	MetaUI.statRow(card, 10, "Type", string.upper(mask.type), nil)
	MetaUI.statRow(card, 11, "Rarity", string.upper(Rarity.name(mask.rarity)), nil)
	if equipped == mask.id then
		MetaUI.button(card, 20, "EQUIPPED", "disabled", nil)
	elseif isOwned then
		MetaUI.button(card, 20, "EQUIP", "green", function()
			local r = scene.request("equipMask", { maskId = mask.id })
			if r.ok then
				scene.preview.commit()
				scene.refresh()
			end
		end)
	elseif mask.saleType == "Direct" then
		MetaUI.button(card, 20, "UNLOCK - " .. MetaUI.fmtGold(mask.price or Prices.mask), "green", function()
			local r = scene.request("buyMask", { maskId = mask.id })
			if r.ok then
				scene.preview.commit()
				scene.refresh()
			end
		end)
	elseif mask.saleType == "Crate" then
		MetaUI.button(card, 20, "VIEW CRATE", "blue", function()
			scene.toast("CRATE UI · PHASE 4", "click")
		end)
	else
		MetaUI.button(card, 20, "EVENT ONLY", "disabled", nil)
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
	local function tilesFor(list: { Emotes.Emote }, header: string, order: number)
		MetaUI.header(grid, order, header)
		if #list == 0 then
			return
		end
		local row = MetaUI.row(grid, order + 1, tileW, perRow)
		for i, e in list do
			local own = profile ~= nil and profile.emotes ~= nil and profile.emotes.owned[e.id] == true
			local pill: string, pillColor: Color3
			if own then
				pill = if equipped == e.id then "EQUIPPED" else "OWNED"
				pillColor = if equipped == e.id then MetaUI.Green else Theme.Colors.grey
			else
				pill, pillColor = MetaUI.acquisition(e.saleType, e.price or Prices.emote)
			end
			local b = MetaUI.tile(row, {
				name = e.name,
				pill = pill,
				pillColor = pillColor,
				color = Rarity.color(e.rarity),
				owned = own,
				selected = sel == e.id,
				tag = if own and e.saleType ~= "Direct" then string.upper(e.saleType) else nil,
				tagColor = Theme.Colors.blue,
				icon = "class",
				iconColor = Theme.Colors.white,
				glyph = "▶",
				size = tileW,
				order = i,
			})
			b.Activated:Connect(function()
				selectedEmote[category] = e.id
				-- Tap = preview: the emote plays on the avatar right away.
				scene.preview.emote(e.animationId, e.holdSec)
				scene.refresh()
			end)
		end
	end
	tilesFor(ownedList, "OWNED", 1)
	tilesFor(unownedList, "UNOWNED", 10)

	MetaUI.well(card, 1, Rarity.color(emote.rarity), "class", "▶", color)
	MetaUI.heading(
		card,
		2,
		emote.name,
		string.format(
			"%s · %s · %s",
			if slot == "mvp" then "MVP FLEX" else "SQUAD POSE",
			string.upper(Rarity.name(emote.rarity)),
			if isOwned then "OWNED" else string.upper(emote.saleType)
		),
		if isOwned then Theme.Colors.gold else Theme.Colors.grey
	)
	MetaUI.statRow(card, 10, "Rarity", string.upper(Rarity.name(emote.rarity)), nil)
	MetaUI.button(card, 15, "▶ PREVIEW", "blue", function()
		scene.preview.emote(emote.animationId, emote.holdSec)
	end)
	if equipped == emote.id then
		MetaUI.button(card, 20, "EQUIPPED", "disabled", nil)
	elseif isOwned then
		MetaUI.button(card, 20, "EQUIP", "green", function()
			local r = scene.request("equipEmote", { emoteId = emote.id })
			if r.ok then
				scene.refresh()
			end
		end)
	elseif emote.saleType == "Direct" then
		MetaUI.button(card, 20, "UNLOCK - " .. MetaUI.fmtGold(emote.price or Prices.emote), "green", function()
			local r = scene.request("buyEmote", { emoteId = emote.id })
			if r.ok then
				scene.refresh()
			end
		end)
	elseif emote.saleType == "Crate" then
		MetaUI.button(card, 20, "VIEW CRATE", "blue", function()
			scene.toast("CRATE UI · PHASE 4", "click")
		end)
	else
		MetaUI.button(card, 20, "EVENT ONLY", "disabled", nil)
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
	scene.preview.mask(nil, nil)
end

return AvatarTab
