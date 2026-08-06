# Local Match v2 TechDrift window amendment

**Accepted:** 2026-08-04  
**Status:** frozen before estimating either pooled TechDrift contrast

## Motivation

The frozen TechDrift outcome compares each inventor-year IPC4 vector with a
patent-count-weighted IPC4 baseline formed over `g-5,...,g-1`. The event-study
estimator then differences every annual value from `t=-1`. This construction
has two measurement problems that can be diagnosed without inspecting a new
pooled estimate:

1. Annual TechDrift is defined only when an inventor patents in both the
   comparison year and `t=-1`. In the amended 1993--2010 stayer design,
   pairwise treated-weight coverage ranges from roughly 11% to 33%.
2. The `t=-1` vector is a component of the baseline against which it is
   evaluated, so the reference outcome is mechanically self-included.

The annual results were already known before this amendment. In the amended
1993--2010 sample, the stayer estimate is 0.00408 (deal wild-bootstrap 95% CI
[-0.02163, 0.02888], p=0.739); the full-cohort estimate is 0.00685 (95% CI
[-0.02472, 0.03928], p=0.665). They remain reported as the prespecified legacy
results regardless of the pooled findings.

## Frozen amended outcomes

The amended headline TechDrift measure is

`1 - cosine(IPC4[g-5:g-1], IPC4[g+1:g+5])`,

where each vector uses the same integer patent-count weights as the frozen
annual outcome. The acquisition year is excluded. This measure is called the
recent-pre versus pooled-post portfolio displacement. It is a weighted matched
contrast, not an annual difference-in-differences estimand.

Patent-count weighting is the headline construction. It captures the relative
intensity of inventive activity across IPC4 fields and follows the IPC-profile
construction in Verginer et al. A binary field-presence version, in which each
active IPC4 receives weight one within a window, is reported as a robustness
check. The binary construction is not described as the Verginer et al.
measure.

The following analyses are fixed before estimation:

- **Main:** recent pre-period `g-5,...,g-1` versus pooled post-period
  `g+1,...,g+5`.
- **Baseline sensitivity:** complete observed pre-deal IPC stock through
  `g-1` versus pooled `g+1,...,g+5`. This is not called a complete career
  history because patent records are left-censored at 1988.
- **Vector-weight sensitivity:** binary IPC4 field presence over the recent
  pre and pooled post windows, keeping every other design choice fixed.
- **Coarse dynamics:** recent pre-period versus `g+1,g+2`, and recent
  pre-period versus `g+3,g+4,g+5`.
- **Late-tail sensitivity:** the main pooled contrast excluding the 2010
  cohort. No 1994--2008 double-buffer sample is reinstated.
- **Restricted pre/pre diagnostic:** `g-10,...,g-6` versus `g-5,...,g-1`,
  restricted to cohorts from 1998 onward and to inventor-deal stacks with
  nonempty vectors in both windows. This is diagnostic, not a pass/fail gate.

## Design and inference

The certified 1993--2010 stayer support roster and the final
`primary_count_active_scale` weights are reused without rematching,
rebalancing, or outcome-dependent exclusions. The governing confidence
interval uses the existing 9,999-draw deal wild bootstrap. The two-way
deal--inventor interval remains the prominent companion because control
inventors can recur across deal stacks.

TechDrift requires a nonempty classified IPC4 portfolio in both comparison
windows. A patent without an observed IPC4 code does not make the outcome
defined. The pooled contrast is therefore estimated only in the frozen
**initially retained inventor** design: treated inventors classified as
initially retained during `t=1,...,5`, and matched inventors who remain with
clean control firms. This design nearly guarantees post-period patent support,
but the release still reports exact pre-, post-, and joint IPC4 coverage.

Initial retention is measured after treatment. The pooled TechDrift result is
therefore a selected-group matched contrast in technological portfolio
displacement. It is not the main full-cohort DiD ATT, is not directly
comparable to that ATT, and is not interpreted as an always-retained principal
stratum effect. A pooled full-cohort causal estimate is not added because
treatment affects selection into an observable post-period IPC vector.

## Patent-count support diagnostics

Cosine distance can depend on the number of patents available to reveal an
inventor's post-period technology distribution. Before substantive
interpretation, the release must report:

- post-period patent-count and distinct-IPC4 distributions by arm;
- mean pooled TechDrift by arm in patent-count bins `1`, `2`, `3-4`, and `5+`;
- a descriptive decomposition of the raw treated-control drift gap into a
  component associated with different post-patent-count-bin shares and a
  within-bin component.

Any count-standardized contrast is a diagnostic only. Post-period patent
count is a treatment-affected variable, so it is not used to replace the main
estimate or to claim a controlled direct effect. Patent rarefaction is not
pre-designated as an arbiter; it will be considered only if these diagnostics
show a material finite-count problem.

## Reporting rule

The legacy annual outcome, the amended pooled main outcome, and the complete
observed-stock sensitivity are reported regardless of sign or significance.
The annual event study is retained as the prespecified measurement but its
coverage and self-inclusion limitations are stated explicitly.
