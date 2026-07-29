# ============================================================================
# 32a_lmv2_vr_heterogeneity_config.R -- frozen five-year heterogeneity design
# ============================================================================

LMV2_VR_HET_VERSION <- "lmv2_vr_heterogeneity_v1"

LMV2_VR_HET <- list(
  construction = list(
    ipc_granularity = 4L,
    techfit_primary_window = "all_observable_years_before_treatment",
    techfit_robustness_event_times = -5:-1,
    team_event_times = -5:-1,
    persistent_min_joint_patents = 2L,
    persistent_min_joint_years = 2L,
    primary_moderators = c(
      "predeal_productivity", "career_age",
      "team_persistence", "techfit"
    ),
    primary_outcomes = c("patent_count", "active_patenting")
  ),
  estimand = list(
    reference_event_time = -1L,
    pre_event_times = -5:-1,
    post_event_times = 1:5,
    samples = list(
      full_1994_2010 = 1994:2010,
      buffered_1994_2008 = 1994:2008
    ),
    meaningful_contrast = c(
      patent_count = 0.053,
      active_patenting = 0.020
    ),
    focal_contrast = list(
      predeal_productivity = "treated weighted p75 minus p25",
      career_age = "treated weighted p75 minus p25",
      team_persistence = "average positive persistent tie minus no tie",
      techfit = "treated weighted p75 minus p25"
    )
  ),
  inference = list(
    bootstrap_type = "Webb",
    bootstrap_replications = 9999L,
    bootstrap_seed = 20260730L,
    confidence_level = 0.95,
    target_power = 0.80,
    multiplicity = "Holm across 4 moderators x 2 outcomes",
    precision_diagnostic =
      "report MDE and Type-M ratio without using them as inclusion gates"
  ),
  execution = list(threads = 8L, memory_limit = "5GB"),
  inputs = list(
    database = file.path(
      "02_analysis", "output", "thesis_foundation.duckdb"
    ),
    panel_dir = file.path(
      "02_analysis", "output", "audit", "local_match_v2",
      "P6_P5C_PANEL_COUNT_ACTIVE", "panel_matched"
    ),
    panel_manifest = file.path(
      "02_analysis", "output", "audit", "local_match_v2",
      "P6_P5C_PANEL_COUNT_ACTIVE", "p6_manifest.csv"
    ),
    inherited_moderators = file.path(
      "02_analysis", "output", "audit", "local_match_v2",
      "P7_INVENTOR_HETEROGENEITY", "inventor_moderators.parquet"
    ),
    inherited_moderator_manifest = file.path(
      "02_analysis", "output", "audit", "local_match_v2",
      "P7_INVENTOR_HETEROGENEITY", "moderator_build_manifest.csv"
    ),
    headline = file.path(
      "02_analysis", "output", "audit", "local_match_v2",
      "P6_P5C_ESTIMATION_COUNT_ACTIVE", "p6_headline_post_att.csv"
    )
  ),
  freeze_path = file.path(
    "02_analysis", "notes",
    "local_match_v2_vr_heterogeneity_freeze.md"
  ),
  output_dir = file.path(
    "02_analysis", "output", "audit", "local_match_v2",
    "P7_VR_HETEROGENEITY"
  ),
  result_dir = file.path(
    "02_analysis", "output", "results", "local_match_v2",
    "vr_heterogeneity"
  )
)

lmv2_vr_hash <- function() {
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Package 'digest' is required for the VR heterogeneity hash")
  }
  digest::digest(
    list(
      version = LMV2_VR_HET_VERSION,
      parent_design_hash = LMV2_DESIGN_HASH,
      p6_estimation_hash = lmv2_p6_estimation_hash(),
      config = LMV2_VR_HET,
      config_source_sha256 = digest::digest(
        file = file.path(
          "02_analysis", "R", "32a_lmv2_vr_heterogeneity_config.R"
        ),
        algo = "sha256"
      ),
      freeze_sha256 = digest::digest(
        file = LMV2_VR_HET$freeze_path, algo = "sha256"
      )
    ),
    algo = "sha256", serialize = TRUE
  )
}

lmv2_vr_assert_checks <- function(checks) {
  if (!is.data.frame(checks) ||
      !all(c("check", "pass") %in% names(checks)) ||
      anyNA(checks$pass) || !all(checks$pass)) {
    failed <- if (is.data.frame(checks)) {
      checks$check[is.na(checks$pass) | !checks$pass]
    } else {
      "malformed_check_table"
    }
    stop("VR heterogeneity certification failed: ",
         paste(failed, collapse = ", "))
  }
  invisible(TRUE)
}

lmv2_vr_weighted_quantile <- function(x, w, probs) {
  ok <- is.finite(x) & is.finite(w) & w > 0
  x <- x[ok]
  w <- w[ok]
  if (!length(x)) return(rep(NA_real_, length(probs)))
  ord <- order(x)
  x <- x[ord]
  w <- w[ord]
  cw <- cumsum(w) / sum(w)
  vapply(probs, function(p) x[which(cw >= p)[1]], numeric(1))
}

lmv2_vr_analysis_weights <- function(x) {
  treated_mass <- stats::aggregate(
    raw_weight ~ cohort,
    data = x[x$treated == 1, ],
    FUN = sum
  )
  treated_mass$q_g <- treated_mass$raw_weight / sum(treated_mass$raw_weight)
  names(treated_mass)[2] <- "treated_design_mass"
  arm_mass <- stats::aggregate(
    raw_weight ~ cohort + treated, data = x, FUN = sum
  )
  names(arm_mass)[3] <- "arm_mass"
  z <- merge(x, treated_mass, by = "cohort", all.x = TRUE, sort = FALSE)
  z <- merge(z, arm_mass, by = c("cohort", "treated"),
             all.x = TRUE, sort = FALSE)
  z$analysis_weight <- z$q_g * z$raw_weight / z$arm_mass
  z
}

lmv2_vr_prepare_data <- function(
    x, cohorts, techfit_variant = NULL) {
  z <- x[x$cohort %in% cohorts, , drop = FALSE]
  if (!is.null(techfit_variant)) {
    reason <- paste0("techfit_", techfit_variant, "_reason")
    value <- paste0("techfit_", techfit_variant)
    eligible_deals <- unique(z$deal_id[z[[reason]] == "eligible"])
    z <- z[z$deal_id %in% eligible_deals, , drop = FALSE]
    if (any(z[[reason]] != "eligible") || anyNA(z[[value]])) {
      stop("TechFit eligibility is not constant within focal deal")
    }
  }
  z <- lmv2_vr_analysis_weights(z)
  treated <- z$treated == 1
  wmean <- function(v, w) sum(v * w) / sum(w)
  wsd <- function(v, w) {
    m <- wmean(v, w)
    sqrt(sum(w * (v - m)^2) / sum(w))
  }
  z$prod_raw <- z$log_patent_count_5y
  z$age_raw <- log1p(z$career_age)
  prod_mean <- wmean(z$prod_raw[treated], z$analysis_weight[treated])
  age_mean <- wmean(z$age_raw[treated], z$analysis_weight[treated])
  prod_sd <- wsd(z$prod_raw[treated], z$analysis_weight[treated])
  age_sd <- wsd(z$age_raw[treated], z$analysis_weight[treated])
  z$prod_z <- (z$prod_raw - prod_mean) / prod_sd
  z$age_z <- (z$age_raw - age_mean) / age_sd
  team_mean <- wmean(z$team_any[treated], z$analysis_weight[treated])
  positive <- treated & z$team_any == 1
  positive_share_mean <- wmean(
    z$persistent_patent_share[positive],
    z$analysis_weight[positive]
  )
  z$team_any_c <- z$team_any - team_mean
  z$team_intensity <- ifelse(
    z$team_any == 1,
    z$persistent_patent_share - positive_share_mean,
    0
  )
  z$tx_prod <- z$treated * z$prod_z
  z$tx_age <- z$treated * z$age_z
  z$tx_team_any <- z$treated * z$team_any_c
  z$tx_team_intensity <- z$treated * z$team_intensity
  prod_q <- lmv2_vr_weighted_quantile(
    z$prod_raw[treated], z$analysis_weight[treated], c(.25, .75)
  )
  age_q <- lmv2_vr_weighted_quantile(
    z$age_raw[treated], z$analysis_weight[treated], c(.25, .75)
  )
  contrasts <- list(
    predeal_productivity = diff((prod_q - prod_mean) / prod_sd),
    career_age = diff((age_q - age_mean) / age_sd),
    team_persistence = 1,
    prod_raw_quantiles = prod_q,
    age_raw_quantiles = age_q,
    team_positive_share_mean = positive_share_mean,
    team_any_mean = team_mean
  )
  if (!is.null(techfit_variant)) {
    value <- paste0("techfit_", techfit_variant)
    tech_mean <- wmean(z[[value]][treated], z$analysis_weight[treated])
    tech_sd <- wsd(z[[value]][treated], z$analysis_weight[treated])
    z$techfit_z <- (z[[value]] - tech_mean) / tech_sd
    z$tx_techfit <- z$treated * z$techfit_z
    tech_q <- lmv2_vr_weighted_quantile(
      z[[value]][treated], z$analysis_weight[treated], c(.25, .75)
    )
    contrasts$techfit <- diff((tech_q - tech_mean) / tech_sd)
    contrasts$techfit_raw_quantiles <- tech_q
    contrasts$techfit_mean <- tech_mean
    contrasts$techfit_sd <- tech_sd
  }
  list(data = z, contrasts = contrasts)
}

lmv2_vr_cr1 <- function(scores) {
  scores <- as.matrix(scores)
  if (nrow(scores) < 2L) stop("Fewer than two clusters")
  scores <- sweep(scores, 2L, colMeans(scores), "-")
  nrow(scores) / (nrow(scores) - 1) * crossprod(scores)
}

lmv2_vr_cluster_scores <- function(influence, cluster) {
  rowsum(influence, group = as.character(cluster), reorder = TRUE)
}

lmv2_vr_webb_multipliers <- function(deal_levels, cfg = LMV2_VR_HET) {
  set.seed(cfg$inference$bootstrap_seed)
  support <- c(
    -sqrt(3 / 2), -1, -sqrt(1 / 2),
    sqrt(1 / 2), 1, sqrt(3 / 2)
  )
  matrix(
    sample(
      support,
      cfg$inference$bootstrap_replications * length(deal_levels),
      replace = TRUE
    ),
    nrow = cfg$inference$bootstrap_replications,
    ncol = length(deal_levels),
    dimnames = list(NULL, as.character(deal_levels))
  )
}

lmv2_vr_fit_wls <- function(x, outcome, rhs) {
  f <- stats::as.formula(paste("~", paste(rhs, collapse = " + ")))
  X <- stats::model.matrix(f, data = x)
  y <- x[[outcome]]
  w <- x$analysis_weight
  keep <- is.finite(y) & is.finite(w) & w > 0 &
    stats::complete.cases(X)
  X <- X[keep, , drop = FALSE]
  y <- y[keep]
  w <- w[keep]
  xx <- crossprod(X, w * X)
  bread <- tryCatch(
    solve(xx),
    error = function(e) {
      if (!requireNamespace("MASS", quietly = TRUE)) stop(e)
      MASS::ginv(xx)
    }
  )
  beta <- drop(bread %*% crossprod(X, w * y))
  names(beta) <- colnames(X)
  residual <- y - drop(X %*% beta)
  influence <- sweep(X, 1L, w * residual, "*") %*% bread
  colnames(influence) <- colnames(X)
  list(
    beta = beta, influence = influence, keep = keep,
    deal = x$deal_id[keep], inventor = x$codinv[keep],
    intersection = paste(x$deal_id[keep], x$codinv[keep], sep = ":"),
    n = sum(keep), rank = qr(xx)$rank
  )
}

lmv2_vr_model_covariance <- function(fit) {
  S_deal <- lmv2_vr_cluster_scores(fit$influence, fit$deal)
  S_inv <- lmv2_vr_cluster_scores(fit$influence, fit$inventor)
  S_int <- lmv2_vr_cluster_scores(fit$influence, fit$intersection)
  V_deal <- lmv2_vr_cr1(S_deal)
  V_two <- V_deal + lmv2_vr_cr1(S_inv) - lmv2_vr_cr1(S_int)
  diag(V_two) <- pmax(diag(V_two), 0)
  list(
    deal = V_deal, two = V_two,
    S_deal = S_deal,
    df_two = min(nrow(S_deal), nrow(S_inv)) - 1L
  )
}

lmv2_vr_linear_result <- function(
    fit, covariance, contrast, deal_multipliers,
    label, cfg = LMV2_VR_HET) {
  L <- numeric(length(fit$beta))
  names(L) <- names(fit$beta)
  missing <- setdiff(names(contrast), names(L))
  if (length(missing)) {
    stop("Contrast terms absent from model: ", paste(missing, collapse = ", "))
  }
  L[names(contrast)] <- contrast
  estimate <- sum(L * fit$beta)
  se_deal <- sqrt(drop(t(L) %*% covariance$deal %*% L))
  se_two <- sqrt(drop(t(L) %*% covariance$two %*% L))
  score <- drop(covariance$S_deal %*% L)
  model_deals <- rownames(covariance$S_deal)
  mult <- deal_multipliers[, model_deals, drop = FALSE]
  draws <- drop(mult %*% score)
  draw_t <- draws / se_deal
  alpha <- 1 - cfg$inference$confidence_level
  wild_crit <- unname(stats::quantile(
    abs(draw_t), 1 - alpha, type = 7
  ))
  p_wild <- (1 + sum(abs(draw_t) >= abs(estimate / se_deal))) /
    (length(draw_t) + 1)
  tcrit_two <- stats::qt(1 - alpha / 2, covariance$df_two)
  p_two <- 2 * stats::pt(
    -abs(estimate / se_two), df = covariance$df_two
  )
  width_wild <- wild_crit * se_deal
  width_two <- tcrit_two * se_two
  data.frame(
    contrast = label,
    estimate = estimate,
    deal_se = se_deal,
    two_way_se = se_two,
    deal_wild_p = p_wild,
    two_way_p = p_two,
    governing_p = max(p_wild, p_two),
    ci_low = estimate - max(width_wild, width_two),
    ci_high = estimate + max(width_wild, width_two),
    governing_critical = max(wild_crit, tcrit_two),
    governing_se = max(se_deal, se_two),
    governing_interval = ifelse(
      width_wild >= width_two, "deal_wild", "two_way_deal_inventor"
    ),
    stringsAsFactors = FALSE
  )
}

lmv2_vr_type_m_ratio <- function(se, threshold, critical) {
  if (!is.finite(se) || !is.finite(threshold) || threshold <= 0 ||
      !is.finite(critical) || critical <= 0) return(NA_real_)
  mu <- threshold / se
  upper_prob <- 1 - stats::pnorm(critical - mu)
  lower_prob <- stats::pnorm(-critical - mu)
  prob <- upper_prob + lower_prob
  if (prob <= 0) return(NA_real_)
  upper_first <- mu * upper_prob + stats::dnorm(critical - mu)
  lower_first <- mu * lower_prob - stats::dnorm(-critical - mu)
  (se / threshold) * (upper_first - lower_first) / prob
}
