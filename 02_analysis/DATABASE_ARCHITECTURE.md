# Thesis Database Architecture

This document explains the architecture of the thesis data foundation built in `analysis/R`, what the generated database contains, why the project uses DuckDB and Parquet, and how to work with the outputs safely and efficiently.

## Purpose

The pipeline creates a reproducible analytical data foundation for thesis work on inventors, patents, groups, firms, and merger-related context. It is designed to:

- preserve the raw source tables in a cleaned canonical layer
- add helper and enrichment tables without mutating the raw source logic
- build research-oriented derived tables for analysis
- keep the outputs inspectable both as a database and as file-based columnar data
- support validation, auditing, and reproducibility

The architecture is intentionally layered so that we can distinguish:

- what came directly from source data
- what was added as external enrichment
- what was derived by our own transformation logic

## High-Level Architecture

The data foundation is built by these scripts:

- `analysis/R/01_build_data_foundation.R`
- `analysis/R/02_build_derived_tables.R`
- `analysis/R/run_pipeline.R`
- `analysis/R/03_run_audit.R` for optional audit outputs

At a high level, the pipeline works like this:

1. Read raw `.dta`, `.csv`, and `.txt` files from `Data/`.
2. Clean names and character fields in R.
3. Write cleaned base tables into DuckDB.
4. Export each table to Parquet by layer.
5. Build SQL-based derived tables inside DuckDB.
6. Export derived tables to Parquet.
7. Write metadata inventories and key checks for documentation and validation.
8. Optionally run audit logic to produce quality-review outputs.

## Physical Output Layout

The generated outputs live under `analysis/output/`:

- `analysis/output/thesis_foundation.duckdb`
  - the main DuckDB database
- `analysis/output/parquet/canonical/`
  - cleaned source-of-truth tables
- `analysis/output/parquet/helper/`
  - helper and benchmark tables
- `analysis/output/parquet/enrichment/`
  - external enrichment tables
- `analysis/output/parquet/derived/`
  - analysis-ready tables created from SQL transformations
- `analysis/output/parquet/audit/`
  - audit-specific output files
- `analysis/output/metadata/`
  - inventories, row counts, and key diagnostics
- `analysis/output/audit/`
  - audit summaries and validation results

## Logical Layers

### Canonical layer

The canonical layer contains cleaned versions of the core source tables. These are the foundation of the database and should be treated as the closest thing to the project’s internal source of truth after import and cleaning.

Canonical tables:

- `inventor`
- `patent`
- `patent_inventor`
- `ipc`
- `group`
- `firm`
- `firm_group`

The canonical layer is important because it separates source cleaning from later analytical choices. If a derived result looks wrong, debugging should usually start from the canonical tables.

### Helper layer

The helper layer contains supporting tables used for linkage, validation, and comparison with prior work.

Helper tables:

- `inventor_production`
- `group_production`
- `merger_list`
- `bvd_group_id`

These are not the core patent-inventor-firm foundation, but they are valuable for validation and contextual joins.

### Enrichment layer

The enrichment layer adds information from external datasets that augment the patent records.

Enrichment tables:

- `oecd_quality`

This table contributes measures such as citations, claims, originality, radicalness, renewal, and summary quality indices.

### Derived layer

The derived layer contains analysis-ready tables created inside DuckDB using SQL transformations over the canonical, helper, and enrichment layers.

Derived tables:

- `patent_application`
- `patent_company_link`
- `group_year_status`
- `patent_enriched`
- `patent_inventor_enriched`
- `inventor_group_year`
- `inventor_year`
- `inventor_ipc_year`
- `group_ipc_year`

These are the main tables you will usually inspect first when doing empirical work, because they already encode common joins and summary logic.

### Audit layer

The audit layer is optional and is intended for data-quality review, inventor disambiguation checks, and validation outputs. It is not required for the main build pipeline.

## Current Inventory

The current metadata inventories report the following canonical, helper, and enrichment tables:

| Table | Layer | Rows | Columns | Role |
| --- | --- | ---: | ---: | --- |
| `inventor` | canonical | 1,873,035 | 4 | baseline inventor identities |
| `patent` | canonical | 1,426,861 | 3 | patent application table |
| `patent_inventor` | canonical | 4,313,558 | 2 | inventor-patent bridge |
| `ipc` | canonical | 10,315,887 | 2 | patent classification bridge |
| `group` | canonical | 28,807 | 3 | group dimension |
| `firm` | canonical | 39,709 | 3 | firm dimension |
| `firm_group` | canonical | 1,111,025 | 4 | firm-group-year bridge |
| `inventor_production` | helper | 2,034,982 | 9 | validation benchmark |
| `group_production` | helper | 117,233 | 3 | validation benchmark |
| `merger_list` | helper | 513 | 4 | merger summary helper |
| `bvd_group_id` | helper | 2,716 | 2 | linkage helper |
| `oecd_quality` | enrichment | 4,502,512 | 24 | patent quality enrichment |

The current derived inventory reports:

| Table | Rows | Columns |
| --- | ---: | ---: |
| `group_ipc_year` | 3,296,795 | 4 |
| `group_year_status` | 800,826 | 8 |
| `inventor_group_year` | 2,596,631 | 6 |
| `inventor_ipc_year` | 17,520,017 | 5 |
| `inventor_year` | 4,323,154 | 11 |
| `patent_application` | 1,321,349 | 5 |
| `patent_company_link` | 1,426,861 | 5 |
| `patent_enriched` | 1,321,349 | 34 |
| `patent_inventor_enriched` | 9,475,289 | 12 |

These counts come from:

- `analysis/output/metadata/table_inventory.csv`
- `analysis/output/metadata/derived_inventory.csv`
- `analysis/output/metadata/key_checks.csv`
- `analysis/output/metadata/duckdb_tables.csv`

## Table-by-Table Design

### Core canonical tables

`inventor`

- grain: one row per published inventor identifier
- key: `codinv`
- notes:
  - this is the baseline inventor identity table used in the thesis
  - metadata currently reports duplicate rows on the declared key, so this table should be treated carefully during joins and audit work

`patent`

- grain: one row per patent application and company-year link
- key listed in metadata: `appln_id`
- notes:
  - the metadata reports duplicate key rows for `appln_id`
  - this is expected if one application can appear with multiple company links
  - in practice, this means `patent` behaves more like a patent-company-year linkage table than a pure one-row-per-application table

`patent_inventor`

- grain: many-to-many bridge between patents and inventors
- key: `appln_id`, `codinv`
- notes:
  - this is the main bridge for inventor-level aggregation

`ipc`

- grain: many-to-many bridge between patents and IPC classes
- key listed in metadata: `appln_id`, `clmn`
- notes:
  - after import, `clmn` is renamed to `ipc_code`
  - this is the base for technology-field style aggregation

`group`

- grain: one row per `id_group`
- notes:
  - dimension table for business groups
  - includes `group_type` and `group_name`

`firm`

- grain: one row per `compcod`
- notes:
  - dimension table for firms

`firm_group`

- grain: one row per company-year group assignment
- key: `compcod`, `year`, `id_group`
- notes:
  - this is the main bridge from companies to groups over time
  - essential for merger-status and group-level aggregation

### Helper and enrichment tables

`inventor_production` and `group_production`

- benchmark-style helper tables used mainly for validation
- useful when checking whether our derived productivity logic aligns with prior work or expected patterns

`merger_list`

- summary helper organized by merger year and value bucket

`bvd_group_id`

- linkage helper that maps project group identifiers to BvD identifiers

`oecd_quality`

- patent-level quality enrichment keyed by `appln_id`
- includes forward citations, backward citations, claims, generality, originality, radicalness, renewal, and composite quality indices

## Derived Table Semantics

### `patent_application`

This table collapses the `patent` table to one row per patent application.

It stores:

- `appln_id`
- first observed `patent_year`
- number of source rows in `patent`
- count of linked `compcod`
- concatenated company list

This is the clean patent-level anchor for several downstream tables.

### `patent_company_link`

This table standardizes patent-to-company-to-group relationships.

It joins:

- `patent`
- `firm_group`

It is the backbone for:

- group-level patent aggregation
- merger-status propagation
- linking patent applications to groups

### `group_year_status`

This table summarizes each group-year combination.

It combines:

- firm counts inside the group
- merger status values
- group descriptors
- BvD linkage
- helper group production data

This is a good table for broad firm-group-year inspection.

### `patent_enriched`

This is one of the main analysis tables.

It creates a patent-level enriched record by combining:

- `patent_application`
- company/group summaries
- inventor counts
- IPC counts
- OECD quality measures

This table is ideal when you want a compact patent-level research dataset.

### `patent_inventor_enriched`

This table brings together:

- inventor-patent links
- enriched patent-level information
- inventor identity fields

This is useful when the unit of analysis is close to the inventor-patent relation.

### `inventor_group_year`

This table aggregates inventor activity by year with firm and group context.

It reports:

- number of distinct groups
- number of distinct firms
- concatenated group lists
- merger status values

This is helpful for mobility, group exposure, and yearly organizational context.

### `inventor_year`

This is one of the most important analytical tables in the database.

It provides one row per inventor-year and includes:

- patent counts
- fractional patent counts
- distinct firm counts
- distinct group counts
- first and last career year
- career year index
- inventor name
- inventor country

This is the natural first table for broad inventor-level panel analysis.

### `inventor_ipc_year`

This table adds technology detail to the inventor-year view.

Unit of observation:

- inventor x year x IPC code

This is useful for:

- technology specialization
- inventor diversification
- similarity and relatedness measures

### `group_ipc_year`

This table aggregates patenting by:

- group x year x IPC code

This is useful for:

- corporate technology portfolios
- technological scope at the group-year level

## Why DuckDB

DuckDB is a strong fit for this project for several reasons.

### 1. It is ideal for analytical workloads on a single machine

This project is not a high-concurrency production web application. It is a research pipeline with large, read-heavy joins and aggregations. DuckDB is designed exactly for this style of local analytical processing.

### 2. It handles datasets that are large for R data frames

Some of the generated tables are very large:

- `inventor_ipc_year` has over 17.5 million rows
- `ipc` has over 10.3 million rows
- `patent_inventor_enriched` has over 9.4 million rows

Keeping all of this as in-memory R objects would be clumsy, fragile, and slow. DuckDB lets us query large tables lazily and only pull the slices we need.

### 3. SQL is a very transparent transformation language

The derived layer is built in readable SQL statements. That makes the logic:

- easier to audit
- easier to reason about
- easier to validate step by step
- less opaque than deeply nested in-memory transformation chains

### 4. It integrates cleanly with R

DuckDB works well through `DBI`, which means:

- we can build with SQL
- inspect through R scripts
- pull only samples into R for visual inspection
- keep the workflow reproducible inside the existing R project

### 5. It produces a single database artifact

`analysis/output/thesis_foundation.duckdb` is a self-contained file that is easy to point tools at, archive, and reopen.

### 6. It keeps the pipeline reproducible

The build scripts regenerate the database from raw sources and transformation logic. That is preferable to relying on manually curated workspace objects in an interactive session.

## Why Parquet

The project writes every layer to Parquet in addition to DuckDB. That choice is valuable for several reasons.

### 1. Parquet is columnar and efficient

Parquet stores data in a format that is compact and fast for analytical reads, especially when only a subset of columns is needed.

### 2. It is interoperable

Parquet is not tied to R or DuckDB. The same files can be read by:

- DuckDB
- R
- Python
- Spark
- many modern data tools

This makes the outputs durable and portable.

### 3. It separates storage from compute

DuckDB is excellent as a query engine, while Parquet is excellent as a portable storage format. Keeping both gives flexibility:

- DuckDB for convenient database-style querying
- Parquet for archival, sharing, and tool-agnostic reuse

### 4. It supports layer-by-layer inspection

Having `canonical`, `helper`, `enrichment`, and `derived` folders in Parquet makes the pipeline outputs easier to inspect and reason about outside the database file.

### 5. It is good for recovery and validation

If the DuckDB file becomes inconvenient to inspect or needs to be rebuilt, the Parquet outputs remain as concrete intermediate artifacts.

## Why Use Both DuckDB and Parquet Together

Using both is not redundant. They solve different problems.

DuckDB gives us:

- SQL execution
- fast local joins and aggregations
- a unified database interface

Parquet gives us:

- portable storage
- file-level transparency
- interoperability beyond one engine

Together they produce a workflow that is both convenient and robust.

## Recommended Usage Patterns

### For broad inspection

Use the interactive helper script:

- `analysis/R/zz_tim_working.r`

Recommended first commands:

```r
source("analysis/R/zz_tim_working.r")
database_overview()
plot_table_sizes()
inspect_table("inventor_year", n = 1000)
inspect_table("patent_enriched", n = 1000)
inspect_table("group_year_status", n = 1000)
```

This sequence gives:

- a database-wide overview
- a visual sense of which tables are largest
- a sample-based spreadsheet-like inspection of the main analytical tables

### For browser-based visual inspection

If DuckDB CLI is installed locally, you can inspect the full database in the DuckDB browser UI:

```powershell
duckdb -ui analysis/output/thesis_foundation.duckdb
```

This is often the fastest way to:

- browse all available tables
- inspect schemas
- preview rows visually
- run ad hoc SQL against the built database

In practice, this is a very good first-stop inspection workflow, while the R helpers remain more useful once you want to pull specific subsets into analysis code.

### For scripted inspection

Use:

- `analysis/R/inspect_data.R`

Example:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' analysis\R\inspect_data.R inventor_year patent_enriched
```

This is useful for reproducible console inspection and quick checks.

### For rebuilding the full database

Run:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' analysis\R\run_pipeline.R
```

This runs:

- `01_build_data_foundation.R`
- `02_build_derived_tables.R`

### For audit workflows

Run:

```powershell
& 'C:\Program Files\R\R-4.5.1\bin\Rscript.exe' analysis\R\03_run_audit.R
```

## Practical Guidance for Analysis

As a rule of thumb:

- start with `inventor_year` for inventor panel analysis
- start with `patent_enriched` for patent-level analysis
- start with `group_year_status` for group-year analysis
- use `inventor_ipc_year` or `group_ipc_year` when technology composition matters
- go back to canonical tables when debugging joins or checking source consistency

For joins:

- use `appln_id` as the patent-level anchor
- use `codinv` for inventor-level work
- use `compcod` for firm-level work
- use `id_group` for group-level work
- pay attention to the actual grain of each table before joining

## Important Caveats

### Declared keys versus actual grain

The metadata currently shows duplicate key rows in:

- `inventor` on `codinv`
- `patent` on `appln_id`

That does not automatically mean the build is broken. It means the declared key should be interpreted carefully and the actual row grain should be validated against the intended analytical use.

In particular:

- `patent` should not be treated as a pure one-row-per-application table
- `patent_application` is the safer patent-level table when a unique patent record is needed

### Extra tables in DuckDB

The database file may contain manually created or exploratory tables in addition to the scripted pipeline outputs. For example, `duckdb_tables.csv` currently lists `inventor_test2`, which is not created by the main build scripts.

That means:

- not every table in the database is necessarily part of the formal architecture
- the authoritative pipeline outputs are the ones produced by `01_build_data_foundation.R`, `02_build_derived_tables.R`, and the optional audit script

## Architecture Summary

The design follows a simple principle:

- clean sources into a canonical layer
- enrich and validate without overwriting source logic
- derive analysis-ready tables in DuckDB
- export every layer to Parquet
- document the result with metadata inventories

This gives the project:

- reproducibility
- inspectability
- good local performance
- portability across tools
- a clean separation between raw structure and analytical transformations
