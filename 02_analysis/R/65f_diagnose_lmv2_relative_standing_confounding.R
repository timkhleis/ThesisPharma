# ============================================================================
# 65f_diagnose_lmv2_relative_standing_confounding.R
# Post-results diagnostics for the corrected relative-standing construction.
# This script does not alter the frozen P5c roster or headline ATT.
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "digest", "MASS", "WeightIt", "fixest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))
source(file.path(BASE, "R", "32a_lmv2_vr_heterogeneity_config.R"))
source(file.path(BASE, "R", "65a_lmv2_relative_standing_config.R"))

cfg <- LMV2_RELSTAND
root_dir <- cfg$output_dir
out_dir <- file.path(root_dir, "diagnostics_v2")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
moderator_path <- file.path(root_dir, "relative_standing_moderators.parquet")
frozen_path <- file.path(root_dir, "relative_standing_results.csv")
required <- c(moderator_path, frozen_path, cfg$inputs$vr_unit_analysis)
if (!all(file.exists(required))) stop("Run the corrected 65b--65d package first")

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, sprintf("PRAGMA threads=%d", cfg$execution$threads))
DBI::dbExecute(con, sprintf("PRAGMA memory_limit='%s'", cfg$execution$memory_limit))

unit <- DBI::dbGetQuery(con, sprintf("
SELECT
  v.*, r.focal_patents_5y, r.focal_inventors, r.combined_inventors,
  r.relative_standing_loss_10pp, r.relative_standing_loss_pp,
  r.positive_standing_loss
FROM read_parquet(%s) v
JOIN read_parquet(%s) r USING (roster_row_id)
WHERE r.standing_eligibility='eligible'
", DBI::dbQuoteString(con, normalizePath(
  cfg$inputs$vr_unit_analysis, winslash = "/", mustWork = TRUE
)), DBI::dbQuoteString(con, normalizePath(
  moderator_path, winslash = "/", mustWork = TRUE
))))
unit$treated <- as.numeric(unit$treated)

panel_files <- sort(list.files(
  cfg$inputs$panel_dir,
  pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE
))
panel_sql <- lmv2_panel_sql(panel_files)
pre_path <- DBI::dbGetQuery(con, sprintf("
SELECT roster_row_id,
  MAX(CASE WHEN event_time=-5 THEN patent_count END) patent_m5,
  MAX(CASE WHEN event_time=-4 THEN patent_count END) patent_m4,
  MAX(CASE WHEN event_time=-3 THEN patent_count END) patent_m3,
  MAX(CASE WHEN event_time=-2 THEN patent_count END) patent_m2,
  MAX(CASE WHEN event_time=-1 THEN patent_count END) patent_m1
FROM %s
WHERE event_time BETWEEN -5 AND -1
GROUP BY roster_row_id
", panel_sql))
unit <- merge(unit, pre_path, by = "roster_row_id", sort = FALSE)
if (!nrow(unit) || anyDuplicated(unit$roster_row_id) ||
    anyNA(unit[paste0("patent_m", 5:1)])) {
  stop("Diagnostic unit panel is empty, duplicated, or missing pre-periods")
}

wmean <- function(x, w) sum(x * w) / sum(w)
wsd <- function(x, w) {
  m <- wmean(x, w)
  sqrt(sum(w * (x - m)^2) / sum(w))
}

add_balance_variables <- function(x) {
  x$bal_loss <- x$relative_standing_loss_10pp
  x$bal_loss_sq <- x$bal_loss^2
  x$bal_logprod <- x$log_patent_count_5y
  x$bal_logprod_sq <- x$bal_logprod^2
  x$bal_trajectory <- x$patent_trajectory
  x$bal_pre_ref <- x$patent_pre_ref
  x$bal_age <- log1p(x$career_age)
  x$bal_tenure <- log1p(x$focal_group_tenure)
  x$bal_exclusivity <- x$focal_group_exclusivity
  x$bal_team_any <- x$team_any
  x$bal_team_intensity <- ifelse(
    x$team_any == 1, x$persistent_patent_share, 0
  )
  x$bal_focal_size <- log1p(x$focal_inventors)
  x$bal_added_size <- log1p(pmax(x$combined_inventors - x$focal_inventors, 0))
  for (k in 5:2) x[[paste0("bal_dm", k)]] <- x[[paste0("patent_m", k)]] - x$patent_m1
  x$bal_loss_prod <- x$bal_loss * x$bal_logprod
  x$bal_loss_trajectory <- x$bal_loss * x$bal_trajectory
  x$bal_loss_pre_ref <- x$bal_loss * x$bal_pre_ref
  x$bal_loss_focal_size <- x$bal_loss * x$bal_focal_size
  x$bal_loss_added_size <- x$bal_loss * x$bal_added_size
  x
}
unit <- add_balance_variables(unit)

rebalance_vars <- c(
  "bal_loss", "bal_logprod", "bal_trajectory", "bal_pre_ref",
  "bal_age", "bal_tenure", "bal_exclusivity", "bal_team_any",
  "bal_team_intensity", "bal_focal_size", "bal_added_size",
  paste0("bal_dm", 5:2)
)
balance_vars <- c(
  "bal_loss", "bal_loss_sq", "bal_logprod", "bal_logprod_sq",
  "bal_trajectory", "bal_pre_ref", "bal_age", "bal_tenure",
  "bal_exclusivity", "bal_team_any", "bal_team_intensity",
  "bal_focal_size", "bal_added_size", paste0("bal_dm", 5:2),
  "bal_loss_prod", "bal_loss_trajectory", "bal_loss_pre_ref",
  "bal_loss_focal_size", "bal_loss_added_size"
)

entropy_rebalance <- function(x) {
  q <- x
  scale_rows <- lapply(rebalance_vars, function(v) {
    s <- stats::sd(q[[v]])
    m <- mean(q[[v]])
    ok <- is.finite(s) && s > 1e-10
    if (ok) q[[v]] <<- (q[[v]] - m) / s else q[[v]] <<- 0
    data.frame(variable = v, nondegenerate = ok)
  })
  use <- do.call(rbind, scale_rows)
  use <- use$variable[use$nondegenerate]
  form <- stats::as.formula(paste(
    "treated ~ factor(cohort) +", paste(use, collapse = " + ")
  ))
  fit <- tryCatch(
    WeightIt::weightit(
      form, data = q, method = "ebal", estimand = "ATT", moments = 1,
      s.weights = q$raw_weight, maxit = 5000
    ),
    error = function(e) e
  )
  if (inherits(fit, "condition")) {
    stop("Global augmented entropy balance failed: ", fit$message)
  }
  final_weight <- ifelse(
    q$treated == 1, q$raw_weight, q$raw_weight * fit$weights
  )
  final_weight[q$treated == 0] <- final_weight[q$treated == 0] *
    sum(final_weight[q$treated == 1]) / sum(final_weight[q$treated == 0])
  if (any(!is.finite(final_weight)) || any(final_weight <= 0)) {
    stop("Invalid global augmented entropy weights")
  }
  q$raw_weight_aug <- final_weight
  diagnostics <- do.call(rbind, lapply(cfg$estimand$cohorts, function(g) {
    r <- q[q$cohort == g, , drop = FALSE]
    control_w <- r$raw_weight_aug[r$treated == 0]
    data.frame(
      cohort = g, treated_n = sum(r$treated == 1),
      control_n = sum(r$treated == 0),
      control_ess = sum(control_w)^2 / sum(control_w^2),
      max_control_share = max(control_w) / sum(control_w),
      stringsAsFactors = FALSE
    )
  }))
  list(
    weights = q[, c("roster_row_id", "raw_weight_aug")],
    diagnostics = diagnostics
  )
}

ebal <- entropy_rebalance(unit)
unit_ebal <- merge(unit, ebal$weights, by = "roster_row_id", sort = FALSE)
unit_ebal$raw_weight <- unit_ebal$raw_weight_aug

prepare <- function(x) {
  z <- lmv2_vr_analysis_weights(x)
  tr <- z$treated == 1
  center <- function(v) v - wmean(v[tr], z$analysis_weight[tr])
  standardize <- function(v) {
    s <- wsd(v[tr], z$analysis_weight[tr])
    if (!is.finite(s) || s <= 0) stop("Degenerate diagnostic covariate")
    center(v) / s
  }
  z$loss_c <- center(z$relative_standing_loss_10pp)
  z$prod_z <- standardize(z$log_patent_count_5y)
  z$prod_sq_z <- standardize(z$prod_z^2)
  z$trajectory_z <- standardize(z$patent_trajectory)
  z$pre_ref_z <- standardize(z$patent_pre_ref)
  z$age_z <- standardize(log1p(z$career_age))
  z$tenure_z <- standardize(log1p(z$focal_group_tenure))
  z$exclusivity_z <- standardize(z$focal_group_exclusivity)
  z$team_any_c <- center(z$team_any)
  positive <- tr & z$team_any == 1
  team_mean <- wmean(
    z$persistent_patent_share[positive], z$analysis_weight[positive]
  )
  z$team_intensity <- ifelse(
    z$team_any == 1, z$persistent_patent_share - team_mean, 0
  )
  z$focal_size_z <- standardize(log1p(z$focal_inventors))
  z$added_size_z <- standardize(log1p(pmax(
    z$combined_inventors - z$focal_inventors, 0
  )))
  for (k in 5:2) {
    nm <- paste0("dm", k, "_z")
    z[[nm]] <- standardize(z[[paste0("patent_m", k)]] - z$patent_m1)
  }
  interact <- c(
    "loss_c", "prod_z", "prod_sq_z", "trajectory_z", "pre_ref_z",
    "age_z", "tenure_z", "exclusivity_z", "team_any_c",
    "team_intensity", "focal_size_z", "added_size_z",
    paste0("dm", 5:2, "_z")
  )
  for (v in interact) z[[paste0("tx_", v)]] <- z$treated * z[[v]]
  z$tx_loss <- z$tx_loss_c
  z
}

base <- prepare(unit)
aug <- prepare(unit_ebal)
base_rhs <- c(
  "factor(cohort)", "treated", "loss_c", "prod_z", "age_z",
  "team_any_c", "team_intensity", "tx_loss"
)
full_controls <- c(
  "prod_z", "prod_sq_z", "trajectory_z", "pre_ref_z", "age_z",
  "tenure_z", "exclusivity_z", "team_any_c", "team_intensity",
  "focal_size_z", "added_size_z", paste0("dm", 5:2, "_z")
)
full_rhs <- c(
  "factor(cohort)", "treated", "loss_c", full_controls, "tx_loss",
  paste0("tx_", full_controls)
)

deal_levels <- sort(unique(base$deal_id))
deal_multipliers <- lmv2_vr_webb_multipliers(deal_levels, cfg)
fit_spec <- function(data, outcome, rhs, specification, weighting) {
  fit <- lmv2_vr_fit_wls(data, outcome, rhs)
  covariance <- lmv2_vr_model_covariance(fit)
  ans <- lmv2_vr_linear_result(
    fit, covariance, c(tx_loss = 1), deal_multipliers,
    "ATT gradient per 10pp predicted standing loss", cfg
  )
  ans$specification <- specification
  ans$weighting <- weighting
  ans$outcome <- outcome
  ans$n_observations <- fit$n
  ans
}

t0 <- Sys.time()
results <- rbind(
  fit_spec(base, "d_patent_ref", base_rhs, "corrected_frozen", "P5c"),
  fit_spec(base, "d_patent_ref", full_rhs, "fully_interacted_predeal", "P5c"),
  fit_spec(base, "d_patent_5x5", full_rhs, "fully_interacted_five_by_five", "P5c"),
  fit_spec(aug, "d_patent_ref", base_rhs, "corrected_frozen", "augmented_ebal"),
  fit_spec(aug, "d_patent_ref", full_rhs, "fully_interacted_predeal", "augmented_ebal"),
  fit_spec(aug, "d_patent_5x5", full_rhs, "fully_interacted_five_by_five", "augmented_ebal")
)
utils::write.csv(
  results, file.path(out_dir, "relative_standing_confounding_results.csv"),
  row.names = FALSE
)

balance_smd <- function(x, vars, weighting) {
  rows <- lapply(vars, function(v) {
    arm <- lapply(0:1, function(a) {
      q <- x[x$treated == a, , drop = FALSE]
      m <- wmean(q[[v]], q$analysis_weight)
      vv <- wmean((q[[v]] - m)^2, q$analysis_weight)
      c(mean = m, variance = vv)
    })
    denom <- sqrt(mean(vapply(arm, `[[`, numeric(1), "variance")))
    data.frame(
      weighting = weighting, variable = v,
      smd = (arm[[2]]["mean"] - arm[[1]]["mean"]) / denom
    )
  })
  do.call(rbind, rows)
}
balance <- rbind(
  balance_smd(base, balance_vars, "P5c"),
  balance_smd(aug, balance_vars, "augmented_ebal")
)
utils::write.csv(
  balance, file.path(out_dir, "relative_standing_augmented_balance.csv"),
  row.names = FALSE
)
utils::write.csv(
  ebal$diagnostics,
  file.path(out_dir, "relative_standing_augmented_weight_diagnostics.csv"),
  row.names = FALSE
)

region <- function(x) {
  cut(
    x, breaks = c(-Inf, -0.5, 0, 0.5, Inf), right = TRUE,
    labels = c("gain_gt_5pp", "gain_0_to_5pp", "no_change_to_loss_5pp",
               "loss_gt_5pp")
  )
}
region_rows <- lapply(list(P5c = base, augmented_ebal = aug), function(z) {
  z$region <- region(z$relative_standing_loss_10pp)
  do.call(rbind, lapply(levels(z$region), function(g) {
    q <- z[z$region == g, , drop = FALSE]
    arm <- lapply(0:1, function(a) {
      u <- q[q$treated == a, , drop = FALSE]
      c(n = nrow(u), mean = wmean(u$d_patent_ref, u$analysis_weight))
    })
    data.frame(
      region = g, control_n = arm[[1]]["n"], treated_n = arm[[2]]["n"],
      control_change = arm[[1]]["mean"], treated_change = arm[[2]]["mean"],
      descriptive_att = arm[[2]]["mean"] - arm[[1]]["mean"]
    )
  }))
})
region_table <- do.call(rbind, Map(function(x, nm) {
  x$weighting <- nm
  x
}, region_rows, names(region_rows)))
utils::write.csv(
  region_table, file.path(out_dir, "relative_standing_region_descriptives.csv"),
  row.names = FALSE
)

fit_fe <- function(z, weighting) {
  z$deal_arm <- interaction(z$deal_id, z$treated, drop = TRUE)
  rhs <- paste(c("loss_c", full_controls, "tx_loss",
                 paste0("tx_", full_controls)), collapse = " + ")
  fit <- fixest::feols(
    stats::as.formula(paste("d_patent_ref ~", rhs, "| deal_arm")),
    data = z, weights = ~analysis_weight, cluster = ~deal_id + codinv,
    lean = TRUE, notes = FALSE
  )
  ci <- stats::confint(fit, "tx_loss")
  data.frame(
    weighting = weighting,
    specification = "fully_interacted_with_deal_by_arm_fixed_effects",
    estimate = unname(stats::coef(fit)["tx_loss"]),
    two_way_se = unname(fixest::se(fit)["tx_loss"]),
    p_value = unname(fixest::pvalue(fit)["tx_loss"]),
    ci_low = unname(ci[1]), ci_high = unname(ci[2]),
    n_observations = stats::nobs(fit)
  )
}
fe_results <- rbind(fit_fe(base, "P5c"), fit_fe(aug, "augmented_ebal"))
utils::write.csv(
  fe_results, file.path(out_dir, "relative_standing_deal_arm_fe.csv"),
  row.names = FALSE
)

frozen <- utils::read.csv(frozen_path, stringsAsFactors = FALSE)
frozen_est <- frozen$estimate[
  frozen$outcome == "patent_count" & frozen$model == "standing_primary"
]
checks <- data.frame(
  check = c(
    "corrected_frozen_estimate_reproduced",
    "all_cohorts_rebalanced",
    "augmented_balance_below_0_10",
    "control_pool_size_no_longer_arm_specific"
  ),
  pass = c(
    length(frozen_est) == 1L &&
      abs(results$estimate[1] - frozen_est) < 1e-10,
    nrow(ebal$diagnostics) == length(cfg$estimand$cohorts),
    max(abs(balance$smd[
      balance$weighting == "augmented_ebal" &
        balance$variable %in% rebalance_vars
    ])) < 0.10,
    abs(wmean(base$combined_inventors[base$treated == 1],
              base$analysis_weight[base$treated == 1]) /
        wmean(base$combined_inventors[base$treated == 0],
              base$analysis_weight[base$treated == 0]) - 1) < 0.50
  )
)
utils::write.csv(
  checks, file.path(out_dir, "relative_standing_confounding_certification.csv"),
  row.names = FALSE
)

manifest <- data.frame(
  status = "exploratory_post_results_corrected_confounding_audit",
  relative_standing_version = LMV2_RELSTAND_VERSION,
  moderator_sha256 = digest::digest(file = moderator_path, algo = "sha256"),
  result_sha256 = digest::digest(
    file = file.path(out_dir, "relative_standing_confounding_results.csv"),
    algo = "sha256"
  ),
  treated_inventors = sum(base$treated == 1),
  control_rows = sum(base$treated == 0),
  bootstrap_replications = cfg$inference$bootstrap_replications,
  runtime_minutes = as.numeric(difftime(Sys.time(), t0, units = "mins"))
)
utils::write.csv(
  manifest, file.path(out_dir, "relative_standing_confounding_manifest.csv"),
  row.names = FALSE
)
message("Relative-standing confounding audit complete.")
