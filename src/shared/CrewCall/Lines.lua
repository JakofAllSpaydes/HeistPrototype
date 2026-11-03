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
			"Get to the blue beacon and hold it. I'll do the rest.",
		},
		rewardLine = "+$%d CASH",
	},
	doneToast = "%s CLEAR · +$%d",
	failToast = "TOO SLOW",
	portraitLabel = "[IMG: TBA]",
}

return Lines
