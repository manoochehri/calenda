--!strict
-- Client orchestration for how a run ends (issue #16). Owns the pure RunFlow, the 3D EndScene and
-- the RunHud; Main.client.luau calls `frame` once per render step and `resetHandlers` on replay.
-- Decisions (which ending, which tier, when results show) are all in pure, tested modules.
-- IN-ENGINE BEHAVIOUR IS UNVERIFIED (see the PR checklist).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DefeatPlan = require(Shared:WaitForChild("DefeatPlan"))
local FinalePlan = require(Shared:WaitForChild("FinalePlan"))
local Results = require(Shared:WaitForChild("Results"))
local RunFlow = require(Shared:WaitForChild("RunFlow"))
local RunView = require(Shared:WaitForChild("RunView"))
local ViewMap = require(Shared:WaitForChild("ViewMap"))

local EndScene = require(script.Parent:WaitForChild("EndScene"))
local RunHud = require(script.Parent:WaitForChild("RunHud"))

export type Out = {
	crowdTotal: number, -- what CrowdView should draw as loose followers (0 while the end scene stands in)
	tumble: number,
	lift: number,
	pullback: number, -- multiplier on the camera pullback
	musicIntensity: number?, -- FinalePlan.at(t).musicIntensity during the finale, else nil (issue #62)
	defeated: boolean, -- the party is breaking up: duck the music (issue #62)
	view: (hud: RunView.Hud) -> RunView.Hud, -- the HUD view with the results gated on the flow
}

export type EndFlow = {
	frame: (
		self: EndFlow,
		state: any,
		leadX: number,
		leadZ: number,
		dt: number,
		total: number
	) -> Out,
	-- The reset handlers this module owns, for ResetPlan.apply (Main adds the rest).
	resetHandlers: (self: EndFlow) -> { [string]: () -> () },
}
local EndFlow = {}

function EndFlow.new(): EndFlow
	local flow = RunFlow.new()
	local scene = EndScene.new()
	local hud = RunHud.new()
	local prevElapsed = 0

	local self = {} :: EndFlow

	function self.frame(_, state: any, leadX: number, leadZ: number, dt: number, total: number): Out
		local changed = RunFlow.step(flow, state, dt)
		local lead = Vector3.new(ViewMap.x(leadX), 0, leadZ) -- the scene lives in view space
		if changed == "finale" or changed == "breakup" then
			scene:begin(changed, lead, total, flow.tier)
			prevElapsed = -1e-6
		end

		local phase = flow.phase
		local kind = if flow.outcome == "completed"
			then "finale"
			elseif flow.outcome == "defeated" then "breakup"
			else ""
		local ending = (kind ~= "") and phase ~= "running"
		local tumble, lift, pullback = 0, 0, 1
		local musicIntensity: number? = nil
		if ending then
			-- After the beat the scene holds its last frame behind the results panel.
			local length = if kind == "finale" then FinalePlan.DURATION else DefeatPlan.DURATION
			local elapsed = if phase == "results" then length else flow.elapsed
			scene:update(kind, elapsed, prevElapsed, dt, flow.tier)
			prevElapsed = elapsed
			if kind == "finale" then
				local f = FinalePlan.at(elapsed)
				pullback, musicIntensity = f.cameraPullback, f.musicIntensity
			else
				local d = DefeatPlan.at(elapsed)
				tumble, lift = d.tumble, d.lift
			end
		end

		hud:setBanner(RunFlow.banner(flow))

		return {
			crowdTotal = if ending then 0 else total,
			tumble = tumble,
			lift = lift,
			pullback = pullback,
			musicIntensity = musicIntensity,
			defeated = ending and kind == "breakup",
			view = function(view: RunView.Hud): RunView.Hud
				return Results.apply(view, state, flow)
			end,
		}
	end

	function self.resetHandlers(_)
		return {
			bits = function()
				scene:clear() -- also clears the pooled confetti it owns
			end,
			finale = function()
				scene:clear()
				prevElapsed = 0
			end,
			breakup = function()
				scene:clear()
			end,
			results = function()
				hud:reset()
			end,
			flow = function()
				RunFlow.reset(flow)
			end,
		}
	end

	return self
end

return EndFlow
