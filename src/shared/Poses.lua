--!strict
-- Brief 6: animation ids for every pose / emote the monetization brief adds (bundle, VIP, battle pass), plus the
-- Shuffle squad pose and the Victory MVP flex. Each is a different public Roblox emote animation so they
-- read as distinct in testing; swap the ids here for the real bespoke animations later (Emotes.lua points at these by
-- key).
-- These must be ANIMATION asset ids (asset type 24), never the catalog EMOTE item ids (asset type 61, the
-- id on the avatar shop page). An emote item is a container holding one Animation; LoadAnimation on the container id
-- fails with "AnimationClip loaded is not valid" and the avatar just stays in its idle (Salute, Stadium, Big Tilt,
-- Shrug, Hello and Call Out all did that). To find an emote's animation id: fetch
-- assetdelivery.roblox.com/v1/asset/?id=<catalog id> (no auth) and read the AnimationId of the Animation inside, then
-- check economy.roblox.com/v2/assets/<id>/details says AssetTypeId 24 and creator Roblox (Id 1). Every id below was
-- checked that way and is a full R15 body animation (all 15 limbs keyed; the "Face" in their asset names is the
-- facial track they also carry).
local Poses = {
	Salute = "rbxassetid://10714389988", -- Roblox Salute emote (catalog 3360689775)
	Stadium = "rbxassetid://10714356920", -- Roblox Stadium emote (catalog 3360686498)
	Tilt = "rbxassetid://10714338461", -- Roblox Tilt emote (catalog 3360692915)
	Shrug = "rbxassetid://10714374484", -- Roblox Shrug emote (catalog 3576968026)
	Hello = "rbxassetid://10714359093", -- Roblox Hello emote (catalog 3576686446)
	CallOut = "rbxassetid://10714395441", -- Roblox Point 2 emote (catalog 3576823880)
	Godlike = "rbxassetid://3337994105", -- Roblox Godlike animation
	Celebrate = "rbxassetid://3338097973", -- Roblox Celebrate animation
	HeroLanding = "rbxassetid://5104344710", -- Roblox hero landing animation
	-- Shuffle used dance2 (the same clip as the Groove flex) and Victory used cheer (the same clip as the
	-- Cheer pose), so each looked like a copy of another emote. Their own animations now:
	Shuffle = "rbxassetid://10714371274", -- Roblox Shuffle emote (catalog 4391208058)
	PowerBlast = "rbxassetid://10714389396", -- Roblox Power Blast emote (catalog 4849497510)
}

return Poses
