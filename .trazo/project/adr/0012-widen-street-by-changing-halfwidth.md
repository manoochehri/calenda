# 0012: Widen the street by changing one number (`StreetGeometry.HALF_WIDTH`)

**Date:** 2026-10-30  **Status:** proposed
Proposed by architect finding on issue #54 and issue #220; the owner confirms the half-width below. This record changes no code; it gates step 2.

## Context
The owner reported (2026-10-30, three phone screenshots) that the play area looks too narrow. The street is 40 studs wide (`halfWidth` 20; road 30 studs, sidewalks 5 each). `StreetGeometry` (issue #220, PR #221) is now the single definition: the road, the three lane bands and centers, the default lead limit and the outer-lane spawn x all derive from `HALF_WIDTH`, so widening is one edit rather than a change spread over about twenty files.

Corridor (2 x halfWidth) share of the screen width at the lead's row, computed from `CameraRig` with the true view-axis depth (pinhole math, vertical FOV 70; one computed value per cell, no sampling; throwaway script, not committed):

| Camera, aspect | halfWidth 20 (now) | 24 | 28 | 32 |
|---|---|---|---|---|
| pullback 1.0, 19.5:9 phone | 25.8% | 31.0% | 36.2% | 41.3% |
| pullback 1.4, 19.5:9 phone | 18.5% | 22.1% | 25.8% | 29.5% |
| pullback 1.0, 16:9 | 31.5% | 37.8% | 44.1% | 50.4% |
| pullback 1.0, 4:3 tablet | 42.0% | 50.4% | 58.8% | 67.2% |
| pullback 1.4, 4:3 tablet | 30.0% | 36.0% | 42.0% | 48.0% |

The camera zooms out from pullback 1.0 to 1.4 as the parade grows, which shrinks the street by about 28% later in a run. A 40% corridor share on a 19.5:9 phone needs a half-width of about 31 at pullback 1.0 and about 43 at 1.4: width alone cannot reach 40%. Narrowing the vertical FOV instead was tried at 60 degrees: the unit suite went to 972 passed, 24 failed (the 3 s visible-approach rule of #65 and the parade-on-screen rule of #114), so it is rejected.

Measured with `HALF_WIDTH` 24 and 28 on throwaway copies of main (full unit suite, 1 run each): 990 and 989 passed, 15 and 16 failed. The #114 tests (sections and follower slots fully on screen at pullback 1.0 to 1.4, 16:9) did not fail. The failures are tests that pin the old literals (lane bands, centers, the 30-stud road, the pinned sidewalk drift: expected) and two geometric rules that need re-layout when the corridor widens: facade heights against the corridor (`leveltheme.test.luau`) and plaza props against the street end (`streetlayoutgen.test.luau`).

Known drift to settle: `FollowerSlots` and `ObstacleFeedback` assume a 6-stud sidewalk (road half-width 14) while WorldBuilder draws 5 (road half-width 15); `StreetGeometry.FOLLOWER_SIDEWALK_WIDTH` pins it so this ADR resolves it on purpose.

## Decision
Set `StreetGeometry.HALF_WIDTH` to **28** (street 56 studs wide; road 46, outer lane edges +-23, inner +-7.67, outer lane centers +-15.33). **The owner confirms or changes the number**; 24 (48 wide) is the smaller alternative. The decision is the mechanism, not the number: change `HALF_WIDTH` and nothing else, and let the derived values follow.

- This supersedes only these numbers, each in the clause that carries it: the lead limit 15 ("The effective limit is min(18.5, 15) = 15") in ADR 0010 Decision item 3; and the lane band edges [-15,-5), [-5,5), [5,15] and centers -10, 0, 10 as quoted in ADR 0011's Context and in spec Amendment 9 (ADR 0010 Decision item 1 defines the `LaneGeometry` resolver but states no band numbers). It builds on ADR 0011, which already narrowed Decision item 1's clause "Authored spawn x values do not change" for outer-lane clusters (spawns at the lane centers, +-10); the new lane centers replace that +-10. Everything else in those records stands (the lane field, one clamp, authored lane per cluster, the `laneOf` ownership rule).
- A spec amendment states the new lane bands (the bands are in spec Amendment 9).
- The 5-versus-6 sidewalk drift is resolved: followers and obstacle feedback use the sidewalk width WorldBuilder draws (`StreetGeometry.sidewalkWidth`), and `FOLLOWER_SIDEWALK_WIDTH` is removed.
- Facade heights and plaza props are re-laid out for the new corridor; the two failing geometric tests pass by re-layout, not by loosening them.
- Before merge the skeptic re-runs LayoutValidator, the policy ladder and the witness search, because lane width changes spawn spacing and the scatter (`spreadHalfWidth = 8` against a 10-stud lane now) and so the balance numbers on #148. No "easier" or "harder" claim beyond those numbers.
- Unchanged: server authority, `crowdTotal`, the loss rule, safety limits, `Config.layout.maxTotal`.
- Phone appearance stays UNVERIFIED until someone looks on a device.

**Rule:** None

## Alternatives considered
- Narrow the camera field of view to enlarge the street on screen: rejected, 24 tests fail (above).
- Cap how far the camera zooms out as the parade grows (`Config.cameraPullback.max` 1.4): not ruled out, since it is the biggest reason the street looks narrow late in a run, but it trades against keeping a large parade visible (#114). Needs its own decision.
- A half-width near 31 to 43 to reach 40%: would make a street 62 to 86 studs wide, a redesign of lane spacing and scatter rather than the slight widening the owner asked for in #54.
- Edit `halfWidth` in each layout by hand: rejected, that is the pre-#220 state where lanes, drawing and spawns could disagree.

## Consequences
- Easier: the next width change is one edit with the validator as the guard.
- Harder: this one is a balance change; lane width, spawn spacing and scatter shift, and the existing ladder numbers go stale (#148).
- Separate defect: `CameraRig.visibleHalfWidth` uses the along-the-street gap instead of the view-axis depth and understates the visible width by about half; it is used by `tests/issue54_street_width.test.luau` and `tests/screenlayout.test.luau`. Its effect on those tests is UNVERIFIED. Tracked in issue #229.
- Revisit when the owner states a screen-share target as a number, or after a device check.
