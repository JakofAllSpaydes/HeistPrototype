--!strict
-- Queue pads and Create Match (GDD_7 Hub -> Queue Zones, minus the teleport: MatchMode "local").
-- Brief 8: every pad holds its own party (the Round 11 zone logic, one instance per pad) and starts it on the run
-- slot of its map (Runs), so parties on different maps play at once. Walk onto an empty pad -> the Create Match
-- card; CREATE locks the settings and makes you the owner; others join by walking in, leave by walking out; a full
-- party starts at once, otherwise QueueCountdownSec from creation; a party of 1 starts on CREATE. Owner leaves ->
-- next member owns; pad empties -> reset. A party whose map is busy (MapInstancesPerMap) waits on its pad with
-- MAP BUSY · <name> IS INSIDE and starts by itself when the map frees (MapBusyAutoStart). While its party is in a
-- run the pad reads MATCH IN PROGRESS · WAVE N and refuses entry.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Fonts = require(Shared.Fonts)
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Enemies = require(Shared.Enemies)
local Maps = require(Shared.Maps)
local Room = require(script.Parent.Run.Room)
local World = require(script.Parent.Run.World)
local Runs = require(script.Parent.Runs)
local HubMap = require(script.Parent.HubMap)
local Log = require(script.Parent.Log)
local PlayerState = require(script.Parent.PlayerState)

type Billboard = { gui: BillboardGui, title: TextLabel, slots: { Frame }, status: TextLabel, toast: TextLabel }

type Zone = {
	index: number,
	room: Room.Zone,
	-- idle: nobody inside | creating: one player has the card open | open: party formed, counting down (or, with
	-- `waiting`, holding for a busy map) | inProgress: the party is in its run
	phase: string,
	creator: Player?,
	owner: Player?,
	members: { Player },
	settings: World.PartySettings,
	createdAt: number, -- server time
	startsAt: number, -- server time the countdown ends (open phase)
	waiting: boolean, -- the countdown is done but the map is busy
	slot: Runs.Slot?, -- the run slot this pad's party is playing on (inProgress)
	inside: { [Player]: boolean },
	board: Billboard?,
	toastToken: number,
	graceUntil: number, -- os.clock: exits are ignored until then (characters landing on the pad after PLAY AGAIN)
}

local Queue = {}

local zones: { Zone } = {}
local zoneOf: { [Player]: Zone } = {} -- the pad a player is standing on
local lastSent: { [Player]: string } = {}
local GOLD = Color3.fromHex("E8B64C")
local TEXT = Color3.fromHex("F2E6C8")
local GREY = Color3.fromHex("9BA0A8")
local RED = Color3.fromHex("E8554D")
local DARK = Color3.fromHex("1A1A20")

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function defaultSettings(): World.PartySettings
	return {
		partySize = Config.MaxPartySize,
		mapId = Maps.pickable(Config.DefaultMap),
		difficultyId = Config.QueueDifficulties[1].id,
	}
end

local function mapName(id: string): string
	local m = Maps.ById[id]
	return if m then m.name else string.upper(id)
end

local function diffName(id: string): string
	for _, d in Config.QueueDifficulties do
		if d.id == id then
			return d.name
		end
	end
	return string.upper(id)
end

-- The map a party really plays: THE BANK falls back to the arena when its nodes are not playable.
local function runMap(mapId: string): string
	local id = Maps.pickable(mapId)
	if id == "TheBank" then
		for _, s in Runs.forMap(id) do
			local loader = s.folder:FindFirstChild("MapLoader")
			if loader and not (require(loader :: ModuleScript) :: any).playable() then
				Log.event(
					"Queue",
					"THE BANK is not playable (node errors, MapLoaderStrict): this party plays the arena"
				)
				return "Arena"
			end
		end
	end
	return id
end

local function names(list: { Player }): string
	local out = {}
	for _, m in list do
		table.insert(out, m.Name)
	end
	return table.concat(out, ", ")
end

------------------------------------------------------------------ Billboard
local function buildBoard(z: Zone)
	local anchor = z.room.billboardAnchor or z.room.gate or z.room.pad
	if not anchor then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "QueueBoard"
	gui.Adornee = anchor
	gui.AlwaysOnTop = false
	-- Round 30d: floating text (no panel): wider and taller so the words read from across the hall.
	gui.Size = UDim2.fromScale(Config.PadBoardWidth, Config.PadBoardWidth * 0.42) -- studs
	gui.StudsOffset = Vector3.new(0, if anchor == z.room.pad then Config.PadBoardLift else 0, 0)
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.Parent = anchor
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = gui
	local function label(y: number, h: number, size: number, color: Color3): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.03, y)
		l.Size = UDim2.fromScale(0.94, h)
		l.FontFace = Fonts.display
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = ""
		l.Parent = frame
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = size
		c.Parent = l
		-- A heavy dark outline so the words stand on their own against the hall.
		local outline = Instance.new("UIStroke")
		outline.Color = DARK
		outline.Thickness = 3
		outline.Transparency = 0.05
		outline.Parent = l
		return l
	end
	local title = label(0, 0.46, 160, GOLD)
	local slotRow = Instance.new("Frame")
	slotRow.BackgroundTransparency = 1
	slotRow.Position = UDim2.fromScale(0, 0.48)
	slotRow.Size = UDim2.fromScale(1, 0.16)
	slotRow.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.02, 0)
	layout.Parent = slotRow
	local slots = {}
	for i = 1, Config.MaxPartySize do
		local s = Instance.new("Frame")
		s.BackgroundColor3 = GREY
		s.BackgroundTransparency = 0.6
		s.BorderSizePixel = 0
		s.Size = UDim2.fromScale(0.09, 0.9)
		s.LayoutOrder = i
		s.Parent = slotRow
		local sc = Instance.new("UICorner")
		sc.CornerRadius = UDim.new(0.5, 0)
		sc.Parent = s
		local r = Instance.new("UIAspectRatioConstraint")
		r.AspectRatio = 1
		r.Parent = s
		slots[i] = s
	end
	local status = label(0.64, 0.22, 80, TEXT)
	local toast = label(0.86, 0.14, 40, Color3.fromHex("8FE3A1"))
	z.board = { gui = gui, title = title, slots = slots, status = status, toast = toast }
end

local function busyLine(mapId: string): string
	local who = Runs.busyBy(mapId) or "A CREW"
	return string.upper(string.format(Config.MapBusyText, who))
end

local function paintBoard(z: Zone)
	local b = z.board
	if not b then
		return
	end
	local s = z.settings
	if z.phase == "idle" or z.phase == "creating" then
		-- Round 30d: the pad reads as the way into a run, its crew count under it (no pad numbers).
		b.title.Text = Config.PadBoardTitle
		b.status.Text = if z.phase == "creating"
			then "SETTING UP A MATCH…"
			else string.format("0/%d CREW", Config.MaxPartySize)
		b.status.TextColor3 = if z.phase == "creating" then GREY else TEXT
		for _, slot in b.slots do
			slot.Visible = false
		end
		return
	end
	b.title.Text = string.upper(string.format("%s · %s", mapName(s.mapId), diffName(s.difficultyId)))
	for i, slot in b.slots do
		slot.Visible = i <= s.partySize
		local filled = i <= #z.members
		slot.BackgroundColor3 = if filled then GOLD else GREY
		slot.BackgroundTransparency = if filled then 0 else 0.6
	end
	if z.phase == "inProgress" then
		local slot = z.slot
		local w = slot and slot.World
		local wave = if w and (w.state == "Wave" or w.state == "Intermission" or w.state == "Dealer")
			then w.wave
			else nil
		b.status.Text = if wave then string.format("MATCH IN PROGRESS · WAVE %d", wave) else "MATCH IN PROGRESS"
		b.status.TextColor3 = RED
	elseif z.waiting then
		b.status.Text = busyLine(s.mapId)
		b.status.TextColor3 = RED
	else
		local left = math.max(0, math.ceil(z.startsAt - now()))
		b.status.Text = string.format("STARTING IN %d · %d/%d CREW", left, #z.members, s.partySize)
		b.status.TextColor3 = GOLD
	end
end

local function boardToast(z: Zone, text: string)
	local b = z.board
	if not b then
		return
	end
	z.toastToken += 1
	local token = z.toastToken
	b.toast.Text = string.upper(text)
	task.delay(2.5, function()
		if z.toastToken == token and b.toast.Parent then
			b.toast.Text = ""
		end
	end)
end

------------------------------------------------------------------ Client view
-- In some pad's party (open, waiting or in its run).
local function partyOf(player: Player): Zone?
	for _, z in zones do
		if table.find(z.members, player) then
			return z
		end
	end
	return nil
end

-- What a player sees of the queue: nothing, the Create Match card, or the compact party card.
local function viewFor(player: Player): any
	local member = partyOf(player)
	local zone = member or zoneOf[player]
	if not zone then
		return { card = nil }
	end
	local state = PlayerState.get(player)
	local profile = state.profile
	local list = {}
	for _, m in zone.members do
		local mp = PlayerState.get(m).profile
		table.insert(list, {
			userId = m.UserId,
			name = m.Name,
			level = if mp then mp.level else 1,
			vip = mp ~= nil and mp.vip.active == true, -- brief 6
		})
	end
	local card: string? = nil
	if zone.phase == "creating" and zone.creator == player then
		card = "create"
	elseif (zone.phase == "open" or zone.phase == "inProgress") and member then
		card = "party"
	end
	local topKey = zone.settings.mapId .. ":" .. zone.settings.difficultyId
	return {
		card = card,
		zone = zone.index,
		phase = zone.phase,
		waiting = zone.waiting,
		busyText = if zone.waiting then busyLine(zone.settings.mapId) else nil,
		settings = zone.settings,
		maps = Maps.live(),
		difficulties = Config.QueueDifficulties,
		maxPartySize = Config.MaxPartySize,
		members = list,
		owner = if zone.owner then zone.owner.UserId else nil,
		isOwner = zone.owner == player,
		startsAt = zone.startsAt,
		countdownSec = Config.QueueCountdownSec,
		topWave = if profile then (profile.topWave[topKey] or 0) else 0,
		-- Per map:difficulty, so the Create Match bonus row follows the map tile and the segment (Round 16, brief 7).
		topWaves = (function()
			local out = {}
			for _, m in Maps.live() do
				for _, d in Config.QueueDifficulties do
					local key = m.id .. ":" .. d.id
					out[key] = if profile then (profile.topWave[key] or 0) else 0
				end
			end
			return out
		end)(),
		goldMult = Enemies.difficulty(zone.settings.difficultyId).goldMult or 1,
		modifiers = "NONE",
	}
end

local function send(player: Player, force: boolean?)
	local view = viewFor(player)
	-- Cheap change detection so the 10 Hz loop only sends on changes.
	local key = string.format(
		"%s|%s|%d|%d|%s|%.1f|%s",
		tostring(view.card),
		tostring(view.phase),
		#(view.members or {}),
		tonumber(view.zone) or 0,
		tostring(view.isOwner),
		tonumber(view.startsAt) or 0,
		tostring(view.busyText)
	)
	if not force and lastSent[player] == key then
		return
	end
	lastSent[player] = key
	Remotes.QueueState:FireClient(player, view)
end

local function sendMembers(z: Zone)
	for _, m in z.members do
		send(m, true)
	end
end

local function memberToast(z: Zone, text: string)
	boardToast(z, text)
	for _, m in z.members do
		Remotes.Juice:FireClient(m, "QueueToast", { text = text })
	end
end

------------------------------------------------------------------ Party logic
local function reset(z: Zone, reason: string)
	local had = z.members
	z.phase = "idle"
	z.creator = nil
	z.owner = nil
	z.members = {}
	z.settings = defaultSettings()
	z.startsAt = 0
	z.createdAt = 0
	z.waiting = false
	z.slot = nil
	paintBoard(z)
	for _, m in had do
		send(m, true)
	end
	for p in z.inside do
		send(p, true)
	end
	Log.event("Queue", "pad %d reset (%s)", z.index, reason)
end

local function stepOut(z: Zone, player: Player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if char and root and root:IsA("BasePart") then
		char:PivotTo(Room.outsideZone(z.room, root.Position.X))
	end
end

-- The countdown is done (or the party is full): hand the party to a free slot of its map, or wait for one.
local function startParty(z: Zone, reason: string)
	if z.phase ~= "open" or #z.members == 0 then
		return
	end
	local mapId = runMap(z.settings.mapId)
	local slot = Runs.freeSlot(mapId)
	if not slot then
		if not z.waiting then
			z.waiting = true
			paintBoard(z)
			sendMembers(z)
			Log.event("Queue", "pad %d busy-wait: %s is in use (%s inside)", z.index, mapId, Runs.busyBy(mapId) or "?")
		end
		return
	end
	local ids = {}
	for _, m in z.members do
		table.insert(ids, m.UserId)
	end
	local w = slot.World
	w.partySettings = table.clone(z.settings)
	w.partySettings.mapId = mapId
	w.party = ids
	w.runRequested = true
	z.phase = "inProgress"
	z.waiting = false
	z.slot = slot
	z.startsAt = 0
	paintBoard(z)
	sendMembers(z)
	for p in z.inside do
		if not table.find(z.members, p) then
			send(p, true)
		end
	end
	Log.event(
		"Queue",
		"pad %d start %s %s (%s) with %d/%d: %s",
		z.index,
		mapId,
		z.settings.difficultyId,
		reason,
		#z.members,
		z.settings.partySize,
		names(z.members)
	)
	-- A pad still waiting on this map now names the new crew inside.
	for _, other in zones do
		if other ~= z and other.waiting then
			paintBoard(other)
			sendMembers(other)
		end
	end
end

local function tryJoin(z: Zone, player: Player)
	if table.find(z.members, player) then
		return
	end
	if #z.members >= z.settings.partySize then
		Remotes.Juice:FireClient(player, "QueueToast", { text = "PARTY FULL" })
		stepOut(z, player)
		return
	end
	table.insert(z.members, player)
	if not z.owner then
		z.owner = player
	end
	paintBoard(z)
	memberToast(
		z,
		string.format("%s JOINED THE CREW (%d/%d)", string.upper(player.Name), #z.members, z.settings.partySize)
	)
	sendMembers(z)
	Log.event("Queue", "pad %d: %s joined (%d/%d)", z.index, player.Name, #z.members, z.settings.partySize)
	if #z.members >= z.settings.partySize then
		startParty(z, "party full")
	end
end

local function leave(z: Zone, player: Player, reason: string)
	local i = table.find(z.members, player)
	if not i then
		return
	end
	table.remove(z.members, i)
	Log.event("Queue", "pad %d: %s left (%s), %d left", z.index, player.Name, reason, #z.members)
	if #z.members == 0 then
		reset(z, "party empty")
		send(player, true)
		return
	end
	if z.owner == player then
		z.owner = z.members[1]
		memberToast(z, string.format("%s NOW OWNS THE PARTY", string.upper(z.owner.Name)))
		Log.event("Queue", "pad %d: ownership to %s", z.index, z.owner.Name)
	else
		memberToast(
			z,
			string.format("%s LEFT THE PARTY (%d/%d)", string.upper(player.Name), #z.members, z.settings.partySize)
		)
	end
	paintBoard(z)
	sendMembers(z)
	send(player, true)
end

local function onEnter(z: Zone, player: Player)
	if z.phase == "inProgress" then
		-- The pad's party is in its run: the pad is closed until it ends.
		Remotes.Juice:FireClient(player, "QueueToast", { text = "MATCH IN PROGRESS" })
		stepOut(z, player)
		return
	end
	local other = partyOf(player)
	if other and other ~= z then
		Remotes.Juice:FireClient(player, "QueueToast", { text = "YOU'RE ALREADY IN A CREW" })
		stepOut(z, player)
		return
	end
	if z.phase == "idle" then
		z.phase = "creating"
		z.creator = player
		z.settings = defaultSettings()
		paintBoard(z)
		send(player, true)
		Log.event("Queue", "pad %d: %s is creating a match", z.index, player.Name)
	elseif z.phase == "creating" then
		Remotes.Juice:FireClient(player, "QueueToast", { text = "A MATCH IS BEING SET UP · WAIT HERE" })
		send(player, true)
	elseif z.phase == "open" then
		tryJoin(z, player)
	end
end

local function onExit(z: Zone, player: Player)
	if z.phase == "creating" and z.creator == player then
		-- reset() only tells members and whoever is still on the pad; the creator has already stepped off,
		-- so send the cleared view by hand or the Create Party card stays open.
		reset(z, "creator walked out")
		send(player, true)
		return
	end
	if z.phase == "open" then
		leave(z, player, "walked out")
	end
	send(player, true)
end

-- CREATE from the card: lock the settings, make the creator the owner, pull in everyone standing on the pad.
local function create(player: Player, raw: any)
	local z = zoneOf[player]
	if not z or z.phase ~= "creating" or z.creator ~= player then
		return
	end
	local s = defaultSettings()
	if typeof(raw) == "table" then
		local size = tonumber(raw.partySize)
		if size then
			s.partySize = math.clamp(math.floor(size), 1, Config.MaxPartySize)
		end
		if typeof(raw.mapId) == "string" then
			s.mapId = Maps.pickable(raw.mapId)
		end
		for _, d in Config.QueueDifficulties do
			if d.id == raw.difficultyId then
				s.difficultyId = d.id
			end
		end
	end
	z.settings = s
	z.phase = "open"
	z.creator = nil
	z.owner = player
	z.members = {}
	z.waiting = false
	z.createdAt = now()
	z.startsAt = z.createdAt + Config.QueueCountdownSec
	Log.event(
		"Queue",
		"pad %d create %s %s owner %s (party of %d, countdown %ds)",
		z.index,
		s.mapId,
		s.difficultyId,
		player.Name,
		s.partySize,
		Config.QueueCountdownSec
	)
	tryJoin(z, player)
	for other in z.inside do
		if other ~= player and z.phase == "open" and not partyOf(other) then
			tryJoin(z, other)
		end
	end
	if z.phase == "open" and s.partySize == 1 then
		startParty(z, "party of one")
	end
	paintBoard(z)
	sendMembers(z)
end

-- X on the card: close it and step out of the pad.
local function cancel(player: Player)
	local z = zoneOf[player]
	if not z then
		return
	end
	if z.phase == "creating" and z.creator == player then
		reset(z, "cancelled")
	end
	stepOut(z, player)
end

------------------------------------------------------------------ Run lifecycle hooks (Run/Main)
-- A slot's summary closed. PLAY AGAIN re-forms the same party on its pad with the same settings and a fresh
-- countdown; TO LOBBY (or the auto) returns everyone to the hub spawn and reopens the pad.
function Queue.onRunEnded(slotId: string, choice: string?, party: { Player })
	local z: Zone? = nil
	for _, zone in zones do
		if zone.phase == "inProgress" and zone.slot and zone.slot.id == slotId then
			z = zone
			break
		end
	end
	if z then
		z.slot = nil
		if choice == "again" and #party > 0 then
			z.phase = "open"
			z.waiting = false
			z.members = party
			z.owner = party[1]
			z.inside = {}
			z.createdAt = now()
			z.startsAt = z.createdAt + Config.QueueCountdownSec
			z.graceUntil = os.clock() + 3
			local pad = z.room.pad
			for i, p in party do
				local state = PlayerState.get(p)
				local x = pad.Position.X + (i - (#party + 1) / 2) * 3
				state.pendingSpawnCFrame = CFrame.new(x, pad.Position.Y + 3, pad.Position.Z)
				z.inside[p] = true
				zoneOf[p] = z
			end
			paintBoard(z)
			Log.event(
				"Queue",
				"pad %d: PLAY AGAIN re-formed the party (%d), countdown %ds",
				z.index,
				#party,
				Config.QueueCountdownSec
			)
			if #party >= z.settings.partySize then
				-- Full party again: start as soon as the characters have landed.
				local again = z
				task.delay(2, function()
					if again.phase == "open" then
						startParty(again, "play again, party full")
					end
				end)
			else
				sendMembers(z)
			end
		else
			reset(z, "run ended")
		end
	end
	-- A slot just freed: a party waiting for that map starts now (or counts down again).
	for _, other in zones do
		if other.phase == "open" and other.waiting then
			if Config.MapBusyAutoStart then
				startParty(other, "map freed")
			elseif not Runs.busyBy(runMap(other.settings.mapId)) then
				other.waiting = false
				other.startsAt = now() + Config.QueueCountdownSec
				paintBoard(other)
				sendMembers(other)
			end
		end
	end
end

-- Debug: start now. In an open party -> start it; otherwise a party of just this player on the pad it stands on
-- (or the first idle one).
function Queue.forceStart(player: Player)
	local mine = partyOf(player)
	if mine and mine.phase == "open" then
		startParty(mine, "forced")
		return
	end
	local z = zoneOf[player]
	if not z or (z.phase ~= "idle" and z.phase ~= "creating") then
		z = nil
		for _, zone in zones do
			if zone.phase == "idle" then
				z = zone
				break
			end
		end
	end
	if not z then
		return
	end
	reset(z, "forced start")
	z.phase = "open"
	z.settings = defaultSettings()
	z.settings.partySize = 1
	z.owner = player
	z.members = { player }
	z.createdAt = now()
	z.startsAt = now()
	startParty(z, "forced solo")
end

-- Debug Force pad N start: the pad's open party starts now (a busy map still waits).
function Queue.forcePad(index: number)
	local z = zones[index]
	if z and z.phase == "open" then
		z.startsAt = now()
		startParty(z, "forced")
	end
end

function Queue.zoneCount(): number
	return #zones
end

function Queue.init()
	-- Brief 8: the warehouse's four pads (QueuePad nodes); the old yard's zones only without the hub.
	local source = if HubMap.view and #HubMap.view.pads > 0 then HubMap.view.pads else Room.zones
	for _, rz in source do
		local z: Zone = {
			index = rz.index,
			room = rz,
			phase = "idle",
			creator = nil,
			owner = nil,
			members = {},
			settings = defaultSettings(),
			createdAt = 0,
			startsAt = 0,
			waiting = false,
			slot = nil,
			inside = {},
			board = nil,
			toastToken = 0,
			graceUntil = 0,
		}
		buildBoard(z)
		paintBoard(z)
		table.insert(zones, z)
	end
	Log.event("Queue", "%d queue pad%s", #zones, if #zones == 1 then "" else "s")

	Remotes.QueueAction.OnServerEvent:Connect(function(player: Player, action: any, args: any)
		if action == "create" then
			create(player, args)
		elseif action == "cancel" then
			cancel(player)
		elseif action == "leave" then
			local z = partyOf(player) or zoneOf[player]
			if z and z.phase ~= "inProgress" then
				leave(z, player, "left")
				stepOut(z, player)
			end
		elseif action == "refresh" then
			send(player, true)
		elseif action == "play" then
			-- PLAY: straight onto the nearest open pad (no party, or a party with room); the presence loop opens
			-- the card (or joins the party).
			local state = PlayerState.get(player)
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not char or not root or not root:IsA("BasePart") or not PlayerState.isStanding(state) then
				return
			end
			if Runs.inRunCycle(player) then
				return
			end
			local best: Zone? = partyOf(player)
			if not best then
				local bestDist = math.huge
				for _, z in zones do
					local open = z.phase == "idle" or (z.phase == "open" and #z.members < z.settings.partySize)
					if not open then
						continue
					end
					local d = (z.room.pad.Position - root.Position).Magnitude
					if d < bestDist then
						bestDist = d
						best = z
					end
				end
			end
			if not best then
				Remotes.Juice:FireClient(player, "QueueToast", { text = "EVERY PAD IS IN USE" })
				return
			end
			local pad = best.room.pad
			char:PivotTo(CFrame.new(pad.Position.X, pad.Position.Y + 3, pad.Position.Z))
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		for _, z in zones do
			z.inside[player] = nil
			if z.phase == "creating" and z.creator == player then
				reset(z, "creator left the server")
			elseif z.phase == "open" then
				leave(z, player, "left the server")
			end
		end
		zoneOf[player] = nil
		lastSent[player] = nil
	end)

	-- Presence: who is standing on which pad (10 Hz), plus the countdowns and the board refresh.
	local acc = 0
	local boardAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		boardAcc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		for _, z in zones do
			local grace = os.clock() < z.graceUntil
			for _, player in Players:GetPlayers() do
				if Runs.inRunCycle(player) then
					continue -- in a run: not on the hub floor
				end
				local state = PlayerState.get(player)
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if not root or not root:IsA("BasePart") then
					continue -- no character yet (loading): neither an enter nor an exit
				end
				local standing = PlayerState.isStanding(state)
				local pos = root.Position
				local wasInside = z.inside[player] == true
				local isInside = standing and Room.insideZone(z.room, pos, if wasInside then 1 else 0)
				if isInside and not wasInside then
					z.inside[player] = true
					zoneOf[player] = z
					onEnter(z, player)
				elseif wasInside and not isInside and not grace then
					z.inside[player] = nil
					if zoneOf[player] == z then
						zoneOf[player] = nil
					end
					if z.phase ~= "inProgress" then
						onExit(z, player)
					end
				end
			end
			if z.phase == "open" and z.startsAt > 0 and now() >= z.startsAt and not z.waiting then
				startParty(z, "countdown")
			end
		end
		if boardAcc >= 0.5 then
			boardAcc = 0
			for _, z in zones do
				if z.phase == "open" or z.phase == "inProgress" then
					paintBoard(z)
				end
			end
		end
	end)
end

return Queue
