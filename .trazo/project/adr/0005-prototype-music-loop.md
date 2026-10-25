# 0005: Use one free Creator Store music loop for the prototype

**Date:** 2026-10-24  **Status:** accepted

## Context
The prototype needs music, but no original stems have been supplied. The charter forbids paid assets, and Roblox provides a free-to-use Creator Store for audio used in games. The owner asked the PM to choose a track.

## Decision
For the prototype, use **“Mexican Nostalgia” by APMOfficial** as one full-mix loop, Roblox Creator Store asset `1838904620`. Keep the prototype to one music source; do not wait for or invent separate stems. Roblox Creator Hub documents Creator Store audio as free-to-use in games. The track is listed by APMOfficial, and its album catalog describes the album as a traditional Mexican mariachi band.

The track's cultural and tonal fit for this specific game is **UNVERIFIED** until listened to in Studio. Do not label it as Oaxacan or as a calenda recording. Keep playback optional and the game playable muted.

This supersedes the synchronized-stems requirement in spec §10 and issue #21 for the prototype. Reconsider adaptive stems only after owner validation, using a zero-cost, rights-cleared source.

## Alternatives considered
- Keep the prototype silent until the owner supplies stems: avoids a mismatch but leaves the requested music absent.
- Use a commercial recording or pay for stems: outside the charter's no-spend budget.
- Use this Creator Store track as a full mix: chosen because it is available for free in Roblox and is catalogued as Mexican mariachi music; fit for this game remains unverified.

## Consequences
The prototype can have one music bed without spending or building an adaptive stem system. Section changes will not add musical layers. Code must use the verified asset ID through the existing configuration path and allow sound to be disabled. Implementation is tracked in [issue #21](https://github.com/manoochehri/calenda/issues/21). A Studio check must verify playback and fit before the audio is described as final.

## Sources
- Roblox Creator Hub, [Audio assets](https://create.roblox.com/docs/audio/assets)
- Roblox Creator Store, [Mexican Nostalgia](https://create.roblox.com/store/asset/1838904620/Mexican-Nostalgia)
- Universal Production Music, [Mexico album](https://www.universalproductionmusic.com/en-pl/discover/albums/12221/mexico)
