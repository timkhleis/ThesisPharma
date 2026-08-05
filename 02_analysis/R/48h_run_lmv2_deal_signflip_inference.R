# ============================================================================
# 48h_run_lmv2_deal_signflip_inference.R
# ============================================================================
# Paired deal-stack sign-flip diagnostic for the headline post ATT. Because
# acquisition is observational, this is explicitly not presented as exact
# design-based randomization inference. It asks whether the result survives a
# sharp-null exchangeability exercise at the treated-deal stack level.

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (length(hit) != 1L) return(NA_character_)
  sub(paste0("^", flag, "="), "", hit)
}
PANEL_DIR <- get_arg("--panel-dir")
CODE_ROOT <- get_arg("--code-root")
OUTPUT_DIR <- get_arg("--output-dir")
REPS_ARG <- get_arg("--reps")
if (any(is.na(c(PANEL_DIR, CODE_ROOT, OUTPUT_DIR)))) {
  stop("48h requires --panel-dir=, --code-root=, and --output-dir=")
}
REPS <- if (is.na(REPS_ARG)) 99999L else as.integer(REPS_ARG)
if (!is.finite(REPS) || REPS < 999L) stop("--reps must be at least 999")
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
for (pkg in c("DBI", "duckdb", "digest")) {
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
panel_sql <- lmv2_panel_sql(panel_files)

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='5GB'")
DBI::dbExecute(con, "PRAGMA threads=8")
pair <- lmv2_build_pair_table(
  con, panel_sql, "patent_count", cohorts, "signflip_all18"
)
influence <- lmv2_prepare_influence_table(con, pair, panel_sql, cohorts)
DBI::dbExecute(con, sprintf("DROP TABLE %s", pair))
post_sql <- paste(LMV2_P6_ESTIMATION$post_window, collapse = ",")
deal <- DBI::dbGetQuery(con, sprintf(
  paste0(
    "SELECT deal_id, SUM(contribution)/%d AS post_contribution ",
    "FROM %s WHERE event_time IN (%s) GROUP BY deal_id ORDER BY deal_id"
  ), length(LMV2_P6_ESTIMATION$post_window), influence, post_sql
))
DBI::dbExecute(con, sprintf("DROP TABLE %s", influence))
if (nrow(deal) < 2L || any(!is.finite(deal$post_contribution))) {
  stop("Invalid deal contributions")
}
observed <- sum(deal$post_contribution)

set.seed(20260803L)
exceed <- 0L
null_sum <- 0
null_sq_sum <- 0
remaining <- REPS
chunk <- 5000L
while (remaining > 0L) {
  b <- min(chunk, remaining)
  signs <- matrix(
    sample(c(-1, 1), nrow(deal) * b, replace = TRUE),
    nrow = nrow(deal), ncol = b
  )
  draws <- as.numeric(crossprod(deal$post_contribution, signs))
  exceed <- exceed + sum(abs(draws) >= abs(observed))
  null_sum <- null_sum + sum(draws)
  null_sq_sum <- null_sq_sum + sum(draws^2)
  remaining <- remaining - b
}
p_value <- (exceed + 1) / (REPS + 1)
null_mean <- null_sum / REPS
null_sd <- sqrt((null_sq_sum - REPS * null_mean^2) / (REPS - 1))

result <- data.frame(
  outcome = "patent_count",
  statistic = "average_annual_t1_to_t5_ATT",
  observed = observed,
  replications = REPS,
  two_sided_p_value = p_value,
  null_mean = null_mean,
  null_sd = null_sd,
  nominal_deals = nrow(deal),
  interpretation = paste(
    "paired deal-stack sign-flip diagnostic; observational acquisition",
    "assignment prevents an exact design-based randomization claim"
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  result, file.path(OUTPUT_DIR, "deal_signflip_result.csv"),
  row.names = FALSE, na = ""
)
utils::write.csv(
  deal, file.path(OUTPUT_DIR, "deal_post_contributions.csv"),
  row.names = FALSE, na = ""
)
manifest <- data.frame(
  version = "lmv2_deal_signflip_v1",
  seed = 20260803L,
  replications = REPS,
  sharp_null = "deal_stack_treated_control_label_exchangeability",
  exact_randomization_inference = FALSE,
  reason_not_exact = "observational_nonrandom_acquisition_assignment",
  panel_bundle_sha256 = digest::digest(
    vapply(panel_files, tools::md5sum, character(1)),
    algo = "sha256", serialize = TRUE
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(OUTPUT_DIR, "deal_signflip_manifest.csv"),
  row.names = FALSE, na = ""
)
message("Deal-stack sign-flip diagnostic complete: p=", format(p_value))
