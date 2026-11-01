# Architect report: the shortest path to a fun, readable phone game

**Status:** current
**Date:** 2026-10-31 · **Role:** architect (advisory, no code edited) · **Base:** origin/main `3a4a59c`
**Parent:** #150 (also read: #230, milestone 7, #239 #240 #241 #242 #244 #147 #171 #192 #206 #222 #238)

Evidence grade: everything below is read from source or from issue text. **Nothing was run in Studio and
no phone was measured**, so every statement about how the game looks, sounds or performs is UNVERIFIED.
"Likely cause" means source-supported hypothesis, not a finding.

## 0. Diagnosis in one paragraph

The game is not missing features; it is **too many things drawn and moving, with no way to tell which ones
matter**. Over three weeks the team added effects one bug at a time (trails, halos, neon rings, translucent
strips, dust emitters, hit flash and shake, breathing, bounce, beat-dancing, confetti, chevrons, floaters)
and then added *switches* to find which one hurts (#171, #235, #248) instead of *deciding what the screen
is for*. Meanwhile the thing that makes Mob Control fun, a steady rhythm of small decisions with a clear
payoff each time, has one horde lane (`DebugLayout.luau`, hordes all `"right"`), four gates and three
obstacles in 90 s, and no audio. Fix order: (1) subtract until the screen reads, (2) put a cheap
measurement and a write-spy around the render path so regressions stop recurring, (3) thicken the loop
with the two lane-choice features already specified, (4) only then add roster, bosses and sound polish.

## 1. The 7 highest-leverage structural changes, in order

### R1. A "calm screen" render preset: decide the allow-list, delete the rest (readability, performance)

What: define the **only** things allowed on a phone screen during a run: road + lane marks, gate boards,
horde figures, parade figures, the lead avatar, shots, one counter HUD. Everything else is off by
default and only returns when it passes the test in R6. Concretely, remove or default-off:

- `LeadRing`: a **neon, 20% transparent cyan cylinder** 10 studs wide under the lead
  (`src/client/CrowdView.luau:36` colour (80,235,255); `:197-205` builder, `Material.Neon`, `Transparency 0.2`).
  This is the best source-level suspect for **#242 (blue disc) and #244 (translucent cyan wedge on the
  start screen)**: same colour, translucent, lead-centred, and the title camera is framed on the lead
  (title branch of the render step, `Main.client.luau:361` onward). A flat translucent disc seen at a shallow title angle reads as a wedge.
  UNVERIFIED until looked at in Studio; the cheap proof is one-flip `noLeadRing` (see R6). The avatar
  already needs no ring to be findable if it is the only person with a distinct colour.
- Translucent world strips: `GateView` crossing strip (`GateView.luau:167-175`, 0.25) and its per-frame
  re-write (`:364`).
- Shot Trail + three extra Neon parts + halo per projectile (`ClusterView.luau:251-297`, Trail at `:267`).
  One part per shot is enough to read as a note/heart/gift if the silhouette is right (#151).
- Full-screen white-then-red hit flash and camera shake (`HitFeedback`, `Hud.luau` hit overlay, `Main.client.luau`
  `hitFx`). Keep a 0.1 s tint on the *parade members that were lost*; drop the screen flash.
- Dust `ParticleEmitter`s on mobs and warning chevrons (`MobView.luau:126`, `ClusterView.luau:165-180`).
- Dark lane-label plates (#250, already in flight) and floaters that overlap gate numbers (#206 item 2).

Why it moves the owner's complaints: clutter, flashing, "unexplained objects", and the Part/emitter count
that drives frame rate all fall together. Rule for the allow-list: if a viewer on a phone with sound off
cannot say what an object is for in one second, it does not ship.

Owner: **new issue "Calm screen v0: essentials-only render preset"** as the single child of #206, absorbing
#242, #244, #222, #250 and the remainder of #171. Accepts when the R6 inventory test passes with the
preset budgets and the owner confirms the screenshot.

### R2. Put an in-engine measurement on screen before any more performance PRs (performance)

Four performance PRs (#182 bench, #196 text writes, #247 re-parenting, #249 BulkMoveTo) have shipped
without one device number, and the headless bench explicitly "does not model engine cost"
(`tools/bench/frame_cost.luau:5`). The known counts at the touch default (`medium`,
`QualityConfig.luau` levels): up to 16 mobs, **200 horde figures x 3 Parts = 600 Parts moved every frame**
(`MobView.luau:415`, `BulkMoveTo`), plus 24 parade followers x 5 pieces (`CrowdView.luau` Avatar pieces),
plus up to ~27 shots each with Trail + 4 Neon parts, plus 5 + 6 emitters.

Build: a `Config.debug.perfOverlay` text line (one TextLabel, updated at 2 Hz, not per frame) showing
`workspace` descendant Part count, live ParticleEmitters/Trails, and dt p50/p95 over the last 5 s.
The owner reads three numbers off a phone screenshot; that closes the loop that #147 and #27 keep
reopening. Then decide LOD by number, not guess: the preserved constraint is dense people-like crowds,
so reduce **cost per figure**, not figure count: far figures as 1 Part (body capsule with head colour),
near figures 3 Parts (extend the existing `MobLod`, `SpectatorScatter.legibleScale`). Sprites stay an
option only if the overlay says Parts are the bottleneck.

Owner: #147 (retitle to "Measure on device; then LOD") + #65 for the representation decision.
New issue only for the overlay. #249 and #247 should merge first (they are small and already reviewed).

### R3. One motion grammar for the horde (readability; fixes #240)

A horde figure should have exactly four visible states, each distinguishable muted at phone size:
**approach** (steady march, one speed, no idle breathing), **hit** (0.1 s white flash on that figure
plus 1 stud knock-back), **convert** (figure takes the parade colour and runs into the parade; counter
ticks +1), **join** (single small pop on the parade member). Today there are many more: breathing,
join bounce with landing squash, cheer on gain, flinch on loss (`CrowdFeel`/`CrowdFeelConfig.luau`, #188),
beat-synced dancing (#75), stride dust, upright-cylinder bodies (#223). Each is plausible alone; together
they are "confusing horde animation".

Method: keep #248's switches, but instead of the owner flipping six values, ship the **minimal grammar
as the default** and re-enable a family only with a stated purpose. Everything keyed off the one crowd
total stays exact; this is presentation only.

Owner: #240 (rescoped: "ship the four-state grammar"), with **#178 merged into it** (see section 2).

### R4. Thicken the loop: a decision every ~5 s, using specs that already exist (fun)

The current 90 s run is: 34 single-lane horde waves from the right (`DebugLayout.luau` loop; all
`"right"`), 4 gates (15, 20, 50, 80 s) and 3 centre-lane obstacles (40, 64, 88 s). Steering therefore
matters about 7 times in 90 s and the horde never makes you choose. Build, in this order, what #150
already specifies:

1. **#156 lane encounters**: optional +1 pickup lane and consistent targeting, so every ~6 s the
   player chooses between "the horde lane" (shoot, convert, risk contact) and "the pickup lane" (+1
   now, no shooting). That is the Mob Control tension.
2. **#157 one shoot-to-unlock target and one stronger musical attack**: the "I earned something" beat.
3. Then #162/#158 bosses (the stop-and-fight climax), only after the screen is calm.

Gate data note: the gate rows from #238 are real choices in the validator's sense, but gate 1 (+20 vs x4,
crossover 7, reached crowds 5, 9, 10 per `DebugLayout.luau` comment) is won by x4 for two of three
reached crowds, and gates 1 and 2 are only 5 s apart (15 s and 20 s). A choice that is right 2 times in 3
teaches "always take the multiplier". Move gate 1 to about 12 s and gate 2 to about 30 s and move the
crossover of each near the **median** reached crowd, not the edge. Data-only change in `DebugLayout.luau`
(and `Layouts.luau`); the validator already proves the totals stay under `Config.layout.maxTotal`.

Owner: #156 and #157 (both existing, P0); gate retime as a note on #238 or a small new issue.

### R5. Defer the roster (#230-#233) and bosses out of the critical path (focus)

Two competing power-up systems (#157's "one stronger attack" and #232's trumpet/China attacks) plus
typed-membership accounting inside `crowdTotal` (#231) is the largest change on the board and does not
address a single owner complaint. Keep #231 (contract/cultural brief) as docs-only work, move #232/#233
to the next milestone, keep #158/#162 after R1-R4. This also removes the ledger/replication risk from
the period when the render path is being simplified.

### R6. Two guardrails that stop the #171/#241 pattern (see section 3)

(a) A **scene inventory + write-spy test** over the real client views using the existing Roblox stub
approach; (b) a **single debug-switch registry** so a new switch is one table row, not 5 edits.

### R7. Sound last, but unblock the decision now (feel)

`Config.sfx` has 13 empty slots (`Config.luau:554`); `SfxPlayer`/`SfxMap` are wired and tested, so
nothing in code blocks #239. The blocker is a human decision: **which 5 rights-cleared sounds**
(`shotLaunch`, `shotImpact`, `followerHit`, `gatePop`, `convert`). The charter requires the game to be
understandable muted, so this is not the bottleneck for readability, but it is the cheapest single
feel upgrade once ids exist. Do not guess ids. Ask the owner once, in #239, to pick five from the
Creator Store free-audio list (no spend); merge #172 (music) into the same ask because it has the same
sourcing problem. Per-shot sounds at 3 to 20 shots/s must stay under `SfxMap` cooldowns; make `shotLaunch`
play on every Nth shot above tier 2.

## 2. Open issues: redundant, conflicting, merge or close

| Issue | Recommendation |
|---|---|
| #244 cyan wedge | Merge into #242 (PM already notes same object). One PR, one proof (R1 `noLeadRing`). |
| #242, #222, #250, #206 | One owner (R1 calm screen). #206 stays as the umbrella and closes when the owner confirms the screenshot. |
| #171 road flashing | Stop adding A/B switches. Its candidates (shadows #185, trails, strips, dust, hit flash) are all covered by R1. Close when R1 is confirmed. #245 (draft revert of #235) should be closed, not merged: it found no defect, and the revert would lose the switches R6 will consolidate. |
| #241 broken after #235 | Root-cause is unproven (the PR #245 says "no defect found"). Fold into R6: the inventory test is the fail-first evidence this issue lacks. Keep open until the owner re-tests. |
| #178 juice | Merge into #240. It is the opposite of what the owner needs now (more feel layers). |
| #114 and #54 | Both are "camera, width, coverage" and #54 is `needs-decision` with ADR 0012 (widen street, proposed) pending. Merge #114 into #54; the owner decision unblocks both. |
| #192 hordes disappear | Code and tests landed (#198). Move to owner validation or close with the existing verification; it is clutter in the P0 queue. |
| #218 start screen | Items 1-4 are met in code; remaining is device confirmation. Move to owner validation, not P0. |
| #184 pace, #201 SPAN | Config-only owner tunes. Defer; do not let them block. |
| #189 witness policy family | Real guard but P1/P2; defer until R4 changes layouts. |
| #120 spec | Amendments 9 and 12 are already referenced everywhere; verify and close if the exit criteria are met. |
| #231-#233 roster | Move to a later milestone (R5). Conflicts with #157 as a second power-up path. |
| #147, #65 | Keep, rescoped by R2: measure first, then LOD. Do not close on CI. |
| #172 and #239 | One owner ask (R7). |

## 3. Architecture risks that keep producing regressions

1. **Visuals are untestable headlessly, so tests grep source.** `tests/*.luau` contains 24 `fs.readFile` call sites and 14 `has(path, needle)`-style
   source-text assertions (for example `tests/issue171_debug_switches.test.luau`; counted by grep, not audited one by one). A passing test means "the text exists",
   not "the behaviour is right". #235 was reviewed on exactly that evidence (1017 passing) and the owner
   then said the game was broken (#241).
2. **Per-frame property writes with no accounting.** `GateView.luau:321-366` writes Transparency, Size,
   Color and TextTransparency on every portal in a Heartbeat, building a string key each frame
   (`:357`) to dedupe; `CrowdView` writes `CFrame`/`Size` per piece; #147 and #236 were exactly this class
   (TextLabel writes, re-parenting every frame). Each was found and fixed by hand, one at a time.
3. **Two frame loops for one view.** Main drives a render-step (`Main.client.luau:361`), GateView adds
   its own `Heartbeat` (`:321`), so gate visuals update at a different point than the camera and the lead.
   This is a candidate for visible desync "flashiness". UNVERIFIED.
4. **Switches are scattered.** `Config.debug` (`Config.luau:569`) plus `DebugSwitches.luau` plus validation in
   `Config.validate` plus the call site plus a test: five edits per switch, and #235 touched 7 files
   including the render path just to add them. The diagnostic code became the risk.
5. **No budget on materials, transparency, emitters or part count**, only on figures
   (`QualityConfig`). The things most associated with flicker (Neon, translucency, Trails) are unbudgeted.
6. **Open PRs touch the same files.** #247/#248/#249 touch `ClusterView`/`MobView`/`CrowdView`; #250 touches
   the lane labels. Land order matters (section 5).

### Cheapest guardrails

- **Scene inventory test (R6a).** Extend the Roblox stub in `tools/bench/frame_cost.luau` into
  `tests/helpers/SceneStub.luau`, a Lune stub whose `Instance` records every property write and parent change.
  Build the real views against it, run N frames at a fixed state, and assert: Part count <= budget, count of
  Neon, `Transparency` in (0,1), Trail, ParticleEmitter and SurfaceGui <= preset budgets, **zero**
  `Parent` writes and **zero no-change property writes after frame 1**, and writes/frame <= a number.
  One test would have caught #236, #147's text writes, and likely #241 (an erroring require shows as a
  failed build in the stub). Runs in `make test`; no engine needed. It still cannot see rendering, so
  Studio stays UNVERIFIED, but it removes the class "something silently changed".
- **Switch registry (R6b).** A single `DebugSwitches.REGISTRY = { name = { default, describe } }`. `Config.debug`
  validation, the call-site helper and the test iterate it, so a switch is one row. Add `noLeadRing`,
  `calmScreen` (all R1 removals together) and `perfOverlay` as the first rows. Registry first, then
  every other lane adds a row without touching `Config.validate`.
- **Preset budgets in config.** Extend `QualityConfig.levels` with `maxNeon`, `maxTranslucent`, `maxTrails`,
  `maxEmitters` so the inventory test has numbers to hold.
- **On-screen scene dump.** `Config.debug.dumpScene` prints the named inventory of everything visible
  once (class, name, material, transparency). This turns "unexplained blue disc" into a name in one run
  and is what #222/#242/#244 each asked for separately.
- **Every visual issue carries a one-line owner check** ("flip X, look at Y"), per `.trazo/rules.md`
  "Ask before guessing", and stays UNVERIFIED until done.

## 4. The first 60 seconds of mob control: design spec

Principles: one new idea per ~10 s; every event has **one shape, one motion, one sound slot**; nothing
flashes more than 3 times per second and no full-screen effect more than once per 10 s; the count in
the HUD is the score; all numbers are `[proposal]` and live in config. Server arithmetic, `crowdTotal`,
the 10% loss share (ADR 0007), caps (6 representatives, 24 loose) and the layout `maxTotal` are unchanged.
Start state is the existing solo opening (ADR 0012-solo): the avatar is the only person.

| Time | What the player sees and does | What it teaches |
|---|---|---|
| 0-3 s | Camera settles behind the lone avatar. Road, two lane marks, counter "1". No ring, no disc. The march is steady; auto-fire sends one note at a time (tier 0: 3 shots/s, 1 in flight). | "I move left/right, I shoot automatically." |
| 3-8 s | First small horde (3 to 4 people) walks in from far ahead in the right lane, visible for >= 3 s before contact, with a faint arrow-free approach (no chevrons). The player steers into line; notes hit; each hit flashes the figure white 0.1 s. | "Shooting a horde is the point." |
| 8-12 s | Each converted figure takes the parade colour and **runs into the parade** (one at a time, readable), counter ticks +1 each; the counter number pops once per tick, not once per frame. Parade is 4 to 8 people. | "Shooting makes the parade bigger." |
| 12-16 s | Gate 1 (move to ~12 s): two boards, left and right, each showing the **operation and the result for my current count**, for example "+20 -> 28" and "x4 -> 32". Boards are opaque, ring-free, number never overlapped by floaters. Player steers through one; it bursts and the number flies to the counter. | "Gates are a choice, the board tells me the outcome." |
| 16-25 s | Hordes grow to 6 to 10, still one horde lane, plus the **first +1 pickup lane** (#156) on the other side. The player now picks a lane every ~6 s: shoot the horde or grab the safe +1. Fire tier steps up at 25 recruits (4 shots/s, 2 in flight): a small visible change in the note stream. | "Lane choice = risk vs safe." |
| 25-32 s | First horde that reaches the parade unconverted: the **lost members** (10% share) tint red and drop out for 0.3 s, counter ticks down once, one soft thud (slot `followerHit`). No screen flash. | "Contact costs people; avoid or kill." |
| 32-40 s | Gate 2 (~30 s) with a crossover near the median crowd so the better board depends on whether I recruited well. Crowd now dense: fire tier 50 (5 shots/s, 3 in flight). | "More recruits = more fire = more recruits." |
| 40-48 s | Center-lane streetwork obstacle (existing, 40 s). Both side lanes passable, 2+ s visible warning (the cone/-10 sign, no chevron emitters). Dodging costs nothing; contact is -10. | "Dodge by steering." |
| 48-56 s | First **shoot-to-unlock target** (#157) appears in a lane: a visible bar that fills with hits. Filling it grants the one stronger musical attack for ~8 s (a distinct shot silhouette). | "Short-term power is earned by aiming." |
| 56-60 s | Gate 3 approach (50 s row moved to ~56 s or 60 s as the validator allows). The player has now met: shoot, recruit, choose a gate, choose a lane, take a loss, dodge, unlock. | The full loop, once. |

Acceptance for engineers (testable headlessly where possible):
- Between 0 and 60 s there is at least one player choice every 8 s (gate row, pickup-vs-horde lane, obstacle side, unlock target), asserted by a layout test over `DebugLayout`.
- No object exists in the scene that is not in the allow-list (R6a).
- Every event in the table has exactly one visual signature and one sfx slot name in a table
  (`EventGrammar.luau`, pure), so audio can be filled in later by id only.
- All timings above come from layout data and `Config`, none are hard-coded.

## 5. What can run in parallel (separate engineers, minimal conflicts)

Land first (small, already reviewed): #247, #249, #250, #248, in that order, because they edit the same
render files. Then:

| Lane | Work | Files it owns | Depends on |
|---|---|---|---|
| A. Harness | R6a scene stub + inventory test; R6b switch registry (**registry lands first, ~1 day, before B-D add rows**) | `tests/helpers/*`, `tools/bench/*`, `shared/DebugSwitches.luau`, `Config.luau` debug block only | none |
| B. Calm screen | R1 removals + dump scene | `CrowdView`, `GateView`, `Hud`, `WorldBuilder`, `HitFeedback` | A (registry) |
| C. Shots | #151 silhouettes, one-part shots, trail off in preset | `ClusterView` shot section, `ShotLook`, `ProjectileVisual` | A; coordinate with B on `ClusterView` (different regions) |
| D. Horde motion | R3 grammar | `MobView`, `CrowdFeel*`, `SpectatorMotion`, `FollowerLook` | A |
| E. Layout/loop | #156 pickup lane, gate retime, #157 | `Layouts`, `DebugLayout`, `Level`, `LayoutValidator`, `Targeting`, server `RunDriver` | none until it changes `maxTotal` (it must not) |
| F. Measurement | R2 perf overlay + LOD decision after the owner reads the numbers | new `PerfOverlay.luau`, `MobLod`, `QualityConfig` | A (registry row), B (so it measures the calm screen) |
| G. Audio ask | Owner picks 5 ids; one tiny PR wires them | `Config.sfx`, `docs/audio-setup.md` | owner |

Conflict hot spots: `ClusterView.luau` (B, C, F) and `Config.luau` (every lane). Mitigation: one lane
per file region; the registry row addition is the only edit others make in `Config.luau`, in the
`debug` table. No stacked PRs: B, C, D, E start from `main` after A merges. Safety limits
(`Config.layout.maxTotal`, caps) are not touched by any lane. There is no `.github/CODEOWNERS` file in this
checkout; the "limits are human-only" rule is enforced by convention and review here, so lane E must
call out any layout/`maxTotal` diff in its PR.

## 6. Owner questions (only these need the owner)

1. **Sounds.** Decision: which five free sounds to use. Option A: owner picks five from the Creator Store free-audio list and posts the ids in #239 (Recommended: the code is already wired, ids are the only gap). Option B: ship silent until after the playtest (con: owner already reports the game "has no sound").
2. **What to keep on screen.** Decision: accept the allow-list in R1 and delete the rest. Option A: yes, strip first, add back by name (Recommended: it answers clutter, flashing, frame rate and the blue disc together). Option B: keep effects and only add switches (con: this is what produced #241).
3. **Defer the Oaxaca roster and bosses to the next milestone.** Option A: yes (Recommended: the loop is thin before it is wide). Option B: keep in milestone 7 (con: two power-up systems and ledger changes in the same weeks as the render cleanup).

🏛️ Posted by architect via Claude Code
