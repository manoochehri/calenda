# Audio setup (issues #62, #21, #30)

The game ships silent. Every sound id in `src/shared/Config.luau` is an empty string, and with an
empty id nothing is created, nothing plays and nothing errors. You supply the audio.

## Getting an id

1. In Studio open Toolbox > Audio, pick a sound, right-click it and choose Copy Asset ID.
2. Paste the number (or the full `rbxassetid://123` text) between the quotes in Config.

Licensing: use only audio you made, or audio whose license allows use in your game. Check the
creator and license in the Toolbox before publishing. Attribution and licensing review is owner
issue #30.

## Where to paste

In `src/shared/Config.luau`:

- `music.trackSoundId`: ONE looping music track (single-track mode). It gets bigger as the parade
  grows (reverb, chorus, equalizer, compressor on a SoundGroup).
- `music.stemSoundIds`: four stems in the order percussion, brass, ensemble, crowd accents. If any
  stem id is set, stem mode is used and `trackSoundId` is ignored. Stems grow with the parade too.
- `sfx.<slot>`: `gatePop`, `convert`, `sparkle`, `shotLaunch`, `shotImpact`, `obstacleThud`,
  `attackBonk`, `hpHit`, `sectionRise`, `finalePeak`, `defeatBreakup`, `replayClick`, and
  `crowdLoop` (a looping crowd ambience whose volume follows the follower count).

Any slot you leave empty stays silent. Volumes, cooldowns and the intensity curve are in
`src/shared/AudioTuning.luau` (shown as `Config.audio`).

## Loop length for stems

All four stems must be the same length and a whole number of bars at 120 bpm in 4/4 (one bar is
2 seconds, so 8, 16 or 32 seconds). Bar boundaries are where layers fade in, so a loop that is not
a whole number of bars drifts. If your tempo differs, change `music.bpm` and `music.beatsPerBar`.

## Testing locally without committing

1. Paste ids into your working copy of Config.luau, run `rojo serve` and test in Studio.
2. Before committing, restore the file: `git checkout src/shared/Config.luau`. A test
   (`audiointensity.test.luau`) fails if any id is non-empty, so a committed id is caught.
   When you want ids in the repo for real, change that test in the same PR.

## What the code sets (checked against the Roblox Creator Docs)

Source: github.com/Roblox/creator-docs, `content/en-us/reference/engine/classes/*.yaml`, read 2026-10-24.

- ReverbSoundEffect: DecayTime 0.1 to 20, DryLevel -80 to 10, WetLevel -80 to 10.
- ChorusSoundEffect: Depth 0 to 1, Mix 0 to 1, Rate 0 to 20.
- EqualizerSoundEffect: LowGain, MidGain, HighGain, each -80 to 10 dB.
- CompressorSoundEffect: Attack 0.1 to 1 s, Release 0 to 5 s, Threshold -80 to 0 dB, GainMakeup -30 to
  30 dB. Ratio has no documented range, so the code does not touch it (UNVERIFIED).
- UNVERIFIED: that SoundGroup may be parented to SoundService with Sounds assigned through
  `Sound.SoundGroup`, and how the effects sound. Both need a Studio check (below).

## Studio checklist (UNVERIFIED in engine)

- Empty ids: play a run. No sound, no errors or warnings in Output.
- Single track: paste one id in `music.trackSoundId`. It fades in and loops. Grow the crowd with
  gates: the track gets fuller (more reverb, brighter) without clicks or clipping.
- Stems: paste four ids. Layers join on bars and keep growing with the crowd. At most 4 Sounds under
  `SoundService.CalendaMusicGroup`.
- SFX: paste ids for a few slots. Each plays on its event, pitch varies slightly, bangs are louder
  with a big crowd, a flood does not stack (check `SoundService.CalendaSfx` never has more than 8 playing).
- Finale: the music swells to its top. Defeat: the music ducks. Replay: music restarts quiet.
- Crowd loop: quiet with few followers, louder with many.
