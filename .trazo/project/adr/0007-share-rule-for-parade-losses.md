# 0007: A horde or tomato takes a share of the parade, at least 1

**Date:** 2026-10-25  **Status:** accepted

## Context
ADR 0006 made the parade size the life bar and removed parade HP. Its loss rule was a fixed number of followers per horde type (`attackLoss`, small 5 and large 10) and a fixed tomato loss (`tomatoLoss`, 5). The open question on issue #121 was whether a fixed loss could both defeat a run with no input and keep a competent run alive. Measured on the debug layout (one probe run per policy and rate, 30 Hz and 10 Hz): the no-input run completed with a total of about 800 after 12 attacks, because recruits and gates outgrew fixed losses. A loss large enough to empty that parade ended a competent run at its first hit.

The owner chose a share of the current parade over a fixed loss on issue #121. The PM's decision named the share but did not name a rounding rule; the values below are provisional.

## Decision
An unconverted horde that reaches the parade, and an unblocked tomato, each remove a share of the crowd total:

- **Horde (any type):** `max(minShareLoss, floor(attackSharePercent × total / 100))`, with `attackSharePercent = 10` and `minShareLoss = 1`. The total is the parade as it stood immediately before that hit. Hordes in the same batch chain: each share is taken from the total after the previous hit.
- **Tomato:** `max(minShareLoss, floor(hazards.tomatoSharePercent × total / 100))`, with `hazards.tomatoSharePercent = 10`.
- **Obstacle:** unchanged, a fixed `obstacleLoss = 10` (spec §9).

Every loss clamps at zero and goes through the same crowd total as every other change. The run ends defeated the moment the total reaches zero, and the score is the total at that moment (so 0). The per-type `attackLoss` and the `hazards.tomatoLoss` keys are removed from Config.

This supersedes ADR 0006's loss rule only: ADR 0006's decision to remove parade HP, the crowd total as the only life number, and the defeat-at-zero rule are unchanged.

**Floor rounding is an explicit, UNVERIFIED design call.** The owner decision did not specify rounding. Floor was chosen by the engineer. At small totals it means the minimum of 1 applies (for example, any total below 10 loses 1 per hit). No playtest or bot run has yet checked whether floor, rather than round or ceiling, gives a readable loss.

**Balance is not measured under this rule.** The 10% and minimum 1 values are first guesses, UNVERIFIED until the #17 ladder is re-run. The fixed-loss measurements above no longer apply and are not evidence for this rule.

**Rule:** None

## Alternatives considered
- Keep fixed per-type losses (ADR 0006): cannot both defeat the no-input run and keep a competent run alive, per the measurement above.
- Round to nearest or ceiling instead of floor: not chosen. Ceiling would make the minimum of 1 rarely binding, and round would move the loss by up to 1 at small totals; neither was measured.
- Share of the total after the hit: not chosen. It makes a horde's loss depend on its own effect, and the same-tick order in spec Amendment 1 uses the total before each hit.

## Consequences
- The loss scales with the parade, so a large parade loses more per hit. A horde's loss is never a fixed number on the HUD, so the counter alone does not say what a hit will cost.
- Tuning is in Config: `attackSharePercent`, `minShareLoss` and `hazards.tomatoSharePercent`, one whole-number line each.
- The first minute is still the risk: with a starting total of 10 the minimum of 1 means early hits are small, so the no-input defeat check and the competent-run check must be re-measured under this rule before the owner playtest.
- Revisit when the #17 ladder has been re-run under this rule, or if floor rounding reads as unfair in playtest.
- ADR 0006 is not edited. Its status stays `accepted`; this record carries the supersession of its loss rule.
