--!strict
-- One client-local recorder shared by Main and WorldBuilder through ModuleScript require caching.
-- Silent and free unless Config.debug.startupTiming is true: the flag is read once into ENABLED,
-- and when it is false there is no os.clock call, no label string, no per-call closure and no
-- print anywhere in the startup path (the no-op recorder and plain-require timedRequire are
-- chosen once below). Issue #73.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Config = require(Shared:WaitForChild("Config"))
local ENABLED: boolean = Config.debug.startupTiming
local TIMEOUT_SECONDS = 30 -- [default] print what was measured if startup never completes

local StartupTiming = require(Shared:WaitForChild("StartupTiming"))

-- Marks that must all exist before the single report prints.
local REQUIRED_MARKS = {
	"WorldBuilder built",
	"first State received",
	"first CalendaFrame render-step callback",
}

local trace: StartupTiming.Recorder
local timedRequire: (from: string, parent: Instance, child: string) -> any
local finishIfReady: () -> ()

if ENABLED then
	local moduleStartedAt = os.clock()
	trace = StartupTiming.new(true, moduleStartedAt, os.clock, print)
	trace:mark("StartupTrace loaded", moduleStartedAt)
	timedRequire = function(from: string, parent: Instance, child: string): any
		local startedAt = trace:begin()
		local module = require(parent:WaitForChild(child))
		trace:span(`require {from}.{child}`, startedAt)
		return module
	end
	finishIfReady = function()
		for _, label in REQUIRED_MARKS do
			if not trace:has(label) then
				return
			end
		end
		trace:finish()
	end
	-- WorldBuilder may error or no State may ever arrive: still print what was measured.
	task.delay(TIMEOUT_SECONDS, function()
		trace:finish(`timeout after {TIMEOUT_SECONDS}s`)
	end)
else
	trace = StartupTiming.new(false, 0, os.clock, print) -- shared no-op; never calls either
	timedRequire = function(_from: string, parent: Instance, child: string): any
		return require(parent:WaitForChild(child))
	end
	finishIfReady = function() end
end

return {
	Config = Config,
	enabled = ENABLED,
	trace = trace,
	timedRequire = timedRequire,
	finishIfReady = finishIfReady,
}
