# ============================================================================
# 33c_compute_lmv2_stayer_power_gate.R -- precision before heterogeneity
# ============================================================================
# This stage opens outcomes only to materialize unit changes and precision. It
# writes no heterogeneity coefficient, sign, p-value, or confidence interval.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "digest", "MASS")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))
source(file.path(BASE, "R", "33a_lmv2_stayer_heterogeneity_config.R"))

cfg <- LMV2_STAYER_HET
out_dir <- cfg$output_dir
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
temp_dir <- file.path(out_dir, "duckdb_tmp_power")
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)

moderator_path <- file.path(out_dir, "stayer_moderators.parquet")
moderator_manifest_path <- file.path(out_dir, "moderator_build_manifest.csv")
if (!all(file.exists(c(moderator_path, moderator_manifest_path)))) {
  stop("Run 33b before the stayer power stage")
}
moderator_manifest <- utils::read.csv(
  moderator_manifest_path, stringsAsFactors = FALSE
)
if (nrow(moderator_manifest) != 1L ||
    moderator_manifest$design_hash != lmv2_stayer_het_hash() ||
    moderator_manifest$moderator_sha256 != digest::digest(
      file = moderator_path, algo = "sha256"
    )) {
  stop("Stayer moderator table or manifest is stale")
}

panel_files <- sort(list.files(
  cfg$inputs$panel_dir,
  pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE
))
stamp_files <- sort(list.files(
  cfg$inputs$panel_dir,
  pattern = "^lmv2_event_panel_c[0-9]+_stamp\\.csv$",
  full.names = TRUE
))
expected_shards <- length(unique(unlist(cfg$estimand$samples)))
if (length(panel_files) != expected_shards ||
    length(stamp_files) != expected_shards) {
  stop("Certified P6 panel bundle is incomplete")
}

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, sprintf("PRAGMA threads=%d", cfg$execution$threads))
DBI::dbExecute(con, sprintf(
  "PRAGMA memory_limit='%s'", cfg$execution$memory_limit
))
DBI::dbExecute(con, sprintf(
  "PRAGMA temp_directory=%s", lmv2_sql_string(temp_dir)
))
input_checks <- lmv2_validate_estimation_inputs(
  con, panel_files, stamp_files, cfg$inputs$panel_manifest
)
if (!isTRUE(input_checks$pass[[1]])) {
  stop("Inherited certified P6 panel failed validation")
}

t0 <- Sys.time()
panel_sql <- lmv2_panel_sql(panel_files)
mod_sql <- sprintf(
  "read_parquet(%s)",
  lmv2_sql_string(normalizePath(
    moderator_path, winslash = "/", mustWork = TRUE
  ))
)
pre_sql <- paste(cfg$estimand$pre_event_times, collapse = ",")
post_sql <- paste(cfg$estimand$post_event_times, collapse = ",")
DBI::dbExecute(con, sprintf("
CREATE OR REPLACE TEMP TABLE stayer_unit_analysis AS
WITH path AS (
  SELECT
    roster_row_id,
    MIN(deal_id) deal_id,MIN(cohort) cohort,MIN(arm) arm,
    MIN(codinv) codinv,
    MAX(CASE WHEN event_time=%2$d
      THEN CAST(patent_count AS DOUBLE) END) patent_pre_ref,
    MAX(CASE WHEN event_time=%2$d
      THEN CAST(active_patenting AS DOUBLE) END) active_pre_ref,
    AVG(CASE WHEN event_time IN (%3$s)
      THEN CAST(patent_count AS DOUBLE) END) patent_pre_avg,
    AVG(CASE WHEN event_time IN (%3$s)
      THEN CAST(active_patenting AS DOUBLE) END) active_pre_avg,
    AVG(CASE WHEN event_time IN (%4$s)
      THEN CAST(patent_count AS DOUBLE) END) patent_post_avg,
    AVG(CASE WHEN event_time IN (%4$s)
      THEN CAST(active_patenting AS DOUBLE) END) active_post_avg,
    COUNT(*) FILTER (WHERE event_time IN (%3$s)) n_pre,
    COUNT(*) FILTER (WHERE event_time IN (%4$s)) n_post
  FROM %1$s
  WHERE roster_row_id IN (SELECT roster_row_id FROM %5$s)
  GROUP BY roster_row_id
)
SELECT
  p.*,CASE WHEN p.arm='treated' THEN 1.0 ELSE 0.0 END treated,
  p.patent_post_avg-p.patent_pre_ref d_patent_ref,
  p.active_post_avg-p.active_pre_ref d_active_ref,
  p.patent_post_avg-p.patent_pre_avg d_patent_5x5,
  p.active_post_avg-p.active_pre_avg d_active_5x5,
  m.* EXCLUDE(deal_id,cohort,arm,codinv,roster_row_id)
FROM path p JOIN %5$s m USING (roster_row_id)
", panel_sql, cfg$estimand$reference_event_time,
   pre_sql, post_sql, mod_sql))

unit_path <- normalizePath(
  file.path(out_dir, "stayer_unit_analysis.parquet"),
  winslash = "/", mustWork = FALSE
)
if (file.exists(unit_path) && !file.remove(unit_path)) {
  stop("Could not replace stale stayer unit-analysis artifact")
}
DBI::dbExecute(con, sprintf("
COPY (
  SELECT * FROM stayer_unit_analysis
  ORDER BY cohort,deal_id,arm,codinv,roster_row_id
) TO %s (FORMAT PARQUET,COMPRESSION ZSTD)
", lmv2_sql_string(unit_path)))

unit_audit <- DBI::dbGetQuery(con, "
SELECT
  COUNT(*) unit_rows,COUNT(DISTINCT roster_row_id) unique_rows,
  COUNT(*) FILTER (WHERE n_pre<>5 OR n_post<>5) incomplete_paths,
  COUNT(*) FILTER (
    WHERE d_patent_ref IS NULL OR d_active_ref IS NULL
       OR d_patent_5x5 IS NULL OR d_active_5x5 IS NULL
  ) missing_outcomes,
  COUNT(*) FILTER (
    WHERE raw_weight<=0 OR raw_weight IS NULL OR NOT isfinite(raw_weight)
  ) invalid_weights,
  COUNT(*) FILTER (WHERE treated=1) treated_inventors,
  COUNT(DISTINCT deal_id) FILTER (WHERE treated=1) treated_deals
FROM stayer_unit_analysis
")
checks <- data.frame(
  check = c(
    "one_unit_row_per_certified_stayer_row",
    "complete_five_pre_and_five_post_paths",
    "no_missing_primary_or_companion_outcome",
    "all_p5b_weights_positive",
    "expected_treated_inventors_and_deals"
  ),
  pass = c(
    unit_audit$unit_rows == moderator_manifest$moderator_rows &&
      unit_audit$unit_rows == unit_audit$unique_rows,
    unit_audit$incomplete_paths == 0,
    unit_audit$missing_outcomes == 0,
    unit_audit$invalid_weights == 0,
    unit_audit$treated_inventors == moderator_manifest$treated_inventors &&
      unit_audit$treated_deals == moderator_manifest$treated_deals
  ),
  stringsAsFactors = FALSE
)
lmv2_stayer_het_assert(checks)
utils::write.csv(
  unit_audit, file.path(out_dir, "unit_analysis_audit.csv"), row.names = FALSE
)
utils::write.csv(
  checks, file.path(out_dir, "unit_analysis_certification.csv"),
  row.names = FALSE
)

unit <- DBI::dbGetQuery(con, "SELECT * FROM stayer_unit_analysis")
deal_levels <- sort(unique(unit$deal_id))
deal_multipliers <- lmv2_vr_webb_multipliers(deal_levels, cfg)

base <- lmv2_stayer_prepare_data(
  unit, cfg$estimand$samples$full_1993_2010
)$data
base_count <- lmv2_vr_fit_wls(
  base, "d_patent_ref", c("factor(cohort)", "treated")
)
base_active <- lmv2_vr_fit_wls(
  base, "d_active_ref", c("factor(cohort)", "treated")
)
headline <- utils::read.csv(
  cfg$inputs$s4_headline, stringsAsFactors = FALSE
)
get_headline <- function(outcome) {
  z <- headline[
    headline$spec == cfg$construction$primary_spec &
      headline$support_variant == cfg$construction$primary_support &
      headline$outcome == outcome &
      headline$sample == "full_1993_2010" &
      headline$summary == "average_annual_t1_to_t5" &
      headline$governing %in% c(TRUE, "TRUE"), ,
    drop = FALSE
  ]
  if (nrow(z) != 1L) stop("Stayer headline row is not unique for ", outcome)
  z$estimate
}
aggregate_reproduction_pass <-
  abs(base_count$beta[["treated"]] - get_headline("patent_count")) <= 1e-10 &&
  abs(base_active$beta[["treated"]] -
        get_headline("active_patenting")) <= 1e-10
if (!aggregate_reproduction_pass) {
  stop("Nested regression does not reproduce certified P5b stayer ATTs")
}

common_rhs <- c(
  "factor(cohort)", "treated",
  "prod_z", "age_z", "team_any_c", "team_intensity"
)
model_spec <- list(
  predeal_productivity = list(
    techfit = NULL, rhs = c(common_rhs, "tx_prod"), term = "tx_prod"
  ),
  career_age = list(
    techfit = NULL, rhs = c(common_rhs, "tx_age"), term = "tx_age"
  ),
  team_persistence = list(
    techfit = NULL,
    rhs = c(common_rhs, "tx_team_any", "tx_team_intensity"),
    term = "tx_team_any"
  ),
  techfit = list(
    techfit = "full",
    rhs = c(common_rhs, "techfit_z", "tx_techfit"),
    term = "tx_techfit"
  )
)
outcomes <- c(
  patent_count = "d_patent_ref",
  active_patenting = "d_active_ref"
)
power_rows <- list()
row_id <- 0L
for (moderator in names(model_spec)) {
  spec <- model_spec[[moderator]]
  prepared <- lmv2_stayer_prepare_data(
    unit, cfg$estimand$samples$full_1993_2010, spec$techfit
  )
  contrast <- setNames(
    unname(prepared$contrasts[[moderator]]), spec$term
  )
  for (outcome in names(outcomes)) {
    row_id <- row_id + 1L
    fit <- lmv2_vr_fit_wls(
      prepared$data, outcomes[[outcome]], spec$rhs
    )
    covariance <- lmv2_vr_model_covariance(fit)
    result <- lmv2_vr_linear_result(
      fit, covariance, contrast, deal_multipliers,
      cfg$estimand$focal_contrast[[moderator]], cfg
    )
    threshold <- unname(cfg$estimand$meaningful_contrast[[outcome]])
    mde <- (
      result$governing_critical +
        stats::qnorm(cfg$inference$target_power)
    ) * result$governing_se
    power_rows[[row_id]] <- data.frame(
      moderator = moderator,
      outcome = outcome,
      contrast = result$contrast,
      treated_inventors = sum(prepared$data$treated == 1),
      nominal_deals = length(unique(
        prepared$data$deal_id[prepared$data$treated == 1]
      )),
      governing_se = result$governing_se,
      governing_critical = result$governing_critical,
      meaningful_threshold = threshold,
      mde = mde,
      power_gate_pass = mde <= threshold,
      type_m_exaggeration_ratio_at_threshold = lmv2_vr_type_m_ratio(
        result$governing_se, threshold, result$governing_critical
      ),
      reporting_status = "included_with_precision_diagnostic",
      stringsAsFactors = FALSE
    )
  }
}
power <- do.call(rbind, power_rows)
if (nrow(power) != 8L || anyDuplicated(paste(
    power$moderator, power$outcome
))) {
  stop("Stayer precision family is not the frozen 4 x 2 design")
}
utils::write.csv(
  power, file.path(out_dir, "stayer_power_gate.csv"), row.names = FALSE
)

manifest <- data.frame(
  design_hash = lmv2_stayer_het_hash(),
  moderator_sha256 = digest::digest(
    file = moderator_path, algo = "sha256"
  ),
  unit_analysis_sha256 = digest::digest(
    file = unit_path, algo = "sha256"
  ),
  panel_manifest_sha256 = digest::digest(
    file = cfg$inputs$panel_manifest, algo = "sha256"
  ),
  source_sha256 = digest::digest(
    file = file.path(BASE, "R", "33c_compute_lmv2_stayer_power_gate.R"),
    algo = "sha256"
  ),
  aggregate_att_reproduction_pass = aggregate_reproduction_pass,
  power_rows = nrow(power),
  heterogeneity_point_estimates_written = 0L,
  common_webb_draw_seed = cfg$inference$bootstrap_seed,
  runtime_minutes = as.numeric(
    difftime(Sys.time(), t0, units = "mins")
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(out_dir, "power_gate_manifest.csv"), row.names = FALSE
)
message(
  "Stayer precision diagnostic complete: ",
  sum(power$power_gate_pass), "/8 meet the MDE benchmark; ",
  "no heterogeneity point estimates written."
)
