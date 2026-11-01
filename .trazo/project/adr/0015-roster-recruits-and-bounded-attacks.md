# 0015: Recruited roster members: a typed ledger inside one crowd total and a bounded attack mix

**Date:** 2026-10-31  **Status:** proposed

## Context
Owner direction on issue #230 (endorsed "nice!!!!", 2026-10-30): recruiting a character type adds a mechanically distinct projectile, and growth and loss become choices. Issue #231 asks for the concrete contract and #232 for the first slice (trumpet and China Oaxaqueña). Spec §7 deferred "different combat classes and special abilities". ADR 0006 makes the parade size the single life integer; ADR 0013 and spec Amendment 14 set a slower fire rate and a one-at-a-time first shooter; Amendment 11 sets the gift cadence; Amendment 9 (ADR 0010) sets the temporary drum boost. The owner extended the contract: rosters are selected per level or theme with stable ids, and only Oaxaca is active now.

## Decision
The spec text is Amendment 16. In summary:
1. **No second HP.** `crowdTotal` stays the only life integer. The server keeps an ordered list `named` of distinct roster `typeId`s; ordinary members are `crowdTotal - #named`, derived, not stored. After any total change to `T'`, `named := first min(#named, T') entries`. This one rule gives ordinary-first, reverse-acquisition loss, is composable for losses (not across gains; the stable tick order is kept), and lets gate gains and multiplication touch ordinary members only.
2. **Recruit by lane encounter.** A named station in the recruit lane (ADR 0014), crossed once per `(runId, levelId, id)`, grants a named member as exactly +1 when `crowdTotal >= threshold` and the type is absent; a repeat offer is an ordinary +1; unmet or missed grants nothing. Initial thresholds 50 (trumpet) and 100 (China), provisional.
3. **Bounded mix, not extra streams.** Each shot slot is the base shot, a gift, or the attack at `cycle[n mod #cycle]` over `[base] ++ named attackIds`. A named attack with no eligible target falls back to the base attack in the same slot; no charge is banked. Multi-slot attacks consume following slots, so hit-point throughput never exceeds the tier rate. The temporary drum boost multiplies hit-points and is neither a member nor a roster attack.
4. **Data-driven rosters.** A `Roster` module, selected per level by `LevelTheme`, holds typeId, attackId, threshold, display key and an `active` flag. Generic code sees opaque validated ids only. Oaxaca is the only active roster; this contract authorizes no beach or other level content.
5. **Slice and reserve.** `trumpet` (nearest eligible mob) and `china` (rearmost eligible mob in the lane, lobbed) are active. Tuba, drummer, firework carrier, tiliche, rooster and vaca have exact provisional defaults in the spec but stay inactive until #233 settles status replication and ordering. Every named roster entry is preserved; vacas are not replaced by toritos.
6. **Replication.** `StatePayload.roster`, optional shot field `a`, `encounter.kind = recruit`, all validated against the active roster. The client only displays.
7. **Level carryover.** Named members carry across a level only if the next roster has the same typeId; otherwise they become ordinary with the total unchanged. Replay clears them.

Supersedes only: spec §7's sentence deferring combat classes and special abilities, for the roster. Changes the existing contracts of: `Remotes.StatePayload` (adds `roster`), the shot event (adds `a`), `Remotes` encounter kinds, `RunState` (adds the ledger and `recruit` in its mutation set), `Targeting` (attack selection, still one target per slot for the slice), `LevelTheme` and `LayoutValidator`. ADR 0004's cadence, ADR 0006, ADR 0007, ADR 0009, ADR 0013 and Amendments 9, 11, 14 are not changed.

## Alternatives considered
- Typed members as separate HP: violates the single authoritative life integer.
- Per-member firing loops or bonus projectiles: breaks Amendment 14's cadence and the event and pool caps.
- Recruit by shooting a target: puts recruiting into the nearest-target arbitration with hordes and the boss. A distance-plane crossing is already once-only and replay-safe.
- Persist named members through defeat or replay: forbidden by #230.
- Hard-code Oaxaca types in run state: contradicts the per-level extension.

## Consequences
- Child tasks in the description of the PR that carries this record order the implementation; the first slice code is #232.
- Reserved attacks need #233's review; no code on prose names.
- Thresholds, schedule times, cycle fairness and the slowing of boss and unlock progress while mobs are present are UNVERIFIED design defaults. Reachability needs a witness test; balance needs the skeptic.
- Cultural authenticity, rooster and vaca local forms, Studio readability and phone performance are UNVERIFIED (see docs/roster-cultural-brief.md).

**Rule:** The named list never exceeds the roster size or `crowdTotal`; roster membership changes only by a server-resolved station crossing or a total change.
