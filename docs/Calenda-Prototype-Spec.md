# Calenda — Prototype Specification

Version 1.0 · October 23, 2026 · Platform: Roblox · Primary language: Spanish

## 1. Pitch and prototype goal

Lead a tiny marching party down an Oaxaca-inspired street. Throw musical notes and gifts to invite spectators, pass through math gates to multiply your followers, and assemble the growing crowd into dancing giant puppets, spinning globos, and decorated dance sections. Finish by filling a plaza with a spectacular celebration.

**Core loop:** recruit → choose a gate → grow → assemble a parade section → recruit faster → celebrate → replay.

The prototype must answer: Is recruiting satisfying? Is the math understandable? Does the first giant puppet make players want to grow the parade again? Commercial success is unproven; this build tests the game’s appeal.

## 2. Scope

Build one approximately 90-second playable street plus an 8–10-second plaza finale. Use an individual run with NPC spectators; multiplayer interaction is deferred. Support touch and keyboard. Include three simple section visuals, one layered music track, positive math gates, streetwork obstacles and level hazards (issue #96), results, and immediate replay.

Build in stages: first get the entire loop working with one puppet; then add the globo and dancer sections. These are stages of the same prototype, not separate games.

Deferred: shops, paid multipliers, pets, trading, clothing creation, custom music uploads, daily rewards, elaborate progression, boss fights, and global leaderboards.

## 3. Controls and camera

- Automatic forward movement; drag horizontally to steer on touch, A/D or arrow keys on keyboard. No jumping or rhythm precision required.
- Elevated camera behind the parade, showing upcoming gates and both sidewalks. Gates must remain readable behind tall props.
- Music notes fire automatically. Steering toward a sidewalk engages that side’s spectators only; center position engages none (Amendment 5). Shots keep firing as visual misses when nothing is engaged.
- Keep the lead musician visible as the steering anchor. Sections follow in compact rows; decorative size does not enlarge the gameplay collision area.
- Gameplay remains understandable muted through icons, meters, counters, and animations.

## 4. Recruiting spectators

Spectator clusters (see Amendment 1 at the end of this document: they arrive in waves toward the parade) are on either side of the street, displaying an excitement meter and a recruit reward. Start with two cluster types: 3 note hits awards +5 followers; 8 hits awards +15. All values are initial tuning defaults.

Notes visibly arc from the lead/band to the target. A completed meter triggers cheering, a few spectators running into the parade, and a floating +N. Credit each cluster once when its meter fills; animation arrival must not credit it again. Unfinished clusters leave range without a penalty.

The permanent lead musician is separate from the follower total and remains even at zero followers. Starter firing rate: 3 note hits per second. As sections accumulate, use `min(12, 3 + sectionCount)` hits per second. This controlled increase gives growth a gameplay benefit without making thousands of followers produce thousands of projectiles.

Gift tosses share this excitement system. Once a dancer section is present, every fourth shot is a visibly different snack/gift toss worth the same one hit. It replaces a note; it is not an extra reward or damage system. Spectators catch gifts and celebrate. Use placeholder wrapped treats initially; settle specific foods with local reference review.

## 5. Crowd math: one authoritative total

Maintain an integer `crowdTotal`, starting at 10. Sections are a compact representation of followers, not a currency purchase or a separate population.

```text
sectionSize = 50
sectionCount = floor(crowdTotal / sectionSize)
looseFollowers = crowdTotal mod sectionSize
```

| Situation | Crowd total | Representation |
| --- | ---: | --- |
| Start | 10 | 10 loose followers |
| First assembly | 50 | 1 section |
| Continued growth | 120 | 2 sections + 20 loose followers |
| Pass ×2 at 120 | 240 | 4 sections + 40 loose followers |
| Hit a −10 obstacle at 105 | 95 | 1 section + 45 loose followers |

**Every math gate affects the entire total**, including people represented by sections. Assembly never consumes followers, weakens a gate, grants extra score, or independently multiplies recruitment credit.

Losses also affect the whole total. If a threshold is crossed downward, the newest section disperses back into dancers with a brief animation. This supersedes the earlier idea that completed sections are immune to losses; a single consistent total is easier to understand. No death or destruction animation.

## 6. Math gates and choices

Offer two gates side by side, using +N and ×N only in this prototype. Show the operation and its resulting total, for example `+20 → 30` versus `×2 → 20` when the current total is 10. Identify gates with symbols and text, not color alone.

Trigger exactly one gate per pair when the lead crosses its forward plane. Evaluate the lead’s horizontal position; crossing the center selects the closest gate, with a fixed left-side tie break. Followers and puppets never trigger gates separately. Resolve the operation using the authoritative total at crossing time.

Create meaningful route tradeoffs: the gate with the larger immediate result may lead away from a valuable spectator cluster or toward an obstacle. Initially teach simple arithmetic with safe gates; introduce route tradeoffs later. Provide enough distance to read and steer.

No hidden population cap that makes an advertised ×2 false. Bound the authored level’s possible growth and aggregate visuals when totals become large.

## 7. Signature transformation and section types

At 50 followers, the crowd swirls inward, confetti briefly covers the center, and a giant puppet rises with a small dancing entourage. The music adds a layer. The counter stays visible. Target duration: about 0.8 seconds while forward play continues; never cover the next decision.

Sections appear in a deterministic repeating sequence: puppet → globo → dancers. When one gate crosses multiple thresholds, use one combined celebration and a '+N sections' indicator, not repeated camera interruptions.

| Type | Visual direction | Prototype action |
| --- | --- | --- |
| Monos de calenda | Tall humanlike puppets, bobbing heads, swinging loose arms, swaying clothes; visible small entourage | Clap and sway to the music; milestone confetti |
| Globos / marmotas | Large decorated spheres on visible poles, rotating and tilting with carriers | Emit decorative musical rings on the beat |
| Dancers and baskets | Swirling skirts, flower baskets, coordinated steps | Toss occasional gifts in place of note shots |

All types contribute equally to the firing-rate formula. Different combat classes and special abilities are deferred. Rings, claps, and confetti do not secretly recruit spectators.

## 8. Keeping large parades readable

Render at most six section representatives and 24 loose-follower avatars. When there are more logical sections, distribute them across representatives of the correct type and show a small ×N badge for each represented stack. Display the actual loose-follower count even when only 24 are drawn. Entourages are decorative and never add followers.

Example: 2,000 followers means 40 logical sections, not 40 fully simulated giant puppets. Six visual representatives summarize them. The main crowd counter remains exact, and the firing-rate formula uses logical sections.

Use a modest camera pullback and denser formation as the party grows. Give the music and decorations additional intensity without endlessly enlarging models. Do not merge the entire parade into an animal in this prototype; puppets, globos, and dancers are the core identity. The supplied colorful animal sculpture is a possible later collectible or plaza prop.

The parade's size is the life bar (Amendment 4): the exact crowd counter is the only life display, so the representation rules above never hide a loss. There is no separate HP bar.

## 9. Level, obstacles, and ending

| Run time | Intended experience |
| --- | --- |
| 0–10 seconds | Start already moving; 'Arrastra para moverte'; recruit the first cluster |
| 10–25 seconds | Two easy gate choices; aim to introduce the first puppet by 25 seconds |
| 25–65 seconds | More recruitment, globo/dancer assembly, and alternating sidewalk choices |
| 65–90 seconds | Largest growth opportunity, a final route decision, plaza approach |
| Finale | Party spreads into the plaza; music peaks; gifts, confetti, score, replay |

Use closed streetwork lanes marked with cones and a −10 sign. One collision removes 10 followers, clamped at zero; then that obstacle cannot hit again. Use the lead’s fixed hitbox. Avoid visual injury: some followers peel off to cheer from the sidewalk. Zero followers ends the run as defeated (Amendment 4), so the obstacle cannot empty the parade silently.

Issue #96 adds level hazards, drawn from the run seed on the server and listed per level in its hazard set (`Level.Layout.hazardSet`). The first Oaxacan level uses two kinds, at occasional times between 20 and 80 seconds, never before the run starts:
- **Tomato throws** from the buildings. A warning shows 2.5 seconds before the impact. Only a landed gift shot inside that warning window blocks the tomato; note shots do not. An unblocked tomato in the lead’s lane removes a share of the parade, once (Amendment 4: `Config.hazards.tomatoSharePercent`, 10% of the total, minimum 1).
- **Tlayuda cart** across the street, leaving one clear gap 4.5 studs wide, with a warning 2 seconds ahead. Steering into the gap clears it. A collision costs the existing −10 obstacle loss, once.

Later levels select their own hazard kinds in configuration; no level name is checked in code.

HUD copy (issue #112, owner-reviewed for a child audience): the section meter caption reads "Faltan N para un grupo" (N followers still needed for the next section). On results, show the final score once and hide gameplay-only follower counts; a new record gets only the brief "¡Récord!" cue. Music stays on with no in-game control (ADR 0008). Keep the start hint "Arrastra para moverte" and defeat line unchanged.

Reaching the plaza always completes the run. Score equals the final crowd total, with no extra conversion bonus. On the results screen, show the short "¡Listo!" headline and final score once; do not repeat it as a follower count, points label, or numeric best. Show only the short "¡Récord!" cue when the run sets a new best. Keep the "¡Otra calenda!" replay button. A lightweight three-tier celebration can use provisional thresholds of 50, 150, and 300 followers; tune these after observing normal runs.

Replay resets all run state. Start with one fixed layout for debugging; after it works, provide three authored gate/cluster arrangements under recorded seeds. Each must be completable without spending or purchases.

## 10. Art, music, and reference direction

Use the user’s supplied photographs as the visual brief: flower baskets and colorful skirts in `image.png`; decorated animal silhouette and painted patterns in `image(1).png`; pole-carried globos in the 8.48.02 PM screenshot; distinct floral outfits in 8.48.18 PM; loose-limbed giant human puppets in 8.48.44 PM. These are visual references, not permission to reproduce specific artwork, branding, faces, or recordings. The team should receive the reference images alongside this document.

Art priorities: big readable silhouettes, warm street colors, bright flower accents, visible carriers, and joyful imperfect puppet motion. Leave the road and gate text visually clear. Treat different outfits and dances as distinct referenced traditions, not interchangeable generic Oaxaca costumes; confirm specific community attribution before labeling content.

For the prototype, use one free-to-use Roblox Creator Store full-mix loop: “Mexican Nostalgia” by APMOfficial (asset ID 1838904620). This is a provisional music bed, not a claim that the track represents a specific Oaxacan calenda tradition; its fit is UNVERIFIED until heard in Studio. The prototype uses one music source rather than synchronized section stems. Keep playback optional and the game playable muted. This temporary choice is recorded in ADR 0005; revisit adaptive stems after owner validation. Gifts and musical projectiles should look friendly and celebratory.

## 11. Implementation boundaries

Keep tunable values in configuration: section size, spectator approach speed (`spectators.approachSpeed`), side tolerance (`spectators.centerTolerance`), firing range (`firing.range`), parade HP (`hp.max`) and per-cluster-type `attackDamage`, starting total, cluster hits/rewards, gate operations, losses, speed, firing-rate curve, visual budgets, and finale thresholds.

Separate run state and crowd arithmetic from presentation. The server owns totals, gate/cluster consumption, losses, parade HP, attacks, defeat, completion, and score; clients animate the results. Validate steering and crossing events; clients cannot submit arbitrary gains. Use pooled visual actors/projectiles, limited collision checks, and compact formations rather than full independent pathfinding for every represented follower.

Use the team’s existing GitHub and agent workflow. Deliver a reproducible playable build, setup instructions, tuning configuration, a short known-issues list, and a capture of a complete run. This is a build brief; no repository or project has been created by this document.

## 12. Acceptance checks and playtest decision

Functional checks:

- Touch and keyboard can complete the route and replay without stale state.
- 49 → +1 produces one section with no loss of value; 120 → ×2 produces 240; 105 → −10 produces 95 and correctly updates the section visuals.
- Gate pairs, spectator clusters, and obstacles each apply only once, even with overlapping actors or repeated events, including a cluster that fills while moving, and a wave that reaches the parade unconverted (it damages HP exactly once and never credits).
- Large jumps assemble in one animation; a synthetic total of 10,000 keeps the counter accurate and respects visual budgets.
- Client attempts to forge crowd gains or retrigger consumed gates do not alter server totals.
- Total score equals the final crowd total; score and replay remain usable with sound off.
- Measure on a named lower-end mobile test device, targeting sustained 30 FPS through the largest authored parade and finale. Record the device, observed frame times, and any limits; do not treat desktop automation as mobile validation.

Amendment 1 checks: a no-input run ends defeated; a competent scripted run completes with HP above zero; the same-tick ordering below is covered by tests; attacks never change `crowdTotal`; HP never goes below zero and never regenerates; defeat ends the run once and later events are ignored.

Record: run start/seed, first recruitment, gate choice and before/after totals, first assembly/time, obstacle losses, completion/final total, and replay. Distinguish automated QA sessions from human playtests.

For an initial directional test with 10 Spanish-speaking players unfamiliar with the game, aim for at least 8 to understand steering and growth without coaching, 7 to correctly explain what a puppet represents, and 5 to voluntarily replay. These are proposed internal targets, not industry benchmarks or proof of revenue potential. Ask what felt satisfying or confusing before explaining the design.

If players do not understand assembly or want another run, improve the core loop before expanding content or monetization. Later monetization candidates are puppet outfits, globo decorations, trails, and celebrations that preserve readable crowd math.

---

## Amendment 1 — Attacking waves and parade HP (owner decisions, 2026-10-23)

**Superseded in part by Amendment 4 (issue #121):** the separate parade HP, its bar, its defeat check and its HP balance no longer exist. Attacks and tomatoes remove followers instead. Read every HP statement below as the crowd total.

Supersedes, where they conflict: §3 and §4 (static sidewalk clusters; "leave range without a penalty"), §9 ("Reaching the plaza always completes the run") and §12's "no penalty" wording. §5's "No death or destruction animation" is clarified, not removed: defeat is a playful party breakup, never a death or destruction animation. "Zero followers is recoverable" still holds. Everything not listed here is unchanged: crowd math (§5), gates (§6), sections (§7), visual budgets (§8), and the −10 obstacle.

**Waves attack until converted.**
- The layout places spectator clusters in waves. Each cluster starts at a spawn point ahead of the lead, on a sidewalk or in the lane, and walks toward the parade at `spectators.approachSpeed` (Config) along a deterministic path. The server position of every cluster is a pure function of layout, seed and run time, so the layout validator and the scripted-run test can compute it.
- We shoot musical notes, love (hearts) and snacks at them. Mechanically every shot is one hit (§4); hearts and snacks are visual variants, and dancers' gift cadence (§4) is unchanged.
- **Conversion** (unchanged mechanics): when a cluster's meter fills it is credited once, wherever it is; its members then join the parade (they run in from where they stand), and the cluster is removed.
- **Attack:** a cluster that reaches the parade unconverted attacks. It deals its type's `attackDamage` (Config) to parade HP exactly once and is then removed (a cluster can never damage twice). Hits are playful and cartoonish (bonks, bumps, flying hats, no gore) but must feel impactful: screen punch, a hit sound cue, the HP bar jolts.

**Crowd size and HP are separate.**
- `crowdTotal` is unchanged: it drives gates and section assembly and is never reduced by an attack. Only the −10 obstacle (§9) and downward gates reduce it.
- `parade HP` is a second integer, `hp`, starting at `hp.max` (Config) and reduced only by attacks. It never goes below 0 and has no regeneration or healing in this prototype.
- **At zero HP the run ends** as *defeated*: the parade stops and the party breaks up playfully (musicians tumble, hats and instruments fly, confetti, followers wander off laughing; never a death or destruction animation) with a short "¡Uy, la calenda se dispersó!" beat, then the results screen. Reaching the plaza with HP above zero wins the run (*completed*). Score is the crowd total at the moment the run ends; the results screen shows completed vs defeated. The session best counts completed runs only. Replay resets everything, HP included.
- The HUD shows HP as a bar with a number next to the crowd counter and works muted (icon, meter, jolt animation).

**Definitions (measured along the street axis from the lead's forward position).** A cluster has *reached the parade* when its position is at or behind the lead's forward position; from that moment it is *passed* (attacks if unconverted) and no longer a target. A cluster's *side* is the sign of its lateral offset from the street centerline (left, right, or center within the tolerance `spectators.centerTolerance` in Config).

**In range** means the distance along the street from the lead to the cluster is at most `firing.range` (Config). **Targeting.** Eligible = in range, meter not full, not yet passed. Steering toward a side prefers eligible targets on that side; otherwise the nearest target to the lead is chosen. No eligible target means no shots.

**Same-tick ordering (server and validator must agree).** Within one simulation tick, in this order: (1) shots land, meters fill and conversions are credited (a cluster that fills on the tick it reaches the parade converts and does not attack); (2) the lead moves, then gates are resolved and then the obstacle is applied (crowd total changes); (3) unconverted clusters that reached the parade this tick attack, each once, reducing HP in cluster-id order; (4) end checks: if HP is 0 the run ends defeated, even if the lead also reached the plaza on this tick; otherwise reaching the plaza completes the run. Events after the run ends are ignored. Score is the crowd total after all of that tick's events.

**On defeat** there is no plaza finale and no celebration tier is shown; the party breakup beat and the results screen play. The finale and the three tiers (§9) are for completed runs only.

**Balance.** Conversion speed (fire rate), wave size, approach speed and `attackDamage` are tuned in Config and the layout so that the player has to react: standing still or ignoring a side should lose HP, and a careful player should usually finish with HP left. The layout validator and the scripted-run test must show both a no-input run (defeated) and a competent run (completed), and report the HP trajectory. All values are initial defaults.

**Gates stay stationary in the lane**; the gate pair rules (§6) are unchanged.

**Feel reference:** Mob Control. A dense, readable swarm; a bar with a large number above each group (the excitement meter with its hit count). Reference only; no copying of assets, branding or UI.


---

## Amendment 2 — Continuous fire (owner decision, 2026-10-24)

Owner feedback, twice: "the shooting should just be continuous" and "the projectiles are weak and seldom". Recorded in [ADR 0004](../.trazo/project/adr/0004-continuous-fire.md).

Supersedes, where they conflict: §3 ("No target means no projectile spam"), §4 (starter firing rate 3 and the `min(12, 3 + sectionCount)` curve), and Amendment 1's targeting line "No eligible target means no shots". Everything not listed here is unchanged: eligibility, side preference, credit-once, meters, the gift cadence, the same-tick ordering, server authority, crowd math (§5), gates (§6), sections (§7), budgets (§8), the −10 obstacle and parade HP.

**Firing is continuous.**
- The parade shoots at the firing-rate curve whether or not anything is in range. The curve is `min(firing.cap, firing.base + firing.perSection * sectionCount)` shots per second with the new named defaults `firing.base = 6` (was 3), `firing.cap = 20` (was 12) and `firing.perSection = 1` (kept). Each is one Config line; `firing.cap` is validated to be at most 30, the server tick rate, because every shot is one replicated event.
- A shot with an eligible target (Amendment 1 targeting, unchanged) goes to it and **counts as a hit**: one meter hit, credit-once, gift cadence unchanged (every fourth shot once a dancer section exists, counted over all shots, hit or miss).
- A shot with **no eligible target** still fires, straight ahead, as a **miss**: visual only. A miss never fills a meter, credits, damages, consumes a cluster or changes `crowdTotal` or HP, and it is not a gameplay event. It is replicated to the owning player only as a lightweight, bounded, display-only `miss` Event (shot kind and shot number only; no id, position or reward), validated when encoded and again when decoded.
- The same-tick order (Amendment 1) and server authority are unchanged: shots (hits and misses) are phase 1.

**Balance.** Doubling the base rate changes conversion speed, so the HP and recruit balance evidence is stale: the #17 ladder must be re-run after this lands. The fixed debug layout was retuned only enough to keep the Amendment 1 checks true (no-input run defeated, competent run completed with HP left); its numbers are provisional.

**Presentation.** Shots are bigger and readable (a glowing core, a short trail, a muzzle pop at the lead, an impact burst and squash on the target group, distinct note / heart / snack looks); misses fly off into the distance and fade. All pooled with hard caps; every knob is a named `[default]` constant in `ShotLook`. In-engine feel is unverified until a Studio pass.

**Checks.** Rate curve at 0, 1, 9 and 100 sections; misses never credit, damage or consume; hits still credit once; the gift cadence is unchanged; a fixed clock is deterministic; per-tick event caps hold at the top rate.


---

## Amendment 3 — Mobs, the charge and tension from the top (owner decisions, 2026-10-24)

Owner feedback: "there shouldn't be spectator GROUPS, there should be MOBS of them", "like a zillion spectators", the unconverted wave must charge into the parade like the red mass in the reference (used for readability only, no artwork copied), and "each level needs a little tension; the crowd just suddenly appears, shouldn't they start from the top?". Issue #65.

Supersedes, where they conflict: the Amendment 1 / §4 picture of small groups of 3-8 blocks that swing around the parade and disappear. Everything else is unchanged: a "mob" is still a cluster (id, type, reward, hits, path), hits, credit-once, damage and server authority are untouched, and no field is added to any replicated payload.

- **Spectators as individuals.** The visual is decoration derived on the client: each cluster stands `reward x 2` individual figures (body, head, raised arms) on a loose, jittered scatter across the lane (`SpectatorScatter`, tunables in `Config.spectators.scatter`), never closer than 2.1 studs, capped per mob and on screen by `QualityConfig` (high / medium / low). Each person has a deterministic seeded start time, lateral and longitudinal offset, turn, approach speed, and arrival; people do not move or arrive as a group around the cluster center. Human-scale body and head silhouettes stay legible from the gameplay camera, with far figures enlarged up to 3x. Ambient street crowds (#54 phase 2) reuse the same modules.
- **The charge.** Unconverted mobs run straight down the lane as a wedge with stride, raised arms and a forward lean, stop at the front of the parade, and on the server's attack Event slam in (the bump, shake and HP hit of #50) and only then scatter to the sidewalks and dissolve into a puff. Converted mobs recolour to the party palette and stream into the parade. Spectators are attackers until converted: angry-mob colouring before, party fans after, always a friendly cartoon tone.
- **Tension from the top.** A cluster spawns beyond the camera's visible depth plus a margin (`Emergence`, derived from `CameraRig`); a wave is in view for at least 3 seconds before it arrives; nothing is in view during the first 5 seconds; a mob fades and scales in at the far end; a warning chevron and dust mark the top of the lane; a colour pulse on the mob and a screen-edge pulse grow as it closes in. `LayoutValidator` enforces the spawn, approach and calm-opening rules for every layout.
- **Balance consequence.** A wave that really approaches from far away is inside `firing.range` for `range / (speed + approachSpeed)` seconds instead of the old 1 second, so it is easier to convert. To keep the Amendment 1 checks true the debug layout was retimed (provisional, flagged for the skeptic): `spectators.approachSpeed` 6 to 20, every pair 9 seconds later, and rising lines of extra small groups. The #17 ladder must be re-run.


---

## Amendment 4 — The parade size is the life bar (owner decision, 2026-10-24)

Owner decision on issue #121, recorded in [ADR 0006](../.trazo/project/adr/0006-parade-size-is-the-life-bar.md) (life bar) and [ADR 0007](../.trazo/project/adr/0007-share-rule-for-parade-losses.md) (loss rule): "the life bar should be the calenda's candela, the parade's life." A horde that is not shot costs followers; the run ends when the parade has none.

Supersedes, where they conflict: all of Amendment 1's parade HP (its "Crowd size and HP are separate" section, the `hp` integer, `spectators` HP damage, the HP-based ordering in phases 3 and 4, the HUD HP bar and the HP balance paragraph); §9's "Zero followers is recoverable" and the tomato line "costs 5 parade HP"; §11's `parade HP (hp.max)` and `attackDamage` keys; §12's HP checks and "no penalty" wording; Amendment 1's "Amendment 1 checks" HP items; and Amendment 2's balance note where it names HP. Everything else is unchanged: crowd math (§5), gates (§6), sections (§7), visual budgets (§8), the −10 obstacle, cluster conversion, credit-once, targeting, continuous fire and server authority.

**One life number.**
- `crowdTotal` is the only life. There is no `hp`, no `maxHp`, no HP bar and no HP in any replicated payload, Config key or run log field. The HUD shows the crowd counter, and a hit reacts through the existing shake, flash and sound.
- Config owns every loss amount: `attackSharePercent` (10) and `minShareLoss` (1) for hordes, `hazards.tomatoSharePercent` (10) for tomatoes, and `obstacleLoss` (10) for the obstacle. Each is one whole-number Config line.

**Losses (share rule, ADR 0007).**
- A horde that reaches the parade unconverted (Amendment 1, "Attack") removes `max(minShareLoss, floor(attackSharePercent × total / 100))` followers from `crowdTotal`, exactly once, and is removed. The same share applies to every horde type. The total is the parade as it stood immediately before that hit. Hordes in the same batch chain: each share is taken from the total after the previous hit.
- An unblocked tomato (§9, issue #96) removes `max(minShareLoss, floor(hazards.tomatoSharePercent × total / 100))` followers, once. A landed gift still blocks it.
- The −10 obstacle (§9) is a fixed `obstacleLoss` and is unchanged.
- Every loss clamps at zero: a total never goes below 0. The loss goes through the same total as every other change, so sections disperse by the normal rule (§5, newest first) and the counter and visuals stay exact.
- Losses never change gates, the recruit credit, the firing rate or any section's contents beyond the normal total rule.
- Rounding is floor, then the minimum of 1. This rounding is an explicit design call, not verified by a playtest or bot run (ADR 0007, UNVERIFIED).

**Defeat.** The run ends defeated the moment `crowdTotal` reaches 0 (`outcome` "defeated", once, logged). The score is the crowd total at that moment, so a defeated run scores 0. The session best counts completed runs only. Replay resets the total to the starting total.

**Same-tick order (Amendment 1, revised).** Phase 1 (shots and conversions) and phase 2 (lead, gates, obstacle and hazards) run as before. A total that reaches zero in phase 2 ends the run there, and any later event in that tick is ignored. In phase 3, each unconverted cluster that reached the parade attacks once in id order, each share taken from the total left by the previous hit; a total reaching zero during phase 3 ends the run after the remaining attacks of that batch are recorded at zero. Defeat still wins over reaching the plaza on the same tick.

**Balance (provisional, OPEN, not measured under the share rule).** `attackSharePercent` 10, `minShareLoss` 1 and `hazards.tomatoSharePercent` 10 are first guesses and are UNVERIFIED. The earlier fixed-loss measurements (debug layout, one probe run per policy and rate, 30 Hz and 10 Hz: the no-input run about 800 after 12 attacks; the scripted run about 1,450 after 13 attacks) were taken under the superseded fixed-loss rule and are not evidence for the share rule. The no-input defeat check and the competent-run check must be measured under the share rule. The #17 ladder re-run is a separate open gate and must pass before the balance is accepted.

**Checks.**
- A horde or tomato removes exactly its share of the total before the hit, at least `minShareLoss`, once; a second event for the same cluster or tomato removes nothing.
- A same-batch pair of hordes takes the second share from the total after the first.
- The total is clamped at zero and never goes negative.
- Reaching zero defeats the run once; later events are ignored; reset restores the starting total.
- No `hp` field exists in RunState, the run snapshot, the State payload or Config; no `attackLoss` or `tomatoLoss` key exists.
- Clients display the server's total only and never compute a loss.

## Amendment 5 — Steering chooses the side; hordes keep arriving (owner decisions, issue #142, 2026-10-26)

Owner decisions recorded on [issue #142](https://github.com/manoochehri/calenda/issues/142): "the hordes of spectators just stop, they should be continuous," and an idle win has no challenge.

Supersedes, where they conflict: §3's "center position chooses the nearest eligible target"; Amendment 1's targeting line ("otherwise the nearest target to the lead is chosen") and its "Targeting" sentence; and Amendment 1's "Attacking waves" schedule, which ends its waves at the 10th pair. Everything else is unchanged: eligibility, credit-once, meters, the gift cadence, continuous fire (Amendment 2), the same-tick order, server authority, the share loss rule and its 10% values (ADR 0007), gates, sections and crowd math.

**Targeting follows steering.**
- The server reads the lead's lateral position and derives its side with `Level.sideOf` (`spectators.centerTolerance`). Steer left engages only eligible hordes on the left; steer right only eligible hordes on the right.
- Among eligible hordes on the steered side, the nearest to the lead is chosen (ties: lowest id).
- Center steering engages no horde. Every shot is a visual-only miss (Amendment 2), with no meter, credit or loss.
- There is no fallback to the other side. A horde on the side not steered to is not engaged and attacks on reaching the parade as before.

**Continuous arrivals.** Each authored layout keeps the 2.5-second pair rhythm through the late route. Pairs arrive on that spacing for as long as the last arrival is at or before the plaza minus 2 seconds, so the last horde reaches the parade within 3 seconds of the plaza (the layout test checks this). Pairs past each layout's authored soak list repeat its last soak count. The plaza, the finite run and the `maxTotal` bound are unchanged.

**Checks.**
- Hordes keep arriving through the late route on every playable layout (`tests/issue142_continuous_hordes.test.luau`).
- Center steering targets nothing, and steering to a side never engages the other side (`tests/targeting.test.luau`).
- A no-input run (no steer messages) is defeated before the plaza on every playable layout. A scripted competent run completes on every playable layout. Both are measured with the BotHarness at 30 Hz, one seed; the balance evidence is UNVERIFIED until the skeptic clears it.
- The layout validator's `maxTotal` bound applies to every layout. Where the best route exceeds `maxTotal` the layout is not accepted; the bound is not raised by this amendment.

## Amendment 6 — The layout validator bound is raised (owner decision, 2026-10-26)

Supersedes, where they conflict, the Amendment 5 checks line that says the `maxTotal` bound is not raised. `maxTotal` is raised from 2500 to 4000 and now lives in `Config.layout.maxTotal`, read by every authored layout. The best-route totals on this branch are calle-del-mercado 3390, portal-del-sur 3850 and esquina-de-la-banda 3490, so 4000 is the smallest round value that covers all three. The 10% loss rule, the steering-targeting rule and the authored layouts are unchanged. The balance evidence this raise rests on is UNVERIFIED until the skeptic reviews it.

## Amendment 7 — The horde attack share is 7% (owner decision, 2026-10-26, issue #148)

Supersedes, where they conflict, the 10% value of `attackSharePercent` in Amendment 4 and Amendment 5 and the "10%" and "attackSharePercent 10" balance statements in this document. `attackSharePercent` is changed from 10 to 7 in `Config.attackSharePercent`. Recorded in ADR 0009, which supersedes the 10% value of ADR 0007. ADR 0007's loss rule, its floor rounding, its `minShareLoss` of 1 and `hazards.tomatoSharePercent` (10) are unchanged. The loss formula, server authority, targeting, layouts and the tomato and obstacle losses are unchanged.

**Measured basis (owner approval).** Sample: 3 layouts, seeds 1-10, 30 Hz, n=3 effective per policy. At 6, no-input and always-center runs completed 10 of 30 (one layout, all seeds). At 5, 4 and 3, no-input was also not defeated on every layout. The defeat holds on every layout from 7 upward. The scripted margin was 123 to 172. These numbers are UNVERIFIED: the skeptic has not reviewed them, and the #17 ladder re-run remains open.

**Checks.** A horde that reaches the parade removes `max(1, floor(7% × total / 100))` followers. Example: a total of 100 becomes 93, and 93 becomes 87 on a second hit in the same batch. The tomato share stays at `hazards.tomatoSharePercent` = 10.

## Amendment 8 — Clear the gameplay screen (owner request, issue #160, 2026-10-29)

During active play, show no screen crowd counter, loose/section count, next-section meter,
steering hint or section-gain toast. Do not replace them with a bar, banner or tutorial overlay.
Owner rationale: an overwhelmed parade loses and the run ends; no numerical HUD is needed.
The visible parade and world gate/target numbers carry gameplay feedback; the final total
appears once on the results screen. Ending-only finale/defeat banners, title/loading and
results screens remain unchanged.

This supersedes the counter, loose-count, hint, meter and '+N sections' screen-display
requirements in §§7–9 and Amendment 4 (and ADR 0006's client display requirement only).
`crowdTotal` remains the single authoritative life integer: crowd math, losses, defeat,
recruitment, rewards, continuous firing and controls are unchanged. World labels and stack
badges, hit flash/shake/sound, assembly and dispersal remain. No separate HP or music control.

## Amendment 9 — Lane encounters, marching drum and boss checkpoints

Owner-requested scope exception: the first core-loop prototype includes boss encounters, replacing the boss-fight deferral in spec §2 and the charter's corresponding out-of-scope clause for this milestone. Shops, monetization, paid assets, publishing and meta progression remain deferred. Preserve the owner's gameplay HUD-clearance requirement: encounter progress and warnings live in the world, with no new screen HUD.

**Lanes and contact.** Use three logical lanes, left/center/right. Widen the current 28-stud road surface to 30 studs by moving each road edge out one stud within the existing 40-stud street/sidewalk corridor. Keep the existing layout halfWidth=20 and all existing maximum steering/speed/rate/safety limits. For this authored segment clamp the desired lead x to [-15,15]. Lane bands are [-15,-5), [-5,5), [5,15], with centers -10,0,10; exact boundaries belong to the lane to their right. Continuous horizontal steering remains; it is not a lane-snap control. One pure lane resolver supplies server targeting, activation, contact and client markings. Assign every mob an authored lane; do not infer gameplay contact from decorative people wandering across a band.

A +1 pickup is an optional distance-plane crossing, once per id, only when the lead's x at the interpolated crossing lies in its lane. It adds exactly one through crowdTotal; passing elsewhere expires it without reward or loss. Followers never consume pickups. A strip contains six pickups 1.5 travel-seconds apart. The first segment has three strips, one in each travel third, cycling left/right/center; start the first strip at travel-second 8. Keep clear distance from checkpoint planes. Paired math gates remain a different encounter type: one pair consumption, choose nearest offered portal at crossing, ties to the lower lane index. First-prototype offers are ×2 versus +5, twice, at travel-seconds 20 and 50. Portals occupy left/right lanes; center therefore chooses left on the exact tie. World labels show the operation and projected result. No ×3/×4 catalog is needed for this slice. The existing maxTotal=4000 authoring bound remains: validate the authored route; do not raise the bound or clamp advertised multiplication.

Normal mobs still convert: small requires 3 baseline hit-points and rewards 5 followers; large requires 8 and rewards 15. Partial progress persists per mob; fill credits the existing reward once. An unconverted mob crossing the lead plane attacks only if its authored lane equals the lead's lane at crossing, then is consumed. Off-lane mobs pass without conversion, reward or loss and are consumed. This explicitly replaces the prior off-lane attack rule and center-no-target rule. Contact still removes max(1,floor(7*currentTotal/100)), chaining in stable id order. Tomatoes retain max(1,floor(10*currentTotal/100)), existing landed-gift blocking, and obstacles retain fixed loss 10. CrowdTotal remains the parade's sole life integer; zero defeats the run. Lane-bounded attacks invalidate old balance results; rerun #148 rather than carrying old results forward.

**Shots and target choice.** Keep continuous firing min(20,6+sectionCount) shots/sec, range 60, existing event/pool caps and one authoritative target per shot. All three lanes can engage. Choose the nearest eligible ahead target in the lead's lane across mobs and unlock targets, plus an active boss candidate only in its authored lane (mini-boss 1 left, mini-boss 2 right, final boss left). Break distance ties by type (mob, unlock, boss), then stable id. No other-lane fallback, piercing or splash. Boss target distance is 45 studs while its checkpoint is active; center does not auto-hit an off-lane boss, so idle center cannot win a checkpoint; closer mobs can intercept, farther mobs cannot. Empty-lane shots remain visual misses. Notes and hearts retain the existing alternation. Every fourth shot is a lobbed gift from run start, explicitly removing the dancer-section prerequisite but preserving the cadence and landed-gift tomato interaction. Notes/hearts/gifts have the same baseline mechanical strength. No guessed asset IDs.

**One unlock and one stronger attack.** The first power-up is a marching drum. Author one center-lane stationary unlock target before each checkpoint, at travel-seconds 28,58,88. It is eligible only after spawning, ahead and within range; it needs 12 landed shots, each advancing unlock progress by exactly 1 even during an existing boost. Partial progress persists until filled or passed. Filling releases and automatically equips the drum immediately, once; there is no second collectible, extra input, follower reward or shop. Passing an unfilled target consumes it with no effect. Show remaining shots on the world target. The drum makes each shot worth 2 hit-points against its single selected mob or boss, without extra shots, targets or events. Fill/conversion still pays the normal reward once; excess progress is discarded. Duration is 8 simulation/combat seconds, including checkpoint combat. Reacquiring refreshes expiry to now+8, never stacks strength or banks duration. Strength is evaluated at the existing authoritative shot-resolution instant. Reset boost/progress on defeat, replay and level transition; travel checkpoint entry does not reset it. The drum is visible on the parade; its stronger musical impact and expiry are world feedback, not a HUD meter.

**Two mini-bosses and a final boss.** First-prototype checkpoints occur at 30,60,90 travel-seconds at Config.speed=14.4 (z=432,864,1296). Two mini-bosses require 48 and 72 hit-points; the final boss requires 120. These are enemy encounter progress values, never a second parade HP system. Use one original primitive performer/giant-puppet silhouette family with size/palette variations, world remaining-progress numbers and playful departure on victory. Bosses are not convertible ordinary mobs, grant no followers or extra unlock, and cannot damage by mere overlap. Their explicit attack is a lane strike: warn at encounter-second 1.5 and impact at 3; repeat every 3 seconds. Strike lanes cycle left,center,right. Show the warned lane in the world using symbol/shape plus color. At impact, only a lead in that lane loses max(1,floor(7*currentTotal/100)); steering to either other lane avoids the strike. Strike intent is independent of the lane used to shoot. There is no invulnerability, healing or additional attack pattern. Boss-local extra-mob schedule is EMPTY for this first prototype; active incoming route mobs keep moving/attacking/converting under the lane rule. No silent endless boss spawner. Boss strikes continue until defeat/victory, so exhausting the finite active mob set does not remove the boss threat.

**Travel, clocks and resolution.** Preserve outer ready/running/over flow; within running use traveling, mini-boss-combat, final-boss-combat and cleared phases. Simulation time advances for firing, steering, active mobs, attack warnings and boost expiry. Travel time/distance advance only while traveling. Clamp z exactly to the next unresolved checkpoint; discard that tick's unused travel distance rather than accumulating it. Mini-boss victory resumes on the next tick from that z. Final-boss victory clears the level; plazaStart alone never clears it.

Future route spawns and route hazard schedules use travel time and wait during boss combat. On spawn, record simulation time and advance that mob's deterministic path with its own simulation age; never recompute an already active mob from a frozen travel clock. Existing active hazard warnings finish on simulation time, so do not freeze a visible warning or emit duplicate warning/impact on resume. Distance crossings require positive forward progress; stationary lateral movement cannot recollect a pickup. Resume emits neither queued route spawns nor a distance jump. All route and boss schedules are finite authored data except the active boss's bounded periodic strike loop.

Per tick: capture due intents for an already active boss; resolve scheduled shots/conversions using start-of-tick lane/positions and existing ordering; advance lateral motion and clamped travel; resolve ordered gate/pickup/obstacle crossings and active hazard impacts; resolve arriving mob contacts then the already-due boss strike against the updated lane; resolve defeat, then boss victory, then resume/clearance. Interpolate x for distance crossings. A killing shot does not cancel a strike already due on that tick: if crowd reaches zero, defeat wins and no victory/resume/clearance reward occurs. Preserve the existing immediate-zero termination and same-batch mob logging rule. Boss entry during a tick starts its attack clock for subsequent ticks. Expiry uses half-open boost interval [grantTime,expiryTime); events at expiry use baseline strength.

Boss resolution and checkpoint entry/resume/clearance are once per (run,level,encounter). Replicated state includes phase, run/level identity, simulation timestamp, travel z/velocity, active encounter identity/progress and boost expiry. Clients recover from state after missed events and stop longitudinal camera/parade extrapolation in combat while lateral smoothing and animation continue. Explicit run/level identities replace relying solely on clock backsteps for resets. Replay resets every clock/encounter/consumption/boost; level transitions preserve the existing crowd carryover but clear local encounter/attack state.

After final-boss clearance, play the existing plaza celebration for 8 seconds, then advance to the next configured level carrying the exact crowd total, or show results once if this was the final level. Disable new combat/spawns during celebration. This replaces immediate plaza-triggered transition/completion; score remains the final exact crowd total, with zero on defeat.

**Rendering and evidence.** Preserve authored logical mob counts and the continuous 2.5-travel-second pair schedule, including current authored soaks, while traveling. Move outer-lane spawn x positions to lane centers without deleting mobs. Keep existing 6 section/24 loose follower budgets, QualityConfig caps and event/pool limits. Preserve dense people-like silhouettes through rendering/layout work, not arbitrary removal of logical opponents. #147 compares pooled Parts and optional sprite/hybrid/LOD representations on the same representative logical encounter, including active mobs, boss, shots and scenery. Measure frame times and sustained FPS on a named low-end phone against the charter's existing 30 FPS target, recording device, build, settings, run length and sample size. Record people/readability checks separately from performance. No renderer is declared faster without measurements; no default here authorizes exceeding existing hard visual limits. Fill visible background coverage and verify camera/frame/reset paths; Backdrop already constructs earth and scenery, so first diagnose the observed void. All new numeric defaults and balance are UNVERIFIED pending functional tests, engine/device checks and independent skeptic review of empirical results. Existing playtest/stop rules remain.
