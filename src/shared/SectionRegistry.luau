--!strict
-- Section type registry (issue #14, spec s7). Keyed by the CrowdMath sequence type so the globo and
-- dancers sections (issues #19, #20) plug in by registering one entry each; nothing else changes.
-- Pure and generic: the shared descriptors and the client's builders are two registries.
local CrowdMath = require("./CrowdMath")

export type Registry<T> = {
	register: (self: Registry<T>, sectionType: CrowdMath.SectionType, entry: T) -> (),
	get: (self: Registry<T>, sectionType: CrowdMath.SectionType) -> T?,
	has: (self: Registry<T>, sectionType: CrowdMath.SectionType) -> boolean,
}

local SectionRegistry = {}

function SectionRegistry.new<T>(): Registry<T>
	local entries: { [string]: T } = {}
	local known: { [string]: boolean } = {}
	for i = 1, 3 do -- the full repeating sequence puppet -> globo -> dancers
		known[CrowdMath.sectionType(i)] = true
	end
	local registry = {} :: Registry<T>

	function registry.register(_, sectionType: CrowdMath.SectionType, entry: T)
		if not known[sectionType] then
			error(`unknown section type {tostring(sectionType)}`, 2)
		end
		if entries[sectionType] ~= nil then
			error(`section type {sectionType} is already registered`, 2)
		end
		entries[sectionType] = entry
	end

	function registry.get(_, sectionType: CrowdMath.SectionType): T?
		return entries[sectionType]
	end

	function registry.has(_, sectionType: CrowdMath.SectionType): boolean
		return entries[sectionType] ~= nil
	end

	return registry
end

return SectionRegistry
