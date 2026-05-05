# Phase 2 — Deal map extraction
# Run from project root:
#   Rscript 02_analysis/R/05_build_deal_map.R
#
# Output:
#   DuckDB table : deal_map
#   Parquet      : 02_analysis/output/parquet/helper/deal_map.parquet
#
# Grain: one row per merger_list deal (513 total).
#   380 deals have active T_STAYER/T_LEAVER rows (has_active_inventors = TRUE).
#   133 are sentinel-only: active target-side counts are zero.
#
# Acquirer inference — two independent signals, both carried in output:
#
#   acquirer_group_from_stayers   T_STAYER dominant id_group_Tplus vote.
#                                 Most reliable source; covers 288 active deals.
#
#   acquirer_group_from_a_side    Dominant id_group from A_STAYER/A_LEAVER rows
#                                 matched on (acqui_year, acqui_value) = (target_year, target_value).
#                                 96.3% agreement with T_STAYER signal on deals where both exist.
#                                 Covers 53 additional active deals where T_STAYER signal is absent.
#                                 39 active deals remain unresolved by either signal.
#
#   acquirer_group_final          Best estimate: prefer T_STAYER; fall back to A-side.
#                                 On the 7 conflict cases, T_STAYER wins.
#
#   acquirer_source               Provenance: 'T_STAYER' | 'A_SIDE' | 'BOTH_AGREE' |
#                                             'CONFLICT'  | 'MISSING'
#
# T_LEAVER id_group_Tplus is NOT used — it is the leaver's next employer (0.2% match
# rate against known acquirers), not the acquiring firm.
#
# All provisional A-side fills should be reviewed with Prof. Cassi before locking DealSim.

BASE    <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB  <- file.path(BASE, "output", "thesis_foundation.duckdb")
PARQUET <- file.path(BASE, "output", "parquet", "helper")

source(file.path(BASE, "R", "00_utils.R"))
load_packages()
library(duckdb)
dir.create(PARQUET, recursive = TRUE, showWarnings = FALSE)

banner  <- function(x) message("\n", strrep("=", 60), "\n  ", x, "\n", strrep("=", 60))
section <- function(x) message("\n--- ", x, " ---")

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, DUCKDB)
on.exit({ DBI::dbDisconnect(con, shutdown = TRUE) }, add = TRUE)

banner("PHASE 2 — DEAL MAP EXTRACTION")


# ── SQL ───────────────────────────────────────────────────────────────────────
# (target_year, target_value) is unique in merger_list and is the bridge into
# inventor_status_reference. deal_id is a study-specific synthetic identifier.
sql_deal_map <- "
WITH merger_list_deals AS (
  SELECT
    ROW_NUMBER() OVER (ORDER BY target_year, target_value) AS deal_id,
    target_year,
    target_value,
    big,
    merger_count
  FROM merger_list
),
target_nmb_lookup AS (
  SELECT
    target_year,
    target_value,
    MIN(CAST(target_nmb AS VARCHAR))              AS target_nmb,
    COUNT(DISTINCT CAST(target_nmb AS VARCHAR))   AS n_target_nmb
  FROM inventor_status_reference
  WHERE target_year  IS NOT NULL
    AND target_value IS NOT NULL
    AND target_nmb   IS NOT NULL
    AND TRIM(CAST(target_nmb AS VARCHAR)) NOT IN ('', '.')
  GROUP BY target_year, target_value
),
-- Signal 1: dominant acquirer from T_STAYER id_group_Tplus
stayer_acquirer_votes AS (
  SELECT
    target_year,
    target_value,
    id_group_Tplus,
    COUNT(DISTINCT codinv)                         AS n_inv,
    ROW_NUMBER() OVER (
      PARTITION BY target_year, target_value
      ORDER BY COUNT(DISTINCT codinv) DESC
    )                                              AS rk
  FROM inventor_status_reference
  WHERE type        = 'T_STAYER'
    AND target_year  IS NOT NULL
    AND target_value IS NOT NULL
    AND id_group_Tplus IS NOT NULL
  GROUP BY target_year, target_value, id_group_Tplus
),
-- Signal 2: dominant acquirer from A_STAYER/A_LEAVER id_group,
-- matched by (acqui_year, acqui_value) = (target_year, target_value).
-- Validated at 96.3% agreement against the T_STAYER signal on 189 benchmark deals.
a_side_acquirer_votes AS (
  SELECT
    acqui_year  AS target_year,
    acqui_value AS target_value,
    id_group,
    COUNT(DISTINCT codinv)                         AS n_inv,
    ROW_NUMBER() OVER (
      PARTITION BY acqui_year, acqui_value
      ORDER BY COUNT(DISTINCT codinv) DESC
    )                                              AS rk
  FROM inventor_status_reference
  WHERE type        IN ('A_STAYER', 'A_LEAVER')
    AND acqui_year   IS NOT NULL
    AND acqui_value  IS NOT NULL
  GROUP BY acqui_year, acqui_value, id_group
),
target_votes AS (
  SELECT
    target_year,
    target_value,
    id_group,
    COUNT(DISTINCT codinv)                         AS n_inv_to_target,
    ROW_NUMBER() OVER (
      PARTITION BY target_year, target_value
      ORDER BY COUNT(DISTINCT codinv) DESC
    )                                              AS rk
  FROM inventor_status_reference
  WHERE type        IN ('T_STAYER', 'T_LEAVER')
    AND target_year  IS NOT NULL
    AND target_value IS NOT NULL
    AND id_group     IS NOT NULL
  GROUP BY target_year, target_value, id_group
),
deal_counts AS (
  SELECT
    target_year,
    target_value,
    COUNT(DISTINCT CASE WHEN type = 'T_STAYER' THEN codinv END) AS n_t_stayer,
    COUNT(DISTINCT CASE WHEN type = 'T_LEAVER' THEN codinv END) AS n_t_leaver,
    COUNT(DISTINCT codinv)                                       AS n_active_inventors
  FROM inventor_status_reference
  WHERE type        IN ('T_STAYER', 'T_LEAVER')
    AND target_year  IS NOT NULL
    AND target_value IS NOT NULL
  GROUP BY target_year, target_value
)
SELECT
  ml.deal_id,
  ml.target_year,
  ml.target_value,
  ml.big,
  ml.merger_count,
  tn.target_nmb,
  COALESCE(tn.n_target_nmb, 0)                                   AS n_target_nmb,
  tv.id_group                                                     AS target_group,
  -- acquirer signal 1: T_STAYER votes
  sa.id_group_Tplus                                               AS acquirer_group_from_stayers,
  -- acquirer signal 2: A-side votes (provisional; review with Prof. Cassi)
  aa.id_group                                                     AS acquirer_group_from_a_side,
  -- provenance flag (determines which signal wins in acquirer_group_final)
  CASE
    WHEN sa.id_group_Tplus IS NOT NULL AND aa.id_group IS NOT NULL
         AND sa.id_group_Tplus  = aa.id_group
         THEN 'BOTH_AGREE'
    WHEN sa.id_group_Tplus IS NOT NULL AND aa.id_group IS NOT NULL
         AND sa.id_group_Tplus != aa.id_group
         AND CAST(sa.id_group_Tplus AS VARCHAR) LIKE '999%'
         THEN 'CONFLICT_PLACEHOLDER'
    WHEN sa.id_group_Tplus IS NOT NULL AND aa.id_group IS NOT NULL
         AND sa.id_group_Tplus != aa.id_group
         THEN 'CONFLICT_REAL'
    WHEN sa.id_group_Tplus IS NOT NULL
         THEN 'T_STAYER'
    WHEN aa.id_group IS NOT NULL
         THEN 'A_SIDE'
    ELSE      'MISSING'
  END                                                             AS acquirer_source,
  -- consolidated best estimate:
  --   BOTH_AGREE / T_STAYER / CONFLICT_REAL  -> T_STAYER signal
  --   A_SIDE / CONFLICT_PLACEHOLDER          -> A-side signal (placeholder T_STAYER yields to real A-side)
  --   MISSING                                -> NULL
  CASE
    WHEN sa.id_group_Tplus IS NOT NULL
         AND NOT (aa.id_group IS NOT NULL
                  AND sa.id_group_Tplus != aa.id_group
                  AND CAST(sa.id_group_Tplus AS VARCHAR) LIKE '999%')
         THEN sa.id_group_Tplus
    WHEN aa.id_group IS NOT NULL
         THEN aa.id_group
    ELSE NULL
  END                                                             AS acquirer_group_final,
  -- TRUE only when the *final* acquirer is a placeholder ID
  CAST(
    CASE WHEN CAST(
      CASE
        WHEN sa.id_group_Tplus IS NOT NULL
             AND NOT (aa.id_group IS NOT NULL
                      AND sa.id_group_Tplus != aa.id_group
                      AND CAST(sa.id_group_Tplus AS VARCHAR) LIKE '999%')
             THEN sa.id_group_Tplus
        WHEN aa.id_group IS NOT NULL THEN aa.id_group
        ELSE NULL
      END AS VARCHAR) LIKE '999%' THEN 1 ELSE 0 END
    AS BOOLEAN)                                                   AS placeholder_acquirer,
  COALESCE(dc.n_t_stayer, 0)                                     AS n_t_stayer,
  COALESCE(dc.n_t_leaver, 0)                                     AS n_t_leaver,
  COALESCE(dc.n_active_inventors, 0)                             AS n_active_inventors,
  CAST(
    CASE WHEN dc.n_active_inventors IS NOT NULL THEN 1 ELSE 0 END
    AS BOOLEAN)                                                   AS has_active_inventors
FROM merger_list_deals ml
LEFT JOIN target_nmb_lookup       tn ON ml.target_year  = tn.target_year
                                    AND ml.target_value = tn.target_value
LEFT JOIN target_votes            tv ON ml.target_year  = tv.target_year
                                    AND ml.target_value = tv.target_value
                                    AND tv.rk = 1
LEFT JOIN stayer_acquirer_votes   sa ON ml.target_year  = sa.target_year
                                    AND ml.target_value = sa.target_value
                                    AND sa.rk = 1
LEFT JOIN a_side_acquirer_votes   aa ON ml.target_year  = aa.target_year
                                    AND ml.target_value = aa.target_value
                                    AND aa.rk = 1
LEFT JOIN deal_counts             dc ON ml.target_year  = dc.target_year
                                    AND ml.target_value = dc.target_value
ORDER BY ml.target_year, ml.target_value
"

section("Extracting deal map")
deal_map <- DBI::dbGetQuery(con, sql_deal_map)
message("Rows returned: ", nrow(deal_map))


# ── Validation ────────────────────────────────────────────────────────────────
section("Validation checks")

total       <- nrow(deal_map)
active      <- sum(deal_map$has_active_inventors)
sentinel    <- sum(!deal_map$has_active_inventors)
placeholder <- sum(deal_map$placeholder_acquirer, na.rm = TRUE)
dup_keys    <- sum(duplicated(deal_map[, c("target_year", "target_value")]))

message(sprintf("Total deals                       : %d  (expected 513)", total))
message(sprintf("Active (T_STAYER/LEAVER)           : %d  (expected ~380)", active))
message(sprintf("Sentinel-only                     : %d  (expected ~133)", sentinel))
message(sprintf("Placeholder acquirer (final)       : %d  (expected 14)", placeholder))
message(sprintf("Deals with no target_nmb           : %d", sum(deal_map$n_target_nmb == 0)))
message(sprintf("Deals with multiple target_nmb     : %d", sum(deal_map$n_target_nmb > 1)))
message(sprintf("Duplicate (target_year, target_value) keys: %d  (expected 0)", dup_keys))

if (total != 513 || dup_keys != 0) {
  stop("Unexpected deal_map shape — review SQL before writing output.")
}

section("Acquirer source breakdown (all 513 deals)")
print(table(deal_map$acquirer_source, useNA = "ifany"))

section("Acquirer source breakdown (active deals only)")
print(table(deal_map$acquirer_source[deal_map$has_active_inventors], useNA = "ifany"))

section("Active deal summary")
active_rows <- deal_map[deal_map$has_active_inventors, ]
message(sprintf("  n_t_stayer total                : %d", sum(active_rows$n_t_stayer)))
message(sprintf("  n_t_leaver total                : %d", sum(active_rows$n_t_leaver)))
message(sprintf("  big deals (active)              : %d", sum(active_rows$big)))
message(sprintf("  acquirer_group_final not NA     : %d", sum(!is.na(active_rows$acquirer_group_final))))
message(sprintf("  acquirer_group_final missing    : %d", sum(is.na(active_rows$acquirer_group_final))))

section("CONFLICT cases — T_STAYER and A-side signals disagree")
conflicts <- deal_map[!is.na(deal_map$acquirer_source) &
                        startsWith(deal_map$acquirer_source, "CONFLICT"), ]
if (nrow(conflicts) > 0) {
  print(conflicts[, c("deal_id", "target_year", "target_value", "big",
                      "acquirer_source",
                      "acquirer_group_from_stayers", "acquirer_group_from_a_side",
                      "acquirer_group_final", "n_t_stayer", "n_t_leaver")],
        row.names = FALSE)
} else {
  message("  No conflicts.")
}

section("Cohort (treatment year) distribution — active deals")
print(table(deal_map$target_year[deal_map$has_active_inventors]))


# ── Write to DuckDB ───────────────────────────────────────────────────────────
section("Writing deal_map to DuckDB")
DBI::dbWriteTable(con, "deal_map", deal_map, overwrite = TRUE)
message("Table 'deal_map' written.")


# ── Write to Parquet ──────────────────────────────────────────────────────────
section("Writing deal_map to Parquet")
parquet_file <- file.path(PARQUET, "deal_map.parquet")
parquet_sql  <- gsub("\\\\", "/", parquet_file)
DBI::dbExecute(
  con,
  sprintf("COPY deal_map TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)", parquet_sql)
)
message("Written: ", parquet_file)


message("\n", strrep("=", 60))
message("Phase 2 complete. Review CONFLICT cases and A_SIDE fills with Prof. Cassi.")
message("deal_map ready for Phase 3 (stayer reconstruction).")
message(strrep("=", 60), "\n")
