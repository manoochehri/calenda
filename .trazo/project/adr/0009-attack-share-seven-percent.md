# 0009: The horde attack share is 7% of the parade

**Date:** 2026-10-26  **Status:** accepted

## Context
ADR 0007 set the horde loss to `max(minShareLoss, floor(attackSharePercent × total / 100))` with `attackSharePercent = 10`, and flagged the 10% value as a first guess, UNVERIFIED until the #17 ladder was re-run. Issue #148 asked the owner to choose a new value after measurement under the share rule. The measurement covered 3 layouts, seeds 1-10, 30 Hz, n=3 effective per policy. At 6, no-input and always-center runs completed 10 of 30 (one layout, all seeds). At 5, 4 and 3, no-input was also not defeated on every layout. The defeat holds on every layout from 7 upward. The scripted margin was 123 to 172.

## Decision
`attackSharePercent` changes from 10 to 7 (`Config.attackSharePercent`). Owner approval: 2026-10-26, issue #148.

This supersedes the 10% value of ADR 0007's horde rule only. ADR 0007 is not edited. Its loss formula, floor rounding, `minShareLoss = 1`, the tomato rule with `hazards.tomatoSharePercent = 10`, and the obstacle's fixed loss are unchanged. So are ADR 0006's decisions and server authority.

**The value is UNVERIFIED.** The measured numbers have not been reviewed by the skeptic, and the #17 ladder re-run is still open.

**Limits of the evidence:**
- 7 is the smallest tested value that defeats no-input, found by sweeping the cliff. This is a post-hoc fit to the sweep, not a pre-registered test.
- The check ran at 30 Hz only. 60 Hz is not checked.
- One schedule was tested.
- Deterministic policies give effective n=3, so the seed count does not add independent samples.
- The value held on 20 perturbed variants per layout. No-input survived 0 of 60 runs (defeated in all 60). Scripted completed 60 of 60. The minimum margin was 123.

**Rule:** None

## Alternatives considered
- Keep 10%: the owner chose the lower value on the measurements above.
- Change the formula or rounding: out of scope for issue #148.

## Consequences
- A horde removes 7% of the parade at minimum 1, so a total of 100 loses 7 instead of 10.
- The balance claim rests on the measured numbers above and is not independent evidence until the skeptic and the #17 ladder re-run confirm it.
