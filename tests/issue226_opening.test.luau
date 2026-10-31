--!strict
local fs = require("@lune/fs")
local Config = require("../src/shared/Config")
local RunState = require("../src/shared/RunState")
local RunDriver = require("../src/shared/RunDriver")
local RunHooks = require("../src/shared/RunHooks")
local DebugLayout = require("../src/shared/DebugLayout")
local ScreenLayout = require("../src/shared/ScreenLayout")
local StreetLayoutGen = require("../src/shared/StreetLayoutGen")
local LevelTheme = require("../src/shared/LevelTheme")

local function solo(): RunState.RunState
	return RunState.new({
		seed = 226,
		automated = true,
		startingTotal = 0,
		layout = {
			gatePairs = {},
			clusters = { { id = "c1", type = "small" } },
			obstacles = { { id = "o1" } },
			tomatoes = { { id = "t1" } },
		},
	})
end

return {
	{
		name = "226: title and run defaults contain zero NPC recruits",
		run = function()
			assert(Config.startingTotal == 0, "default still grants starter followers")
			local d = RunDriver.new({ layout = DebugLayout, hooks = RunHooks.new(DebugLayout) })
			assert(d:snapshot().total == 0, "ready state has starter followers")
			d:start(0)
			assert(d:snapshot().total == 0, "Start grants followers")
		end,
	},
	{
		name = "226: empty attack batches and rejected IDs do not defeat a solo opening",
		run = function()
			local s = solo()
			for _ = 1, 120 do
				s:attackClusters({})
			end
			s:attackClusters({ "unknown" })
			assert(s:outcome() == nil, "no contact must not defeat the player")
			assert(s:creditCluster("c1").ok, "solo player cannot recruit")
			assert(s:total() == Config.clusterTypes.small.reward, "recruit once from zero")
			assert(not s:creditCluster("c1").ok, "no duplicate recruits")
		end,
	},
	{
		name = "226: a real hit while solo defeats for each existing loss source",
		run = function()
			for _, hit in
				{
					function(s)
						s:attackCluster("c1")
					end,
					function(s)
						s:attackClusters({ "c1" })
					end,
					function(s)
						s:hitObstacle("o1")
					end,
					function(s)
						s:hitTomato("t1")
					end,
				}
			do
				local s = solo()
				hit(s)
				assert(s:outcome() == "defeated", "solo opening is not invulnerable")
				assert(s:score() == 0, "defeat scores zero")
				assert(not s:creditCluster("c1").ok, "no rescue after defeat")
			end
		end,
	},
	{
		name = "226: losing recruited followers still defeats, replay restores playable zero",
		run = function()
			local s = solo()
			s:creditCluster("c1")
			s:hitObstacle("o1")
			assert(s:outcome() == "defeated", "loss to zero defeats")
			s:reset()
			assert(s:total() == 0 and s:outcome() == nil, "replay resets solo start")
			s:attackClusters({})
			assert(s:creditCluster("c1").ok, "replay can recruit again")
		end,
	},
	{
		name = "226: production opening fires alone, survives without contact and recruits in lane",
		run = function()
			local d = RunDriver.new({ layout = DebugLayout, hooks = RunHooks.new(DebugLayout) })
			d:start(0)
			local shots = 0
			for _ = 1, 30 do
				for _, e in d:tick(RunDriver.TICK_DT) do
					if e.kind == "miss" or e.kind == "cluster" then
						shots += 1
					end
				end
			end
			assert(d:outcome() == nil and d:snapshot().total == 0, "idle solo opening survives")
			assert(shots > 0, "zero recruits must still fire")
			local first = DebugLayout.clusters[1]
			d:steer(1, { x = first.spawn.x })
			for _ = 1, 600 do
				d:tick(RunDriver.TICK_DT)
				if d:snapshot().total > 0 or d:outcome() ~= nil then
					break
				end
			end
			assert(d:outcome() == nil and d:snapshot().total > 0, "solo opening can recruit")
		end,
	},
	{
		name = "226: Jugar has comfortable bottom spacing across supported safe areas",
		run = function()
			local play = ScreenLayout.element("Play")
			assert(play)
			for _, aspect in ScreenLayout.ASPECTS do
				local safe = ScreenLayout.safeRect(aspect)
				local rect = ScreenLayout.elementRect(play, safe)
				assert(safe.y + safe.h - rect.y - rect.h >= 24, "Jugar still sits on bottom edge")
				assert(rect.y >= safe.y and rect.x >= safe.x, "button stays in safe area")
				assert(rect.w >= 44 and rect.h >= 44, "touch target retained")
			end
		end,
	},
	{
		name = "226: plaza floor is one continuous surface, and ground materials have no tile texture",
		run = function()
			local result = StreetLayoutGen.generate(DebugLayout, LevelTheme.level1, 226)
			local floors = 0
			for _, p in result.plaza do
				if p.group == "paving" then
					floors += 1
					assert(p.sx == DebugLayout.halfWidth * 2, "plaza is tiled across width")
					assert(
						p.sz == DebugLayout.streetLength - DebugLayout.plazaStart,
						"plaza is tiled along depth"
					)
				end
			end
			assert(floors == 1, "plaza still uses checkerboard tiles")
			for _, key in { "road", "ground", "plaza" } do
				assert(LevelTheme.level1.materials[key] == "SmoothPlastic", `textured {key}`)
			end
			assert(#result.facades > 0, "retain city")
		end,
	},
	{
		name = "226: avatar render is established before either city builder, with no opaque completion cover",
		run = function()
			local main = fs.readFile("src/client/Main.client.luau")
			local avatar = string.find(main, "local leadAvatar = LeadAvatar.new()", 1, true)
			local backdrop = string.find(main, "Backdrop.build(", 1, true)
			assert(avatar and backdrop and avatar < backdrop, "backdrop still builds before avatar")
			assert(
				string.find(main, 'SetAttribute("CalendaAvatarReady", true)', 1, true),
				"world builder has no avatar signal"
			)
			local world = fs.readFile("src/client/WorldBuilder.client.luau")
			assert(
				string.find(world, 'GetAttribute("CalendaAvatarReady")', 1, true),
				"parallel world does not wait for avatar"
			)
			local screen = fs.readFile("src/client/StartupScreen.luau")
			assert(
				not string.find(screen, 'cover.Name = "Cover"', 1, true),
				"opaque loading cover still hides avatar"
			)
		end,
	},
}
