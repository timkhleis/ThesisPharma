# Local Match v2: 1993 cohort amendment

## Status and timing

This amendment was approved on 2026-08-03 before any matched outcome,
treatment-effect estimate, event-study coefficient, or 1993 outcome comparison
was inspected. It creates `local_match_v2_1993_amendment_v1`; it does not alter
the frozen `local_match_v2` release or its artifacts.

## Rationale

The former 1994 lower bound was inherited from a superseded matching design
that used information from event years `g-6` through `g-3`. A 1993 acquisition
would have required data from 1987 under that design. Local Match v2 instead
constructs all matching covariates from `g-5` through `g-1`. The 1993 cohort
therefore has a complete pre-treatment window from 1988 through 1992 and a
complete post-treatment window from 1994 through 1998 in the 1988--2015 panel.

## Amended rule

- The primary cohort window is 1993--2010.
- The event window remains `t=-5,...,+5`, with `t=-1` as the reference period
  and `t=+1,...,+5` as the aggregate post-treatment window.
- The right-end censoring companion, when required by an outcome, is
  1993--2008.
- The frozen 1994--2010 sample is an internal reproduction check. It is not a
  routinely co-reported specification. It is reported only if the amended
  design fails a locked gate or differs materially for a reason that readers
  need to understand.
- The former 1994--2008 double-buffer sample is not part of the amended result
  package when the 1993 design passes.

No matching variable, caliper, donor-universe rule, balance threshold,
retention threshold, concentration threshold, outcome definition, estimand,
or inference rule changes.

## Outcome-blind gate

The 1993 cohort must pass the existing Local Match v2 support, balance,
retention, effective-sample-size, and concentration gates without retuning.
Before outcomes are opened, the build must also record:

1. the treated-inventor and treated-deal counts before and after support;
2. five-year pre- and post-window completeness;
3. weighted balance, reuse-adjusted ESS, and maximum control-weight share;
4. the share of 1993 inventors whose observed career begins in 1988; and
5. exact reproduction of the frozen 1994--2010 cohort-level rosters and
   weights after restricting the amended build to those cohorts.

If a locked gate fails, execution stops. No outcome-guided repair or alternate
matching specification is authorized by this amendment.

## Downstream propagation

The approved 1993--2010 definition governs every substantive analysis derived
from the matched full-cohort or initially retained samples. This includes the
primary outcomes, stayer outcomes and selection diagnostics, inventor and
stayer heterogeneity, the DealSim power gate, exit decompositions, recurrent-
inventor results, the completion-year sensitivity, and the control-endpoint
diagnostic. Generated tables, figures, and result notes use the separate
`local_match_v2_1993_amendment` namespace.

The amendment does not waive any prospective gate. A downstream estimand is
omitted when its gate fails. In particular, the DealSim treatment-effect stage
and the t+1 landmark decomposition remain omitted, while balance- or power-
limited heterogeneity estimates are retained only as clearly labelled
appendix evidence. The machine-readable cross-package certification is built
by `42b_certify_lmv2_1993_downstream_comparability.R`.

The symmetric untreated-firm placebo was rerun on 1993--2010 with 2,000
assignments, 100 firms per arm and cohort, and 999 Webb-bootstrap
replications. The release includes both the placebo-ATT distribution and the
dynamic event-study plot. The uniform-top-20 control-null exercise also
completed all 499 frozen draws. It failed its prospective comparability gate:
only 150 of 499 draws were inference-comparable, and the upper endpoint of the
exact 95% interval for the false-rejection share was 0.1024, above the 0.10
threshold. In accordance with the frozen rule, no real post-treatment ATT was
estimated for that design.
