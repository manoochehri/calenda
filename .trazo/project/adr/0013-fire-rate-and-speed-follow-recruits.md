# 0013: Projectile speed and fire rate follow the recruit count; the first shooter fires one at a time

**Date:** 2026-10-31  **Status:** proposed

## Context
Owner rule (2026-10-31, issue #234, P0): the player's projectile speed and fire rate reflect how many parade people are recruited. The initial player, with zero recruits, fires one projectile at a time: the next shot waits until the current one has hit, missed or left the playfield. ADR 0004 made fire continuous at `min(20, 6 + sections)` shots per second with a fixed projectile speed; issue #148 repeated a 3 shots/sec line with unchanged speed.

## Decision
`Config.firing.tiers` is one table mapping recruits (the server's `crowdTotal`) to shots per second, projectile speed (studs/s) and the most projectiles in flight at once. Row 0 has `maxInFlight = 1`. `Targeting` models each shot's flight on the server (hit: distance over tier speed with the existing clamps and gift scale; miss: `ShotLook.MISS_SECONDS` scaled by reference speed over tier speed) and starts a shot only while fewer than `maxInFlight` are unresolved. The server sends the speed it used as an optional validated field on the shot event, so the client draws it. The numbers are provisional [default] and UNVERIFIED for feel. This supersedes the rate curve of ADR 0004 and spec Amendment 2 (`firing.base`, `firing.cap`, `firing.perSection` are removed) and the cadence line of #148. Unchanged: continuous fire as hit-or-miss, hitscan credit-once, one hit per shot, target selection and lanes, `giftEveryNthShot` (1 in 100), the loss rules, `maxTotal`, server authority.

**Rule:** The initial player fires one projectile at a time; speed and rate never decrease as recruits grow and are strictly higher at the top row.

## Consequences
The early conversion pace is set by the zero-recruit row, so the earlier balance evidence (the #17 ladder, #148 sweeps) is stale and must be re-measured. `LayoutValidator` still simulates only the row-0 rate and does not model shots in flight, so it is optimistic for the first seconds. Recruited characters' distinct attacks (#230 to #232) are not covered here and must not contradict one-at-a-time for the initial player.
