--!strict
local Remotes = require("../src/shared/Remotes")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

return {
	{
		name = "names are distinct, non-empty strings",
		run = function()
			local seen: { [string]: boolean } = {}
			for key, name in Remotes.names do
				assert(type(name) == "string" and name ~= "", `name {key}`)
				assert(not seen[name], `duplicate remote name {name}`)
				seen[name] = true
			end
			assert(type(Remotes.folderName) == "string" and Remotes.folderName ~= "", "folder")
		end,
	},
	{
		name = "decodeSteer accepts only a table with a finite number x",
		run = function()
			eq(Remotes.decodeSteer({ x = 3.5 }), 3.5, "valid")
			eq(Remotes.decodeSteer({ x = -2 }), -2, "negative")
			for _, bad in
				{
					"x",
					5,
					true,
					{},
					{ x = "3" },
					{ x = 0 / 0 },
					{ x = math.huge },
					{ x = -math.huge },
					{ x = {} },
					{ x = true },
				}
			do
				eq(Remotes.decodeSteer(bad :: any), nil, "bad payload")
			end
			eq(Remotes.decodeSteer(nil), nil, "nil")
		end,
	},
	{
		name = "decodeSteer ignores forged state, attack, and event fields",
		run = function()
			eq(
				Remotes.decodeSteer({
					x = 1,
					total = 99999,
					hp = 0,
					score = 99999,
					id = "g1",
					clusterId = 4,
					amount = 5,
					damage = 999,
					attack = true,
					kind = "attack",
					side = "left",
				}),
				1,
				"only steering x is accepted; forged state/attack fields are ignored"
			)
		end,
	},
	{
		name = "encodeState builds a compact payload with only known fields",
		run = function()
			local p = Remotes.encodeState({
				time = 1.234,
				z = 20.123456,
				x = -3.987,
				total = 42,
				outcome = nil,
				score = nil,
				best = 7,
			})
			eq(p.total, 42, "total")
			eq((p :: any).hp, nil, "no HP in State (ADR 0006)")
			eq((p :: any).maxHp, nil, "no maxHp in State")
			eq(p.best, 7, "best")
			eq(p.over, false, "over")
			assert(math.abs(p.z - 20.12) < 0.006, "z rounded")
			assert(math.abs(p.x - -3.99) < 0.006, "x rounded")
			local p2 = Remotes.encodeState({
				time = 90,
				z = 1440,
				x = 0,
				total = 0,
				outcome = "completed",
				score = 100,
				best = 100,
			})
			eq(p2.over, true, "over")
			eq(p2.outcome, "completed", "outcome")
			eq(p2.total, 0, "defeated at zero followers")
			eq(p2.score, 100, "score")
		end,
	},
	{
		name = "event kinds are the closed set the server may emit",
		run = function()
			for _, kind in { "gate", "obstacle", "complete", "attack", "defeated" } do
				assert(Remotes.isEventKind(kind), kind)
			end
			assert(not Remotes.isEventKind("credit_everything"), "unknown")
			assert(not Remotes.isEventKind(5), "non-string")
		end,
	},
}
