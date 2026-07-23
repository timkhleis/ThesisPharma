# Local matching v2: P6 certified outcome panel

Status: **implementation-ready, synthetic-fixture-verified, not certified on
real data.** After Codex's review found runtime blockers that syntax-only
parsing could not detect, a repair round fixed all seven findings and the
synthetic fixture now executes green against an in-memory database
(hand-built data only): 16/16 outcome assertions, 19/19 roster-validation
tests, restart-skip honored, stale-provenance shards refused. No thesis data
was provisioned or opened; no ingredient tables, treated fixture, or
production certification ran. Those wait until P3–P5a are complete.

## Repair round (post-review)

1. Ambiguous `codinv` joins in the materializer replaced with explicit
   qualified joins (the immediate runtime failure).
2. `lmv2_quote_qualified` quotes schema-qualified names part-by-part; the
   double-build checksum works on `p6_build_a.table` names.
3. The runner reuses the repository-level `.r_libs` from the nested worktree
   (same pattern as P3's `16a`).
4. Production runs now REQUIRE `--roster`; `--fixture-only` is the explicit
   pre-P5 mode, labeled in the manifest and pass message. A supplied
   production roster is materialized BEFORE certification and passes through
   every shard-level family (grain, stamped rows, Left monotonicity/onset,
   zero-vs-missing, exact P2 stayer equality for treated rows).
5. Shard stamps now include the materializer source hash, a strong roster
   hash (rows + hash-sum + hash-XOR), and the output's row count and parquet
   MD5; a stamped shard whose parquet no longer matches its checksum is
   refused, never skipped.
6. Undefined Left is **NA and audited** via `left_defined`, never coded 1.
7. Roster validation catches NULL keys explicitly, and production mode
   requires every treated row to carry a complete three-control matched set;
   the treated fixture uses a separate `treated_fixture` validation mode.

Additional: `tech_drift = 1 − tech_similarity` stored alongside the
similarity; weights are described as certified P5a weights (no balancing
rule assumed); the matched-control firm-exit diagnostic
(`control_firm_exits_before_g_plus_5`) is attached to control rows in the
panel from the frozen P2 interface.

Base commit: `5d602a7` (frozen P2). Branch: `claude/lmv2-p6-outcomes`.
Authority order: approved amendments (`local_match_v2_amendments.md`) >
frozen P0 lock (`15a`, hash `cabba2c5…21c52`).

## Files

| File | Role |
|---|---|
| `18a_lmv2_outcome_config.R` | P6 config, roster contract, zero-vs-missing SQL generator, provenance helpers (P1 hash-sum/XOR, P2 serialized SHA-256, file SHA-256, robust df comparison) |
| `18b_build_lmv2_outcome_ingredients.R` | Roster-independent ingredient builder into an isolated schema; OECD coverage audits; linkage-decline decomposition |
| `18c_materialize_lmv2_outcome_panel.R` | Roster validation (row-level + matched-set), treated fixture derivation, shard provenance stamps, cohort-sharded materializer |
| `18d_certify_lmv2_outcomes.R` | P2 interface gate, P1 upstream checksums, synthetic fixture with hand-derivable expectations, roster-validation unit tests, full certification suite |
| `18e_run_lmv2_p6.R` | Runner: explicit-path provenance gate, isolated double build, publish, fixtures, certification, manifest |

All five files are function libraries or argument-gated scripts: sourcing
`18a`–`18d` executes nothing; `18e` aborts immediately unless `--db=`,
`--p2-manifest=`, and `--audit-dir=` are supplied explicitly.

## External provisioning (operator command, not the runner)

The runner never locates or copies data itself. Before execution, the
operator copies the frozen post-P2 database and P2 audit directory into this
worktree (one-time, outside R):

```powershell
Copy-Item <frozen>/02_analysis/output/thesis_foundation.duckdb `
  .worktrees/lmv2-p6-outcomes/02_analysis/output/
Copy-Item -Recurse <frozen>/02_analysis/output/audit/local_match_v2/P2 `
  .worktrees/lmv2-p6-outcomes/02_analysis/output/audit/local_match_v2/
```

The runner's first step then validates all five P2 interfaces
(`lmv2_treated_primary`, `lmv2_treated_broad`,
`lmv2_treated_unique_affiliation_robustness`, `lmv2_control_firm_eligibility`,
`lmv2_control_inventor_eligibility`) against `p2_interface_manifest.csv`
using P2's exact serialized-SHA-256 method, and records P1 hash-sum/XOR
checksums for every consumed foundation table. Both are re-compared after
the build (dual-method; the methods are never unified).

## Ingredients (grains)

| Table | Grain | Purpose |
|---|---|---|
| `lmv2_outcome_inventor_year` | (codinv, year), sparse patent years | counts + OECD non-missing counts and observed sums (citations and PQII separately) |
| `lmv2_outcome_inventor_affiliation_year` | (codinv, year, resolved_group) | **sole source for stayer group-path classification, both arms** |
| `lmv2_inventor_group_patent_year` | (codinv, year, id_group) | **sole source for absorbing Left** (patent-level links; `pcl.year`, as in P2's company path) |
| `lmv2_inventor_target_company_patent_year` | (codinv, deal_id, year) | treated Left/stayer company path (strict bridge incl. promoted deals) |
| `lmv2_inventor_ipc4_year` | (codinv, year, ipc4) | TechDrift vectors, integer patent-count weights |

Restricted to relevant inventors (treated ∪ control-eligible). The unmatched
control universe is never expanded across event years; panels only ever
contain roster rows × 11, asserted per shard.

## Roster contract (frozen interface for P5a)

Columns: `deal_id` BIGINT, `cohort` INTEGER, `arm` ∈ {treated, control},
`codinv` BIGINT, `match_id` BIGINT, `weight` DOUBLE, `status_eligible`
BOOLEAN, `focal_group_1` BIGINT (non-missing), `focal_group_2` BIGINT
(nullable), `use_target_company_path` BOOLEAN (TRUE ⟺ treated).

Weights arrive **entropy-balanced from certified P5 output**; P6 never
recomputes, rebalances, repairs, or renormalizes them. Matched-set rules at
`(deal_id, cohort, match_id)`: exactly three distinct controls, ≥2 distinct
control firms, nonnegative finite weights summing to one within 1e-8, every
control `match_id` referencing a treated row in the same deal and cohort.
Row-level rules and exact failure messages are unit-tested in `18d`.
`status_eligible` is copied from `lmv2_treated_primary` for treated rows and
TRUE for controls (the P2 deal-assignment restriction is not applicable to
control firms); it is required to reproduce
`status_eligible_stayer_first_post_t0_t5` exactly.

## Outcome semantics

- **Patent clock**: application year, always. OECD `filing` is consumed only
  by audit tables; certification asserts the materializer source never
  references it.
- **Zero-vs-missing** (lock: `missing_not_zero`), separately for citations
  (`n_fwd_nonmiss`) and PQII (`n_pqii_nonmiss`):

| Case | complete | observed | scaled | conditional mean |
|---|---|---|---|---|
| patents > 0, all values observed | sum | sum | sum | sum/n |
| patents > 0, partial (0 < n < count) | NA | sum over observed | obs × count/n | obs/n |
| patents > 0, none observed (n = 0) | NA | NA | NA | NA |
| genuine zero-patent year | 0 | 0 | 0 | NA |

- **Active Patenting**: `patent_count > 0` in the current calendar year only;
  never forward-looking.
- **Absorbing Left** (`left_focal`; `left` is a SQL keyword): last
  focal-entity patent year from patent-level links (∪ deal target-company
  links for treated); `1{last_focal < calendar_year}`; absorbing by
  construction; `left_onset` fires at most once; `left_defined = FALSE`
  flags units with no focal patent evidence.
- **Stayer**: replicates P2 semantics verbatim — first post-event
  affiliation year in `[g, g+5]` from resolved affiliations; group path
  `resolved_group ∈ {focal_group_1, focal_group_2}` at that year; company
  path (treated only) via the strict target-company ingredient. t = 0 may
  classify status but is excluded from post-treatment outcome totals at
  estimation. The deliberate semantic split — resolved affiliations for
  stayer status, patent-level links for Left — mirrors P2 exactly on one
  side and the locked Left formula on the other.
- **TechDrift**: stored measure is **cosine similarity** (`tech_similarity`);
  drift = 1 − similarity at analysis time. IPC4 subclass level, integer
  weights, baseline `g−5…g−1`. NA (never 0 or 1) when the baseline is empty
  or the current year has no classified patents.
- `late_tail_flag` marks calendar years ≥ 2014 (patent-layer tail).

## OECD audits (diagnostic only)

Three coverage tables at separate grains (application year; filing year;
filing-minus-application delta histogram) plus the mandatory linkage-decline
decomposition: patent-layer tail vs. linkage failure vs. identifier
availability vs. composition of matched/unmatched patents (inventor counts,
company-link and group coverage; authority prefix available for linked
records only — unlinked-side authority is not present in the thesis patent
layer and is documented as such) vs. OECD-side field missingness among
linked records. Field availability is **not** citation-window completeness:
a non-missing `fwd_cits5` does not prove a fully elapsed five-year window
for late applications; substantive treatment of late-tail citations is
deferred until that metadata question is resolved. No alternative keys, no
automatic record recovery, no design change can result from these audits
without an explicit follow-up decision.

## Certification suite (13 families, dormant)

Grain uniqueness; patent counts vs the P1 spine (full outer join, zero
mismatches); current-year-only Active Patenting; the full zero-vs-missing
matrix on a synthetic fixture plus global no-silent-zero assertions; no
`filing` reference in the materializer; Left weakly increasing / onset ≤ 1;
**exact stayer equality with P2's four columns on the treated fixture**;
panel rows ≡ roster × 11; roster-validation unit tests (15 corruption
cases, exact messages); true double-build determinism (isolated schemas
`p6_build_a`/`p6_build_b` in the working copy plus separate output
locations; publish only on hash equality; restart-skipping never substitutes
for the second build); memory reporting (configured cap recorded as a
setting, DuckDB statistics when available, process peak NA unless reliably
measurable); OECD field availability by filing year; TechDrift unit fixtures
(identical → 1, disjoint → 0, empty baseline → NA); dual-method upstream
integrity before vs after.

## Shard provenance

Every shard stamp records: P0 design hash, P6 design hash, amendments file
SHA-256, all five P2 interface hashes, the ingredient-build hash, and the
order-invariant logical hash of the supplied roster cohort. A shard matching
on design but differing on any field — including the roster hash — is
**refused with an explicit error**, never skipped. Reruns skip only shards
matching the complete stamp, and only when `--allow-restart` is set.

## Expectations (not results)

Ingredients ~5–10 minutes; treated fixture 29,170 × 11 = 320,870 rows;
certification including the double build ~20–30 minutes under the 9 GB
DuckDB cap. To be replaced by measured values at the execution stage.
