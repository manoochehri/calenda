--!strict
-- Issues #242/#244: the cyan disc/wedge behind the avatar on the title was the LeadRing, built at
-- the origin standing on edge and only laid flat by CrowdView.update, which the title never calls.
local fs = require("@lune/fs")

local function between(src: string, from: string, to: string): string
	local a = src:find(from, 1, true)
	assert(a, `missing {from}`)
	local b = src:find(to, a, true)
	assert(b, `missing {to}`)
	return src:sub(a, b)
end

return {
	{
		name = "242: LeadRing is not in the world until update has laid it flat under the lead",
		run = function()
			local src = fs.readFile("src/client/CrowdView.luau")
			local build = between(src, "local function buildRing", "function CrowdView.new")
			assert(
				not build:find("ring.Parent = parent", 1, true),
				"LeadRing is parented at build: it shows upright at the origin on the title"
			)
			assert(src:find("ring.Parent = folder", 1, true), "update never shows the ring")
		end,
	},
	{
		name = "242: the ring is only shown from update, after its CFrame is set",
		run = function()
			local src = fs.readFile("src/client/CrowdView.luau")
			local upd =
				between(src, "ring.CFrame = CFrame.new(ViewMap.x(leadX)", "local frame = flow:step")
			local cf = upd:find("ring.CFrame", 1, true)
			local guard = upd:find("if ring.Parent ~= folder then", 1, true)
			assert(guard, "ring re-parenting must be guarded (no per-frame Parent write)")
			local par = upd:find("ring.Parent = folder", guard, true)
			assert(cf and par and cf < par, "ring must be parented after it is placed flat")
		end,
	},
	{
		name = "242: inventory, the only Neon Cylinder parts in the client are the lead ring and gate rings",
		run = function()
			local allowed = { ["CrowdView.luau"] = true, ["GateView.luau"] = true }
			for _, file in fs.readDir("src/client") do
				local lines = string.split(fs.readFile("src/client/" .. file), "\n")
				for n, line in lines do
					if line:find("PartType.Cylinder", 1, true) then
						for m = n, math.min(n + 8, #lines) do
							if lines[m]:find("Material.Neon", 1, true) then
								assert(allowed[file], `{file}:{n}: unlisted Neon Cylinder (#242)`)
							end
						end
					end
				end
			end
		end,
	},
}
