# ============================================================================
# 33d_estimate_lmv2_stayer_heterogeneity.R -- stayer effects and decomposition
# ============================================================================

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
source(file.path(BASE, "R", "33a_lmv2_stayer_heterogeneity_config.R"))

cfg <- LMV2_STAYER_HET
out_dir <- cfg$output_dir
unit_path <- file.path(out_dir, "stayer_unit_analysis.parquet")
power_path <- file.path(out_dir, "stayer_power_gate.csv")
power_manifest_path <- file.path(out_dir, "power_gate_manifest.csv")
required <- c(
  unit_path, power_path, power_manifest_path,
  file.path(out_dir, "moderator_build_manifest.csv")
)
if (!all(file.exists(required))) {
  stop("Run 33b and 33c before opening stayer heterogeneity estimates")
}
power_manifest <- utils::read.csv(
  power_manifest_path, stringsAsFactors = FALSE
)
if (nrow(power_manifest) != 1L ||
    power_manifest$design_hash != lmv2_stayer_het_hash() ||
    power_manifest$unit_analysis_sha256 != digest::digest(
      file = unit_path, algo = "sha256"
    ) ||
    !isTRUE(power_manifest$aggregate_att_reproduction_pass) ||
    power_manifest$heterogeneity_point_estimates_written != 0L) {
  stop("Stayer power stage or unit table is stale")
}
power <- utils::read.csv(power_path, stringsAsFactors = FALSE)
if (nrow(power) != 8L) stop("Frozen stayer 4 x 2 power family is incomplete")

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
unit <- DBI::dbGetQuery(con, sprintf(
  "SELECT * FROM read_parquet(%s)",
  DBI::dbQuoteString(
    con, normalizePath(unit_path, winslash = "/", mustWork = TRUE)
  )
))
deal_levels <- sort(unique(unit$deal_id))
deal_multipliers <- lmv2_vr_webb_multipliers(deal_levels, cfg)
t0 <- Sys.time()

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
  ),
  focal_tenure = list(
    techfit = NULL,
    rhs = c(common_rhs, "tenure_z", "tx_tenure"),
    term = "tx_tenure"
  )
)
outcomes_ref <- c(
  patent_count = "d_patent_ref",
  active_patenting = "d_active_ref"
)
outcomes_5x5 <- c(
  patent_count = "d_patent_5x5",
  active_patenting = "d_active_5x5"
)

marginal_contrasts <- function(prepared, moderator) {
  c0 <- c(treated = 1)
  if (moderator == "predeal_productivity") {
    q <- prepared$contrasts$prod_raw_quantiles
    z <- lmv2_vr_weighted_quantile(
      prepared$data$prod_z[prepared$data$treated == 1],
      prepared$data$analysis_weight[prepared$data$treated == 1],
      c(.25, .75)
    )
    return(list(
      low = c(c0, tx_prod = z[1]),
      high = c(c0, tx_prod = z[2]), raw = q
    ))
  }
  if (moderator == "career_age") {
    q <- prepared$contrasts$age_raw_quantiles
    z <- lmv2_vr_weighted_quantile(
      prepared$data$age_z[prepared$data$treated == 1],
      prepared$data$analysis_weight[prepared$data$treated == 1],
      c(.25, .75)
    )
    return(list(
      low = c(c0, tx_age = z[1]),
      high = c(c0, tx_age = z[2]), raw = expm1(q)
    ))
  }
  if (moderator == "team_persistence") {
    p <- prepared$contrasts$team_any_mean
    return(list(
      low = c(c0, tx_team_any = -p),
      high = c(c0, tx_team_any = 1 - p), raw = c(0, 1)
    ))
  }
  if (moderator == "techfit") {
    q <- prepared$contrasts$techfit_raw_quantiles
    z <- lmv2_vr_weighted_quantile(
      prepared$data$techfit_z[prepared$data$treated == 1],
      prepared$data$analysis_weight[prepared$data$treated == 1],
      c(.25, .75)
    )
    return(list(
      low = c(c0, tx_techfit = z[1]),
      high = c(c0, tx_techfit = z[2]), raw = q
    ))
  }
  if (moderator == "focal_tenure") {
    q <- prepared$contrasts$tenure_raw_quantiles
    z <- lmv2_vr_weighted_quantile(
      prepared$data$tenure_z[prepared$data$treated == 1],
      prepared$data$analysis_weight[prepared$data$treated == 1],
      c(.25, .75)
    )
    return(list(
      low = c(c0, tx_tenure = z[1]),
      high = c(c0, tx_tenure = z[2]), raw = q
    ))
  }
  stop("Unknown moderator: ", moderator)
}

add_two_way_interval <- function(z, covariance) {
  critical <- stats::qt(
    1 - (1 - cfg$inference$confidence_level) / 2,
    covariance$df_two
  )
  z$two_way_ci_low <- z$estimate - critical * z$two_way_se
  z$two_way_ci_high <- z$estimate + critical * z$two_way_se
  z$two_way_df <- covariance$df_two
  z
}

run_one <- function(
    moderator, outcome, outcome_col, sample_name, cohorts, window,
    model_type = "separate_primary", techfit_override = NULL) {
  spec <- model_spec[[moderator]]
  techfit <- if (is.null(techfit_override)) spec$techfit else techfit_override
  prepared <- lmv2_stayer_prepare_data(unit, cohorts, techfit)
  fit <- lmv2_vr_fit_wls(prepared$data, outcome_col, spec$rhs)
  covariance <- lmv2_vr_model_covariance(fit)
  focal <- lmv2_vr_linear_result(
    fit, covariance,
    setNames(unname(prepared$contrasts[[moderator]]), spec$term),
    deal_multipliers, cfg$estimand$focal_contrast[[moderator]], cfg
  )
  marg <- marginal_contrasts(prepared, moderator)
  low <- lmv2_vr_linear_result(
    fit, covariance, marg$low, deal_multipliers,
    "predicted ATT at low moderator value", cfg
  )
  high <- lmv2_vr_linear_result(
    fit, covariance, marg$high, deal_multipliers,
    "predicted ATT at high moderator value", cfg
  )
  focal <- add_two_way_interval(focal, covariance)
  low <- add_two_way_interval(low, covariance)
  high <- add_two_way_interval(high, covariance)
  add_meta <- function(z, result_type, raw_value = NA_real_) {
    z$moderator <- moderator
    z$outcome <- outcome
    z$sample <- sample_name
    z$window <- window
    z$model_type <- model_type
    z$techfit_variant <- ifelse(
      is.null(techfit), "not_applicable", techfit
    )
    z$result_type <- result_type
    z$moderator_raw_value <- raw_value
    z$treated_inventors <- sum(prepared$data$treated == 1)
    z$nominal_deals <- length(unique(
      prepared$data$deal_id[prepared$data$treated == 1]
    ))
    z
  }
  focal <- add_meta(focal, "focal_contrast")
  low <- add_meta(low, "low_marginal_effect", marg$raw[1])
  high <- add_meta(high, "high_marginal_effect", marg$raw[2])
  for (field in c(
    "predeal_annual_patent_stock", "effect_as_share_predeal_output"
  )) {
    focal[[field]] <- low[[field]] <- high[[field]] <- NA_real_
  }
  if (moderator == "predeal_productivity" && outcome == "patent_count") {
    low$predeal_annual_patent_stock <- expm1(marg$raw[1]) / 5
    high$predeal_annual_patent_stock <- expm1(marg$raw[2]) / 5
    low$effect_as_share_predeal_output <-
      low$estimate / low$predeal_annual_patent_stock
    high$effect_as_share_predeal_output <-
      high$estimate / high$predeal_annual_patent_stock
  }
  rbind(focal, low, high)
}

run_grid <- function(
    moderators, sample_name, cohorts, outcomes, window, model_type) {
  rows <- list()
  for (moderator in moderators) {
    for (outcome in names(outcomes)) {
      message(
        "Estimating ", sample_name, " / ", moderator, " / ", outcome
      )
      rows[[length(rows) + 1L]] <- run_one(
        moderator, outcome, outcomes[[outcome]], sample_name, cohorts,
        window, model_type
      )
    }
  }
  do.call(rbind, rows)
}

primary_mods <- cfg$construction$primary_moderators
all_results <- list(
  run_grid(
    primary_mods, "full_1993_2010",
    cfg$estimand$samples$full_1993_2010, outcomes_ref,
    "post_mean_minus_t_minus_1", "separate_primary"
  ),
  run_grid(
    primary_mods, "full_1993_2010",
    cfg$estimand$samples$full_1993_2010, outcomes_5x5,
    "five_post_minus_five_pre", "five_by_five_companion"
  ),
  run_grid(
    "focal_tenure", "full_1993_2010",
    cfg$estimand$samples$full_1993_2010, outcomes_ref,
    "post_mean_minus_t_minus_1", "tenure_appendix"
  )
)
techfit_5y <- lapply(names(outcomes_ref), function(outcome) {
  run_one(
    "techfit", outcome, outcomes_ref[[outcome]], "full_1993_2010",
    cfg$estimand$samples$full_1993_2010,
    "post_mean_minus_t_minus_1", "techfit_five_year_robustness", "5y"
  )
})
all_results[[length(all_results) + 1L]] <- do.call(rbind, techfit_5y)
results <- do.call(rbind, all_results)

primary <- results$result_type == "focal_contrast" &
  results$sample == "full_1993_2010" &
  results$window == "post_mean_minus_t_minus_1" &
  results$model_type == "separate_primary" &
  results$techfit_variant %in% c("not_applicable", "full")
if (sum(primary) != 8L) stop("Primary stayer 4 x 2 family is incomplete")
results$holm_adjusted_governing_p <- NA_real_
results$holm_adjusted_governing_p[primary] <- stats::p.adjust(
  results$governing_p[primary], method = "holm"
)
results$power_gate_pass <- NA
results$precision_mde <- NA_real_
results$meaningful_threshold <- NA_real_
results$type_m_exaggeration_ratio_at_threshold <- NA_real_
results$reporting_status <- "appendix_robustness_or_marginal_effect"
for (i in which(primary)) {
  p <- power[
    power$moderator == results$moderator[i] &
      power$outcome == results$outcome[i], ,
    drop = FALSE
  ]
  if (nrow(p) != 1L) stop("Missing stayer power row")
  results$power_gate_pass[i] <- p$power_gate_pass
  results$precision_mde[i] <- p$mde
  results$meaningful_threshold[i] <- p$meaningful_threshold
  results$type_m_exaggeration_ratio_at_threshold[i] <-
    p$type_m_exaggeration_ratio_at_threshold
  results$reporting_status[i] <- "included_primary_heterogeneity_table"
}

# Aggregate effects are independently reconstructed for both windows.
aggregate_rows <- list()
for (sample_name in names(cfg$estimand$samples)) {
  prepared <- lmv2_stayer_prepare_data(
    unit, cfg$estimand$samples[[sample_name]]
  )
  for (window in c("ref", "5x5")) {
    outcomes <- if (window == "ref") outcomes_ref else outcomes_5x5
    for (outcome in names(outcomes)) {
      fit <- lmv2_vr_fit_wls(
        prepared$data, outcomes[[outcome]],
        c("factor(cohort)", "treated")
      )
      covariance <- lmv2_vr_model_covariance(fit)
      z <- lmv2_vr_linear_result(
        fit, covariance, c(treated = 1), deal_multipliers,
        "aggregate initially retained inventor effect", cfg
      )
      z <- add_two_way_interval(z, covariance)
      z$sample <- sample_name
      z$outcome <- outcome
      z$window <- ifelse(
        window == "ref", "post_mean_minus_t_minus_1",
        "five_post_minus_five_pre"
      )
      aggregate_rows[[length(aggregate_rows) + 1L]] <- z
    }
  }
}
aggregate_results <- do.call(rbind, aggregate_rows)

decomposition_function <- function(theta) {
  names(theta) <- c(
    "yTpre", "yCpre", "pTpre", "pCpre",
    "yTpost", "yCpost", "pTpost", "pCpost"
  )
  mu <- c(
    muTpre = unname(theta["yTpre"] / theta["pTpre"]),
    muCpre = unname(theta["yCpre"] / theta["pCpre"]),
    muTpost = unname(theta["yTpost"] / theta["pTpost"]),
    muCpost = unname(theta["yCpost"] / theta["pCpost"])
  )
  ext_a_pre <- (theta["pTpre"] - theta["pCpre"]) * mu["muCpre"]
  int_a_pre <- theta["pTpre"] * (mu["muTpre"] - mu["muCpre"])
  ext_a_post <- (theta["pTpost"] - theta["pCpost"]) * mu["muCpost"]
  int_a_post <- theta["pTpost"] * (mu["muTpost"] - mu["muCpost"])
  ext_b_pre <- (theta["pTpre"] - theta["pCpre"]) * mu["muTpre"]
  int_b_pre <- theta["pCpre"] * (mu["muTpre"] - mu["muCpre"])
  ext_b_post <- (theta["pTpost"] - theta["pCpost"]) * mu["muTpost"]
  int_b_post <- theta["pCpost"] * (mu["muTpost"] - mu["muCpost"])
  out <- unname(c(
    ext_a_post - ext_a_pre, int_a_post - int_a_pre,
    ext_b_post - ext_b_pre, int_b_post - int_b_pre,
    ((ext_a_post - ext_a_pre) + (ext_b_post - ext_b_pre)) / 2,
    ((int_a_post - int_a_pre) + (int_b_post - int_b_pre)) / 2,
    (theta["yTpost"] - theta["yCpost"]) -
      (theta["yTpre"] - theta["yCpre"])
  ))
  names(out) <- c(
    "ordering_a_extensive", "ordering_a_intensive",
    "ordering_b_extensive", "ordering_b_intensive",
    "symmetric_extensive", "symmetric_intensive", "total"
  )
  out
}

numeric_gradient <- function(fun, theta) {
  base <- fun(theta)
  G <- matrix(
    NA_real_, nrow = length(base), ncol = length(theta),
    dimnames = list(names(base), names(theta))
  )
  for (j in seq_along(theta)) {
    h <- max(1e-7, abs(theta[j]) * 1e-6)
    up <- down <- theta
    up[j] <- up[j] + h
    down[j] <- down[j] - h
    G[, j] <- (fun(up) - fun(down)) / (2 * h)
  }
  G
}

estimate_decomposition <- function(sample_name, cohorts) {
  x <- unit[unit$cohort %in% cohorts, , drop = FALSE]
  x <- lmv2_vr_analysis_weights(x)
  components <- names(decomposition_function(rep(.1, 8)))
  estimates <- setNames(numeric(length(components)), components)
  influence <- matrix(
    0, nrow = nrow(x), ncol = length(components),
    dimnames = list(NULL, components)
  )
  for (g in sort(unique(x$cohort))) {
    ix <- which(x$cohort == g)
    z <- x[ix, ]
    get_mean <- function(v, arm) {
      k <- z$treated == arm
      weighted.mean(z[[v]][k], z$raw_weight[k])
    }
    theta <- c(
      yTpre = get_mean("patent_pre_ref", 1),
      yCpre = get_mean("patent_pre_ref", 0),
      pTpre = get_mean("active_pre_ref", 1),
      pCpre = get_mean("active_pre_ref", 0),
      yTpost = get_mean("patent_post_avg", 1),
      yCpost = get_mean("patent_post_avg", 0),
      pTpost = get_mean("active_post_avg", 1),
      pCpost = get_mean("active_post_avg", 0)
    )
    value <- decomposition_function(theta)
    q <- unique(z$q_g)
    if (length(q) != 1L) stop("Cohort weight is not unique")
    estimates <- estimates + q * value
    G <- numeric_gradient(decomposition_function, theta)
    arm_mass <- tapply(z$raw_weight, z$treated, sum)
    param_map <- list(
      yTpre = c("patent_pre_ref", 1),
      yCpre = c("patent_pre_ref", 0),
      pTpre = c("active_pre_ref", 1),
      pCpre = c("active_pre_ref", 0),
      yTpost = c("patent_post_avg", 1),
      yCpost = c("patent_post_avg", 0),
      pTpost = c("active_post_avg", 1),
      pCpost = c("active_post_avg", 0)
    )
    for (j in names(param_map)) {
      variable <- param_map[[j]][1]
      arm <- as.numeric(param_map[[j]][2])
      k <- which(z$treated == arm)
      mean_if <- z$raw_weight[k] / arm_mass[as.character(arm)] *
        (z[[variable]][k] - theta[j])
      influence[ix[k], ] <- influence[ix[k], , drop = FALSE] +
        q * outer(mean_if, G[, j])
    }
  }
  fit <- list(
    beta = estimates, influence = influence,
    deal = x$deal_id, inventor = x$codinv,
    intersection = paste(x$deal_id, x$codinv, sep = ":")
  )
  covariance <- lmv2_vr_model_covariance(fit)
  rows <- lapply(components, function(component) {
    z <- lmv2_vr_linear_result(
      fit, covariance, setNames(1, component), deal_multipliers,
      component, cfg
    )
    z <- add_two_way_interval(z, covariance)
    z$sample <- sample_name
    z$component <- component
    z
  })
  out <- do.call(rbind, rows)
  out$five_year_patents <- 5 * out$estimate
  out$five_year_ci_low <- 5 * out$ci_low
  out$five_year_ci_high <- 5 * out$ci_high
  total <- out$estimate[out$component == "total"]
  out$share_of_total <- out$estimate / total
  out
}

decomposition <- do.call(rbind, lapply(
  names(cfg$estimand$samples),
  function(s) estimate_decomposition(s, cfg$estimand$samples[[s]])
))
full_decomp <- decomposition[decomposition$sample == "full_1993_2010", ]
sym_sum <- sum(full_decomp$estimate[
  full_decomp$component %in%
    c("symmetric_extensive", "symmetric_intensive")
])
total <- full_decomp$estimate[full_decomp$component == "total"]
headline_count <- aggregate_results$estimate[
  aggregate_results$sample == "full_1993_2010" &
    aggregate_results$outcome == "patent_count" &
    aggregate_results$window == "post_mean_minus_t_minus_1"
]
if (length(total) != 1L || abs(sym_sum - total) > 1e-10 ||
    abs(total - headline_count) > 1e-10) {
  stop("Stayer extensive/intensive identity does not reproduce the ATT")
}

utils::write.csv(
  results, file.path(out_dir, "stayer_heterogeneity_results.csv"),
  row.names = FALSE
)
utils::write.csv(
  aggregate_results, file.path(out_dir, "stayer_aggregate_results.csv"),
  row.names = FALSE
)
utils::write.csv(
  decomposition, file.path(out_dir, "stayer_margin_decomposition.csv"),
  row.names = FALSE
)

manifest <- data.frame(
  design_hash = lmv2_stayer_het_hash(),
  power_manifest_sha256 = digest::digest(
    file = power_manifest_path, algo = "sha256"
  ),
  unit_analysis_sha256 = digest::digest(
    file = unit_path, algo = "sha256"
  ),
  source_sha256 = digest::digest(
    file = file.path(
      BASE, "R", "33d_estimate_lmv2_stayer_heterogeneity.R"
    ),
    algo = "sha256"
  ),
  primary_family_rows = sum(primary),
  aggregate_att_reproduced = TRUE,
  decomposition_identity_pass = TRUE,
  tenure_appendix_rows = sum(
    results$moderator == "focal_tenure" &
      results$result_type == "focal_contrast"
  ),
  runtime_minutes = as.numeric(
    difftime(Sys.time(), t0, units = "mins")
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(out_dir, "estimation_manifest.csv"), row.names = FALSE
)
message(
  "Stayer heterogeneity estimation complete in ",
  round(manifest$runtime_minutes, 2), " minutes."
)
