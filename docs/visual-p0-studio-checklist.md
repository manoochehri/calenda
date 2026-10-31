# P0 visual fixes: source evidence and Studio checklist

Status: source-checked; in-engine appearance **UNVERIFIED**.

This record covers the owner's 2026-10-30 phone screenshot and review round 2 for PR
#223. It does not claim that Roblox Studio has been run.

## Review-round evidence

### Round 1 — reviewer and security, head `abc6c3b`

- Reviewer verdict: **merge after fixes**. Must-fixes were missing review-round evidence, a concrete
  #171 A/B diagnosis, a complete #222 rectangle inventory, and exact manual checks.
- Security verdict: **fail** only for pre-existing repository governance: `main` is not
  protected and `.github/CODEOWNERS` is absent. That finding is tracked separately in
  issue #224 and is not part of PR #223.
- PR checks at this head were green: `ci/test` and `ci/secret-scan`.

### Round 2 — this update

This document and the PR description now carry the requested evidence. The implementation
scope remains limited to client presentation and source-level regression checks; no server,
encounter, targeting, cadence, gate-count, budget, workflow, or permission changes are
included.

## #171 source diagnosis and A/B test

The current source rules out several causes without claiming to reproduce Roblox rendering:

- `WorldBuilder.client.luau` sets `CastShadow = false` on the flat StartingPlaza, Street,
  sidewalk, Plaza, and centre-line parts. This addresses the confirmed shadow-map failure
  fixed by the earlier #171 work.
- `Backdrop`/`OaxacaStreet` set lighting at startup; there is no per-frame road-material or
  Lighting write in the gameplay update path.
- `GateView` uses the smoothed `ServerClock` timeline, so the old 10 Hz state extrapolation
  kink is not the active gate animation path.
- `ClusterView` previously created a `CalendaThreat` ScreenGui that tinted both screen edges
  red from the nearest approaching wave. PR #223 removes that full-screen tint. The horde
  itself still uses a steady, in-world threat colour; it does not oscillate.

Remaining Studio-only diagnosis, one variable at a time:

1. Run from an empty no-Baseplate place on the same phone-sized landscape aspect and route.
2. Baseline: record whether the road or whole view flashes, and whether the red effect is
   on the screen edge, on a horde, on a gate, or on the ground.
3. Set `Config.debug.noShadows = true`, restart, and repeat the same route. A change only
   here implicates shadow rendering; no change rules it down.
4. Restore shadows, set `Config.debug.freezeCamera = true`, restart, and repeat. A change
   only here implicates camera-follow motion; no change rules that out.
5. Restore the camera, set `Config.debug.rawExtrapolation = true`, restart, and repeat.
   A change only here implicates the legacy unsmoothed timeline; this is diagnostic only.
6. If it still flashes, disable the `OaxacaStreet` model in Workspace for one comparison.
   If the symptom changes, the facade/SurfaceGui path is implicated; otherwise it is not.

Record the observed toggle and exact route position in the issue before changing source
again. Without that Studio observation, the rendering result remains **UNVERIFIED**.

## #222 rectangle inventory

The screenshot annotations are mapped to source-owned presentation objects as follows.
Where the screenshot alone cannot distinguish an object, the classification is explicitly
marked **UNVERIFIED** rather than treated as proof.

| Screenshot appearance | Source owner | Classification | PR #223 action |
| --- | --- | --- | --- |
| Dark floating rectangles with small white count/reward text near incoming groups | `ClusterView.buildGroup`: `BillboardGui` with `back`/`fill` meter frames | Stray-looking backing; the tag itself is intentional gameplay feedback | `back.BackgroundTransparency = 1`; labels and fill remain |
| Orange/red individual figures in the incoming lane | `MobView`: pooled body, head, and arms | Intentional crowd members; not stray geometry | Body is now an upright cylinder; pool/cap unchanged |
| Tall blue/gold portal bars and their horizontal crossing strip | `GateView.buildPortal` | Intentional gates; gate count is not changed by this PR | None |
| Small blue/cyan blocks around the lead and lower parade | `CrowdView` follower pieces / lead ring and `SectionsView` representatives | Intentional parade representation | None |
| White lane bars/arrows on the road | `LaneView` lane markings | Intentional navigation/readability geometry | None |
| Large gray/colored area outside the street | `Backdrop` earth/scenery or a Studio template Baseplate | Source backdrop is intentional; a template Baseplate is stray. Exact in-engine source is **UNVERIFIED** | Existing startup cleanup removes direct stray Baseplate; checklist requires empty place |
| Any remaining black rectangle after the tag backing is transparent | No source-level identity can be proven from the supplied screenshot alone | **UNVERIFIED** pending the Workspace instance name in Studio | Do not guess; capture the instance path and add it to #222 |

The source inventory is complete for the named client builders and intentionally separates
objects that look rectangular from geometry that is actually unexplained. `make test`
includes `tests/issue222_visual_cleanup.test.luau` to keep the removed overlay, transparent
tag backing, and rounded horde body from regressing.

## Exact presentation checks

Run these after the source checks, using the same empty place and phone-sized landscape
window. They are manual and currently **UNVERIFIED**.

- **Threat overlay:** start a run, wait for an incoming wave, and confirm no red tint covers
  either screen edge or the whole viewport. Confirm the horde remains visible and steady.
- **Road stability:** traverse the opening plaza, first gate, mid-street, and final plaza;
  repeat after replay. Confirm the road, curbs, lane marks, and ground do not shimmer or
  flash as the camera follows the lead.
- **Rectangle audit:** pause at the screenshot-like dense scene. In Explorer, inspect every
  visible rectangle and record its full instance path. Confirm no unexplained black backing
  remains; confirm intentional gate banners, lane marks, projectiles, and crowd members
  remain readable.
- **Crowd silhouette:** observe an incoming horde at its first appearance, mid-route, and
  near contact. Confirm bodies read as rounded upright figures rather than flat blocks, and
  that individual head/body separation remains visible at phone size.
- **Reset/replay:** replay from the results screen and repeat the four checks above. Confirm
  no removed overlay, opaque tag backing, or stale pooled geometry returns.

No Studio/device run was available during this review round, so all bullets above remain
**UNVERIFIED**.

🛠️ Posted by senior-eng via Codex
