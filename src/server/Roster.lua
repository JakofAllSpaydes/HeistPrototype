--!strict
-- The scoreboard's data: one row per party member (level, class, state, kills, cash collected, bags, jobs,
-- downs, revives, MVP score) in MVP order, plus the team totals, rebuilt every RosterSyncSec into
-- World.roster, which StateSync carries. Nothing else reads player state for the scoreboard.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local World = require(script.Parent.World)
local PlayerState = require(script.Parent.PlayerState)
local RunEnd = require(script.Parent.RunEnd)

local Roster = {}

export type Row = {
	userId: number,
	name: string,
	level: number,
	classId: string,
	state: string, -- standing | downed | spectating
	kills: number,
	cash: number,
	bags: number,
	jobs: number,
	downs: number,
	revives: number,
	score: number,
}

export type View = { rows: { Row }, cash: number, banked: number, survivedSec: number, vault: boolean }

function Roster.build(): View?
	if not World.inRunCycle() or #World.party == 0 then
		return nil
	end
	local rows: { Row } = {}
	local cash = 0
	for _, player in World.partyPlayers() do
		local s = PlayerState.get(player)
		local profile = s.profile
		local state = if s.bledOut then "spectating" elseif s.downed then "downed" else "standing"
		table.insert(rows, {
			userId = player.UserId,
			name = player.Name,
			level = if profile then profile.level else 1,
			classId = PlayerState.classOf(s),
			state = state,
			kills = s.kills,
			cash = s.cashCollected,
			bags = s.bags,
			jobs = s.jobsDone + s.minigamesDone,
			downs = s.downs,
			revives = s.revives,
			score = RunEnd.mvpScore(s.kills, s.cashCollected, s.revives),
		})
		cash += s.cashCollected
	end
	table.sort(rows, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.userId < b.userId
	end)
	return {
		rows = rows,
		cash = cash,
		banked = World.banked,
		survivedSec = math.floor(World.survivedSec()),
		vault = World.vaultLive,
	}
end

function Roster.init()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < Config.RosterSyncSec then
			return
		end
		acc = 0
		local view = Roster.build()
		World.roster = view
		if view then
			PlayerState.markAllDirty()
		end
	end)
end

return Roster
