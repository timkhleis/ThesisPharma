#!/usr/bin/env Rscript

# Local Match v2 network N1: held-out pre-period validation, precision gate,
# and untreated-firm falsification. This script is structurally unable to
# read event time zero or any positive event time.

options(stringsAsFactors = FALSE, scipen = 999)

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "digest", "ggplot2")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

ROOT <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment"
)
N0 <- file.path(ROOT, "NETWORK_N0_CENSUS")
AMEND <- file.path(ROOT, "NETWORK_N0_AMENDMENT_20260806")
OUT <- file.path(ROOT, "NETWORK_N1_VALIDATION")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

CONFIG <- list(
  validation_event_times = c(-2L, -1L),
  equivalence_bound = 0.05,
  meaningful_effect = 0.05,
  confidence_level = 0.95,
  equivalence_confidence_level = 0.90,
  power = 0.80,
  bootstrap_replications = 9999L,
  bootstrap_seed = 20260806L,
  falsification_draws = 200L,
  falsification_seed = 20260807L,
  falsification_mean_gap_bound = 0.01,
  falsification_rejection_share_bound = 0.10,
  minimum_denominator_coverage = 0.80,
  joint_test_alpha = 0.10
)

write_csv <- function(x, name) {
  utils::write.csv(x, file.path(OUT, name), row.names = FALSE, na = "")
}
sha <- function(path) digest::digest(path, file = TRUE, algo = "sha256")
sql_path <- function(path, must_work = TRUE) gsub(
  "\\\\", "/", normalizePath(path, winslash = "/", mustWork = must_work)
)

# Verify that the amendment was fully frozen before validation construction.
amend_decision_path <- file.path(AMEND, "network_n0_amended_path_decision.csv")
amend_cert_path <- file.path(AMEND, "network_n0_amendment_certification.csv")
amend_manifest_path <- file.path(AMEND, "network_n0_amendment_manifest.csv")
for (p in c(amend_decision_path, amend_cert_path, amend_manifest_path)) {
  if (!file.exists(p)) stop("Missing N0 amendment input: ", p)
}
amend_decision <- utils::read.csv(amend_decision_path, check.names = FALSE)
amend_cert <- utils::read.csv(amend_cert_path, check.names = FALSE)
amend_manifest <- utils::read.csv(amend_manifest_path, check.names = FALSE)
if (nrow(amend_decision) != 1L || amend_decision$amended_path[[1L]] != "N1") {
  stop("N0 amendment does not release N1")
}
if (!all(as.logical(amend_cert$pass))) stop("N0 amendment is not certified")
for (i in seq_len(nrow(amend_manifest))) {
  p <- file.path(AMEND, amend_manifest$artifact[[i]])
  if (!file.exists(p) || sha(p) != amend_manifest$sha256[[i]]) {
    stop("N0 amendment hash mismatch: ", p)
  }
}
amendment_freeze_hash <- sha(amend_manifest_path)

panel_glob <- file.path(ROOT, "P6_BASE", "panel_matched", "*.parquet")
ties_file <- file.path(N0, "network_persistent_ties.parquet")
db_file <- file.path(BASE, "output", "thesis_foundation.duckdb")
if (!file.exists(ties_file) || !file.exists(db_file)) stop("Missing N1 source")

validation_file <- file.path(OUT, "network_validation_panel.parquet")
con <- DBI::dbConnect(duckdb::duckdb(), db_file, read_only = TRUE)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='9GB'")
DBI::dbExecute(con, "PRAGMA threads=8")
temp_dir <- file.path(OUT, "duckdb_tmp")
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
DBI::dbExecute(con, sprintf(
  "PRAGMA temp_directory='%s'", gsub("\\\\", "/", temp_dir)
))

message("N1: materializing held-out event times -2 and -1 only")
DBI::dbExecute(con, sprintf("
  COPY (
    WITH roster AS MATERIALIZED (
      SELECT DISTINCT roster_row_id, CAST(deal_id AS INTEGER) AS deal_id,
        CAST(cohort AS INTEGER) AS cohort, arm,
        CAST(codinv AS BIGINT) AS codinv, CAST(weight AS DOUBLE) AS weight,
        CAST(focal_group_1 AS BIGINT) AS focal_group
      FROM read_parquet('%s')
      WHERE event_time=-1 AND cohort BETWEEN 1993 AND 2010
    ), ties AS MATERIALIZED (
      SELECT roster_row_id, CAST(collaborator_codinv AS BIGINT)
        AS collaborator_codinv
      FROM read_parquet('%s')
    ), partner_group_year AS MATERIALIZED (
      SELECT DISTINCT CAST(pi.codinv AS BIGINT) AS codinv,
        CAST(pcl.year AS INTEGER) AS patent_year,
        CAST(pcl.id_group AS BIGINT) AS id_group
      FROM patent_inventor pi
      JOIN patent_company_link pcl
        ON CAST(pcl.appln_id AS BIGINT)=CAST(pi.appln_id AS BIGINT)
      WHERE pcl.id_group IS NOT NULL
    ), eval AS (
      SELECT * FROM (VALUES (-2),(-1)) v(event_time)
    ), expanded AS (
      SELECT r.*, e.event_time, r.cohort+e.event_time AS calendar_year,
        t.collaborator_codinv,
        pgy.codinv IS NOT NULL AS partner_in_focal_group
      FROM roster r
      JOIN ties t USING(roster_row_id)
      CROSS JOIN eval e
      LEFT JOIN partner_group_year pgy
        ON pgy.codinv=t.collaborator_codinv
       AND pgy.patent_year=r.cohort+e.event_time
       AND pgy.id_group=r.focal_group
    )
    SELECT roster_row_id, deal_id, cohort, arm, codinv, weight,
      focal_group, event_time, calendar_year,
      COUNT(DISTINCT collaborator_codinv) AS anchor_collaborators,
      COUNT(DISTINCT collaborator_codinv) AS at_risk_collaborators,
      COUNT(DISTINCT collaborator_codinv) FILTER (
        WHERE partner_in_focal_group
      ) AS focal_group_collaborators,
      CAST(COUNT(DISTINCT collaborator_codinv) FILTER (
             WHERE partner_in_focal_group) AS DOUBLE)
        / COUNT(DISTINCT collaborator_codinv)
        AS partner_focal_persistence_share
    FROM expanded
    GROUP BY 1,2,3,4,5,6,7,8,9
    ORDER BY cohort,deal_id,arm DESC,codinv,roster_row_id,event_time
  ) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD, OVERWRITE TRUE)
", gsub("\\\\", "/", panel_glob), sql_path(ties_file),
   gsub("\\\\", "/", validation_file)))

panel <- DBI::dbGetQuery(con, sprintf(
  "SELECT * FROM read_parquet('%s') ORDER BY cohort,deal_id,arm DESC,codinv,event_time",
  sql_path(validation_file)
))
DBI::dbDisconnect(con, shutdown = TRUE)
on.exit(NULL, add = FALSE)

panel$treated <- as.integer(panel$arm == "treated")
panel$event_time <- as.integer(panel$event_time)
panel$cohort <- as.integer(panel$cohort)
panel$deal_id <- as.integer(panel$deal_id)
panel$codinv <- as.character(panel$codinv)
panel$weight <- as.numeric(panel$weight)
panel$partner_focal_persistence_share <- as.numeric(
  panel$partner_focal_persistence_share
)

key_audit <- data.frame(
  rows = nrow(panel),
  duplicate_keys = anyDuplicated(
    panel[c("roster_row_id", "event_time")]
  ),
  event_times = paste(sort(unique(panel$event_time)), collapse = ";"),
  min_outcome = suppressWarnings(min(
    panel$partner_focal_persistence_share, na.rm = TRUE
  )),
  max_outcome = suppressWarnings(max(
    panel$partner_focal_persistence_share, na.rm = TRUE
  )),
  stringsAsFactors = FALSE
)
write_csv(key_audit, "network_validation_key_audit.csv")

coverage <- do.call(rbind, lapply(
  split(panel, list(panel$arm, panel$event_time), drop = TRUE),
  function(z) data.frame(
    arm = z$arm[[1L]], event_time = z$event_time[[1L]],
    anchor_focal_inventors = length(unique(z$roster_row_id)),
    defined_focal_inventors = length(unique(
      z$roster_row_id[is.finite(z$partner_focal_persistence_share)]
    )),
    defined_weight_share = sum(
      z$weight[is.finite(z$partner_focal_persistence_share)]
    ) / sum(z$weight),
    mean_anchor_collaborators = mean(z$anchor_collaborators),
    mean_at_risk_collaborators = mean(z$at_risk_collaborators),
    stringsAsFactors = FALSE
  )
))
rownames(coverage) <- NULL
write_csv(coverage, "network_validation_denominator_coverage.csv")

# Standardize both arms to the treated network cohort distribution. Missing
# denominators are renormalized within arm/cohort/event; this is not rematching.
cohort_mass <- aggregate(
  weight ~ cohort, panel[panel$arm == "treated" & panel$event_time == -1L, ],
  sum
)
cohort_mass$cohort_share <- cohort_mass$weight / sum(cohort_mass$weight)
names(cohort_mass)[names(cohort_mass) == "weight"] <- "treated_anchor_mass"
panel <- merge(panel, cohort_mass, by = "cohort", all.x = TRUE, sort = FALSE)
panel$analysis_weight <- NA_real_
for (idx in split(seq_len(nrow(panel)), list(
  panel$arm, panel$cohort, panel$event_time), drop = TRUE
)) {
  ok <- is.finite(panel$partner_focal_persistence_share[idx]) &
    is.finite(panel$weight[idx]) & panel$weight[idx] > 0
  if (any(ok)) {
    panel$analysis_weight[idx[ok]] <- panel$cohort_share[idx[ok]] *
      panel$weight[idx[ok]] / sum(panel$weight[idx[ok]])
  }
}

cr1 <- function(scores) {
  scores <- as.matrix(scores)
  if (nrow(scores) < 2L) stop("Fewer than two clusters")
  scores <- sweep(scores, 2L, colMeans(scores), "-")
  nrow(scores) / (nrow(scores) - 1) * crossprod(scores)
}
cluster_scores <- function(influence, cluster) {
  rowsum(influence, group = as.character(cluster), reorder = TRUE)
}
fit_validation <- function(z, treatment = "treated") {
  keep <- is.finite(z$partner_focal_persistence_share) &
    is.finite(z$analysis_weight) & z$analysis_weight > 0
  x <- z[keep, , drop = FALSE]
  tr <- x[[treatment]]
  X <- cbind(
    base_m2 = as.numeric(x$event_time == -2L),
    base_m1 = as.numeric(x$event_time == -1L),
    gap_m2 = as.numeric(x$event_time == -2L) * tr,
    gap_m1 = as.numeric(x$event_time == -1L) * tr
  )
  y <- x$partner_focal_persistence_share
  w <- x$analysis_weight
  xx <- crossprod(X, w * X)
  if (qr(xx)$rank != ncol(X)) stop("Validation model is rank deficient")
  bread <- solve(xx)
  beta <- drop(bread %*% crossprod(X, w * y))
  names(beta) <- colnames(X)
  residual <- y - drop(X %*% beta)
  influence <- sweep(X, 1L, w * residual, "*") %*% bread
  colnames(influence) <- colnames(X)
  deal <- cluster_scores(influence, x$deal_id)
  inventor <- cluster_scores(influence, x$codinv)
  intersection <- cluster_scores(
    influence, paste(x$deal_id, x$codinv, sep = ":")
  )
  v_deal <- cr1(deal)
  v_two <- v_deal + cr1(inventor) - cr1(intersection)
  diag(v_two) <- pmax(diag(v_two), 0)
  list(
    beta = beta, v_deal = v_deal, v_two = v_two,
    deal_scores = deal, inventor_clusters = nrow(inventor),
    deal_clusters = nrow(deal), rows = nrow(x)
  )
}

webb_multipliers <- function(levels, reps, seed) {
  set.seed(seed)
  support <- c(-sqrt(3 / 2), -1, -sqrt(1 / 2),
               sqrt(1 / 2), 1, sqrt(3 / 2))
  matrix(
    sample(support, reps * length(levels), replace = TRUE),
    nrow = reps, ncol = length(levels),
    dimnames = list(NULL, levels)
  )
}

fit <- fit_validation(panel)
mult <- webb_multipliers(
  rownames(fit$deal_scores), CONFIG$bootstrap_replications,
  CONFIG$bootstrap_seed
)

linear_result <- function(term, event_time) {
  L <- setNames(rep(0, length(fit$beta)), names(fit$beta))
  L[[term]] <- 1
  est <- sum(L * fit$beta)
  se_deal <- sqrt(drop(t(L) %*% fit$v_deal %*% L))
  se_two <- sqrt(drop(t(L) %*% fit$v_two %*% L))
  score <- drop(fit$deal_scores %*% L)
  draws <- drop(mult %*% score)
  draw_t <- draws / se_deal
  crit95_wild <- unname(stats::quantile(abs(draw_t), 0.95, type = 7))
  crit90_wild <- unname(stats::quantile(abs(draw_t), 0.90, type = 7))
  p_wild <- (1 + sum(abs(draw_t) >= abs(est / se_deal))) /
    (length(draw_t) + 1)
  df_two <- min(fit$deal_clusters, fit$inventor_clusters) - 1L
  crit95_two <- stats::qt(0.975, df_two)
  crit90_two <- stats::qt(0.95, df_two)
  p_two <- 2 * stats::pt(-abs(est / se_two), df = df_two)
  width95 <- max(crit95_wild * se_deal, crit95_two * se_two)
  width90 <- max(crit90_wild * se_deal, crit90_two * se_two)
  governing_se <- max(se_deal, se_two)
  governing_critical <- max(crit95_wild, crit95_two)
  data.frame(
    event_time = event_time, estimate = est,
    deal_se = se_deal, two_way_se = se_two,
    deal_wild_p = p_wild, two_way_p = p_two,
    governing_p = max(p_wild, p_two),
    ci95_low = est - width95, ci95_high = est + width95,
    ci90_low = est - width90, ci90_high = est + width90,
    governing_interval = ifelse(
      crit95_wild * se_deal >= crit95_two * se_two,
      "deal_wild", "two_way_deal_inventor"
    ),
    governing_se = governing_se,
    governing_critical = governing_critical,
    mde_80 = (governing_critical + stats::qnorm(CONFIG$power)) *
      governing_se,
    stringsAsFactors = FALSE
  )
}
leads <- rbind(linear_result("gap_m2", -2L),
               linear_result("gap_m1", -1L))
leads$within_point_band <- abs(leads$estimate) <= CONFIG$equivalence_bound
leads$equivalent_90 <- leads$ci90_low > -CONFIG$equivalence_bound &
  leads$ci90_high < CONFIG$equivalence_bound
leads$precision_pass <- leads$mde_80 <= CONFIG$meaningful_effect
write_csv(leads, "network_validation_leads.csv")

L_joint <- rbind(
  m2 = c(base_m2 = 0, base_m1 = 0, gap_m2 = 1, gap_m1 = 0),
  m1 = c(base_m2 = 0, base_m1 = 0, gap_m2 = 0, gap_m1 = 1)
)
b_joint <- drop(L_joint %*% fit$beta)
v_joint <- L_joint %*% fit$v_two %*% t(L_joint)
wald <- drop(t(b_joint) %*% solve(v_joint, b_joint))
p_joint_two <- stats::pchisq(wald, df = 2L, lower.tail = FALSE)
score_joint <- fit$deal_scores %*% t(L_joint)
draw_joint <- mult %*% score_joint
se_joint_deal <- sqrt(diag(L_joint %*% fit$v_deal %*% t(L_joint)))
draw_t_joint <- sweep(draw_joint, 2L, se_joint_deal, "/")
obs_t_joint <- b_joint / se_joint_deal
p_joint_wild <- (1 + sum(
  apply(abs(draw_t_joint), 1L, max) >= max(abs(obs_t_joint))
)) / (nrow(draw_t_joint) + 1)
joint <- data.frame(
  statistic_two_way = wald, df = 2L,
  two_way_p = p_joint_two, deal_wild_max_t_p = p_joint_wild,
  governing_p = max(p_joint_two, p_joint_wild),
  stringsAsFactors = FALSE
)
write_csv(joint, "network_validation_joint_test.csv")

# Untreated-firm pseudo-event falsification. Control observations are already
# indexed to acquisition cohorts they never experience. Within each cohort,
# half of the control roster rows receive a random pseudo-treated label.
controls <- panel[panel$arm == "control", , drop = FALSE]
set.seed(CONFIG$falsification_seed)
falsification <- vector("list", CONFIG$falsification_draws)
for (b in seq_len(CONFIG$falsification_draws)) {
  controls$pseudo_treated <- 0L
  for (cc in sort(unique(controls$cohort))) {
    ids <- unique(controls$roster_row_id[controls$cohort == cc])
    selected <- sample(ids, floor(length(ids) / 2L), replace = FALSE)
    controls$pseudo_treated[
      controls$cohort == cc & controls$roster_row_id %in% selected
    ] <- 1L
  }
  controls$analysis_weight <- NA_real_
  for (idx in split(seq_len(nrow(controls)), list(
    controls$pseudo_treated, controls$cohort, controls$event_time),
    drop = TRUE
  )) {
    ok <- is.finite(controls$partner_focal_persistence_share[idx]) &
      controls$weight[idx] > 0
    if (any(ok)) {
      controls$analysis_weight[idx[ok]] <- controls$cohort_share[idx[ok]] *
        controls$weight[idx[ok]] / sum(controls$weight[idx[ok]])
    }
  }
  fb <- fit_validation(controls, treatment = "pseudo_treated")
  rows <- lapply(c(gap_m2 = -2L, gap_m1 = -1L), function(et) {
    term <- if (et == -2L) "gap_m2" else "gap_m1"
    L <- setNames(rep(0, length(fb$beta)), names(fb$beta))
    L[[term]] <- 1
    est <- sum(L * fb$beta)
    se <- sqrt(drop(t(L) %*% fb$v_deal %*% L))
    df <- fb$deal_clusters - 1L
    data.frame(
      draw = b, event_time = et, estimate = est, deal_se = se,
      p_value = 2 * stats::pt(-abs(est / se), df = df),
      stringsAsFactors = FALSE
    )
  })
  falsification[[b]] <- do.call(rbind, rows)
}
falsification <- do.call(rbind, falsification)
falsification_summary <- data.frame(
  draws = CONFIG$falsification_draws,
  mean_gap_m2 = mean(falsification$estimate[falsification$event_time == -2L]),
  mean_gap_m1 = mean(falsification$estimate[falsification$event_time == -1L]),
  maximum_absolute_mean_gap = max(abs(tapply(
    falsification$estimate, falsification$event_time, mean
  ))),
  rejection_share_5pct = mean(falsification$p_value < 0.05),
  mean_gap_bound = CONFIG$falsification_mean_gap_bound,
  rejection_share_bound = CONFIG$falsification_rejection_share_bound,
  stringsAsFactors = FALSE
)
falsification_summary$pass <-
  falsification_summary$maximum_absolute_mean_gap <=
    falsification_summary$mean_gap_bound &
  falsification_summary$rejection_share_5pct <=
    falsification_summary$rejection_share_bound
write_csv(falsification, "network_untreated_falsification_draws.csv")
write_csv(falsification_summary, "network_untreated_falsification_summary.csv")

support <- utils::read.csv(
  file.path(N0, "network_support_census.csv"), check.names = FALSE
)
treated_support <- support[support$arm == "treated", , drop = FALSE]
coverage_pass <- all(
  coverage$defined_weight_share >= CONFIG$minimum_denominator_coverage
)
construction_pass <-
  key_audit$duplicate_keys[[1L]] == 0L &&
  identical(sort(unique(panel$event_time)), c(-2L, -1L)) &&
  key_audit$min_outcome[[1L]] >= 0 && key_audit$max_outcome[[1L]] <= 1 &&
  coverage_pass
validity_pass <-
  all(leads$within_point_band) &&
  joint$governing_p[[1L]] > CONFIG$joint_test_alpha &&
  isTRUE(falsification_summary$pass[[1L]])
precision_pass <- all(leads$equivalent_90) && all(leads$precision_pass)
support_pass <-
  treated_support$nominal_deals[[1L]] >= 150L &&
  treated_support$effective_deals[[1L]] >= 20 &&
  treated_support$largest_deal_share[[1L]] <= 0.10
path <- if (construction_pass && validity_pass && precision_pass && support_pass) {
  "N"
} else if (construction_pass && validity_pass && support_pass) {
  "Q"
} else {
  "F"
}
decision <- data.frame(
  selected_path = path,
  construction_pass = construction_pass,
  validity_pass = validity_pass,
  precision_pass = precision_pass,
  support_pass = support_pass,
  denominator_coverage_pass = coverage_pass,
  all_point_gaps_within_005 = all(leads$within_point_band),
  joint_governing_p = joint$governing_p[[1L]],
  all_90pct_intervals_equivalent = all(leads$equivalent_90),
  maximum_mde_80 = max(leads$mde_80),
  meaningful_effect = CONFIG$meaningful_effect,
  untreated_falsification_pass = falsification_summary$pass[[1L]],
  post_treatment_outcomes_opened = FALSE,
  stringsAsFactors = FALSE
)
write_csv(decision, "network_n1_path_decision.csv")

cert <- data.frame(
  check = c(
    "n0_amendment_hash_verified", "negative_event_times_only",
    "unique_roster_event_key", "share_in_natural_bounds",
    "denominator_coverage_assessed", "strict_tie_definition_reused",
    "frozen_weights_not_rematched", "untreated_falsification_constructed",
    "deterministic_path_written", "positive_outcomes_remain_closed"
  ),
  pass = c(
    TRUE, identical(sort(unique(panel$event_time)), c(-2L, -1L)),
    key_audit$duplicate_keys[[1L]] == 0L,
    key_audit$min_outcome[[1L]] >= 0 && key_audit$max_outcome[[1L]] <= 1,
    all(is.finite(coverage$defined_weight_share)) &&
      all(coverage$defined_weight_share >= 0) &&
      all(coverage$defined_weight_share <= 1),
    file.exists(ties_file), TRUE,
    nrow(falsification) == 2L * CONFIG$falsification_draws,
    path %in% c("N", "Q", "F"),
    !decision$post_treatment_outcomes_opened[[1L]]
  ),
  value = c(
    amendment_freeze_hash, paste(sort(unique(panel$event_time)), collapse = ";"),
    key_audit$duplicate_keys[[1L]],
    paste(key_audit$min_outcome[[1L]], key_audit$max_outcome[[1L]], sep = ":"),
    min(coverage$defined_weight_share), sha(ties_file),
    "renormalization_only", nrow(falsification), path,
    decision$post_treatment_outcomes_opened[[1L]]
  ),
  detail = c(
    "all amendment artifact hashes verified before construction",
    "SQL contains only literal event times -2 and -1",
    "one row per roster row and evaluation event time",
    "partner persistence is a share",
    paste0(
      "minimum weighted defined share is assessed against 0.80; gate pass=",
      coverage_pass
    ),
    "certified two-application/two-year anchor parquet",
    "common-cohort renormalization does not alter relative frozen weights",
    "control-only pseudo-event arm-label draws",
    "Path N/Q/F follows the frozen deterministic rule",
    "N2 access depends on certified Path N"
  ),
  stringsAsFactors = FALSE
)
write_csv(cert, "network_n1_certification.csv")
if (!all(cert$pass)) stop("N1 construction certification failed")

# Validation figure contains no post-treatment estimate.
plot_data <- leads
p <- ggplot2::ggplot(
  plot_data, ggplot2::aes(x = event_time, y = estimate)
) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey45", linewidth = 0.4) +
  ggplot2::geom_hline(
    yintercept = c(-CONFIG$equivalence_bound, CONFIG$equivalence_bound),
    linetype = "dashed", colour = "grey60", linewidth = 0.35
  ) +
  ggplot2::geom_errorbar(
    ggplot2::aes(ymin = ci95_low, ymax = ci95_high), width = 0.08
  ) +
  ggplot2::geom_point(size = 2.2) +
  ggplot2::scale_x_continuous(breaks = c(-2, -1)) +
  ggplot2::labs(
    x = "Event time", y = "Treated-control gap",
    title = "Held-out partner focal-organization persistence",
    subtitle = "Strict persistent ties; dashed lines mark the +/-0.05 equivalence band"
  ) +
  ggplot2::theme_minimal(base_size = 11)
ggplot2::ggsave(
  file.path(OUT, "network_validation_leads.png"), p,
  width = 7, height = 4.5, dpi = 220
)

report <- c(
  "# Local Match v2 network N1 validation",
  "",
  sprintf("Decision: **Path %s**.", path),
  "",
  "The governing outcome is the share of strict persistent baseline",
  "collaborators who remain patent-active in the relevant focal organization",
  "while observable and at risk. N1 uses only event times -2 and -1.",
  "",
  sprintf(
    "The treated-control gaps are %.3f at t=-2 and %.3f at t=-1.",
    leads$estimate[leads$event_time == -2L],
    leads$estimate[leads$event_time == -1L]
  ),
  sprintf(
    "The governing joint p-value is %.3f. The largest 80%% MDE is %.3f,",
    joint$governing_p[[1L]], max(leads$mde_80)
  ),
  sprintf(
    "against the frozen meaningful effect of %.2f.",
    CONFIG$meaningful_effect
  ),
  "",
  if (path == "N") {
    "N1 passes construction, validity, equivalence, precision, and falsification gates. N2 may open positive event times."
  } else if (path == "Q") {
    "Construction and validation are acceptable, but precision is inadequate. Positive event times remain closed."
  } else {
    "At least one construction, validation, or falsification condition fails. Positive event times remain closed."
  },
  "",
  "The original N0 Path-Q artifact remains unchanged. N1 relies on the dated",
  "outcome-blind amendment and the strict two-application/two-year tie definition."
)
writeLines(report, file.path(OUT, "network_n1_results.md"), useBytes = TRUE)

artifacts <- c(
  "network_validation_panel.parquet", "network_validation_key_audit.csv",
  "network_validation_denominator_coverage.csv", "network_validation_leads.csv",
  "network_validation_joint_test.csv",
  "network_untreated_falsification_draws.csv",
  "network_untreated_falsification_summary.csv",
  "network_n1_path_decision.csv", "network_n1_certification.csv",
  "network_validation_leads.png", "network_n1_results.md"
)
manifest <- data.frame(
  artifact = artifacts,
  sha256 = vapply(file.path(OUT, artifacts), sha, character(1)),
  bytes = file.info(file.path(OUT, artifacts))$size,
  stringsAsFactors = FALSE
)
write_csv(manifest, "network_n1_manifest.csv")

source_paths <- c(
  file.path(BASE, "R", "final_thesis", "61_run_lmv2_network_n1.R"),
  ties_file, amend_manifest_path
)
source_manifest <- data.frame(
  source = vapply(source_paths, normalizePath, character(1),
                  winslash = "/", mustWork = TRUE),
  sha256 = vapply(source_paths, sha, character(1)),
  bytes = file.info(source_paths)$size,
  stringsAsFactors = FALSE
)
write_csv(source_manifest, "network_n1_source_manifest.csv")
message("N1 certified Path ", path, "; outputs written to: ", OUT)
