# 0002: Spectator waves attack until converted; separate parade HP

**Date:** 2026-10-23  **Status:** accepted

## Context
Spec §3/§4 had spectator clusters standing still, with no penalty for missing them, no death (§5) and a run that always completes (§9). The owner wants the game to feel very similar to Mob Control. Offered three options (waves with no penalty, waves that cost followers, static clusters), the owner first chose waves with no penalty ("ok 1"), then refined the design on the same day: incoming spectators are attackers until converted; converted ones join; unconverted ones that reach the parade reduce parade HP; crowd size and HP are separate; zero HP ends the run; hits stay playful but impactful; balance so the player has to react.

## Decision
Adopt Amendment 1 in `docs/Calenda-Prototype-Spec.md`: clusters walk toward the parade on deterministic paths; an unconverted cluster that reaches the parade deals its `attackDamage` to parade HP once; `crowdTotal` is untouched by attacks; at zero HP the run ends as defeated; reaching the plaza with HP left completes the run. This supersedes the spec's no-penalty, no-death and always-completes statements, and supersedes the first (no-penalty) form of this decision.

Defaults chosen by the PM where the owner gave none (all in Config, all tunable, flagged for the owner): no HP regeneration; one attack per cluster; score = crowd total at the end of the run; session best counts completed runs only; hearts and snacks are visual variants of the one-hit shot.

**Rule:** None

## Alternatives considered
- Waves with no penalty (the owner's first pick): less pressure, little like the reference. Superseded by the owner.
- Attacks that cost followers: would couple HP to crowd math and break the single-total clarity the spec protects. The owner chose a separate HP.
- Static clusters: simplest, least like the reference.

## Consequences
Run state gains HP and a defeat outcome (#6); cluster position is a function of time (#7, #9, #12); there is a new HP/defeat issue; the HUD, results and finale handle defeat (#16); the scripted-run test needs a no-input run and a competent run (#17). Defeat adds a way to fail, which raises the risk that the first minute feels punishing: revisit damage and wave size if playtests show early defeats. Both the spec's "no penalty" tone and the charter's success criteria still hold for crowd math; the charter's hard constraints are unaffected.
