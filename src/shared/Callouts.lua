--!strict
-- Ally callouts (brief 5): the short radio lines a downed, revived or bled-out player sends their teammates,
-- shown in the crew-call shell with the player's headshot. The server picks a random line per event, never the
-- same one twice in a row for that event, and sends it to teammates only (Revive Everybody goes to everyone).
local Callouts = {}

Callouts.Lines = {
	downed = { "I'M DOWN, HELP!", "Someone get me up!", "Down over here!" },
	revived = { "Thanks, I owe you.", "Back in it." },
	bledOut = { "I'm out. Finish the job." },
	reviveAll = { "%s brought everyone back." }, -- %s: the player's name
}

-- Frame color per event: red for the crew in trouble, gold for Revive Everybody.
Callouts.Gold = { reviveAll = true }

return Callouts
