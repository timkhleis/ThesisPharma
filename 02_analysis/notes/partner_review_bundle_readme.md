# Local Match v2 partner review bundle

This bundle is a code-and-results snapshot for methodological review. It
excludes raw data, DuckDB databases, Parquet tables, and reproducible output
directories because they are large and cannot be shared through the repository.

## Review order

1. Read `README.md` and `02_analysis/README.md` for the current design and
   three-worktree lineage.
2. Read `02_analysis/notes/local_match_v2_quantity_results_for_supervisors.md`
   and the supervisor PDF in `results/` for the current full-cohort findings.
3. Review source scripts in `source/foundation/`, `source/p4_p5/`, and
   `source/p6/` in that order.
4. Treat `source/p6/archive/` as historical exploration only.

## Current design in one paragraph

The main analysis estimates the five-year post-acquisition patent-count ATT
for the full pre-deal target-inventor cohort. It uses clean local firm and
IPC4 support, then entropy-balances five annual pre-treatment patent-count and
active-patenting histories plus inventor and firm characteristics. The
acquisition year is excluded from the headline because annual filing data do
not order patents relative to deal completion. Censoring and held-out-year
diagnostics are reported rather than used to select a favorable specification.

The initially retained-inventor analysis is separately balanced and is shown
as a post-treatment-selected, suggestive contrast rather than the headline
causal estimand.
