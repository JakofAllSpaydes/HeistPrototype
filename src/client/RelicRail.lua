--!strict
-- Brief 13: relics on the Create Match card. While a map tile with relics is highlighted, a side rail stands to the
-- right of the card (the card keeps its size): `THE BANK · RELICS 1/4`, the map's relic masks stacked, owned ones in
-- colour with their names, the rest dark silhouettes reading ???, the starter marked FIRST CRATE. Tapping one shows
-- its name (owned) or DROPS FROM GUN CRATES (unowned) on the rail's last line. The Arena (no relics) shows no rail.
-- Phones: no rail; a `RELICS 1/4` chip on the map's tile opens the same list as a sheet. Pad: RB hops between the
-- card and the rail (the queue context's tabs hook); the sheet has its own GamepadNav context (B closes it).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local Relics = require(Shared:WaitForChild("Relics"))
local Maps = require(Shared:WaitForChild("Maps"))
local Lines = require(Shared:WaitForChild("CrewCall"):WaitForChild("Lines"))

local Client = script.Parent
local ClientState = require(Client:WaitForChild("ClientState"))
local UI = require(Client:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(Client:WaitForChild("UI"):WaitForChild("Theme"))
local ModelIcon = require(Client:WaitForChild("UI"):WaitForChild("ModelIcon"))
local GamepadNav = require(Client:WaitForChild("GamepadNav"))

local RelicRail = {}

local RELIC = Rarity.color(Rarity.Relic)

local function owned(id: string): boolean
	local sync = ClientState.sync
	local p = sync and sync.profile
	return p ~= nil and p.relics ~= nil and p.relics.owned ~= nil and p.relics.owned[id] == true
end

local function countOwned(mapId: string): (number, number)
	local set = Relics.forMap(mapId)
	local n = 0
	for _, r in set do
		if owned(r.id) then
			n += 1
		end
	end
	return n, #set
end

-- The relic list (rail or sheet): header, one row per relic, the info line. Returns the first row (pad focus).
local function list(parent: Frame, mapId: string, rowH: number): TextButton?
	local S = UI.S
	for _, c in parent:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local set = Relics.forMap(mapId)
	local have, total = countOwned(mapId)
	UI.text({
		Name = "Header",
		Text = string.format(Lines.relic.railHeader, Maps.get(mapId).name, have, total),
		FontFace = Theme.Fonts.display,
		TextSize = S(16),
		TextColor3 = RELIC,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, S(22)),
		LayoutOrder = 0,
		Parent = parent,
	})
	local info = UI.text({
		Name = "Info",
		Text = "",
		FontFace = Theme.Fonts.display,
		TextSize = S(13),
		TextColor3 = Theme.Colors.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, S(32)),
		LayoutOrder = 99,
		Parent = parent,
	})
	local first: TextButton? = nil
	for i, r in set do
		local own = owned(r.id)
		local row = UI.button({
			Name = "Relic_" .. r.id,
			Text = "",
			BackgroundColor3 = Theme.Colors.panel,
			Size = UDim2.new(1, 0, 0, rowH),
			LayoutOrder = i,
			Parent = parent,
		})
		UI.corner(row, S(6))
		UI.stroke(row, if own then RELIC else Theme.Colors.panel2, S(if own then 2 else 1), if own then 0 else 0.3)
		local well = UI.frame({
			BackgroundColor3 = Theme.Colors.bg,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, S(5), 0.5, 0),
			Size = UDim2.fromOffset(rowH - S(10), rowH - S(10)),
			Parent = row,
		})
		UI.corner(well, S(5))
		local icon = ModelIcon.mask(well, r.id, UDim2.fromScale(1, 1), { state = if own then "normal" else "shadow" })
		icon.Position = UDim2.fromScale(0, 0)
		local textX = rowH + S(2)
		UI.text({
			Text = if own then string.upper(r.name) else Lines.relic.unknown,
			FontFace = Theme.Fonts.display,
			TextSize = S(17),
			TextColor3 = if own then Theme.Colors.text else Theme.Colors.grey,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.new(0, textX, 0, S(6)),
			Size = UDim2.new(1, -textX - S(6), 0, S(22)),
			Parent = row,
		})
		if r.id == Config.StarterRelic then
			UI.text({
				Text = Lines.relic.firstCrate,
				FontFace = Theme.Fonts.display,
				TextSize = S(11),
				TextColor3 = RELIC,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.new(0, textX, 0, S(28)),
				Size = UDim2.new(1, -textX - S(6), 0, S(14)),
				Parent = row,
			})
		end
		row.Activated:Connect(function()
			UI.punch(row, 0.96, 0.15)
			UI.sound(Theme.Sounds.toast, 1.25, 0.3)
			info.Text = if own then string.upper(r.name) .. " · " .. Lines.relic.tag else Lines.relic.dropsFrom
			info.TextColor3 = if own then RELIC else Theme.Colors.textDim
		end)
		first = first or row
	end
	return first
end

------------------------------------------------------------------ The card's rail (one at a time)
type Rail = { gui: ScreenGui, panel: Frame, frame: Frame?, mapId: string?, first: TextButton?, sheet: Frame? }
local rail: Rail? = nil

local function hasRelics(mapId: string?): boolean
	return Config.RelicsEnabled and mapId ~= nil and #Relics.forMap(mapId) > 0
end

-- The highlighted map changed (or the card opened): the rail follows it, gone for a map with none.
function RelicRail.select(mapId: string?)
	local r = rail
	if not r or not r.gui.Parent or ClientState.isMobile then
		return
	end
	r.mapId = mapId
	local f = r.frame
	if not hasRelics(mapId) then
		if f then
			f.Visible = false
		end
		return
	end
	local S = UI.S
	if not f then
		local nf = UI.frame({
			Name = "RelicRail",
			BackgroundColor3 = Theme.Colors.bg,
			BackgroundTransparency = 0.04,
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.fromOffset(S(220), 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = r.gui,
		})
		UI.corner(nf, S(10))
		UI.stroke(nf, RELIC, S(2), 0.2)
		UI.pad(nf, S(10), S(10), S(10), S(10))
		UI.list(nf, Enum.FillDirection.Vertical, S(6))
		r.frame = nf
		f = nf
	end
	local frame = f :: Frame
	-- Right of the card, centred on it (the card's own size never changes).
	local p = r.panel
	frame.Position = UDim2.new(0.5, p.AbsoluteSize.X / 2 + S(12), 0.5, 0)
	frame.Visible = true
	r.first = list(frame, mapId :: string, S(56))
	UI.punch(frame, 1.04, 0.2)
end

-- Phones: the RELICS n/4 chip on a map's tile; tapping it opens the list as a sheet.
local function openSheet(mapId: string)
	local r = rail
	if not r then
		return
	end
	local S = UI.S
	if r.sheet then
		r.sheet:Destroy()
	end
	local dim = UI.button({
		Name = "RelicSheet",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Colors.black,
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Parent = r.gui,
	})
	local sheet = UI.frame({
		BackgroundColor3 = Theme.Colors.bg,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(S(300), 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 21,
		Active = true,
		Parent = dim,
	})
	UI.corner(sheet, S(10))
	UI.stroke(sheet, RELIC, S(2), 0.2)
	UI.pad(sheet, S(12), S(12), S(12), S(12))
	UI.list(sheet, Enum.FillDirection.Vertical, S(6))
	UI.mobileGrow(sheet, true)
	local body = UI.frame({
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = sheet,
	})
	UI.list(body, Enum.FillDirection.Vertical, S(6))
	local first = list(body, mapId, S(56))
	local close: () -> ()
	local closeBtn = UI.button({
		Name = "Close",
		Text = "X",
		FontFace = Theme.Fonts.display,
		TextSize = S(18),
		TextColor3 = Theme.Colors.white,
		BackgroundColor3 = Theme.Colors.red,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, S(6), 0, -S(6)),
		Size = UDim2.fromOffset(S(36), S(36)),
		ZIndex = 25,
		Parent = sheet,
	})
	UI.corner(closeBtn, S(6))
	close = function()
		if dim.Parent then
			dim:Destroy()
		end
		r.sheet = nil
		GamepadNav.pop("relicSheet")
	end
	closeBtn.Activated:Connect(close)
	dim.Activated:Connect(close)
	r.sheet = dim
	UI.punch(sheet, 1.06, 0.2)
	GamepadNav.push("relicSheet", {
		root = function(): GuiObject?
			return if dim.Parent then sheet else nil
		end,
		default = function(): GuiObject?
			return first
		end,
		back = close,
	})
end

-- The card opened: remember it, build the rail for its highlighted map, put the chips on the phone's tiles.
function RelicRail.attach(gui: ScreenGui, panel: Frame, mapCards: { TextButton }, liveMaps: { any }, mapId: string?)
	rail = { gui = gui, panel = panel, frame = nil, mapId = mapId, first = nil, sheet = nil }
	if not Config.RelicsEnabled then
		return
	end
	if ClientState.isMobile then
		local S = UI.S
		for i, card in mapCards do
			local m = liveMaps[i]
			if not m or not hasRelics(m.id) then
				continue
			end
			local have, total = countOwned(m.id)
			local chip = UI.button({
				Name = "RelicChip",
				Text = string.format(Lines.relic.chip, have, total),
				FontFace = Theme.Fonts.display,
				TextSize = S(13),
				TextColor3 = Theme.Colors.bg,
				BackgroundColor3 = RELIC,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -2, 0, 2),
				Size = UDim2.fromOffset(S(84), S(22)),
				ZIndex = 5,
				Parent = card,
			})
			UI.corner(chip, S(4))
			local id = m.id
			chip.Activated:Connect(function()
				UI.punch(chip, 0.94, 0.15)
				openSheet(id)
			end)
		end
		return
	end
	-- Wait a frame so the card has its size before the rail lines up beside it.
	task.defer(RelicRail.select, mapId)
end

-- Pad: RB (the queue context's tabs hook) hops from the card into the rail and back.
function RelicRail.init()
	GamepadNav.register("queue", {
		tabs = function(_dir: number)
			local r = rail
			if not r or not r.gui.Parent then
				return
			end
			local f = r.frame
			local sel = game:GetService("GuiService").SelectedObject
			local inRail = f ~= nil and sel ~= nil and sel:IsDescendantOf(f)
			if not inRail and f and f.Visible and r.first then
				GamepadNav.focus(r.first)
			else
				local create = r.panel:FindFirstChild("CreateParty", true) :: GuiObject?
				local target = create
				if not target then
					for _, d in r.panel:GetDescendants() do
						if d:IsA("TextButton") and d.Visible then
							target = d
							break
						end
					end
				end
				if target then
					GamepadNav.focus(target)
				end
			end
		end,
	})
end

return RelicRail
