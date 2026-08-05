# ============================================================================
# 48f_run_lmv2_ppml_robustness.R -- levels-based PPML functional-form check
# ============================================================================
# PPML is fit in levels, never on first differences. Conceptual-unit fixed
# effects absorb permanent inventor-stack differences; cohort-by-event fixed
# effects absorb common cohort-time shocks. The estimation window excludes t=0
# and compares t=1..5 with t=-5..-1. Report exp(beta)-1, not a level ATT.

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (length(hit) != 1L) return(NA_character_)
  sub(paste0("^", flag, "="), "", hit)
}
PANEL_DIR <- get_arg("--panel-dir")
CODE_ROOT <- get_arg("--code-root")
OUTPUT_DIR <- get_arg("--output-dir")
if (any(is.na(c(PANEL_DIR, CODE_ROOT, OUTPUT_DIR)))) {
  stop("48f requires --panel-dir=, --code-root=, and --output-dir=")
}
if (!dir.exists(PANEL_DIR) || !dir.exists(CODE_ROOT)) stop("Input directory missing")
if (dir.exists(OUTPUT_DIR) && length(list.files(
  OUTPUT_DIR, all.files = TRUE, no.. = TRUE
))) stop("Output directory must be new or empty: ", OUTPUT_DIR)

BASE <- normalizePath(CODE_ROOT, mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "digest", "fixest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))

panel_files <- sort(list.files(
  PANEL_DIR, pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE
))
cohorts <- as.integer(sub(
  "^.*_c([0-9]+)\\.parquet$", "\\1", panel_files
))
if (!identical(cohorts, 1993:2010)) stop("Panel cohort set is not 1993:2010")

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
write_csv <- function(x, name) utils::write.csv(
  x, file.path(OUTPUT_DIR, name), row.names = FALSE, na = ""
)
con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='5GB'")
DBI::dbExecute(con, "PRAGMA threads=8")
panel_sql <- lmv2_panel_sql(panel_files)
dat <- DBI::dbGetQuery(con, sprintf(
  paste0(
    "SELECT deal_id, codinv, roster_row_id, cohort, event_time, weight, ",
    "CAST(arm='treated' AS INTEGER) treated, CAST(event_time BETWEEN 1 AND 5 AS INTEGER) post, ",
    "CAST(patent_count AS DOUBLE) patent_count, ",
    "CAST(cohort*100 + event_time + 10 AS INTEGER) cohort_event_id ",
    "FROM %s WHERE event_time BETWEEN -5 AND 5 AND event_time<>0"
  ), panel_sql
))
if (any(!is.finite(dat$weight) | dat$weight <= 0) ||
    any(!is.finite(dat$patent_count) | dat$patent_count < 0)) {
  stop("PPML input certification failed")
}
dat$treated_post <- dat$treated * dat$post

post_model <- fixest::fepois(
  patent_count ~ treated_post | roster_row_id + cohort_event_id,
  data = dat, weights = ~weight, vcov = ~deal_id + codinv,
  fixef.rm = "perfect_fit", notes = FALSE, warn = TRUE
)
b <- unname(stats::coef(post_model)[["treated_post"]])
v <- stats::vcov(post_model)["treated_post", "treated_post"]
se <- sqrt(v)
df <- length(unique(dat$deal_id)) - 1L
crit <- stats::qt(0.975, df)
post <- data.frame(
  outcome = "patent_count",
  estimator = "PPML_levels_unit_FE_cohort_event_FE",
  coefficient_log_rate = b,
  se_log_rate = se,
  df = df,
  ci_low_log_rate = b - crit * se,
  ci_high_log_rate = b + crit * se,
  percent_effect = 100 * (exp(b) - 1),
  ci_low_percent = 100 * (exp(b - crit * se) - 1),
  ci_high_percent = 100 * (exp(b + crit * se) - 1),
  p_value = 2 * stats::pt(-abs(b / se), df),
  n_observations = stats::nobs(post_model),
  stringsAsFactors = FALSE
)
write_csv(post, "ppml_post_effect.csv")

dynamic_model <- fixest::fepois(
  patent_count ~ i(event_time, treated, ref = -1) |
    roster_row_id + cohort_event_id,
  data = dat, weights = ~weight, vcov = ~deal_id + codinv,
  fixef.rm = "perfect_fit", notes = FALSE, warn = TRUE
)
coefs <- stats::coef(dynamic_model)
vc <- stats::vcov(dynamic_model)
event_time <- as.integer(sub(
  ".*event_time::(-?[0-9]+):treated.*", "\\1", names(coefs)
))
dynamic <- data.frame(
  event_time = event_time,
  coefficient_log_rate = unname(coefs),
  se_log_rate = sqrt(diag(vc)),
  percent_effect = 100 * (exp(unname(coefs)) - 1),
  stringsAsFactors = FALSE
)
dynamic$ci_low_percent <- 100 * (
  exp(dynamic$coefficient_log_rate - crit * dynamic$se_log_rate) - 1
)
dynamic$ci_high_percent <- 100 * (
  exp(dynamic$coefficient_log_rate + crit * dynamic$se_log_rate) - 1
)
dynamic <- rbind(dynamic, data.frame(
  event_time = -1L, coefficient_log_rate = 0, se_log_rate = 0,
  percent_effect = 0, ci_low_percent = 0, ci_high_percent = 0
))
dynamic <- dynamic[order(dynamic$event_time), ]
write_csv(dynamic, "ppml_dynamic.csv")

pre_names <- names(coefs)[event_time %in% -5:-2]
pre_b <- coefs[pre_names]
pre_v <- vc[pre_names, pre_names, drop = FALSE]
q <- length(pre_b)
f_stat <- as.numeric(t(pre_b) %*% solve(pre_v, pre_b)) / q
pretrend <- data.frame(
  periods = "-5;-4;-3;-2", f_stat = f_stat, df1 = q, df2 = df,
  p_value = stats::pf(f_stat, q, df, lower.tail = FALSE),
  stringsAsFactors = FALSE
)
write_csv(pretrend, "ppml_pretrend.csv")

manifest <- data.frame(
  version = "lmv2_ppml_robustness_v1",
  amendment_date = "2026-08-03",
  outcome = "integer_patent_count_levels",
  formula = "patent_count ~ treated_post | roster_row_id + cohort_event_id",
  event_window = "-5:-1;1:5",
  inference = "two_way_deal_inventor_cluster",
  interpretation = "multiplicative_rate_not_level_ATT",
  input_observations = nrow(dat),
  estimation_observations = stats::nobs(post_model),
  removed_observations = nrow(dat) - stats::nobs(post_model),
  panel_bundle_sha256 = digest::digest(
    vapply(panel_files, tools::md5sum, character(1)),
    algo = "sha256", serialize = TRUE
  ),
  runner_sha256 = digest::digest(
    file = "02_analysis/R/48f_run_lmv2_ppml_robustness.R",
    algo = "sha256"
  ),
  stringsAsFactors = FALSE
)
write_csv(manifest, "ppml_manifest.csv")
message("PPML robustness complete")
