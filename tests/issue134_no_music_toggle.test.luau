--!strict
-- Issue #134: the in-game music toggle is removed. Music plays on from the start of the run; device
-- volume and the silent switch are the mute. These cases pin the removal so it cannot come back by
-- accident.
local fs = require("@lune/fs")
local ScreenLayout = require("../src/shared/ScreenLayout")
local Strings = require("../src/shared/Strings")

local function source(path: string): string
	return fs.readFile(path)
end

return {
	{
		name = "the HUD layout has no MusicToggle element",
		run = function()
			assert(
				ScreenLayout.element("MusicToggle") == nil,
				"MusicToggle is still in ScreenLayout"
			)
		end,
	},
	{
		name = "the toggle's strings are gone",
		run = function()
			assert((Strings :: any).musicOn == nil, "musicOn string still defined")
			assert((Strings :: any).musicOff == nil, "musicOff string still defined")
		end,
	},
	{
		name = "Hud has no music toggle button and no mute callback",
		run = function()
			local hud = source("src/client/Hud.luau")
			assert(not string.find(hud, "MusicToggle", 1, true), "Hud.luau still names MusicToggle")
			assert(not string.find(hud, "onMusicMute", 1, true), "Hud.luau still takes onMusicMute")
		end,
	},
	{
		name = "MusicPlayer has no in-game mute path",
		run = function()
			local player = source("src/client/MusicPlayer.luau")
			assert(not string.find(player, "setMuted", 1, true), "MusicPlayer still has setMuted")
		end,
	},
	{
		name = "music still starts on Jugar (the run's start), with no toggle in between",
		run = function()
			local main = source("src/client/Main.client.luau")
			assert(
				string.find(main, "music:start(os.clock())", 1, true) ~= nil,
				"Main no longer starts the music on Jugar"
			)
			assert(not string.find(main, "setMuted", 1, true), "Main still wires a mute callback")
		end,
	},
}
