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
		rewardLine = "+$%d CASH",
		promptAction = "HACK",
		promptObject = "TERMINAL",
		doneTitle = "NICE WORK",
		doneText = {
			"Clean. That's how it's done.",
			"Payment's in, and I sent you a little extra.",
		},
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
		rewardLine = "+$%d CASH",
		markerHint = "STAND IN THE CIRCLE",
		holdingHint = "HOLDING · %d%%",
		leftHint = "%d%% · GET BACK IN",
		doneTitle = "NICE WORK",
		doneText = {
			"Got it. That relay's ours now.",
			"Payment's in. Keep moving.",
		},
		failText = {
			"Signal's gone. You couldn't hold it.",
			"Next time, plant your feet.",
		},
	},
	hackMarkerHint = "HACK THE TERMINAL",
	doneToast = "%s CLEAR · +$%d",
	failToast = "TOO SLOW",
	portraitLabel = "[IMG: TBA]",
}

return Lines
