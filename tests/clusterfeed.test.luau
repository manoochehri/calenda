--!strict
local ClusterFeed = require("../src/shared/ClusterFeed")
local Remotes = require("../src/shared/Remotes")

local function eq(actual: any, expected: any, name: string)
	assert(actual == expected, `{name}: expected {tostring(expected)}, got {tostring(actual)}`)
end

return {
	{
		name = "a well-formed cluster event decodes to id, hits and shot",
		run = function()
			local s = ClusterFeed.decode({ kind = "cluster", id = 3, hits = 2, shot = "note" })
			assert(s ~= nil, "decoded")
			eq(s.id, 3, "id")
			eq(s.hits, 2, "hits")
			eq(s.shot, "note", "shot")
			eq(
				ClusterFeed.decode({ kind = "cluster", id = 1, hits = 8, shot = "gift" }).shot,
				"gift",
				"gift"
			)
		end,
	},
	{
		name = "malformed payloads decode to nil and never throw",
		run = function()
			local bad: { any } = {
				"x",
				42,
				{},
				{ kind = "gate", id = 1, hits = 1, shot = "note" },
				{ kind = "cluster", id = 0, hits = 1, shot = "note" },
				{ kind = "cluster", id = 1.5, hits = 1, shot = "note" },
				{ kind = "cluster", id = 1, hits = -1, shot = "note" },
				{ kind = "cluster", id = 1, hits = 0.5, shot = "note" },
				{ kind = "cluster", id = 1, hits = 1, shot = "rocket" },
				{ kind = "cluster", id = 1, hits = 1 },
				{ kind = "cluster", id = 0 / 0, hits = 1, shot = "note" },
				{ kind = "cluster", id = 1, hits = math.huge, shot = "note" },
				{ kind = "cluster", id = 1, hits = ClusterFeed.MAX_HITS + 1, shot = "note" },
			}
			for i, p in bad do
				eq(ClusterFeed.decode(p), nil, `bad payload {i}`)
			end
		end,
	},
	{
		name = "encode mirrors a Targeting shot and round-trips; kind is a known event kind",
		run = function()
			local p =
				ClusterFeed.encode({ targetId = 4, hits = 3, shot = nil, kind = "gift" } :: any)
			eq(p.kind, "cluster", "kind")
			assert(Remotes.isEventKind(p.kind), "reserved kind exists in Remotes")
			local back = ClusterFeed.decode(p)
			assert(back ~= nil, "round trip")
			eq(back.id, 4, "id")
			eq(back.hits, 3, "hits")
			eq(back.shot, "gift", "shot")
		end,
	},
}
