# Runbook

**Status:** current

## Local
From a fresh clone or worktree, with [Rokit](https://github.com/rojo-rbx/rokit) installed (`~/.rokit/bin` on `PATH`):

```bash
make setup   # trusts and installs the pinned tools in rokit.toml (rojo, lune, stylua, selene)
make test    # stylua --check, selene, Lune tests (tests/run.luau), then rojo build -> build/Calenda.rbxl
```

Other targets: `make lint`, `make fmt` (applies stylua), `make build`, `make scan` (secret-pattern grep).
`build/` is gitignored. Open `build/Calenda.rbxl` in Studio, or run `rojo serve` for live sync.

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
