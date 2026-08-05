# Local matching v2: P4 small-cohort balance-gate amendment

Status: immutable prospective record, written 2026-07-23, approved by the
review before any P4 design was frozen and before any outcome inspection.
Like the P4 resolution lock, this record lives outside
`local_match_v2_amendments.md` because the certified P3 configuration hashes
that file. The SHA-256 of this record is pinned in
`17a_lmv2_p4_pilot_config.R` and folded into the P4 configuration hash.

## Context and outcome-blindness

The first P4 pilot execution stopped at the prespecified Stage-1
design-failure gate. The diagnostics inspected in reaching this amendment
were exclusively firm-level pre-treatment balance and retention measures
(run1 Stage-1 outputs); no outcome variable, outcome table, or
treatment-effect estimate was read. The stop revealed two independent
causes: a P3 control-firm data defect (patched separately as P3 version 2)
and the structural impossibility of a cohort-level SMD gate in a cohort
with four treated deals. This amendment addresses only the second cause.

## The rule

1. `minimum_treated_deals_for_cohort_smd_gate = 10`. A pilot cohort's
   cohort-specific Stage-1 balance gates are enforced only when that cohort
   contains at least 10 treated deals in the primary pilot spine.
2. Pooled balance gates are always enforced, for every profile, regardless
   of cohort sizes.
3. The cohort-specific Stage-1 SMD gates (preferred 0.075, acceptable 0.10)
   and the cohort-specific trajectory-promotion trigger (0.075) apply only
   to gate-eligible cohorts. The pooled trajectory-promotion trigger (0.05)
   is unaffected.
4. Small-cohort SMDs are still computed and reported prominently in every
   profile-metrics output; they are excluded only from pass/fail gating and
   from the balance ordering metric used for lexicographic selection.
5. Stage-2 gates are unchanged in every respect.
6. The same principle applies prospectively in P5a production matching:
   formal balance gates are evaluated pooled and across the three broad
   eras rather than per cohort, so that no gate is ever asked to bind on a
   handful of deal-level observations.

## Rationale

This is a general small-sample rule, not a 1995 exception. A deal-level SMD
computed over four deals is dominated by sampling noise: no design, however
well matched, can reliably satisfy a 0.075 or 0.10 bound there, so such a
gate cannot distinguish good designs from bad ones. The threshold of 10
applies symmetrically to every cohort in the pilot and, through the era
rule, to all production cohorts; several early-1990s cohorts have similar
deal counts and are treated identically.
