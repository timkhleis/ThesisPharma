# Local matching v2: P2 cohort, controls, and power certification

Status: interfaces structurally certified; prospective buffered-stayer power
gate requires design review before P2 can freeze.

## Stable interfaces

P2 creates four deterministic tables and corresponding Parquet files:

- `lmv2_treated_primary`: deal-specific target-company inventors whose latest
  pre-deal affiliation resolves to the target, plus the strict transition route.
- `lmv2_treated_broad`: company-linked sensitivity cohort before the
  latest-affiliation restriction.
- `lmv2_control_firm_eligibility`: never-target groups with no acquirer event
  during the cohort-specific `g-5,...,g+5` window.
- `lmv2_control_inventor_eligibility`: inventors uniquely resolved to an
  eligible control group at their latest pre-event affiliation and with no
  target exposure through `g+5`.

All tables cover cohorts 1994--2010. The build uses `target_year`, keeps the
inventor's earliest target-company exposure, and does not require two observed
patent years. A pre-period recurrent-inventor count is retained only for later
robustness work.

## Certification results

- Primary treated cohort: 28,643 inventors across 339 deals.
- Buffered 1994--2008 cohort: 24,074 inventors across 290 deals.
- Transition route: 351 inventors (1.23% overall); the largest era share is
  2.35%. Both prospective thresholds pass.
- Treated affiliation errors: zero.
- Eligible control inventor-cohort rows: 3,956,193; ambiguous affiliations and
  target-exposure contamination: zero.
- Cassi--Ornaghi reconstruction: 311,358 inventors, 760,047 separation
  observations, 7,104 target stayers, 2,675 target leavers, 643,267 non-target
  stayers, and 107,001 non-target leavers. These equal the published counts.

## Stayer-definition correction and power gate

The provisional audit counted an acquirer patent in event year zero as evidence
of staying. P0 instead defines a stayer using event times 1--5. P2 implements
that rule and treats either an acquirer-group patent or a patent linked directly
to the deal-specific target company as focal-entity evidence.

The corrected counts are:

| Sample | Stayers | Deals | Raw deal ESS | Locked gate |
|---|---:|---:|---:|---|
| 1994--2008 | 2,780 | 149 | 27.39 | Fail: 3,000 / 150 / 20 |
| 1994--2010 | 3,101 | 172 | 32.66 | Pass |

For 1994--2008, the old `t=0,...,5` rule counted 3,656 stayers. Removing event
year zero loses 990 old-only cases; the deal-specific target-company route adds
114 cases not captured by the acquirer-group path. The resulting 2,780 stayers
miss the count floor, and 149 deals miss the deal floor by one. ESS remains
comfortably above its floor.

No treatment effects or outcome comparisons were inspected. The pipeline stops
before P3 pending a design decision. A defensible outcome-blind amendment would
keep absorbing Left on 1994--2008 but use 1994--2010 for the stayer analysis:
the stayer definition needs only observed patents in `t=1,...,5`, and the 2010
cohort's `t=+5` is observed in 2015. This preserves all original power thresholds
and passes them without admitting event year zero. Lowering the thresholds is a
less attractive alternative.

## Reproduction

Run `02_analysis/R/15g_run_lmv2_p2.R`. It performs two complete builds, compares
logical interface hashes, runs independent certification, and writes the P2
manifest and audit CSVs under `02_analysis/output/audit/local_match_v2/P2`.
