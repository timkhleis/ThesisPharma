# Phase 2b — Audit missing acquirer groups in deal_map
#
# Outputs CSV diagnostics to:
#   02_analysis/output/audit/deal_map_acquirer_audit/

BASE <- normalizePath("02_analysis", mustWork = TRUE)
DUCKDB <- file.path(BASE, "output", "thesis_foundation.duckdb")
OUT <- file.path(BASE, "output", "audit", "deal_map_acquirer_audit")

.libPaths(c(normalizePath(".r_libs", mustWork = FALSE),
            .libPaths()))

library(DBI)
library(duckdb)

dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

con <- DBI::dbConnect(duckdb::duckdb(), DUCKDB, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

write_csv_base <- function(df, filename) {
  utils::write.csv(df, file.path(OUT, filename), row.names = FALSE, na = "")
}

message("\n=== Deal map acquirer audit ===\n")

current_map <- DBI::dbGetQuery(con, "SELECT * FROM deal_map ORDER BY deal_id")
write_csv_base(current_map, "deal_map_current.csv")

summary <- DBI::dbGetQuery(con, "
SELECT
  COUNT(*) AS n_deals,
  SUM(CASE WHEN has_active_inventors THEN 1 ELSE 0 END) AS n_active_deals,
  SUM(CASE WHEN has_active_inventors AND acquirer_group IS NULL THEN 1 ELSE 0 END)
    AS n_active_missing_acquirer,
  SUM(CASE WHEN has_active_inventors AND acquirer_group IS NULL THEN n_t_stayer ELSE 0 END)
    AS t_stayers_in_missing_acquirer_deals,
  SUM(CASE WHEN has_active_inventors AND acquirer_group IS NULL THEN n_t_leaver ELSE 0 END)
    AS t_leavers_in_missing_acquirer_deals
FROM deal_map
")
print(summary)
write_csv_base(summary, "summary.csv")

missing_deals <- DBI::dbGetQuery(con, "
SELECT
  deal_id,
  target_year,
  target_value,
  target_nmb,
  target_group,
  acquirer_group,
  n_t_stayer,
  n_t_leaver,
  n_active_inventors,
  has_active_inventors
FROM deal_map
WHERE has_active_inventors
  AND acquirer_group IS NULL
ORDER BY n_t_leaver DESC, target_year, target_value
")
write_csv_base(missing_deals, "active_deals_missing_acquirer.csv")

# Benchmark whether T_LEAVER id_group_Tplus points to the known acquirer in
# deals where T_STAYER rows let us infer an acquirer.
leaver_match_benchmark <- DBI::dbGetQuery(con, "
WITH leaver_rows AS (
  SELECT
    dm.deal_id,
    dm.acquirer_group,
    s.codinv,
    s.id_group_Tplus AS leaver_tplus_group
  FROM inventor_status_reference s
  JOIN deal_map dm
    ON s.target_year = dm.target_year
   AND s.target_value = dm.target_value
  WHERE s.type = 'T_LEAVER'
    AND dm.acquirer_group IS NOT NULL
    AND s.id_group_Tplus IS NOT NULL
)
SELECT
  COUNT(*) AS leaver_rows_known_acquirer,
  COUNT(DISTINCT deal_id) AS deals_with_leavers_and_known_acquirer,
  SUM(CASE WHEN leaver_tplus_group = acquirer_group THEN 1 ELSE 0 END)
    AS leaver_rows_matching_acquirer,
  AVG(CASE WHEN leaver_tplus_group = acquirer_group THEN 1.0 ELSE 0.0 END)
    AS share_leaver_rows_matching_acquirer
FROM leaver_rows
")
print(leaver_match_benchmark)
write_csv_base(leaver_match_benchmark, "leaver_tplus_match_benchmark.csv")

leaver_candidate_summary <- DBI::dbGetQuery(con, "
WITH candidates AS (
  SELECT
    dm.deal_id,
    dm.target_year,
    dm.target_value,
    dm.target_group,
    s.id_group_Tplus AS candidate_acquirer_group,
    COUNT(DISTINCT s.codinv) AS n_leaver_inventors
  FROM inventor_status_reference s
  JOIN deal_map dm
    ON s.target_year = dm.target_year
   AND s.target_value = dm.target_value
  WHERE s.type = 'T_LEAVER'
    AND dm.has_active_inventors
    AND dm.acquirer_group IS NULL
    AND s.id_group_Tplus IS NOT NULL
  GROUP BY
    dm.deal_id,
    dm.target_year,
    dm.target_value,
    dm.target_group,
    s.id_group_Tplus
),
ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY deal_id
      ORDER BY n_leaver_inventors DESC, candidate_acquirer_group
    ) AS candidate_rank,
    SUM(n_leaver_inventors) OVER (PARTITION BY deal_id) AS total_leaver_inventors,
    COUNT(*) OVER (PARTITION BY deal_id) AS n_candidate_groups
  FROM candidates
)
SELECT
  deal_id,
  target_year,
  target_value,
  target_group,
  candidate_acquirer_group,
  n_leaver_inventors,
  total_leaver_inventors,
  n_candidate_groups,
  CAST(n_leaver_inventors AS DOUBLE) / NULLIF(total_leaver_inventors, 0)
    AS candidate_share
FROM ranked
WHERE candidate_rank = 1
ORDER BY candidate_share DESC, total_leaver_inventors DESC, deal_id
")
write_csv_base(leaver_candidate_summary, "top_leaver_tplus_candidate_for_missing_deals.csv")

candidate_distribution <- aggregate(
  total_leaver_inventors ~ n_candidate_groups,
  data = leaver_candidate_summary,
  FUN = function(x) c(n_missing_deals = length(x), n_leaver_inventors = sum(x))
)
candidate_distribution <- do.call(
  data.frame,
  candidate_distribution
)
names(candidate_distribution) <- c(
  "n_candidate_groups",
  "n_missing_deals",
  "n_leaver_inventors"
)

write_csv_base(candidate_distribution, "leaver_candidate_distribution.csv")
print(candidate_distribution)

acquirer_side_benchmark <- DBI::dbGetQuery(con, "
WITH acquirer_side_votes AS (
  SELECT
    dm.deal_id,
    dm.acquirer_group,
    s.id_group AS candidate_acquirer_group,
    COUNT(DISTINCT s.codinv) AS n_acquirer_side_inventors,
    ROW_NUMBER() OVER (
      PARTITION BY dm.deal_id
      ORDER BY COUNT(DISTINCT s.codinv) DESC, s.id_group
    ) AS rk
  FROM deal_map dm
  JOIN inventor_status_reference s
    ON dm.target_year = s.acqui_year
   AND dm.target_value = s.acqui_value
  WHERE dm.acquirer_group IS NOT NULL
    AND s.type IN ('A_STAYER', 'A_LEAVER')
    AND s.id_group IS NOT NULL
  GROUP BY dm.deal_id, dm.acquirer_group, s.id_group
)
SELECT
  COUNT(*) AS known_acquirer_deals_with_acquirer_side_rows,
  SUM(CASE WHEN candidate_acquirer_group = acquirer_group THEN 1 ELSE 0 END)
    AS top_candidate_matches_known_acquirer,
  AVG(CASE WHEN candidate_acquirer_group = acquirer_group THEN 1.0 ELSE 0.0 END)
    AS share_top_candidate_matches_known_acquirer
FROM acquirer_side_votes
WHERE rk = 1
")
print(acquirer_side_benchmark)
write_csv_base(acquirer_side_benchmark, "acquirer_side_match_benchmark.csv")

acquirer_side_benchmark_failures <- DBI::dbGetQuery(con, "
WITH acquirer_side_votes AS (
  SELECT
    dm.deal_id,
    dm.target_year,
    dm.target_value,
    dm.target_group,
    dm.acquirer_group,
    s.id_group AS candidate_acquirer_group,
    COUNT(DISTINCT s.codinv) AS n_acquirer_side_inventors,
    ROW_NUMBER() OVER (
      PARTITION BY dm.deal_id
      ORDER BY COUNT(DISTINCT s.codinv) DESC, s.id_group
    ) AS rk
  FROM deal_map dm
  JOIN inventor_status_reference s
    ON dm.target_year = s.acqui_year
   AND dm.target_value = s.acqui_value
  WHERE dm.acquirer_group IS NOT NULL
    AND s.type IN ('A_STAYER', 'A_LEAVER')
    AND s.id_group IS NOT NULL
  GROUP BY
    dm.deal_id,
    dm.target_year,
    dm.target_value,
    dm.target_group,
    dm.acquirer_group,
    s.id_group
)
SELECT *
FROM acquirer_side_votes
WHERE rk = 1
  AND candidate_acquirer_group <> acquirer_group
ORDER BY deal_id
")
write_csv_base(
  acquirer_side_benchmark_failures,
  "acquirer_side_benchmark_failures.csv"
)

acquirer_side_candidates_missing <- DBI::dbGetQuery(con, "
WITH candidates AS (
  SELECT
    dm.deal_id,
    dm.target_year,
    dm.target_value,
    dm.target_group,
    s.id_group AS candidate_acquirer_group,
    COUNT(DISTINCT s.codinv) AS n_acquirer_side_inventors
  FROM deal_map dm
  JOIN inventor_status_reference s
    ON dm.target_year = s.acqui_year
   AND dm.target_value = s.acqui_value
  WHERE dm.has_active_inventors
    AND dm.acquirer_group IS NULL
    AND s.type IN ('A_STAYER', 'A_LEAVER')
    AND s.id_group IS NOT NULL
  GROUP BY
    dm.deal_id,
    dm.target_year,
    dm.target_value,
    dm.target_group,
    s.id_group
),
ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY deal_id
      ORDER BY n_acquirer_side_inventors DESC, candidate_acquirer_group
    ) AS candidate_rank,
    SUM(n_acquirer_side_inventors) OVER (PARTITION BY deal_id)
      AS total_acquirer_side_inventors,
    COUNT(*) OVER (PARTITION BY deal_id) AS n_candidate_groups
  FROM candidates
)
SELECT
  deal_id,
  target_year,
  target_value,
  target_group,
  candidate_acquirer_group,
  n_acquirer_side_inventors,
  total_acquirer_side_inventors,
  n_candidate_groups,
  CAST(n_acquirer_side_inventors AS DOUBLE)
    / NULLIF(total_acquirer_side_inventors, 0) AS candidate_share
FROM ranked
WHERE candidate_rank = 1
ORDER BY candidate_share DESC, total_acquirer_side_inventors DESC, deal_id
")
write_csv_base(
  acquirer_side_candidates_missing,
  "top_acquirer_side_candidate_for_missing_deals.csv"
)

acquirer_side_missing_summary <- data.frame(
  missing_active_deals = nrow(missing_deals),
  missing_deals_with_acquirer_side_candidate =
    length(unique(acquirer_side_candidates_missing$deal_id)),
  missing_deals_without_acquirer_side_candidate =
    nrow(missing_deals) - length(unique(acquirer_side_candidates_missing$deal_id))
)
print(acquirer_side_missing_summary)
write_csv_base(
  acquirer_side_missing_summary,
  "acquirer_side_missing_summary.csv"
)

deal_map_with_candidates <- DBI::dbGetQuery(con, "
WITH group_names_raw AS (
  SELECT id_group AS id_group, \"group\" AS group_name
  FROM inventor_status_reference
  WHERE id_group IS NOT NULL
    AND \"group\" IS NOT NULL
    AND TRIM(\"group\") <> ''
  UNION ALL
  SELECT id_group_Tplus AS id_group, group_Tplus AS group_name
  FROM inventor_status_reference
  WHERE id_group_Tplus IS NOT NULL
    AND group_Tplus IS NOT NULL
    AND TRIM(group_Tplus) <> ''
),
group_name_votes AS (
  SELECT
    id_group,
    group_name,
    COUNT(*) AS n_rows,
    ROW_NUMBER() OVER (
      PARTITION BY id_group
      ORDER BY COUNT(*) DESC, group_name
    ) AS rk
  FROM group_names_raw
  GROUP BY id_group, group_name
),
group_names AS (
  SELECT id_group, group_name
  FROM group_name_votes
  WHERE rk = 1
),
acquirer_side_candidates AS (
  SELECT
    dm.deal_id,
    s.id_group AS candidate_acquirer_group,
    COUNT(DISTINCT s.codinv) AS n_acquirer_side_inventors,
    ROW_NUMBER() OVER (
      PARTITION BY dm.deal_id
      ORDER BY COUNT(DISTINCT s.codinv) DESC, s.id_group
    ) AS rk,
    SUM(COUNT(DISTINCT s.codinv)) OVER (PARTITION BY dm.deal_id)
      AS total_acquirer_side_inventors,
    COUNT(*) OVER (PARTITION BY dm.deal_id) AS n_candidate_groups
  FROM deal_map dm
  JOIN inventor_status_reference s
    ON dm.target_year = s.acqui_year
   AND dm.target_value = s.acqui_value
  WHERE s.type IN ('A_STAYER', 'A_LEAVER')
    AND s.id_group IS NOT NULL
  GROUP BY dm.deal_id, s.id_group
)
SELECT
  dm.*,
  tgt.group_name AS target_group_name,
  known_acq.group_name AS acquirer_group_name,
  ascand.candidate_acquirer_group,
  cand_name.group_name AS candidate_acquirer_group_name,
  ascand.n_acquirer_side_inventors,
  ascand.total_acquirer_side_inventors,
  ascand.n_candidate_groups,
  CAST(ascand.n_acquirer_side_inventors AS DOUBLE)
    / NULLIF(ascand.total_acquirer_side_inventors, 0) AS candidate_share,
  CASE
    WHEN dm.acquirer_group IS NOT NULL THEN dm.acquirer_group
    ELSE ascand.candidate_acquirer_group
  END AS acquirer_group_candidate_filled,
  CASE
    WHEN dm.acquirer_group IS NOT NULL THEN 'from_T_STAYER'
    WHEN ascand.candidate_acquirer_group IS NOT NULL THEN 'from_A_side_candidate'
    ELSE 'unresolved'
  END AS acquirer_source,
  CASE
    WHEN dm.acquirer_group IS NOT NULL THEN TRUE
    WHEN ascand.candidate_acquirer_group IS NOT NULL
      AND ascand.n_candidate_groups = 1 THEN TRUE
    ELSE FALSE
  END AS high_confidence_fill
FROM deal_map dm
LEFT JOIN acquirer_side_candidates ascand
  ON dm.deal_id = ascand.deal_id
 AND ascand.rk = 1
LEFT JOIN group_names tgt
  ON dm.target_group = tgt.id_group
LEFT JOIN group_names known_acq
  ON dm.acquirer_group = known_acq.id_group
LEFT JOIN group_names cand_name
  ON ascand.candidate_acquirer_group = cand_name.id_group
ORDER BY dm.deal_id
")

write_csv_base(deal_map_with_candidates, "deal_map_with_acquirer_candidates.csv")
utils::write.csv(
  deal_map_with_candidates,
  file.path(BASE, "output", "helper_deal_map_with_acquirer_candidates.csv"),
  row.names = FALSE,
  na = ""
)

message("\nWritten diagnostics to: ", OUT)
