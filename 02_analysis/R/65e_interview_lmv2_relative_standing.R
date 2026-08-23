# ============================================================================
# 65e_interview_lmv2_relative_standing.R -- explicitly post-results diagnostics
# ============================================================================

# This script is exploratory by construction. It was added after inspecting the
# frozen 65b--65d results and must not be presented as part of the confirmatory
# result family. Its purpose is to locate the source of an unexpected gradient.

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
source(file.path(BASE, "R", "32a_lmv2_vr_heterogeneity_config.R"))
source(file.path(BASE, "R", "65a_lmv2_relative_standing_config.R"))

cfg <- LMV2_RELSTAND
out_dir <- cfg$output_dir
moderator_path <- file.path(out_dir, "relative_standing_moderators.parquet")
frozen_results_path <- file.path(out_dir, "relative_standing_results.csv")
required <- c(
  moderator_path, frozen_results_path, cfg$inputs$vr_unit_analysis,
  file.path(out_dir, "relative_standing_estimation_manifest.csv")
)
if (!all(file.exists(required))) stop("Run and certify 65b--65d first")

estimation_manifest <- utils::read.csv(
  file.path(out_dir, "relative_standing_estimation_manifest.csv"),
  stringsAsFactors = FALSE
)
if (estimation_manifest$moderator_sha256 != digest::digest(
  file = moderator_path, algo = "sha256"
)) stop("The certified moderator has changed")

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, sprintf("PRAGMA threads=%d", cfg$execution$threads))
DBI::dbExecute(con, sprintf(
  "PRAGMA memory_limit='%s'", cfg$execution$memory_limit
))
unit <- DBI::dbGetQuery(con, sprintf("
SELECT
  v.*, r.relative_standing_loss_10pp, r.positive_standing_loss
FROM read_parquet(%s) v
JOIN read_parquet(%s) r USING (roster_row_id)
WHERE r.standing_eligibility='eligible'
", DBI::dbQuoteString(con, normalizePath(
  cfg$inputs$vr_unit_analysis, winslash = "/", mustWork = TRUE
)), DBI::dbQuoteString(con, normalizePath(
  moderator_path, winslash = "/", mustWork = TRUE
))))
unit$treated <- as.numeric(unit$treated)
if (!nrow(unit) || anyDuplicated(unit$roster_row_id)) {
  stop("Eligible unit analysis is empty or duplicated")
}

wmean <- function(x, w) sum(x * w) / sum(w)
wsd <- function(x, w) {
  m <- wmean(x, w)
  sqrt(sum(w * (x - m)^2) / sum(w))
}
prepare <- function(x) {
  z <- lmv2_vr_analysis_weights(x)
  tr <- z$treated == 1
  standardize <- function(v) {
    s <- wsd(v[tr], z$analysis_weight[tr])
    if (!is.finite(s) || s <= 0) stop("Moderator has no treated variation")
    (v - wmean(v[tr], z$analysis_weight[tr])) / s
  }
  center <- function(v) v - wmean(v[tr], z$analysis_weight[tr])

  z$loss_c <- center(z$relative_standing_loss_10pp)
  z$prod_z <- standardize(z$log_patent_count_5y)
  z$trajectory_z <- standardize(z$patent_trajectory)
  z$age_z <- standardize(log1p(z$career_age))
  z$team_any_c <- center(z$team_any)
  positive_team <- tr & z$team_any == 1
  intensity_mean <- if (any(positive_team)) {
    wmean(
      z$persistent_patent_share[positive_team],
      z$analysis_weight[positive_team]
    )
  } else 0
  z$team_intensity <- ifelse(
    z$team_any == 1, z$persistent_patent_share - intensity_mean, 0
  )
  z$positive_slope_c <- center(pmax(z$relative_standing_loss_10pp, 0))
  z$gain_slope_c <- center(pmax(-z$relative_standing_loss_10pp, 0))
  z$tx_loss <- z$treated * z$loss_c
  z$tx_prod <- z$treated * z$prod_z
  z$tx_trajectory <- z$treated * z$trajectory_z
  z$tx_positive_slope <- z$treated * z$positive_slope_c
  z$tx_gain_slope <- z$treated * z$gain_slope_c
  z
}

deal_levels <- sort(unique(unit$deal_id))
deal_multipliers <- lmv2_vr_webb_multipliers(deal_levels, cfg)
common_controls <- c(
  "factor(cohort)", "treated", "prod_z", "trajectory_z", "age_z",
  "team_any_c", "team_intensity"
)

fit_terms <- function(data, outcome, rhs, terms, model, sample) {
  fit <- lmv2_vr_fit_wls(data, outcome, rhs)
  covariance <- lmv2_vr_model_covariance(fit)
  rows <- lapply(seq_along(terms), function(i) {
    ans <- lmv2_vr_linear_result(
      fit, covariance, setNames(1, terms[i]), deal_multipliers,
      terms[i], cfg
    )
    ans$model <- model
    ans$outcome <- outcome
    ans$sample <- sample
    ans$term <- terms[i]
    ans$n_observations <- fit$n
    ans$nominal_deals <- length(unique(fit$deal))
    ans
  })
  do.call(rbind, rows)
}

t0 <- Sys.time()
z <- prepare(unit)
trimmed <- prepare(unit[abs(unit$relative_standing_loss_10pp) <= 2, , drop = FALSE])
results <- list()
k <- 0L
for (outcome_name in names(cfg$estimand$outcomes)) {
  outcome <- unname(cfg$estimand$outcomes[[outcome_name]])

  k <- k + 1L
  results[[k]] <- fit_terms(
    z, outcome,
    c(common_controls, "loss_c", "tx_loss", "tx_prod", "tx_trajectory"),
    c("tx_loss", "tx_prod", "tx_trajectory"),
    "trajectory_horse_race", "eligible_1993_2010"
  )

  k <- k + 1L
  results[[k]] <- fit_terms(
    z, outcome,
    c(
      common_controls, "positive_slope_c", "gain_slope_c", "tx_prod",
      "tx_trajectory", "tx_positive_slope", "tx_gain_slope"
    ),
    c("tx_positive_slope", "tx_gain_slope"),
    "piecewise_loss_gain", "eligible_1993_2010"
  )

  k <- k + 1L
  results[[k]] <- fit_terms(
    trimmed, outcome,
    c(common_controls, "loss_c", "tx_loss", "tx_prod", "tx_trajectory"),
    "tx_loss", "common_support_20pp", "absolute_loss_or_gain_le20pp"
  )
}
results <- do.call(rbind, results)
results$outcome <- ifelse(
  results$outcome == cfg$estimand$outcomes[["patent_count"]],
  "patent_count", "active_patenting"
)
utils::write.csv(
  results, file.path(out_dir, "relative_standing_interview_results.csv"),
  row.names = FALSE
)

pick <- function(outcome, model, term) {
  x <- results[
    results$outcome == outcome & results$model == model & results$term == term,
    , drop = FALSE
  ]
  if (nrow(x) != 1L) stop("Interview result grid is incomplete")
  x
}
fmt <- function(x) formatC(x, digits = 3, format = "f")
fmt_p <- function(x) ifelse(x < 0.001, "<0.001", fmt(x))
p_traj <- pick("patent_count", "trajectory_horse_race", "tx_loss")
p_pos <- pick("patent_count", "piecewise_loss_gain", "tx_positive_slope")
p_gain <- pick("patent_count", "piecewise_loss_gain", "tx_gain_slope")
p_trim <- pick("patent_count", "common_support_20pp", "tx_loss")

memo <- c(
  "# Post-results interview of the relative-standing estimate",
  "",
  "These diagnostics were specified after seeing the frozen result. They are",
  "exploratory and do not enlarge or replace the confirmatory result family.",
  "",
  sprintf(
    paste0(
      "With a treatment--pre-deal-trajectory interaction added, the patent ",
      "standing-loss gradient is %s (95%% CI [%s, %s]; governing p=%s)."
    ),
    fmt(p_traj$estimate), fmt(p_traj$ci_low), fmt(p_traj$ci_high),
    fmt_p(p_traj$governing_p)
  ),
  sprintf(
    paste0(
      "In the piecewise model, the slope for actual predicted losses is %s ",
      "(95%% CI [%s, %s]; p=%s), while the slope for the absolute size of a ",
      "predicted rank gain is %s (95%% CI [%s, %s]; p=%s)."
    ),
    fmt(p_pos$estimate), fmt(p_pos$ci_low), fmt(p_pos$ci_high),
    fmt_p(p_pos$governing_p), fmt(p_gain$estimate), fmt(p_gain$ci_low),
    fmt(p_gain$ci_high), fmt_p(p_gain$governing_p)
  ),
  sprintf(
    paste0(
      "Restricting the sample to predicted changes within plus or minus 20 ",
      "percentage points gives a gradient of %s (95%% CI [%s, %s]; p=%s)."
    ),
    fmt(p_trim$estimate), fmt(p_trim$ci_low), fmt(p_trim$ci_high),
    fmt_p(p_trim$governing_p)
  )
)
writeLines(
  memo, file.path(out_dir, "relative_standing_interview.md"), useBytes = TRUE
)

manifest <- data.frame(
  status = "exploratory_post_results",
  frozen_results_sha256 = digest::digest(
    file = frozen_results_path, algo = "sha256"
  ),
  interview_results_sha256 = digest::digest(
    file = file.path(out_dir, "relative_standing_interview_results.csv"),
    algo = "sha256"
  ),
  full_treated_inventors = sum(z$treated == 1),
  trimmed_treated_inventors = sum(trimmed$treated == 1),
  bootstrap_replications = cfg$inference$bootstrap_replications,
  runtime_minutes = as.numeric(difftime(Sys.time(), t0, units = "mins")),
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(out_dir, "relative_standing_interview_manifest.csv"),
  row.names = FALSE
)
message("Post-results relative-standing interview complete.")
