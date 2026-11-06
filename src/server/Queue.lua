--!strict
-- Queue zones and Create Match (GDD_7 Hub -> Queue Zones, minus the teleport: MatchMode "local").
-- Walk into an empty zone -> the Create Match card; CREATE locks the settings and makes you the owner;
-- others join by walking in, leave by walking out; a full party starts at once, otherwise
-- QueueCountdownSec from creation; a party of 1 starts on CREATE. Owner leaves -> next member owns;
-- zone empties -> reset. Start -> World.party is the run's player set and GameLoop takes it from there.
-- Local-mode rule: while the party is in the arena the zone reads MATCH IN PROGRESS and refuses entry.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Enemies = require(Shared.Enemies)
local Room = require(script.Parent.Room)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
local PlayerState = require(script.Parent.PlayerState)

type Billboard = { gui: BillboardGui, title: TextLabel, slots: { Frame }, status: TextLabel, toast: TextLabel }

type Zone = {
	index: number,
	room: Room.Zone,
	-- idle: nobody inside | creating: one player has the card open | open: party formed, counting down |
	-- inProgress: the party is in the arena (local mode)
	phase: string,
	creator: Player?,
	owner: Player?,
	members: { Player },
	settings: World.PartySettings,
	createdAt: number, -- server time
	startsAt: number, -- server time the countdown ends (open phase)
	inside: { [Player]: boolean },
	board: Billboard?,
	toastToken: number,
	graceUntil: number, -- os.clock: exits are ignored until then (characters landing on the pad after PLAY AGAIN)
}

local Queue = {}

local zones: { Zone } = {}
local zoneOf: { [Player]: Zone } = {} -- the zone a player is standing in
local lastSent: { [Player]: string } = {}
local BLUE = Color3.fromHex("4D9FE8")
local GOLD = Color3.fromHex("E8B64C")
local TEXT = Color3.fromHex("F2E6C8")
local GREY = Color3.fromHex("9BA0A8")
local DARK = Color3.fromHex("1A1A20")

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function defaultSettings(): World.PartySettings
	return {
		partySize = Config.MaxPartySize,
		mapId = Config.QueueMaps[1].id,
		difficultyId = Config.QueueDifficulties[1].id,
	}
end

local function mapName(id: string): string
	for _, m in Config.QueueMaps do
		if m.id == id then
			return m.name
		end
	end
	return string.upper(id)
end

local function diffName(id: string): string
	for _, d in Config.QueueDifficulties do
		if d.id == id then
			return d.name
		end
	end
	return string.upper(id)
end

------------------------------------------------------------------ Billboard
local function buildBoard(z: Zone)
	local anchor = z.room.billboardAnchor or z.room.gate
	if not anchor then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "QueueBoard"
	gui.Adornee = anchor
	gui.AlwaysOnTop = false
	gui.Size = UDim2.fromScale(16, 4.4)
	gui.StudsOffset = Vector3.new(0, 1.5, 0)
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.Parent = anchor
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = DARK
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.12, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = BLUE
	stroke.Thickness = 3
	stroke.Parent = frame
	local function label(y: number, h: number, size: number, color: Color3): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.03, y)
		l.Size = UDim2.fromScale(0.94, h)
		l.Font = Enum.Font.LuckiestGuy
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = ""
		l.Parent = frame
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = size
		c.Parent = l
		return l
	end
	local title = label(0.04, 0.3, 40, TEXT)
	local slotRow = Instance.new("Frame")
	slotRow.BackgroundTransparency = 1
	slotRow.Position = UDim2.fromScale(0, 0.36)
	slotRow.Size = UDim2.fromScale(1, 0.24)
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
	local status = label(0.62, 0.22, 30, GOLD)
	local toast = label(0.82, 0.16, 20, Color3.fromHex("8FE3A1"))
	z.board = { gui = gui, title = title, slots = slots, status = status, toast = toast }
end

local function paintBoard(z: Zone)
	local b = z.board
	if not b then
		return
	end
	local s = z.settings
	if z.phase == "idle" or z.phase == "creating" then
		b.title.Text = "QUEUE ZONE " .. z.index
		b.status.Text = if z.phase == "creating" then "SETTING UP A MATCH…" else "WALK IN TO CREATE A MATCH"
		b.status.TextColor3 = GREY
		for _, slot in b.slots do
			slot.Visible = false
		end
		return
	end
	b.title.Text = string.format("%s · %s", mapName(s.mapId), diffName(s.difficultyId))
	for i, slot in b.slots do
		slot.Visible = i <= s.partySize
		local filled = i <= #z.members
		slot.BackgroundColor3 = if filled then GOLD else GREY
		slot.BackgroundTransparency = if filled then 0 else 0.6
	end
	if z.phase == "inProgress" then
		b.status.Text = "MATCH IN PROGRESS"
		b.status.TextColor3 = Color3.fromHex("E8554D")
	else
		local left = math.max(0, math.ceil(z.startsAt - now()))
		b.status.Text = string.format("STARTING IN %d · %d / %d", left, #z.members, s.partySize)
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
	b.toast.Text = text
	task.delay(2.5, function()
		if z.toastToken == token and b.toast.Parent then
			b.toast.Text = ""
		end
	end)
end

------------------------------------------------------------------ Client view
-- What a player sees of the queue: nothing, the Create Match card, or the compact party card.
local function viewFor(player: Player): any
	local z = zoneOf[player]
	local member: Zone? = nil
	for _, zone in zones do
		if table.find(zone.members, player) then
			member = zone
			break
		end
	end
	local zone = member or z
	if not zone then
		return { card = nil }
	end
	local state = PlayerState.get(player)
	local profile = state.profile
	local names = {}
	for _, m in zone.members do
		local mp = PlayerState.get(m).profile
		table.insert(names, { userId = m.UserId, name = m.Name, level = if mp then mp.level else 1 })
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
		settings = zone.settings,
		maps = Config.QueueMaps,
		difficulties = Config.QueueDifficulties,
		maxPartySize = Config.MaxPartySize,
		members = names,
		owner = if zone.owner then zone.owner.UserId else nil,
		isOwner = zone.owner == player,
		startsAt = zone.startsAt,
		countdownSec = Config.QueueCountdownSec,
		topWave = if profile then (profile.topWave[topKey] or 0) else 0,
		-- Per difficulty on this map, so the Create Match bonus row follows the segment (Round 16).
		topWaves = (function()
			local out = {}
			for _, d in Config.QueueDifficulties do
				out[d.id] = if profile then (profile.topWave[zone.settings.mapId .. ":" .. d.id] or 0) else 0
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
		"%s|%s|%d|%d|%s|%.1f",
		tostring(view.card),
		tostring(view.phase),
		#(view.members or {}),
		tonumber(view.zone) or 0,
		tostring(view.isOwner),
		tonumber(view.startsAt) or 0
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
	paintBoard(z)
	for _, m in had do
		send(m, true)
	end
	for p in z.inside do
		send(p, true)
	end
	Log.event("Queue", "zone %d reset (%s)", z.index, reason)
end

local function stepOut(z: Zone, player: Player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if char and root and root:IsA("BasePart") then
		char:PivotTo(Room.outsideZone(z.room, root.Position.X))
	end
end

local function startParty(z: Zone, reason: string)
	if z.phase ~= "open" or #z.members == 0 then
		return
	end
	if World.state ~= "Hub" or World.runRequested then
		return -- another zone's party is already going (one arena in local mode)
	end
	local ids = {}
	for _, m in z.members do
		table.insert(ids, m.UserId)
	end
	World.party = ids
	World.partySettings = table.clone(z.settings)
	World.runRequested = true
	z.phase = "inProgress"
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
		"zone %d: match starting (%s) with %d/%d: %s",
		z.index,
		reason,
		#z.members,
		z.settings.partySize,
		table.concat(
			(function()
				local names = {}
				for _, m in z.members do
					table.insert(names, m.Name)
				end
				return names
			end)(),
			", "
		)
	)
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
		string.format("%s JOINED THE PARTY (%d/%d)", string.upper(player.Name), #z.members, z.settings.partySize)
	)
	sendMembers(z)
	Log.event("Queue", "zone %d: %s joined (%d/%d)", z.index, player.Name, #z.members, z.settings.partySize)
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
	Log.event("Queue", "zone %d: %s left (%s), %d left", z.index, player.Name, reason, #z.members)
	if #z.members == 0 then
		reset(z, "party empty")
		send(player, true)
		return
	end
	if z.owner == player then
		z.owner = z.members[1]
		memberToast(z, string.format("%s NOW OWNS THE PARTY", string.upper(z.owner.Name)))
		Log.event("Queue", "zone %d: ownership to %s", z.index, z.owner.Name)
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
		-- Local-mode rule: one arena, so the zone is closed until the run ends.
		Remotes.Juice:FireClient(player, "QueueToast", { text = "MATCH IN PROGRESS" })
		stepOut(z, player)
		return
	end
	if z.phase == "idle" then
		z.phase = "creating"
		z.creator = player
		z.settings = defaultSettings()
		paintBoard(z)
		send(player, true)
		Log.event("Queue", "zone %d: %s is creating a match", z.index, player.Name)
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
		for _, m in Config.QueueMaps do
			if m.id == raw.mapId then
				s.mapId = m.id
			end
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
	z.createdAt = now()
	z.startsAt = z.createdAt + Config.QueueCountdownSec
	Log.event(
		"Queue",
		"zone %d: %s created a match (%s · %s · %d), countdown %ds",
		z.index,
		player.Name,
		s.mapId,
		s.difficultyId,
		s.partySize,
		Config.QueueCountdownSec
	)
	tryJoin(z, player)
	for other in z.inside do
		if other ~= player and z.phase == "open" then
			tryJoin(z, other)
		end
	end
	if z.phase == "open" and s.partySize == 1 then
		startParty(z, "party of one")
	end
	paintBoard(z)
	sendMembers(z)
end

-- X on the card: close it and step out of the zone.
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

------------------------------------------------------------------ Run lifecycle hooks (GameLoop)
-- The summary closed. PLAY AGAIN re-forms the same party on the pad with the same settings and a fresh
-- countdown; TO LOBBY (or the auto) returns everyone to the hub spawn and reopens the zone.
function Queue.onRunEnded(choice: string?)
	local party = World.partyPlayers()
	local z: Zone? = nil
	for _, zone in zones do
		if zone.phase == "inProgress" then
			z = zone
			break
		end
	end
	if not z then
		z = zones[1]
	end
	if not z then
		return
	end
	if choice == "again" and #party > 0 then
		z.phase = "open"
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
			state.pendingSpawnCFrame = CFrame.new(x, Config.FloorTop + 3, pad.Position.Z + 2)
			z.inside[p] = true
			zoneOf[p] = z
		end
		paintBoard(z)
		Log.event(
			"Queue",
			"zone %d: PLAY AGAIN re-formed the party (%d), countdown %ds",
			z.index,
			#party,
			Config.QueueCountdownSec
		)
		if #party >= z.settings.partySize then
			-- Full party again: start as soon as the characters have landed.
			task.delay(2, function()
				if z and z.phase == "open" then
					startParty(z, "play again, party full")
				end
			end)
		else
			sendMembers(z)
		end
	else
		reset(z, "run ended")
	end
end

-- Debug: start now. In an open party -> start it; otherwise a party of just this player.
function Queue.forceStart(player: Player)
	for _, z in zones do
		if table.find(z.members, player) and z.phase == "open" then
			startParty(z, "forced")
			return
		end
	end
	local z = zoneOf[player] or zones[1]
	if not z or z.phase == "inProgress" then
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

function Queue.zoneCount(): number
	return #zones
end

function Queue.init()
	for _, rz in Room.zones do
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
			inside = {},
			board = nil,
			toastToken = 0,
			graceUntil = 0,
		}
		buildBoard(z)
		paintBoard(z)
		table.insert(zones, z)
	end
	if #zones ~= Config.QueueZoneCount then
		Log.event("Queue", "map has %d queue zones, Config.QueueZoneCount is %d", #zones, Config.QueueZoneCount)
	end

	Remotes.QueueAction.OnServerEvent:Connect(function(player: Player, action: any, args: any)
		if action == "create" then
			create(player, args)
		elseif action == "cancel" then
			cancel(player)
		elseif action == "leave" then
			local z = zoneOf[player]
			if z then
				leave(z, player, "left")
				stepOut(z, player)
			end
		elseif action == "refresh" then
			send(player, true)
		elseif action == "play" then
			-- PLAY: straight onto the nearest open pad; the presence loop opens the card (or joins the party).
			local state = PlayerState.get(player)
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not char or not root or not root:IsA("BasePart") or not PlayerState.isStanding(state) then
				return
			end
			if World.inRunCycle() and World.isInParty(player) then
				return
			end
			local best: Zone? = nil
			local bestDist = math.huge
			for _, z in zones do
				if z.phase == "inProgress" then
					continue
				end
				local d = (z.room.pad.Position - root.Position).Magnitude
				if d < bestDist then
					bestDist = d
					best = z
				end
			end
			if not best then
				Remotes.Juice:FireClient(player, "QueueToast", { text = "MATCH IN PROGRESS" })
				return
			end
			local pad = best.room.pad
			char:PivotTo(CFrame.new(pad.Position.X, Config.FloorTop + 3, pad.Position.Z + 2))
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
			if z.phase == "inProgress" then
				-- Members are in the arena; only keep outsiders off the pad.
				for _, player in Players:GetPlayers() do
					if World.isInParty(player) then
						continue
					end
					local char = player.Character
					local root = char and char:FindFirstChild("HumanoidRootPart")
					if root and root:IsA("BasePart") and Room.insideZone(z.room, root.Position) then
						if not z.inside[player] then
							z.inside[player] = true
							onEnter(z, player)
						end
					else
						z.inside[player] = nil
					end
				end
				continue
			end
			local grace = os.clock() < z.graceUntil
			for _, player in Players:GetPlayers() do
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
					onExit(z, player)
				end
			end
			if z.phase == "open" and z.startsAt > 0 and now() >= z.startsAt then
				startParty(z, "countdown")
			end
		end
		if boardAcc >= 0.5 then
			boardAcc = 0
			for _, z in zones do
				if z.phase == "open" then
					paintBoard(z)
				end
			end
		end
	end)
end

return Queue
