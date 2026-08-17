# Local matching v2 robustness amendment, 2026-08-03

Status: post-results amendment. This document does not alter the frozen
headline estimator or outcome family. Every newly added result is reported
unconditionally in the appendix, including failed feasibility and balance
gates. The purpose is to close declared-but-unexecuted robustness items and to
correct their interpretation before the final paper is written.

## Implemented checks

1. **Equal-deal estimand.** Estimate the precommitted equal-deal weights on the
   15 cohorts for which that solve is feasible. Compare them only with the
   headline inventor-weighted estimator restricted to those same 15 cohorts;
   the all-17-cohort headline appears only as context.

2. **Precommitted dependence refits.** Carry the already solved P5 weights for
   exclusion of deal 70, exclusion of Henkel, and the eight feasible
   single-firm omissions through P6 estimation. The ninth single-firm attempt
   (Henkel, group 303292) failed the ordinary hierarchy and is represented by
   the separately solved exact-balance Henkel omission. Re-solved rosters are
   materialized against a complete union outcome panel because they introduce
   donors absent from the frozen headline panel.

3. **CBPS reweighting.** Fit one cohort-specific ATT CBPS specification on the
   identical frozen local-support roster, using the P5 base weights and the 15
   pre-treatment variables stored in the count/active annual-trajectory
   files. Report cohort balance, control ESS, ESS relative to the treated
   count, and maximum control-weight share before any ATT. ATT estimation is
   authorized only if every cohort has maximum absolute SMD at most 0.10.
   Ordinary propensity-score IPW is not run.

4. **Finer IPC resolution.** Apply the prospective P4 pilot gate to IPC main-
   group matching at the frozen Stage-2 caliper of 1.5. A full alternative ATT
   is authorized only if every fixed pilot cohort clears 80% inventor
   retention. Failure is a feasibility result, not evidence for robustness.

5. **Amended quantity outcomes.** Estimate fractional patent applications and
   log(1 + patent applications) with the frozen weights and estimator. These
   outcomes were not frozen as headline outcomes and therefore remain
   unconditional appendix checks. Fractional counts address team-size
   allocation only; they do not explain the extensive margin.

6. **PPML.** Fit patent counts in levels using PPML with conceptual-unit and
   cohort-by-event fixed effects, frozen weights, and deal/inventor two-way
   clustered inference. Exclude event time zero. Report the multiplicative
   rate effect, not a level ATT; PPML is never applied to first differences.

7. **Deal-stack sign flip.** Report a 99,999-draw paired sign-flip diagnostic
   using treated-deal post-period contributions. Because acquisition is not
   randomized, label this a sharp-null diagnostic rather than exact design-
   based randomization inference.

## Reporting corrections

- Caliper sensitivity is not added. The values 2.0 and 1.5 are the headline
  firm- and inventor-stage calipers, not an unexecuted sensitivity grid.
- A ``never-treated'' control-group robustness row is not added because firms
  never observed as targets, with acquirer-window exclusions, already define
  the headline donor pool. Duplicating it under a different label would not be
  a robustness check.
- LOYO stability refers only to holding out pre-periods -5 through -2. Holding
  out -1 changes the reference to -4 and is reported as a timing/reference
  sensitivity. It does not identify an anticipation-one design.
- The lead heterogeneity multiplicity family is Holm across all eight primary
  contrasts. Holm adjustment within each outcome (four contrasts) is shown
  secondarily and explicitly labelled post hoc.
- The untreated-control exercise is a pipeline-calibration diagnostic. It
  does not address selection because both arms are drawn from untreated firms.
- PPSCM and uniform-top-20 are reported as validation failures; neither
  produced an ATT that can be cited as positive robustness evidence.

## Final-table organization

The final robustness table is split into four panels: estimand and functional
form; dependence and inference; timing and support; and pipeline/validation
diagnostics. Rows that fail an upstream gate show ``no ATT authorized'' rather
than an empty or selectively omitted estimate.

## Verified production results

| Exercise | Verified result |
|---|---|
| Headline patent count | -0.0534; 95% wild-bootstrap CI [-0.0909, -0.0168]; p=0.0077 |
| CBPS, identical support/covariates | -0.0534; 95% wild-bootstrap CI [-0.0909, -0.0168]; p=0.0077; all 17 balance gates pass |
| Equal-deal, common 15 cohorts | -0.0074; 95% two-way-clustered CI [-0.0430, 0.0282]; p=0.6845 |
| Fractional patent count | -0.0110; 95% wild-bootstrap CI [-0.0214, -0.0008]; p=0.0348 |
| log(1 + patent count) | -0.0221; 95% wild-bootstrap CI [-0.0413, -0.0035]; p=0.0235 |
| PPML | exp(beta)-1 = -33.65%; 95% CI [-43.29%, -22.37%]; p<0.001 |
| Deal 70 / Henkel re-solves | -0.0496 / -0.0463; both wild-bootstrap p<0.02 |
| Eight feasible donor-firm re-solves | estimates range from -0.0567 to -0.0527; all wild-bootstrap p<0.009 |
| Frozen-weight leave-one-deal-out | 340 feasible deletions range from -0.0623 to -0.0472; one thin-cohort deletion undefined |
| Deal-stack sign flip | p=0.00396 with 99,999 draws |
| IPC main-group | all pilot cohorts fail the 80% retention gate (59.3%-75.4%); no ATT authorized |

The equal-deal result changes the paper's substantive claim. The headline is
an average for inventors in the supported treated workforce, not an estimate
for the average acquisition. This qualification belongs in the abstract,
introduction, results discussion, and conclusion wherever the headline effect
is summarized.
