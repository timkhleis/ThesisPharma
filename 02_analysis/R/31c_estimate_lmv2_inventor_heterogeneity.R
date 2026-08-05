# ============================================================================
# 31c_estimate_lmv2_inventor_heterogeneity.R -- subgroup patent-count ATTs
# ============================================================================
# Opens the outcome only after the frozen moderator table exists.  The P5c
# roster and weights are reused unchanged.  All subgroup effects are
# standardized to common full-treated cohort shares.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))
source(file.path(BASE, "R", "31a_lmv2_inventor_heterogeneity_config.R"))

cfg <- LMV2_INVENTOR_HET
out_dir <- cfg$output_dir
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
temp_dir <- file.path(out_dir, "duckdb_tmp_estimation")
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)

moderator_path <- file.path(out_dir, "inventor_moderators.parquet")
moderator_manifest_path <- file.path(out_dir, "moderator_build_manifest.csv")
if (!all(file.exists(c(moderator_path, moderator_manifest_path)))) {
  stop("Run 31b before opening heterogeneity outcomes")
}
moderator_manifest <- utils::read.csv(
  moderator_manifest_path, stringsAsFactors = FALSE
)
if (nrow(moderator_manifest) != 1L ||
    moderator_manifest$heterogeneity_design_hash !=
      lmv2_inventor_het_hash() ||
    moderator_manifest$moderator_parquet_sha256 !=
      digest::digest(file = moderator_path, algo = "sha256")) {
  stop("Moderator table or its design manifest is stale")
}

panel_files <- sort(list.files(
  cfg$inputs$panel_dir,
  pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE
))
stamp_files <- sort(list.files(
  cfg$inputs$panel_dir,
  pattern = "^lmv2_event_panel_c[0-9]+_stamp\\.csv$",
  full.names = TRUE
))
expected_shards <- length(unique(unlist(cfg$estimand$samples)))
if (length(panel_files) != expected_shards ||
    length(stamp_files) != expected_shards) {
  stop("Certified P5c panel bundle is incomplete")
}
panel_sql <- lmv2_panel_sql(panel_files)
mod_sql <- sprintf(
  "read_parquet(%s)",
  lmv2_sql_string(normalizePath(
    moderator_path, winslash = "/", mustWork = TRUE
  ))
)

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, sprintf(
  "PRAGMA threads=%d", cfg$execution$threads
))
DBI::dbExecute(con, sprintf(
  "PRAGMA memory_limit='%s'", cfg$execution$memory_limit
))
DBI::dbExecute(con, sprintf(
  "PRAGMA temp_directory=%s", lmv2_sql_string(temp_dir)
))
input_checks <- lmv2_validate_estimation_inputs(
  con, panel_files, stamp_files, cfg$inputs$panel_manifest
)
if (!isTRUE(input_checks$pass[[1]])) {
  stop("Inherited P5c panel certification failed")
}

# Collapse the complete t=+1,...,+5 path before subgroup estimation.  Because
# patent count is observed for every roster row-year, this is algebraically
# identical to averaging the five event-time first-difference ATTs.
post_sql <- paste(cfg$estimand$post_event_times, collapse = ",")
DBI::dbExecute(con, sprintf("
CREATE OR REPLACE TEMP TABLE het_unit_outcome AS
WITH baseline AS (
  SELECT roster_row_id,CAST(patent_count AS DOUBLE) y0,
         CAST(weight AS DOUBLE) p5c_weight
  FROM %1$s WHERE event_time=%2$d
), post AS (
  SELECT roster_row_id,AVG(CAST(patent_count AS DOUBLE)) ypost
  FROM %1$s WHERE event_time IN (%3$s)
  GROUP BY roster_row_id
)
SELECT
  m.* EXCLUDE(weight),b.p5c_weight AS weight,
  p.ypost-b.y0 AS dy_post
FROM %4$s m
JOIN baseline b USING (roster_row_id)
JOIN post p USING (roster_row_id)
", panel_sql, cfg$estimand$reference_event_time, post_sql, mod_sql))

moderator_columns <- c(
  career_age = "career_age_group",
  predeal_productivity = "predeal_productivity_group",
  focal_exclusivity = "focal_exclusivity_group",
  team_embeddedness = "team_embeddedness_group",
  focal_tenure = "focal_tenure_group"
)
balance_covariates <- c(
  "log_patent_count_5y", "patent_trajectory", "career_age",
  "focal_group_tenure", "focal_group_exclusivity"
)
excluded_balance <- list(
  career_age = "career_age",
  predeal_productivity = "log_patent_count_5y",
  focal_exclusivity = "focal_group_exclusivity",
  team_embeddedness = character(),
  focal_tenure = "focal_group_tenure"
)

cr1 <- function(x) {
  x <- as.matrix(x)
  x <- sweep(x, 2L, colMeans(x), "-")
  n <- nrow(x)
  if (n < 2L) stop("Fewer than two clusters")
  n / (n - 1) * crossprod(x)
}

score_matrix <- function(x, cluster, groups) {
  keys <- unique(as.character(x[[cluster]]))
  out <- matrix(
    0, nrow = length(keys), ncol = length(groups),
    dimnames = list(keys, groups)
  )
  out[cbind(
    match(as.character(x[[cluster]]), keys),
    match(x$group_name, groups)
  )] <- x$score
  out
}

webb_draws <- function(deal_scores, seed) {
  set.seed(seed)
  support <- c(
    -sqrt(3 / 2), -1, -sqrt(1 / 2),
    sqrt(1 / 2), 1, sqrt(3 / 2)
  )
  B <- cfg$inference$bootstrap_replications
  G <- nrow(deal_scores)
  draws <- matrix(NA_real_, nrow = B, ncol = ncol(deal_scores))
  block <- 500L
  for (start in seq.int(1L, B, by = block)) {
    finish <- min(B, start + block - 1L)
    mult <- matrix(
      sample(support, (finish - start + 1L) * G, replace = TRUE),
      nrow = finish - start + 1L, ncol = G
    )
    draws[start:finish, ] <- mult %*% deal_scores
  }
  draws
}

weighted_balance <- function(moderator, group_col, groups, cohorts) {
  cohort_sql <- paste(cohorts, collapse = ",")
  pieces <- vapply(balance_covariates, function(v) sprintf(
    "SELECT %1$s group_name,arm,'%2$s' AS variable_name,
            weight,%2$s AS value
     FROM het_unit_outcome WHERE cohort IN (%3$s)",
    group_col, v, cohort_sql
  ), character(1))
  moments <- DBI::dbGetQuery(con, sprintf("
WITH long AS (%1$s), means AS (
  SELECT group_name,arm,variable_name,
         SUM(weight*value)/SUM(weight) mean_value,
         SUM(weight) weight_mass
  FROM long GROUP BY 1,2,3
)
SELECT m.*,SUM(l.weight*POWER(l.value-m.mean_value,2))/SUM(l.weight)
  AS variance
FROM means m JOIN long l USING(group_name,arm,variable_name)
GROUP BY m.group_name,m.arm,m.variable_name,m.mean_value,m.weight_mass
", paste(pieces, collapse = "\nUNION ALL\n")))
  names(moments)[names(moments) == "variable_name"] <- "variable"
  treated <- moments[moments$arm == "treated", ]
  control <- moments[moments$arm == "control", ]
  b <- merge(
    treated, control, by = c("group_name", "variable"),
    suffixes = c("_treated", "_control"), sort = FALSE
  )
  denom <- sqrt((b$variance_treated + b$variance_control) / 2)
  diff <- b$mean_value_treated - b$mean_value_control
  b$smd <- ifelse(
    denom > 0, diff / denom, ifelse(abs(diff) <= 1e-12, 0, Inf)
  )
  b$moderator <- moderator
  b$included_in_gate <- !b$variable %in% excluded_balance[[moderator]]
  b <- b[b$group_name %in% groups, ]
  b
}

estimate_one <- function(moderator, sample_name, cohorts, seed_offset) {
  group_col <- unname(moderator_columns[[moderator]])
  groups <- cfg$construction$moderators[[moderator]]$order
  cohort_sql <- paste(cohorts, collapse = ",")
  support_cells <- DBI::dbGetQuery(con, sprintf("
SELECT cohort,%1$s group_name,arm,COUNT(*) n,SUM(weight) mass
FROM het_unit_outcome
WHERE cohort IN (%2$s)
GROUP BY 1,2,3
", group_col, cohort_sql))
  complete <- stats::aggregate(
    support_cells$arm,
    by = list(cohort = support_cells$cohort),
    FUN = length
  )
  names(complete)[2] <- "n_group_arm"
  common_cohorts <- complete$cohort[
    complete$n_group_arm == length(groups) * 2L
  ]
  if (!length(common_cohorts)) {
    stop("No moderator-common cohort set for ", moderator)
  }
  common_sql <- paste(common_cohorts, collapse = ",")
  influence_table <- paste0("het_if_", moderator, "_", sample_name)
  DBI::dbExecute(con, sprintf("
CREATE OR REPLACE TEMP TABLE %1$s AS
WITH design_mass AS (
  SELECT cohort,SUM(weight) treated_design_mass
  FROM het_unit_outcome
  WHERE arm='treated' AND cohort IN (%2$s)
  GROUP BY cohort
), design_share AS (
  SELECT cohort,treated_design_mass/
    SUM(treated_design_mass) OVER () q_g
  FROM design_mass
), arm_stats AS (
  SELECT cohort,%3$s group_name,arm,
         SUM(weight) arm_mass,
         SUM(weight*dy_post)/SUM(weight) mean_dy
  FROM het_unit_outcome
  WHERE cohort IN (%2$s)
  GROUP BY 1,2,3
)
SELECT
  u.roster_row_id,u.deal_id,u.cohort,u.arm,u.codinv,u.weight,
  u.%3$s group_name,u.dy_post,s.arm_mass,s.mean_dy,q.q_g,
  CASE WHEN u.arm='treated' THEN 1.0 ELSE -1.0 END *
    q.q_g*u.weight/s.arm_mass*u.dy_post AS contribution,
  CASE WHEN u.arm='treated' THEN 1.0 ELSE -1.0 END *
    q.q_g*u.weight/s.arm_mass*(u.dy_post-s.mean_dy) AS influence
FROM het_unit_outcome u
JOIN arm_stats s
  ON s.cohort=u.cohort AND s.group_name=u.%3$s AND s.arm=u.arm
JOIN design_share q ON q.cohort=u.cohort
WHERE u.cohort IN (%2$s)
", influence_table, common_sql, group_col))

  estimates <- DBI::dbGetQuery(con, sprintf("
SELECT group_name,SUM(contribution) estimate,SUM(influence) influence_sum
FROM %s GROUP BY group_name
", influence_table))
  estimates <- estimates[match(groups, estimates$group_name), ]
  if (anyNA(estimates$estimate) ||
      max(abs(estimates$influence_sum)) > 1e-8) {
    stop("Invalid subgroup influence construction for ", moderator)
  }

  deal_long <- DBI::dbGetQuery(con, sprintf("
SELECT CAST(deal_id AS VARCHAR) AS cluster_id,
       group_name,SUM(influence) score
FROM %s GROUP BY 1,2
", influence_table))
  inventor_long <- DBI::dbGetQuery(con, sprintf("
SELECT CAST(codinv AS VARCHAR) AS cluster_id,
       group_name,SUM(influence) score
FROM %s GROUP BY 1,2
", influence_table))
  intersection_long <- DBI::dbGetQuery(con, sprintf("
SELECT CAST(deal_id AS VARCHAR)||':'||CAST(codinv AS VARCHAR) AS cluster_id,
       group_name,SUM(influence) score
FROM %s GROUP BY 1,2
", influence_table))
  names(deal_long)[1] <- names(inventor_long)[1] <-
    names(intersection_long)[1] <- "cluster"
  S_deal <- score_matrix(deal_long, "cluster", groups)
  S_inv <- score_matrix(inventor_long, "cluster", groups)
  S_intersection <- score_matrix(intersection_long, "cluster", groups)
  V_deal <- cr1(S_deal)
  V_two <- V_deal + cr1(S_inv) - cr1(S_intersection)
  if (any(diag(V_two) < -1e-12)) {
    stop("Negative two-way variance for ", moderator)
  }
  diag(V_two) <- pmax(diag(V_two), 0)
  se_deal <- sqrt(diag(V_deal))
  se_two <- sqrt(diag(V_two))
  draws <- webb_draws(
    S_deal, cfg$inference$bootstrap_seed + seed_offset
  )
  draw_t <- sweep(draws, 2L, se_deal, "/")
  alpha <- 1 - cfg$inference$confidence_level
  wild_crit <- apply(abs(draw_t), 2L, stats::quantile,
                     probs = 1 - alpha, type = 7)
  p_wild <- vapply(seq_along(groups), function(j) {
    (1 + sum(abs(draw_t[, j]) >=
               abs(estimates$estimate[j] / se_deal[j]))) /
      (nrow(draw_t) + 1)
  }, numeric(1))
  df_two <- min(nrow(S_deal), nrow(S_inv)) - 1L
  tcrit_two <- stats::qt(1 - alpha / 2, df_two)
  p_two <- 2 * stats::pt(
    -abs(estimates$estimate / se_two), df = df_two
  )
  wild_width <- wild_crit * se_deal
  two_width <- tcrit_two * se_two
  governing_width <- pmax(wild_width, two_width)
  governing_p <- pmax(p_wild, p_two)

  group_results <- data.frame(
    moderator = moderator,
    designation = cfg$construction$moderators[[moderator]]$designation,
    sample = sample_name,
    group_name = groups,
    estimate = estimates$estimate,
    deal_se = se_deal,
    two_way_se = se_two,
    ci_low = estimates$estimate - governing_width,
    ci_high = estimates$estimate + governing_width,
    deal_wild_p = p_wild,
    two_way_p = p_two,
    governing_p = governing_p,
    governing_interval = ifelse(
      wild_width >= two_width, "deal_wild", "two_way_deal_inventor"
    ),
    common_cohort_count = length(common_cohorts),
    common_cohorts = paste(common_cohorts, collapse = ";"),
    stringsAsFactors = FALSE
  )

  C <- matrix(
    0, nrow = length(groups) - 1L, ncol = length(groups),
    dimnames = list(
      paste0(groups[-1], " minus ", groups[1]),
      groups
    )
  )
  for (j in seq_len(nrow(C))) {
    C[j, 1] <- -1
    C[j, j + 1L] <- 1
  }
  contrast_est <- drop(C %*% estimates$estimate)
  S_contrast <- S_deal %*% t(C)
  Vc_deal <- cr1(S_contrast)
  Vc_two <- C %*% V_two %*% t(C)
  se_c_deal <- sqrt(diag(Vc_deal))
  se_c_two <- sqrt(pmax(diag(Vc_two), 0))
  draw_c <- draws %*% t(C)
  draw_c_t <- sweep(draw_c, 2L, se_c_deal, "/")
  joint_crit <- unname(stats::quantile(
    apply(abs(draw_c_t), 1L, max),
    1 - cfg$inference$family_alpha, type = 7
  ))
  observed_max_t <- max(abs(contrast_est / se_c_deal))
  omnibus_wild_p <- (
    1 + sum(apply(abs(draw_c_t), 1L, max) >= observed_max_t)
  ) / (nrow(draw_c_t) + 1)
  Vc_two_inv <- tryCatch(
    solve(Vc_two),
    error = function(e) MASS::ginv(Vc_two)
  )
  wald <- drop(t(contrast_est) %*% Vc_two_inv %*% contrast_est)
  omnibus_two_p <- stats::pchisq(
    wald, df = qr(Vc_two)$rank, lower.tail = FALSE
  )
  two_joint_crit <- stats::qt(
    1 - cfg$inference$family_alpha /
      (2 * nrow(C)), df_two
  )
  governing_joint_crit <- max(joint_crit, two_joint_crit)
  se_c_governing <- pmax(se_c_deal, se_c_two)
  contrast_results <- data.frame(
    moderator = moderator,
    sample = sample_name,
    contrast = rownames(C),
    estimate = contrast_est,
    deal_se = se_c_deal,
    two_way_se = se_c_two,
    joint_critical_value = governing_joint_crit,
    ci_low = contrast_est - governing_joint_crit * se_c_governing,
    ci_high = contrast_est + governing_joint_crit * se_c_governing,
    mde_annual_patents = (
      governing_joint_crit +
        stats::qnorm(cfg$inference$target_power)
    ) * se_c_governing,
    meaningful_annual_contrast =
      cfg$estimand$meaningful_annual_contrast,
    stringsAsFactors = FALSE
  )

  support <- DBI::dbGetQuery(con, sprintf("
WITH d AS (
  SELECT %1$s group_name,deal_id,
         COUNT(*) treated_inventors,SUM(weight) treated_mass
  FROM het_unit_outcome
  WHERE arm='treated' AND cohort IN (%2$s)
  GROUP BY 1,2
), s AS (
  SELECT *,treated_mass/SUM(treated_mass)
    OVER (PARTITION BY group_name) deal_share
  FROM d
)
SELECT group_name,SUM(treated_inventors) treated_inventors,
       COUNT(*) nominal_deals,
       1/SUM(deal_share*deal_share) effective_deals,
       MAX(deal_share) largest_deal_share,
       SUM(treated_mass) treated_weight_mass
FROM s GROUP BY group_name
", group_col, common_sql))
  support <- support[match(groups, support$group_name), ]
  balance <- weighted_balance(
    moderator, group_col, groups, common_cohorts
  )
  balance$sample <- sample_name
  gate_balance <- stats::aggregate(
    abs(smd) ~ group_name,
    data = balance[balance$included_in_gate, ],
    FUN = max
  )
  names(gate_balance)[2] <- "max_abs_smd"
  gate <- merge(support, gate_balance, by = "group_name", sort = FALSE)
  gate <- gate[match(groups, gate$group_name), ]
  gate$moderator <- moderator
  gate$sample <- sample_name
  gate$support_balance_pass <-
    gate$treated_inventors >= cfg$diagnostics$minimum_treated_inventors &
    gate$effective_deals >=
      cfg$diagnostics$minimum_effective_treated_deals &
    gate$largest_deal_share <=
      cfg$diagnostics$maximum_treated_deal_share &
    gate$max_abs_smd <= cfg$diagnostics$max_abs_smd
  moderator_gate <- all(gate$support_balance_pass)
  power_gate <- all(
    contrast_results$mde_annual_patents <=
      cfg$estimand$meaningful_annual_contrast
  )
  omnibus <- data.frame(
    moderator = moderator,
    designation = cfg$construction$moderators[[moderator]]$designation,
    sample = sample_name,
    omnibus_deal_wild_p = omnibus_wild_p,
    omnibus_two_way_p = omnibus_two_p,
    omnibus_governing_p = max(omnibus_wild_p, omnibus_two_p),
    support_balance_gate_pass = moderator_gate,
    meaningful_contrast_power_gate_pass = power_gate,
    main_text_status = if (moderator_gate && power_gate) {
      "confirmatory"
    } else if (moderator_gate) {
      "descriptive_underpowered"
    } else {
      "appendix_support_or_balance_limited"
    },
    stringsAsFactors = FALSE
  )
  list(
    groups = group_results, contrasts = contrast_results,
    omnibus = omnibus, support = gate, balance = balance
  )
}

t0 <- Sys.time()
all_results <- list()
counter <- 0L
for (sample_name in names(cfg$estimand$samples)) {
  for (moderator in names(moderator_columns)) {
    counter <- counter + 1L
    message("Estimating ", sample_name, " / ", moderator)
    all_results[[paste(sample_name, moderator, sep = "__")]] <-
      estimate_one(
        moderator, sample_name, cfg$estimand$samples[[sample_name]],
        seed_offset = counter * 1000L
      )
  }
}

bind_component <- function(name) do.call(
  rbind, lapply(all_results, `[[`, name)
)
group_results <- bind_component("groups")
contrast_results <- bind_component("contrasts")
omnibus <- bind_component("omnibus")
support <- bind_component("support")
balance <- bind_component("balance")

# Family adjustment is applied prospectively to full-sample omnibus tests for
# the three primary moderators plus conditional exclusivity.  Appendix tenure
# remains outside that family.
family_rows <- omnibus$sample == "full_1993_2010" &
  omnibus$designation %in% c("primary", "conditional")
omnibus$holm_adjusted_governing_p <- NA_real_
omnibus$holm_adjusted_governing_p[family_rows] <- stats::p.adjust(
  omnibus$omnibus_governing_p[family_rows], method = "holm"
)

utils::write.csv(
  group_results, file.path(out_dir, "heterogeneity_group_att.csv"),
  row.names = FALSE
)
utils::write.csv(
  contrast_results, file.path(out_dir, "heterogeneity_contrasts.csv"),
  row.names = FALSE
)
utils::write.csv(
  omnibus, file.path(out_dir, "heterogeneity_omnibus_tests.csv"),
  row.names = FALSE
)
utils::write.csv(
  support, file.path(out_dir, "heterogeneity_support_balance_gate.csv"),
  row.names = FALSE
)
utils::write.csv(
  balance, file.path(out_dir, "heterogeneity_within_group_balance.csv"),
  row.names = FALSE
)

# Verify the compact construction against the certified overall headline before
# accepting any subgroup result.
overall <- DBI::dbGetQuery(con, "
WITH design_mass AS (
  SELECT cohort,SUM(weight) mass
  FROM het_unit_outcome WHERE arm='treated' GROUP BY cohort
), q AS (
  SELECT cohort,mass/SUM(mass) OVER () q_g FROM design_mass
), arm_stats AS (
  SELECT cohort,arm,SUM(weight) mass,
         SUM(weight*dy_post)/SUM(weight) mean_dy
  FROM het_unit_outcome GROUP BY cohort,arm
), cohort_att AS (
  SELECT cohort,
    MAX(mean_dy) FILTER (arm='treated')-
    MAX(mean_dy) FILTER (arm='control') estimate
  FROM arm_stats GROUP BY cohort
)
SELECT SUM(q.q_g*c.estimate) estimate
FROM cohort_att c JOIN q USING(cohort)
")
headline_path <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment",
  "P6_ESTIMATION_PRIMARY", "p6_headline_post_att.csv"
)
headline <- utils::read.csv(headline_path, stringsAsFactors = FALSE)
headline <- headline[
  headline$outcome == "patent_count" &
    headline$sample == "full_1993_2010" &
    headline$summary == "average_annual_t1_to_t5" &
    headline$governing %in% c(TRUE, "TRUE"),
]
if (nrow(headline) != 1L ||
    abs(overall$estimate - headline$estimate) > 1e-10) {
  stop(
    "Compact heterogeneity estimator does not reproduce headline ATT: ",
    "n_headline=", nrow(headline), "; compact=", overall$estimate,
    "; certified=", paste(headline$estimate, collapse = ",")
  )
}

manifest <- data.frame(
  heterogeneity_design_hash = lmv2_inventor_het_hash(),
  moderator_parquet_sha256 = digest::digest(
    file = moderator_path, algo = "sha256"
  ),
  panel_manifest_sha256 = digest::digest(
    file = cfg$inputs$panel_manifest, algo = "sha256"
  ),
  source_sha256 = digest::digest(
    file = file.path(
      BASE, "R", "31c_estimate_lmv2_inventor_heterogeneity.R"
    ), algo = "sha256"
  ),
  overall_att_reproduced = TRUE,
  reproduced_overall_att = overall$estimate,
  bootstrap_replications = cfg$inference$bootstrap_replications,
  runtime_minutes = as.numeric(
    difftime(Sys.time(), t0, units = "mins")
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(out_dir, "heterogeneity_estimation_manifest.csv"),
  row.names = FALSE
)
message(
  "Inventor heterogeneity estimation complete in ",
  round(manifest$runtime_minutes, 2), " minutes."
)
