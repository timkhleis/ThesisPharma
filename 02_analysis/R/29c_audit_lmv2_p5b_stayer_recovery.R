# Audit whether the 412 initially retained inventors outside P5c can be
# recovered without relaxing the already-approved clean-U2 support rules.

source(file.path("02_analysis", "R", "00_utils.R"))
source(file.path("02_analysis", "R", "28a_lmv2_p5b_s4_config.R"))
use_project_library()
shared_lib <- file.path(Sys.getenv("USERPROFILE"), "Documents", "Thesis",
                        ".r_libs")
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
if (!requireNamespace("DBI", quietly = TRUE) ||
    !requireNamespace("duckdb", quietly = TRUE)) {
  stop("DBI and duckdb are required")
}

cfg <- lmv2_p5b_s4_config()
out_dir <- file.path(
  cfg$base, "02_analysis", "output", "audit", "local_match_v2",
  "P5B_STAYER_S5_SELECTION_DECOMP")
p4_audit <- file.path(
  cfg$s3$p4_root, "02_analysis", "output", "audit", "local_match_v2")
candidate_glob <- file.path(
  p4_audit, "P5_CARDINALITY_FINAL", "cohort_*", "candidates",
  "cardinality_candidates_*.parquet")
recovered_paths <- file.path(
  p4_audit, "P5_CARDINALITY_FINAL",
  c("cohort_2006/cardinality_weights_2006.parquet",
    "cohort_2007/cardinality_weights_2007.parquet"))
treated_path <- file.path(
  cfg$s3$s2_dir, "treated_retention_partition.parquet")
control_path <- file.path(
  cfg$s3$s2_dir, "control_retained_candidates.parquet")
p5c <- lmv2_p5b_s3_selected_p5c(cfg$s3)
required <- c(treated_path, control_path, p5c$weight_path, recovered_paths)
if (any(!file.exists(required))) {
  stop("Missing recovery-audit input")
}

sql_list <- function(paths) {
  paste0("[", paste(vapply(paths, lmv2_sql_string, character(1)),
                         collapse = ","), "]")
}
con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=8")
DBI::dbExecute(con, sprintf("
  CREATE TEMP TABLE retained_treated AS
  SELECT cohort,deal_id,codinv
  FROM read_parquet(%s)
  WHERE retention_window='t1_t5_primary'
    AND retention_status='initially_retained'
", lmv2_sql_string(treated_path)))
DBI::dbExecute(con, sprintf("
  CREATE TEMP TABLE retained_control AS
  SELECT cohort,codinv,control_group
  FROM read_parquet(%s)
  WHERE retention_window='t1_t5_primary'
", lmv2_sql_string(control_path)))
DBI::dbExecute(con, sprintf("
  CREATE TEMP TABLE p5c_treated AS
  SELECT DISTINCT CAST(cohort AS INTEGER) cohort,
    CAST(deal_id AS BIGINT) deal_id,CAST(codinv AS BIGINT) codinv
  FROM read_parquet(%s) WHERE treated=1
", sql_list(p5c$weight_path)))
DBI::dbExecute(con, "
  CREATE TEMP TABLE excluded_retained AS
  SELECT t.* FROM retained_treated t
  LEFT JOIN p5c_treated p USING(cohort,deal_id,codinv)
  WHERE p.codinv IS NULL
")
DBI::dbExecute(con, sprintf("
  CREATE TEMP TABLE candidate_edges AS
  SELECT CAST(cohort AS INTEGER) cohort,
    CAST(deal_id AS BIGINT) deal_id,
    CAST(treated_codinv AS BIGINT) codinv,
    CAST(control_codinv AS BIGINT) control_codinv,
    CAST(control_group AS BIGINT) control_group
  FROM read_parquet(%s)
", lmv2_sql_string(candidate_glob)))
DBI::dbExecute(con, "
  CREATE TEMP TABLE eligible_edges AS
  SELECT e.*,c.codinv IS NOT NULL retained_control
  FROM candidate_edges e JOIN excluded_retained x
    USING(cohort,deal_id,codinv)
  LEFT JOIN retained_control c
    ON e.cohort=c.cohort AND e.control_codinv=c.codinv
   AND e.control_group=c.control_group
")

cohort <- DBI::dbGetQuery(con, "
  WITH x AS (
    SELECT cohort,COUNT(*) excluded_initially_retained
    FROM excluded_retained GROUP BY cohort
  ), e AS (
    SELECT cohort,COUNT(DISTINCT (deal_id,codinv)) any_clean_u2_candidate,
      COUNT(DISTINCT (deal_id,codinv))
        FILTER(retained_control) any_retained_control_candidate,
      COUNT(*) FILTER(retained_control) retained_control_edges,
      COUNT(DISTINCT control_group)
        FILTER(retained_control) retained_control_firms
    FROM eligible_edges GROUP BY cohort
  )
  SELECT x.*,COALESCE(e.any_clean_u2_candidate,0) any_clean_u2_candidate,
    COALESCE(e.any_retained_control_candidate,0)
      any_retained_control_candidate,
    COALESCE(e.retained_control_edges,0) retained_control_edges,
    COALESCE(e.retained_control_firms,0) retained_control_firms
  FROM x LEFT JOIN e USING(cohort) ORDER BY cohort
")
utils::write.csv(
  cohort, file.path(out_dir, "s5_recovery_feasibility_by_cohort.csv"),
  row.names = FALSE)

summary <- data.frame(
  metric = c(
    "initially_retained_outside_p5c",
    "with_any_clean_u2_cardinality_candidate",
    "with_any_initially_retained_control_candidate",
    "without_initially_retained_control_candidate",
    "maximum_recovery_share_of_412"),
  value = c(
    sum(cohort$excluded_initially_retained),
    sum(cohort$any_clean_u2_candidate),
    sum(cohort$any_retained_control_candidate),
    sum(cohort$excluded_initially_retained) -
      sum(cohort$any_retained_control_candidate),
    sum(cohort$any_retained_control_candidate) /
      sum(cohort$excluded_initially_retained)),
  stringsAsFactors = FALSE)
utils::write.csv(
  summary, file.path(out_dir, "s5_recovery_feasibility_summary.csv"),
  row.names = FALSE)

# Audit the already-frozen full-cohort cardinality solution. This is not yet a
# stayer recovery roster because its matched controls were not required to be
# initially retained.
DBI::dbExecute(con, sprintf("
  CREATE TEMP TABLE recovered AS
  SELECT CAST(cohort AS INTEGER) cohort,CAST(deal_id AS BIGINT) deal_id,
    CAST(matched_treated_codinv AS BIGINT) treated_codinv,
    CAST(codinv AS BIGINT) control_codinv,
    CAST(control_group AS BIGINT) control_group,treated
  FROM read_parquet(%s)
", sql_list(recovered_paths)))
existing <- DBI::dbGetQuery(con, "
  WITH eligible AS (
    SELECT r.*,c.codinv IS NOT NULL retained_control
    FROM recovered r JOIN retained_treated t
      ON r.cohort=t.cohort AND r.deal_id=t.deal_id
     AND r.treated_codinv=t.codinv
    LEFT JOIN retained_control c
      ON r.cohort=c.cohort AND r.control_codinv=c.codinv
     AND r.control_group=c.control_group
  )
  SELECT
    COUNT(DISTINCT (cohort,deal_id,treated_codinv))
      initially_retained_cardinality_recovered,
    COUNT(DISTINCT (cohort,deal_id,treated_codinv))
      FILTER(treated=0 AND retained_control)
      recovered_with_at_least_one_retained_matched_control
  FROM eligible
")
utils::write.csv(
  existing, file.path(out_dir, "s5_existing_cardinality_intersection.csv"),
  row.names = FALSE)

if (summary$value[summary$metric == "initially_retained_outside_p5c"] != 412 ||
    summary$value[
      summary$metric == "with_any_initially_retained_control_candidate"] !=
      22) {
  stop("Recovery audit no longer reproduces the 412/22 interface")
}
message("Stayer recovery feasibility audit complete")
