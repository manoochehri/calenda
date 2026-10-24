# 0002: Spectator clusters arrive in waves

**Date:** 2026-10-23  **Status:** accepted

## Context
Spec §3/§4 had spectator clusters standing still on the sidewalks. The owner wants the game to feel very similar to Mob Control, where groups come toward the player. Three options were put to the owner on 2026-10-23: (1) waves stream toward the parade with no penalty, (2) waves cost followers when missed, (3) keep static clusters. The owner chose option 1 ("ok 1").

## Decision
Clusters spawn ahead of the lead and walk toward the parade on deterministic paths (see Amendment 1 in `docs/Calenda-Prototype-Spec.md`). Missing a wave has no penalty. Crowd math, gates, obstacle and scoring are unchanged.

**Rule:** None

## Alternatives considered
- Waves that cost followers when missed: contradicts the spec's no-penalty rule and adds a second way to lose followers, which hurts math readability.
- Static clusters: simplest, but least like the reference.

## Consequences
Cluster position becomes a function of time, so the level format (#7), targeting (#9), cluster visuals (#12) and the scripted-run test (#17) all change; Config gains `spectators.approachSpeed`. Revisit if playtests show waves make the street unreadable or recruiting feels rushed.
