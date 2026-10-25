--!strict
local Config = require("../src/shared/Config")
local SfxMap = require("../src/shared/SfxMap") :: any

local function near(a: number, b: number, name: string)
	assert(math.abs(a - b) < 1e-9, `{name}: expected {b}, got {a}`)
end

local function one(list: { string }, slot: string)
	assert(#list == 1 and list[1] == slot, `expected {slot}, got {table.concat(list, ",")}`)
end

return {
	{
		name = "every event kind maps to its sound slot",
		run = function()
			one(SfxMap.forEvent({ kind = "gate" }), "gatePop")
			one(SfxMap.forEvent({ kind = "obstacle" }), "obstacleThud")
			one(SfxMap.forEvent({ kind = "complete" }), "finalePeak")
			one(SfxMap.forEvent({ kind = "defeated" }), "defeatBreakup")
			local shot = SfxMap.forEvent({ kind = "cluster", id = 1, hits = 1, shot = "note" })
			assert(table.find(shot, "shotLaunch") and table.find(shot, "shotImpact"), "shot")
			local atk = SfxMap.forEvent({ kind = "attack", id = 1 })
			assert(table.find(atk, "attackBonk") and table.find(atk, "followerHit"), "attack")
			one(SfxMap.forEvent({ kind = "replay" }), "replayClick")
		end,
	},
	{
		name = "unknown or malformed events map to nothing and never error",
		run = function()
			assert(#SfxMap.forEvent({ kind = "nope" }) == 0, "unknown")
			assert(#SfxMap.forEvent({}) == 0, "no kind")
			assert(#SfxMap.forEvent(nil) == 0, "nil")
			assert(#SfxMap.forEvent("gate") == 0, "string")
		end,
	},
	{
		name = "a rising total plays convert and +N sparkle; a new section adds the rise",
		run = function()
			local up = SfxMap.forTotalChange(10, 12)
			assert(table.find(up, "convert") and table.find(up, "sparkle"), "convert, sparkle")
			assert(not table.find(up, "sectionRise"), "no section yet")
			assert(table.find(SfxMap.forTotalChange(48, 52), "sectionRise"), "crossed 50")
			assert(#SfxMap.forTotalChange(12, 12) == 0, "unchanged")
			assert(#SfxMap.forTotalChange(12, 3) == 0, "losses are the obstacle sound, not these")
			assert(#SfxMap.forTotalChange(0 / 0, 3) == 0, "nan")
		end,
	},
	{
		name = "every slot has a Config.sfx id key, volume and cooldown",
		run = function()
			for _, slot in SfxMap.SLOTS do
				assert(Config.sfx[slot] ~= nil, `sfx.{slot}`)
				assert(Config.audio.sfx.volumes[slot] ~= nil, `volume {slot}`)
				assert(Config.audio.sfx.cooldowns[slot] ~= nil, `cooldown {slot}`)
			end
			assert(#SfxMap.SLOTS == 12, "12 slots")
		end,
	},
	{
		name = "empty ids are silent: playable is false for every slot",
		run = function()
			for _, slot in SfxMap.SLOTS do
				assert(SfxMap.playable(slot) == false, slot)
			end
			assert(
				SfxMap.playable("gatePop", { sfx = { gatePop = "rbxassetid://1" } }) == true,
				"set"
			)
			assert(SfxMap.playable("nonsense") == false, "unknown slot")
		end,
	},
	{
		name = "bigger parade = bigger bangs: volume grows with intensity, under the ceiling",
		run = function()
			local small = SfxMap.volume("attackBonk", 0)
			local big = SfxMap.volume("attackBonk", 1)
			assert(big > small and small > 0, `{small} {big}`)
			for _, slot in SfxMap.SLOTS do
				for i = -1, 21 do
					local v = SfxMap.volume(slot, i / 20)
					assert(v >= 0 and v <= Config.audio.sfx.maxVolume + 1e-9, `{slot} {v}`)
				end
			end
		end,
	},
	{
		name = "pitch variation range grows with intensity and stays near 1",
		run = function()
			near(SfxMap.speed(0, 0.5), 1, "middle roll is unchanged")
			local smallLo, smallHi = SfxMap.speed(0, 0), SfxMap.speed(0, 1)
			local bigLo, bigHi = SfxMap.speed(1, 0), SfxMap.speed(1, 1)
			assert(bigHi - bigLo > smallHi - smallLo, "wider at high intensity")
			assert(bigLo >= 0.5 and bigHi <= 2, "bounded")
			assert(
				SfxMap.speed(1, 5) <= bigHi + 1e-9 and SfxMap.speed(1, -5) >= bigLo - 1e-9,
				"clamp roll"
			)
		end,
	},
	{
		name = "per-slot cooldown: a flood of the same slot is mostly dropped, other slots unaffected",
		run = function()
			local lim = SfxMap.limiter()
			local played = 0
			for i = 0, 99 do
				if SfxMap.admit(lim, "gatePop", i * 0.01) then
					played += 1
				end
			end
			-- 1 s at cooldown 0.15 s: at most 7
			assert(played >= 1 and played <= 7, `played {played}`)
			assert(SfxMap.admit(lim, "obstacleThud", 0.995), "another slot is independent")
			assert(not SfxMap.admit(lim, "gatePop", 0.995 + 0.01), "still cooling")
		end,
	},
	{
		name = "the pool never exceeds the hard cap, picks free then oldest-expiring is NOT stolen",
		run = function()
			local cap = Config.audio.sfx.maxConcurrent
			assert(cap <= 8, "cap is at most 8")
			local busy: { number } = {}
			local started = 0
			for i = 1, 100 do
				local idx = SfxMap.pick(busy, 1 + i * 0.001, cap)
				if idx then
					busy[idx] = 1 + i * 0.001 + 2
					started += 1
				end
			end
			assert(started == cap, `started {started}`)
			local n = 0
			for _ in busy do
				n += 1
			end
			assert(n <= cap, "table size")
			assert(SfxMap.pick(busy, 99, cap) ~= nil, "a free voice returns once sounds end")
		end,
	},
	{
		name = "assetUri accepts bare ids and URIs, empty stays empty",
		run = function()
			assert(SfxMap.assetUri("12345") == "rbxassetid://12345", "digits")
			assert(SfxMap.assetUri(" 12345 ") == "rbxassetid://12345", "trim")
			assert(SfxMap.assetUri("rbxassetid://9") == "rbxassetid://9", "uri")
			assert(SfxMap.assetUri("") == "" and SfxMap.assetUri(nil) == "", "empty")
		end,
	},
}
