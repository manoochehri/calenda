--!strict
-- Lune test runner: loads every tests/*.test.luau, runs each case, exits non-zero on failure.
local fs = require("@lune/fs")
local process = require("@lune/process")

export type Case = { name: string, run: () -> () }

local failed = 0
local passed = 0

for _, file in fs.readDir("tests") do
	if string.match(file, "%.test%.luau$") then
		local suite = require(`./{string.gsub(file, "%.luau$", "")}`) :: { Case }
		for _, case in suite do
			local ok, err = pcall(case.run)
			if ok then
				passed += 1
				print(`PASS {file}: {case.name}`)
			else
				failed += 1
				print(`FAIL {file}: {case.name}: {err}`)
			end
		end
	end
end

print(`{passed} passed, {failed} failed`)
if failed > 0 or passed == 0 then
	process.exit(1)
end
