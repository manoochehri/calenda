# Calenda — Prototype Specification

Version 1.0 · October 23, 2026 · Platform: Roblox · Primary language: Spanish

## 1. Pitch and prototype goal

Lead a tiny marching party down an Oaxaca-inspired street. Throw musical notes and gifts to invite spectators, pass through math gates to multiply your followers, and assemble the growing crowd into dancing giant puppets, spinning globos, and decorated dance sections. Finish by filling a plaza with a spectacular celebration.

**Core loop:** recruit → choose a gate → grow → assemble a parade section → recruit faster → celebrate → replay.

The prototype must answer: Is recruiting satisfying? Is the math understandable? Does the first giant puppet make players want to grow the parade again? Commercial success is unproven; this build tests the game’s appeal.

## 2. Scope

Build one approximately 90-second playable street plus an 8–10-second plaza finale. Use an individual run with NPC spectators; multiplayer interaction is deferred. Support touch and keyboard. Include three simple section visuals, one layered music track, positive math gates, one obstacle type, results, and immediate replay.

Build in stages: first get the entire loop working with one puppet; then add the globo and dancer sections. These are stages of the same prototype, not separate games.

Deferred: shops, paid multipliers, pets, trading, clothing creation, custom music uploads, daily rewards, elaborate progression, boss fights, and global leaderboards.

## 3. Controls and camera

- Automatic forward movement; drag horizontally to steer on touch, A/D or arrow keys on keyboard. No jumping or rhythm precision required.
- Elevated camera behind the parade, showing upcoming gates and both sidewalks. Gates must remain readable behind tall props.
- Music notes fire automatically. Steering toward a sidewalk prioritizes that side’s spectators; center position chooses the nearest eligible target. No target means no projectile spam.
- Keep the lead musician visible as the steering anchor. Sections follow in compact rows; decorative size does not enlarge the gameplay collision area.
- Gameplay remains understandable muted through icons, meters, counters, and animations.

## 4. Recruiting spectators

Spectator clusters stand on either side of the street, displaying an excitement meter and a recruit reward. Start with two cluster types: 3 note hits awards +5 followers; 8 hits awards +15. All values are initial tuning defaults.

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

## 9. Level, obstacles, and ending

| Run time | Intended experience |
| --- | --- |
| 0–10 seconds | Start already moving; 'Arrastra para moverte'; recruit the first cluster |
| 10–25 seconds | Two easy gate choices; aim to introduce the first puppet by 25 seconds |
| 25–65 seconds | More recruitment, globo/dancer assembly, and alternating sidewalk choices |
| 65–90 seconds | Largest growth opportunity, a final route decision, plaza approach |
| Finale | Party spreads into the plaza; music peaks; gifts, confetti, score, replay |

Use one readable obstacle: a closed streetwork lane marked with cones and a −10 sign. One collision removes 10 followers, clamped at zero; then that obstacle cannot hit again. Use the lead’s fixed hitbox. Avoid visual injury: some followers peel off to cheer from the sidewalk. Zero followers is recoverable because the lead still recruits.

Reaching the plaza always completes the run. Score equals the final crowd total, with no extra conversion bonus. Show the session best and '¡Otra calenda!' replay button. A lightweight three-tier celebration can use provisional thresholds of 50, 150, and 300 followers; tune these after observing normal runs.

Replay resets all run state. Start with one fixed layout for debugging; after it works, provide three authored gate/cluster arrangements under recorded seeds. Each must be completable without spending or purchases.

## 10. Art, music, and reference direction

Use the user’s supplied photographs as the visual brief: flower baskets and colorful skirts in `image.png`; decorated animal silhouette and painted patterns in `image(1).png`; pole-carried globos in the 8.48.02 PM screenshot; distinct floral outfits in 8.48.18 PM; loose-limbed giant human puppets in 8.48.44 PM. These are visual references, not permission to reproduce specific artwork, branding, faces, or recordings. The team should receive the reference images alongside this document.

Art priorities: big readable silhouettes, warm street colors, bright flower accents, visible carriers, and joyful imperfect puppet motion. Leave the road and gate text visually clear. Treat different outfits and dances as distinct referenced traditions, not interchangeable generic Oaxaca costumes; confirm specific community attribution before labeling content.

Use an original or appropriately licensed brass-and-percussion loop with synchronized stems: percussion at start, brass at first section, fuller bass/ensemble at three sections, and crowd accents at six. Crossfade on musical boundaries. Layer volume must remain controlled; adding sections must not add unlimited audio sources. Gifts and musical projectiles should look friendly and celebratory.

## 11. Implementation boundaries

Keep tunable values in configuration: section size, starting total, cluster hits/rewards, gate operations, losses, speed, firing-rate curve, visual budgets, and finale thresholds.

Separate run state and crowd arithmetic from presentation. The server owns totals, gate/cluster consumption, losses, completion, and score; clients animate the results. Validate steering and crossing events; clients cannot submit arbitrary gains. Use pooled visual actors/projectiles, limited collision checks, and compact formations rather than full independent pathfinding for every represented follower.

Use the team’s existing GitHub and agent workflow. Deliver a reproducible playable build, setup instructions, tuning configuration, a short known-issues list, and a capture of a complete run. This is a build brief; no repository or project has been created by this document.

## 12. Acceptance checks and playtest decision

Functional checks:

- Touch and keyboard can complete the route and replay without stale state.
- 49 → +1 produces one section with no loss of value; 120 → ×2 produces 240; 105 → −10 produces 95 and correctly updates the section visuals.
- Gate pairs, spectator clusters, and obstacles each apply only once, even with overlapping actors or repeated events.
- Large jumps assemble in one animation; a synthetic total of 10,000 keeps the counter accurate and respects visual budgets.
- Client attempts to forge crowd gains or retrigger consumed gates do not alter server totals.
- Total score equals the final crowd total; score and replay remain usable with sound off.
- Measure on a named lower-end mobile test device, targeting sustained 30 FPS through the largest authored parade and finale. Record the device, observed frame times, and any limits; do not treat desktop automation as mobile validation.

Record: run start/seed, first recruitment, gate choice and before/after totals, first assembly/time, obstacle losses, completion/final total, and replay. Distinguish automated QA sessions from human playtests.

For an initial directional test with 10 Spanish-speaking players unfamiliar with the game, aim for at least 8 to understand steering and growth without coaching, 7 to correctly explain what a puppet represents, and 5 to voluntarily replay. These are proposed internal targets, not industry benchmarks or proof of revenue potential. Ask what felt satisfying or confusing before explaining the design.

If players do not understand assembly or want another run, improve the core loop before expanding content or monetization. Later monetization candidates are puppet outfits, globo decorations, trails, and celebrations that preserve readable crowd math.

---

## Amendment 1 — Waves of spectators (owner decision, 2026-10-23)

Supersedes the "stand on either side" placement in §4 and the sidewalk-only targeting in §3 where they conflict. Everything not listed here is unchanged (no combat, no penalty, crowd math, gates, obstacle, score).

- **Waves move toward the parade.** The layout places spectator clusters in waves. Each cluster starts at a spawn point ahead of the lead, on a sidewalk or in the lane, and walks toward the parade at `spectators.approachSpeed` (Config) along a deterministic path. The server position of every cluster is a pure function of layout, seed and run time, so the layout validator and the scripted-run test can compute it.
- **Meter, hits, rewards and credit-once are unchanged** (§4). A cluster whose meter fills is credited once, wherever it is; its members then run into the parade.
- **Missing a wave has no penalty.** A cluster that reaches the parade unfilled passes around it (visual only) and is gone. No loss, no credit, no extra way to lose followers.
- **Targeting.** Eligible = in range, meter not full, not yet passed. Steering toward a side prefers eligible targets on that side; otherwise the nearest target to the lead is chosen. No eligible target means no shots.
- **Pacing.** Wave density and speed are tuned in the layout so the intended recruit total stays reachable at the base fire rate; the layout validator proves it.
- **Gates stay stationary in the lane**; the gate pair rules (§6) are unchanged.
- **Feel reference:** Mob Control. A dense, readable swarm; a bar with a large number above each group (here the excitement meter with its hit count). Reference only; no copying of assets, branding or UI.

