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
- Music notes fire automatically. Steering toward a sidewalk prioritizes that side’s spectators; center position chooses the nearest eligible target. No target means no projectile spam.
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

Use closed streetwork lanes marked with cones and a −10 sign. One collision removes 10 followers, clamped at zero; then that obstacle cannot hit again. Use the lead’s fixed hitbox. Avoid visual injury: some followers peel off to cheer from the sidewalk. Zero followers is recoverable because the lead still recruits.

Issue #96 adds level hazards, drawn from the run seed on the server and listed per level in its hazard set (`Level.Layout.hazardSet`). The first Oaxacan level uses two kinds, at occasional times between 20 and 80 seconds, never before the run starts:
- **Tomato throws** from the buildings. A warning shows 2.5 seconds before the impact. Only a landed gift shot inside that warning window blocks the tomato; note shots do not. An unblocked tomato in the lead’s lane costs 5 parade HP, once (`Config.hazards.tomatoDamage`).
- **Tlayuda cart** across the street, leaving one clear gap 4.5 studs wide, with a warning 2 seconds ahead. Steering into the gap clears it. A collision costs the existing −10 obstacle loss, once.

Later levels select their own hazard kinds in configuration; no level name is checked in code.

Reaching the plaza always completes the run. Score equals the final crowd total, with no extra conversion bonus. Show the session best and '¡Otra calenda!' replay button. A lightweight three-tier celebration can use provisional thresholds of 50, 150, and 300 followers; tune these after observing normal runs.

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

- **Mobs by level of detail.** The visual size is decoration derived on the client: `MobLod.mobSize = reward x 60 x quality scale`, hard-capped per quality level (`QualityConfig`: high / medium / low, one pure config shared with the future JuiceConfig). Near the camera a few hundred pooled real figures (body, head, raised arms) are moved in bulk; the rest is a ParticleEmitter swarm; the two crossfade by the screen share of a figure. Ambient street crowds (#54 phase 2) reuse the same modules.
- **The charge.** Unconverted mobs run straight down the lane as a wedge with stride, raised arms and a forward lean, stop at the front of the parade, and on the server's attack Event slam in (the bump, shake and HP hit of #50) and only then scatter to the sidewalks and dissolve into a puff. Converted mobs recolour to the party palette and stream into the parade. Spectators are attackers until converted: angry-mob colouring before, party fans after, always a friendly cartoon tone.
- **Tension from the top.** A cluster spawns beyond the camera's visible depth plus a margin (`Emergence`, derived from `CameraRig`); a wave is in view for at least 3 seconds before it arrives; nothing is in view during the first 5 seconds; a mob fades and scales in at the far end; a warning chevron and dust mark the top of the lane; a colour pulse on the mob and a screen-edge pulse grow as it closes in. `LayoutValidator` enforces the spawn, approach and calm-opening rules for every layout.
- **Balance consequence.** A wave that really approaches from far away is inside `firing.range` for `range / (speed + approachSpeed)` seconds instead of the old 1 second, so it is easier to convert. To keep the Amendment 1 checks true the debug layout was retimed (provisional, flagged for the skeptic): `spectators.approachSpeed` 6 to 20, every pair 9 seconds later, and rising lines of extra small groups. The #17 ladder must be re-run.


---

## Amendment 4 — The parade size is the life bar (owner decision, 2026-10-24)

Owner decision on issue #121, recorded in [ADR 0006](../.trazo/project/adr/0006-parade-size-is-the-life-bar.md): "the life bar should be the calenda's candela, the parade's life." A horde that is not shot costs followers; the run ends when the parade has none.

Supersedes, where they conflict: all of Amendment 1's parade HP (its "Crowd size and HP are separate" section, the `hp` integer, `spectators` HP damage, the HP-based ordering in phases 3 and 4, the HUD HP bar and the HP balance paragraph); §9's "Zero followers is recoverable" and the tomato line "costs 5 parade HP"; §11's `parade HP (hp.max)` and `attackDamage` keys; §12's HP checks and "no penalty" wording; Amendment 1's "Amendment 1 checks" HP items; and Amendment 2's balance note where it names HP. Everything else is unchanged: crowd math (§5), gates (§6), sections (§7), visual budgets (§8), the −10 obstacle, cluster conversion, credit-once, targeting, continuous fire and server authority.

**One life number.**
- `crowdTotal` is the only life. There is no `hp`, no `maxHp`, no HP bar and no HP in any replicated payload, Config key or run log field. The HUD shows the crowd counter, and a hit reacts through the existing shake, flash and sound.
- Config owns every loss amount: `clusterTypes.small.attackLoss` and `clusterTypes.large.attackLoss` (followers lost when that type's unconverted cluster reaches the parade) and `hazards.tomatoLoss` (followers lost to an unblocked tomato). Each is one whole-number Config line.

**Losses.**
- A horde that reaches the parade unconverted (Amendment 1, "Attack") removes its type's `attackLoss` from `crowdTotal`, exactly once, and is removed. A horde is not a fraction of the parade: the amount is fixed per type.
- An unblocked tomato (§9, issue #96) removes `hazards.tomatoLoss` followers, once. A landed gift still blocks it.
- The −10 obstacle (§9) is unchanged.
- Every loss clamps at zero: a total never goes below 0. The loss goes through the same total as every other change, so sections disperse by the normal rule (§5, newest first) and the counter and visuals stay exact.
- Losses never change gates, the recruit credit, the firing rate or any section's contents beyond the normal total rule.

**Defeat.** The run ends defeated the moment `crowdTotal` reaches 0 (`outcome` "defeated", once, logged). The score is the crowd total at that moment, so a defeated run scores 0. The session best counts completed runs only. Replay resets the total to the starting total.

**Same-tick order (Amendment 1, revised).** Phase 1 (shots and conversions) and phase 2 (lead, gates, obstacle and hazards) run as before. A total that reaches zero in phase 2 ends the run there, and any later event in that tick is ignored. In phase 3, each unconverted cluster that reached the parade attacks once in id order; a total reaching zero during phase 3 ends the run after the remaining attacks of that batch are recorded at zero. Defeat still wins over reaching the plaza on the same tick.

**Balance (provisional).** The `attackLoss` and `tomatoLoss` defaults are first guesses on a starting total of 10 and are UNVERIFIED until the layout validator, the bot runs and the #17 ladder are re-run. The checks are: a no-input run ends defeated; a competent scripted run completes with followers left; a single lost horde never ends a competent run. Owner review sets the final values.

**Checks.**
- A hit removes exactly its configured loss, once; a second event for the same cluster or tomato removes nothing.
- The total is clamped at zero and never goes negative.
- Reaching zero defeats the run once; later events are ignored; reset restores the starting total.
- No `hp` field exists in RunState, the run snapshot, the State payload or Config.
- Clients display the server's total only and never compute a loss.
