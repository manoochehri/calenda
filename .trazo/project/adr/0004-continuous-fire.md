# 0004: The parade shoots continuously

**Date:** 2026-10-24  **Status:** accepted

## Context
Owner feedback on 2026-10-24, twice: "the shooting should just be continuous" and "the projectiles are weak and seldom." Today `firing.base` is 3 shots per second (cap 12), a shot fires only when an eligible target is in range, and the shots are small with no trail or impact. Spec §3 says "No target means no projectile spam" and Amendment 1 says "No eligible target means no shots."

## Decision
Firing is continuous: the parade shoots at the firing-rate curve whether or not a target is in range (owner decision 2026-10-24). The curve gets named defaults `firing.base = 6` (was 3) and `firing.cap = 20` (was 12), with +1 per section kept. A shot with an eligible target is a hit exactly as before (credit once, meters, gift cadence). A shot with none is a visual-only miss that never credits, damages or consumes anything and is replicated as a bounded, owner-only, display-only `miss` Event. This supersedes "no target means no shots" in spec §3 and Amendment 1; the spec's Amendment 2 carries the details. The base rate change makes the earlier HP and recruit balance evidence stale, so the #17 ladder is re-run after this lands.

**Rule:** None

## Alternatives considered
- Keep "no target, no shots" and only enlarge the shots: does not answer "continuous"; shots stay seldom.
- Derive misses on the client from the fire clock: the client would have to guess the server's shot schedule (section count, gift cadence, per-step catch-up), so it would drift from the server; an explicit event is smaller to reason about and keeps one source of truth.
- Raise only the rate and leave the visuals: the owner called the projectiles weak as well as seldom.

## Consequences
More shots, so more events: up to 20 per second per player instead of 12, still far below the 240 per second hard ceiling of the per-tick cap. Balance numbers (debug layout offsets, `maxTotal`) are provisional until the ladder is re-run. Revisit the rate if mobile frame time suffers (spec §12) or if the owner retunes `firing.base` / `firing.cap`, each one Config line.
