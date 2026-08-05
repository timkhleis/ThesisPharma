# Build and estimate the pooled-window TechDrift amendment. This script uses
# the frozen stayer roster and weights without modifying the certified P6
# event panel.

source(file.path("02_analysis", "R", "50a_lmv2_techdrift_window_config.R"))
config <- lmv2_techdrift_window_config()
source(file.path("02_analysis", "R", "00_utils.R"))
use_project_library()
shared_lib <- file.path(
  Sys.getenv("USERPROFILE"), "Documents", "Thesis", ".r_libs")
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))

required_packages <- c(
  "DBI", "duckdb", "digest", "fixest", "fwildclusterboot", "dqrng")
for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

BASE <- normalizePath(
  file.path(config$p6_root,"02_analysis"),winslash="/",mustWork=TRUE)
source(file.path(config$p6_root, "02_analysis", "R",
                 "15a_lmv2_design_lock.R"))
source(file.path(config$p6_root, "02_analysis", "R",
                 "18a_lmv2_outcome_config.R"))
source(file.path(config$p6_root, "02_analysis", "R",
                 "19a_lmv2_p6_estimation_config.R"))
source(file.path(config$p6_root, "02_analysis", "R",
                 "19b_lmv2_p6_estimation_core.R"))
LMV2_P6_ESTIMATION$inference$seed <- config$seed
LMV2_P6_ESTIMATION$execution$threads <- 1L

dir.create(config$output_dir, recursive = TRUE, showWarnings = FALSE)
write_csv <- function(x, name) {
  utils::write.csv(
    x, file.path(config$output_dir, name), row.names = FALSE, na = "")
}

panel_files <- sort(list.files(
  config$panel_dir,
  pattern = "^lmv2_event_panel_c[0-9]+[.]parquet$",
  full.names = TRUE))
stamp_files <- sort(list.files(
  config$panel_dir,
  pattern = "^lmv2_event_panel_c[0-9]+_stamp[.]csv$",
  full.names = TRUE))
required_inputs <- c(
  config$foundation_db, panel_files, stamp_files, config$panel_manifest,
  config$weights, config$weights_manifest, config$weights_certification,
  config$amendment_note)
missing_inputs <- required_inputs[!file.exists(required_inputs)]
if (length(panel_files) != length(config$cohorts) || length(missing_inputs)) {
  stop("Missing TechDrift amendment inputs: ",
       paste(missing_inputs, collapse = ", "))
}

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "SET threads=8")
DBI::dbExecute(con, "SET memory_limit='6GB'")
DBI::dbExecute(con, sprintf(
  "ATTACH %s AS foundation (READ_ONLY)",
  lmv2_sql_string(config$foundation_db)))

input_checks <- lmv2_validate_estimation_inputs(
  con, panel_files, stamp_files, config$panel_manifest)
if (!isTRUE(input_checks$pass[[1L]])) {
  stop("The certified P6 panel failed validation")
}
write_csv(input_checks, "techdrift_input_checks.csv")

panel_sql <- lmv2_panel_sql(panel_files)
DBI::dbExecute(con, sprintf("\n  CREATE TEMP TABLE td_weights AS\n  SELECT *\n  FROM read_parquet(%s)\n  WHERE spec=%s\n", lmv2_sql_string(config$weights),
  lmv2_sql_string(config$primary_spec)))
DBI::dbExecute(con, sprintf("\n  CREATE TEMP TABLE td_base_units AS\n  SELECT\n    roster_row_id, CAST(deal_id AS INTEGER) deal_id,\n    CAST(cohort AS INTEGER) cohort, arm, CAST(codinv AS BIGINT) codinv,\n    CAST(focal_group_1 AS BIGINT) focal_group_1, multi_exposure_inventor\n  FROM %s\n  WHERE event_time=-1\n", panel_sql))
DBI::dbExecute(con, "
  CREATE TEMP TABLE td_unit_map AS
  WITH treated_map AS (
    SELECT b.roster_row_id, w.final_weight
    FROM td_weights w
    JOIN td_base_units b
      ON w.cohort=b.cohort AND w.deal_id=b.deal_id
     AND w.codinv=b.codinv AND b.arm='treated'
    WHERE w.treated=1
  ), control_map AS (
    SELECT b.roster_row_id, w.final_weight
    FROM td_weights w
    JOIN td_base_units b
      ON w.cohort=b.cohort AND w.deal_id=b.deal_id
     AND w.codinv=b.codinv AND w.control_group=b.focal_group_1
     AND b.arm='control'
    WHERE w.treated=0
  )
  SELECT * FROM treated_map
  UNION ALL
  SELECT * FROM control_map
")
DBI::dbExecute(con, "
  CREATE TEMP TABLE td_units AS
  SELECT b.*, CAST(m.final_weight AS DOUBLE) weight
  FROM td_base_units b
  JOIN td_unit_map m USING(roster_row_id)
")

mapping_checks <- DBI::dbGetQuery(con, "
  SELECT
    (SELECT COUNT(*) FROM td_weights) weight_rows,
    (SELECT COUNT(*) FROM td_unit_map) mapped_rows,
    (SELECT COUNT(DISTINCT roster_row_id) FROM td_unit_map) unique_rows,
    (SELECT COUNT(*) FROM td_units) unit_rows,
    (SELECT COUNT(*) FROM td_units WHERE weight<=0 OR weight IS NULL)
      invalid_weights
")
mapping_checks$pass <- with(
  mapping_checks,
  weight_rows == mapped_rows & mapped_rows == unique_rows &
    unique_rows == unit_rows & invalid_weights == 0L)
if (!isTRUE(mapping_checks$pass[[1L]])) {
  stop("TechDrift weight-to-roster mapping failed")
}
write_csv(mapping_checks, "techdrift_mapping_checks.csv")

DBI::dbExecute(con, "
  CREATE TEMP TABLE td_relevant_inventors AS
  SELECT DISTINCT codinv FROM td_units
")
DBI::dbExecute(con, "
  CREATE TEMP TABLE td_ipc4_year AS
  SELECT
    CAST(i.codinv AS BIGINT) codinv,
    CAST(i.year AS INTEGER) ipc_year,
    SUBSTR(i.ipc_code,1,4) ipc4,
    CAST(SUM(i.patent_count) AS DOUBLE) ipc_weight
  FROM foundation.inventor_ipc_year i
  JOIN td_relevant_inventors r
    ON r.codinv=CAST(i.codinv AS BIGINT)
  WHERE i.ipc_code IS NOT NULL
  GROUP BY 1,2,3
")

DBI::dbExecute(con, "
  CREATE TEMP TABLE td_window_vectors AS
  SELECT roster_row_id, 'recent_pre5' window_name, ipc4,
         SUM(ipc_weight) vector_weight
  FROM td_units u JOIN td_ipc4_year i USING(codinv)
  WHERE i.ipc_year BETWEEN u.cohort-5 AND u.cohort-1
  GROUP BY 1,2,3
  UNION ALL
  SELECT roster_row_id, 'full_pre', ipc4, SUM(ipc_weight)
  FROM td_units u JOIN td_ipc4_year i USING(codinv)
  WHERE i.ipc_year<=u.cohort-1
  GROUP BY 1,2,3
  UNION ALL
  SELECT roster_row_id, 'post5', ipc4, SUM(ipc_weight)
  FROM td_units u JOIN td_ipc4_year i USING(codinv)
  WHERE i.ipc_year BETWEEN u.cohort+1 AND u.cohort+5
  GROUP BY 1,2,3
  UNION ALL
  SELECT roster_row_id, 'post2', ipc4, SUM(ipc_weight)
  FROM td_units u JOIN td_ipc4_year i USING(codinv)
  WHERE i.ipc_year BETWEEN u.cohort+1 AND u.cohort+2
  GROUP BY 1,2,3
  UNION ALL
  SELECT roster_row_id, 'post3_5', ipc4, SUM(ipc_weight)
  FROM td_units u JOIN td_ipc4_year i USING(codinv)
  WHERE i.ipc_year BETWEEN u.cohort+3 AND u.cohort+5
  GROUP BY 1,2,3
  UNION ALL
  SELECT roster_row_id, 'early_pre5', ipc4, SUM(ipc_weight)
  FROM td_units u JOIN td_ipc4_year i USING(codinv)
  WHERE u.cohort>=1998
    AND i.ipc_year BETWEEN u.cohort-10 AND u.cohort-6
  GROUP BY 1,2,3
")
DBI::dbExecute(con, "
  CREATE TEMP TABLE td_vector_stats AS
  SELECT roster_row_id, window_name,
         SQRT(SUM(vector_weight*vector_weight)) vector_norm,
         COUNT(*) n_ipc4, SUM(vector_weight) total_ipc_weight
  FROM td_window_vectors
  GROUP BY 1,2
")
DBI::dbExecute(con, "
  CREATE TEMP TABLE td_window_vectors_binary AS
  SELECT roster_row_id,window_name,ipc4,1.0::DOUBLE vector_weight
  FROM td_window_vectors
")
DBI::dbExecute(con, "
  CREATE TEMP TABLE td_vector_stats_binary AS
  SELECT roster_row_id, window_name,
         SQRT(SUM(vector_weight*vector_weight)) vector_norm,
         COUNT(*) n_ipc4, SUM(vector_weight) total_ipc_weight
  FROM td_window_vectors_binary
  GROUP BY 1,2
")

pair_values <- paste(apply(
  config$pair_definitions, 1L,
  function(z) sprintf(
    "(%s,%s,%s)", lmv2_sql_string(z[["pair_name"]]),
    lmv2_sql_string(z[["left_window"]]),
    lmv2_sql_string(z[["right_window"]]))), collapse = ",")
DBI::dbExecute(con, sprintf("
  CREATE TEMP TABLE td_pair_definitions AS
  SELECT * FROM (VALUES %s)
    AS p(pair_name,left_window,right_window)
", pair_values))
DBI::dbExecute(con, "
  CREATE TEMP TABLE td_pair_dots AS
  SELECT p.pair_name, l.roster_row_id,
         SUM(l.vector_weight*r.vector_weight) dot_product
  FROM td_pair_definitions p
  JOIN td_window_vectors l ON l.window_name=p.left_window
  JOIN td_window_vectors r
    ON r.roster_row_id=l.roster_row_id
   AND r.window_name=p.right_window AND r.ipc4=l.ipc4
  GROUP BY 1,2
")
DBI::dbExecute(con, "
  CREATE TEMP TABLE td_pair_dots_binary AS
  SELECT p.pair_name, l.roster_row_id,
         SUM(l.vector_weight*r.vector_weight) dot_product
  FROM td_pair_definitions p
  JOIN td_window_vectors_binary l ON l.window_name=p.left_window
  JOIN td_window_vectors_binary r
    ON r.roster_row_id=l.roster_row_id
   AND r.window_name=p.right_window AND r.ipc4=l.ipc4
  GROUP BY 1,2
")
DBI::dbExecute(con, "
  CREATE TEMP TABLE td_pair_metrics AS
  SELECT
    u.roster_row_id, u.deal_id, u.cohort, u.arm, u.codinv,
    u.weight, u.multi_exposure_inventor,
    'patent_count' weight_scheme,
    p.pair_name, p.left_window, p.right_window,
    ls.vector_norm left_norm, rs.vector_norm right_norm,
    ls.n_ipc4 left_n_ipc4, rs.n_ipc4 right_n_ipc4,
    ls.total_ipc_weight left_ipc_weight,
    rs.total_ipc_weight right_ipc_weight,
    COALESCE(d.dot_product,0) dot_product,
    CASE WHEN ls.vector_norm>0 AND rs.vector_norm>0
      THEN LEAST(1.0,GREATEST(0.0,
        COALESCE(d.dot_product,0)/(ls.vector_norm*rs.vector_norm)))
      ELSE NULL END tech_similarity,
    CASE WHEN ls.vector_norm>0 AND rs.vector_norm>0
      THEN 1-LEAST(1.0,GREATEST(0.0,
        COALESCE(d.dot_product,0)/(ls.vector_norm*rs.vector_norm)))
      ELSE NULL END tech_drift
  FROM td_units u
  CROSS JOIN td_pair_definitions p
  LEFT JOIN td_vector_stats ls
    ON ls.roster_row_id=u.roster_row_id
   AND ls.window_name=p.left_window
  LEFT JOIN td_vector_stats rs
    ON rs.roster_row_id=u.roster_row_id
   AND rs.window_name=p.right_window
  LEFT JOIN td_pair_dots d
    ON d.roster_row_id=u.roster_row_id AND d.pair_name=p.pair_name
")
DBI::dbExecute(con, "
  CREATE TEMP TABLE td_pair_metrics_binary AS
  SELECT
    u.roster_row_id, u.deal_id, u.cohort, u.arm, u.codinv,
    u.weight, u.multi_exposure_inventor,
    'binary_presence' weight_scheme,
    p.pair_name, p.left_window, p.right_window,
    ls.vector_norm left_norm, rs.vector_norm right_norm,
    ls.n_ipc4 left_n_ipc4, rs.n_ipc4 right_n_ipc4,
    ls.total_ipc_weight left_ipc_weight,
    rs.total_ipc_weight right_ipc_weight,
    COALESCE(d.dot_product,0) dot_product,
    CASE WHEN ls.vector_norm>0 AND rs.vector_norm>0
      THEN LEAST(1.0,GREATEST(0.0,
        COALESCE(d.dot_product,0)/(ls.vector_norm*rs.vector_norm)))
      ELSE NULL END tech_similarity,
    CASE WHEN ls.vector_norm>0 AND rs.vector_norm>0
      THEN 1-LEAST(1.0,GREATEST(0.0,
        COALESCE(d.dot_product,0)/(ls.vector_norm*rs.vector_norm)))
      ELSE NULL END tech_drift
  FROM td_units u
  CROSS JOIN td_pair_definitions p
  LEFT JOIN td_vector_stats_binary ls
    ON ls.roster_row_id=u.roster_row_id
   AND ls.window_name=p.left_window
  LEFT JOIN td_vector_stats_binary rs
    ON rs.roster_row_id=u.roster_row_id
   AND rs.window_name=p.right_window
  LEFT JOIN td_pair_dots_binary d
    ON d.roster_row_id=u.roster_row_id AND d.pair_name=p.pair_name
")
DBI::dbExecute(con, "
  CREATE TEMP TABLE td_pair_metrics_all AS
  SELECT * FROM td_pair_metrics
  UNION ALL
  SELECT * FROM td_pair_metrics_binary
")

DBI::dbExecute(con, sprintf("
  CREATE TEMP TABLE td_annual_counts AS
  SELECT
    p.roster_row_id,
    SUM(p.patent_count) FILTER(p.event_time BETWEEN -5 AND -1)
      pre5_patent_count,
    SUM(p.patent_count) FILTER(p.event_time BETWEEN 1 AND 5)
      post5_patent_count,
    COUNT(*) FILTER(p.event_time BETWEEN 1 AND 5
                    AND p.patent_count>0) post5_active_years
  FROM %s p
  JOIN td_unit_map m USING(roster_row_id)
  GROUP BY 1
", panel_sql))
DBI::dbExecute(con, "
  CREATE TEMP TABLE td_history AS
  SELECT u.roster_row_id,
         MIN(i.ipc_year) FILTER(i.ipc_year<=u.cohort-1)
           first_observed_pre_year,
         MAX(i.ipc_year) FILTER(i.ipc_year<=u.cohort-1)
           last_observed_pre_year,
         COUNT(DISTINCT i.ipc_year) FILTER(i.ipc_year<=u.cohort-1)
           observed_pre_active_years
  FROM td_units u
  LEFT JOIN td_ipc4_year i USING(codinv)
  GROUP BY 1
")
DBI::dbExecute(con, "
  CREATE TEMP TABLE td_window_units AS
  SELECT
    u.*,
    a.pre5_patent_count, a.post5_patent_count, a.post5_active_years,
    h.first_observed_pre_year, h.last_observed_pre_year,
    h.observed_pre_active_years,
    (h.first_observed_pre_year=1988) left_boundary_1988,
    MAX(v.n_ipc4) FILTER(v.window_name='recent_pre5') pre5_n_ipc4,
    MAX(v.n_ipc4) FILTER(v.window_name='full_pre') full_pre_n_ipc4,
    MAX(v.n_ipc4) FILTER(v.window_name='post5') post5_n_ipc4,
    MAX(v.n_ipc4) FILTER(v.window_name='post2') post2_n_ipc4,
    MAX(v.n_ipc4) FILTER(v.window_name='post3_5') post3_5_n_ipc4,
    MAX(v.n_ipc4) FILTER(v.window_name='early_pre5') early_pre5_n_ipc4,
    MAX(pm.tech_drift) FILTER(pm.pair_name='recent5_post5')
      tech_drift_recent5_post5,
    MAX(pm.tech_drift) FILTER(pm.pair_name='fullstock_post5')
      tech_drift_fullstock_post5,
    MAX(pm.tech_drift) FILTER(pm.pair_name='recent5_post2')
      tech_drift_recent5_post2,
    MAX(pm.tech_drift) FILTER(pm.pair_name='recent5_post3_5')
      tech_drift_recent5_post3_5,
    MAX(pm.tech_drift) FILTER(pm.pair_name='pre10_6_pre5')
      tech_drift_pre10_6_pre5,
    MAX(pmb.tech_drift) FILTER(pmb.pair_name='recent5_post5')
      tech_drift_recent5_post5_binary
  FROM td_units u
  LEFT JOIN td_annual_counts a USING(roster_row_id)
  LEFT JOIN td_history h USING(roster_row_id)
  LEFT JOIN td_vector_stats v USING(roster_row_id)
  LEFT JOIN td_pair_metrics pm USING(roster_row_id)
  LEFT JOIN td_pair_metrics_binary pmb USING(roster_row_id)
  GROUP BY ALL
")

units_parquet <- file.path(config$output_dir, "techdrift_window_units.parquet")
pairs_parquet <- file.path(config$output_dir, "techdrift_window_pairs.parquet")
DBI::dbExecute(con, sprintf(
  "COPY (SELECT * FROM td_window_units ORDER BY cohort,deal_id,arm,codinv,roster_row_id) TO %s (FORMAT PARQUET,COMPRESSION ZSTD,OVERWRITE TRUE)",
  lmv2_sql_string(units_parquet)))
DBI::dbExecute(con, sprintf(
  "COPY (SELECT * FROM td_pair_metrics_all ORDER BY weight_scheme,pair_name,cohort,deal_id,arm,codinv,roster_row_id) TO %s (FORMAT PARQUET,COMPRESSION ZSTD,OVERWRITE TRUE)",
  lmv2_sql_string(pairs_parquet)))

# Vector construction is the expensive stage and is byte-stable at eight
# threads. Use one thread for the small weighted aggregations and bootstrap so
# CSV results do not depend on parallel floating-point reduction order.
DBI::dbExecute(con, "SET threads=1")

window_bounds <- DBI::dbGetQuery(con, "
  SELECT w.window_name,
         MIN(i.ipc_year-u.cohort) min_event_time,
         MAX(i.ipc_year-u.cohort) max_event_time,
         COUNT(*) source_rows
  FROM td_units u
  JOIN td_ipc4_year i USING(codinv)
  JOIN (
    SELECT 'recent_pre5' window_name,-5 lo,-1 hi UNION ALL
    SELECT 'post5',1,5 UNION ALL SELECT 'post2',1,2 UNION ALL
    SELECT 'post3_5',3,5 UNION ALL SELECT 'early_pre5',-10,-6
  ) w ON i.ipc_year-u.cohort BETWEEN w.lo AND w.hi
  WHERE w.window_name<>'early_pre5' OR u.cohort>=1998
  GROUP BY 1 ORDER BY 1
")
write_csv(window_bounds, "techdrift_window_year_bounds.csv")

baseline_audit <- DBI::dbGetQuery(con, "
  SELECT cohort, arm,
         COUNT(*) units, SUM(weight) design_mass,
         SUM(weight*pre5_n_ipc4)/SUM(weight) mean_pre5_n_ipc4,
         SUM(weight*full_pre_n_ipc4)/SUM(weight) mean_full_pre_n_ipc4,
         SUM(weight) FILTER(full_pre_n_ipc4>pre5_n_ipc4)/SUM(weight)
           share_full_baseline_broader,
         SUM(weight) FILTER(left_boundary_1988)/SUM(weight)
           share_left_boundary_1988
  FROM td_window_units
  GROUP BY 1,2 ORDER BY 1,2
")
write_csv(baseline_audit, "techdrift_baseline_audit.csv")

eligibility_audit <- DBI::dbGetQuery(con, "
  SELECT arm, COUNT(*) roster_units, SUM(weight) roster_mass,
         COUNT(*) FILTER(pre5_n_ipc4>0) pre_ipc_units,
         SUM(weight) FILTER(pre5_n_ipc4>0) pre_ipc_mass,
         COUNT(*) FILTER(post5_n_ipc4>0) post_ipc_units,
         SUM(weight) FILTER(post5_n_ipc4>0) post_ipc_mass,
         COUNT(*) FILTER(pre5_n_ipc4>0 AND post5_n_ipc4>0)
           joint_ipc_units,
         SUM(weight) FILTER(pre5_n_ipc4>0 AND post5_n_ipc4>0)
           joint_ipc_mass,
         joint_ipc_mass/roster_mass joint_ipc_weight_coverage
  FROM td_window_units
  GROUP BY arm ORDER BY arm
")
eligibility_audit$analysis_population <- config$analysis_population
eligibility_audit$outcome_defined_population <-
  config$outcome_defined_population
write_csv(eligibility_audit, "techdrift_eligibility_audit.csv")

estimate_specification <- function(spec_row) {
  spec_id <- spec_row$specification[[1L]]
  pair_name <- spec_row$pair_name[[1L]]
  weight_scheme <- spec_row$weight_scheme[[1L]]
  metric_table <- if (weight_scheme == "patent_count") {
    "td_pair_metrics"
  } else if (weight_scheme == "binary_presence") {
    "td_pair_metrics_binary"
  } else {
    stop("Unknown vector weight scheme: ", weight_scheme)
  }
  cohort_min <- as.integer(spec_row$cohort_min[[1L]])
  cohort_max <- as.integer(spec_row$cohort_max[[1L]])
  safe_id <- gsub("[^A-Za-z0-9_]", "_", spec_id)
  influence_table <- paste0("td_influence_", safe_id)

  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE %1$s AS
    WITH design_mass AS (
      SELECT cohort, SUM(weight) treated_design_mass
      FROM td_units
      WHERE arm='treated' AND cohort BETWEEN %2$d AND %3$d
      GROUP BY cohort
    ), design_share AS (
      SELECT cohort, treated_design_mass,
             treated_design_mass/SUM(treated_design_mass) OVER() q_g
      FROM design_mass
    ), arm_stats AS (
      SELECT cohort, arm, SUM(weight) observed_mass,
             SUM(weight*tech_drift)/SUM(weight) mean_outcome
      FROM %5$s
      WHERE pair_name=%4$s AND tech_drift IS NOT NULL
        AND cohort BETWEEN %2$d AND %3$d
      GROUP BY cohort,arm
    ), eligible AS (
      SELECT cohort FROM arm_stats GROUP BY cohort
      HAVING COUNT(DISTINCT arm)=2 AND MIN(observed_mass)>0
    ), retained AS (
      SELECT SUM(q.q_g) retained_design_share
      FROM eligible e JOIN design_share q USING(cohort)
    )
    SELECT
      p.roster_row_id,p.deal_id,p.cohort,p.arm,p.codinv,p.weight,
      p.tech_drift outcome_value, 1 event_time,
      q.q_g/r.retained_design_share q_event,
      s.observed_mass,s.mean_outcome,
      q.q_g/r.retained_design_share*p.weight/s.observed_mass
        analysis_weight,
      CASE WHEN p.arm='treated' THEN 1.0 ELSE -1.0 END *
        q.q_g/r.retained_design_share*p.weight/s.observed_mass*p.tech_drift
        contribution,
      CASE WHEN p.arm='treated' THEN 1.0 ELSE -1.0 END *
        q.q_g/r.retained_design_share*p.weight/s.observed_mass*
        (p.tech_drift-s.mean_outcome) influence
    FROM %5$s p
    JOIN arm_stats s USING(cohort,arm)
    JOIN eligible e USING(cohort)
    JOIN design_share q USING(cohort)
    CROSS JOIN retained r
    WHERE p.pair_name=%4$s AND p.tech_drift IS NOT NULL
      AND p.cohort BETWEEN %2$d AND %3$d
  ", influence_table, cohort_min, cohort_max,
  lmv2_sql_string(pair_name), metric_table))

  direct <- DBI::dbGetQuery(con, sprintf("
    SELECT SUM(contribution) estimate, SUM(influence) influence_sum,
           COUNT(*) n_rows, COUNT(DISTINCT deal_id) n_deals,
           COUNT(DISTINCT codinv) n_inventors
    FROM %s
  ", influence_table))
  if (!is.finite(direct$estimate[[1L]]) ||
      abs(direct$influence_sum[[1L]]) > 1e-8) {
    stop("Invalid influence construction for ", spec_id)
  }

  covariance <- lmv2_two_way_covariance(con, influence_table, 1L)
  df <- covariance$n_deal - 1L
  crit <- stats::qt(
    1 - (1 - LMV2_P6_ESTIMATION$inference$confidence_level) / 2, df)
  make_cluster_result <- function(vcov_name, label) {
    se <- sqrt(covariance[[vcov_name]][1L,1L])
    data.frame(
      inference=label, estimate=direct$estimate[[1L]], se=se, df=df,
      ci_low=direct$estimate[[1L]]-crit*se,
      ci_high=direct$estimate[[1L]]+crit*se,
      p_value=2*stats::pt(-abs(direct$estimate[[1L]]/se),df),
      ci_method="analytic_cluster_t", stringsAsFactors=FALSE)
  }

  compact <- DBI::dbGetQuery(con, sprintf("
    SELECT deal_id,cohort,CAST(arm='treated' AS INTEGER) treated,
           SUM(analysis_weight) analysis_weight,
           SUM(analysis_weight*outcome_value)/SUM(analysis_weight) outcome
    FROM %s GROUP BY 1,2,3
  ", influence_table))
  mod <- fixest::feols(
    outcome~treated|cohort, data=compact, weights=~analysis_weight,
    cluster=~deal_id, fixef.rm="none", notes=FALSE)
  model_estimate <- unname(stats::coef(mod)[["treated"]])
  if (!is.finite(model_estimate) ||
      abs(model_estimate-direct$estimate[[1L]]) > 1e-9) {
    stop("Compact-regression tooth check failed for ", spec_id)
  }
  wild <- lmv2_wild_post(mod, config$bootstrap_replications)
  results <- rbind(
    wild,
    make_cluster_result("two_way", "two_way_deal_inventor"),
    make_cluster_result("deal", "deal_cluster_robust"))
  results$specification <- spec_id
  results$pair_name <- pair_name
  results$weight_scheme <- weight_scheme
  results$role <- spec_row$role[[1L]]
  results$cohort_min <- cohort_min
  results$cohort_max <- cohort_max
  results$observed_rows <- direct$n_rows[[1L]]
  results$observed_deals <- direct$n_deals[[1L]]
  results$observed_inventors <- direct$n_inventors[[1L]]
  results$bootstrap_replications <- c(
    config$bootstrap_replications, NA_integer_, NA_integer_)

  coverage <- DBI::dbGetQuery(con, sprintf("
    WITH design AS (
      SELECT cohort,arm,SUM(weight) design_mass
      FROM td_units WHERE cohort BETWEEN %1$d AND %2$d
      GROUP BY 1,2
    ), observed AS (
      SELECT cohort,arm,COUNT(*) observed_rows,SUM(weight) observed_mass
      FROM %4$s
      WHERE pair_name=%3$s AND tech_drift IS NOT NULL
        AND cohort BETWEEN %1$d AND %2$d
      GROUP BY 1,2
    )
    SELECT d.*,COALESCE(o.observed_rows,0) observed_rows,
           COALESCE(o.observed_mass,0) observed_mass,
           COALESCE(o.observed_mass,0)/d.design_mass weight_coverage
    FROM design d LEFT JOIN observed o USING(cohort,arm)
    ORDER BY cohort,arm
  ", cohort_min, cohort_max, lmv2_sql_string(pair_name), metric_table))
  coverage$specification <- spec_id
  coverage$pair_name <- pair_name
  coverage$weight_scheme <- weight_scheme

  DBI::dbExecute(con, sprintf("DROP TABLE %s", influence_table))
  list(results=results, coverage=coverage)
}

run_started <- Sys.time()
fits <- lapply(seq_len(nrow(config$specifications)), function(i) {
  message("Estimating ", config$specifications$specification[[i]])
  estimate_specification(config$specifications[i,,drop=FALSE])
})
results <- do.call(rbind, lapply(fits, `[[`, "results"))
coverage <- do.call(rbind, lapply(fits, `[[`, "coverage"))
write_csv(results, "techdrift_window_estimates.csv")
write_csv(coverage, "techdrift_window_coverage.csv")

count_bins <- DBI::dbGetQuery(con, "
  SELECT arm,
    CASE WHEN post5_patent_count=1 THEN '1'
         WHEN post5_patent_count=2 THEN '2'
         WHEN post5_patent_count BETWEEN 3 AND 4 THEN '3-4'
         WHEN post5_patent_count>=5 THEN '5+'
         ELSE '0' END post_patent_bin,
    COUNT(*) units, SUM(weight) weight_mass,
    SUM(weight*post5_patent_count)/SUM(weight) mean_post_patents,
    SUM(weight*post5_n_ipc4)/SUM(weight) mean_post_ipc4,
    SUM(weight*tech_drift_recent5_post5)/
      SUM(weight) FILTER(tech_drift_recent5_post5 IS NOT NULL)
      mean_tech_drift
  FROM td_window_units
  GROUP BY 1,2 ORDER BY 1,2
")
write_csv(count_bins, "techdrift_post_count_bins.csv")

count_wide <- reshape(
  count_bins[,c("post_patent_bin","arm","weight_mass","mean_tech_drift")],
  idvar="post_patent_bin", timevar="arm", direction="wide")
required_count_cols <- c(
  "weight_mass.treated", "weight_mass.control",
  "mean_tech_drift.treated", "mean_tech_drift.control")
if (!all(required_count_cols %in% names(count_wide))) {
  stop("Count-bin diagnostic lacks one analysis arm")
}
count_wide <- count_wide[
  is.finite(count_wide$mean_tech_drift.treated) &
    is.finite(count_wide$mean_tech_drift.control),]
count_wide$share_treated <-
  count_wide$weight_mass.treated/sum(count_wide$weight_mass.treated)
count_wide$share_control <-
  count_wide$weight_mass.control/sum(count_wide$weight_mass.control)
count_wide$common_share <-
  (count_wide$share_treated+count_wide$share_control)/2
count_wide$common_share <-
  count_wide$common_share/sum(count_wide$common_share)
raw_gap <- with(count_wide,
  sum(share_treated*mean_tech_drift.treated)-
    sum(share_control*mean_tech_drift.control))
composition_gap <- with(count_wide,
  sum((share_treated-share_control)*mean_tech_drift.control))
within_gap <- with(count_wide,
  sum(share_treated*(mean_tech_drift.treated-mean_tech_drift.control)))
common_standardized_gap <- with(count_wide,
  sum(common_share*(mean_tech_drift.treated-mean_tech_drift.control)))
write_csv(count_wide, "techdrift_post_count_standardization_bins.csv")
write_csv(data.frame(
  diagnostic=c(
    "raw_global_gap", "count_composition_component",
    "within_count_bin_component", "common_count_distribution_gap"),
  estimate=c(raw_gap,composition_gap,within_gap,common_standardized_gap),
  causal_interpretation=FALSE,
  stringsAsFactors=FALSE), "techdrift_post_count_decomposition.csv")

legacy_stayer <- utils::read.csv(
  config$legacy_stayer_headline, stringsAsFactors=FALSE)
legacy_full <- utils::read.csv(
  config$legacy_full_headline, stringsAsFactors=FALSE)
legacy <- rbind(
  transform(legacy_stayer[
    legacy_stayer$outcome=="tech_drift" &
      legacy_stayer$sample=="full_1993_2010" &
      legacy_stayer$summary=="average_annual_t1_to_t5",],
    population="initially_retained_inventors"),
  transform(legacy_full[
    legacy_full$outcome=="tech_drift" &
      legacy_full$sample=="full_1993_2010" &
      legacy_full$summary=="average_annual_t1_to_t5",],
    population="full_target_inventor_cohort"))
write_csv(legacy, "techdrift_legacy_annual_results.csv")

source_paths <- c(required_inputs, config$source_files)
source_paths <- unique(normalizePath(
  source_paths, winslash="/", mustWork=FALSE))
source_paths <- source_paths[file.exists(source_paths)]
source_manifest <- data.frame(
  source_path=source_paths,
  sha256=vapply(source_paths, digest::digest, character(1),
                algo="sha256", file=TRUE),
  stringsAsFactors=FALSE)
write_csv(source_manifest, "techdrift_source_manifest.csv")

output_manifest <- data.frame(
  version=config$version,
  analysis_population=config$analysis_population,
  outcome_defined_population=config$outcome_defined_population,
  main_pair=config$main_pair,
  primary_spec=config$primary_spec,
  cohorts=paste(range(config$cohorts),collapse="-"),
  bootstrap_replications=config$bootstrap_replications,
  seed=config$seed,
  unit_rows=mapping_checks$unit_rows,
  pair_rows=DBI::dbGetQuery(con,
    "SELECT COUNT(*) n FROM td_pair_metrics_all")$n,
  runtime_minutes=as.numeric(difftime(
    Sys.time(),run_started,units="mins")),
  stringsAsFactors=FALSE)
write_csv(output_manifest, "techdrift_run_manifest.csv")

message("Pooled-window TechDrift amendment completed: ",
        config$output_dir)
