# Outcome-blind finalizer for the U2-clean rescue pilot.

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) stop("Missing --", name, "=...")
  sub(paste0("^--", name, "="), "", hit[[1]])
}

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "16a_lmv2_matching_config.R"))
source(file.path(BASE, "R", "16c_lmv2_matching_utils.R"))
source(file.path(BASE, "R", "17f_lmv2_p4_ebal_config.R"))
source(file.path(BASE, "R", "17g_lmv2_p4_ebal_utils.R"))
source(file.path(BASE, "R", "17l_lmv2_p4_hybrid_core.R"))
source(file.path(BASE, "R", "17m_lmv2_p4_cohort_hybrid_core.R"))
source(file.path(BASE, "R", "19a_lmv2_p5_rescue_config.R"))

db_path <- normalizePath(
  read_arg("db"), winslash = "/", mustWork = TRUE)
rescue_root <- normalizePath(
  read_arg("rescue-root"), winslash = "/", mustWork = TRUE)
original_main_dir <- normalizePath(
  read_arg("original-main-dir"), winslash = "/", mustWork = TRUE)
output_dir <- read_arg("output-dir")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_dir <- normalizePath(
  output_dir, winslash = "/", mustWork = TRUE)

atomic_csv <- function(x, path) {
  temporary <- paste0(path, ".tmp_", Sys.getpid())
  utils::write.csv(x, temporary, row.names = FALSE, na = "")
  if (file.exists(path)) file.remove(path)
  if (!file.rename(temporary, path)) stop("Could not finalize ", path)
}
sql_paths <- function(paths) {
  paste(sprintf(
    "'%s'", gsub("'", "''", normalizePath(
      paths, winslash = "/", mustWork = TRUE), fixed = TRUE)),
    collapse = ",")
}
collect_csv <- function(root, pattern) {
  paths <- list.files(
    root, pattern = pattern, recursive = TRUE, full.names = TRUE)
  if (!length(paths)) return(data.frame())
  do.call(rbind, lapply(
    paths, utils::read.csv, stringsAsFactors = FALSE))
}

new_covers <- list.files(
  rescue_root, pattern = "^c_u2_.*\\.parquet$",
  recursive = TRUE, full.names = TRUE)
old_covers <- list.files(
  original_main_dir, pattern = "^c_u1_.*\\.parquet$",
  recursive = TRUE, full.names = TRUE)
if (length(new_covers) !=
    length(LMV2_P5_RESCUE$diagnostic_cohorts)) {
  stop(
    "Expected one U2 cover for each diagnostic cohort; found ",
    length(new_covers))
}
if (!length(old_covers)) stop("No completed original U1 covers found")

drv <- duckdb::duckdb()
con <- DBI::dbConnect(drv, db_path, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "SET threads=2")
DBI::dbExecute(con, "SET memory_limit='6GB'")
DBI::dbExecute(con, "SET preserve_insertion_order=false")

full_treated <- DBI::dbGetQuery(con, "
  SELECT CAST(cohort AS INTEGER) cohort,
         CAST(deal_id AS INTEGER) deal_id,
         CAST(codinv AS BIGINT) codinv,
         log_patent_count_5y, patent_trajectory, career_age,
         focal_group_exclusivity, focal_group_tenure
  FROM lmv2_p3_treated_inventor_units
  WHERE cohort BETWEEN 1994 AND 2010
  ORDER BY cohort,deal_id,codinv")
new_edges <- DBI::dbGetQuery(con, sprintf(
  "SELECT CAST(cohort AS INTEGER) cohort,
          CAST(deal_id AS INTEGER) deal_id,
          CAST(treated_codinv AS BIGINT) codinv,
          distance
   FROM read_parquet([%s], union_by_name=true)",
  sql_paths(new_covers)))
old_supported <- DBI::dbGetQuery(con, sprintf(
  "SELECT DISTINCT CAST(cohort AS INTEGER) cohort,
          CAST(deal_id AS INTEGER) deal_id,
          CAST(treated_codinv AS BIGINT) codinv
   FROM read_parquet([%s], union_by_name=true)
   WHERE cohort NOT IN (2000,2009)",
  sql_paths(old_covers)))
new_supported <- unique(new_edges[c("cohort", "deal_id", "codinv")])
supported_keys <- rbind(old_supported, new_supported)
if (anyDuplicated(supported_keys[c("cohort", "deal_id", "codinv")])) {
  stop("Combined treated-support keys are not unique")
}
full_key <- paste(
  full_treated$cohort, full_treated$deal_id, full_treated$codinv)
supported_key <- paste(
  supported_keys$cohort, supported_keys$deal_id, supported_keys$codinv)
full_treated$supported <- full_key %in% supported_key
score <- lmv2_p5_rescue_score_gates(full_treated)
full_treated$productivity_quartile <-
  lmv2_p5_rescue_assign_productivity_quartile(full_treated)

pilot <- full_treated[
  full_treated$cohort %in% LMV2_P5_RESCUE$diagnostic_cohorts, ]
coverage_by_cohort_quartile <- do.call(rbind, lapply(
  split(
    pilot,
    interaction(
      pilot$cohort, pilot$productivity_quartile,
      drop = TRUE, lex.order = TRUE)),
  function(z) data.frame(
    cohort = z$cohort[[1]],
    productivity_quartile = z$productivity_quartile[[1]],
    eligible = nrow(z),
    supported = sum(z$supported),
    coverage = mean(z$supported))))
coverage_by_deal <- do.call(rbind, lapply(
  split(
    pilot,
    interaction(
      pilot$cohort, pilot$deal_id,
      drop = TRUE, lex.order = TRUE)),
  function(z) data.frame(
    cohort = z$cohort[[1]],
    deal_id = z$deal_id[[1]],
    eligible = nrow(z),
    supported = sum(z$supported),
    coverage = mean(z$supported))))

nearest <- stats::aggregate(
  distance ~ cohort + deal_id + codinv,
  data = new_edges, FUN = min)
nearest <- merge(
  nearest,
  full_treated[
    c("cohort", "deal_id", "codinv", "productivity_quartile")],
  by = c("cohort", "deal_id", "codinv"),
  all.x = TRUE)
distance_by_cohort_quartile <- do.call(rbind, lapply(
  split(
    nearest,
    interaction(
      nearest$cohort, nearest$productivity_quartile,
      drop = TRUE, lex.order = TRUE)),
  function(z) data.frame(
    cohort = z$cohort[[1]],
    productivity_quartile = z$productivity_quartile[[1]],
    n = nrow(z),
    median_nearest_distance = stats::median(z$distance),
    p95_nearest_distance =
      unname(stats::quantile(z$distance, 0.95)),
    maximum_nearest_distance = max(z$distance))))
deal_70_distance <- nearest[
  nearest$cohort == 2000L & nearest$deal_id == 70L, ]

dependence <- collect_csv(
  rescue_root, "^dependence_[0-9]{4}_.*\\.csv$")
loo <- collect_csv(
  rescue_root, "^leave_one_firm_out_[0-9]{4}_.*\\.csv$")
deal_70_dependence <- if (nrow(dependence)) {
  dependence[
    dependence$cohort == 2000L &
      dependence$deal_id == 70L, ]
} else {
  data.frame(
    cohort = integer(), deal_id = integer(), scheme = character(),
    n_control_firms = integer(),
    n_distinct_control_inventors = integer(),
    effective_firm_count = numeric(),
    maximum_firm_weight_share = numeric(),
    reuse_adjusted_control_ess = numeric(),
    effective_firm_review_trigger = logical())
}
loo_summary <- if (nrow(loo)) {
  do.call(rbind, lapply(
    split(
      loo,
      interaction(
        loo$scheme, loo$omitted_control_group,
        drop = TRUE, lex.order = TRUE)),
    function(z) data.frame(
      scheme = z$scheme[[1]],
      omitted_control_group = z$omitted_control_group[[1]],
      n_balance_variables = nrow(z),
      maximum_absolute_shift_sd = max(z$absolute_shift_sd),
      every_variable_passes = all(z$pass))))
} else {
  data.frame(
    scheme = character(), omitted_control_group = numeric(),
    n_balance_variables = integer(),
    maximum_absolute_shift_sd = numeric(),
    every_variable_passes = logical())
}

cell_diagnostics <- collect_csv(
  rescue_root,
  "^cohort_hybrid_diagnostics_[0-9]{4}\\.csv$")
if (!nrow(cell_diagnostics)) {
  stop("Cohort hybrid diagnostics are missing")
}
scheme_status <- cell_diagnostics[
  cell_diagnostics$cohort %in%
    LMV2_P5_RESCUE$diagnostic_cohorts,
  c("cohort", "scheme", "mode", "failure_reason")]

atomic_csv(score$checks, file.path(
  output_dir, "combined_gate_checks.csv"))
atomic_csv(score$by_cohort, file.path(
  output_dir, "combined_coverage_by_cohort.csv"))
atomic_csv(score$by_quartile, file.path(
  output_dir, "combined_coverage_by_productivity_quartile.csv"))
atomic_csv(score$selection, file.path(
  output_dir, "combined_retained_vs_unsupported.csv"))
atomic_csv(coverage_by_cohort_quartile, file.path(
  output_dir, "pilot_coverage_by_cohort_quartile.csv"))
atomic_csv(coverage_by_deal, file.path(
  output_dir, "pilot_coverage_by_deal.csv"))
atomic_csv(distance_by_cohort_quartile, file.path(
  output_dir, "pilot_nearest_distance_by_cohort_quartile.csv"))
atomic_csv(deal_70_distance, file.path(
  output_dir, "deal_70_nearest_distances.csv"))
atomic_csv(deal_70_dependence, file.path(
  output_dir, "deal_70_dependence.csv"))
atomic_csv(loo, file.path(
  output_dir, "deal_70_leave_one_firm_out_long.csv"))
atomic_csv(loo_summary, file.path(
  output_dir, "deal_70_leave_one_firm_out_summary.csv"))
atomic_csv(cell_diagnostics, file.path(
  output_dir, "pilot_cell_diagnostics.csv"))
atomic_csv(scheme_status, file.path(
  output_dir, "pilot_scheme_status.csv"))

deal_70_coverage <- coverage_by_deal[
  coverage_by_deal$cohort == 2000L &
    coverage_by_deal$deal_id == 70L, ]
lines <- c(
  "# P5.1 U2-clean outcome-blind pilot audit",
  "",
  paste0(
    "- Frozen amendment SHA-256: `",
    LMV2_P5_RESCUE_AMENDMENT_SHA256, "`"),
  paste0(
    "- Industry-support amendment SHA-256: `",
    LMV2_P5_INDUSTRY_SUPPORT_AMENDMENT_SHA256, "`"),
  "- Headline donor universe: U2-clean.",
  "- U3* remains an unestimated coverage-robustness arm.",
  "- No outcome table was read and no treatment effect was estimated.",
  "",
  "## Deal 70",
  "",
  sprintf(
    "- Supported treated inventors: %d/%d (%.2f%%).",
    deal_70_coverage$supported, deal_70_coverage$eligible,
    100 * deal_70_coverage$coverage),
  paste0(
    "- Effective firm count below 2.5 is a design-review trigger, ",
    "not a solver constraint."),
  paste0(
    "- Leave-one-firm-out passes only when every balance-variable shift ",
    "is strictly below 0.10 pooled SD."),
  paste0(
    "- Dependence diagnostics are reported only for schemes that reached ",
    "an accepted weighting solution; failed schemes remain explicit in ",
    "`pilot_scheme_status.csv`."),
  "",
  "## Combined support gates",
  "",
  paste0(
    "- All terminal support gates pass: ",
    if (score$pass) "yes" else "no", "."))
writeLines(
  lines,
  file.path(output_dir, "p5_rescue_pilot_audit.md"),
  useBytes = TRUE)
message(
  "P5.1 U2-clean pilot finalization complete: ", output_dir)
