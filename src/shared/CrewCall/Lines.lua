--!strict
-- Every string the crew call component shows. Rewrite freely; nothing else references the copy.
-- Round 25: the interact key in every hint (Config.InteractKey).
local KEY = (require(script.Parent.Parent:WaitForChild("Config")) :: any).InteractKey :: string

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
			Cut = { name = "CHAIN", title = "CUT THE CHAIN" }, -- Round 19c
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
		-- Brief 7: THE BANK's vault call.
		textBank = {
			"Vault's at the bottom of the stairwell. Crack the wheel,",
			"clean it out, and take the tunnel if you have to.",
		},
		hatchTitle = "TUNNEL",
		hatchHint = "THE BACK WAY",
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
	-- Brief 7: door objectives on THE BANK. The card's first line is lines[<door group>] (default when unset).
	door = {
		crewLead = "MARLOW",
		typeLabel = "DOOR",
		kind = "job",
		lines = {
			D1 = "Front doors. Make some noise.",
			D2 = "They chained the stairs. Cut it.",
			D3 = "Shutters are down. Get them up.",
			D5 = "Stairwell to the vault is chained off. Cut your way down.",
			default = "That door's locked. Get it open.",
		},
		extraText = "Hold F at it. No clock on this one.",
		-- Round 19: how each door opens (Door node Interact: hold, or a minigame kind).
		extra = {
			hold = "Hold F at it. No clock on this one.",
			Charges = "Set a breach charge on them. No clock on this one.",
			Lockpick = "Pick the lock. No clock on this one.",
			Keypad = "Crack the keypad. No clock on this one.",
			Hotwire = "Hotwire the panel. No clock on this one.",
			Freq = "Jam the lock. No clock on this one.",
			Cut = "Take the bolt cutters to them. No clock on this one.",
		},
		holdActions = { chain = "CUT", shutter = "RAISE", panel = "FORCE", wheel = "OPEN" },
		minigameActions = {
			Charges = "BREACH",
			Lockpick = "PICK",
			Keypad = "HACK",
			Hotwire = "WIRE",
			Freq = "JAM",
			Safe = "CRACK",
			Cut = "CUT",
		},
		holdHint = "HOLD " .. KEY .. " · %s",
		minigameHint = KEY .. " · %s",
		rewardLine = "+$%d CASH · OPENS %s",
		markerHint = "HOLD " .. KEY,
		promptAction = "OPEN",
		lockedAction = "LOCKED",
		busyTag = "OPENING",
		holdText = "OPENING · %.1fs",
		doneTitle = "NICE WORK",
		doneText = { "That's open.", "Keep moving." },
		doneByText = { "It's open.", "Move up." },
		openedToast = "%s OPENED THE %s",
		vaultSign = "UNLOCKS · VAULT JOB",
	},
	-- Round 19c: SILENCE THE ALARM. Every alarm in the building rings and strobes until someone shuts the panel off
	-- (Round 19d: a minigame at the beacon); expiry shuts it off anyway, without the pay.
	alarm = {
		name = "SILENCE THE ALARM",
		crewLead = "MARLOW",
		typeLabel = "SIDE JOB",
		kind = "job",
		text = {
			"Somebody tripped the building alarm. It's giving me a headache.",
			"Alarm panel's at the blue beacon. Shut it off.",
		},
		rewardLine = "+$%d CASH · +%d GOLD",
		markerHint = "SHUT IT OFF",
		promptAction = "SILENCE",
		promptObject = "ALARM PANEL",
		busyTag = "SILENCING",
		-- Round 19d: the panel opens a minigame (Config.AlarmJobMinigames); the card's second line says which.
		panelLines = {
			Keypad = "Alarm panel's at the blue beacon. Punch in the override code.",
			Hotwire = "Alarm panel's at the blue beacon. Rewire it dead.",
			Freq = "Alarm panel's at the blue beacon. Jam its frequency.",
			Charges = "Alarm panel's at the blue beacon. Blow it off the wall.",
		},
		doneTitle = "PEACE AND QUIET",
		doneText = { "Finally. I can hear myself think.", "Payment's in." },
		doneByText = { "Alarm's off.", "Payment's coming through." },
		failText = { "It timed out on its own. No thanks to you.", "Next one, don't dawdle." },
	},
	-- Round 19f: RAID THE OFFICE (Offices.lua). Text line 1 takes the office's label; line 2 is the minigame's.
	office = {
		name = "RAID THE OFFICE",
		crewLead = "MARLOW",
		typeLabel = "SIDE JOB",
		kind = "job",
		text = {
			"The %s is locked up tight. Somebody's been stuffing it with cash.",
			"Get that door open.",
		},
		gameLines = {
			Lockpick = "Pick the lock on the door. Grab everything, their security gasses the room.",
			Hotwire = "Short the door's maglock. Grab everything, their security gasses the room.",
			Charges = "Blow the door off. Grab everything, their security gasses the room.",
			Cut = "Cut the chain on the handles. Grab everything, their security gasses the room.",
		},
		rewardLine = "+$%d CASH · +%d GOLD · BAGS INSIDE",
		markerHint = "BREAK IN",
		promptAction = "BREAK IN",
		busyTag = "BREAKING IN",
		doneTitle = "OFFICE OPEN",
		doneText = { "Door's down. Bag it all.", "Their security gasses that room. Don't linger." },
		doneByText = { "Door's down.", "Bag it before the gas." },
		failText = { "Too slow. They locked it down.", "Next one." },
		openToast = "%s OPEN · %ds",
		warnToast = "OFFICE GAS IN %ds · GET OUT",
		gasToast = "OFFICE GASSED · GET OUT",
		sealedToast = "%s SEALED",
		markerTitle = "OFFICE",
		markerOpen = "GRAB THE BAGS",
		markerWarn = "GAS · GET OUT",
		markerGas = "GASSED",
	},
	-- Round 19c: the zone gas event (ZoneGas.lua) on the toast line and the zone's marker.
	zoneGas = {
		warnToast = "GAS IN THE %s · %ds · MOVE",
		gasToast = "%s GASSED · GET OUT",
		clearToast = "%s CLEAR",
		markerTitle = "GAS",
		markerWarn = "IN %ds · MOVE",
		markerGas = "GET OUT",
		-- Round 19d: lockdown gas. A door objective left too long floods the map; only the zone behind it is clean.
		forceWarnToast = "LOCKDOWN · GAS IN %ds · %s",
		forceGasToast = "GAS EVERYWHERE · %s",
		forceClearToast = "AIR CLEARING",
		forceBanner = "%s", -- the pinned line under the wave bar (the door's ping text)
		forceBannerSub = "ONLY CLEAN AIR IS PAST THE %s",
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
	-- Brief 9: MARLOW's daily announce card adds this while a profile owns nothing on the Skill Web.
	skillsIntro = "Planning board's open. Spend some Gold on yourself.",
	-- Half-time reminder while a job is still open (Config.SideJobReminderPct).
	reminder = {
		title = "STILL OPEN",
		text = {
			"Half the window's gone and that job's still sitting there.",
			"Finish it or forget it. Your call.",
		},
	},
	-- Brief 13: the pre-heist on THE BANK (Breach.lua, the wave bar's pill, the summary). [Copy: TBA]
	preHeist = {
		doorLine = "Front doors. Make some noise.", -- MARLOW's card with the front-door objective from the first second
		nagLabel = "WHENEVER YOU'RE READY",
		stamp = "HEIST ON", -- the centre stamp at the breach
		pill = "BREACH WHEN READY", -- where the wave bar sits until the breach
		pillHint = "BLOW THE DOORS OR GO IN THROUGH A WINDOW",
		idleRow = "IDLE BEFORE BREACH %s", -- the summary's small line under the time row
	},
	-- MARLOW every Config.PreHeistNagSec of idling, cycling. [Copy: TBA]
	preHeistNag = {
		"Clock's ticking, in your head at least.",
		"Whenever you're ready. No rush. Some rush.",
		"The vault isn't coming out here.",
	},
}

return Lines
