# 0001: Luau + Rojo, with crowd logic as pure testable modules

**Date:** 2026-10-23  **Status:** accepted

## Context
The owner tests in Roblox Studio via Rojo, but agents cannot run Studio. The mount-time contract needs a one-command, hermetic build/test. The spec (§11) already requires run state and crowd arithmetic to be separate from presentation, with the server authoritative.

## Decision
- Luau source synced with Rojo; toolchain pinned in `rokit.toml` (rojo, lune, stylua, selene).
- All gameplay rules (crowd arithmetic, gate/cluster/obstacle resolution, firing-rate curve, visual-budget allocation, run recording, layout generation) live in pure Luau modules with no `game`/`Instance` access, in `src/shared/`, and are unit-tested under Lune. `make test` runs lint, format check, Lune tests and `rojo build`.
- Presentation code (camera, input, models, UI, audio) cannot be tested by agents; each such issue states the exact manual check for the owner in the PR and is verified by reading code plus `rojo build`, marked UNVERIFIED in-engine. Owner testing is never a merge gate (owner instruction 2026-10-23).
- Placeholder art is built from primitive Parts; no asset IDs are invented.

**Rule:** None

## Alternatives considered
- TestEZ/Jest inside Studio: agents cannot run it, so it would give no evidence at merge time.
- No tests, Studio-only: violates "tests are evidence".

## Consequences
Logic bugs get caught in CI; engine behavior (physics feel, performance, visuals) stays UNVERIFIED until the owner plays it. Revisit if Lune cannot load a module because of a Roblox-only API.
