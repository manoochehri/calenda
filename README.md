# Calenda

A Roblox prototype (Luau, synced with Rojo). A parade of followers walks an Oaxacan street;
the player leads it, converts crowds, and picks up gates and shots along the way. The game
design is in [docs/Calenda-Prototype-Spec.md](docs/Calenda-Prototype-Spec.md).

## Prerequisites

- [Rokit](https://github.com/rojo-rbx/rokit) on your `PATH` (`~/.rokit/bin`). It installs the
  tools pinned in `rokit.toml`: Rojo 7.7.1, Lune 0.11.1, StyLua 2.6.0 and Selene 0.32.0.
- macOS or Linux with `make`, `git` and `curl`.
- Roblox Studio, for the in-engine check and for playing the place.

## Build and test

From a fresh clone or a `git worktree` (see [.trazo/project/RUNBOOK.md](.trazo/project/RUNBOOK.md)):

```bash
make setup   # trust and install the pinned toolchain (Rokit)
make test    # stylua --check, selene, Lune tests (tests/run.luau), then rojo build
```

Other targets:

| Command | Does |
|---|---|
| `make lint` | StyLua check and Selene on `src` and `tests` |
| `make fmt` | Applies StyLua formatting |
| `make test-unit` | Lune tests only (run from the repo root) |
| `make build` | Writes the place file to `build/Calenda.rbxl` |
| `make scan` | Greps tracked files for obvious credential patterns |

`make test` must print `OK: built build/Calenda.rbxl` at the end. CI (`.github/workflows/ci.yml`)
runs `make setup` and `make test` on every pull request and uploads `build/Calenda.rbxl` as the
`Calenda.rbxl` artifact (kept 14 days). CI also runs gitleaks over the full history.

## Open the game in Studio

The place file is built from source, so you can use either route.

1. **Live sync (recommended while editing).** Open an empty place in Studio (File > New, no
   Baseplate template: a Baseplate is coplanar with the street and hides the backdrop). From the
   repo root run `~/.rokit/bin/rojo serve default.project.json`, then connect with the Rojo plugin
   and press Play Solo.
2. **Built place.** Run `make build`, then open `build/Calenda.rbxl` in Studio and press Play.
   Or download the `Calenda.rbxl` artifact from a green CI run.

The server creates each run paused. Press **Jugar** on the title screen to start it.

## Layout

| Path | What lives there |
|---|---|
| `src/shared` | Pure Luau logic and data, with no Roblox API calls. Tested by Lune in `tests/`. |
| `src/server` | Server script: run state, remotes, replication. |
| `src/client` | Client scripts: world, HUD, input, audio, figures, camera. |
| `tests/` | Lune tests (`*.test.luau`) and the runner `tests/run.luau`. |
| `docs/` | Game spec, audio setup, art brief, Studio checklists. |

## Tuning guide

Every gameplay number is in [src/shared/Config.luau](src/shared/Config.luau). Audio numbers are in
[src/shared/AudioTuning.luau](src/shared/AudioTuning.luau) (exposed as `Config.audio`). Edit the
value, run `make test` (the `validate` function in `Config.luau` rejects bad values at test time),
then check the change in Studio.

Each value is marked `[spec]` (given by the spec, section number shown) or `[default]` (a tuning
placeholder chosen by the engineer). Speeds are studs per second; distances are studs; times are
seconds. Counts are whole numbers unless noted.

### Core loop

| Key | Default | Unit | Source | Meaning |
|---|---|---|---|---|
| `sectionSize` | 50 | count | [spec s5] | Followers per section (must be a positive integer). |
| `startingTotal` | 10 | count | [spec s5] | Followers at the start of a run (non-negative integer). |
| `hp.max` | 100 | HP | [default] | Parade HP at the start. No regeneration. |
| `obstacleLoss` | 10 | count | [spec s9] | Followers lost when hitting an obstacle. |
| `speed` | 14.4 | studs/s | [default] | Forward speed of the parade. |
| `giftEveryNthShot` | 4 | shots | [spec s4] | Every Nth shot is a gift once a dancer section exists. |
| `finaleThresholds` | 50, 150, 300 | followers | [spec s9, provisional] | Strictly ascending. Follower counts that trigger finale stages. |
| `musicLayerSections` | 0, 1, 3, 6 | sections | [spec s10] | Strictly ascending. Section counts that gate each music stem. |

### Clusters (`clusterTypes.small`, `clusterTypes.large`)

Each cluster has `hits`, `reward`, and `attackDamage` (all positive integers).

| Cluster | `hits` | `reward` | `attackDamage` | Source |
|---|---|---|---|---|
| small | 3 | 5 | 5 | hits and reward [spec s4]; attack [default] |
| large | 8 | 15 | 12 | hits and reward [spec s4]; attack [default] |

### Gates (`gateOps`)

A non-empty list of `{ kind, value }`. `kind` is `"add"` or `"multiply"`; `value` is a positive
integer. A `multiply` value must be at least 2. Defaults: `{ add, 20 }` and `{ multiply, 2 }`
[default], since the spec only gives the forms `+N` and `xN` (s6).

### Firing (`firing`)

Firing is continuous: one shot every `1 / rate` seconds, hit or miss. The rate is
`min(cap, base + perSection * sectionCount)` shots per second (ADR 0004).

| Key | Default | Unit | Source | Meaning |
|---|---|---|---|---|
| `firing.base` | 6 | shots/s | [default] (spec s4 had 3) | Rate with no sections. |
| `firing.cap` | 20 | shots/s | [default] (spec s4 had 12) | Maximum rate. Must be at least `base` and at most 30 (the 30 Hz server tick). |
| `firing.perSection` | 1 | shots/s per section | [spec s4] | Rate added per section. |
| `firing.range` | 60 | studs | [default] | How far along the street a shot reaches from the lead. |

### Spectators (`spectators`)

| Key | Default | Unit | Source | Meaning |
|---|---|---|---|---|
| `spectators.approachSpeed` | 20 | studs/s | [default] | Speed at which a spectator mob charges toward the parade. |
| `spectators.centerTolerance` | 3 | studs | [default] | Horizontal offset at or below which a spectator counts as centered. Non-negative. |

### Visual budget (`visualBudget`)

| Key | Default | Unit | Source | Meaning |
|---|---|---|---|---|
| `visualBudget.sectionRepresentatives` | 6 | figures | [spec s8] | Figures drawn per section. |
| `visualBudget.looseAvatars` | 24 | figures | [spec s8] | Free-standing avatars drawn at once. |
| `visualBudget.cameraPullback` | start 1.0, max 1.4, sectionsToMax 40 | multiplier | [default] | Camera distance multiplier, rising linearly with sections and saturating at `sectionsToMax`. |
| `visualBudget.formationDensity` | start 0.5, max 1.0, sectionsToMax 40 | 0 to 1 | [default] | Formation compactness, same curve shape. |

A curve needs `start >= 0`, `max >= start`, and a positive integer `sectionsToMax`.

### Durations (`durations`)

| Key | Default | Unit | Source |
|---|---|---|---|
| `durations.assemblySeconds` | 0.8 | s | [spec s7] |
| `durations.dispersalSeconds` | 0.5 | s | [default] (spec s5 says only "brief") |

### Music (`music`)

| Key | Default | Unit | Source | Meaning |
|---|---|---|---|---|
| `music.bpm` | 120 | beats/min | [default] | Tempo of the loop. The spec gives no number. |
| `music.beatsPerBar` | 4 | beats | [default] | 4/4. Positive integer. |
| `music.fadeBars` | 1 | bars | [default] | Crossfade length. Positive integer. |
| `music.maxSources` | 4 | sources | [spec s10] | Simultaneous stems, 1 to 4. Values above 4 are rejected. |
| `music.stemSoundIds` | four `""` | asset strings | [default] | One entry per `musicLayerSections` entry. Empty means no stem. |
| `music.trackSoundId` | `"1838904620"` | asset id | [default] | Single full-mix loop. Empty or nil turns it off. See [docs/audio-setup.md](docs/audio-setup.md). |

The music mixer also reads `Config.audio` (see below). Its intensity and layer curves are
[default] placeholders.

### Audio (`Config.audio`, from `AudioTuning.luau`)

All values are [default] unless the comment says otherwise. Volumes are multipliers from 0 to 1.

- Intensity from the crowd: `refTotal` (10), `fullTotal` (10000), `fullSections` (200),
  `sectionWeight` (0.25), `riseRate` (0.2 per s), `fallRate` (0.4 per s), `volumeSlew` (1.5 per s).
- Music master: `masterMin` (0.6), `masterMax` (1.0), `defeatDuck` (0.2).
- Four-stem mode: `layerFloor`, `layerStart`, `layerWidth`.
- Single-track effects under `audio.effects`: reverb, chorus, EQ and compressor ranges. Each
  property's documented range is in [docs/audio-setup.md](docs/audio-setup.md).
- Sound effects under `audio.sfx`: `maxConcurrent` (8), volume and pitch ranges, `maxVolume`
  (0.9), `crowdLoopVolume` (0.35), per-slot `volumes` and `cooldowns` (seconds).

### Sound effects (`sfx`)

A map from slot to a sound asset id string. Every slot is empty (silent) today. Never invent an
id: the owner supplies licensed or original audio (issue #30). See [docs/audio-setup.md](docs/audio-setup.md).

### Debug switches (`debug`)

These default to normal play. Leave them alone for a release build.

| Key | Default | Effect |
|---|---|---|
| `debug.startupTiming` | `false` | Opt-in local startup trace. No Output logging unless enabled. |
| `debug.freezeCamera` | `false` | Holds the camera at its first pose (A/B check for flicker, issue #85). |
| `debug.noShadows` | `false` | Turns off `Lighting.GlobalShadows` (A/B check, issue #85). |
| `debug.rawExtrapolation` | `false` | Uses the pre-#85 snap-to-State lead path (A/B check). |
| `debug.quality` | `nil` | `nil` is automatic (medium on touch, high otherwise). Or `"low"`, `"medium"`, `"high"` to force the mob quality (issue #65). |

## Known issues

Items below are not verified in Roblox Studio or on devices. The source file for each is named.
The owner's in-engine check (below) covers them.

- **Music fit and access.** The track `1838904620` (APMOfficial, "Mexican Nostalgia") is not yet
  heard in Studio, and its playback permission from this experience is unverified.
  (`src/shared/Config.luau`, `docs/audio-setup.md`)
- **No sound effects.** Every `sfx` slot is empty, so the game is silent apart from the music.
- **Look and layout of the street, figures, and effects.** Marked `IN-ENGINE BEHAVIOUR IS
  UNVERIFIED` in: `src/server/RunServer.server.luau`, `src/client/OaxacaStreet.luau`,
  `src/client/Backdrop.luau`, `src/client/LeadAvatar.luau` (the Roblox character's animation
  names are unverified), `src/client/FigureParts.luau`, `src/client/PuppetFigure.luau`,
  `src/client/DancerFigure.luau`, `src/client/ClusterView.luau`, `src/client/GateView.luau`,
  `src/client/ObstacleView.luau`, `src/client/SectionsView.luau`, `src/client/RunHud.luau`,
  `src/client/EndFlow.luau`, `src/client/Bits.luau`, `src/client/InputController.luau`,
  `src/client/MusicPlayer.luau`, `src/client/SfxPlayer.luau`.
- **Portal and shot look.** `src/shared/PortalFx.luau`, `src/shared/PortalGeometry.luau`
  (the FredokaOne digit metrics are unverified), `src/shared/ShotLook.luau`.
- **Camera and screen.** `src/shared/CameraRig.luau` (vertical framing on wider aspect ratios)
  and `src/shared/ScreenLayout.luau` (layout on real devices).
- **Gui distance.** `OaxacaStreet.luau` sets `SurfaceGui.MaxDistance`; the property is documented
  but its effect in engine is unverified.
- **Lighting.** The `Atmosphere` and `Haze` settings under `Lighting` are unverified.
- **Audio intensity range.** `src/shared/AudioIntensity.luau` (one range is not documented).
- **Run start gating (issue #72).** Confirm in Studio that the run stays at time 0 until **Jugar**.

## Owner's in-engine check

1. Build or sync the place (see "Open the game in Studio").
2. Play Solo. Confirm the title screen shows and the run stays at time 0 until you press **Jugar**.
3. Play a full run in landscape. Check the street, figures, HUD, and the end screen.
4. Check music: it starts on **Jugar**, and the ♫ Música control mutes only music.
5. Work through the matching checklists in `docs/` (`opening-route-studio-checklist.md`,
   `rey-studio-checklist.md`, `dance-studio-checklist.md`, `stutter-studio-checklist.md`).
6. Record anything wrong against the issue it belongs to.

The longer Studio procedure is in [.trazo/project/RUNBOOK.md](.trazo/project/RUNBOOK.md).

## Status of the seeded layouts

The three authored layouts under recorded seeds (issue #23) are in an open pull request and are
not on `main` yet. This README describes `main`. Update the Layout and Known issues sections
after that pull request merges.
