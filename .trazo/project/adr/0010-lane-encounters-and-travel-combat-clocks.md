# 0010: Lane encounters and independent travel/combat progression

**Date:** 2026-10-29  **Status:** proposed

## Context
Forced paired gates and left/right targeting cannot express optional +1/unlock lanes. RunDriver, Level and ServerClock couple travel to one elapsed-time line and would jump/extrapolate through a stationary boss fight. The owner requested forward parade, stop/resume bosses and shoot-to-unlock musical attacks, and delegated routine defaults to the architect (issue #120).

## Decision
Retain the pure-Luau authoritative simulation/presentation split (ADR0001). Introduce shared lane geometry, typed encounter lifecycles and distinct monotonic simulation time versus pausable route progress. RunState remains sole crowd/life/reward/consumption authority. Enemy and unlock progress and timed attack strength are separate explicit encounter state. Server resolves contact/target choice, checkpoints and level clearance; snapshots carry enough state to reconstruct them. Normal conversions, accepted loss magnitudes and all hard resource/safety limits remain except the explicit contact/target/cadence/product amendments in spec Amendment 9. Use the minimal three-lane/drum/two-mini-boss/final-boss defaults from Amendment 9.

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
- This ADR supersedes only the conflicting targeting, contact, cadence, completion and product-deferral clauses listed in spec Amendment 9. It does not supersede ADR 0001's stack or the crowd/loss authority of ADR 0006, 0007 and 0009.
