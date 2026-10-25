# Mob waves: Studio checklist (issue #65)

**Status:** UNVERIFIED. Nothing in this list has been run in Roblox Studio or on a phone yet. The
pure rules are Lune-tested (`make test`); how the waves look, feel and perform is not.

## Caps and budgets (from `src/shared/QualityConfig.luau` and `Config.spectators.scatter`, [default] values)

Spectators are individuals (owner direction 2026-10-25: no grouped bunches). A +5 cluster stands
10 individuals, a +15 cluster 30 (`Config.spectators.scatter.perReward` = 2). They spread across
the lane with at least 2.1 studs between any two and never more than 2 in one bunch.

| Level | Max individuals per mob | Mobs drawn | Figures on screen | Dust emitters | Emitters in total | Puff bursts (worst case) |
|---|---|---|---|---|---|---|
| high | 90 | 20 | 300 | 8 | 14 | 640 |
| medium (phone default) | 60 | 16 | 200 | 5 | 11 | 240 |
| low | 30 | 12 | 100 | 3 | 9 | 72 |

Emitters = dust emitters + 6 warning chevrons. Puff bursts are transient `Emit` calls. Each figure
is 3 Parts (body, head, arms). A figure far up the lane is enlarged up to `maxScale` (2x) so it
still reads. The on-screen cap is the figure budget: spectators past it are not drawn.

## Checks in Studio

1. Set the quality level with the player attribute `CalendaQuality` (`high`, `medium` or `low`) and
   confirm the individuals per mob and the figure count do not pass the table above.
2. Start a run and confirm no wave is in view for the first 5 s.
3. Confirm each wave appears at the top of the screen as a faded, scaled-in mob (no pop), with a
   warning chevron ahead of it, and that it takes at least 3 s to reach the parade.
4. Confirm the spectators read as individuals spread across the lane (no bunch of more than two),
   coming at the player from the top of the screen, and that each figure is readable from the high
   camera, including the ones at the top of the lane. Then they slam the parade and scatter.
5. Confirm a converted mob recolours to the party palette and streams into the parade.
6. Confirm the music swells as an unconverted wave closes in, and eases off once it is converted or gone.
7. Frame time: 30 FPS or better on the phone emulator with the biggest wave on screen, at the
   default (medium) level. **UNVERIFIED until measured on the named phone.**
8. Note any stutter in the Studio output (`debug.profilebegin` labels `Calenda/...`) and record it on
   issue #65 with the device and level.
