# ============================================================================
# P5.1 main-ATT support rescue: outcome-blind configuration and pure helpers
# ============================================================================

LMV2_P5_RESCUE_VERSION <- "local_match_v2_p5_rescue_v2"
LMV2_P5_RESCUE_AMENDMENT_SHA256 <-
  "5797bf09da4ff565c1516e3de541b302cb7d66c4460b9bf995b6cec08a08eccb"
LMV2_P5_INDUSTRY_SUPPORT_AMENDMENT_SHA256 <-
  "403b3b4d946f36542c1932880088b062e308047d63e3e17e1dc153738358537c"

LMV2_P5_RESCUE_PATHS <- list(
  amendment = file.path(
    BASE, "notes", "local_match_v2_p5_rescue_amendment.md"),
  industry_support_amendment = file.path(
    BASE, "notes",
    "local_match_v2_p5_industry_support_amendment.md")
)

observed_rescue_amendment_hash <- lmv2_p3_file_hash(
  LMV2_P5_RESCUE_PATHS$amendment)
if (!identical(
    observed_rescue_amendment_hash,
    LMV2_P5_RESCUE_AMENDMENT_SHA256)) {
  stop(
    "P5.1 rescue amendment drifted: expected ",
    LMV2_P5_RESCUE_AMENDMENT_SHA256, ", observed ",
    observed_rescue_amendment_hash)
}
observed_industry_support_hash <- lmv2_p3_file_hash(
  LMV2_P5_RESCUE_PATHS$industry_support_amendment)
if (!identical(
    observed_industry_support_hash,
    LMV2_P5_INDUSTRY_SUPPORT_AMENDMENT_SHA256)) {
  stop(
    "P5.2 industry-support amendment drifted: expected ",
    LMV2_P5_INDUSTRY_SUPPORT_AMENDMENT_SHA256, ", observed ",
    observed_industry_support_hash)
}

LMV2_P5_RESCUE <- list(
  outcome_boundary = paste(
    "P5.1 may read treatment assignments, pre-treatment covariates,",
    "eligibility, support, and weight diagnostics only. Outcome and",
    "treatment-effect objects remain outside P5.1."
  ),
  diagnostic_cohorts = c(2000L, 2009L),
  stages = c(
    "u2_inventor_first", "u2_reduced", "u2_reduced_knn",
    "u2_reduced_stage1_2"),
  selected = list(
    universe = "u2",
    profile = "nearest_50",
    stage1_caliper = 1.5,
    stage2_caliper = 1.5,
    technology_resolution = "ipc4",
    schemes = c("primary", "equal_deal"),
    solver = "newton",
    cohorts = 1994:2010
  ),
  original_distance_variables = c(
    "log_patent_count_5y", "patent_trajectory", "career_age",
    "focal_group_tenure", "focal_group_exclusivity"
  ),
  reduced_distance_variables = c(
    "log_patent_count_5y", "patent_trajectory", "career_age"
  ),
  reduced_balance_variables = c(
    "log_patent_count_5y", "patent_trajectory", "career_age",
    "focal_group_exclusivity"
  ),
  gates = list(
    aggregate_inventor_coverage = 0.80,
    minimum_cohort_coverage = 0.60,
    aggregate_deal_coverage = 0.80,
    minimum_productivity_quartile_coverage = 0.70,
    selection_smd_pass = 0.20,
    selection_smd_fail = 0.25,
    minimum_reuse_adjusted_ess_ratio = 0.50,
    deal_70_effective_firm_review = 2.50,
    deal_70_leave_one_firm_out_max_shift_sd = 0.10
  ),
  inventor_first = list(
    minimum_stage1_firms = 2L,
    minimum_controls_per_treated = 3L,
    minimum_firms_per_treated = 2L
  ),
  knn = list(
    k = 5L,
    sanity_quantile = 0.99,
    minimum_firms_per_treated = 2L
  ),
  selection_variables = c(
    "log_patent_count_5y", "career_age",
    "focal_group_exclusivity", "focal_group_tenure"
  ),
  compute = list(
    max_workers = 2L,
    duckdb_threads_per_worker = 2L,
    duckdb_memory_limit = "6GB"
  ),
  amendment_hash = LMV2_P5_RESCUE_AMENDMENT_SHA256
)
LMV2_P5_RESCUE$industry_support_amendment_hash <-
  LMV2_P5_INDUSTRY_SUPPORT_AMENDMENT_SHA256

lmv2_p5_rescue_u2_eligible <- function(
    target_event_years, acquirer_event_years, cohort) {
  target_event_years <- target_event_years[is.finite(target_event_years)]
  acquirer_event_years <- acquirer_event_years[
    is.finite(acquirer_event_years)]
  no_target_through_window <- !length(target_event_years) ||
    all(target_event_years > cohort + 5L)
  no_near_acquirer_event <- !length(acquirer_event_years) ||
    all(acquirer_event_years < cohort - 5L |
          acquirer_event_years > cohort + 5L)
  no_target_through_window && no_near_acquirer_event
}

lmv2_p5_rescue_apply_stage <- function(stage) {
  if (!stage %in% LMV2_P5_RESCUE$stages) {
    stop(
      "Unknown rescue stage: ", stage, "; expected ",
      paste(LMV2_P5_RESCUE$stages, collapse = ", "))
  }
  if (identical(stage, "u2_inventor_first")) {
    LMV2_P3$stage_2$scalar_variables <-
      LMV2_P5_RESCUE$original_distance_variables
    LMV2_HYBRID_INV_VARS <-
      LMV2_P5_RESCUE$original_distance_variables
  } else {
    LMV2_P3$stage_2$scalar_variables <-
      LMV2_P5_RESCUE$reduced_distance_variables
    # Exclusivity remains an exact balance moment even though it is not a
    # local-distance component.
    LMV2_HYBRID_INV_VARS <-
      LMV2_P5_RESCUE$reduced_balance_variables
  }
  LMV2_COHORT_RETENTION_MIN <-
    LMV2_P5_RESCUE$gates$minimum_cohort_coverage
  LMV2_P5_MIN_CONTROLS_PER_TREATED <-
    LMV2_P5_RESCUE$inventor_first$minimum_controls_per_treated
  LMV2_P5_MIN_FIRMS_PER_TREATED <-
    LMV2_P5_RESCUE$inventor_first$minimum_firms_per_treated
  LMV2_P5_KNN_MODE <- identical(stage, "u2_reduced_knn")
  LMV2_P5_KNN_K <- LMV2_P5_RESCUE$knn$k
  LMV2_P5_KNN_SANITY_QUANTILE <-
    LMV2_P5_RESCUE$knn$sanity_quantile
  STAGE2_CALIPER <- if (LMV2_P5_KNN_MODE) {
    Inf
  } else {
    LMV2_P5_RESCUE$selected$stage2_caliper
  }
  STAGE1_CALIPERS <- if (identical(
      stage, "u2_reduced_stage1_2")) {
    2.0
  } else {
    LMV2_P5_RESCUE$selected$stage1_caliper
  }

  # Compatibility object used by the existing, certified materializer.
  LMV2_P5_FINAL <<- list(
    outcome_boundary = LMV2_P5_RESCUE$outcome_boundary,
    selected = c(
      LMV2_P5_RESCUE$selected,
      list(rescue_stage = stage)
    )
  )
  assign("LMV2_P3", LMV2_P3, envir = .GlobalEnv)
  assign("LMV2_HYBRID_INV_VARS", LMV2_HYBRID_INV_VARS,
         envir = .GlobalEnv)
  assign("LMV2_COHORT_RETENTION_MIN", LMV2_COHORT_RETENTION_MIN,
         envir = .GlobalEnv)
  assign(
    "LMV2_P5_MIN_CONTROLS_PER_TREATED",
    LMV2_P5_MIN_CONTROLS_PER_TREATED,
    envir = .GlobalEnv)
  assign(
    "LMV2_P5_MIN_FIRMS_PER_TREATED",
    LMV2_P5_MIN_FIRMS_PER_TREATED,
    envir = .GlobalEnv)
  assign("LMV2_P5_KNN_MODE", LMV2_P5_KNN_MODE, envir = .GlobalEnv)
  assign("LMV2_P5_KNN_K", LMV2_P5_KNN_K, envir = .GlobalEnv)
  assign(
    "LMV2_P5_KNN_SANITY_QUANTILE",
    LMV2_P5_KNN_SANITY_QUANTILE,
    envir = .GlobalEnv)
  assign("STAGE2_CALIPER", STAGE2_CALIPER, envir = .GlobalEnv)
  assign("STAGE1_CALIPERS", STAGE1_CALIPERS, envir = .GlobalEnv)
  invisible(stage)
}

lmv2_p5_rescue_execution_hash <- function(
    base_dir, p3_manifest_hash, stage) {
  digest::digest(
    list(
      parent = lmv2_p5_selected_execution_hash(
        base_dir, p3_manifest_hash),
      version = LMV2_P5_RESCUE_VERSION,
      amendment = LMV2_P5_RESCUE_AMENDMENT_SHA256,
      industry_support_amendment =
        LMV2_P5_INDUSTRY_SUPPORT_AMENDMENT_SHA256,
      config = lmv2_p3_file_hash(
        file.path(base_dir, "R", "19a_lmv2_p5_rescue_config.R")),
      stage = stage,
      distance_variables = LMV2_P3$stage_2$scalar_variables,
      balance_variables = LMV2_HYBRID_INV_VARS,
      cohort_floor = LMV2_COHORT_RETENTION_MIN,
      inventor_first = LMV2_P5_RESCUE$inventor_first,
      knn = LMV2_P5_RESCUE$knn
    ),
    algo = "sha256"
  )
}

lmv2_p5_rescue_assign_productivity_quartile <- function(x) {
  required <- c(
    "cohort", "deal_id", "codinv", "log_patent_count_5y")
  if (!all(required %in% names(x)) || anyDuplicated(
      x[c("cohort", "deal_id", "codinv")])) {
    stop("Treated spine is missing quartile inputs or has duplicate keys")
  }
  ord <- order(
    x$log_patent_count_5y, x$cohort, x$deal_id, x$codinv,
    na.last = NA)
  if (length(ord) != nrow(x)) {
    stop("Pre-deal productivity is missing")
  }
  quartile <- integer(nrow(x))
  quartile[ord] <- pmin(
    4L, as.integer(ceiling(seq_along(ord) * 4 / length(ord))))
  quartile
}

lmv2_p5_rescue_selection_stat <- function(x, supported, variable) {
  z1 <- x[[variable]][supported]
  z0 <- x[[variable]][!supported]
  if (!length(z1) || !length(z0) ||
      any(!is.finite(c(z1, z0)))) {
    return(data.frame(
      variable = variable, supported_mean = NA_real_,
      unsupported_mean = NA_real_, smd = NA_real_,
      unsupported_to_supported_sd = NA_real_))
  }
  pooled_sd <- sqrt((stats::var(z1) + stats::var(z0)) / 2)
  smd <- if (is.finite(pooled_sd) && pooled_sd > 0) {
    (mean(z1) - mean(z0)) / pooled_sd
  } else {
    0
  }
  supported_sd <- stats::sd(z1)
  variance_ratio <- if (is.finite(supported_sd) && supported_sd > 0) {
    stats::sd(z0) / supported_sd
  } else {
    NA_real_
  }
  data.frame(
    variable = variable,
    supported_mean = mean(z1),
    unsupported_mean = mean(z0),
    smd = smd,
    unsupported_to_supported_sd = variance_ratio
  )
}

lmv2_p5_rescue_score_gates <- function(treated_support) {
  required <- c(
    "cohort", "deal_id", "codinv", "supported",
    "log_patent_count_5y", LMV2_P5_RESCUE$selection_variables)
  if (!all(required %in% names(treated_support)) ||
      anyDuplicated(treated_support[c("cohort", "deal_id", "codinv")])) {
    stop("Support table schema or key is invalid")
  }
  if (anyNA(treated_support$supported)) {
    stop("Support indicator contains missing values")
  }
  treated_support$productivity_quartile <-
    lmv2_p5_rescue_assign_productivity_quartile(treated_support)
  supported <- as.logical(treated_support$supported)
  by_cohort <- do.call(
    rbind,
    lapply(split(treated_support, treated_support$cohort), function(z) {
      data.frame(
        cohort = z$cohort[[1]],
        eligible = nrow(z),
        supported = sum(z$supported),
        coverage = mean(z$supported)
      )
    })
  )
  by_quartile <- do.call(
    rbind,
    lapply(
      split(treated_support, treated_support$productivity_quartile),
      function(z) {
        data.frame(
          productivity_quartile = z$productivity_quartile[[1]],
          eligible = nrow(z),
          supported = sum(z$supported),
          coverage = mean(z$supported)
        )
      }
    )
  )
  selection <- do.call(
    rbind,
    lapply(
      LMV2_P5_RESCUE$selection_variables,
      function(v) lmv2_p5_rescue_selection_stat(
        treated_support, supported, v)
    )
  )
  eligible_deals <- unique(treated_support[c("cohort", "deal_id")])
  supported_deals <- unique(
    treated_support[supported, c("cohort", "deal_id")])
  g <- LMV2_P5_RESCUE$gates
  checks <- data.frame(
    gate = c(
      "aggregate_inventor_coverage", "minimum_cohort_coverage",
      "aggregate_deal_coverage",
      "minimum_productivity_quartile_coverage",
      "maximum_absolute_selection_smd"
    ),
    realized = c(
      mean(supported), min(by_cohort$coverage),
      nrow(supported_deals) / nrow(eligible_deals),
      min(by_quartile$coverage),
      max(abs(selection$smd))
    ),
    threshold = c(
      g$aggregate_inventor_coverage, g$minimum_cohort_coverage,
      g$aggregate_deal_coverage,
      g$minimum_productivity_quartile_coverage,
      g$selection_smd_pass
    ),
    direction = c(">=", ">=", ">=", ">=", "<="),
    stringsAsFactors = FALSE
  )
  checks$pass <- ifelse(
    checks$direction == ">=",
    checks$realized >= checks$threshold,
    checks$realized <= checks$threshold
  )
  checks$terminal <- checks$gate !=
    "maximum_absolute_selection_smd"
  list(
    pass = all(checks$pass[checks$terminal]),
    checks = checks,
    by_cohort = by_cohort,
    by_quartile = by_quartile,
    selection = selection
  )
}

# Pure fallback selector. It is certified now but cannot enter production
# until a supplemental amendment pins explicit k and max_distance values.
lmv2_p5_rescue_select_knn <- function(
    edges, k, max_distance, minimum_controls = 3L,
    minimum_firms = 2L) {
  required <- c(
    "cohort", "deal_id", "treated_codinv", "control_codinv",
    "control_group", "distance")
  if (!all(required %in% names(edges)) ||
      length(k) != 1L || k < minimum_controls ||
      length(max_distance) != 1L || !is.finite(max_distance)) {
    stop("Invalid k-nearest inputs")
  }
  x <- edges[
    is.finite(edges$distance) & edges$distance <= max_distance,
    required,
    drop = FALSE
  ]
  x <- x[order(
    x$cohort, x$deal_id, x$treated_codinv, x$distance,
    x$control_codinv, x$control_group), , drop = FALSE]
  x <- x[!duplicated(
    x[c("cohort", "deal_id", "treated_codinv", "control_codinv")]), ]
  treated <- unique(edges[c("cohort", "deal_id", "treated_codinv")])
  keys <- interaction(
    x$cohort, x$deal_id, x$treated_codinv,
    drop = TRUE, lex.order = TRUE)
  groups <- split(seq_len(nrow(x)), keys)
  selected <- list()
  unsupported <- list()
  for (i in seq_len(nrow(treated))) {
    key_i <- interaction(
      treated$cohort[i], treated$deal_id[i],
      treated$treated_codinv[i],
      drop = TRUE, lex.order = TRUE)
    z <- x[groups[[as.character(key_i)]], , drop = FALSE]
    if (nrow(z) < minimum_controls ||
        length(unique(z$control_group)) < minimum_firms) {
      unsupported[[length(unsupported) + 1L]] <- data.frame(
        treated[i, , drop = FALSE],
        reason = "insufficient_donors_or_firms_within_sanity_bound"
      )
      next
    }
    first_firm <- z$control_group[[1]]
    second_firm_idx <- which(z$control_group != first_firm)[1]
    anchor_idx <- c(1L, second_firm_idx)
    fill_idx <- setdiff(seq_len(nrow(z)), anchor_idx)
    take <- c(anchor_idx, head(fill_idx, max(0L, k - 2L)))
    chosen <- z[take, , drop = FALSE]
    chosen <- chosen[order(
      chosen$distance, chosen$control_codinv,
      chosen$control_group), , drop = FALSE]
    selected[[length(selected) + 1L]] <- chosen
  }
  selected_df <- if (length(selected)) {
    do.call(rbind, selected)
  } else {
    x[0, , drop = FALSE]
  }
  unsupported_df <- if (length(unsupported)) {
    do.call(rbind, unsupported)
  } else {
    data.frame(
      cohort = integer(), deal_id = integer(),
      treated_codinv = numeric(), reason = character()
    )
  }
  list(edges = selected_df, unsupported = unsupported_df)
}
