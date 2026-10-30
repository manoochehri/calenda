# Charter

**Status:** current

**Project:** Calenda — a Roblox prototype
**Owner:** manoochehri
**Started:** 2026-10-23

## Why
Test whether a recruit-and-grow parade game set in an Oaxaca-inspired calenda is appealing, before investing in content or monetization. Commercial success is unproven; this build exists to answer the questions below. Full brief: [docs/Calenda-Prototype-Spec.md](../../../docs/Calenda-Prototype-Spec.md) (the spec is the source of truth for behavior; this charter does not restate it).

## Goal
One playable ~90-second street plus an 8–10-second plaza finale, individual run with NPC spectators, touch and keyboard, built in Roblox (Luau, Rojo), per the spec. Staged: whole loop with one puppet first, then globo and dancer sections.

## Success criteria (measurable)
Agent-verifiable (spec §12 functional checks), each backed by an automated test or a recorded server-side run log:
- 49 → +1 gives 1 section, no value lost; 120 → ×2 gives 240; 105 → −10 gives 95 with correct section count.
- Gate pairs, clusters and obstacles each apply once under repeated/overlapping events.
- Synthetic total of 10,000 keeps the counter exact and stays within the visual budgets (6 section representatives, 24 loose avatars).
- Forged client crowd gains and re-triggered consumed gates do not change server totals.
- Score equals the final crowd total; replay resets all run state.
- Reproducible build: `make test` passes from a fresh worktree and `rojo build` produces a place file.

Owner-run (cannot be done by agents; tracked in the "Owner validation" milestone, not blocking the build milestones):
- 30 FPS sustained on a named lower-end mobile device through the largest authored parade and finale.
- Directional playtest with 10 Spanish-speaking players: ≥8 understand steering and growth uncoached, ≥7 explain what a puppet represents, ≥5 voluntarily replay. These are proposed internal targets, not industry benchmarks or proof of revenue.

## Budget
No cloud spend. No Roblox publishing, no paid assets, no Robux. Effort: agent sessions, one issue per session.

## Hard constraints
- Server owns crowd totals, gate/cluster/obstacle consumption, losses, completion and score; clients only animate (spec §11).
- One authoritative integer `crowdTotal`; no hidden caps; every tunable lives in configuration (spec §5, §11).
- No monetization, shops, multiplayer interaction or other deferred items (spec §2).
- Gameplay is understandable muted; gates identified by symbol and text, not color alone.
- Audio and art must be original, appropriately licensed, or placeholder. Never guess or invent Roblox asset IDs; unverified IDs are marked UNVERIFIED. Reference photos are a visual brief only, not to be reproduced.
- Primary language is Spanish for all player-facing text.
- No secrets in the repo.

## Stop rule
Build: stop adding scope when every build milestone has 0 open issues; the remaining work is owner validation, not more features.
Project: after the 10-player playtest, if fewer than 5 voluntarily replay or fewer than 7 can explain what a puppet represents, no content, monetization or new section-type work is filed until a core-loop (recruit, gate, assemble) change has been built and retested (spec §12).

## Out of scope
Everything in spec §2 "Deferred": shops, paid multipliers, pets, trading, clothing creation, custom music uploads, daily rewards, elaborate progression, global leaderboards; also multiplayer interaction and merging the parade into an animal. Boss fights are owner-approved for the lane-choice milestone (milestone 7): mini-bosses at travel checkpoints and a final boss per level, as specified in spec Amendment 9 and ADR 0010. All other deferrals stand. Charter additions beyond the spec (owner to confirm): no publishing to Roblox, and the Stop rule thresholds restate spec §12's playtest targets as a work-stopping condition.
