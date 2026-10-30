--!strict
local ProjectileVisual = require("../src/shared/ProjectileVisual")

-- Sample the union of the camera-plane primitive footprints. This checks meaningful empty
-- space (the heart cleft and pointed tip, the note's narrow stem), not colors or pinned knobs.
local function filled(kind: string, x: number, y: number): boolean
	for _, piece in ProjectileVisual.geometry(kind) do
		local dx, dy = x - piece.x, y - piece.y
		local c, s = math.cos(piece.roll), math.sin(piece.roll)
		local u, v = (dx * c + dy * s) / (piece.w / 2), (-dx * s + dy * c) / (piece.h / 2)
		if piece.shape == "ball" then
			if u * u + v * v <= 1 then
				return true
			end
		elseif math.abs(u) <= 1 and math.abs(v) <= 1 then
			return true
		end
	end
	return false
end

return {
	{
		name = "heart has two separated upper lobes, a joined middle and a narrow lower point",
		run = function()
			assert(filled("heart", -0.3, 0.43) and filled("heart", 0.3, 0.43), "two lobes")
			assert(not filled("heart", 0, 0.43), "cleft must remain empty, not a central ball")
			assert(filled("heart", 0, 0) and filled("heart", 0, -0.62), "joined body and tip")
			assert(not filled("heart", -0.3, -0.62) and not filled("heart", 0.3, -0.62), "tapered tip")
		end,
	},
	{
		name = "note has a wide low head, narrow tall stem and separate flag extension",
		run = function()
			assert(filled("note", -0.35, -0.5) and filled("note", 0.35, -0.5), "wide head")
			assert(filled("note", 0.4, 0.35), "stem reaches above head")
			assert(not filled("note", -0.3, 0.35), "empty beside stem")
			assert(filled("note", 0.8, 0.75), "flag extends right above stem")
		end,
	},
	{
		name = "gift has a rectangular body, overhanging lid and crossed ribbons in the existing part budget",
		run = function()
			local shapes = ProjectileVisual.geometry("gift")
			local ribbons = 0
			for _, p in shapes do
				assert(p.shape == "block", "box and ribbon edges, no spherical core")
				if p.ribbon then
					ribbons += 1
				end
			end
			assert(ribbons == 2, "crossed ribbons")
			assert(filled("gift", -0.6, -0.4) and filled("gift", 0.6, -0.4), "square lower corners")
			assert(filled("gift", 0.75, 0.5) and not filled("gift", 0.75, 0), "lid overhang")
			for _, kind in { "note", "heart", "gift" } do
				assert(#ProjectileVisual.geometry(kind) <= 4, "reuse body and three extras")
			end
		end,
	},
	{
		name = "gift hits and misses both lob above the baseline and return exactly to their endpoints",
		run = function()
			for _, miss in { false, true } do
				assert(ProjectileVisual.lift("gift", 0, miss) == 0, "launch lift")
				assert(ProjectileVisual.lift("gift", 1, miss) == 0, "landing lift")
				for _, f in { 0.2, 0.5, 0.8 } do
					assert(ProjectileVisual.lift("gift", f, miss) > ProjectileVisual.lift("note", f, miss), "gift lobs higher")
				end
			end
			assert(ProjectileVisual.lift("note", 0.5, true) == 0, "ordinary misses keep original flight")
			assert(ProjectileVisual.lift("heart", 0.5, true) == 0, "heart misses keep original flight")
		end,
	},
}
