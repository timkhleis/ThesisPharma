# Response to Claude Opus: P5 approval conditions

## Decision requested

Please review the three completed conditions below and approve the certified
P5 roster as the immutable input to P6. No matched outcome panel or ATT has
yet been produced.

## 1. Henkel technology diagnostic completed

The concern is confirmed:

| Resolution | Henkel--SmithKline cosine |
|---|---:|
| IPC4 | 0.4284 |
| IPC main group | 0.0437 |
| IPC7 | 0.0209 |

A61K8 represents 88.51% of Henkel's A61K portfolio, while SmithKline
Beecham's A61K portfolio is led by A61K31 (44.29%) and A61K39 (22.29%).
Their IPC4 similarity therefore does not survive finer classification.

Henkel is nevertheless retained in the baseline donor pool. It is uniquely
comparable in firm scale and materially improves effective sample size. This
is now governed and disclosed as a cross-industry scale counterfactual, not
as evidence that Henkel is a close pharmaceutical technology analogue.

The deal-70 reporting rule is:

1. report the baseline ATT with Henkel and the construct-validity caveat;
2. report all eight deletion-refit ATTs that pass the ESS hierarchy; and
3. report Henkel omission as exact-balance but ESS-failing.

## 2. Henkel-deletion language corrected

The review note and governance package no longer call Henkel omission flatly
infeasible. The correct statement is:

> Exact balance is attainable without Henkel, but the solution fails the
> predeclared 0.50 reuse-adjusted ESS gate. Henkel is required for acceptable
> precision under the frozen design, not for balance.

## 3. Roster stability and P6 mismatch resolved

The P5 roster was rebuilt independently. Both builds contain 500,906 rows
and have the identical SHA-256:

`458036894be7ae16648ab41de7d6a4e6f3fd489d11373f9e6a18e7686d268ab0`.

The P6 double-build discrepancy did not involve the roster. Nine of ten
ingredient tables were initially identical. The only difference was
`lmv2_outcome_inventor_year`, where 9,168 rows differed solely in
`sum_pqii_obs` at approximately 1e-15 because parallel floating-point
summation changed addition order. Identifiers, patent counts, fractional
counts, citation sums, and all other ingredients were identical.

The PQII aggregation now rounds each source value to 12 decimals, sums exact
scaled integers, and restores the scale. A fresh isolated double build
reproduced all ten ingredient tables exactly, including all 1,695,004 rows
of the inventor-year ingredient.

## Additional pre-specification completed

The separate estimate for the 17 cardinality-recovered inventors will be
reported with its confidence interval regardless of precision. If too
imprecise to interpret, it will be labelled uninformative rather than
dropped. It will never be appended to the primary entropy ATT.

## Approval requested

The five items already approved by Claude remain unchanged. Please now
confirm:

1. approval of the Henkel-retaining deal-70 baseline under the explicit
   cross-industry scale-counterfactual interpretation and sensitivity rule;
2. approval of the independently reproduced 500,906-row P5 roster as the
   immutable P6 input; and
3. approval to start P6 outcome-panel materialization under the frozen P5
   design.

## Review artifacts

- `02_analysis/notes/local_match_v2_p5_henkel_diagnostic.md`
- `02_analysis/output/audit/local_match_v2/P5_HENKEL_DIAGNOSTIC/`
- `02_analysis/output/audit/local_match_v2/P5_P6_HANDOFF/p5_p6_roster_rebuild_check.csv`
- `02_analysis/output/audit/local_match_v2/P5_PRODUCTION_FINAL/finalized/specification_search_governance_changes.csv`
- P6 double-build audit:
  `02_analysis/output/audit/local_match_v2/P6_DETERMINISM_RECHECK/ingredient_double_build_check.csv`
  in the `lmv2-p6-outcomes` worktree.
