--!strict
-- Minigame test props. The server owns the result: a prop's prompt (or the debug panel) opens a session
-- and tells the client to play; the client sends back done / fail / cancel with its miss count; the server
-- checks the time against Config.MinigameMinSec, prints one log line per close and keeps per-session stats.
-- Nothing else happens on success yet; wiring into side jobs comes after review.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Room = require(script.Parent.Room)
local World = require(script.Parent.World)
local Log = require(script.Parent.Log)
local PlayerState = require(script.Parent.PlayerState)

type Session = {
	token: number,
	player: Player,
	name: string,
	tier: number,
	startedAt: number,
	onDone: ((Player) -> ())?, -- side job hook
}

export type OpenOpts = { position: Vector3?, onDone: ((Player) -> ())? }
type Result = { sec: number, misses: number, outcome: string, tier: number }

local Minigames = {}

local sessions: { [number]: Session } = {}
local byPlayer: { [Player]: Session } = {}
local stats: { [string]: { Result } } = {}
local nextToken = 0

local function record(s: Session, outcome: string, misses: number)
	local sec = os.clock() - s.startedAt
	local list = stats[s.name]
	if not list then
		list = {}
		stats[s.name] = list
	end
	table.insert(list, { sec = sec, misses = misses, outcome = outcome, tier = s.tier })
	if outcome == "done" then
		print(string.format("minigame %s tier %d done in %.1fs, %d fails", s.name, s.tier, sec, misses))
	else
		print(string.format("minigame %s tier %d %s %.1fs %d misses", s.name, s.tier, outcome, sec, misses))
	end
end

local function close(s: Session, outcome: string, misses: number)
	sessions[s.token] = nil
	if byPlayer[s.player] == s then
		byPlayer[s.player] = nil
	end
	record(s, outcome, misses)
end

-- Open `name` for a player at the session tier. An open game for that player is cancelled first.
-- opts.position is where the panel closes from when walked away from (default: the yard prop);
-- opts.onDone runs on a validated done (side jobs).
function Minigames.open(player: Player, name: string, opts: OpenOpts?)
	if not table.find(Room.PropNames, name) then
		return
	end
	if not PlayerState.isStanding(PlayerState.get(player)) then
		return -- downed or bled out: no interacting
	end
	local old = byPlayer[player]
	if old then
		close(old, "cancel", 0)
	end
	nextToken += 1
	local s: Session = {
		token = nextToken,
		player = player,
		name = name,
		tier = World.minigameTier,
		startedAt = os.clock(),
		onDone = if opts then opts.onDone else nil,
	}
	sessions[s.token] = s
	byPlayer[player] = s
	local prop = Room.props[name]
	local position = if opts and opts.position then opts.position elseif prop then prop.panel.Position else nil
	Remotes.MinigameStart:FireClient(player, {
		token = s.token,
		name = name,
		tier = s.tier,
		position = position, -- walking away from here closes the panel
	})
	Log.event("Minigame", "%s opened %s at tier %d", player.Name, name, s.tier)
end

local function onResult(player: Player, token: any, outcome: any, misses: any)
	local s = if typeof(token) == "number" then sessions[token] else nil
	if not s or s.player ~= player then
		return
	end
	local out = if outcome == "done" or outcome == "fail" or outcome == "cancel" then outcome else "cancel"
	local m = math.max(0, math.floor(if typeof(misses) == "number" then misses else 0))
	local minSec = Config.MinigameMinSec[s.name] or 0
	if out == "done" and os.clock() - s.startedAt < minSec then
		Log.event(
			"Minigame",
			"%s finished %s faster than MinigameMinSec (%.1fs): counted as a fail",
			player.Name,
			s.name,
			minSec
		)
		out = "fail"
	end
	close(s, out, m)
	if out == "done" then
		local state = PlayerState.get(player)
		state.minigamesDone += 1
		state.dirty = true
		Remotes.Juice:FireClient(player, "MinigameDone", { name = s.name, tier = s.tier })
		if s.onDone then
			s.onDone(player)
		end
	end
end

-- Averages per game for the output window (debug panel: Minigame stats).
function Minigames.printStats()
	print("[GHS Minigame] stats this session:")
	local any = false
	for _, name in Room.PropNames do
		local list = stats[name]
		if not list or #list == 0 then
			continue
		end
		any = true
		local done, fail, cancel, secSum, missSum = 0, 0, 0, 0, 0
		for _, r in list do
			if r.outcome == "done" then
				done += 1
				secSum += r.sec
			elseif r.outcome == "fail" then
				fail += 1
			else
				cancel += 1
			end
			missSum += r.misses
		end
		print(
			string.format(
				"  %-9s plays %2d  done %2d  fail %2d  cancel %2d  avg done %.1fs  avg misses %.1f",
				name,
				#list,
				done,
				fail,
				cancel,
				if done > 0 then secSum / done else 0,
				missSum / #list
			)
		)
	end
	if not any then
		print("  (no plays yet)")
	end
end

function Minigames.init()
	for name, prop in Room.props do
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Prompt"
		prompt.ActionText = "OPEN"
		prompt.ObjectText = string.upper(name)
		prompt.KeyboardKeyCode = Enum.KeyCode.F
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.Parent = prop.panel
		prompt.Triggered:Connect(function(player)
			Minigames.open(player, name)
		end)
	end
	Remotes.MinigameResult.OnServerEvent:Connect(onResult)
	Players.PlayerRemoving:Connect(function(player)
		local s = byPlayer[player]
		if s then
			close(s, "cancel", 0)
		end
	end)
end

return Minigames
