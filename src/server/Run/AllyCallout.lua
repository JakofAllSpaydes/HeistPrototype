--!strict
-- Ally callouts (brief 5, widened in Round 16): the short radio lines a teammate "sends" when something happens to
-- them or they do something big, shown on the other players' screens in the crew-call shell with that player's
-- headshot and name. The line pool is Shared/Callouts.lua; a random line per event, never the same one twice in
-- a row. Teammates only (the speaker already has their own feedback), except events listed in Callouts.Everyone.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(script.Parent.SlotRemotes)
local Callouts = require(Shared.Callouts)
local World = require(script.Parent.World)
local Log = require(script.Parent.Parent.Log)
local Profiles = require(script.Parent.Parent.Profiles)

local AllyCallout = {}

local lastLine: { [string]: number } = {}

-- `...` fills the line's %s / %d slots in order (Revive Everybody passes the speaker's name).
function AllyCallout.send(speaker: Player, event: string, ...: any)
	local pool = Callouts.Lines[event]
	if not pool or #pool == 0 then
		return
	end
	local i = math.random(#pool)
	if #pool > 1 and i == lastLine[event] then
		i = (i % #pool) + 1
	end
	lastLine[event] = i
	local line = pool[i]
	if select("#", ...) > 0 then
		local ok, formatted = pcall(string.format, line, ...)
		if ok then
			line = formatted
		end
	end
	local gold = Callouts.Gold[event] == true
	local everyone = Callouts.Everyone[event] == true
	local sp = Profiles.get(speaker)
	local payload = {
		userId = speaker.UserId,
		name = speaker.Name,
		vip = sp ~= nil and sp.vip.active == true, -- brief 6: the VIP tag on crew callouts
		event = event,
		line = line,
		gold = gold,
	}
	for _, p in World.runAudience() do
		if everyone or p ~= speaker then
			Remotes.Juice:FireClient(p, "AllyCallout", payload)
		end
	end
	Log.event("Callout", "%s: %s", speaker.Name, line)
end

return AllyCallout
