# 0012: Start with the player alone; empty opening is playable

**Date:** 2026-10-30  **Status:** accepted

## Context

Owner direction in [#226](https://github.com/manoochehri/calenda/issues/226): show the
player before the city fills in, start gameplay with no NPC followers, and recruit
everyone during play. Implementation and this minimal life-semantics amendment were
explicitly authorized in the engineering request. The permanent avatar is already separate
from the follower total (spec §4, ADR 0003). An unconditional empty-crowd check in the
per-tick attack batch defeated even an untouched solo opening.

## Decision

Set `Config.startingTotal = 0`. Ready/title, intro, run start and replay grant no NPC
followers. Continuous firing remains available with zero followers, using the existing
base cadence and server-owned recruitment. Show the avatar before releasing city
construction; reuse the existing bounded avatar wait for failed character loads.

Zero initial followers alone does not defeat. A valid damaging contact while solo does
defeat, and a loss that empties a recruited parade still defeats immediately. Empty,
off-lane and rejected attack batches do not count as damage. All valid contacts in the
same batch remain consumed/logged before its single defeat check. This is not a grace
period or invulnerability and adds no HP or life counter.

This supersedes only the starting total of 10 in spec §5 and the unconditional
defeat-at-zero wording in ADRs 0006/0007 and spec Amendments 4/9. The loss formula,
minimum loss, once-only consumption, defeat precedence, score, server authority,
firing tunables, visual/resource/safety limits and city buildings remain unchanged.
It resolves the solo-start decision deferred in Amendment 12.

## Consequences

Startup and replay must demonstrate zero followers, firing, recruitment and survival
without contact, plus defeat on a real hit at zero or on loss of the last follower.
Existing balance evidence is not evidence for the new opening. Balance changes belong
to their separate issue; presentation and device behavior remain UNVERIFIED in Studio.
