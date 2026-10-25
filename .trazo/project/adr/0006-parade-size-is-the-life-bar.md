# 0006: The parade size is the life bar; no separate HP

**Date:** 2026-10-24  **Status:** accepted

## Context
Amendment 1 (ADR 0002) gave the parade a second integer, parade HP, that only attacks reduced. Players now see two numbers for one parade: the crowd counter and an HP bar. Issue #121 records the owner's decision: the life bar is the parade itself. A horde that is not shot costs followers, and the run ends when the parade has none.

## Decision
Remove parade HP. `crowdTotal` is the only life number.
- An unconverted horde that reaches the parade removes its type's `attackLoss` followers (Config, per cluster type) once. An unblocked tomato removes `hazards.tomatoLoss` followers once. The −10 obstacle is unchanged.
- Every loss clamps the total at zero and goes through the same total as every other change, so sections disperse by the normal rule.
- The run ends defeated the moment the total reaches zero. The score is the total at that moment, so a defeated run scores 0.
- The client displays the server total only and has no HP bar, HP field or HP payload.

This supersedes ADR 0002's parade HP and its HP defeat, and the HP wording in spec Amendment 1, and the HP-only parts of ADR 0002's consequences. The spec change is Amendment 4 in `docs/Calenda-Prototype-Spec.md`. The per-type loss values and the tomato loss are provisional defaults chosen by the engineer, UNVERIFIED until the validator, bot runs and the #17 ladder are re-run.

**Rule:** None

## Alternatives considered
- Keep HP and show it beside the counter: two numbers for one parade, which the owner rejected.
- A horde takes a fraction of the parade: harder to read than a fixed number per type, and it couples losses to size.
- Keep a hidden HP that is derived from the total: the same single number under another name, so it is removed too.

## Consequences
A defeated run's score is 0 by construction; the results screen still shows "defeated". The first minute is the risk: a starting total of 10 means one large horde can end a run, so the balance numbers must be re-tuned before the owner playtest. PR #119 (#93) tunes the old HP balance and is superseded by this decision. Its unmerged ADR 0006 and Amendment 4 collide with the numbers used here; whichever lands second takes the next free numbers.
