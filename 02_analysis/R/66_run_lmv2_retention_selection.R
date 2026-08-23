# ============================================================================
# 66_run_lmv2_retention_selection.R -- two-part retention-selection models
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))

required <- c("DBI", "duckdb", "digest", "fixest")
for (pkg in required) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

VERSION <- "lmv2_retention_selection_1993_v1"
FREEZE_PATH <- file.path(
  BASE, "notes", "local_match_v2_1993_selection_extensions_freeze.md")
FREEZE_SHA256 <-
  "3f4ea043dc48eefee6e3b60e0c0396584c5477898db7c2c56249f659cc490aa6"
if (!identical(
    digest::digest(file = FREEZE_PATH, algo = "sha256"),
    FREEZE_SHA256)) {
  stop("Selection-extension freeze has drifted")
}

AUDIT_ROOT <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment")
INPUT_DIR <- file.path(AUDIT_ROOT, "P5B_STAYER_S0_S2")
EXISTING_SELECTION_DIR <- file.path(
  AUDIT_ROOT, "P5B_STAYER_SELECTION_DIAGNOSTICS")
OUTPUT_DIR <- file.path(AUDIT_ROOT, "RETENTION_SELECTION_MODELS")
DB_PATH <- file.path(BASE, "output", "thesis_foundation.duckdb")
PARTITION_PATH <- file.path(INPUT_DIR, "treated_retention_partition.parquet")
RAW_AUDIT_PATH <- file.path(
  INPUT_DIR, "raw_first_post_affiliation_audit.parquet")
GROUP_SUMMARY_PATH <- file.path(
  EXISTING_SELECTION_DIR, "selection_group_summary.csv")

inputs <- c(DB_PATH, PARTITION_PATH, RAW_AUDIT_PATH, GROUP_SUMMARY_PATH)
if (any(!file.exists(inputs))) {
  stop("A required retention-selection input is missing: ",
       paste(inputs[!file.exists(inputs)], collapse = "; "))
}
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

write_csv <- function(x, name) {
  utils::write.csv(
    x, file.path(OUTPUT_DIR, name), row.names = FALSE, na = "")
}

sql_string <- function(x) {
  paste0("'", gsub("'", "''", normalizePath(
    x, winslash = "/", mustWork = TRUE), fixed = TRUE), "'")
}

con <- DBI::dbConnect(duckdb::duckdb(), DB_PATH, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "SET threads=4")

partition_sql <- sql_string(PARTITION_PATH)
raw_sql <- sql_string(RAW_AUDIT_PATH)

dat <- DBI::dbGetQuery(con, sprintf("
  WITH status AS (
    SELECT *
    FROM read_parquet(%s)
    WHERE cohort BETWEEN 1993 AND 2010
  ), raw AS (
    SELECT retention_window, cohort, deal_id, codinv,
           raw_group_mixed, any_focal_route_mixed
    FROM read_parquet(%s)
    WHERE arm='treated'
  ), ipc AS (
    SELECT s.retention_window, s.cohort, s.deal_id, s.codinv,
           SUBSTR(i.ipc_code, 1, 1) AS ipc_section,
           SUM(i.patent_count) AS ipc_patents
    FROM status s
    LEFT JOIN inventor_ipc_year i
      ON CAST(i.codinv AS BIGINT)=s.codinv
     AND i.year BETWEEN s.cohort-5 AND s.cohort-1
    GROUP BY s.retention_window, s.cohort, s.deal_id, s.codinv,
             SUBSTR(i.ipc_code, 1, 1)
  ), ipc_ranked AS (
    SELECT *, ROW_NUMBER() OVER (
      PARTITION BY retention_window, cohort, deal_id, codinv
      ORDER BY ipc_patents DESC NULLS LAST, ipc_section) AS rn
    FROM ipc
  ), target_size AS (
    SELECT cohort, deal_id, COUNT(DISTINCT codinv) AS target_group_size
    FROM lmv2_p3_treated_inventor_units
    WHERE cohort BETWEEN 1993 AND 2010
    GROUP BY cohort, deal_id
  )
  SELECT s.cohort, s.deal_id, s.codinv, s.retention_window,
         s.is_primary, s.first_event_time, s.first_post_year,
         s.retention_status, s.route_disagreement,
         COALESCE(r.raw_group_mixed, FALSE) AS raw_group_mixed,
         COALESCE(r.any_focal_route_mixed, FALSE) AS any_focal_route_mixed,
         p.patent_count_5y, p.log_patent_count_5y,
         CAST(p.active_pre_years AS DOUBLE)/5.0 AS pre_active_rate,
         p.patent_trajectory, p.career_age, p.focal_group_tenure,
         p.focal_group_exclusivity,
         COALESCE(ir.ipc_section, 'UNKNOWN') AS ipc_section,
         ts.target_group_size, dm.target_value
  FROM status s
  JOIN lmv2_p3_treated_inventor_units p
    USING (cohort, deal_id, codinv)
  LEFT JOIN raw r
    USING (retention_window, cohort, deal_id, codinv)
  LEFT JOIN ipc_ranked ir
    ON ir.retention_window=s.retention_window
   AND ir.cohort=s.cohort AND ir.deal_id=s.deal_id
   AND ir.codinv=s.codinv AND ir.rn=1
  LEFT JOIN target_size ts USING (cohort, deal_id)
  LEFT JOIN deal_map dm USING (deal_id)
  ORDER BY s.retention_window, s.cohort, s.deal_id, s.codinv
", partition_sql, raw_sql))

key <- dat[c("retention_window", "cohort", "deal_id", "codinv")]
if (anyDuplicated(key)) stop("Retention model input keys are duplicated")
if (!all(dat$retention_status %in% c(
    "initially_retained", "leaver", "no_post_patent"))) {
  stop("Unexpected retention status")
}

primary <- dat[dat$retention_window == "t1_t5_primary", , drop = FALSE]
existing <- utils::read.csv(GROUP_SUMMARY_PATH, stringsAsFactors = FALSE)
observed_counts <- table(primary$retention_status)
expected_counts <- setNames(existing$inventors, existing$retention_status)
if (!all(observed_counts[names(expected_counts)] == expected_counts)) {
  stop("Primary status counts do not reproduce the existing diagnostics")
}

continuous <- c(
  "log_patent_count_5y", "pre_active_rate", "patent_trajectory",
  "career_age", "focal_group_tenure", "focal_group_exclusivity",
  "log_target_group_size", "log_deal_value")
dat$log_target_group_size <- log1p(dat$target_group_size)
dat$log_deal_value <- log1p(pmax(dat$target_value, 0))

scale_reference <- dat[
  dat$retention_window == "t1_t5_primary", , drop = FALSE]
scale_manifest <- list()
for (v in continuous) {
  ref <- scale_reference[[v]]
  med <- stats::median(ref, na.rm = TRUE)
  if (!is.finite(med)) stop("No finite values for ", v)
  ref_filled <- ifelse(is.na(ref), med, ref)
  mu <- mean(ref_filled)
  sig <- stats::sd(ref_filled)
  if (!is.finite(sig) || sig <= 0) stop("Zero or invalid SD for ", v)
  dat[[paste0("missing_", v)]] <- as.integer(is.na(dat[[v]]))
  filled <- ifelse(is.na(dat[[v]]), med, dat[[v]])
  dat[[paste0("z_", v)]] <- (filled - mu) / sig
  scale_manifest[[v]] <- data.frame(
    variable = v, median_imputation = med, mean = mu, sd = sig,
    missing_primary = sum(is.na(ref)), stringsAsFactors = FALSE)
}
dat$z_career_age_sq <- dat$z_career_age^2
scale_manifest <- do.call(rbind, scale_manifest)
write_csv(scale_manifest, "retention_selection_scaling.csv")

rhs_terms <- c(
  "z_log_patent_count_5y", "z_pre_active_rate", "z_patent_trajectory",
  "z_career_age", "z_career_age_sq", "z_focal_group_tenure",
  "z_focal_group_exclusivity", "z_log_target_group_size",
  "z_log_deal_value", "factor(ipc_section)")
missing_terms <- paste0("missing_", continuous)
missing_terms <- missing_terms[vapply(
  missing_terms, function(v) length(unique(dat[[v]])) > 1L, logical(1))]
rhs_terms <- c(rhs_terms, missing_terms)

make_formula <- function(outcome) {
  stats::as.formula(paste0(
    outcome, " ~ ", paste(rhs_terms, collapse = " + "), " | cohort"))
}

auc_rank <- function(y, p) {
  n1 <- sum(y == 1L)
  n0 <- sum(y == 0L)
  if (!n1 || !n0) return(NA_real_)
  (sum(rank(p, ties.method = "average")[y == 1L]) -
     n1 * (n1 + 1) / 2) / (n1 * n0)
}

link_derivatives <- function(eta, link) {
  if (link == "logit") {
    p <- stats::plogis(eta)
    g <- p * (1 - p)
    gp <- g * (1 - 2 * p)
  } else {
    p <- stats::pnorm(eta)
    g <- stats::dnorm(eta)
    gp <- -eta * g
  }
  list(p = p, g = g, gp = gp)
}

average_marginal_effects <- function(fit, link, model_id) {
  beta <- stats::coef(fit)
  X <- stats::model.matrix(fit)
  X <- X[, names(beta), drop = FALSE]
  eta <- as.numeric(stats::predict(fit, type = "link"))
  deriv <- link_derivatives(eta, link)
  V <- stats::vcov(fit)
  wanted <- intersect(c(
    "z_log_patent_count_5y", "z_pre_active_rate",
    "z_patent_trajectory", "z_career_age",
    "z_focal_group_tenure", "z_focal_group_exclusivity",
    "z_log_target_group_size", "z_log_deal_value"), names(beta))
  do.call(rbind, lapply(wanted, function(term) {
    j <- match(term, names(beta))
    ame <- mean(deriv$g) * beta[[j]]
    grad <- colMeans(deriv$gp * X) * beta[[j]]
    grad[[j]] <- grad[[j]] + mean(deriv$g)
    se <- sqrt(max(0, as.numeric(t(grad) %*% V %*% grad)))
    data.frame(
      model_id = model_id, term = term, estimate = ame, se = se,
      ci_low = ame - 1.96 * se, ci_high = ame + 1.96 * se,
      scale = "average_probability_change_per_one_reference_SD",
      stringsAsFactors = FALSE)
  }))
}

prediction_at_productivity <- function(fit, data_used, model_id) {
  beta <- stats::coef(fit)
  X <- stats::model.matrix(fit)
  X <- X[, names(beta), drop = FALSE]
  eta <- as.numeric(stats::predict(fit, type = "link"))
  link <- if (grepl("probit", model_id)) "probit" else "logit"
  term <- "z_log_patent_count_5y"
  if (!term %in% names(beta)) return(NULL)
  raw <- data_used$patent_count_5y
  points <- stats::quantile(raw, c(0.25, 0.75), na.rm = TRUE, names = FALSE)
  scaler <- scale_manifest[scale_manifest$variable ==
                             "log_patent_count_5y", ]
  z_points <- (log1p(points) - scaler$mean) / scaler$sd
  V <- stats::vcov(fit)
  out <- lapply(seq_along(points), function(k) {
    Xcf <- X
    Xcf[, term] <- z_points[[k]]
    eta_cf <- eta + (z_points[[k]] - X[, term]) * beta[[term]]
    if (link == "logit") {
      p <- stats::plogis(eta_cf)
      density <- p * (1 - p)
    } else {
      p <- stats::pnorm(eta_cf)
      density <- stats::dnorm(eta_cf)
    }
    grad <- colMeans(density * Xcf)
    estimate <- mean(p)
    se <- sqrt(max(0, as.numeric(t(grad) %*% V %*% grad)))
    data.frame(
      model_id = model_id,
      productivity_point = c("p25", "p75")[[k]],
      patent_count_5y = points[[k]], estimate = estimate, se = se,
      ci_low = estimate - 1.96 * se,
      ci_high = estimate + 1.96 * se,
      stringsAsFactors = FALSE)
  })
  do.call(rbind, out)
}

joint_productivity_test <- function(fit, model_id) {
  terms <- intersect(c(
    "z_log_patent_count_5y", "z_pre_active_rate",
    "z_patent_trajectory"), names(stats::coef(fit)))
  b <- stats::coef(fit)[terms]
  V <- stats::vcov(fit)[terms, terms, drop = FALSE]
  stat <- as.numeric(t(b) %*% solve(V, b))
  data.frame(
    model_id = model_id, terms = paste(terms, collapse = ";"),
    chi_square = stat, df = length(terms),
    p_value = stats::pchisq(stat, length(terms), lower.tail = FALSE),
    stringsAsFactors = FALSE)
}

fit_one <- function(data_used, outcome, link, model_id) {
  if (length(unique(data_used[[outcome]])) != 2L) {
    stop("Binary outcome lacks variation for ", model_id)
  }
  fit <- fixest::feglm(
    make_formula(outcome), data = data_used,
    family = stats::binomial(link = link), vcov = ~deal_id,
    notes = FALSE, warn = FALSE)
  pred <- as.numeric(stats::predict(fit, type = "response"))
  y <- data_used[[outcome]]
  clipped <- pmin(pmax(pred, 1e-6), 1 - 1e-6)
  calibration <- stats::glm(
    y ~ stats::qlogis(clipped), family = stats::binomial())
  summary_row <- data.frame(
    model_id = model_id, outcome = outcome, link = link,
    observations = nrow(data_used), positives = sum(y),
    deals = length(unique(data_used$deal_id)),
    cohorts = length(unique(data_used$cohort)),
    auc = auc_rank(y, pred), brier = mean((y - pred)^2),
    calibration_intercept = stats::coef(calibration)[[1]],
    calibration_slope = stats::coef(calibration)[[2]],
    min_prediction = min(pred), max_prediction = max(pred),
    log_likelihood = as.numeric(stats::logLik(fit)),
    stringsAsFactors = FALSE)
  list(
    fit = fit,
    summary = summary_row,
    ame = average_marginal_effects(fit, link, model_id),
    predictions = prediction_at_productivity(fit, data_used, model_id),
    joint = joint_productivity_test(fit, model_id))
}

prepare_sample <- function(window, outcome, restriction = "none") {
  z <- dat[dat$retention_window == window, , drop = FALSE]
  z$continued_patenting <- as.integer(
    z$retention_status != "no_post_patent")
  z$observed_retention <- as.integer(
    z$retention_status == "initially_retained")
  if (outcome == "observed_retention") {
    z <- z[z$continued_patenting == 1L, , drop = FALSE]
  }
  if (restriction == "raw_unmixed") {
    z <- z[!z$raw_group_mixed, , drop = FALSE]
  } else if (restriction == "route_consistent") {
    z <- z[!z$route_disagreement, , drop = FALSE]
  }
  z
}

specs <- list(
  list("primary_continuation_logit", "t1_t5_primary",
       "continued_patenting", "logit", "none"),
  list("primary_retention_logit", "t1_t5_primary",
       "observed_retention", "logit", "none"),
  list("primary_continuation_probit", "t1_t5_primary",
       "continued_patenting", "probit", "none"),
  list("primary_retention_probit", "t1_t5_primary",
       "observed_retention", "probit", "none"),
  list("raw_unmixed_retention_logit", "t1_t5_primary",
       "observed_retention", "logit", "raw_unmixed"),
  list("route_consistent_retention_logit", "t1_t5_primary",
       "observed_retention", "logit", "route_consistent"),
  list("t2_t5_retention_logit", "t2_t5_sensitivity",
       "observed_retention", "logit", "none"))

fits <- list()
for (s in specs) {
  message("Estimating ", s[[1]])
  sample <- prepare_sample(s[[2]], s[[3]], s[[5]])
  fits[[s[[1]]]] <- fit_one(sample, s[[3]], s[[4]], s[[1]])
}

model_summary <- do.call(rbind, lapply(fits, `[[`, "summary"))
ames <- do.call(rbind, lapply(fits, `[[`, "ame"))
predictions <- do.call(rbind, lapply(fits, `[[`, "predictions"))
joint_tests <- do.call(rbind, lapply(fits, `[[`, "joint"))

timing <- primary[primary$retention_status != "no_post_patent", ]
timing$first_post_event_time <- timing$first_post_year - timing$cohort
timing_diagnostic <- do.call(rbind, lapply(
  split(timing, timing$first_post_event_time), function(z) data.frame(
    first_post_event_time = z$first_post_event_time[[1]],
    continuing_inventors = nrow(z),
    retained_inventors = sum(z$retention_status == "initially_retained"),
    observed_retention_rate = mean(
      z$retention_status == "initially_retained"),
    deals = length(unique(z$deal_id)), stringsAsFactors = FALSE)))

primary_productivity <- ames[
  ames$model_id == "primary_retention_logit" &
    ames$term == "z_log_patent_count_5y", ]
if (nrow(primary_productivity) != 1L) {
  stop("Primary retained-productivity AME is unavailable")
}
selection_direction <- if (primary_productivity$ci_low > 0) {
  "positive_observed_selection"
} else if (primary_productivity$ci_high < 0) {
  "negative_observed_selection"
} else {
  "imprecise_observed_selection"
}
primary_block <- ames[
  ames$model_id == "primary_retention_logit" &
    ames$term %in% c(
      "z_log_patent_count_5y", "z_pre_active_rate",
      "z_patent_trajectory"), ]
primary_joint <- joint_tests[
  joint_tests$model_id == "primary_retention_logit", ]
block_direction <- if (
    primary_joint$p_value < 0.05 && all(primary_block$estimate > 0)) {
  "positive_joint_productivity_association"
} else if (
    primary_joint$p_value < 0.05 && all(primary_block$estimate < 0)) {
  "negative_joint_productivity_association"
} else {
  "mixed_or_imprecise_joint_productivity_association"
}
sign_mapping <- rbind(
  data.frame(
    evidence = "five_year_patent_stock_ame",
    estimand = "observed_retention_conditional_on_postdeal_patenting",
    estimate = primary_productivity$estimate,
    ci_low = primary_productivity$ci_low,
    ci_high = primary_productivity$ci_high,
    p_value = NA_real_, selection_direction = selection_direction,
    thesis_interpretation = paste(
      "The patent-stock component alone is read from its confidence interval.",
      "It does not identify the direction of bias in an always-retained",
      "causal effect without additional assumptions."),
    stringsAsFactors = FALSE),
  data.frame(
    evidence = "joint_productivity_block",
    estimand = "observed_retention_conditional_on_postdeal_patenting",
    estimate = NA_real_, ci_low = NA_real_, ci_high = NA_real_,
    p_value = primary_joint$p_value,
    selection_direction = block_direction,
    thesis_interpretation = paste(
      "The three pre-deal productivity measures are tested jointly and",
      "their marginal-effect signs are reported. This documents selection",
      "on observables but does not identify the direction of bias in an",
      "always-retained causal effect without additional assumptions."),
    stringsAsFactors = FALSE))

write_csv(model_summary, "retention_selection_model_summary.csv")
write_csv(ames, "retention_selection_average_marginal_effects.csv")
write_csv(predictions, "retention_selection_productivity_predictions.csv")
write_csv(joint_tests, "retention_selection_productivity_joint_tests.csv")
write_csv(timing_diagnostic, "retention_selection_timing_diagnostic.csv")
write_csv(sign_mapping, "retention_selection_sign_mapping.csv")

certification <- data.frame(
  check = c(
    "freeze_hash_matches", "primary_keys_unique",
    "primary_status_counts_reproduce_existing_diagnostics",
    "all_18_cohorts_present", "all_models_finite",
    "all_probabilities_in_unit_interval", "primary_logit_and_probit_built",
    "classification_sensitivities_built",
    "post_timing_not_in_model_formula", "sign_mapping_is_noncausal"),
  pass = c(
    TRUE, !anyDuplicated(key),
    all(observed_counts[names(expected_counts)] == expected_counts),
    identical(sort(unique(primary$cohort)), 1993:2010),
    all(is.finite(model_summary$log_likelihood)),
    all(model_summary$min_prediction >= 0 &
          model_summary$max_prediction <= 1),
    all(c("primary_continuation_logit", "primary_retention_logit",
          "primary_continuation_probit", "primary_retention_probit") %in%
          model_summary$model_id),
    all(c("raw_unmixed_retention_logit",
          "route_consistent_retention_logit",
          "t2_t5_retention_logit") %in% model_summary$model_id),
    !any(grepl("first_post", rhs_terms)),
    all(grepl("does not identify", sign_mapping$thesis_interpretation))),
  stringsAsFactors = FALSE)
write_csv(certification, "retention_selection_certification.csv")
if (!all(certification$pass)) {
  stop("Retention-selection certification failed")
}

source_files <- c(
  FREEZE_PATH, file.path(BASE, "R", "66_run_lmv2_retention_selection.R"))
manifest <- data.frame(
  version = VERSION,
  freeze_sha256 = FREEZE_SHA256,
  source_sha256 = digest::digest(
    vapply(source_files, digest::digest, character(1),
           file = TRUE, algo = "sha256"),
    algo = "sha256", serialize = TRUE),
  partition_sha256 = digest::digest(
    file = PARTITION_PATH, algo = "sha256"),
  raw_audit_sha256 = digest::digest(
    file = RAW_AUDIT_PATH, algo = "sha256"),
  primary_observations = nrow(primary),
  primary_deals = length(unique(primary$deal_id)),
  primary_cohorts = length(unique(primary$cohort)),
  models = nrow(model_summary),
  certified = all(certification$pass),
  stringsAsFactors = FALSE)
write_csv(manifest, "retention_selection_manifest.csv")

main_cont <- ames[
  ames$model_id == "primary_continuation_logit" &
    ames$term == "z_log_patent_count_5y", ]
lines <- c(
  "# Retention-selection diagnostics",
  "",
  "These models quantify selection on observed pre-acquisition characteristics. They do not identify an effect for inventors who would have been retained under either acquisition state.",
  "",
  sprintf(
    "- A one-standard-deviation increase in log pre-deal patent stock changes the predicted probability of any post-deal patenting by %.3f (95%% CI [%.3f, %.3f]).",
    main_cont$estimate, main_cont$ci_low, main_cont$ci_high),
  sprintf(
    "- Conditional on post-deal patenting, the corresponding change in predicted observed retention is %.3f (95%% CI [%.3f, %.3f]).",
    primary_productivity$estimate, primary_productivity$ci_low,
    primary_productivity$ci_high),
  sprintf(
    "- The pre-deal productivity block jointly predicts observed retention (p=%.3g); all three marginal-effect point estimates are positive.",
    primary_joint$p_value),
  sprintf(
    "- The five-year patent-stock component alone is classified as `%s`; the joint productivity pattern is `%s`.",
    selection_direction, block_direction),
  "- The probit, affiliation, route, and timing specifications are functional-form or measurement sensitivities, not alternative causal estimands.")
writeLines(lines, file.path(OUTPUT_DIR, "retention_selection_results.md"))

message("Retention-selection package complete and certified")
