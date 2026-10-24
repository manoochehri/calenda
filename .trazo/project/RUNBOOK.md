# Runbook

**Status:** current

## Local
From a fresh clone or worktree, with [Rokit](https://github.com/rojo-rbx/rokit) installed (`~/.rokit/bin` on `PATH`):

```bash
make setup   # trusts and installs the pinned tools in rokit.toml (rojo, lune, stylua, selene)
make test    # stylua --check, selene, Lune tests (tests/run.luau), then rojo build -> build/Calenda.rbxl
```

The Lune test runner (`tests/run.luau`) reads `tests/` by relative path, so run it from the repo root (`make test-unit` does this).
Any `rokit.toml` version bump needs security review: `rokit trust` is per repo, not per version, so a compromised future release of a trusted repo would be accepted.

Other targets: `make lint`, `make fmt` (applies stylua), `make build`, `make scan` (secret-pattern grep).
`build/` is gitignored. Open `build/Calenda.rbxl` in Studio, or run `rojo serve` for live sync.

## Studio (manual)
Open an EMPTY place (File > New > no Baseplate template; a Baseplate is coplanar with the street and hides the backdrop), then from the repo root: `~/.rokit/bin/rojo serve default.project.json`, connect with the Rojo plugin, Play Solo.
Note: the lead musician is the player's own Roblox avatar (ADR 0003): the server leaves `Players.CharacterAutoLoads` at its default, and the client (`src/client/LeadAvatar`) anchors the local character, holds it at the server-driven lead position and plays the walk; the primitive block in `src/client/CrowdView` is only a fallback when no character loads for 3 s. The server never reads the character (the lead hitbox is the fixed Crossing hitbox).

Run start (issue #72): the server creates each player's run READY but paused at join (no ticking, no log, no events; State with `phase = "ready"` goes out once a second) and begins it only on the client's `Start` request (no payload; every argument is ignored). Until the title screen lands (#72 part 2), `Main.client.luau` sends `Start` automatically on the first ready State. A client that never sends `Start` costs one idle session, dropped on `PlayerRemoving`. In Studio, if the street never moves, check the Output for the first State and that `Start` fired.

## Parallel work (git worktrees)
```bash
git fetch origin && git worktree add .worktrees/<name> -b <name> origin/main
git worktree list
git worktree remove .worktrees/<name> && git branch -D <name>
git worktree prune
```

## Secrets
TODO: where they live and how the owner enters them. Never in git.

## Deploy
TODO

## Roll back
TODO

## Recurring
TODO

## Teardown
TODO
