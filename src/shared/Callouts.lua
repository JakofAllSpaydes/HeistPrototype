--!strict
-- Ally callouts (brief 5, Round 16): the short radio lines a teammate sends, shown in the crew-call shell with the
-- player's headshot and name (AllyCallout.lua on the server picks and sends them). Rewrite freely. %s / %d slots are
-- filled by the event (named per line below).
local Callouts = {}

Callouts.Lines = {
	-- The crew in trouble.
	downed = { "I'M DOWN, HELP!", "Someone get me up!", "Down over here!" },
	revived = { "Thanks, I owe you.", "Back in it." },
	bledOut = { "I'm out. Finish the job." },
	reviveAll = { "%s brought everyone back." }, -- %s: the player's name
	-- Round 16: big moments a teammate pulled off.
	bossKill = { "%s is down. Last hit's mine!", "Got the last hit on %s!" }, -- %s: the boss name
	legendary = { "LEGENDARY %s out of the crate!", "Look what I pulled: LEGENDARY %s." }, -- %s: the gun
	multiKill = { "%d down in one blast!", "That's %d with one go." }, -- %d: kills
	masteryUp = { "%s MASTERY %s. Getting good with this.", "Just hit %s MASTERY %s." }, -- %s: gun / class, %s: tier
}

-- Frame color per event: red for the crew in trouble, gold for the big moments.
Callouts.Gold = { reviveAll = true, bossKill = true, legendary = true, multiKill = true, masteryUp = true }
-- Sent to the speaker too (everything else goes to teammates only).
Callouts.Everyone = { reviveAll = true }

return Callouts
