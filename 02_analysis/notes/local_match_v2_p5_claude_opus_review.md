# Request for Claude Opus review: approve P5 before P6

## Decision requested

Please review and either approve P5 as the frozen matching and balancing
design for the main ATT, or identify a specific blocking defect. No P6
treatment effect should be estimated until this review is complete.

P5 is substantively complete. It selected the sample, constructed and
certified row-level weights, ran the predeclared support and dependence
diagnostics, evaluated a separate recovery design for unsupported inventors,
and produced a certified P5-to-P6 weighted roster. P5 did not read an outcome
table or estimate an ATT.

## Frozen primary design

- Cohorts: 1994--2010.
- Donor universe: U2 clean.
- Firm support: reduced specification, Stage-1 caliper 2.0.
- Inventor support: Stage-2 caliper 1.5.
- Technology resolution: IPC4.
- Firm profile: `nearest_50`.
- Primary scheme: inventor-weighted entropy balancing.
- Secondary scheme: equal-deal entropy balancing.
- Primary balance moments: log five-year inventor patent count, inventor
  patent trajectory, career age, focal-group exclusivity, log five-year firm
  patent stock, log five-year firm inventor count, and firm patent
  trajectory.
- Production freeze SHA-256:
  `637e7535239a835ffadc5cbba17a96c2f9a2410d997f36ff127568493b9b33d4`.

The implementation uses a disk-backed sparse technology cache, a Newton
entropy solver, cohort checkpoints, checksum-verified row-level weights, and
a memory-aware two-worker scheduler. Full 17-cohort production completed in
about 35 minutes without an out-of-memory failure.

## Realized primary results

| Diagnostic | Realized result |
|---|---:|
| Eligible treated inventors | 29,170 |
| Entropy-supported treated inventors | 27,078 |
| Aggregate inventor coverage | 92.83% |
| Minimum cohort coverage | 82.72% |
| Aggregate deal coverage | 99.42% |
| Minimum productivity-quartile coverage | 85.63% |
| Primary-feasible cohorts | 17/17 |
| Maximum cohort-level absolute balance SMD | < 4.6e-8 |
| Minimum reuse-adjusted ESS ratio | 0.765 (cohort 2000) |
| Equal-deal-feasible cohorts | 15/17 |

All primary cohort cells achieve exact balance, including firm patent
trajectory. The equal-deal scheme fails its ESS hierarchy in cohorts 2000
and 2005. The comparison map therefore excludes both cohorts from every
like-for-like primary-versus-equal-deal statement while retaining all 17
cohorts in the headline primary ATT.

## Deal 70 and dependence

The baseline cohort-2000 primary design for deal 70 uses:

- 9 control firms;
- 4,911 distinct control inventors;
- effective firm count 4.94;
- maximum firm weight share 29.85%;
- reuse-adjusted control ESS 2,740.6.

Eight of the nine predeclared firm-deletion refits remain feasible with exact
balance. Their reuse-adjusted ESS ratios range from 0.607 to 0.797. Removing
firm 303292 still permits an exact-balance solution, but no solution clears
the predeclared ESS hierarchy. In particular, the exact solution fails the
0.50 reuse-adjusted ESS gate. Henkel is therefore required for acceptable
precision under the frozen design, not for mathematical balance.

Firm 303292 is Henkel. It is the only donor near SmithKline Beecham in firm
scale in cohort 2000:

- SmithKline Beecham: 1,997 five-year patents and 2,395 inventors.
- Henkel: 2,326 five-year patents and 2,131 inventors.
- Every other selected donor has at most 1,230 patents or 1,570 inventors.

The requested technology diagnostic shows that the IPC4 similarity does not
survive disaggregation:

| Technology resolution | Henkel--SmithKline cosine |
|---|---:|
| IPC4 | 0.4284 |
| IPC main group | 0.0437 |
| IPC7 | 0.0209 |

The mechanism is also visible in portfolio composition. A61K8
(cosmetics/toiletries) is 88.51% of Henkel's A61K portfolio, whereas A61K31
(medicinal preparations containing organic active ingredients) is 44.29% of
SmithKline Beecham's A61K portfolio and only 3.27% of Henkel's. IPC4 thus
conflates technologically different parts of A61K.

Henkel remains in the baseline control pool. This is a prospective
interpretive choice: it is uniquely valuable for matching SmithKline
Beecham's firm scale and materially improves effective sample size, but it is
not a close fine-technology analogue. Deal 70 must therefore be described as
a cross-industry scale counterfactual anchored partly by Henkel, not as a
pure pharmaceutical technology match.

P6 should report the baseline ATT and all eight deletion-refit ATTs that pass
the frozen ESS hierarchy. The Henkel-omitted refit must be reported
accurately as “exact balance attained, ESS gate failed,” rather than simply
“infeasible.” Its rejection is a precision decision; it does not establish
that balance without Henkel is impossible.

## Unsupported inventors and cardinality recovery

The entropy design leaves 2,092 inventors unsupported (7.17%). The
unsupported group is observably different:

| Variable | Supported mean | Unsupported mean | Absolute SMD |
|---|---:|---:|---:|
| Log five-year patents | 0.96 | 1.42 | 0.715 |
| Career age | 3.09 | 6.69 | 0.758 |
| Focal-group exclusivity | 0.974 | 0.919 | 0.357 |
| Focal-group tenure | 3.87 | 6.24 | 0.576 |

The selection SMD therefore remains a required scope and bounding diagnostic,
not a balance pass. This reclassification is licensed by the realized
92.83% aggregate coverage, 82.72% minimum-cohort coverage, and 85.63%
minimum-quartile coverage.

A separately frozen, reuse-constrained cardinality design tested whether the
unsupported tail could be recovered without altering the primary entropy
weights. It recovered only 17 inventors: 8 in 2006 and 9 in 2007. Both
recovered cells satisfy the 0.10 balance tolerance; their maximum absolute
SMDs are 0.091 and 0.096. Fifteen cohorts recover nobody. Combined
descriptive coverage rises only from 92.83% to 92.89%, leaving 2,075
inventors unsupported.

This result supports the conclusion that the residual tail generally lacks
clean comparators. The 17 recovered inventors form a separate
recovered-inventor estimate. The estimate and confidence interval must be
reported even if they are too imprecise to interpret, in which case they are
labelled uninformative rather than dropped. They must not be appended to or
allowed to change the primary entropy ATT.

## Estimand and required P6 reporting

The headline estimand is the ATT for treated inventors with clean common
support:

\[
ATT_S.
\]

Population sensitivity must accompany it:

\[
ATT_{\mathrm{all}}
=
p\,ATT_S+(1-p)\,ATT_U,
\qquad p=0.9283.
\]

P6 should report a transparent grid for the unsupported-tail effect
\(ATT_U\), including the value required to reverse the headline conclusion.
The paper should state that unsupported inventors are systematically more
senior and productive.

The frozen reporting hierarchy is:

1. Full 17-cohort primary supported-sample ATT.
2. Equal-deal ATT and primary ATT on the same 15-cohort like-for-like sample.
3. Deal-70 baseline plus eight deletion-refit ATTs that pass the ESS
   hierarchy; Henkel omission reported as exact-balance but ESS-failing.
4. Unsupported-tail bounds and descriptive statistics.
5. A separate recovered-inventor estimate and confidence interval for the 17
   cardinality matches, reported even if uninformative because of imprecision.
6. U3/acquirer-admitting estimates only as coverage robustness, not as the
   headline design.
7. DealSim analysis after the main ATT design is implemented and checked.

## Certified P5-to-P6 handoff

The primary weights were converted without rebalancing or renormalization
into a 500,906-row weighted roster. Certification verifies:

- all 17 cohorts are present;
- treated rows map exactly to the frozen P2 treated interface;
- control inventor-group rows map to the frozen P2 eligibility interface;
- treated weights equal one;
- weights are finite and nonnegative;
- treated and control weight mass agree within each cohort;
- every treated deal has a control pool spanning at least two firms;
- roster keys are unique.

Roster SHA-256:
`458036894be7ae16648ab41de7d6a4e6f3fd489d11373f9e6a18e7686d268ab0`.

An independent rebuild produced the same 500,906 rows and the same SHA-256
byte for byte. The rebuild check is recorded in
`P5_P6_HANDOFF/p5_p6_roster_rebuild_check.csv`.

P5-to-P6 composite design hash:
`a42aec9c13d4dfd3eb5b7766311f54f1ffb94cfed4a8695ed12bcecc20fb3ece`.

## Approval questions

Please answer each item explicitly.

1. Do you approve U2 reduced, Stage 1 = 2.0 and Stage 2 = 1.5, with the
   inventor-weighted scheme as the 17-cohort headline design?
2. Do you approve the realized coverage, exact balance, and ESS as sufficient
   for the supported-sample ATT?
3. Do you approve treatment of the selection SMD as a scope/bounding
   diagnostic, given 92.83% coverage and the cardinality result?
4. Do you approve retaining Henkel in the deal-70 baseline as a disclosed
   cross-industry scale counterfactual, together with the baseline-plus-eight
   ESS-passing deletion reporting rule and the corrected Henkel-omission
   language?
5. Do you approve excluding both 2000 and 2005 from the like-for-like
   primary-versus-equal-deal comparison?
6. Do you approve keeping the 17 cardinality-recovered inventors separate
   from the primary ATT?
7. Do you approve the certified 500,906-row weighted roster as the immutable
   P5 input to P6?

Approval should freeze P5. Later pre-trend, placebo, or ATT results may
falsify or qualify the design, but they should not silently trigger a new
matching search.

## Files to inspect

Primary audit:
`02_analysis/output/audit/local_match_v2/P5_PRODUCTION_FINAL/finalized/p5_final_production_audit.md`

Coverage and gates:
`02_analysis/output/audit/local_match_v2/P5_PRODUCTION_FINAL/finalized/realized_gate_checks.csv`

Cell diagnostics:
`02_analysis/output/audit/local_match_v2/P5_PRODUCTION_FINAL/finalized/production_cell_diagnostics.csv`

Equal-deal comparison map:
`02_analysis/output/audit/local_match_v2/P5_PRODUCTION_FINAL/finalized/comparison_sample_map.csv`

Governance changes:
`02_analysis/output/audit/local_match_v2/P5_PRODUCTION_FINAL/finalized/specification_search_governance_changes.csv`

Deal-70 refits:
`02_analysis/output/audit/local_match_v2/P5_DEAL70_REFITS/deal70_refit_design_status_all.csv`

Cardinality totals and balance:
`02_analysis/output/audit/local_match_v2/P5_CARDINALITY_FINAL/cardinality_totals.csv`
and
`02_analysis/output/audit/local_match_v2/P5_CARDINALITY_FINAL/cardinality_balance_all.csv`

P5-to-P6 handoff:
`02_analysis/output/audit/local_match_v2/P5_P6_HANDOFF/p5_p6_roster_manifest.csv`
and
`02_analysis/output/audit/local_match_v2/P5_P6_HANDOFF/p5_p6_roster_certification.csv`

Core implementation review scope:

- `17x_lmv2_p5_sparse_technology_cache.R`
- `18f_lmv2_p5_selected_acceleration.R`
- `18j_lmv2_p5_newton_solver.R`
- `18n_lmv2_p5_weight_materialization.R`
- `19i_lmv2_p5_final_production_config.R`
- `19j_run_lmv2_p5_final_production.R`
- `19k_certify_lmv2_p5_final_production.R`
- `19l_finalize_lmv2_p5_final_production.R`
- `19m_run_lmv2_p5_deal70_refits.R`
- `19n_schedule_lmv2_p5_deal70_refits.R`
- `19o_finalize_lmv2_p5_deal70_refits.R`
- `20a_lmv2_p6_selection_sensitivity_config.R`
- `20b_lmv2_cardinality_engine.R`
- `20c_lmv2_cardinality_candidates.R`
- `20d_run_lmv2_p5_cardinality.R`
- `20e_schedule_lmv2_p5_cardinality.R`
- `20f_finalize_lmv2_p5_cardinality.R`
- `20g_build_lmv2_p5_p6_weighted_roster.R`

## P6 status disclosure

A first P6 outcome-panel build was attempted only after the P5 roster
certified. Its independent double-build check stopped before publication.
The only differing ingredient was `lmv2_outcome_inventor_year`: 9,168 rows
differed solely in `sum_pqii_obs` at floating-point magnitudes around
1e-15; identifiers, patent counts, fractional counts, citation sums, and
every other ingredient were identical. The cause was parallel
floating-point summation order in the OECD PQII aggregate, not P5 rows or
weights.

The PQII sum now rounds each source value to 12 decimals, aggregates exact
scaled integers, and restores the scale. A fresh isolated double build
reproduced all ten ingredient tables exactly, including all 1,695,004 rows
of `lmv2_outcome_inventor_year`. No matched outcome panel and no ATT have
been produced. P6 remains paused pending final P5 approval.
