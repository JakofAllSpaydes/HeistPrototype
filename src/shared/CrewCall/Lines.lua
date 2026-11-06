--!strict
-- Every string the crew call component shows. Rewrite freely; nothing else references the copy.
local Lines = {
	job = {
		name = "VAULT PING",
		crewLead = "MARLOW",
		typeLabel = "SIDE JOB",
		kind = "job", -- job (blue) | door (amber) | ftue (grey) | legendary (gold)
		text = {
			"Someone left a terminal open on the floor.",
			"Get to the blue beacon and hack it. I'll do the rest.",
		},
		rewardLine = "+$%d CASH · +%d GOLD",
		promptAction = "HACK",
		promptObject = "TERMINAL",
		busyTag = "HACKING", -- over the holder's head for teammates
		doneTitle = "NICE WORK",
		doneText = {
			"Clean. That's how it's done.",
			"Payment's in, and I sent you a little extra.",
		},
		-- Round 16: the completion card shows the player who finished the job, in their own voice.
		doneByText = { "Terminal's hacked.", "Payment's coming through." },
		failText = {
			"Window's closed. They locked it down.",
			"Next one, don't dawdle.",
		},
	},
	-- Capture point: stand in the circle for Config.SideJobCaptureSec.
	capture = {
		name = "HOLD THE FLOOR",
		crewLead = "MARLOW",
		typeLabel = "SIDE JOB",
		kind = "job",
		text = {
			"Their relay is in the floor under that blue circle.",
			"Stand on it long enough and I can tap it. Don't step off.",
		},
		rewardLine = "+$%d CASH · +%d GOLD",
		markerHint = "STAND IN THE CIRCLE",
		busyTag = "CAPTURING", -- over anyone in the circle, for teammates
		holdingHint = "HOLDING · %d%%",
		leftHint = "%d%% · GET BACK IN",
		doneTitle = "NICE WORK",
		doneText = {
			"Got it. That relay's ours now.",
			"Payment's in. Keep moving.",
		},
		doneByText = { "Held the floor. That relay's ours.", "Payment's coming through." },
		failText = {
			"Signal's gone. You couldn't hold it.",
			"Next time, plant your feet.",
		},
	},
	-- Minigame jobs: the beacon carries a prop; open it and play the game to finish the job.
	minigame = {
		crewLead = "MARLOW",
		typeLabel = "SIDE JOB",
		kind = "job",
		text = {
			"There's a %s on the floor by the blue beacon.",
			"Crack it before the window shuts. Botch it and try again.",
		},
		rewardLine = "+$%d CASH · +%d GOLD",
		markerHint = "OPEN THE %s",
		props = {
			Lockpick = { name = "LOCK", title = "PICK THE LOCK" },
			Hotwire = { name = "FUSE BOX", title = "HOTWIRE THE BOX" },
			Keypad = { name = "KEYPAD", title = "CRACK THE CODE" },
			Charges = { name = "CHARGE RIG", title = "ARM THE CHARGES" },
			Safe = { name = "SAFE", title = "CRACK THE SAFE" },
			Freq = { name = "JAMMER", title = "JAM THE SIGNAL" },
		},
		doneTitle = "NICE WORK",
		doneText = {
			"Smooth hands. That's the stuff.",
			"Payment's in. Keep moving.",
		},
		doneByText = { "Got the %s open.", "Payment's coming through." }, -- %s: the prop
		failText = {
			"Window's closed. Fingers too slow.",
			"Next one, don't dawdle.",
		},
	},
	-- The vault job: F at the vault door opens the Safe dial; done opens the door onto a bag burst with a gas timer.
	vault = {
		name = "CRACK THE VAULT",
		crewLead = "MARLOW",
		typeLabel = "SIDE JOB",
		kind = "job",
		text = {
			"Vault's on the north wall. Crack it and clean it out,",
			"you won't get long.",
		},
		rewardLine = "+$%d CASH · +%d GOLD · THE VAULT",
		markerHint = "CRACK THE DOOR",
		promptAction = "CRACK",
		promptObject = "VAULT DOOR",
		doneTitle = "WE'RE IN",
		doneText = {
			"We're in. Move!",
			"Grab everything before the gas.",
		},
		doneByText = { "Vault's open. Move!", "Grab everything before the gas." },
		failText = {
			"Window's closed. That door's staying shut.",
			"Next one, don't dawdle.",
		},
		openToast = "VAULT OPEN",
		pillName = "VAULT",
		lootHint = "CLEAN IT OUT",
		gasWarnHint = "GAS IN %ds · GET OUT",
		gasHint = "GAS · GET OUT",
		gasTitle = "GAS",
		gasText = {
			"Gas! Get out!",
			"Leave the rest, it's not worth your lungs.",
		},
		sealedLabel = "SEALED",
	},
	-- The boss cutscene call and the kill stamp.
	boss = {
		crewLead = "MARLOW",
		typeLabel = "HEAVY RESPONSE",
		kind = "door",
		text = { "Heavy response inbound. Big one." },
		downStamp = "%s DOWN",
	},
	-- Bag pickups.
	bagsDropped = "BAGS DROPPED · %s",
	bagGrabbed = "%s GRABBED %s",
	bagBanked = "%s BANKED ◆ %d",
	hackMarkerHint = "HACK THE TERMINAL",
	doneToast = "%s CLEAR · +$%d · +%d GOLD",
	failToast = "TOO SLOW",
	-- Round 16: NPC portraits are a dummy avatar bust (CrewCallUI) in these hex colors until real art lands.
	portraits = {
		MARLOW = { skin = "D9A87E", shirt = "2B2F3A", accent = "4D9FE8", hair = "2A1E18" },
		DEALER = { skin = "A8714F", shirt = "5A2E2E", accent = "E8B64C", hair = "141414" },
		default = { skin = "C9C2B8", shirt = "3A3F4A", accent = "9BA0A8", hair = "2A2A2A" },
	},
	-- Half-time reminder while a job is still open (Config.SideJobReminderPct).
	reminder = {
		title = "STILL OPEN",
		text = {
			"Half the window's gone and that job's still sitting there.",
			"Finish it or forget it. Your call.",
		},
	},
}

return Lines
