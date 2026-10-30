# 0010: Lane encounters and independent travel/combat progression

**Date:** 2026-10-29  **Status:** accepted
Accepted: 2026-10-29 by architect review on issue #120 (comment "approve").

## Context
Forced paired gates and left/right targeting cannot express optional +1/unlock lanes. RunDriver, Level and ServerClock couple travel to one elapsed-time line and would jump/extrapolate through a stationary boss fight. The owner requested forward parade, stop/resume bosses and shoot-to-unlock musical attacks, and delegated routine defaults to the architect (issue #120). The architect's must-change review of this record is on issue #120; this revision applies its six answers, checked against origin/main 372dbc6.

## Decision
Retain the pure-Luau authoritative simulation/presentation split (ADR0001). Introduce shared lane geometry, typed encounter lifecycles and distinct monotonic simulation time versus pausable route progress. RunState remains sole crowd/life/reward/consumption authority. Enemy and unlock progress and timed attack strength are separate explicit encounter state. Server resolves contact/target choice, checkpoints and level clearance; snapshots carry enough state to reconstruct them. Normal conversions, accepted loss magnitudes and all hard resource/safety limits remain except the explicit contact/target/cadence/product amendments in spec Amendment 9. Use the minimal three-lane/drum/two-mini-boss/final-boss defaults from Amendment 9.

The architect's answers to the six must-change items are binding for implementation:

1. **LaneGeometry replaces `Level.sideOf` for gameplay.** The pure `LaneGeometry` module replaces `Level.sideOf` (src/shared/Level.luau:66-74) in Targeting (src/shared/Targeting.luau:132), contact (src/shared/RunHooks.luau:38) and the wave-side rule (src/shared/LayoutValidator.luau:201-206). `spectators.centerTolerance` (src/shared/Config.luau:410) is retired after migration. Authored spawn x values do not change, so spectator placement does not change. This supersedes Amendment 5's "center engages no horde" (spec line 268): center steering now engages the center lane.
2. **Explicit lane field.** Every cluster, pickup, unlock target and boss carries an authored `lane` field. LayoutValidator asserts `lane == LaneGeometry.laneOf(spawn.x)` in place of the side check. Contact and targeting read the authored lane; only the lead's lane is derived, from its continuous x at the crossing.
3. **One clamp.** `Steering.bound(halfWidth, leadLimit)` is the only clamp on lead x. It returns `min(halfWidth - Steering.EDGE_MARGIN, leadLimit)` (src/shared/Steering.luau:8, 13-14). The server (src/shared/RunDriver.luau:194, with `Steering.clampTarget` at :229) and the client (src/client/Main.client.luau:133) both call it, as does src/shared/Hazards.luau:71. `leadLimit` is a per-layout field, a constant for that layout. It is not a function of z. The effective limit is min(18.5, 15) = 15.
4. **Plaza coincidence.** `plazaStart` equals the final checkpoint, z=1296 (src/shared/Layouts.luau:104). The gate and obstacle rule (`z >= plazaStart`, src/shared/LayoutValidator.luau:124-125 and 153-154) still rejects that equality. The checkpoint validator allows `z == plazaStart` for the final boss only. The plaza branch (src/shared/RunDriver.luau:393-396) becomes `stage == cleared`, so the plaza never triggers clearance. Order on the tick: the defeat check (RunDriver.luau:385-392) runs first; then travel clamps to 1296, discards that tick's unused distance and enters final-boss-combat; victory sets cleared; cleared runs the 8-second celebration and then advances.
5. **Replicated contract.** `StatePayload` (src/shared/Remotes.luau:26-37) gains `runId`, `levelId` (`level` remains the 1-based index), `simTime` (distinct from `t`), `zVelocity`, `stage`, `encounter` {id, kind, progress, remaining, active} and `boostExpiry`. `encounter` is a single object because at most one encounter is active per authored layout. LayoutValidator enforces this in `structure()` (src/shared/LayoutValidator.luau, beside the gate and obstacle checks at :124-125 and :153-154): a layout whose encounters overlap in active span fails validation. The rule is new and is added with the encounter schema (#156). `phase` stays `ready|running|over`; `Remotes.isPhase` (PHASES at :66) is unchanged. `stage` is `traveling|mini-boss-combat|final-boss-combat|cleared`, decoded by a new `Remotes.isStage`. `encodeState` (:112-119) keeps its `over` handling. The decoder ships with the server.
6. **Supersession and loss sources.**
   - ADR 0007's horde trigger, the clause "An unconverted horde that reaches the parade" (ADR 0007 Decision, Horde bullet), is superseded by the lane-gated attack in spec Amendment 9. Its formula, floor rounding and `minShareLoss = 1` are unchanged.
   - The boss strike is a new loss source under ADR 0009's share rule: `max(minShareLoss, floor(Config.attackSharePercent × total / 100))`. It reads `Config.attackSharePercent`, not a literal 7. ADR 0009 is not edited.
   - ADR 0004 keeps the gift cadence (every fourth shot, counted over all shots). The dancer prerequisite for gifts (spec §4 line 37 and Amendment 1 line 165) is superseded: the cadence runs from run start.

These defaults are provisional design choices, UNVERIFIED for balance, readability and performance. This record stays `proposed` until architectural approval.

**Rule:** None

## Alternatives considered
- Forced gate pair for every pickup: cannot miss a reward.
- Stop the shared clock: freezes combat and warnings.
- Set speed to zero in z=speed*t: causes a resume jump.
- Client-only boss pause: server and view disagree.
- Per-person pathfinding or unbounded rendering: unnecessary structural or resource change.
- Rewrite the game: the existing authoritative, pure and view boundaries are reusable.

## Consequences
- Schedule, validator, bot and client contracts must migrate together.
- Existing balance evidence becomes stale and must be re-run (#148).
- Boss fights increase wall-clock duration beyond the 90-second travel route.
- Rendering investigation preserves logical gameplay. No phone performance or balance result is implied.
- Supersedes only the conflicting clauses listed in Decision items 1, 4, 5 and 6: Amendment 5's center rule, ADR 0007's horde trigger, the dancer gift prerequisite, and the boss, plaza-completion and product-deferral clauses that spec Amendment 9 replaces. It does not supersede ADR 0001's stack, ADR 0004's cadence, ADR 0006's crowd authority, ADR 0007's formula, or ADR 0009's share rule.
- Spec Amendment 9 keeps its existing wording except the deleted rename sentence. Where it says "phase" for traveling, mini-boss-combat, final-boss-combat and cleared, this record's `stage` carries those values; `phase` stays `ready|running|over`.
