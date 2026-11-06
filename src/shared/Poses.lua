--!strict
-- Brief 6: animation ids for every pose / emote the monetization brief adds (bundle, VIP, battle pass). Each is a
-- different public Roblox emote animation so they read as distinct in testing; swap the ids here for the real
-- bespoke animations later (Emotes.lua points at these by key). Verify each id loads in Studio's output: a
-- failed load just leaves the avatar in its idle.
local Poses = {
	Salute = "rbxassetid://3360689775",
	Stadium = "rbxassetid://3360686498",
	Tilt = "rbxassetid://3360692915",
	Shrug = "rbxassetid://3576968026",
	Hello = "rbxassetid://3576686446",
	CallOut = "rbxassetid://3576823880",
	Godlike = "rbxassetid://3337994105",
	Celebrate = "rbxassetid://3338097973",
	HeroLanding = "rbxassetid://5104344710",
}

return Poses
