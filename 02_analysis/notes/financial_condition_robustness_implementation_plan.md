# Financial-condition robustness: implementation plan

## Implementation amendment after the outcome-blind feasibility audit

The feasibility audit materially narrows the design and therefore amends the
implementation below in four respects. These choices were fixed before the
financial outcome estimates were read and supersede any inconsistent wording
later in this plan.

1. The comparison contains four rows: the full headline; headline weights
   restricted to the feasible treated-deal set without re-solving; the
   financially linked roster re-solved on the original balance vector; and the
   identical roster additionally balanced on financial conditions.
2. The support restriction follows the locked deal-level requirement of at
   least five financially observed control firms. It is not imposed separately
   for every treated inventor.
3. Exact entropy balancing is followed by the certified approximate-balance
   hierarchy at SMD tolerances 0.05 and 0.10, including the reuse-adjusted ESS
   gate. No cohort is admitted when either the linked or adjusted design fails.
4. Outcome-blind coverage, composition, balance, and effective-deal-count gates
   determine placement. A failed reporting gate permits an appendix diagnostic
   but rules out presenting the result as a broad-coverage main-text robustness
   check.

The primary financial rule uses exact `g-1` information. The already planned
latest-observation rule within `g-3:g-1` is implemented separately to determine
whether sparse annual reporting drives the feasibility problem. Certified
results and the placement decision are recorded in
`02_analysis/notes/financial_condition_robustness_results.md`.

## 1. Objective

Test whether the five-year inventor-weighted patent-count ATT changes after accounting for pre-acquisition differences in firms' financial conditions. The exercise is motivated by Cassi and Ornaghi's financial-control check, but it should preserve this thesis's local-support, cohort-specific entropy-balancing, and DiD framework.

The exercise must distinguish two possible sources of a different estimate:

1. restricting the analysis to firms with usable financial data; and
2. balancing treated and control inventors on those financial variables.

The main comparison is therefore between two specifications estimated on exactly the same financially linked sample:

- **Financial-linked benchmark:** rebalance the restricted sample using the original balance vector only.
- **Financial-adjusted specification:** rebalance the same sample using the original balance vector plus the financial variables.

The full-sample headline ATT remains the reference estimate. The financial exercise is a restricted-sample robustness check and does not replace it.

## 2. Inputs and source files

Use only the certified 1993--2010 design artifacts.

- Financial data: `cassi_financial_all` in `02_analysis/output/thesis_foundation.duckdb`.
- Frozen local-support rosters and base weights: cohort files in `.worktrees/lmv2-1993-amendment/02_analysis/output/audit/local_match_v2_1993_amendment/P5C_ANNUAL_TRAJECTORY/production/weights/`.
- Certified P6 event-panel shards: the same panel directory used by the existing robustness runners.
- Existing estimation functions: `19a_lmv2_p6_estimation_config.R` and `19b_lmv2_p6_estimation_core.R`.
- Existing balance and weighting logic: reuse the relevant functions from the P5c entropy-balancing implementation rather than writing a second solver.

The financial table has already passed the first key audit: it contains 2,716 rows and 2,716 distinct `id_group` values. Join it to the frozen roster through `group_id`, which identifies the target group for treated rows and the corresponding control group for control rows.

## 3. Design choices to lock before reading outcomes

### Financial reference year

Use financial information from `g-1`, the final complete year before acquisition cohort `g`. This avoids post-treatment information and keeps the timing transparent. Because the available financial columns begin in 1996, the primary check can start no earlier than the 1997 cohort.

Do not carry information backward from the acquisition year or any post-acquisition year. As a secondary appendix sensitivity, the latest jointly observed financial record within `g-3` to `g-1` may be used, but this must be labelled separately and cannot replace the exact-`g-1` specification.

### Financial variables

Construct three predetermined variables:

- `log_turnover = log(1 + turnover)`;
- `asinh_operating_income = asinh(operating_income)`;
- `negative_operating_income = 1[operating_income < 0]`.

The inverse-hyperbolic-sine transformation accommodates zero and negative operating income without discarding loss-making firms. Do not winsorise the primary variables. If extreme values prevent feasible balance, any winsorised specification must be presented as a separate, prespecified sensitivity rather than introduced after inspecting outcomes.

Require turnover and operating income to be observed for the same pre-acquisition year. Do not impute missing financial values in the primary specification.

### Outcome and estimand

Keep the outcome and estimand identical to the headline analysis:

- annual patent count;
- event years `t=+1` to `t=+5` relative to `t=-1`;
- inventor-weighted cohort aggregation;
- two-way acquisition--inventor clustered inference in the main table;
- the existing wild-cluster bootstrap as an appendix inference check.

## 4. Implementation stages

### Stage F0: Outcome-blind financial coverage audit

Create `48j_build_lmv2_financial_condition_design.R` alongside the existing robustness scripts. This script must remain outcome-blind and cover Stages F0--F3 only.

1. Reshape `cassi_financial_all` from wide group-by-year form into one row per `id_group` and financial year.
2. Verify uniqueness of `(id_group, financial_year)`.
3. Join the financial records to each frozen roster row through `group_id` and `financial_year = cohort - 1`.
4. Report financial-data coverage separately for treated and control rows by cohort.
5. Report the number and share of supported treated inventors, acquisitions, and cohorts retained.
6. Compare original balance characteristics between financially observed and financially missing treated inventors. This identifies how the restricted financial sample differs from the headline population.

Write:

- `financial_linkage_audit.csv`;
- `financial_coverage_by_cohort.csv`;
- `financial_coverage_by_arm.csv`;
- `financial_observed_vs_missing.csv`.

### Stage F1: Reapply support after the financial restriction

The financial restriction can remove entire control firms and thereby weaken inventor-level support. Do not assume that the original three-control, two-firm rule still holds.

1. Start from the frozen admissible donor relationships; do not recruit any new firms or inventors.
2. Remove target and control firms without complete `g-1` financial information.
3. Reapply the preferred requirement of at least three admissible control inventors from at least two financially observed firms for every treated inventor.
4. Pool the remaining treated and control rows by cohort using the same logic as the main design.
5. Freeze this common financial roster before solving either set of weights.

Both financial specifications must use this identical roster. Otherwise, differences between their ATTs could reflect different observations rather than financial adjustment.

Write:

- `financial_support_by_cohort.csv`;
- `financial_support_by_deal.csv`;
- `financial_roster.parquet`;
- `financial_roster_manifest.csv`.

### Stage F2: Solve two entropy-balancing specifications

Within every retained cohort, solve:

1. **Linked benchmark weights:** the original balance vector only.
2. **Financial-adjusted weights:** the original balance vector plus `log_turnover`, `asinh_operating_income`, and `negative_operating_income`.

Both specifications must begin from the same deal-normalised base weights. Treated inventors retain weight one, and control weights must sum to the number of treated inventors in the cohort.

If the financial-adjusted specification is infeasible for a cohort, remove that cohort from both specifications and re-solve both on the same feasible cohort set. Do not compare estimates based on different cohorts.

Write one weight file per cohort and specification, plus:

- `financial_balance_before_after.csv`;
- `financial_weight_diagnostics.csv`;
- `financial_feasible_cohorts.csv`.

### Stage F3: Balance and weight-quality gates

Outcomes remain inaccessible until both specifications pass all gates:

- unique `roster_row_id` values;
- finite, non-negative weights;
- treated weights equal one;
- control and treated weight mass equal within each cohort;
- maximum absolute SMD no greater than 0.10 for every required variable and cohort;
- finite positive control ESS;
- reported maximum control-weight share and ESS ratio;
- identical roster rows and cohort set across the linked benchmark and financial-adjusted specifications.

The adjusted specification should report financial-variable SMDs before and after weighting explicitly. Save the design choices, input checksums, balance results, and pass/fail status in `financial_design_manifest.csv`.

### Stage F4: Materialise and certify the outcome panels

Create `48k_run_lmv2_financial_condition_estimation.R`. It may proceed only after validating the frozen design manifest and its input checksums.

Join each set of frozen financial weights to the certified P6 panel through `roster_row_id`. Verify:

- one panel unit for each roster row;
- eleven event-time observations from `t=-5` through `t=+5`;
- no duplicated inventor--deal--event-time rows;
- no missing or invalid weights;
- equal treated and control weight mass within cohorts.

Write separate certified panel manifests for the linked benchmark and adjusted specifications.

### Stage F5: Estimate the effects

Using the existing P6 estimator, estimate for both specifications:

- the dynamic patent-count event study;
- the five-year average ATT;
- two-way acquisition--inventor clustered standard errors, confidence intervals, and p-values;
- the pre-trend diagnostic for any pre-acquisition outcomes not mechanically balanced;
- wild-cluster-bootstrap inference for the appendix.

Write:

- `financial_dynamic.csv`;
- `financial_headline.csv`;
- `financial_pretrend.csv`;
- `financial_coverage.csv`;
- `financial_estimation_manifest.csv`.

The result table should contain three rows:

1. full-sample headline ATT;
2. financial-linked benchmark ATT;
3. financial-adjusted ATT.

The comparison between rows 2 and 3 is the test of sensitivity to financial adjustment. The comparison between rows 1 and 2 shows how much of any change comes from restricting the sample to firms with financial data.

### Stage F6: Independent certification and release integration

Create `48l_certify_lmv2_financial_condition_robustness.R` to verify the design freeze, balance gates, common roster, panel integrity, and reported estimates without re-estimating the models. Only after this certification passes should the result be added to `49a_build_lmv2_1993_robustness_release.R` and the thesis exhibit builder `68_build_robustness_exhibits.R`.

## 5. Interpretation rules

- If rows 2 and 3 are similar, financial adjustment adds little once the analysis is restricted to the linked sample.
- If row 1 differs from both rows 2 and 3, the difference mainly reflects financial-data coverage and the narrower estimand.
- If row 3 differs materially from row 2, pre-acquisition financial conditions affect the estimated ATT and must be discussed as an identification qualification.
- If the adjusted estimate remains negative but becomes imprecise, describe the direction as stable while acknowledging the loss of precision.
- If financial coverage or balance is too weak for an informative comparison, report the feasibility results without interpreting the ATT as evidence of robustness.

Do not describe stability on the financial subsample as proof that financial selection is absent in the full sample.

## 6. Thesis placement

The complete coverage, balance, and three-row results table belongs in the appendix. Add the financial-adjusted estimate to the main robustness table only if the linked sample retains broad coverage and the balance diagnostics pass cleanly. Otherwise, include one concise main-text sentence and an appendix reference.

Suggested main-text wording if the result is stable:

> The estimated decline also remains similar when I restrict the sample to firms with available pre-acquisition financial information and additionally balance on turnover and operating income. Because the financial linkage reduces sample coverage, I report the complete comparison and diagnostics in Appendix~\ref{app:financial_robustness}.

## 7. Final acceptance criteria

The exercise is complete only when:

- all financial variables are strictly pre-treatment;
- the linked benchmark and adjusted estimates use the same inventor rows and cohorts;
- all balance and weight-quality gates pass before outcomes are read;
- the estimate, standard error, confidence interval, p-value, treated-inventor count, acquisition count, and cohort coverage are reported;
- the output is reproducible from one command and all source paths and checksums are recorded;
- the robustness release builder and thesis table generator read only certified outputs.
