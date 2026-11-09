--!strict
-- Round 19d: the soundtrack. Follows the run state on this client and crossfades between Config.MusicTracks:
--   hub      the yard and its menus (also before the first sync)
--   run      the whole run: waves, intermissions, the dealer, alarms and gas (Round 19e: one track carries on
--            under all of it; sound effects play over the music, never instead of it)
--   boss     while a boss is alive (the one deliberate mood shift in a run)
--   summary  run end and the summary
-- The run-over stamp is silence. A state picks a track from its list; a track left mid-way resumes where it was if
-- its state comes back within MusicResumeSec (the run track picks up after the boss), and a finished track moves
-- on to another in the list. Big moments (the boss cutscene) duck the music to MusicDuck.
-- Also preloads every Theme.Sounds clip so the first shot of a session is not silent.
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ClientState = require(script.Parent:WaitForChild("ClientState"))
local UI = require(script.Parent:WaitForChild("UI"):WaitForChild("UI"))
local Theme = require(script.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local Music = {}

local sounds: { [string]: Sound } = {} -- track id -> its Sound (kept, paused when not playing)
local leftAt: { [string]: number } = {} -- track id -> os.clock() it faded out
local stateTrack: { [string]: string } = {} -- state -> the track it last played
local current: Sound? = nil
local currentState = ""
local ducked = false

local function soundFor(id: string): Sound
	local s = sounds[id]
	if s and s.Parent then
		return s
	end
	local made = Instance.new("Sound")
	made.Name = "Music"
	made.SoundId = id
	made.Looped = true
	made.Volume = 0
	made.SoundGroup = UI.soundGroup("Music")
	made.Parent = SoundService
	sounds[id] = made
	return made
end

local function fade(s: Sound, to: number, thenPause: boolean)
	local t = TweenService:Create(s, TweenInfo.new(Config.MusicFadeSec, Enum.EasingStyle.Sine), { Volume = to })
	t.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed and thenPause and s.Volume <= 0.001 then
			s:Pause()
		end
	end)
	t:Play()
end

local function pick(list: { string }, avoid: string?): string
	if #list == 1 then
		return list[1]
	end
	local options = {}
	for _, id in list do
		if id ~= avoid then
			table.insert(options, id)
		end
	end
	return options[math.random(#options)]
end

-- Crossfade to `state` (`fresh`: a new track even if the last one could resume).
local function switch(state: string, fresh: boolean?)
	if state == currentState and not fresh then
		return
	end
	currentState = state
	local old = current
	current = nil
	if old then
		leftAt[old.SoundId] = os.clock()
		fade(old, 0, true)
	end
	local list = (
		if state == "preheist" then Config.MusicPreHeist else (Config.MusicTracks :: any)[state]
	) :: { string }?
	if not list or #list == 0 then
		return
	end
	local last = stateTrack[state]
	local id = last
	local resume = not fresh
		and last ~= nil
		and table.find(list, last) ~= nil
		and os.clock() - (leftAt[last] or -math.huge) <= Config.MusicResumeSec
	if not resume then
		id = pick(list, last)
	end
	local chosen = id :: string
	stateTrack[state] = chosen
	local s = soundFor(chosen)
	if s == old then
		-- The same track again (a one-track list): keep it going.
		fade(s, 1, false)
		current = s
		return
	end
	if resume and s.TimePosition > 0 then
		s:Resume()
	else
		s.TimePosition = 0
		s:Play()
	end
	fade(s, 1, false)
	current = s
end

local function wanted(): string
	if not Config.MusicEnabled then
		return "off"
	end
	local sync = ClientState.sync
	if not sync or sync.waveState == "Hub" then
		return "hub"
	end
	local ws = sync.waveState
	if ws == "RunOver" then
		return "off"
	elseif ws == "RunEnd" or ws == "Summary" then
		return "summary"
	elseif sync.boss then
		return "boss"
	elseif ws == "PreHeist" then
		return "preheist" -- brief 13: the intro cue, quiet, until the breach
	end
	return "run"
end

local function setDuck(on: boolean)
	if ducked == on then
		return
	end
	ducked = on
	local group = UI.soundGroup("Music")
	TweenService:Create(group, TweenInfo.new(0.6), {
		Volume = Config.MusicVolume * (if on then Config.MusicDuck else 1),
	}):Play()
end

local function preload()
	local ids = {}
	local seen = {}
	for _, id in Theme.Sounds do
		if id ~= "" and not seen[id] then
			seen[id] = true
			table.insert(ids, id)
		end
	end
	for _, id in (Config.MusicTracks :: any).hub or {} do
		table.insert(ids, id)
	end
	pcall(function()
		ContentProvider:PreloadAsync(ids)
	end)
end

function Music.init()
	task.spawn(preload)
	task.spawn(function()
		while true do
			switch(wanted())
			setDuck(ClientState.musicDuck or currentState == "preheist") -- brief 13: the pre-heist cue plays quietly
			-- A track that played through moves on to another one in its state's list.
			local s = current
			if s and s.TimeLength > 0 and s.TimePosition >= s.TimeLength - Config.MusicFadeSec - 0.3 then
				local list = (Config.MusicTracks :: any)[currentState] :: { string }?
				if list and #list > 1 then
					switch(currentState, true)
				end
			end
			task.wait(0.25)
		end
	end)
end

return Music
