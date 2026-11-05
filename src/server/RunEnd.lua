--!strict
-- Run end timeline (beats in Config.RunEndBeats), after the RUN OVER beat, in the arena spawn zone.
-- The server lines everyone up (plus dummies up to SquadSize) with a fresh character, cash bag and mask,
-- hangs a KILLS · $CASH tag over each head, rains bills scaled to Total Banked, picks the MVP, then holds
-- the Summary state until a summary button is pressed or SummaryAutoLobbySec passes. Clients run the
-- camera, poses, MVP stamp and the summary panel off the same clock (RunEndUI).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Room = require(script.Parent.Room)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
local PlayerState = require(script.Parent.PlayerState)
local RunStart = require(script.Parent.RunStart)
local Hub = require(script.Parent.Hub)
local Squad = require(script.Parent.Squad)
local Profiles = require(script.Parent.Profiles)

local RunEnd = {}

local effects = Workspace:WaitForChild("Effects")

export type Row = {
	userId: number,
	name: string,
	pose: number,
	poseAnim: string?, -- the player's SQUAD emote (dummies use Config.Poses by index)
	poseHold: number?,
	mvpAnim: string?, -- the player's MVP emote
	maskColor: string,
	kills: number,
	cash: number,
	revives: number,
	downs: number,
	selfRevives: number,
	reviveAll: number,
	jobs: number, -- side jobs + minigames completed
	bags: number, -- bags this player collected
	gold: number, -- GOLD EARNED: the run payout (GDD_7 formula) plus this player's side job Gold
	banked: number, -- TOTAL BANKED: the team's gold bag total, paid in full to everyone
	newBest: boolean, -- the run's wave beat this player's top wave
	newBestBanked: boolean, -- the banked total beat this player's best
	score: number,
	lineIndex: number,
	model: Model?, -- dummies only
	dummy: boolean?,
}

function RunEnd.mvpScore(kills: number, cash: number, revives: number): number
	return kills * Config.MvpKillWeight + cash * Config.MvpCashWeight + revives * Config.MvpReviveWeight
end

-- The stat line under the MVP stamp: whichever term carried the score.
local function statLine(row: Row): string
	local k = row.kills * Config.MvpKillWeight
	local c = row.cash * Config.MvpCashWeight
	local r = row.revives * Config.MvpReviveWeight
	if r > k and r > c then
		return string.format("%d REVIVES", row.revives)
	elseif c > k then
		return string.format("$%d BANKED", row.cash)
	end
	return string.format("%d KILLS", row.kills)
end

local function headTag(char: Model, row: Row)
	local head = char:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "RunEndTag"
	gui.Adornee = head
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromScale(6, 1.6)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.LightInfluence = 0
	gui.Parent = head
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.fromScale(1, 0.5)
	name.Font = Enum.Font.LuckiestGuy
	name.TextScaled = true
	name.Text = string.upper(row.name)
	name.TextColor3 = Color3.fromHex(row.maskColor)
	name.TextStrokeTransparency = 0.3
	name.Parent = gui
	local line = Instance.new("TextLabel")
	line.BackgroundTransparency = 1
	line.Position = UDim2.fromScale(0, 0.5)
	line.Size = UDim2.fromScale(1, 0.5)
	line.Font = Enum.Font.GothamBold
	line.TextScaled = true
	line.Text = string.format("%d KILLS · $%d", row.kills, row.cash)
	line.TextColor3 = Color3.fromHex("F2E6C8")
	line.TextStrokeTransparency = 0.3
	line.Parent = gui
end

-- A cash bag welded to the left hand.
local function cashBag(char: Model)
	local hand = (char:FindFirstChild("LeftHand") or char:FindFirstChild("Left Arm")) :: BasePart?
	if not hand then
		return
	end
	local bag = Instance.new("Part")
	bag.Name = "CashBag"
	bag.Size = Vector3.new(1.3, 1.5, 0.9)
	bag.Color = Color3.fromRGB(28, 28, 32)
	bag.Material = Enum.Material.Fabric
	bag.CanCollide = false
	bag.CanQuery = false
	bag.Massless = true
	bag.CFrame = hand.CFrame * CFrame.new(0, -1.1, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = bag
	weld.Parent = bag
	bag.Parent = char
	local stripe = Instance.new("Part")
	stripe.Name = "Stripe"
	stripe.Size = Vector3.new(1.35, 0.3, 0.95)
	stripe.Color = Color3.fromHex("8FE3A1")
	stripe.Material = Enum.Material.Neon
	stripe.CanCollide = false
	stripe.CanQuery = false
	stripe.Massless = true
	stripe.CFrame = bag.CFrame * CFrame.new(0, 0.2, 0)
	local weld2 = Instance.new("WeldConstraint")
	weld2.Part0 = bag
	weld2.Part1 = stripe
	weld2.Parent = stripe
	stripe.Parent = char
end

-- Line-up dressing for any character: anchored at its slot, mask on, bag, tag.
local function dress(char: Model, cf: CFrame, row: Row)
	local root = char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		char:PivotTo(cf)
		root.Anchored = true
	end
	local head = char:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		head.Color = Color3.fromHex(row.maskColor)
	end
	cashBag(char)
	headTag(char, row)
end

local function rain(center: Vector3, count: number, seconds: number)
	local bills: { BasePart } = {}
	-- Spread the drop over `seconds`: a batch every tick, ~20 ticks a second.
	local batch = math.max(1, math.floor(count / math.max(seconds * 20, 1)))
	for i = 1, count do
		local bill = Instance.new("Part")
		bill.Name = "Bill"
		bill.Size = Vector3.new(1.2, 0.05, 0.6)
		bill.Color = Color3.fromRGB(80, 190, 110)
		bill.Material = Enum.Material.SmoothPlastic
		bill.CanQuery = false
		bill.CFrame = CFrame.new(
			center + Vector3.new((math.random() - 0.5) * 18, 12 + math.random() * 6, (math.random() - 0.5) * 8)
		) * CFrame.Angles(math.random() * 3, math.random() * 3, math.random() * 3)
		bill.AssemblyLinearVelocity = Vector3.new((math.random() - 0.5) * 4, 0, (math.random() - 0.5) * 4)
		bill.Parent = effects
		table.insert(bills, bill)
		if i % batch == 0 then
			task.wait(seconds * batch / math.max(count, 1))
		end
	end
	task.delay(seconds + 4, function()
		for _, b in bills do
			if b.Parent then
				b:Destroy()
			end
		end
	end)
end

-- Dummy rows carry plausible numbers under the best real player, so the layout reads like a 4-man run.
local function dummyRow(d: Squad.Dummy, i: number, k: number, topKills: number, topCash: number): Row
	local kills = math.floor(topKills * (0.4 + math.random() * 0.5))
	local cash = math.floor(topCash * (0.4 + math.random() * 0.5))
	local revives = math.random(0, 2)
	return {
		userId = -k,
		name = d.name,
		pose = d.pose,
		poseAnim = nil,
		poseHold = nil,
		mvpAnim = nil,
		maskColor = d.maskColor,
		kills = kills,
		cash = cash,
		revives = revives,
		downs = math.random(0, 2),
		selfRevives = 0,
		reviveAll = 0,
		jobs = math.random(0, 3),
		bags = math.random(0, 3),
		gold = World.payoutBase(),
		banked = World.banked,
		newBest = false,
		newBestBanked = false,
		score = RunEnd.mvpScore(kills, cash, revives),
		lineIndex = i,
		model = d.model,
		dummy = true,
	}
end

-- Payout at the final summary (GDD_7): base = (sum over cleared waves + GoldPerObjective x objectives) x
-- DiffGoldMult, plus the side job Gold already granted per job, plus the team's TOTAL BANKED in full.
-- Lands in the profile at once, with the top wave, the top banked and the lifetime stats. Players who left
-- before the summary earn nothing.
local function payout(p: Player, s: PlayerState.State, base: number, banked: number): (number, boolean, boolean)
	local earned = base + s.gold
	local profile = s.profile or Profiles.get(p)
	local newBest = false
	local newBestBanked = false
	if profile then
		local key = World.partyKey()
		local top = profile.topWave[key] or 0
		if World.wave > top then
			profile.topWave[key] = World.wave
			newBest = true
		end
		local topB = profile.topBanked[key] or 0
		if banked > topB then
			profile.topBanked[key] = banked
			newBestBanked = banked > 0
		end
		profile.stats.kills += s.kills
		profile.stats.matchesPlayed += 1
		profile.stats.bagsCollected += s.bags
		profile.stats.goldBanked += banked
		Profiles.grantPayout(p, earned + banked, "run payout")
	end
	Log.event(
		"Payout",
		"%s earned %d gold (base %d + %d side job) + %d banked, wave %d%s%s",
		p.Name,
		earned,
		base,
		s.gold,
		banked,
		World.wave,
		if newBest then ", NEW PERSONAL BEST" else "",
		if newBestBanked then ", NEW BEST BANKED" else ""
	)
	return earned, newBest, newBestBanked
end

-- Yields through the sequence and the summary. Returns "again" | "lobby".
function RunEnd.play(): string
	Hub.clearArena()
	local players = RunStart.roster()
	local dummyCount = RunStart.dummyCount()
	local n = #players + dummyCount
	local beats = Config.RunEndBeats
	local base = World.payoutBase()
	local banked = World.banked

	-- Real rows and totals.
	local rows: { Row } = {}
	local total = 0
	local topKills, topCash = 0, 0
	for i, p in players do
		local s = PlayerState.get(p)
		local earned, newBest, newBestBanked = payout(p, s, base, banked)
		rows[i] = {
			userId = p.UserId,
			name = p.Name,
			pose = s.pose,
			poseAnim = PlayerState.squadEmote(s).animationId,
			poseHold = PlayerState.squadEmote(s).holdSec,
			mvpAnim = PlayerState.mvpEmote(s).animationId,
			maskColor = s.maskColor,
			kills = s.kills,
			cash = s.cashCollected,
			revives = s.revives,
			downs = s.downs,
			selfRevives = s.selfRevives,
			reviveAll = s.reviveAllUsed,
			jobs = s.jobsDone + s.minigamesDone,
			bags = s.bags,
			gold = earned,
			banked = banked,
			newBest = newBest,
			newBestBanked = newBestBanked,
			score = RunEnd.mvpScore(s.kills, s.cashCollected, s.revives),
			lineIndex = i,
		}
		total += s.cashCollected
		topKills = math.max(topKills, s.kills)
		topCash = math.max(topCash, s.cashCollected)
	end
	if topKills == 0 and topCash == 0 then
		-- Debug skip with nothing earned: give the dummies something to show.
		topKills = World.wave * 10
		topCash = topKills * 20
	end

	-- Everyone gets a fresh character standing in the line, anchored, bag and mask on. Dummies fill the squad.
	local line = {}
	for i = 1, n do
		line[i] = RunStart.lineCFrame(i, n)
	end
	for i, p in players do
		local s = PlayerState.get(p)
		s.downed = false
		s.bledOut = false
		s.pendingSpawnCFrame = line[i]
		p:LoadCharacter()
	end
	for i, p in players do
		task.spawn(function()
			local char = p.Character or p.CharacterAdded:Wait()
			char:WaitForChild("HumanoidRootPart", 5)
			char:WaitForChild("Humanoid", 5)
			task.wait(0.1)
			dress(char, line[i], rows[i])
		end)
	end
	local dummies = Squad.spawn(dummyCount, #players + 1, function(slot)
		return line[slot]
	end)
	for k, d in dummies do
		local i = #players + k
		rows[i] = dummyRow(d, i, k, topKills, topCash)
		dress(d.model, line[i], rows[i])
	end

	local mvp: Row? = nil
	for _, row in rows do
		if not mvp or row.score > mvp.score then
			mvp = row -- rows are in join order, so a tie keeps the earlier joiner
		end
	end
	local rainCount = math.clamp(math.floor(total * Config.CashRainPerBanked), 0, Config.CashRainMax)
	local gold = base

	local startedAt = Workspace:GetServerTimeNow()
	World.fireRun("RunEndBegin", {
		startedAt = startedAt,
		players = rows,
		mvp = if mvp
			then {
				userId = mvp.userId,
				name = mvp.name,
				statLine = statLine(mvp),
				pose = mvp.pose,
				mvpAnim = mvp.mvpAnim,
				model = mvp.model,
			}
			else nil,
		totalBanked = total, -- cash collected by the crew (the bill rain scales on it)
		banked = banked, -- TOTAL BANKED (gold bags), the headline
		gold = gold,
		wave = World.wave,
		heat = World.heat,
		line = line,
		beats = beats,
		rainSec = Config.CashRainSec,
		rainCount = rainCount,
		mvpOrbitSec = Config.MvpOrbitSec,
		autoLobbySec = Config.SummaryAutoLobbySec,
		countUpSec = Config.SummaryCountUpSec,
	})
	Log.event(
		"Run",
		"run end: wave %d, cash collected $%d, banked %d, payout base %d gold, %d bills, MVP %s (%s)",
		World.wave,
		total,
		banked,
		gold,
		rainCount,
		if mvp then mvp.name else "none",
		if mvp then statLine(mvp) else ""
	)

	task.wait(beats.rain)
	local sum = Vector3.zero
	for _, cf in line do
		sum += cf.Position
	end
	local center = if n > 0 then sum / n else Room.arenaSpawn
	task.spawn(rain, center, rainCount, Config.CashRainSec)
	task.wait(math.max(0, beats.summary - beats.rain))

	World.state = "Summary"
	World.summaryChoice = nil
	PlayerState.markAllDirty()
	local t0 = os.clock()
	while not World.summaryChoice and os.clock() - t0 < Config.SummaryAutoLobbySec do
		task.wait(0.1)
	end
	return World.summaryChoice or "lobby"
end

function RunEnd.init()
	Remotes.SummaryChoice.OnServerEvent:Connect(function(player: Player, choice: any)
		if World.state ~= "Summary" or World.summaryChoice or not World.isInParty(player) then
			return
		end
		World.summaryChoice = if choice == "again" then "again" else "lobby"
		Log.event("Run", "%s pressed %s", player.Name, if choice == "again" then "PLAY AGAIN" else "TO LOBBY")
	end)
end

return RunEnd
