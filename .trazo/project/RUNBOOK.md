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
Note: `RunServer` sets `Players.CharacterAutoLoads = false` (server only, nothing replicated): no Roblox character spawns, the lead is drawn by the client (`src/client/CrowdView`). A feature that needs a character must revisit this.

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
