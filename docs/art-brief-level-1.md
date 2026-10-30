# Level 1 art brief: the Oaxacan street

Words only. No image, photo, face, sign, shop front or branding is reproduced or committed; the
owner's reference screenshots stay local. The numbers below live in `src/shared/LevelTheme.luau`
(one table per level; the later pueblo and playa levels, #57, are other tables of the same shape).
The street is built by `StreetLayoutGen` (pure, seeded) and `OaxacaStreet` (client builder).

## Attribution and community note

Spec s10: treat outfits, dances and street traditions as distinct referenced traditions, not as
interchangeable generic "Oaxaca" costume. Confirm the specific community attribution with the
owner before any text label, sign, caption or credit names a community, festival or tradition.
Until then this level carries no such labels: the street is generic colonial-Mexican festival
architecture, and nothing on a facade, flag or lamp is lettered.

## Feel

A narrow colonial street in bright daylight with a blue sky, in a festival mood. Warm, saturated,
slightly weathered paint; dark iron; paper flags overhead. The road, the gates, the lead and the
crowd stay the plainest, clearest things on screen: all the festivity sits at the edges and above.

## Palette (hex)

| Token | Hex | Use |
|---|---|---|
| ochre | #E8AC3A | facade |
| terracotta | #CC5838 | facade |
| pink | #E06092 | facade |
| lavender | #7E70C4 | facade (darker than a pastel so it separates from the plaza) |
| white trim | #FAF2E2 | cornices, plinth bands, window and door surrounds |
| iron | #1E1C1E | grilles, balcony railings, lamp posts |
| window glass | #283446 | dark window and arch openings |
| cantera stone | #B8C2A6 | stone-block corner buildings and the church wall (grey-green) |
| road | #383332 | warm dark flagstone: followers, gates and the lead read on it (3:1 or more vs the ground plate) |
| road course alt | #46403F | alternate flagstone course, a subtle step (contrast 1.15 to 1.5 vs road; 3:1 or more vs ground) |
| yellow curb stripe | #F4C22C | painted line at the road edge |
| sidewalk | #CDC4AC | pale cantera pavement, |x| 14 to 20 |
| forecourt | #B2A892 | pavement from the sidewalk to the facades (|x| 20 to 28) |
| earth plate | #AA8C64 | the plain ground around everything |
| plaza paving | #C49868 / #B0865C | zocalo checker |
| papel picado | pink #782C4E, orange #783303, yellow #57451B, green #1B5132, blue #1F4877, purple #5B377A | dark jewel tones so each flag reads 3:1 or more against the sky and 2:1 or more against every facade wall; never two neighbours alike |
| farol glass / light | #FFD682 / #FFC878 | lamp lantern and PointLight |

Contrast (WCAG ratio) is checked in `tests/leveltheme.test.luau` for every pair that matters:
road vs follower, lead, ring, spectator, both gate banners and every facade; sidewalk, forecourt,
ground and plaza vs each other, vs the crowd colors and vs every facade; plaza vs the dancers.
Lead and ring against the sidewalk are only 1.25 and 1.2 (they walk on the road, which gives them
4 and above); the multiplier banner on the plaza is 1.05 and relies on its numerals, icon and dark
stroke. Those two trade-offs are deliberate and written next to the numbers.

Issue #54 contrast: every papel picado flag is at least 3:1 against the sky (the Atmosphere color)
and at least 2:1 against every facade wall and the stone corner; road and road course alt are at
least 3:1 against the ground plate. The flags are dark because a light flag cannot reach 3:1 on the
pale sky, and the lavender wall (the darkest facade) sets the ceiling of 2:1. As a result the six
flags share nearly one luminance and differ by hue, not value; the Studio check decides whether
that reads.

## Buildings

Two-storey colonial buildings (about 70% of modules) are solid blocks about 9 studs deep, painted
in the four wall colors, never the same color twice in a row on one side. Their thick roof caps
overhang the street-facing wall and the side edges. Most two-storey colored buildings carry a wide,
projecting iron balcony slab; the repeat of roof volume and balconies should read from the high
camera before the finer facade details do. Roughly a quarter of the street modules are one-storey
shopfronts with a wide barred window and a door. Every ninth module (and the first) is a
stone-block corner building in cantera grey-green with iron trim. In the plaza zone the street
becomes an arcade of tall arches. Beyond the end of the street stands a church-like stone wall with
two towers.

Details, drawn as Frames on one SurfaceGui per facade (no Part per window):

- windows: dark glass, a white or iron outline, about half with an arched head; ground-floor
  windows always carry an iron grille outline;
- doors: an iron-dark door with a white surround, arched about 60% of the time;
- balconies: a projecting iron slab (one Part) on most two-storey colored buildings, with a railing
  outline on the wall above it, over the upper windows;
- no lettering, no signs, no shop names.

Building height is 13 to 20 studs plus a 1.5 stud roof cap (top at most 21.5). They stand with their
street-facing wall at |x| = 28, beyond the sidewalk edge (|x| = 20), so the wall volume and roof cap
stay outside the camera corridor to the road, gates, spectators and lead (see "Camera rule").

## Papel picado

Strings of small colored paper flags run along the street (not across it), on two lanes per side
at |x| = 23.5 and 26.5 and heights 22 and 25: from the high camera they converge toward the
vanishing point. Each string is a Part with a SurfaceGui; every flag is a colored Frame on that
GUI and a thin cord Frame carries them: about 44 strips and 1,700 Frames for the whole street, not
a Part per flag. The strips cut no hole in play space: see "Camera rule".

## Road, curb, sidewalk

Flagstone: six lengthwise courses across the road in two nearly equal dark tones (Cobblestone
material), so the converging lines add depth without competing with gate text. A yellow stripe
runs along each road edge. Sidewalks are pale pavement; the forecourt beyond them is a slightly
darker pavement so the facade feet are anchored. The dashed center line of the road stays.

Layering (issue #85): flat ground things never share a height. `src/shared/LayerHeights.luau`
names the tops: earth plate -1.1, road slab -0.2 (a 0.2 kerb below the sidewalks), ground 0
(sidewalks, forecourt, plaza, road courses), markings 0.2 (curb stripe, dashes, plaza paving),
decals 0.4 (gate crossing strips, cone feet), lead ring 0.6, gate pass ring 0.8, landed confetti
1.0. Any two that overlap differ by at least 0.2 studs; a test checks every pair in the world.

## Farol lamps

Black iron lamp posts (9 studs) with a warm glowing lantern, alternating sides about every 96
studs on the forecourt edge (|x| = 21.5). Only about a dozen carry a PointLight (warm, range 24,
no shadows): the pools of warm light are sparse by design.

## Sky and light

Bright warm daylight: ClockTime 14.5, Brightness 2.6, a warm ColorShift_Top, soft shadows
(ShadowSoftness 0.6), warm ambient. A blue Atmosphere (light haze, warm decay) gives the sky
without any Sky asset; fog is pushed far out so the street stays crisp. No asset ids anywhere.

## Distant scenery

The street sits within a broad earth-colored ground plate so the high camera does not show the
empty baseplate around the route. Beyond the street walls, paired rows of simple trees and broad,
muted hillside silhouettes continue the view toward the horizon and frame the street and plaza.
Use a fixed, symmetrical layout: the silhouettes are the same on every reset and sit well outside
the road and camera corridor. Keep their greens and stone-like hill colors subdued so the bright
facades, road, gates, lead and parade remain the visual focus. The scenery is made from native,
anchored, non-interactive geometry with no asset IDs.

## Zocalo plaza

At the end (the plaza begins at `layout.plazaStart`, currently 648 studs, and the street ends at
`layout.streetLength`, currently 720 studs at the slower 7.2 studs/s pace): a checker of two warm
paving tones, a kiosco (bandstand: round base, six posts, a terracotta roof and dome) just behind
the end of the street, trees (trunk plus two round crowns) in a row on each side outside the plaza
floor, the arcade facades, more flag strings on the same lanes, and the church-like wall behind.
The plaza floor stays clear: the finale spreads dancers over all of it.

## Camera rule (heights against CameraRig)

The camera sight lines to the lead, the next gate row and the spectators run between the camera
(|x| at most half the lead's x) and targets inside the corridor |x| <= 20, so nothing standing at
|x| > 20 can be on them sideways. All dressing therefore stays outside |x| = 20 (flags 23.5 and
up, lamps 21.5, trees 24.5, facades 28 and beyond), and everything is lower than the camera (46)
minus two clearances. Flags hang above the tallest standing prop (CameraRig.TALLEST_PROP, now the
gate portal at 19): their lowest edge is 20.8. A pure test sweeps 120 camera and lead positions
(pullbacks 1, 1.2, 1.4) against every box the street generates and finds none on a sight line,
with a control wall that is detected, so the test can fail.

## Mirror

The generator uses WORLD x (left negative); `OaxacaStreet` applies `ViewMap.x` to every Part
position. Facade colors come from the seeded sequence, never from the side name, so the mirror
cannot swap a meaning; a test checks every style appears on both sides.

## What not to do

- Do not reproduce any real person, face, sign, shop, logo or photo; no asset ids or textures.
- Do not add lettering or name a community before the owner confirms attribution.
- Do not put anything inside |x| < 20 or hang flags across the road where they cross the camera's
  line to the lead or the next gate row.
- Do not make facades pastel-white or the road pale: the dark road is what makes followers, gates
  and the lead readable.
- Do not add a Part per flag or per window; the generated street stays under the
  600-Part limit checked by the Lune budget test.

## Studio checklist (presentation is UNVERIFIED until done)

- [ ] 16:9, 4:3 and 19.5:9 landscape: facades fill both sides along the whole route, from the first
      second to the plaza; the road, gates, lead and crowd stay the clearest things.
- [ ] No flag string, lamp, facade or tree ever covers the lead, the next gate row or a spectator
      while running the whole street; pullback at maximum too.
- [ ] Building thickness, overhanging roof caps and projecting balconies read as 3D buildings from
      the game camera and do not cover gameplay.
- [ ] Frames on SurfaceGuis render (windows, arches with rounded corners, flags); the flags face
      inward on both sides and are not mirrored wrongly; the frame order is irrelevant.
- [ ] Road courses and curb stripes do not z-fight with the road, the center-line dashes or the
      plaza at camera distance; the Cobblestone material looks fine from the high camera.
- [ ] Atmosphere, ColorShift and ShadowSoftness give a bright blue-sky day with soft shadows, not
      washed out; the street far ahead is not fogged.
- [ ] About a dozen PointLights are fine on a phone; the whole street builds over several frames
      without a visible hitch and the progress callback reaches 1.
- [ ] Record the phone model and frame rate while the whole street builds; compare with the
      generated Part/GUI counts printed by the Lune budget test.
- [ ] Restart (reset) twice: Backdrop.build leaves exactly one street and one Atmosphere.
