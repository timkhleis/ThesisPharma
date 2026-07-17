# ============================================================================
# 11l_estimate_robustness_results.R -- Main DiD v1 robustness event studies
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "11a_main_design_config.R"))
source(file.path(BASE, "R", "11_main_design_utils.R"))
source(file.path(BASE, "R", "11i_robustness_config.R"))

for (pkg in c("DBI", "duckdb", "fixest", "ggplot2"))
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
suppressMessages({ library(DBI); library(duckdb); library(fixest); library(ggplot2) })

PANEL_NT_H5_PARQUET <- file.path(DERIVED_PAR, "main_did_v1_panel_never_target_h5.parquet")
PANEL_G7_PARQUET <- file.path(DERIVED_PAR, "main_did_v1_panel_g7.parquet")

EVENT_WINDOW_11L <- EVENT_LO:EVENT_HI
PRE_PERIODS_11L <- EVENT_LO:-2L
POST_PERIODS_11L <- PRIMARY_POST
REFERENCE_11L <- -1L
EXPECTED_EVENT_TIMES <- setdiff(EVENT_WINDOW_11L, REFERENCE_11L)

sql_path <- function(path) gsub("\\\\", "/", path)
term_for <- function(periods) sprintf("event_time::%d:treated", periods)

specs <- data.frame(
  spec = c("P0H5", "P2", "P5", "P4"),
  label = c("Inventor-weighted never-target (P0H5)",
            "Acquirer-clean never-target (P2)",
            "Deal-weighted never-target (P5)",
            "Deal-weighted g+7 (P4)"),
  panel_path = c(PANEL_NT_H5_PARQUET, PANEL_NT_H5_PARQUET, PANEL_NT_H5_PARQUET, PANEL_G7_PARQUET),
  weight_path = c(P0H5_WEIGHTS_PARQUET, P2_WEIGHTS_PARQUET, P5_WEIGHTS_PARQUET, P4_WEIGHTS_PARQUET),
  color = c("#1B7837", "#2166AC", "#E66101", "#5E3C99"),
  stringsAsFactors = FALSE
)

vcov_matrix <- function(mod) {
  V <- stats::vcov(mod)
  if (is.null(dim(V))) stop("Model returned no covariance matrix.")
  V
}

extract_dynamic <- function(mod, outcome, spec, variant, cluster_label, spec_label) {
  b <- stats::coef(mod)
  V <- vcov_matrix(mod)
  missing_terms <- setdiff(term_for(EXPECTED_EVENT_TIMES), names(b))
  if (length(missing_terms) > 0) {
    stop("Missing expected event-study coefficients for ", spec, " / ", outcome, ": ",
         paste(missing_terms, collapse = ", "))
  }
  do.call(rbind, lapply(EVENT_WINDOW_11L, function(e) {
    if (e == REFERENCE_11L) {
      data.frame(outcome = outcome, spec = spec, spec_label = spec_label,
        variant = variant, cluster = cluster_label, event_time = e, estimate = 0,
        se = NA_real_, ci_low = NA_real_, ci_high = NA_real_,
        reference_period = TRUE, partial_exposure = FALSE, stringsAsFactors = FALSE)
    } else {
      tm <- term_for(e)
      est <- b[[tm]]
      se <- sqrt(V[tm, tm])
      data.frame(outcome = outcome, spec = spec, spec_label = spec_label,
        variant = variant, cluster = cluster_label, event_time = e,
        estimate = est, se = se, ci_low = est - 1.96 * se,
        ci_high = est + 1.96 * se, reference_period = FALSE,
        partial_exposure = e == 0L, stringsAsFactors = FALSE)
    }
  }))
}

linear_combo <- function(mod, periods, divisor, label) {
  b <- stats::coef(mod)
  V <- vcov_matrix(mod)
  keep <- term_for(periods)
  missing_terms <- setdiff(keep, names(b))
  if (length(missing_terms) > 0)
    stop("Cannot compute ", label, "; missing terms: ", paste(missing_terms, collapse = ", "))
  L <- stats::setNames(rep(0, length(b)), names(b))
  L[keep] <- 1 / divisor
  est <- sum(L * b)
  se <- sqrt(as.numeric(t(L) %*% V %*% L))
  data.frame(summary = label, estimate = est, se = se,
    ci_low = est - 1.96 * se, ci_high = est + 1.96 * se,
    periods = paste(periods, collapse = ","), stringsAsFactors = FALSE)
}

joint_wald <- function(mod, periods, label) {
  b <- stats::coef(mod)
  V <- vcov_matrix(mod)
  keep <- term_for(periods)
  missing_terms <- setdiff(keep, names(b))
  if (length(missing_terms) > 0)
    stop("Cannot compute joint test; missing terms: ", paste(missing_terms, collapse = ", "))
  bb <- b[keep]
  VV <- V[keep, keep, drop = FALSE]
  stat <- tryCatch(as.numeric(t(bb) %*% solve(VV) %*% bb), error = function(e) NA_real_)
  df <- length(keep)
  data.frame(test = label, periods = paste(periods, collapse = ","),
    stat = stat, df = df, p = stats::pchisq(stat, df, lower.tail = FALSE),
    stringsAsFactors = FALSE)
}

load_spec_outcome <- function(con, spec_row, outcome, citation_stack_cutoff) {
  where <- if (outcome == "fwd_cits5") {
    sprintf("p.stack <= %d AND p.fwd_cits5 IS NOT NULL", citation_stack_cutoff)
  } else {
    sprintf("p.%s IS NOT NULL", outcome)
  }
  dbGetQuery(con, sprintf("
    SELECT
      CAST(p.%s AS DOUBLE) AS y,
      CAST(p.event_time AS INTEGER) AS event_time,
      CAST(p.treated AS INTEGER) AS treated,
      CAST(p.stack AS INTEGER) AS stack,
      p.uid_stack,
      p.cluster_entity,
      CAST(p.codinv AS DOUBLE) AS codinv,
      CAST(w.final_weight AS DOUBLE) AS final_weight,
      CAST(p.n_patents_for_cites AS BIGINT) AS n_patents_for_cites,
      CAST(p.n_patents_missing_fwd_cits5 AS BIGINT) AS n_patents_missing_fwd_cits5
    FROM read_parquet('%s') p
    JOIN read_parquet('%s') w
      ON CAST(p.codinv AS BIGINT) = CAST(w.codinv AS BIGINT)
     AND CAST(p.stack AS INTEGER) = CAST(w.stack AS INTEGER)
    WHERE %s
    ORDER BY p.stack, p.treated, p.codinv, p.event_time",
    outcome, sql_path(spec_row$panel_path), sql_path(spec_row$weight_path), where))
}

sample_audit <- function(dat, outcome, spec, spec_label) {
  data.frame(
    outcome = outcome, spec = spec, spec_label = spec_label,
    n_rows = nrow(dat),
    n_units = length(unique(paste(dat$codinv, dat$stack))),
    n_stacks = length(unique(dat$stack)),
    min_stack = min(dat$stack),
    max_stack = max(dat$stack),
    n_cluster_entities = length(unique(dat$cluster_entity)),
    n_codinv_clusters = length(unique(dat$codinv)),
    treated_rows = sum(dat$treated == 1L),
    control_rows = sum(dat$treated == 0L),
    treated_weighted_mass = sum(dat$final_weight[dat$treated == 1L]),
    control_weighted_mass = sum(dat$final_weight[dat$treated == 0L]),
    stringsAsFactors = FALSE
  )
}

run_models <- function(dat, outcome, spec, spec_label) {
  if (any(!is.finite(dat$final_weight)) || any(dat$final_weight <= 0))
    stop("Bad weights in estimation sample for ", spec, " / ", outcome)
  if (any(is.na(dat$cluster_entity)) || any(is.na(dat$codinv)))
    stop("Missing clustering variables for ", spec, " / ", outcome)
  fml <- stats::as.formula("y ~ i(event_time, treated, ref = -1) | stack^event_time + uid_stack")
  variants <- list(
    weighted_twoway = list(weights = TRUE, cluster = ~ cluster_entity + codinv,
      cluster_label = "cluster_entity + codinv"),
    unweighted_twoway = list(weights = FALSE, cluster = ~ cluster_entity + codinv,
      cluster_label = "cluster_entity + codinv"),
    weighted_oneway = list(weights = TRUE, cluster = ~ cluster_entity,
      cluster_label = "cluster_entity")
  )
  out <- list()
  for (variant in names(variants)) {
    section(sprintf("Estimating %s | %s | %s", spec, outcome, variant))
    v <- variants[[variant]]
    mod <- if (v$weights) {
      fixest::feols(fml, data = dat, weights = ~ final_weight,
        cluster = v$cluster, fixef.rm = "none", notes = FALSE)
    } else {
      fixest::feols(fml, data = dat, cluster = v$cluster,
        fixef.rm = "none", notes = FALSE)
    }
    if (stats::nobs(mod) != nrow(dat))
      stop("Model sample changed for ", spec, " / ", outcome, " / ", variant)
    dyn <- extract_dynamic(mod, outcome, spec, variant, v$cluster_label, spec_label)
    post <- rbind(
      linear_combo(mod, POST_PERIODS_11L, length(POST_PERIODS_11L), "average_annual_t1_to_t5"),
      linear_combo(mod, POST_PERIODS_11L, 1, "cumulative_t1_to_t5")
    )
    post <- cbind(outcome = outcome, spec = spec, spec_label = spec_label,
      variant = variant, cluster = v$cluster_label, post)
    tests <- rbind(
      joint_wald(mod, PRE_PERIODS_11L, "joint_pretrend_tminus5_to_tminus2"),
      joint_wald(mod, POST_PERIODS_11L, "joint_post_t1_to_t5")
    )
    tests <- cbind(outcome = outcome, spec = spec, spec_label = spec_label,
      variant = variant, cluster = v$cluster_label, tests)
    out[[variant]] <- list(model = mod, dynamic = dyn, post = post, tests = tests)
  }
  out
}

plot_event <- function(df, specs_keep, file_name, title) {
  d <- df[df$variant == "weighted_twoway" & df$spec %in% specs_keep, ]
  d$outcome_lab <- factor(OUTCOME_LABS[d$outcome], levels = OUTCOME_LABS[OUTCOMES])
  d$spec_label <- factor(d$spec_label, levels = specs$label[match(specs_keep, specs$spec)])
  cols <- stats::setNames(specs$color[match(specs_keep, specs$spec)],
                          specs$label[match(specs_keep, specs$spec)])
  fig <- ggplot(d, aes(event_time, estimate, colour = spec_label)) +
    geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.35) +
    geom_vline(xintercept = REFERENCE_11L, colour = "grey35", linewidth = 0.45) +
    geom_vline(xintercept = 0, colour = "grey55", linewidth = 0.45, linetype = 2) +
    geom_errorbar(aes(ymin = ci_low, ymax = ci_high), width = 0.12,
      position = position_dodge(width = 0.35), linewidth = 0.35, na.rm = TRUE) +
    geom_point(position = position_dodge(width = 0.35), size = 1.2) +
    geom_line(aes(group = spec_label), linewidth = 0.55) +
    facet_wrap(~ outcome_lab, ncol = 1, scales = "free_y") +
    scale_x_continuous(breaks = EVENT_WINDOW_11L) +
    scale_colour_manual(values = cols, name = NULL) +
    labs(x = "Event time", y = "ATT", title = title,
      subtitle = "Delta = 0. Solid vertical line: t = -1 reference. Dashed line: t = 0 partial exposure.",
      caption = "95% CIs use two-way clustering by treatment/control entity and inventor.") +
    theme_minimal(base_size = 9) +
    theme(panel.grid.minor = element_blank(), strip.text = element_text(face = "bold"),
      plot.title = element_text(face = "bold"), legend.position = "bottom",
      plot.caption = element_text(colour = "#4B5563", size = 7))
  path <- file.path(FIGS_DIR, file_name)
  ggsave(path, fig, width = 9, height = 8.5, dpi = 300, bg = "white")
  path
}

plot_forest <- function(post_df) {
  d <- post_df[post_df$variant == "weighted_twoway" &
                 post_df$summary == "average_annual_t1_to_t5", ]
  d$outcome_lab <- factor(OUTCOME_LABS[d$outcome], levels = OUTCOME_LABS[OUTCOMES])
  d$spec_label <- factor(d$spec_label, levels = specs$label)
  cols <- stats::setNames(specs$color, specs$label)
  fig <- ggplot(d, aes(estimate, spec_label, colour = spec_label)) +
    geom_vline(xintercept = 0, colour = "grey55", linewidth = 0.35) +
    geom_errorbarh(aes(xmin = ci_low, xmax = ci_high), height = 0.18, linewidth = 0.45) +
    geom_point(size = 1.6) +
    facet_wrap(~ outcome_lab, scales = "free_x") +
    scale_colour_manual(values = cols, guide = "none") +
    labs(x = "Average annual effect, t = 1..5", y = NULL,
      title = "Robustness of five-year post effects",
      caption = "Each estimate is the exact average of displayed event-study coefficients; SEs use a'Va.") +
    theme_minimal(base_size = 9) +
    theme(panel.grid.minor = element_blank(), strip.text = element_text(face = "bold"),
      plot.title = element_text(face = "bold"), plot.caption = element_text(colour = "#4B5563", size = 7))
  path <- file.path(FIGS_DIR, "robustness_post_effects_forest.png")
  ggsave(path, fig, width = 9, height = 5.8, dpi = 300, bg = "white")
  path
}

banner("11l ROBUSTNESS EVENT STUDIES")

for (p in unique(c(specs$panel_path, specs$weight_path)))
  if (!file.exists(p)) stop("Missing input parquet: ", p)

citation_cutoff <- utils::read.csv(file.path(AUDIT_DIR, "main_robustness_citation_followup_cutoff.csv"),
  stringsAsFactors = FALSE)
citation_stack_cutoff <- citation_cutoff$stack_cutoff_for_full_t_plus_5_followup[1]
citation_balance_path <- file.path(RESULTS_DIR, "main_robustness_citation_restricted_balance.csv")
if (!file.exists(citation_balance_path))
  stop("Missing restricted citation balance diagnostics: ", citation_balance_path)
citation_balance <- utils::read.csv(citation_balance_path, stringsAsFactors = FALSE)
citation_status <- aggregate(abs_smd_weighted ~ spec + citation_balance_status,
  citation_balance, max)
names(citation_status)[names(citation_status) == "abs_smd_weighted"] <- "citation_restricted_max_abs_smd"

con <- dbConnect(duckdb::duckdb(), DUCKDB, read_only = TRUE)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, "PRAGMA memory_limit='10GB'")
dbExecute(con, "PRAGMA threads=4")
dbExecute(con, sprintf("PRAGMA temp_directory='%s'", sql_path(DUCKDB_TMP)))

dynamic_all <- list()
post_all <- list()
tests_all <- list()
sample_all <- list()
model_sample_all <- list()

for (i in seq_len(nrow(specs))) {
  spec_row <- specs[i, ]
  for (outcome in OUTCOMES) {
    banner(sprintf("%s / %s", spec_row$spec, outcome))
    dat <- load_spec_outcome(con, spec_row, outcome, citation_stack_cutoff)
    if (nrow(dat) == 0) stop("No estimation rows for ", spec_row$spec, " / ", outcome)
    sample_all[[paste(spec_row$spec, outcome)]] <- sample_audit(dat, outcome, spec_row$spec, spec_row$label)
    models <- run_models(dat, outcome, spec_row$spec, spec_row$label)
    dynamic_all[[paste(spec_row$spec, outcome)]] <- do.call(rbind, lapply(models, `[[`, "dynamic"))
    post_all[[paste(spec_row$spec, outcome)]] <- do.call(rbind, lapply(models, `[[`, "post"))
    tests_all[[paste(spec_row$spec, outcome)]] <- do.call(rbind, lapply(models, `[[`, "tests"))
    model_sample_all[[paste(spec_row$spec, outcome)]] <- data.frame(
      outcome = outcome, spec = spec_row$spec, spec_label = spec_row$label,
      variant = names(models), identical_input_sample = TRUE,
      n_input_rows = nrow(dat),
      n_model_rows = vapply(models, function(x) stats::nobs(x$model), integer(1)),
      n_units = length(unique(paste(dat$codinv, dat$stack))),
      n_stacks = length(unique(dat$stack)),
      n_cluster_entities = length(unique(dat$cluster_entity)),
      n_codinv_clusters = length(unique(dat$codinv)),
      stringsAsFactors = FALSE
    )
    rm(dat, models)
    gc()
  }
}

dynamic_df <- do.call(rbind, dynamic_all)
post_df <- do.call(rbind, post_all)
tests_df <- do.call(rbind, tests_all)
sample_df <- do.call(rbind, sample_all)
model_sample_df <- do.call(rbind, model_sample_all)

post_df$interpretation <- ifelse(
  post_df$outcome == "active_patenting" & post_df$summary == "cumulative_t1_to_t5",
  "change in expected active-patenting years",
  ifelse(post_df$summary == "average_annual_t1_to_t5",
         "average annual post effect", "cumulative five-year effect")
)

add_citation_status <- function(df) {
  df$citation_balance_status <- ""
  df$citation_restricted_max_abs_smd <- NA_real_
  idx <- df$outcome == "fwd_cits5"
  if (any(idx)) {
    m <- match(df$spec[idx], citation_status$spec)
    df[idx, "citation_balance_status"] <- citation_status$citation_balance_status[m]
    df[idx, "citation_restricted_max_abs_smd"] <- citation_status$citation_restricted_max_abs_smd[m]
  }
  df
}

dynamic_df <- add_citation_status(dynamic_df)
post_df <- add_citation_status(post_df)
tests_df <- add_citation_status(tests_df)
sample_df <- add_citation_status(sample_df)

write_result(dynamic_df, "main_robustness_event_study_dynamic.csv")
write_result(tests_df[tests_df$test == "joint_pretrend_tminus5_to_tminus2", ],
             "main_robustness_joint_pretrends.csv")
write_result(post_df, "main_robustness_post_summaries.csv")
write_audit(model_sample_df, "main_robustness_model_sample_audit.csv")
write_audit(sample_df, "main_robustness_weight_and_cluster_audit.csv")
write_result(tests_df, "main_robustness_joint_tests.csv")

primary_path <- plot_event(dynamic_df, "P0H5", "main_event_study_p0h5.png",
  "Corrected primary never-target event study")
nt_cmp <- plot_event(dynamic_df, c("P0H5", "P5"), "robustness_event_study_p0h5_vs_p5.png",
  "Never-target estimand comparison")
dw_cmp <- plot_event(dynamic_df, c("P5", "P4"), "robustness_event_study_p5_vs_p4.png",
  "Deal-weighted donor-pool comparison")
forest <- plot_forest(post_df)

figure_manifest <- data.frame(
  figure = c("main_event_study_p0h5", "robustness_event_study_p0h5_vs_p5",
             "robustness_event_study_p5_vs_p4", "robustness_post_effects_forest"),
  path = c(primary_path, nt_cmp, dw_cmp, forest),
  source_csv = file.path(RESULTS_DIR, "main_robustness_event_study_dynamic.csv"),
  stringsAsFactors = FALSE
)
write_result(figure_manifest, "main_robustness_figure_manifest.csv")

banner("11l DONE")
message("Results: ", RESULTS_DIR)
message("Figures: ", FIGS_DIR)
