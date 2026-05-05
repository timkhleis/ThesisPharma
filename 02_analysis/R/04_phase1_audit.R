# Phase 1 audit — run from project root:
#   Rscript 02_analysis/R/04_phase1_audit.R
#
# Covers:
#   1a  Deal list check (manual — see output note)
#   1b  Deep audit of inventor_status.csv → inventor_status_reference
#   1c  Audit of firm_group.merger_status

BASE    <- normalizePath("02_analysis", mustWork = TRUE)
DATA    <- normalizePath("01_Data/CassiOrnaghiPaperData", mustWork = TRUE)
DUCKDB  <- file.path(BASE, "output", "thesis_foundation.duckdb")
PARQUET <- file.path(BASE, "output", "parquet", "reference")

source(file.path(BASE, "R", "00_utils.R"))
load_packages()
library(duckdb)

dir.create(PARQUET, recursive = TRUE, showWarnings = FALSE)

banner <- function(x) message("\n", strrep("=", 60), "\n  ", x, "\n", strrep("=", 60))
section <- function(x) message("\n--- ", x, " ---")

# ── connect ──────────────────────────────────────────────────────────────────
drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, DUCKDB)
on.exit({ DBI::dbDisconnect(con, shutdown = TRUE) }, add = TRUE)


# ════════════════════════════════════════════════════════════════════════════
banner("PHASE 1a — DEAL LIST CHECK")
# ════════════════════════════════════════════════════════════════════════════

message(
  "\nManual check required before coding:\n",
  "  Does Prof. Cassi have a deal-level file with:\n",
  "    (target_group_id, acquirer_group_id, deal_year, deal_value)?\n\n",
  "Files found in 01_Data/CassiOrnaghiPaperData/:\n",
  paste(" ", list.files(DATA), collapse = "\n"), "\n\n",
  ">> No obvious explicit deal-level file found in this directory.\n",
  ">> Proceeding with extraction from inventor_status.csv (Phase 2).\n",
  ">> FLAG: Bring reconstructed deal map to next Prof. Cassi meeting for confirmation."
)


# ════════════════════════════════════════════════════════════════════════════
banner("PHASE 1b — INVENTOR_STATUS.CSV AUDIT")
# ════════════════════════════════════════════════════════════════════════════

section("Loading inventor_status.csv")
inv_status_path <- file.path(DATA, "inventor_status.csv")
inv_status <- readr::read_csv(
  inv_status_path,
  locale = readr::locale(encoding = "windows-1252"),
  show_col_types = FALSE,
  progress = FALSE
)
message("Rows: ", nrow(inv_status), "  Cols: ", ncol(inv_status))
message("Columns: ", paste(names(inv_status), collapse = ", "))


# ── write to DuckDB and parquet ───────────────────────────────────────────
section("Writing to DuckDB as inventor_status_reference")
DBI::dbWriteTable(con, "inventor_status_reference", inv_status, overwrite = TRUE)

parquet_file <- file.path(PARQUET, "inventor_status_reference.parquet")
parquet_sql  <- gsub("\\\\", "/", parquet_file)
DBI::dbExecute(
  con,
  sprintf("COPY inventor_status_reference TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)", parquet_sql)
)
message("Written: ", parquet_file)


# ── audit queries ─────────────────────────────────────────────────────────
section("1. Row counts by type")
print(DBI::dbGetQuery(con,
  "SELECT type, COUNT(*) AS n_rows
   FROM inventor_status_reference
   GROUP BY type ORDER BY n_rows DESC"
))

section("2. (codinv, year) uniqueness — duplicates within active spell rows")
dups <- DBI::dbGetQuery(con,
  "SELECT codinv, year, COUNT(*) AS n
   FROM inventor_status_reference
   WHERE type != 'last year'
   GROUP BY codinv, year HAVING n > 1"
)
message("Duplicate (codinv, year) pairs (excl. sentinel rows): ", nrow(dups))
if (nrow(dups) > 0) print(head(dups, 20))

section("3. Unique T_STAYER inventors")
print(DBI::dbGetQuery(con,
  "SELECT COUNT(DISTINCT codinv) AS unique_t_stayer_inventors
   FROM inventor_status_reference
   WHERE type = 'T_STAYER'"
))

section("4. Multi-exposure inventors — T_STAYER in more than one deal")
multi <- DBI::dbGetQuery(con,
  "WITH t_stayer_deals AS (
     SELECT DISTINCT
       codinv,
       id_group,
       id_group_tplus,
       target_year,
       target_value
     FROM inventor_status_reference
     WHERE type = 'T_STAYER'
       AND target_year IS NOT NULL
   )
   SELECT
     codinv,
     COUNT(*) AS n_deals,
     COUNT(DISTINCT target_year) AS n_distinct_target_years
   FROM t_stayer_deals
   GROUP BY codinv HAVING n_deals > 1
   ORDER BY n_deals DESC, codinv"
)
message("Inventors with >1 T_STAYER deal exposure: ", nrow(multi))
if (nrow(multi) > 0) print(head(multi, 20))

section("5. Group table coverage for T_STAYER target and acquirer groups")
print(DBI::dbGetQuery(con,
  "SELECT
     COUNT(DISTINCT s.id_group)       AS t_stayer_target_groups,
     COUNT(DISTINCT gt.id_group)      AS matched_target_groups,
     COUNT(DISTINCT s.id_group_tplus) AS t_stayer_acquirer_groups,
     COUNT(DISTINCT ga.id_group)      AS matched_acquirer_groups
   FROM inventor_status_reference s
   LEFT JOIN \"group\" gt ON s.id_group = gt.id_group
   LEFT JOIN \"group\" ga ON s.id_group_tplus = ga.id_group
   WHERE s.type = 'T_STAYER'"
))

section("6. id_group_Tplus coverage — NULLs in T_STAYER rows")
print(DBI::dbGetQuery(con,
  "SELECT
     COUNT(*)                                      AS total_t_stayer_rows,
     COUNT(id_group_tplus)                         AS has_acquirer_group,
     COUNT(*) - COUNT(id_group_tplus)              AS missing_acquirer_group,
     COUNT(CASE WHEN id_group = id_group_tplus
                THEN 1 END)                        AS same_target_acquirer
   FROM inventor_status_reference
   WHERE type = 'T_STAYER'"
))

section("7. Year range by type (sentinel row structure)")
print(DBI::dbGetQuery(con,
  "SELECT type,
     MIN(year) AS min_year,
     MAX(year) AS max_year,
     COUNT(*) AS n_rows
   FROM inventor_status_reference
   GROUP BY type ORDER BY n_rows DESC"
))

section("8. target_year distribution for T_STAYER")
print(DBI::dbGetQuery(con,
  "SELECT target_year, COUNT(DISTINCT codinv) AS n_inventors
   FROM inventor_status_reference
   WHERE type = 'T_STAYER'
   GROUP BY target_year ORDER BY target_year"
))

section("9. d1-d26 deal-time dummies — what values do they take?")
d_cols <- paste0("d", 1:26)
d_present <- d_cols[d_cols %in% tolower(names(inv_status))]
if (length(d_present) == 0) {
  message("NOTE: d1-d26 columns not found — may have been renamed on load. Checking actual column names...")
  message(paste(names(inv_status)[grepl("^d\\d+$", names(inv_status))], collapse = ", "))
} else {
  sample_d <- DBI::dbGetQuery(con,
    sprintf(
      "SELECT %s
       FROM inventor_status_reference
       WHERE type = 'T_STAYER'
       LIMIT 5",
      paste(d_present[1:min(5, length(d_present))], collapse = ", ")
    )
  )
  message("Sample d1-d5 values for T_STAYER rows:")
  print(sample_d)

  # Check which d column is non-zero for each T_STAYER row.
  nonzero_check <- DBI::dbGetQuery(con, paste0(
    "SELECT CASE ",
    paste(sprintf("WHEN %s = 1 THEN %d", d_present, seq_along(d_present)), collapse = " "),
    " END AS active_d_position, COUNT(*) AS n
     FROM inventor_status_reference
     WHERE type = 'T_STAYER'
     GROUP BY active_d_position ORDER BY active_d_position"
  ))
  message("Non-zero d column positions for T_STAYER rows:")
  print(nonzero_check)

  event_time_check <- DBI::dbGetQuery(con, paste0(
    "SELECT
       year - target_year AS event_time,
       CASE ",
       paste(sprintf("WHEN %s = 1 THEN %d", d_present, seq_along(d_present)), collapse = " "),
       " END AS active_d_position,
       COUNT(*) AS n
     FROM inventor_status_reference
     WHERE type = 'T_STAYER'
       AND target_year IS NOT NULL
     GROUP BY event_time, active_d_position
     ORDER BY event_time, active_d_position"
  ))
  message("Cross-tab of calendar event time (year - target_year) and active d position:")
  print(event_time_check)
}

section("10. target_value range and big-deal split in T_STAYER")
print(DBI::dbGetQuery(con,
  "WITH deals AS (
     SELECT DISTINCT
       id_group,
       id_group_tplus,
       target_year,
       target_value
     FROM inventor_status_reference
     WHERE type IN ('T_STAYER', 'T_LEAVER')
       AND target_year IS NOT NULL
   )
   SELECT
     COUNT(*) AS n_deals,
     MIN(target_value) AS min_deal_value,
     MAX(target_value) AS max_deal_value,
     MEDIAN(target_value) AS median_deal_value,
     SUM(CASE WHEN target_value > 5000000 THEN 1 ELSE 0 END) AS n_big_deals
   FROM deals"
))

section("11. acqui_year vs target_year gap")
print(DBI::dbGetQuery(con,
  "SELECT
     acqui_year - target_year AS year_gap,
     COUNT(DISTINCT codinv)  AS n_inventors
   FROM inventor_status_reference
   WHERE type = 'T_STAYER' AND acqui_year IS NOT NULL AND target_year IS NOT NULL
   GROUP BY year_gap ORDER BY year_gap"
))


# ════════════════════════════════════════════════════════════════════════════
banner("PHASE 1c — FIRM_GROUP.MERGER_STATUS AUDIT")
# ════════════════════════════════════════════════════════════════════════════

section("Distribution of merger_status in firm_group")
print(DBI::dbGetQuery(con,
  "SELECT merger_status,
     COUNT(*) AS n_rows,
     COUNT(DISTINCT compcod) AS n_firms,
     COUNT(DISTINCT id_group) AS n_groups,
     MIN(year) AS min_year,
     MAX(year) AS max_year
   FROM firm_group
   GROUP BY merger_status ORDER BY n_rows DESC"
))

section("Target-flagged firms: year distribution")
print(DBI::dbGetQuery(con,
  "SELECT year, COUNT(DISTINCT compcod) AS n_target_firms
   FROM firm_group
   WHERE merger_status = 'target'
   GROUP BY year ORDER BY year"
))

section("Cross-check: target firms in firm_group vs T_STAYER id_groups")
print(DBI::dbGetQuery(con,
  "WITH firm_group_targets AS (
     SELECT DISTINCT id_group, compcod
     FROM firm_group
     WHERE merger_status = 'target'
   ),
   t_stayer_groups AS (
     SELECT DISTINCT id_group
     FROM inventor_status_reference
     WHERE type = 'T_STAYER'
   )
   SELECT
     (SELECT COUNT(DISTINCT compcod) FROM firm_group_targets) AS target_compcod_in_firm_group,
     (SELECT COUNT(DISTINCT id_group) FROM firm_group_targets) AS target_groups_in_firm_group,
     (SELECT COUNT(DISTINCT id_group) FROM t_stayer_groups) AS t_stayer_id_groups_in_inv_status,
     (SELECT COUNT(DISTINCT f.id_group)
      FROM firm_group_targets f
      INNER JOIN t_stayer_groups s ON f.id_group = s.id_group) AS overlapping_target_groups,
     (SELECT COUNT(DISTINCT s.id_group)
      FROM t_stayer_groups s
      LEFT JOIN firm_group_targets f ON s.id_group = f.id_group
      WHERE f.id_group IS NULL) AS t_stayer_groups_not_target_flagged"
))

message("\n", strrep("=", 60))
message("Phase 1 audit complete.")
message("Review output above before proceeding to Phase 2 (deal map extraction).")
message(strrep("=", 60), "\n")
