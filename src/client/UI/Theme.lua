--!strict
-- Colors, fonts, sizes and sounds. Layout changes are diffs here, not Studio edits.
local Theme = {}

Theme.Colors = {
	bg = Color3.fromHex("101014"),
	panel = Color3.fromHex("1A1A20"),
	panel2 = Color3.fromHex("23232B"),
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

Theme.Fonts = {
	display = Enum.Font.LuckiestGuy, -- stand-in for Lilita One
	body = Enum.Font.GothamBold,
	mono = Enum.Font.RobotoMono,
}

-- Pixel sizes at the basis height; UI.S() scales them to the viewport.
-- scaleBasis: the viewport height at which sizes render 1:1. Lower = bigger UI on the same screen.
Theme.Desktop = {
	scaleBasis = 760,
	minScale = 0.6,
	maxScale = 2.2,
	tile = Vector2.new(92, 104),
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
Theme.Sounds = {
	shot = "rbxasset://sounds/paintball.wav",
	hit = "rbxasset://sounds/electronicpingshort.wav",
	kill = "rbxasset://sounds/collide.wav",
	reelTick = "rbxasset://sounds/switch3.wav",
	reelLand = "rbxasset://sounds/button.wav",
	legendary = "rbxasset://sounds/victory.wav",
	take = "rbxasset://sounds/snap.mp3",
	reload = "rbxasset://sounds/switch3.wav", -- played twice as a click-clack; swap for a real reload asset here
	swap = "rbxasset://sounds/swoosh.wav",
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
}

return Theme
