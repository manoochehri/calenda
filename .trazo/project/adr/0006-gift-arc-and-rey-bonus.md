# 0006: Gifts are two meter hits on a gift arc, and Rey is a bonus target

**Date:** 2026-10-24  **Status:** accepted (owner decisions in issue #93); engineer choices marked below are proposed for PM confirmation

## Context
Issue #93 (owner, 2026-10-24) asks for three things. A gift (the every-fourth shot, ADR 0004 cadence) should travel in a high, slow looping arc. A gift that hits one recruitable cluster should add two meter hits to it, not one. Rey, the seeded parade cameo from #92 / PR #90, should be a targetable bonus that pays followers. ADR 0004 and spec §4 say every shot is exactly one hit; that rule stays for notes and hearts.

## Decision
- **Gift = two meter hits.** A gift shot applies `Config.giftMeterHits` (2) hits to its one target cluster. The meter caps at full and the cluster credits and pays its reward once. Any surplus does not carry to another cluster. Notes and hearts remain one hit. The gift cadence and the total shot count are unchanged; a gift replaces a scheduled shot and is not an extra one.
- **Gift arc.** A gift flies a high arc (`giftArc.height`) with `giftArc.loops` whole sideways loops (`giftArc.loopRadius`) and takes `giftArc.slowdown` times a note's flight time. This is a presentation change only; the server decides nothing from it.
- **Rey is a bonus target.** Rey takes a shot only when (a) no cluster is eligible and (b) the lead is steering toward Rey's lane side (`ReyFormation.side(seed)`). Such a shot is a Rey hit: no cluster id, no meter, and it is one shot event like any other. The first Rey hit per run adds `Config.rey.bonus` (5) to `crowdTotal` (`RunState.awardRey`); later hits add nothing. A Rey hit never moves a cluster meter.
- **Rey's position.** Rey is drawn `Config.rey.aheadStuds` (12) ahead of the lead, in the outer lane. He was behind the lead before; a forward-only shot cannot reach him there. The server and client compute the same pose from `ReyFormation.pose`.
- Server authority is unchanged: totals, cluster conversion and the Rey award are decided in `Targeting` and `RunState` only. Rey and gift events are display payloads.

**Engineer choices (proposed; PM to confirm):**
1. Rey is a fallback, not a peer of clusters. A cluster in range always wins, so Rey never starves meters.
2. Rey only takes shots while the lead steers toward his lane. A centred lead keeps the continuous-fire miss (ADR 0004), so the no-input and centred-steer runs are unchanged by Rey.
3. `awardRey` logs a `rey_bonus` run event. `RunLog` does not yet summarise it; the structured log is a known gap.

**Balance consequence (provisional).** With gifts worth two hits, the no-input run no longer ends defeated, which breaks the Amendment 1 check. `attackDamage` for the large cluster is raised from 12 to 20 in `Config` to restore it. The small-cluster value and the competent run are unchanged in the checks. This needs a ladder re-run and skeptic review before it is trusted.

## Alternatives considered
- Rey as a regular candidate ranked by distance: the nearest target would win, starving clusters or making Rey take most shots.
- Rey behind the lead as before: shots fly forward, so he could never be hit.
- Rey as a fallback on any steer: every no-cluster miss becomes a Rey hit, which removes the continuous-fire miss contract for most of the run.

## Consequences
- Gifts convert clusters faster. The debug layout's attack numbers are provisional, as they were under ADR 0004.
- Rey's pose moved, so `tests/reyformation.test.luau` now asserts the forward placement.
- Studio checks remain UNVERIFIED: arc readability, whether Rey in the outer lane occludes gates or spectator sight lines, and whether steering-gated Rey is discoverable. See the PR checklist.
