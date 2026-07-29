# P5b S5 post-outcome diagnostic amendment

This amendment was written after the P5b S4 initially-retained estimates were
opened. It therefore does not alter the frozen S3 roster, weights, outcomes, or
S4 point estimates. It freezes the additional diagnostics requested after the
positive event-time-zero estimate was investigated.

## Reporting hierarchy

The primary uncertainty estimate is the analytic two-way
deal/inventor-clustered interval. The deal-level wild-cluster bootstrap remains
a prominently reported conservative sensitivity. Both results are reported;
the inference choice does not alter the point estimate.

## Sample-funnel and pipeline audit

The audit starts with every status-eligible treated inventor classified in S2
and reports mutually exclusive retention statuses. It then follows initially
retained inventors through the exact P5c common-support roster and the
stayer-specific S3 support restrictions. It separately identifies:

1. no observed patent in years \(t=+1,\ldots,+5\);
2. a first observed post-deal patent outside the focal entity (leaver);
3. an initially retained first post-deal patent;
4. exclusion from the already-frozen P5c common-support roster;
5. the three prospectively declared convex-hull exclusions; and
6. absence of a retained-control analogue in the same frozen P5c support.

The audit must prove that S4 uses the same certified P6 patent-count panel as
the clean full-cohort DiD. Only the retained sample restriction and S3 weights
may differ.

## Extensive/intensive decomposition

For post-deal patent count, write

\[
E[Y]=P(Y>0)\,E[Y\mid Y>0].
\]

The treated-minus-counterfactual difference is decomposed exactly using the
two-factor Shapley decomposition:

\[
\Delta_Y =
(\Delta_P)\frac{\mu_T+\mu_C}{2}
+
(\Delta_\mu)\frac{P_T+P_C}{2}.
\]

The first term is the extensive margin and the second the intensive margin.
Two-way deal/inventor-clustered uncertainty is calculated with a delta method
from the same cohort-weighted influence functions used by P6/S4.

## Selection diagnostics and bounds

The selection package reports:

- pre-deal productivity and career characteristics for initially retained
  inventors, leavers, and inventors with no observed post-deal patent;
- the observed \(t=-1\) to \(t=0\) changes by treatment arm and subsequent
  retention status;
- a pooled trimming diagnostic for the post-deal patent-count contrast,
  explicitly not labelled as a formal Lee bound unless the Lee independence
  and monotonicity assumptions are shown to hold; and
- a common-support tipping calculation
  \(ATT_{\rm all}=pATT_{\rm supported}+(1-p)ATT_{\rm unsupported}\).

The trimming calculation uses the original P5c weights and post-average minus
\(t=-1\) patent counts. Because the pooled treated retention rate is below the
control rate, it retains the treated/control fraction of retained-control
weight. Specifically, it retains 77.14% and discards 22.86%. The lower
endpoint retains controls with the most favorable outcome changes and discards
the most negative 22.86%; the upper endpoint retains controls with the most
negative changes and discards the most favorable 22.86%. The endpoints are
therefore pooled worst-tail selected-control comparisons. They are calculated
using P5c weights rather than the separately balanced S3 stayer weights and
are not bounds on an always-retained ATT.

Ordinary Lee bounds require treatment exchangeability and a common monotonic
direction of treatment-induced selection. This observational DiD instead
relies on conditional parallel trends, and the empirical selection-rate
direction reverses in four cohorts. Patent outcomes are also observed for
non-retainers; retention is an analyst-defined post-treatment subgroup rather
than literal outcome attrition. Cohort-specific retention rates and a
requirement-by-requirement assumption audit are therefore reported.

A future conditional/generalized Lee implementation would need a
prospectively frozen, coarse pretreatment stratification; an explicit
principal-stratum exchangeability or parallel-trends assumption; sign-specific
trimming within strata; and clustered uncertainty. With only 31.53 effective
treated deals, fine strata or outcome-informed sign selection are not
defensible. Unless a coarse stratification is agreed in advance, the thesis
should retain the current range as a descriptive sensitivity and rely on the
selection table plus the common-support tipping calculation. The latter does
not impute an unsupported effect; it reports the effect required among
unsupported initially retained inventors to reverse the supported-sample
conclusion.
