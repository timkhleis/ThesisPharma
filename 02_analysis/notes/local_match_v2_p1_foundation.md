# Local matching v2: P1 certified inventor-year foundation

Status: **PASS**, pending package review. Design hash: `cabba2c523bf5abdeb44ba28e61dec2eeaedf5c9df8aa6fba1b7087361521c52`.

## Repair

The old `inventor_year` first aggregated inventor--application records and then joined the non-unique raw inventor dimension. That final join multiplied analytical rows without changing the values stored on each duplicated row. The repair:

1. constructs distinct inventor--application pairs before all inventor-derived aggregations;
2. removes inventor metadata from the analytical inventor-year table;
3. stores metadata in a separate, deterministic one-row-per-inventor `inventor_lookup`, with source-conflict counts retained as diagnostics;
4. uses fixed-decimal summation for fractional contributions so the logical table is reproducible under parallel execution; and
5. preserves application-year timing.

The same unique lookup fixes the duplicated `patent_inventor_enriched` table. Pipeline paths were updated from the obsolete `analysis/Data` layout to `02_analysis/01_Data`.

## Before and after

| Metric | Before repair | After repair |
|---|---:|---:|
| `inventor_year` rows | 4,323,154 | 2,596,631 |
| unique inventor-years | 2,596,631 | 2,596,631 |
| duplicated analytical rows | 1,726,523 | 0 |
| sum of annual patent counts | 9,475,289 | 4,313,558 |
| distinct inventor--application pairs | 4,313,558 | 4,313,558 |

The old aggregate patent total was therefore inflated by the metadata join. The repaired sum agrees exactly with the distinct inventor--application spine.

## Certification

Fourteen acceptance checks passed in each of two complete rebuilds:

- zero duplicate inventor-years and inventor-group-years;
- zero duplicate source inventor--application pairs and zero conflicting application years;
- exact annual patent-count agreement across 2,596,631 inventor-years;
- maximum fractional-count gap from an independent patent-level calculation of `2.13e-14`, below the `1e-12` tolerance;
- zero career-endpoint or firm/group-affiliation-count mismatches;
- complete, unique inventor metadata lookup;
- exactly 4,313,558 unique rows in `patent_inventor_enriched`; and
- zero mismatches in five-year patent stock, early/recent trajectory components, or last-pre-patent year for the locked treated population.

Logical checksums for `inventor_year`, `inventor_lookup`, and `patent_inventor_enriched` reproduce exactly across the two builds. Physical Parquet MD5 values are not a gate because unordered relational-table exports may differ in row order while containing the same rows; the order-invariant logical hashes are the prospective reproducibility test.

The raw inventor table contains conflicting metadata for some published inventor identifiers: 45,758 name conflicts, 10,330 country conflicts, and 207,952 alternative `codinv2` conflicts. These values are retained in the lookup audit but are not matching covariates or analytical identifiers.

## Interface and downstream status

- Certified analytical grain: `inventor_year(codinv, year)`.
- Metadata interface: `inventor_lookup(codinv)`.
- Application spine: distinct `(codinv, appln_id)` pairs joined to `patent_application.patent_year`.
- Existing downstream cohort, matching, outcome, and result tables in the copied database must be treated as stale until rebuilt by later packages. P1 certifies only the foundation layer.

P2 must now rebuild and report the buffered stayer count, deals with stayers, and raw deal ESS prominently against the locked floors of 3,000, 150, and 20.
