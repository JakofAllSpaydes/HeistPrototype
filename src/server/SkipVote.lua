--!strict
-- Intermission skip vote. V / the VOTES pill casts a vote for this intermission; AUTO SKIP votes for you
-- every intermission. GameLoop polls World.skipVotePassed() while it waits. Votes clear at each state change.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local World = require(script.Parent.World)
local PlayerState = require(script.Parent.PlayerState)
local Log = require(script.Parent.Log)

local SkipVote = {}

local function announce(player: Player, on: boolean, auto: boolean)
	World.fireRun("SkipVote", {
		userId = player.UserId,
		name = player.Name,
		on = on,
		auto = auto,
		votes = World.skipVoteCount(),
		needed = World.skipNeeded(),
		intermission = World.state == "Intermission",
	})
end

function SkipVote.reset()
	World.skipVotes = {}
	PlayerState.markAllDirty()
end

function SkipVote.init()
	Remotes.VoteSkip.OnServerEvent:Connect(function(player: Player, on: any)
		if World.state ~= "Intermission" then
			return
		end
		local want = on == true
		if (World.skipVotes[player.UserId] == true) == want then
			return
		end
		World.skipVotes[player.UserId] = if want then true else nil
		PlayerState.markAllDirty()
		announce(player, want, false)
		Log.event(
			"Wave",
			"%s %s skip (%d/%d)",
			player.Name,
			if want then "voted to" else "withdrew",
			World.skipVoteCount(),
			World.skipNeeded()
		)
	end)
	Remotes.SetAutoSkip.OnServerEvent:Connect(function(player: Player, on: any)
		local want = on == true
		if (World.autoSkip[player.UserId] == true) == want then
			return
		end
		World.autoSkip[player.UserId] = if want then true else nil
		PlayerState.markAllDirty()
		announce(player, want, true)
		Log.event("Wave", "%s auto skip %s", player.Name, if want then "on" else "off")
	end)
	Players.PlayerRemoving:Connect(function(player)
		World.skipVotes[player.UserId] = nil
		World.autoSkip[player.UserId] = nil
	end)
end

return SkipVote
