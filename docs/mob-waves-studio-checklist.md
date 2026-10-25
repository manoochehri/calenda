# Mob waves: Studio checklist (issue #65)

**Status:** UNVERIFIED. Nothing in this list has been run in Roblox Studio or on a phone yet. The
pure rules are Lune-tested (`make test`); how the waves look, feel and perform is not.

## Caps and budgets (from `src/shared/QualityConfig.luau`, [default] values)

| Level | Mob scale | Max spectators per mob | Mobs drawn | Figures on screen | Particles per mob | Particles in total | Emitters | Puff bursts (worst case) |
|---|---|---|---|---|---|---|---|---|
| high | 1.5 | 2000 | 20 | 300 | 1500 | 6000 | 34 | 960 |
| medium (phone default) | 1.0 | 1200 | 16 | 200 | 900 | 3500 | 27 | 360 |
| low | 0.5 | 600 | 12 | 100 | 400 | 1500 | 21 | 108 |

Emitters = mobs + dust emitters + 6 warning chevrons. Puff bursts are transient `Emit` calls on top of
the steady particles. Each figure is 3 Parts (body, head, arms).

## Checks in Studio

1. Set the quality level with the player attribute `CalendaQuality` (`high`, `medium` or `low`) and
   confirm the mob sizes change and the figure count does not pass the table above.
2. Start a run and confirm no wave is in view for the first 5 s.
3. Confirm each wave appears at the top of the screen as a faded, scaled-in mob (no pop), with a
   warning chevron ahead of it, and that it takes at least 3 s to reach the parade.
4. Confirm the mob charges as a dense mass (not separate small groups), slams the parade, and then
   scatters to the sidewalks.
5. Confirm a converted mob recolours to the party palette and streams into the parade.
6. Confirm the music swells as an unconverted wave closes in, and eases off once it is converted or gone.
7. Frame time: 30 FPS or better on the phone emulator with the biggest wave on screen, at the
   default (medium) level. **UNVERIFIED until measured on the named phone.**
8. Note any stutter in the Studio output (`debug.profilebegin` labels `Calenda/...`) and record it on
   issue #65 with the device and level.
