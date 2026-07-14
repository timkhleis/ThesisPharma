# ============================================================================
# 11e_estimate_main_results.R -- Main DiD v1: never-target event study
# ----------------------------------------------------------------------------
# Delta=0 only. Dynamic effects are the primary results; post summaries are
# exact linear combinations of the displayed event-study coefficients.
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "11a_main_design_config.R"))
source(file.path(BASE, "R", "11_main_design_utils.R"))

for (pkg in c("DBI", "duckdb", "fixest", "ggplot2"))
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
suppressMessages({ library(DBI); library(duckdb); library(fixest); library(ggplot2) })

EVENT_WINDOW_11E <- -5L:5L
PRE_PERIODS_11E <- -5L:-2L
POST_PERIODS_11E <- 1L:5L
REFERENCE_11E <- -1L
EXPECTED_EVENT_TIMES <- setdiff(EVENT_WINDOW_11E, REFERENCE_11E)
PANEL_PARQUET_11E <- file.path(DERIVED_PAR, "main_did_v1_panel.parquet")

sql_path <- function(path) gsub("\\\\", "/", path)
term_for <- function(periods) sprintf("event_time::%d:treated", periods)

vcov_matrix <- function(mod) {
  V <- stats::vcov(mod)
  if (is.null(dim(V))) stop("Model returned no covariance matrix.")
  V
}

extract_dynamic <- function(mod, outcome, spec, cluster_label) {
  b <- stats::coef(mod)
  V <- vcov_matrix(mod)
  expected_terms <- term_for(EXPECTED_EVENT_TIMES)
  missing_terms <- setdiff(expected_terms, names(b))
  if (length(missing_terms) > 0) {
    stop("Missing expected event-study coefficients for ", outcome, " / ", spec, ": ",
         paste(missing_terms, collapse = ", "))
  }
  rows <- lapply(EVENT_WINDOW_11E, function(e) {
    if (e == REFERENCE_11E) {
      data.frame(outcome = outcome, spec = spec, cluster = cluster_label,
                 event_time = e, att = 0, se = NA_real_,
                 ci_low = NA_real_, ci_high = NA_real_,
                 reference_period = TRUE)
    } else {
      tm <- term_for(e)
      se <- sqrt(V[tm, tm])
      est <- b[[tm]]
      data.frame(outcome = outcome, spec = spec, cluster = cluster_label,
                 event_time = e, att = est, se = se,
                 ci_low = est - 1.96 * se, ci_high = est + 1.96 * se,
                 reference_period = FALSE)
    }
  })
  do.call(rbind, rows)
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
             periods = paste(periods, collapse = ","))
}

joint_wald <- function(mod, periods) {
  b <- stats::coef(mod)
  V <- vcov_matrix(mod)
  keep <- term_for(periods)
  missing_terms <- setdiff(keep, names(b))
  if (length(missing_terms) > 0)
    stop("Cannot compute joint pretrend; missing terms: ", paste(missing_terms, collapse = ", "))
  bb <- b[keep]
  VV <- V[keep, keep, drop = FALSE]
  stat <- tryCatch(as.numeric(t(bb) %*% solve(VV) %*% bb), error = function(e) NA_real_)
  df <- length(keep)
  data.frame(periods = paste(periods, collapse = ","), stat = stat, df = df,
             p = stats::pchisq(stat, df, lower.tail = FALSE))
}

sample_audit <- function(con, outcome, sample_where, panel_pq) {
  dbGetQuery(con, sprintf("
    SELECT
      '%s' AS outcome,
      COUNT(*) AS n_rows,
      COUNT(DISTINCT CAST(codinv AS VARCHAR) || '|' || CAST(stack AS VARCHAR)) AS n_units,
      COUNT(DISTINCT stack) AS n_stacks,
      MIN(stack) AS min_stack,
      MAX(stack) AS max_stack,
      COUNT(DISTINCT cluster_entity) AS n_cluster_entities,
      COUNT(DISTINCT codinv) AS n_codinv_clusters,
      SUM(CASE WHEN treated = 1 THEN 1 ELSE 0 END) AS n_treated_rows,
      SUM(CASE WHEN treated = 0 THEN 1 ELSE 0 END) AS n_control_rows,
      SUM(CASE WHEN treated = 1 THEN final_weight ELSE 0 END) AS treated_weighted_rows,
      SUM(CASE WHEN treated = 0 THEN final_weight ELSE 0 END) AS control_weighted_rows
    FROM read_parquet('%s')
    WHERE %s", outcome, panel_pq, sample_where))
}

load_outcome_sample <- function(con, outcome, panel_pq) {
  if (outcome == "fwd_cits5") {
    where <- "fwd_cits5_stack_sample = TRUE AND fwd_cits5 IS NOT NULL"
  } else {
    where <- sprintf("%s IS NOT NULL", outcome)
  }
  dat <- dbGetQuery(con, sprintf("
    SELECT
      CAST(%s AS DOUBLE) AS y,
      CAST(event_time AS INTEGER) AS event_time,
      CAST(treated AS INTEGER) AS treated,
      CAST(stack AS INTEGER) AS stack,
      uid_stack,
      cluster_entity,
      CAST(codinv AS DOUBLE) AS codinv,
      CAST(final_weight AS DOUBLE) AS final_weight
    FROM read_parquet('%s')
    WHERE %s
    ORDER BY stack, treated, codinv, event_time", outcome, panel_pq, where))
  list(data = dat, where = where)
}

run_models <- function(dat, outcome) {
  fml <- stats::as.formula("y ~ i(event_time, treated, ref = -1) | stack^event_time + uid_stack")
  specs <- list(
    weighted_twoway = list(weights = TRUE, cluster = ~ cluster_entity + codinv,
                           cluster_label = "cluster_entity + codinv"),
    unweighted_twoway = list(weights = FALSE, cluster = ~ cluster_entity + codinv,
                             cluster_label = "cluster_entity + codinv"),
    weighted_oneway = list(weights = TRUE, cluster = ~ cluster_entity,
                           cluster_label = "cluster_entity")
  )
  out <- list()
  for (nm in names(specs)) {
    section(sprintf("Estimating %s | %s", outcome, nm))
    s <- specs[[nm]]
    if (s$weights) {
      mod <- fixest::feols(fml, data = dat, weights = ~ final_weight,
                           cluster = s$cluster, fixef.rm = "none", notes = FALSE)
    } else {
      mod <- fixest::feols(fml, data = dat, cluster = s$cluster,
                           fixef.rm = "none", notes = FALSE)
    }
    if (stats::nobs(mod) != nrow(dat)) {
      stop("Model sample changed for ", outcome, " / ", nm,
           ": nobs=", stats::nobs(mod), " vs input rows=", nrow(dat))
    }
    dyn <- extract_dynamic(mod, outcome, nm, s$cluster_label)
    avg <- linear_combo(mod, POST_PERIODS_11E, length(POST_PERIODS_11E), "average_annual_t1_to_t5")
    cum <- linear_combo(mod, POST_PERIODS_11E, 1, "cumulative_t1_to_t5")
    post <- cbind(outcome = outcome, spec = nm, cluster = s$cluster_label, rbind(avg, cum))
    pre <- cbind(outcome = outcome, spec = nm, cluster = s$cluster_label,
                 joint_wald(mod, PRE_PERIODS_11E))
    out[[nm]] <- list(model = mod, dynamic = dyn, post = post, pretrend = pre)
  }
  out
}

banner("11e NEVER-TARGET EVENT STUDY (delta = 0 only)")

if (!file.exists(PANEL_PARQUET_11E)) stop("Missing panel parquet. Run 11d first: ", PANEL_PARQUET_11E)

con <- dbConnect(duckdb::duckdb(), DUCKDB, read_only = TRUE)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, "PRAGMA memory_limit='10GB'")
dbExecute(con, "PRAGMA threads=4")
dbExecute(con, sprintf("PRAGMA temp_directory='%s'", sql_path(DUCKDB_TMP)))

panel_pq <- sql_path(PANEL_PARQUET_11E)

panel_check <- dbGetQuery(con, sprintf("
  SELECT COUNT(*) AS n_rows,
         COUNT(DISTINCT CAST(codinv AS VARCHAR) || '|' || CAST(stack AS VARCHAR)) AS n_units,
         MIN(event_time) AS min_event_time, MAX(event_time) AS max_event_time
  FROM read_parquet('%s')", panel_pq))
write_audit(panel_check, "main_results_panel_input_check.csv")
print(panel_check)
if (panel_check$min_event_time != min(EVENT_WINDOW_11E) ||
    panel_check$max_event_time != max(EVENT_WINDOW_11E))
  stop("Panel event window is not [-5,+5].")

dynamic_all <- list()
post_all <- list()
pretrend_all <- list()
sample_all <- list()
model_sample_all <- list()

for (outcome in OUTCOMES) {
  banner(sprintf("Outcome: %s", outcome))
  loaded <- load_outcome_sample(con, outcome, panel_pq)
  dat <- loaded$data
  if (nrow(dat) == 0) stop("No estimation rows for outcome: ", outcome)
  if (any(!is.finite(dat$final_weight)) || any(dat$final_weight <= 0))
    stop("Bad weights in estimation data for ", outcome)
  if (any(is.na(dat$cluster_entity)) || any(is.na(dat$codinv)))
    stop("Missing cluster variables in estimation data for ", outcome)
  sample_all[[outcome]] <- sample_audit(con, outcome, loaded$where, panel_pq)
  model_specs <- run_models(dat, outcome)
  dynamic_all[[outcome]] <- do.call(rbind, lapply(model_specs, `[[`, "dynamic"))
  post_all[[outcome]] <- do.call(rbind, lapply(model_specs, `[[`, "post"))
  pretrend_all[[outcome]] <- do.call(rbind, lapply(model_specs, `[[`, "pretrend"))
  model_sample_all[[outcome]] <- data.frame(
    outcome = outcome,
    spec = c("weighted_twoway", "unweighted_twoway", "weighted_oneway"),
    same_input_sample = TRUE,
    n_input_rows = nrow(dat),
    n_model_rows = vapply(model_specs, function(x) stats::nobs(x$model), integer(1)),
    n_units = length(unique(paste(dat$codinv, dat$stack))),
    n_stacks = length(unique(dat$stack)),
    n_cluster_entities = length(unique(dat$cluster_entity)),
    n_codinv_clusters = length(unique(dat$codinv))
  )
  rm(dat, loaded, model_specs)
  gc()
}

dynamic_df <- do.call(rbind, dynamic_all)
post_df <- do.call(rbind, post_all)
pretrend_df <- do.call(rbind, pretrend_all)
sample_df <- do.call(rbind, sample_all)
model_sample_df <- do.call(rbind, model_sample_all)

post_df$interpretation <- ifelse(
  post_df$outcome == "active_patenting" & post_df$summary == "cumulative_t1_to_t5",
  "change in expected active-patenting years",
  ifelse(post_df$summary == "average_annual_t1_to_t5", "average annual post effect", "cumulative five-year effect")
)

write_result(dynamic_df, "main_event_study_dynamic.csv")
write_result(pretrend_df, "main_event_study_joint_pretrend.csv")
write_result(post_df, "main_event_study_post_summaries.csv")
write_audit(sample_df, "main_results_outcome_sample_audit.csv")
write_audit(model_sample_df, "main_results_model_sample_audit.csv")

primary_dyn <- dynamic_df[dynamic_df$spec == "weighted_twoway", ]
primary_dyn$outcome_lab <- factor(OUTCOME_LABS[primary_dyn$outcome], levels = OUTCOME_LABS[OUTCOMES])

banner("Writing event-study figure")
fig <- ggplot(primary_dyn, aes(event_time, att)) +
  geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.35) +
  geom_vline(xintercept = REFERENCE_11E, colour = "grey35", linewidth = 0.45) +
  geom_vline(xintercept = 0, colour = "grey55", linewidth = 0.45, linetype = 2) +
  geom_ribbon(aes(ymin = ci_low, ymax = ci_high), fill = "#90BE6D", alpha = 0.18, na.rm = TRUE) +
  geom_line(colour = "#1B4332", linewidth = 0.65) +
  geom_point(colour = "#1B4332", size = 1.25) +
  facet_wrap(~ outcome_lab, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = EVENT_WINDOW_11E) +
  labs(
    x = "Event time relative to acquisition / placebo year",
    y = "ATT",
    title = "Never-target inventor-weighted event study",
    subtitle = "Delta = 0 only. Solid vertical line: t = -1 reference. Dashed line: t = 0 partial-exposure year.",
    caption = "95% CIs use two-way clustering by hybrid deal/firm entity and inventor; entropy-balancing weights are held fixed."
  ) +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(),
        strip.text = element_text(face = "bold"),
        plot.title = element_text(face = "bold", colour = "#1B4332"),
        plot.subtitle = element_text(colour = "#4B5563", size = 8),
        plot.caption = element_text(colour = "#4B5563", size = 7),
        plot.background = element_rect(fill = "white", colour = NA))

fig_path <- file.path(FIGS_DIR, "main_event_study_never_target_delta0.png")
ggsave(fig_path, fig, width = 8.5, height = 8.5, dpi = 300, bg = "white")
message("Figure: ", fig_path)

banner("11e DONE")
message("Results: ", RESULTS_DIR)
message("Figure:  ", fig_path)
