# Calenda

A Roblox prototype (Luau, synced with Rojo). A parade of followers walks an Oaxacan street;
the player leads it, converts crowds, and picks up gates and shots along the way. The game
design is in [docs/Calenda-Prototype-Spec.md](docs/Calenda-Prototype-Spec.md).

## Prerequisites

- [Rokit](https://github.com/rojo-rbx/rokit) on your `PATH` (or at `~/.rokit/bin/rokit`). It
  installs the tools pinned in `rokit.toml`: Rojo 7.7.1, Lune 0.11.1, StyLua 2.6.0 and Selene 0.32.0.
- macOS or Linux with `make`, `git` and `curl`.
- Roblox Studio with the Rojo plugin, for the in-engine check and for playing the place.

## Build and test

From a fresh clone or a git worktree (see [.trazo/project/RUNBOOK.md](.trazo/project/RUNBOOK.md)):

```bash
make setup   # trust and install the pinned toolchain (Rokit)
make test    # stylua --check, selene, Lune tests (tests/run.luau), then rojo build
```

`make test` ends with `OK: built build/Calenda.rbxl` when everything passes. It takes a few
seconds once the tools are installed.

| Command | Does |
|---|---|
| `make setup` | Trusts and installs the pinned tools from `rokit.toml` |
| `make lint` | StyLua check and Selene on `src` and `tests` |
| `make fmt` | Applies StyLua formatting |
| `make test-unit` | Lune tests only (run from the repo root) |
| `make build` | Writes the place file to `build/Calenda.rbxl` |
| `make scan` | Greps tracked files for obvious credential patterns |
| `make ladder` | Headless balance report (about 5,000 runs). Not part of `make test` |

CI (`.github/workflows/ci.yml`) runs `make setup` and `make test` on every pull request and on
pushes to `main`, uploads `build/Calenda.rbxl` as the `Calenda.rbxl` artifact (kept 14 days), and
runs gitleaks over the full git history. The tools are pinned by version in `rokit.toml`, and CI checks the
sha256 of its Rokit and gitleaks downloads.

## Open the game in Studio

Use either route. Both need an **empty** place: in Studio choose File > New and do not use the
Baseplate template, because a Baseplate is coplanar with the street and hides the backdrop.

1. **Live sync (recommended while editing).** From the repo root run
   `~/.rokit/bin/rojo serve default.project.json`, connect with the Rojo plugin in Studio, and press
   Play Solo.
2. **Built place.** Run `make build`, open `build/Calenda.rbxl` in Studio and press Play. Or download
   the `Calenda.rbxl` artifact from a green CI run.

The server creates each run paused. Press **Jugar** on the title screen to start the run and the
music.

### Controls

- Keyboard: `A` / `D` or the left and right arrow keys steer the lead.
- Touch: drag horizontally to steer.
- **♫ Música: Sí/No** mutes only the music. Gameplay stays fully usable muted.
- Replay is offered on the results screen.

### Owner in-engine check

This is a playtest for you, not a merge gate. Each feature's detailed checklist is in `docs/`
(see Known issues).

1. Open an empty place, run `rojo serve` from the repo root, connect the Rojo plugin, press Play Solo.
2. Confirm the title screen appears and the run stays at time 0 until you press **Jugar**.
3. Steer with `A` / `D` (or drag on touch). The parade follows the street and the camera stays behind it.
4. Take a gate and a spectator cluster. Confirm the total updates and the sections rise in steps.
5. Confirm the music starts on **Jugar**, loops, and the **♫** button mutes and unmutes it.
6. Let the run end, check the results screen, and press Replay. Confirm the new run starts clean.
7. Note anything odd (frame drops, figures stuck, text cut off) and the device it happened on.

## Layout

| Path | What lives there |
|---|---|
| `src/shared` | Pure Luau logic and data, with no Roblox API calls. Tested by Lune in `tests/`. |
| `src/server` | Server script: run state, remotes, replication. |
| `src/client` | Client scripts: world, HUD, input, audio, figures, camera. |
| `tests/` | Lune tests (`*.test.luau`) and the runner `tests/run.luau`. |
| `docs/` | Game spec, audio setup, art brief, Studio checklists. |

## Tuning guide

Gameplay numbers are in [src/shared/Config.luau](src/shared/Config.luau). Audio numbers are in
[src/shared/AudioTuning.luau](src/shared/AudioTuning.luau) (exposed as `Config.audio`). Mob caps are
in [src/shared/QualityConfig.luau](src/shared/QualityConfig.luau).

To tune: edit the value, run `make test`, then check the change in Studio. `Config.validate`
rejects bad values at test time, so a broken edit fails `make test` rather than the game.

Each value is tagged `[spec]` (given by the spec, section shown), `[default]` (a tuning
placeholder chosen by the engineer) or `[provisional]` (waiting on a decision or measurement).
Speeds are studs per second, distances are studs, times are seconds, counts are whole numbers.

### Core loop

| Key | Default | Unit | Tag | Meaning |
|---|---|---|---|---|
| `sectionSize` | 50 | followers | [spec s5] | Followers per section. Positive integer. |
| `startingTotal` | 10 | followers | [spec s5] | Followers at the start of a run. Non-negative integer. |
| `obstacleLoss` | 10 | followers | [spec s9] | Followers lost when the parade hits an obstacle. |
| `speed` | 14.4 | studs/s | [default] | Forward speed of the parade. Must be positive. |
| `giftEveryNthShot` | 4 | shots | [spec s4] | Every Nth shot is a gift once a dancer section exists. |
| `finaleThresholds` | 50, 150, 300 | followers | [spec s9, provisional] | Strictly ascending. Totals that trigger finale stages. |
| `musicLayerSections` | 0, 1, 3, 6 | sections | [spec s10] | Strictly ascending. Section counts that gate each music stem. |

### Balance (provisional)

These values are first guesses. ADR 0007 says they are unmeasured until `make ladder` is re-run.

| Key | Default | Unit | Tag | Meaning |
|---|---|---|---|---|
| `attackSharePercent` | 10 | % of parade | [default, provisional] | Followers lost when an unconverted horde hits (floored). Whole number 1 to 100. |
| `minShareLoss` | 1 | followers | [default, provisional] | Minimum loss from a share-based hit. Positive integer. |
| `hazards.tomatoSharePercent` | 10 | % of parade | [default, provisional] | Followers lost when an unblocked tomato hits the lead. Whole number 1 to 100. |

### Clusters and gates

| Key | Default | Unit | Tag | Meaning |
|---|---|---|---|---|
| `clusterTypes.small` | hits 3, reward 5 | hits, followers | [spec s4] | Small spectator cluster. Positive integers. |
| `clusterTypes.large` | hits 8, reward 15 | hits, followers | [spec s4] | Large spectator cluster. Positive integers. |
| `gateOps` | `{add, 20}`, `{multiply, 2}` | op | [default] | Non-empty list of `{kind, value}`. `kind` is `"add"` or `"multiply"`; `value` is a positive integer; a `multiply` value must be at least 2. The spec gives only the forms `+N` and `xN`. |

### Firing (`firing`)

Firing is continuous: one shot every `1 / rate` seconds, hit or miss (ADR 0004). The rate is
`min(cap, base + perSection * sectionCount)` shots per second.

| Key | Default | Unit | Tag | Meaning |
|---|---|---|---|---|
| `firing.base` | 6 | shots/s | [default] (spec s4 had 3) | Rate with no sections. Positive integer. |
| `firing.cap` | 20 | shots/s | [default] (spec s4 had 12) | Maximum rate. At least `base` and at most 30 (the 30 Hz server tick). |
| `firing.perSection` | 1 | shots/s per section | [spec s4] | Rate added per section. Positive integer. |
| `firing.range` | 60 | studs | [default] | How far along the street a shot reaches from the lead. |

### Spectators (`spectators`)

| Key | Default | Unit | Tag | Meaning |
|---|---|---|---|---|
| `spectators.approachSpeed` | 20 | studs/s | [default] | Speed at which a spectator mob charges toward the parade. Was 6 before issue #65. |
| `spectators.centerTolerance` | 3 | studs | [default] | Horizontal offset at or below which a spectator counts as centered. Non-negative. |

### Visual budget (`visualBudget`)

| Key | Default | Unit | Tag | Meaning |
|---|---|---|---|---|
| `visualBudget.sectionRepresentatives` | 6 | figures | [spec s8] | Figures drawn per section. Positive integer. |
| `visualBudget.looseAvatars` | 24 | figures | [spec s8] | Free-standing follower avatars drawn at once. Positive integer. |
| `visualBudget.cameraPullback` | start 1.0, max 1.4, sectionsToMax 40 | multiplier | [default] | Camera distance multiplier, rising linearly with sections and saturating at `sectionsToMax`. |
| `visualBudget.formationDensity` | start 0.5, max 1.0, sectionsToMax 40 | 0 to 1 | [default] | Formation compactness, same curve shape. |

A curve needs `start >= 0`, `max >= start`, and a positive integer `sectionsToMax`.

### Durations (`durations`)

| Key | Default | Unit | Tag | Meaning |
|---|---|---|---|---|
| `durations.assemblySeconds` | 0.8 | s | [spec s7] | Length of the assembly animation for a large jump. |
| `durations.dispersalSeconds` | 0.5 | s | [default] | Length of the dispersal animation. The spec says only "brief". |

### Music (`music`)

| Key | Default | Unit | Tag | Meaning |
|---|---|---|---|---|
| `music.bpm` | 120 | beats/min | [default] | Tempo of the loop. The spec gives no number. |
| `music.beatsPerBar` | 4 | beats | [default] | 4/4. Positive integer. |
| `music.fadeBars` | 1 | bars | [default] | Crossfade length. Positive integer. |
| `music.maxSources` | 4 | sources | [spec s10] | Simultaneous stems, 1 to 4. Values above 4 are rejected. |
| `music.stemSoundIds` | four `""` | asset strings | [default] | One entry per `musicLayerSections` entry. Empty means no stem. |
| `music.trackSoundId` | `"1838904620"` | asset id | [default] | Single full-mix loop. Empty or nil turns it off. See [docs/audio-setup.md](docs/audio-setup.md). |

Audio mixing (`Config.audio`, from `AudioTuning.luau`) holds the intensity curve (`refTotal`,
`fullTotal`, `fullSections`, `sectionWeight`, `riseRate`, `fallRate`, `volumeSlew`), the master and
duck levels, the four-stem layer curves, the single-track effect ranges, and the SFX pool, volume,
pitch and cooldown tables. Every value there is a `[default]`; each line carries its own comment.

Sound effect asset ids are `sfx.<slot>` in `Config.luau`. All slots are empty, so the game is
silent apart from the music loop. See [docs/audio-setup.md](docs/audio-setup.md) for the slot list
and how to add ids.

### Debug switches (`debug`)

All default to off. Leave them off for a normal game.

| Key | Default | Meaning |
|---|---|---|
| `debug.startupTiming` | false | Opt-in local startup trace. |
| `debug.freezeCamera` | false | Hold the camera at its first pose (issue #85 A/B). |
| `debug.noShadows` | false | Turn global shadows off (issue #85 A/B). |
| `debug.rawExtrapolation` | false | The pre-#85 snap-to-State lead path. |
| `debug.quality` | nil | nil is automatic (medium on touch, high otherwise); or `"low"`, `"medium"`, `"high"`. The player attribute `CalendaQuality` overrides it in Studio. |

## Known issues

- **The shipped place runs one fixed layout.** The server starts every run with `DebugLayout`
  (`src/server/RunServer.server.luau`). The three authored layouts in `src/shared/Layouts.luau` are
  covered by `tests/issue23_layouts.test.luau`, but nothing in `src` calls `Layouts.select`, so no
  seed picks one at runtime.
- **Nothing in-engine has been verified by an agent.** Presentation, input feel, audio and phone
  performance are UNVERIFIED. The checklists are: [mob waves](docs/mob-waves-studio-checklist.md),
  [hazards](docs/hazard-studio-checklist.md), [dancers](docs/dance-studio-checklist.md),
  [opening route](docs/opening-route-studio-checklist.md), [background HUD](docs/background-hud-studio-checklist.md),
  [Rey](docs/rey-studio-checklist.md), [stutter](docs/stutter-studio-checklist.md),
  [art brief](docs/art-brief-level-1.md) and [audio](docs/audio-setup.md).
- **The music track is UNVERIFIED.** Asset `1838904620` is a provisional bed (ADR 0005). Whether
  this experience may load it, and whether it fits the game, are checked only in Studio. Do not
  describe it as an Oaxacan calenda recording.
- **Sound effects are silent.** Every `sfx` and stem id is empty. Owner-supplied, licensed audio is
  issue #30.
- **Balance is provisional.** `attackSharePercent`, `minShareLoss` and `hazards.tomatoSharePercent`
  are first guesses. The floor rounding of share losses is an engineer's design call, not
  playtested (ADR 0007). Run `make ladder` before changing them on the strength of a number.
- **Mobile performance is not measured.** The mob caps in `QualityConfig.luau` are `[default]`
  values. The spec asks for a sustained 30 FPS check on a named lower-end phone; no such result exists yet.
- **Studio behaviour of the audio routing is UNVERIFIED.** The `SoundGroup` placement and how the
  effects sound are not confirmed in the engine (see [docs/audio-setup.md](docs/audio-setup.md)).
