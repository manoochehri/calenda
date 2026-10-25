--!strict
-- The flowing crowd (issue #68, spec s3 and s8, Amendment 1). Pure: no Instances, time is passed in.
-- The HUD always shows the exact total from State; this module only decides how the DRAWN crowd
-- gets there so it reads as a flow and never as blocks popping in or out:
--   * joins: when the total rises, followers start one at a time (FollowerStagger) from a SOURCE
--     (the converted group, the gate panel, or the lead's side) and spring to their slot;
--   * extra joins past the drawn cap (and gains that only grow sections) show as a bounded stream
--     of runners that merge into the crowd;
--   * leaves: when the total drops, followers peel off one at a time to the sidewalk; when a section
--     forms they hurry into the lead instead;
--   * loose layout: stable slot per follower (FollowerSlots), spring follow with per-follower
--     omega/zeta/phase (FollowerSpring) so the crowd ripples as the lead steers.
-- World coordinates: left is negative x. The client mirrors with ViewMap.x when it draws.
local Config = require("./Config")
local FollowerSlots = require("./FollowerSlots")
local FollowerSpring = require("./FollowerSpring")
local FollowerStagger = require("./FollowerStagger")
local SectionEvents = require("./SectionEvents")
local VisualBudget = require("./VisualBudget")

export type Hint = { kind: string, x: number, z: number, side: string? }
export type Member = {
	id: number,
	slot: number,
	x: number,
	z: number,
	vx: number, -- world lateral velocity, for leaning into turns
	y: number, -- extra hop height from the join arc
	phase: number, -- per-follower phase for the march bounce
	bobRate: number,
}
export type Runner = { id: number, x: number, z: number, vx: number, y: number }
export type Leaver = { id: number, x: number, z: number, vx: number, y: number, cheering: boolean }
export type Frame = { members: { Member }, runners: { Runner }, leavers: { Leaver } }
export type Flow = {
	reset: (self: Flow, total: number) -> (),
	hint: (self: Flow, hint: Hint) -> (),
	setTotal: (self: Flow, total: number) -> (),
	step: (self: Flow, dt: number, leadX: number, leadZ: number, swirl: number?) -> Frame,
	counts: (self: Flow) -> { members: number, pending: number, runners: number, leavers: number },
}

local FollowerFlow = {}

FollowerFlow.STREAM_CAP = 16 -- [default] live stream runners at once (extras to the drawn cap)
FollowerFlow.LEAVER_CAP = Config.visualBudget.looseAvatars -- leavers were drawn members already
FollowerFlow.HINT_TTL = 1.0 -- [default] seconds a source hint stays valid for a total change
FollowerFlow.LEAVE_RATE = 14 -- [default] followers peeling off per second
FollowerFlow.LEAVE_SPAN = 1.0 -- [default] seconds, like joins
FollowerFlow.JOIN_SPEED = 22 -- [default] studs/second launch speed toward the slot
FollowerFlow.JOIN_CURVE = 0.45 -- [default] sideways share of the launch (a springy, curved path)
FollowerFlow.JOIN_HOP_SECONDS = 0.55 -- [default]
FollowerFlow.JOIN_HOP_HEIGHT = 1.3 -- [default] studs
FollowerFlow.RUNNER_MAX_SECONDS = 1.2 -- [default]
FollowerFlow.LEAVER_CHEER_SECONDS = 0.7 -- [default]
FollowerFlow.LEAVER_MAX_SECONDS = 2.2 -- [default]
FollowerFlow.SWAY_AMPLITUDE = 0.3 -- [default] studs of idle drift per follower
FollowerFlow.SWAY_RATE = 2.1 -- [default] radians/second
FollowerFlow.SIDEWALK_INSET = 3 -- [default] studs in from the street edge
FollowerFlow.MAX_TARGET_SPEED = 80 -- feed-forward clamp, studs/second

local TWO_PI = math.pi * 2

type Entity = {
	id: number,
	slot: number,
	omega: number,
	zeta: number,
	phase: number,
	bobRate: number,
	born: boolean,
	startAt: number,
	bornAt: number,
	hint: Hint?,
	x: number,
	z: number,
	vx: number,
	vz: number,
	px: number?, -- previous target, for feed-forward
	pz: number?,
	leaveAt: number?,
	leaveMode: string?,
	leaveSide: string?,
}
type Mover = {
	id: number,
	kind: string, -- "runner" | "peel" | "merge"
	omega: number,
	zeta: number,
	phase: number,
	age: number,
	x: number,
	z: number,
	vx: number,
	vz: number,
	tx: number, -- fixed target (peel)
	tz: number,
	slot: number, -- runner: slot to merge into
	arrivedAt: number?,
	px: number?,
	pz: number?,
}

local function traits(id: number): (number, number, number, number)
	local u = FollowerSlots.unit
	return 8 + u(id, 11) * 5, 0.5 + u(id, 12) * 0.35, u(id, 13) * TWO_PI, 8 + u(id, 14) * 3
end

-- The charter's combined cap: members + runners + leavers drawn never exceed `cap`. Transients win;
-- the outermost members (highest slot) step aside while they run, so the stream reads as the crowd
-- taking them in. Mutates and returns the frame.
function FollowerFlow.fit(frame: Frame, cap: number): Frame
	local excess = #frame.members + #frame.runners + #frame.leavers - cap
	if excess > 0 then
		table.sort(frame.members, function(a, b)
			return a.slot < b.slot
		end)
		for _ = 1, math.min(excess, #frame.members) do
			table.remove(frame.members)
		end
		-- Still over (more transients than the cap): drop the newest runners.
		while #frame.runners + #frame.leavers > cap and #frame.runners > 0 do
			table.remove(frame.runners)
		end
		-- Last resort: leavers alone exceed the cap; drop the newest.
		while #frame.runners + #frame.leavers > cap and #frame.leavers > 0 do
			table.remove(frame.leavers)
		end
	end
	return frame
end

function FollowerFlow.new(halfWidth: number): Flow
	local members: { Entity } = {}
	local movers: { Mover } = {}
	local pendingRunners: { { id: number, startAt: number, hint: Hint? } } = {}
	local clock = 0
	local nextId = 0
	local lastTotal: number? = nil
	local density = 0
	local lastHint: Hint? = nil
	local lastHintAt = -math.huge
	local lastLeadX: number? = nil
	local lastLeadZ: number? = nil
	local self = {} :: Flow

	local function newId(): number
		nextId += 1
		return nextId
	end

	local function newMember(slot: number, startAt: number, hint: Hint?, born: boolean): Entity
		local id = newId()
		local omega, zeta, phase, bobRate = traits(id)
		return {
			id = id,
			slot = slot,
			omega = omega,
			zeta = zeta,
			phase = phase,
			bobRate = bobRate,
			born = born,
			startAt = startAt,
			bornAt = startAt,
			hint = hint,
			x = 0,
			z = 0,
			vx = 0,
			vz = 0,
		}
	end

	local function takenSlots(): { [number]: boolean }
		local taken: { [number]: boolean } = {}
		for _, m in members do
			if m.leaveAt == nil then -- a leaver is on its way out: its slot may be reused
				taken[m.slot] = true
			end
		end
		return taken
	end

	local function liveCount(): number
		local n = 0
		for _, m in members do
			if m.leaveAt == nil then
				n += 1
			end
		end
		return n
	end

	function self.reset(_, total: number)
		members, movers, pendingRunners = {}, {}, {}
		lastHint, lastHintAt = nil, -math.huge
		lastLeadX, lastLeadZ = nil, nil
		lastTotal = total
		local plan = VisualBudget.allocate(total)
		density = plan.formationDensity
		local taken: { [number]: boolean } = {}
		for _ = 1, plan.looseAvatars do
			local slot = FollowerSlots.lowestFree(taken)
			taken[slot] = true
			local m = newMember(slot, clock, nil, true)
			m.bornAt = -math.huge -- settled: no join hop
			table.insert(members, m)
		end
	end

	function self.hint(_, hint: Hint)
		lastHint, lastHintAt = hint, clock
	end

	function self.setTotal(_, total: number)
		if lastTotal == nil then
			self:reset(total)
			return
		end
		local plan = VisualBudget.allocate(total)
		density = plan.formationDensity
		local delta = total - lastTotal
		lastTotal = total
		if total == 0 then
			members, movers, pendingRunners = {}, {}, {}
			return
		end
		local hint: Hint? = nil
		if lastHint ~= nil and clock - lastHintAt <= FollowerFlow.HINT_TTL then
			hint = lastHint
		end
		if delta ~= 0 then
			lastHint = nil
		end

		local live = liveCount()
		local target = plan.looseAvatars
		if live > target then
			-- Cancel followers that have not started yet, then outermost first.
			local excess = live - target
			local order: { Entity } = {}
			for _, m in members do
				if m.leaveAt == nil then
					table.insert(order, m)
				end
			end
			table.sort(order, function(a, b)
				if a.born ~= b.born then
					return not a.born -- unborn first
				end
				return a.slot > b.slot
			end)
			local leaving: { Entity } = {}
			for i = 1, excess do
				table.insert(leaving, order[i])
			end
			local mode = if delta < 0 then "peel" else "merge"
			local side = if hint and hint.side then hint.side else nil
			local offsets = FollowerStagger.offsets(
				#leaving,
				FollowerFlow.LEAVE_RATE,
				FollowerFlow.LEAVE_SPAN,
				#leaving
			)
			local dropped: { [Entity]: boolean } = {}
			local k = 0
			for _, m in leaving do
				if not m.born then
					dropped[m] = true
				else
					k += 1
					m.leaveAt = clock + (offsets[k] or 0)
					m.leaveMode = mode
					m.leaveSide = side
				end
			end
			if next(dropped) ~= nil then
				local kept = {}
				for _, m in members do
					if not dropped[m] then
						table.insert(kept, m)
					end
				end
				members = kept
			end
			live = target
		end

		local deficit = math.max(0, target - live)
		local arrivals = math.max(deficit, math.max(delta, 0))
		if arrivals > 0 then
			local offsets = FollowerStagger.offsets(arrivals)
			local taken = takenSlots()
			for i, off in offsets do
				if i <= deficit then
					local slot = FollowerSlots.lowestFree(taken)
					taken[slot] = true
					table.insert(members, newMember(slot, clock + off, hint, false))
				else
					table.insert(
						pendingRunners,
						{ id = newId(), startAt = clock + off, hint = hint }
					)
				end
			end
		end
	end

	-- Where an arrival starts: the hint, else beside the lead (its side alternates by id).
	local function sourceFor(
		id: number,
		hint: Hint?,
		leadX: number,
		leadZ: number
	): (number, number)
		if hint ~= nil then
			return hint.x, hint.z
		end
		local sign = if id % 2 == 0 then 1 else -1
		return leadX + sign * 6, leadZ - 2
	end

	local cloudC, cloudW = 0, 1 -- FollowerSlots.layout for this frame: keeps the cloud on the road

	local function slotTarget(
		slot: number,
		leadZ: number,
		swirl: number,
		phase: number
	): (number, number)
		local s = FollowerSlots.slot(slot, density)
		local dx, dz = SectionEvents.swirlSlot(s.dx, s.dz, swirl)
		local sway = FollowerFlow.SWAY_AMPLITUDE
		return cloudC + cloudW * dx + math.sin(clock * FollowerFlow.SWAY_RATE + phase) * sway,
			leadZ + dz + math.sin(clock * FollowerFlow.SWAY_RATE * 0.8 + phase * 1.3) * sway * 0.6
	end

	local function feedForward(prev: number?, now: number, dt: number): number
		if prev == nil or not (dt > 0) then
			return 0
		end
		return math.clamp(
			(now - prev) / dt,
			-FollowerFlow.MAX_TARGET_SPEED,
			FollowerFlow.MAX_TARGET_SPEED
		)
	end

	local function launch(
		e: { vx: number, vz: number, id: number },
		x: number,
		z: number,
		tx: number,
		tz: number
	)
		local dx, dz = tx - x, tz - z
		local len = math.max(math.sqrt(dx * dx + dz * dz), 0.001)
		local side = FollowerSlots.unit(e.id, 21) * 2 - 1
		local c = FollowerFlow.JOIN_CURVE * side
		local speed = FollowerFlow.JOIN_SPEED * (0.8 + FollowerSlots.unit(e.id, 22) * 0.4)
		e.vx = (dx / len - dz / len * c) * speed
		e.vz = (dz / len + dx / len * c) * speed
	end

	function self.step(_, dt: number, leadX: number, leadZ: number, swirl: number?): Frame
		clock += dt
		cloudC, cloudW = FollowerSlots.layout(leadX)
		local sw = swirl or 0
		local leadVx = feedForward(lastLeadX, leadX, dt)
		local leadVz = feedForward(lastLeadZ, leadZ, dt)
		lastLeadX, lastLeadZ = leadX, leadZ

		-- Pending stream runners start (bounded).
		local keptPending = {}
		local streams = 0
		for _, m in movers do
			if m.kind == "runner" then
				streams += 1
			end
		end
		for _, p in pendingRunners do
			if clock >= p.startAt then
				if streams < FollowerFlow.STREAM_CAP then
					streams += 1
					local omega, zeta, phase = traits(p.id)
					local x, z = sourceFor(p.id, p.hint, leadX, leadZ)
					local mover: Mover = {
						id = p.id,
						kind = "runner",
						omega = omega + 3,
						zeta = zeta + 0.2,
						phase = phase,
						age = 0,
						x = x,
						z = z,
						vx = 0,
						vz = 0,
						tx = 0,
						tz = 0,
						slot = 1 + math.floor(
							FollowerSlots.unit(p.id, 31)
								* math.min(math.max(1, #members), FollowerSlots.capacity())
						),
					}
					local s = FollowerSlots.slot(mover.slot, density)
					launch(mover, x, z, cloudC + cloudW * s.dx, leadZ + s.dz)
					table.insert(movers, mover)
				end
			else
				table.insert(keptPending, p)
			end
		end
		pendingRunners = keptPending

		local frame: Frame = { members = {}, runners = {}, leavers = {} }
		local keptMembers: { Entity } = {}
		local bornCount = 0
		for _, m in members do
			if m.born then
				bornCount += 1
			end
		end
		for _, m in members do
			if m.leaveAt ~= nil and clock >= m.leaveAt then
				-- Detach: becomes a leaver that runs off on its own.
				local mover: Mover = {
					id = m.id,
					kind = m.leaveMode or "peel",
					omega = m.omega + 1,
					zeta = m.zeta,
					phase = m.phase,
					age = 0,
					x = m.x,
					z = m.z,
					vx = m.vx,
					vz = m.vz,
					tx = 0,
					tz = 0,
					slot = m.slot,
				}
				local side = m.leaveSide
				if side == nil then
					side = if m.id % 2 == 0 then "right" else "left"
				end
				local sign = if side == "left" then -1 else 1
				mover.tx = sign
					* (halfWidth - FollowerFlow.SIDEWALK_INSET + FollowerSlots.unit(m.id, 41) * 1.5)
				mover.tz = leadZ - 3 - FollowerSlots.unit(m.id, 42) * 5
				local leavers = 0
				for _, o in movers do
					if o.kind ~= "runner" then
						leavers += 1
					end
				end
				if leavers < FollowerFlow.LEAVER_CAP then
					table.insert(movers, mover)
				end
			else
				if not m.born and clock >= m.startAt and bornCount < FollowerSlots.capacity() then
					bornCount += 1
					m.born = true
					m.bornAt = m.startAt
					local x, z = sourceFor(m.id, m.hint, leadX, leadZ)
					m.x, m.z = x, z
					local tx, tz = slotTarget(m.slot, leadZ, sw, m.phase)
					launch(m, x, z, tx, tz)
					m.px, m.pz = nil, nil
				end
				if m.born then
					local tx, tz = slotTarget(m.slot, leadZ, sw, m.phase)
					if m.px == nil and m.bornAt == -math.huge then
						m.x, m.z = tx, tz -- settled members start on their slot
					end
					local tvx, tvz = feedForward(m.px, tx, dt), feedForward(m.pz, tz, dt)
					m.px, m.pz = tx, tz
					m.x, m.vx = FollowerSpring.step(m.x, m.vx, tx, tvx, dt, m.omega, m.zeta)
					m.z, m.vz = FollowerSpring.step(m.z, m.vz, tz, tvz, dt, m.omega, m.zeta)
					local age = clock - m.bornAt
					local y = 0
					if age < FollowerFlow.JOIN_HOP_SECONDS then
						y = math.sin(math.pi * age / FollowerFlow.JOIN_HOP_SECONDS)
							* FollowerFlow.JOIN_HOP_HEIGHT
					end
					table.insert(frame.members, {
						id = m.id,
						slot = m.slot,
						x = m.x,
						z = m.z,
						vx = m.vx,
						y = y,
						phase = m.phase,
						bobRate = m.bobRate,
					})
				end
				table.insert(keptMembers, m)
			end
		end
		members = keptMembers

		local keptMovers: { Mover } = {}
		for _, v in movers do
			v.age += dt
			local tx, tz, tvx, tvz = v.tx, v.tz, 0, 0
			if v.kind == "runner" then
				local s = FollowerSlots.slot(v.slot, density)
				tx, tz = cloudC + cloudW * s.dx, leadZ + s.dz
				tvx, tvz = leadVx, leadVz
			elseif v.kind == "merge" then
				tx, tz = leadX, leadZ - 4
				tvx, tvz = leadVx, leadVz
			end
			v.x, v.vx = FollowerSpring.step(v.x, v.vx, tx, tvx, dt, v.omega, v.zeta)
			v.z, v.vz = FollowerSpring.step(v.z, v.vz, tz, tvz, dt, v.omega, v.zeta)
			local dist = math.sqrt((v.x - tx) ^ 2 + (v.z - tz) ^ 2)
			local alive = true
			local y = 0.5 * math.abs(math.sin(clock * 14 + v.phase))
			if v.kind == "runner" then
				alive = dist > 1.2 and v.age < FollowerFlow.RUNNER_MAX_SECONDS
			elseif v.kind == "merge" then
				alive = dist > 2 and v.age < FollowerFlow.RUNNER_MAX_SECONDS
			else
				if v.arrivedAt == nil and dist < 1.5 then
					v.arrivedAt = v.age
				end
				local cheering = v.arrivedAt ~= nil
				if cheering then
					y = 0.9 * math.abs(math.sin(clock * 12 + v.phase))
				end
				alive = v.age < FollowerFlow.LEAVER_MAX_SECONDS
					and not (
						cheering
						and v.age - (v.arrivedAt :: number) > FollowerFlow.LEAVER_CHEER_SECONDS
					)
			end
			if alive then
				table.insert(keptMovers, v)
				if v.kind == "runner" then
					table.insert(frame.runners, { id = v.id, x = v.x, z = v.z, vx = v.vx, y = y })
				else
					table.insert(frame.leavers, {
						id = v.id,
						x = v.x,
						z = v.z,
						vx = v.vx,
						y = y,
						cheering = v.arrivedAt ~= nil,
					})
				end
			end
		end
		movers = keptMovers
		FollowerFlow.fit(frame, FollowerSlots.capacity())
		return frame
	end

	function self.counts(_)
		local runners, leavers = 0, 0
		for _, v in movers do
			if v.kind == "runner" then
				runners += 1
			else
				leavers += 1
			end
		end
		local pending = #pendingRunners
		for _, m in members do
			if not m.born then
				pending += 1
			end
		end
		return { members = #members, pending = pending, runners = runners, leavers = leavers }
	end

	return self
end

return FollowerFlow
