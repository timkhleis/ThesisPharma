#!/usr/bin/env Rscript

# Estimate and certify acquisition-aligned patent output for the approved
# initially-outside selected populations.

source(file.path("02_analysis", "R", "71a_lmv2_initially_outside_config.R"))
source(file.path("02_analysis", "R", "72_build_lmv2_initially_outside_s3.R"))
source(file.path("02_analysis", "R", "00_utils.R"))
use_project_library()

required <- c("DBI", "duckdb", "digest")
missing <- required[!vapply(required, requireNamespace, logical(1),
                           quietly = TRUE)]
if (length(missing)) stop("Missing R packages: ", paste(missing, collapse = ", "))

config <- lmv2_io_config()
dir.create(config$s4_dir, recursive = TRUE, showWarnings = FALSE)

gate <- read.csv(file.path(config$s3_dir, "s3_gate_summary.csv"),
                 stringsAsFactors = FALSE)
if (nrow(gate) != 1L || !isTRUE(gate$all_pass)) {
  stop("S3 gate is absent or did not pass; outcomes remain closed")
}

weights_path <- file.path(config$s3_dir, "s3_production_weights.parquet")
weights <- lmv2_io_read_parquet(weights_path)
weights$codinv <- as.numeric(weights$codinv)
weights$deal_id <- as.numeric(weights$deal_id)

load_outcomes <- function(ids) {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, paste0(
    "ATTACH ", lmv2_io_sql_string(config$foundation_db),
    " AS foundation (READ_ONLY)"))
  DBI::dbWriteTable(con, "relevant_ids",
                    data.frame(codinv = unique(as.numeric(ids))),
                    overwrite = TRUE)
  DBI::dbGetQuery(con, "
    SELECT CAST(y.codinv AS DOUBLE) AS codinv, y.year,
           CAST(y.patent_count AS DOUBLE) AS patent_count
    FROM foundation.p6.lmv2_outcome_inventor_year y
    JOIN relevant_ids r ON CAST(y.codinv AS DOUBLE)=r.codinv
    WHERE y.year BETWEEN 1988 AND 2015")
}

outcome <- load_outcomes(weights$codinv)

two_way_variance <- function(score, deal_id, codinv) {
  cluster_meat <- function(id) {
    sums <- rowsum(score, group = id, reorder = FALSE)
    g <- nrow(sums)
    if (g <= 1L) return(NA_real_)
    g / (g - 1) * sum(sums^2)
  }
  intersection <- paste(deal_id, codinv, sep = ":")
  variance <- cluster_meat(deal_id) + cluster_meat(codinv) -
    cluster_meat(intersection)
  max(variance, 0)
}

contrast_components <- function(dat, y) {
  d <- dat$treated == 1L
  w <- dat$final_weight
  mu_t <- weighted.mean(y[d], w[d])
  mu_c <- weighted.mean(y[!d], w[!d])
  estimate <- mu_t - mu_c
  score <- numeric(length(y))
  score[d] <- w[d] * (y[d] - mu_t) / sum(w[d])
  score[!d] <- -w[!d] * (y[!d] - mu_c) / sum(w[!d])
  list(estimate = estimate, treated_mean = mu_t, control_mean = mu_c,
       score = score,
       se = sqrt(two_way_variance(score, dat$deal_id, dat$codinv)))
}

wild_deal <- function(att, att_score, denominator, denominator_score,
                      deal_id, seed, draws) {
  att_cluster <- rowsum(att_score, deal_id, reorder = FALSE)[, 1]
  den_cluster <- rowsum(denominator_score, deal_id, reorder = FALSE)[, 1]
  deal_levels <- rownames(rowsum(att_score, deal_id, reorder = FALSE))
  den_by_deal <- rowsum(denominator_score, deal_id, reorder = FALSE)[deal_levels, 1]
  set.seed(seed)
  signs <- matrix(
    sample(c(-1, 1), length(att_cluster) * draws, replace = TRUE),
    nrow = length(att_cluster), ncol = draws)
  delta_att <- drop(crossprod(att_cluster, signs))
  delta_den <- drop(crossprod(den_by_deal, signs))
  alpha <- 0.05
  q <- stats::quantile(delta_att, c(alpha / 2, 1 - alpha / 2),
                       names = FALSE, type = 8)
  joint_ratio <- 100 * (att + delta_att) / (denominator + delta_den)
  list(
    conf_low = att - q[[2L]], conf_high = att - q[[1L]],
    p_value = (1 + sum(abs(delta_att) >= abs(att))) / (draws + 1),
    joint_ratio_low = stats::quantile(joint_ratio, alpha / 2,
                                      names = FALSE, type = 8),
    joint_ratio_high = stats::quantile(joint_ratio, 1 - alpha / 2,
                                       names = FALSE, type = 8))
}

build_panel <- function(w) {
  event <- data.frame(event_time = config$event_times)
  if (!"row_id" %in% names(w)) w$row_id <- seq_len(nrow(w))
  panel <- merge(w, event, by = NULL)
  panel$year <- panel$cohort + panel$event_time
  panel <- merge(panel, outcome, by = c("codinv", "year"),
                 all.x = TRUE, sort = FALSE)
  panel$patent_count[is.na(panel$patent_count)] <- 0
  panel[order(panel$row_id, panel$event_time), ]
}

estimate_variant <- function(w, variant_index) {
  w$row_id <- seq_len(nrow(w))
  panel <- build_panel(w)
  baseline <- panel[panel$event_time == -1,
                    c("row_id", "patent_count")]
  names(baseline)[2] <- "baseline_count"
  panel <- merge(panel, baseline, by = "row_id", all.x = TRUE, sort = FALSE)
  panel$change <- panel$patent_count - panel$baseline_count

  dynamic <- lapply(config$event_times[config$event_times != -1L], function(k) {
    x <- panel[panel$event_time == k, ]
    comp <- contrast_components(x, x$change)
    z <- comp$estimate / comp$se
    data.frame(
      event_time = k, estimate = comp$estimate, std_error = comp$se,
      conf_low = comp$estimate - 1.96 * comp$se,
      conf_high = comp$estimate + 1.96 * comp$se,
      p_value = 2 * stats::pnorm(-abs(z)),
      treated_change = comp$treated_mean,
      control_change = comp$control_mean,
      stringsAsFactors = FALSE)
  })
  dynamic <- do.call(rbind, dynamic)

  wide <- reshape(panel[c("row_id", "event_time", "patent_count")],
                  idvar = "row_id", timevar = "event_time",
                  direction = "wide")
  dat <- merge(w, wide, by = "row_id", all.x = TRUE, sort = FALSE)
  post_cols <- paste0("patent_count.", config$post_times)
  dat$post_mean <- rowMeans(dat[post_cols])
  dat$baseline <- dat[["patent_count.-1"]]
  dat$post_change <- dat$post_mean - dat$baseline
  comp <- contrast_components(dat, dat$post_change)

  d <- dat$treated == 1L
  wc <- dat$final_weight[!d]
  control_post <- weighted.mean(dat$post_mean[!d], wc)
  treated_post <- weighted.mean(dat$post_mean[d], dat$final_weight[d])
  control_baseline <- weighted.mean(dat$baseline[!d], wc)
  treated_baseline <- weighted.mean(
    dat$baseline[d], dat$final_weight[d])
  denominator_score <- numeric(nrow(dat))
  denominator_score[!d] <- wc * (dat$post_mean[!d] - control_post) / sum(wc)
  wild <- wild_deal(
    comp$estimate, comp$score, control_post, denominator_score,
    dat$deal_id, config$bootstrap$seed + variant_index,
    config$bootstrap$draws)

  analytic_low <- comp$estimate - 1.96 * comp$se
  analytic_high <- comp$estimate + 1.96 * comp$se
  aggregate <- data.frame(
    estimate = comp$estimate, std_error = comp$se,
    conf_low = analytic_low, conf_high = analytic_high,
    p_value = 2 * stats::pnorm(-abs(comp$estimate / comp$se)),
    wild_conf_low = wild$conf_low, wild_conf_high = wild$conf_high,
    wild_p_value = wild$p_value,
    cumulative_five_year = 5 * comp$estimate,
    treated_post_mean = treated_post,
    control_post_mean = control_post,
    treated_baseline_mean = treated_baseline,
    control_baseline_mean = control_baseline,
    baseline_gap = treated_baseline - control_baseline,
    percent_effect = 100 * comp$estimate / control_post,
    percent_fixed_low = 100 * analytic_low / control_post,
    percent_fixed_high = 100 * analytic_high / control_post,
    percent_joint_wild_low = wild$joint_ratio_low,
    percent_joint_wild_high = wild$joint_ratio_high,
    n_treated = sum(d), n_control_rows = sum(!d),
    nominal_treated_deals = length(unique(dat$deal_id[d])),
    stringsAsFactors = FALSE)

  deals <- sort(unique(dat$deal_id[d]))
  lodo <- lapply(deals, function(g) {
    keep <- dat$deal_id != g
    cpt <- contrast_components(dat[keep, ], dat$post_change[keep])
    data.frame(omitted_deal_id = g, estimate = cpt$estimate)
  })
  list(dynamic = dynamic, aggregate = aggregate,
       lodo = do.call(rbind, lodo), analysis_data = dat)
}

variant_names <- sort(unique(weights$support_variant))
results <- list()
for (i in seq_along(variant_names)) {
  variant <- variant_names[[i]]
  message("Estimating initially-outside outcome: ", variant)
  w <- weights[weights$support_variant == variant, , drop = FALSE]
  results[[variant]] <- estimate_variant(w, i)
  results[[variant]]$dynamic$support_variant <- variant
  results[[variant]]$aggregate$support_variant <- variant
  results[[variant]]$lodo$support_variant <- variant
}

dynamic <- do.call(rbind, lapply(results, `[[`, "dynamic"))
aggregate_results <- do.call(rbind, lapply(results, `[[`, "aggregate"))
lodo <- do.call(rbind, lapply(results, `[[`, "lodo"))
row.names(dynamic) <- row.names(aggregate_results) <- row.names(lodo) <- NULL

lmv2_io_write_csv(dynamic, file.path(config$s4_dir, "dynamic_estimates.csv"))
lmv2_io_write_csv(aggregate_results,
                  file.path(config$s4_dir, "aggregate_estimates.csv"))
lmv2_io_write_csv(lodo, file.path(config$s4_dir, "leave_one_deal_out.csv"))

# Common-support tipping for the primary selected population.
primary_name <- "primary_initially_outside_t1_t5"
primary_att <- aggregate_results$estimate[
  aggregate_results$support_variant == primary_name]
treated_partition <- lmv2_io_read_parquet(
  file.path(config$s0_dir, "treated_status_partition.parquet"),
  "primary_initially_outside")
pre_outcome <- load_outcomes(treated_partition$codinv)
pre_grid <- merge(
  treated_partition[c("cohort", "deal_id", "codinv")],
  data.frame(event_time = -5:-1), by = NULL)
pre_grid$year <- pre_grid$cohort + pre_grid$event_time
pre_grid <- merge(pre_grid, pre_outcome, by = c("codinv", "year"),
                  all.x = TRUE, sort = FALSE)
pre_grid$patent_count[is.na(pre_grid$patent_count)] <- 0
pre_mean <- stats::aggregate(patent_count ~ cohort + deal_id + codinv,
                             pre_grid, mean)$patent_count
limits <- stats::quantile(pre_mean, c(0.01, 0.99), names = FALSE)
pre_winsor <- pmin(pmax(pre_mean, limits[[1L]]), limits[[2L]])
sigma_pre <- stats::sd(pre_winsor)
p_support <- gate$support_retention
delta_grid <- c(-3, -2, -1.5, -1, -0.5, 0, 0.5, 1, 1.5, 2, 3)
tipping <- data.frame(
  delta = delta_grid,
  att_supported = primary_att,
  att_unsupported = primary_att + delta_grid * sigma_pre,
  p_supported = p_support,
  sigma_pre = sigma_pre)
tipping$att_all <- with(
  tipping, p_supported * att_supported +
    (1 - p_supported) * att_unsupported)
reversal <- data.frame(
  att_supported = primary_att, p_supported = p_support,
  sigma_pre = sigma_pre,
  unsupported_att_to_zero = -p_support / (1 - p_support) * primary_att,
  delta_to_zero = -primary_att / ((1 - p_support) * sigma_pre))
lmv2_io_write_csv(tipping, file.path(config$s4_dir, "support_tipping_grid.csv"))
lmv2_io_write_csv(reversal, file.path(config$s4_dir, "support_tipping_reversal.csv"))

# Precision interpretation fixed before outcomes were opened.
mde <- read.csv(file.path(config$s3_dir, "preperiod_mde.csv"),
                stringsAsFactors = FALSE)
primary <- aggregate_results[
  aggregate_results$support_variant == primary_name, ]
equivalence_bound <- config$gates$equivalence_percent / 100 *
  primary$control_post_mean
precision <- data.frame(
  mde_80 = mde$mde_80,
  mde_percent_control_post = 100 * mde$mde_80 / primary$control_post_mean,
  equivalence_bound = equivalence_bound,
  equivalently_small = primary$conf_low > -equivalence_bound &
    primary$conf_high < equivalence_bound,
  stringsAsFactors = FALSE)
lmv2_io_write_csv(precision, file.path(config$s4_dir, "precision_interpretation.csv"))

# Certification.
primary_dynamic <- dynamic[dynamic$support_variant == primary_name, ]
clean_name <- "censoring_clean_initially_outside_1993_2008"
checks <- data.frame(
  check = c(
    "s3_gate_passed", "primary_estimate_present",
    "primary_dynamic_complete", "headline_excludes_event_zero",
    "cumulative_identity", "percentage_identity", "baseline_balanced",
    "censoring_clean_present", "target_only_not_silently_estimated",
    "wild_draw_count_fixed", "support_tipping_complete",
    "all_numeric_outputs_finite"),
  pass = c(
    isTRUE(gate$all_pass),
    nrow(primary) == 1L,
    identical(sort(primary_dynamic$event_time),
              config$event_times[config$event_times != -1L]),
    !0L %in% config$post_times,
    abs(primary$cumulative_five_year - 5 * primary$estimate) < 1e-12,
    abs(primary$percent_effect -
          100 * primary$estimate / primary$control_post_mean) < 1e-12,
    abs(primary$baseline_gap) <= config$gates$maximum_exact_smd,
    clean_name %in% aggregate_results$support_variant,
    !"target_only_initially_outside_t1_t5" %in%
      aggregate_results$support_variant,
    config$bootstrap$draws == 9999L,
    nrow(tipping) == length(delta_grid) && nrow(reversal) == 1L,
    all(is.finite(unlist(aggregate_results[setdiff(
      names(aggregate_results), "support_variant")])))),
  stringsAsFactors = FALSE)
lmv2_io_write_csv(checks, file.path(config$s4_dir, "s4_certification.csv"))

manifest_paths <- c(
  config$plan_files, weights_path, config$foundation_db,
  file.path(config$base, "02_analysis", "R",
            c("71a_lmv2_initially_outside_config.R",
              "73_run_lmv2_initially_outside_s4.R")))
manifest_paths <- manifest_paths[file.exists(manifest_paths)]
manifest <- data.frame(
  path = normalizePath(manifest_paths, winslash = "/", mustWork = TRUE),
  sha256 = vapply(manifest_paths, lmv2_io_sha256, character(1)),
  stringsAsFactors = FALSE)
lmv2_io_write_csv(manifest, file.path(config$s4_dir, "s4_manifest.csv"))

if (!all(checks$pass)) {
  stop("S4 certification failed: ",
       paste(checks$check[!checks$pass], collapse = ", "))
}
print(primary)
print(precision)
message("Certified initially-outside S4: ", config$s4_dir)
