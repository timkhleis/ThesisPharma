# Moderator-specific pre-trend diagnostics for the 1993--2010 five-by-five
# heterogeneity specifications. This is a reporting diagnostic and does not
# alter the certified treatment-effect estimates.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = TRUE
)
.libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "MASS")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "32a_lmv2_vr_heterogeneity_config.R"))
source(file.path(BASE, "R", "33a_lmv2_stayer_heterogeneity_config.R"))
source(file.path(BASE, "R", "65a_lmv2_relative_standing_config.R"))

read_parquet <- function(con, path) {
  DBI::dbGetQuery(con, sprintf(
    "SELECT * FROM read_parquet(%s)",
    DBI::dbQuoteString(
      con, normalizePath(path, winslash = "/", mustWork = TRUE)
    )
  ))
}

write_csv_atomic <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp")
  utils::write.csv(x, tmp, row.names = FALSE, na = "")
  if (file.exists(path)) file.remove(path)
  if (!file.rename(tmp, path)) stop("Could not write: ", path)
}

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

panel_glob <- normalizePath(
  file.path(
    LMV2_VR_HET$inputs$panel_dir,
    "lmv2_event_panel_c*.parquet"
  ),
  winslash = "/", mustWork = FALSE
)
annual <- DBI::dbGetQuery(con, sprintf(
  "
  SELECT roster_row_id,
         MAX(CASE WHEN event_time = -5 THEN patent_count END) AS patent_m5,
         MAX(CASE WHEN event_time = -4 THEN patent_count END) AS patent_m4,
         MAX(CASE WHEN event_time = -3 THEN patent_count END) AS patent_m3,
         MAX(CASE WHEN event_time = -2 THEN patent_count END) AS patent_m2,
         MAX(CASE WHEN event_time = -1 THEN patent_count END) AS patent_m1,
         MAX(CASE WHEN event_time = -5 THEN active_patenting END) AS active_m5,
         MAX(CASE WHEN event_time = -4 THEN active_patenting END) AS active_m4,
         MAX(CASE WHEN event_time = -3 THEN active_patenting END) AS active_m3,
         MAX(CASE WHEN event_time = -2 THEN active_patenting END) AS active_m2,
         MAX(CASE WHEN event_time = -1 THEN active_patenting END) AS active_m1
  FROM read_parquet(%s)
  WHERE event_time BETWEEN -5 AND -1
  GROUP BY roster_row_id
  ",
  DBI::dbQuoteString(con, panel_glob)
))

attach_pre_outcomes <- function(x) {
  pos <- match(x$roster_row_id, annual$roster_row_id)
  if (anyNA(pos)) stop("Annual pre-period outcomes are missing for unit rows")
  for (nm in setdiff(names(annual), "roster_row_id")) {
    x[[nm]] <- annual[[nm]][pos]
  }
  for (k in 5:2) {
    x[[paste0("dpre_patent_m", k)]] <-
      x[[paste0("patent_m", k)]] - x$patent_m1
    x[[paste0("dpre_active_m", k)]] <-
      x[[paste0("active_m", k)]] - x$active_m1
  }
  x
}

common_rhs <- c(
  "factor(cohort)", "treated",
  "prod_z", "age_z", "team_any_c", "team_intensity"
)
model_spec <- list(
  predeal_productivity = list(
    techfit = NULL,
    rhs = c(common_rhs, "tx_prod"),
    term = "tx_prod"
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

star_rhs <- c(
  common_rhs, "star_c", "tx_star"
)

linear_two_way <- function(fit, covariance, term, confidence = 0.95) {
  L <- numeric(length(fit$beta))
  names(L) <- names(fit$beta)
  if (!term %in% names(L)) stop("Missing interaction term: ", term)
  L[[term]] <- 1
  estimate <- sum(L * fit$beta)
  se <- sqrt(drop(t(L) %*% covariance$two %*% L))
  df <- covariance$df_two
  critical <- stats::qt(1 - (1 - confidence) / 2, df)
  data.frame(
    estimate = estimate,
    two_way_se = se,
    two_way_df = df,
    two_way_p = 2 * stats::pt(-abs(estimate / se), df = df),
    ci_low = estimate - critical * se,
    ci_high = estimate + critical * se,
    stringsAsFactors = FALSE
  )
}

joint_pretrend <- function(x, outcome, rhs, term) {
  prefixes <- if (outcome == "patent_count") {
    paste0("dpre_patent_m", 5:2)
  } else {
    paste0("dpre_active_m", 5:2)
  }
  X <- stats::model.matrix(
    stats::as.formula(paste("~", paste(rhs, collapse = " + "))),
    data = x
  )
  keep <- is.finite(x$analysis_weight) & x$analysis_weight > 0 &
    stats::complete.cases(X) & stats::complete.cases(x[, prefixes])
  z <- x[keep, , drop = FALSE]
  estimates <- numeric(length(prefixes))
  influence <- matrix(NA_real_, nrow(z), length(prefixes))

  for (j in seq_along(prefixes)) {
    fit <- lmv2_vr_fit_wls(z, prefixes[[j]], rhs)
    if (!all(fit$keep)) stop("Pre-trend estimation samples differ by year")
    L <- numeric(length(fit$beta))
    names(L) <- names(fit$beta)
    L[[term]] <- 1
    estimates[[j]] <- sum(L * fit$beta)
    influence[, j] <- drop(fit$influence %*% L)
  }

  deal <- z$deal_id
  inventor <- z$codinv
  intersection <- paste(deal, inventor, sep = ":")
  S_deal <- lmv2_vr_cluster_scores(influence, deal)
  S_inventor <- lmv2_vr_cluster_scores(influence, inventor)
  S_intersection <- lmv2_vr_cluster_scores(influence, intersection)
  V <- lmv2_vr_cr1(S_deal) + lmv2_vr_cr1(S_inventor) -
    lmv2_vr_cr1(S_intersection)
  diag(V) <- pmax(diag(V), 0)
  q <- qr(V)$rank
  if (q < 1L) stop("Moderator pre-trend covariance has zero rank")
  Vinv <- if (q == nrow(V)) solve(V) else MASS::ginv(V)
  f_stat <- drop(t(estimates) %*% Vinv %*% estimates) / q
  df2 <- min(nrow(S_deal), nrow(S_inventor)) - 1L

  data.frame(
    periods = "-5;-4;-3;-2",
    f_stat = f_stat,
    df1 = q,
    df2 = df2,
    p_value = stats::pf(f_stat, q, df2, lower.tail = FALSE),
    estimate_m5 = estimates[[1]],
    estimate_m4 = estimates[[2]],
    estimate_m3 = estimates[[3]],
    estimate_m2 = estimates[[4]],
    n_observations = nrow(z),
    nominal_deals = length(unique(z$deal_id[z$treated == 1])),
    stringsAsFactors = FALSE
  )
}

estimate_sample <- function(unit, sample, prepare, cfg, output_path) {
  rows <- list()
  effects <- list()
  for (moderator in names(model_spec)) {
    spec <- model_spec[[moderator]]
    prepared <- prepare(
      unit,
      cfg$estimand$samples$full_1993_2010,
      spec$techfit
    )
    z <- attach_pre_outcomes(prepared$data)
    for (outcome in c("patent_count", "active_patenting")) {
      diagnostic <- joint_pretrend(z, outcome, spec$rhs, spec$term)
      diagnostic$sample <- sample
      diagnostic$moderator <- moderator
      diagnostic$outcome <- outcome
      rows[[length(rows) + 1L]] <- diagnostic

      outcome_col <- if (outcome == "patent_count") {
        "d_patent_5x5"
      } else {
        "d_active_5x5"
      }
      fit <- lmv2_vr_fit_wls(z, outcome_col, spec$rhs)
      covariance <- lmv2_vr_model_covariance(fit)
      effect <- linear_two_way(
        fit, covariance, spec$term, cfg$inference$confidence_level
      )
      effect$sample <- sample
      effect$moderator <- moderator
      effect$outcome <- outcome
      effect$contrast <- if (moderator == "team_persistence") {
        "persistent team at mean positive intensity versus none"
      } else {
        "one-standard-deviation increase"
      }
      effects[[length(effects) + 1L]] <- effect
    }
  }
  pretrend <- do.call(rbind, rows)
  effect <- do.call(rbind, effects)
  pretrend <- pretrend[, c(
    "sample", "moderator", "outcome", "periods", "f_stat", "df1",
    "df2", "p_value", "estimate_m5", "estimate_m4", "estimate_m3",
    "estimate_m2", "n_observations", "nominal_deals"
  )]
  effect <- effect[, c(
    "sample", "moderator", "outcome", "contrast", "estimate",
    "two_way_se", "two_way_df", "two_way_p", "ci_low", "ci_high"
  )]
  write_csv_atomic(pretrend, output_path)
  list(pretrend = pretrend, effect = effect)
}

attach_star_moderator <- function(unit, moderators) {
  eligible <- moderators$standing_eligibility == "eligible" &
    !is.na(moderators$kapoor_top20)
  m <- moderators[eligible, c("roster_row_id", "kapoor_top20")]
  if (anyDuplicated(m$roster_row_id)) {
    stop("Eligible star moderator rows are duplicated")
  }
  pos <- match(unit$roster_row_id, m$roster_row_id)
  keep <- !is.na(pos)
  z <- unit[keep, , drop = FALSE]
  z$kapoor_top20 <- m$kapoor_top20[pos[keep]]
  z
}

prepare_star_data <- function(unit, cohorts) {
  z <- unit[unit$cohort %in% cohorts, , drop = FALSE]
  z <- lmv2_vr_analysis_weights(z)
  tr <- z$treated == 1
  wmean <- function(v, w) sum(v * w) / sum(w)
  center <- function(v) v - wmean(v[tr], z$analysis_weight[tr])
  standardize <- function(v) {
    m <- wmean(v[tr], z$analysis_weight[tr])
    s <- sqrt(wmean((v[tr] - m)^2, z$analysis_weight[tr]))
    if (!is.finite(s) || s <= 1e-12) stop("Degenerate moderator scale")
    (v - m) / s
  }
  z$prod_z <- standardize(z$log_patent_count_5y)
  z$age_z <- standardize(log1p(z$career_age))
  z$team_any_c <- center(z$team_any)
  positive_team <- tr & z$team_any == 1
  team_mean <- if (any(positive_team)) {
    wmean(
      z$persistent_patent_share[positive_team],
      z$analysis_weight[positive_team]
    )
  } else 0
  z$team_intensity <- ifelse(
    z$team_any == 1, z$persistent_patent_share - team_mean, 0
  )
  z$star_c <- center(z$kapoor_top20)
  z$tx_star <- z$treated * z$star_c
  z
}

estimate_star_sample <- function(unit, sample, cohorts) {
  z <- attach_pre_outcomes(prepare_star_data(unit, cohorts))
  rows <- lapply(c("patent_count", "active_patenting"), function(outcome) {
    diagnostic <- joint_pretrend(z, outcome, star_rhs, "tx_star")
    diagnostic$sample <- sample
    diagnostic$moderator <- "star_inventor"
    diagnostic$outcome <- outcome
    diagnostic
  })
  pretrend <- do.call(rbind, rows)
  pretrend[, c(
    "sample", "moderator", "outcome", "periods", "f_stat", "df1",
    "df2", "p_value", "estimate_m5", "estimate_m4", "estimate_m3",
    "estimate_m2", "n_observations", "nominal_deals"
  )]
}

full_unit <- read_parquet(
  con,
  file.path(LMV2_VR_HET$output_dir, "vr_unit_analysis.parquet")
)
retained_unit <- read_parquet(
  con,
  file.path(LMV2_STAYER_HET$output_dir, "stayer_unit_analysis.parquet")
)
standing_moderators <- read_parquet(
  con,
  file.path(
    LMV2_RELSTAND$output_dir, "relative_standing_moderators.parquet"
  )
)
full_star <- estimate_star_sample(
  attach_star_moderator(full_unit, standing_moderators),
  "full_target_inventor_cohort",
  LMV2_VR_HET$estimand$samples$full_1993_2010
)
retained_star <- estimate_star_sample(
  attach_star_moderator(retained_unit, standing_moderators),
  "initially_retained",
  LMV2_STAYER_HET$estimand$samples$full_1993_2010
)
star_pretrend <- rbind(full_star, retained_star)
write_csv_atomic(
  star_pretrend,
  file.path(
    LMV2_RELSTAND$output_dir, "star_moderator_pretrend_tests.csv"
  )
)

full <- estimate_sample(
  full_unit,
  "full_target_inventor_cohort",
  lmv2_vr_prepare_data,
  LMV2_VR_HET,
  file.path(
    LMV2_VR_HET$output_dir,
    "vr_moderator_pretrend_tests.csv"
  )
)
retained <- estimate_sample(
  retained_unit,
  "initially_retained",
  lmv2_stayer_prepare_data,
  LMV2_STAYER_HET,
  file.path(
    LMV2_STAYER_HET$output_dir,
    "stayer_moderator_pretrend_tests.csv"
  )
)

combined_dir <- file.path(
  "02_analysis", "output", "results", "local_match_v2_1993_amendment",
  "results_section_exhibits"
)
write_csv_atomic(
  rbind(full$pretrend, retained$pretrend, star_pretrend),
  file.path(combined_dir, "heterogeneity_pretrend_tests.csv")
)
write_csv_atomic(
  rbind(full$effect, retained$effect),
  file.path(combined_dir, "heterogeneity_5x5_two_way_results.csv")
)

message("Moderator-specific pre-trend diagnostics written successfully.")
