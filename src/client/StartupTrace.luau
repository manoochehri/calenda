--!strict
-- One client-local recorder shared by Main and WorldBuilder through ModuleScript require caching.
-- It is intentionally silent unless Config.debug.startupTiming is enabled.
local moduleStartedAt = os.clock()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local configStartedAt = os.clock()
local Config = require(Shared:WaitForChild("Config"))
local configEndedAt = os.clock()

local timingStartedAt = os.clock()
local StartupTiming = require(Shared:WaitForChild("StartupTiming"))
local timingEndedAt = os.clock()

local trace = StartupTiming.new(Config.debug.startupTiming, moduleStartedAt, function()
	return os.clock()
end, function(line: string)
	print(line)
end)
trace:recordDuration("require Shared.Config", configStartedAt, configEndedAt)
trace:recordDuration("require Shared.StartupTiming", timingStartedAt, timingEndedAt)
trace:recordDuration("load Client.StartupTrace", moduleStartedAt, os.clock())

return {
	Config = Config,
	trace = trace,
}
