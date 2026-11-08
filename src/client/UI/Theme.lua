--!strict
-- Colors, fonts, sizes and sounds. Layout changes are diffs here, not Studio edits.
local Fonts = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Fonts"))

local Theme = {}

-- Round 19o style pass: near-black panels, tight corners, condensed caps (see Theme.Fonts / Theme.Corner).
Theme.Colors = {
	bg = Color3.fromHex("0B0B0F"),
	panel = Color3.fromHex("15151A"),
	panel2 = Color3.fromHex("1F1F26"),
	text = Color3.fromHex("F2E6C8"),
	textDim = Color3.fromHex("B8AE98"),
	gold = Color3.fromHex("E8B64C"),
	cash = Color3.fromHex("8FE3A1"),
	health = Color3.fromHex("6FD48A"),
	malus = Color3.fromHex("FF9A8C"),
	grey = Color3.fromHex("9BA0A8"),
	red = Color3.fromHex("E8554D"),
	blue = Color3.fromHex("4D9FE8"),
	amber = Color3.fromHex("E8B64C"),
	black = Color3.new(0, 0, 0),
	white = Color3.new(1, 1, 1),
}

-- Font objects (shared/Fonts.lua): set them with `FontFace =`, never `Font =`.
Theme.Fonts = Fonts

-- Corners: UI.corner caps every radius at this (px at the basis) so panels, cards, pills and buttons read sharp;
-- a full round on a square (dots, dials, rings) stays round. Text outlines cap at TextStrokeMax (thick outlines
-- read cartoony on the condensed face).
Theme.Corner = 4
Theme.TextStrokeMax = 1.5
-- Every label's TextSize x this, per font (UI.caps): brings the house fonts back to the old fonts' visual size so
-- nothing reads smaller. Readability first: raise these before shrinking anything.
Theme.TextScale = { display = 1.3, body = 1.25, mono = 1.15 }

-- Pixel sizes at the basis height; UI.S() scales them to the viewport.
-- scaleBasis: the viewport height at which sizes render 1:1. Lower = bigger UI on the same screen.
Theme.Desktop = {
	scaleBasis = 760,
	minScale = 0.6,
	maxScale = 2.2,
	tile = Vector2.new(80, 90),
	tilePad = 10,
	card = Vector2.new(236, 288),
	tracker = 64,
	health = Vector2.new(300, 18),
	callWidth = 420,
	hotkeyChips = true,
}

Theme.Mobile = {
	scaleBasis = 720,
	minScale = 0.5,
	maxScale = 1.2,
	tile = Vector2.new(62, 62),
	tilePad = 8,
	card = Vector2.new(190, 232),
	tracker = 48,
	health = Vector2.new(220, 14),
	callWidth = 340,
	hotkeyChips = false,
}

-- Roblox default library only. Swap ids here.
-- Round 19d polish pass: real assets where the built-in clip read as a placeholder. Every rbxassetid below is a
-- Roblox-licensed library sound (ProSoundEffects or Roblox's own UI pack), checked public and approved; per-key
-- volume trims and pitch variation are Config.SfxGain / Config.SfxPitchJitter. swoosh.wav no longer loads
-- ("Asset is not approved"), so every swap / whoosh was silent before this pass.
Theme.Sounds = {
	shot = "rbxassetid://9114729252", -- Gun Single Shots 11 (was paintball.wav)
	hit = "rbxasset://sounds/electronicpingshort.wav",
	kill = "rbxassetid://15675059323", -- Roblox_UI_Bright_Click: the kill tick (Round 19h: was collide.wav, a loud crash)
	reelTick = "rbxasset://sounds/switch3.wav",
	reelLand = "rbxasset://sounds/button.wav",
	legendary = "rbxasset://sounds/victory.wav",
	take = "rbxasset://sounds/snap.mp3",
	-- Round 19k: picking an upgrade, Jack's pick (sfx_menu_upgrade). Was the snap, a quiet riser, then a shrill power-up.
	upgrade = "rbxassetid://85188753846582",
	reloadOut = "rbxassetid://9113104176", -- Ammo Magazine 1: the mag comes out
	reloadIn = "rbxassetid://9113104208", -- Ammo Magazine 2: the mag seats
	-- Round 24o: one shell into a tube-fed gun (was the snap.mp3 "take", which read as a slap). Verified library
	-- alternatives to audition: 9113104337 Ammo Magazine 3, 9113104335 Ammo Magazine 4 (ProSoundEffects),
	-- 16480551554 Roblox_Pinball_Small_Metal_Click_01 (Roblox), 9116321575 Locking Wrench 15 (ProSoundEffects).
	shellLoad = "rbxassetid://9117396156", -- Pistol Clip 2 (ProSoundEffects): a short metal click
	swap = "rbxassetid://15675024286", -- Roblox_UI_Whoosh_01 (swoosh.wav is blocked)
	crate = "rbxasset://sounds/bass.wav",
	call = "rbxasset://sounds/clickfast.wav",
	hurt = "rbxasset://sounds/uuhhh.mp3",
	deny = "rbxasset://sounds/flashbulb.wav",
	cardFlip = "rbxasset://sounds/clickfast.wav",
	toast = "rbxasset://sounds/button.wav",
	wave = "rbxasset://sounds/bass.wav",
	-- Brief 4 enemies: the Runner's approach wail, the Boomer's fuse beep, the Marksman's laser hum, a plate
	-- or wall crunch, the Grenadier's lob thump.
	runner = "rbxasset://sounds/HalloweenGhost.wav",
	beep = "rbxasset://sounds/electronicpingshort.wav",
	laser = "rbxasset://sounds/switch3.wav",
	crunch = "rbxasset://sounds/collide.wav",
	lob = "rbxasset://sounds/Rocket shot.wav",
	-- Round 19d: world and objective sounds that had none (or borrowed a UI blip).
	body = "rbxassetid://9113480917", -- Body Fall Thud 1: a soft drop under the kill tick (Round 19h: was Body Hits 8)
	cash = "rbxassetid://9113728756", -- Cash Register 5: a cash bag banked
	coins = "rbxassetid://9113849492", -- Coins Or Keys Jingle 6: a gold bag
	glass = "rbxassetid://9114592245", -- Glass Breaks 3: a bank window shatters
	hiss = "rbxassetid://9116496074", -- Medium Pressure Air Release 6: gas floods in
	alarm = "rbxassetid://9113085764", -- Alarm Buzzer 5: the building alarm's horn
	shutter = "rbxassetid://9119207863", -- Sliding Metal Door 2: shutters roll up
	whiz = "rbxassetid://9118168320", -- Rico Bullet Whiz 1: an enemy round past your ear
	click = "rbxassetid://15675032796", -- Roblox_UI_Small_Click
	snip = "rbxassetid://9119064378", -- Round 19e: Shears Metal Snips: a bolt-cutter link goes (was the collide crash)
	-- Round 19e: the lootbox (crate reel, store crate scene and reveals).
	lootTick = "rbxassetid://16480551554", -- Roblox_Pinball_Small_Metal_Click_01: the prize-wheel clicker
	lootDing = "rbxassetid://9126073001", -- Synth Sparkle Bell Tone Ding: the rarity arpeggio notes
	lootShimmer = "rbxassetid://9116418035", -- Magic Tone Falling Shimmer: Rare and up
	lootChimes = "rbxassetid://9119447936", -- Sparkle Bell Tree Wind Chimes: Epic and up
	lootRise = "rbxassetid://9125805579", -- Rising Whoosh Build Up: the lid pops, the reel starts
	lootPop = "rbxassetid://15675055424", -- Roblox_UI_Cute_Pop: the prize flies out
}

return Theme
