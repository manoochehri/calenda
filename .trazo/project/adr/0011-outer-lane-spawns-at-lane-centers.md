# 0011: Outer-lane spawns move to the lane centers

**Date:** 2026-10-29  **Status:** accepted
Accepted: 2026-10-29 by architect decision on issue #156

## Context
ADR 0010 Decision 1 kept authored spawn x values unchanged, so spectator placement would not change. Spec Amendment 9 (Rendering) instead says to move outer-lane spawn x positions to lane centers without deleting mobs. Production layouts spawn each outer pair's groups at x = ±16 (`buildClusters` in `src/shared/Layouts.luau`: `smallX` and `bigX`, where `bigX = -smallX`). The lane bands in `LaneGeometry` are [-15,-5), [-5,5) and [5,15], with centers -10, 0 and 10. x = ±16 falls in no band, so `LayoutValidator` cannot assign a lane to those spawns under `lane == LaneGeometry.laneOf(spawn.x)` (ADR 0010 Decision 2). Issue #156 was blocked on this conflict.

## Decision
This supersedes ADR 0010 Decision 1, only the clause "Authored spawn x values do not change", and only for outer-lane clusters. Both groups in each outer pair move: `smallX` and `bigX` (`bigX = -smallX`), so the outer-pair groups go from ±16 to ±10, the lane centers, as Amendment 9 states.

**Dependency note:** `LaneGeometry` is not yet on `main`. The lane-band citation in Context (bands [-15,-5), [-5,5), [5,15] and their centers) rests on ADR 0010 alone until #156 lands and provides the module. Spawn z, `spawnTime`, group counts and soaks do not change. Every other clause of ADR 0010 Decision 1 stands, and so does the rest of ADR 0010.

## Alternatives considered
- Keep x = ±16 and define `laneOf(|x| > 15)` as the outer lane: keeps placement, but adds a rule the spec does not state.
- Keep x = ±16 and widen the outer lane bands to [-inf,-5) and [5,inf): the same new rule with a wider band.

## Consequences
- Every authored layout's outer-lane spawns must be re-validated with `LayoutValidator` after the move.
- The contract migration includes the authored `cluster.lane` field, which the validator checks against `laneOf(spawn.x)`.
- No other ADR 0010 consequence changes. Calm-opening and Emergence checks are z-based and are expected to pass unchanged, but this is UNVERIFIED until `LayoutValidator` re-runs.
