# 0014: Lanes have fixed roles: pickups, hordes, recruits

**Date:** 2026-10-31  **Status:** proposed

## Context
Spec Amendment 9 (ADR 0010) let a +1 pickup appear in any lane, put the stationary unlock target in the center lane and fixed the three boss lanes at left, right, left. Amendment 12 (issue #206) then moved every horde of a layout into one side lane. The owner's 2026-10-30 clarification on issue #120 describes the street as "mob control" with lanes that do different jobs: lane 1 +1 pickups, lane 2 the hordes you shoot, lane 3 "might be" random power-ups. The PM decided (issue #120, latest comment): lane 3 is reserved for recruit encounters from the roster (issues #230, #231, #232), not a random loot catalog, which #230 forbids. That supersedes the any-lane +1 reading of Amendment 9. No safety limit is involved.

## Decision
Each authored layout carries `laneRoles = { pickup, horde, recruit }`, a permutation of `left`, `center`, `right` (lane 1, 2, 3 are the roles in that order, not screen positions). `LaneGeometry` stays the only lane resolver.

- **Authored layouts (levels 1 to 3 of `Layouts.all`).** `horde` is the lane `bigOnLeft` already selects (Amendment 12). `pickup` is the opposite side lane. `recruit` is `center`.
- **Pickup lane.** A +1 pickup is authored only in the `pickup` lane. A pickup in any other lane fails `LayoutValidator`. Behavior of a pickup (crossing, once per id, exactly +1) is unchanged.
- **Horde lane.** Every cluster is in the `horde` lane (already validated since #206). The unlock target and every boss are also in the `horde` lane: they are things the player shoots, so the player steers to one shooting lane. This replaces Amendment 9's center-lane unlock target and its boss lanes (left, right, left). Boss strike lanes still cycle left, center, right, so the player must leave the shooting lane to dodge. An idle center lead still cannot win a checkpoint, because the center is not the horde lane.
- **Recruit lane.** Only recruit stations (spec Amendment 16, ADR 0015) are authored in the `recruit` lane. No other encounter type is.
- **Gates and obstacles are not lane-role encounters.** Paired math gates keep their left and right portals and obstacles keep their authored lanes. Encounter spans still may not overlap each other (ADR 0010 item 5); gates and obstacles are not encounters.
- **Test fixtures.** A layout that omits `laneRoles` is valid only if it authors no pickup, unlock target, boss or recruit station. The debug layout is such a fixture.
- **Markings.** The `LaneMarkings` role labels (#193) read `laneRoles` instead of a fixed left/center/right assignment.

## Alternatives considered
- Keep Amendment 9 (any-lane +1, center unlock): the accepted design, but lanes then have no distinct jobs, which the owner asked for.
- Random power-up catalog in lane 3: forbidden by #230 and not decided by the owner.
- Fixed positions (left pickups, center hordes, right recruits): contradicts Amendment 12's existing choice of a side horde lane per layout.
- Leave the boss lanes at left, right, left: puts the shooting lane on a different side in the same level, which fights the one-shooting-lane rule.

## Consequences
- Supersedes only: Amendment 9's "any-lane" pickup placement and first-strip left/right/center rotation, its center-lane unlock target, and its boss lane assignment. Superseded clauses are listed in spec Amendment 15. ADR 0010 and Amendment 9 are not edited.
- Layout data gains one field; `LayoutValidator`, `Layouts`, `LaneMarkings` and the bot read it.
- All lane numbers and positions are provisional design defaults, UNVERIFIED for readability and balance. Prior balance evidence stays stale (#148).
- Lane 3's role is only recruits. A future reward type for it needs a new decision record.

**Rule:** A layout's pickups lie only in its pickup lane; its clusters, unlock targets and bosses only in its horde lane; its recruit stations only in its recruit lane.
