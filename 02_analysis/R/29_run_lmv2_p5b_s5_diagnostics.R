# P5b S5: sample funnel, margin decomposition, and selection diagnostics.
#
# This is a post-outcome diagnostic amendment. It reads but never changes the
# frozen P5c/P5b rosters, weights, panels, or S4 estimates.

source(file.path("02_analysis", "R", "00_utils.R"))
source(file.path("02_analysis", "R", "28a_lmv2_p5b_s4_config.R"))
use_project_library()
shared_lib <- file.path(Sys.getenv("USERPROFILE"), "Documents", "Thesis",
                        ".r_libs")
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

cfg <- lmv2_p5b_s4_config()
out_dir <- file.path(
  cfg$base, "02_analysis", "output", "audit", "local_match_v2",
  "P5B_STAYER_S5_SELECTION_DECOMP")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
out_dir <- normalizePath(out_dir, winslash = "/", mustWork = TRUE)
amendment <- file.path(
  cfg$base, "02_analysis", "notes",
  "local_match_v2_p5b_s5_diagnostic_amendment.md")

write_csv <- function(x, name) {
  utils::write.csv(x, file.path(out_dir, name), row.names = FALSE, na = "")
}
sql_list <- function(paths) {
  paste0("[", paste(vapply(paths, lmv2_sql_string, character(1)),
                         collapse = ","), "]")
}

p5c <- lmv2_p5b_s3_selected_p5c(cfg$s3)
panel_files <- sort(list.files(
  cfg$base_panel_dir, "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE))
if (length(panel_files) != 17L) stop("Expected 17 certified P6 shards")

s2_dir <- cfg$s3$s2_dir
treated_retention <- file.path(
  s2_dir, "treated_retention_partition.parquet")
control_retention <- file.path(
  s2_dir, "control_retained_candidates.parquet")
s3_weights <- cfg$s3_weights
s4_magnitude <- file.path(
  cfg$output_dir, "reporting", "s4_primary_magnitude.csv")
s4_headline <- file.path(cfg$output_dir, "s4_headline_post_att.csv")
required <- c(
  panel_files, p5c$weight_path, treated_retention, control_retention,
  s3_weights, s4_magnitude, s4_headline, amendment)
if (any(!file.exists(required))) {
  stop("Missing input: ", paste(required[!file.exists(required)],
                                collapse = ", "))
}

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=8")
DBI::dbExecute(con, "PRAGMA memory_limit='6GB'")
tmp <- file.path(out_dir, "duckdb_tmp")
dir.create(tmp, showWarnings = FALSE)
DBI::dbExecute(con, sprintf(
  "PRAGMA temp_directory=%s", lmv2_sql_string(tmp)))

DBI::dbExecute(con, sprintf("
  CREATE TEMP TABLE p6_panel AS
  SELECT
    roster_row_id, CAST(deal_id AS INTEGER) deal_id,
    CAST(cohort AS INTEGER) cohort, arm, CAST(codinv AS BIGINT) codinv,
    CAST(focal_group_1 AS BIGINT) focal_group_1,
    CAST(status_eligible AS BOOLEAN) status_eligible,
    CAST(event_time AS INTEGER) event_time, CAST(weight AS DOUBLE) p5c_weight,
    CAST(patent_count AS DOUBLE) patent_count,
    CAST(active_patenting AS DOUBLE) active_patenting
  FROM read_parquet(%s)
", sql_list(panel_files)))
DBI::dbExecute(con, "
  CREATE TEMP TABLE p6_units AS
  SELECT * EXCLUDE(event_time,patent_count,active_patenting)
  FROM p6_panel WHERE event_time=-1
")
DBI::dbExecute(con, sprintf("
  CREATE TEMP TABLE tr AS
  SELECT * FROM read_parquet(%s)
  WHERE retention_window='t1_t5_primary'
", lmv2_sql_string(treated_retention)))
DBI::dbExecute(con, sprintf("
  CREATE TEMP TABLE cr AS
  SELECT * FROM read_parquet(%s)
  WHERE retention_window='t1_t5_primary'
", lmv2_sql_string(control_retention)))
DBI::dbExecute(con, sprintf("
  CREATE TEMP TABLE s3w AS
  SELECT * FROM read_parquet(%s)
  WHERE spec='primary_count_active_scale'
", lmv2_sql_string(s3_weights)))

# --- Full-cohort-to-stayer funnel -------------------------------------------
status_counts <- DBI::dbGetQuery(con, "
  SELECT retention_status, COUNT(*) inventors,
         COUNT(DISTINCT deal_id) deals
  FROM tr GROUP BY retention_status
")
status_counts$stage <- "S2 status-eligible classification"
status_counts$order <- match(
  status_counts$retention_status,
  c("initially_retained", "leaver", "no_post_patent"))

p5c_retained <- DBI::dbGetQuery(con, "
  SELECT COUNT(*) inventors, COUNT(DISTINCT u.deal_id) deals
  FROM p6_units u JOIN tr t
    ON u.arm='treated' AND u.cohort=t.cohort
   AND u.deal_id=t.deal_id AND u.codinv=t.codinv
  WHERE t.retention_status='initially_retained'
")
p5c_treated <- DBI::dbGetQuery(con, "
  SELECT COUNT(*) inventors,COUNT(DISTINCT deal_id) deals,
    COUNT(*) FILTER(status_eligible) status_eligible,
    COUNT(*) FILTER(NOT status_eligible) status_ineligible
  FROM p6_units WHERE arm='treated'
")
s3_final <- DBI::dbGetQuery(con, "
  SELECT COUNT(*) inventors, COUNT(DISTINCT deal_id) deals
  FROM s3w WHERE treated=1
")
initial <- status_counts[
  status_counts$retention_status == "initially_retained", ]
outside_p5c <- initial$inventors - p5c_retained$inventors
convex <- nrow(cfg$s3$treated_support_exclusions)
no_analogue <- p5c_retained$inventors - convex - s3_final$inventors

status_reason <- c(
  initially_retained =
    "First observed patent in t+1..t+5 is assigned to the focal entity",
  leaver =
    "First observed patent in t+1..t+5 is assigned outside the focal entity",
  no_post_patent = "No patent is observed in t+1..t+5")
status_counts <- status_counts[order(status_counts$order), ]
funnel <- rbind(
  data.frame(
    universe = "broader_status_classification",
    stage = paste0("S2: ", status_counts$retention_status),
    inventors = status_counts$inventors, deals = status_counts$deals,
    change_from_prior = NA_integer_,
    reason = unname(status_reason[status_counts$retention_status]),
    stringsAsFactors = FALSE
  ),
  data.frame(
    universe = "frozen_P5c_full_cohort",
    stage = c(
      "All treated inventors in the clean full-DiD P5c roster",
      "P5c inventors eligible for post-deal affiliation classification"),
    inventors = c(
      p5c_treated$inventors, p5c_treated$status_eligible),
    deals = c(p5c_treated$deals, NA_integer_),
    change_from_prior = c(
      NA_integer_, -p5c_treated$status_ineligible),
    reason = c(
      "The exact treated roster used by the clean full-cohort DiD",
      paste0(
        p5c_treated$status_ineligible,
        " P5c inventors lack an unambiguous focal affiliation route and ",
        "cannot be classified as initially retained or leaving")),
    stringsAsFactors = FALSE
  ),
  data.frame(
    universe = "initially_retained_support",
    stage = c(
      "Initially retained and inside frozen P5c common support",
      "After declared convex-hull exclusions",
      "Final S3 retained-inventor support"),
    inventors = c(
      p5c_retained$inventors,
      p5c_retained$inventors - convex,
      s3_final$inventors),
    deals = c(p5c_retained$deals, NA_integer_, s3_final$deals),
    change_from_prior = c(-outside_p5c, -convex, -no_analogue),
    reason = c(
      paste0(
        outside_p5c,
        " initially retained inventors are outside the already-frozen ",
        "full-cohort P5c common-support roster"),
      paste0(convex, " prospectively declared convex-hull exclusions"),
      paste0(
        no_analogue,
        " inventors belong to deal-cohort cells with no retained-control ",
        "analogue inside frozen P5c support")),
    stringsAsFactors = FALSE
  )
)
write_csv(funnel, "s5_sample_funnel.csv")

pipeline <- DBI::dbGetQuery(con, "
  WITH mapped AS (
    SELECT w.treated,w.cohort,w.deal_id,w.codinv,w.control_group,
           u.roster_row_id
    FROM s3w w JOIN p6_units u
      ON w.cohort=u.cohort AND w.deal_id=u.deal_id
     AND w.codinv=u.codinv
     AND ((w.treated=1 AND u.arm='treated')
       OR (w.treated=0 AND u.arm='control'
           AND w.control_group=u.focal_group_1))
  )
  SELECT
    (SELECT COUNT(*) FROM p6_units) certified_p6_roster_rows,
    (SELECT COUNT(*) FROM p6_panel) certified_p6_panel_rows,
    (SELECT COUNT(*) FROM s3w) s3_rows,
    (SELECT COUNT(*) FROM mapped) mapped_s3_rows,
    (SELECT COUNT(DISTINCT roster_row_id) FROM mapped) unique_mapped_rows,
    (SELECT COUNT(*) FROM mapped m JOIN p6_panel p USING(roster_row_id))
      mapped_outcome_rows
")
pipeline$expected_outcome_rows <- 11 * pipeline$s3_rows
pipeline$same_certified_panel <-
  pipeline$s3_rows == pipeline$mapped_s3_rows &
  pipeline$s3_rows == pipeline$unique_mapped_rows &
  pipeline$mapped_outcome_rows == pipeline$expected_outcome_rows
write_csv(pipeline, "s5_pipeline_alignment.csv")
if (!isTRUE(pipeline$same_certified_panel)) {
  stop("S3 rows fail the certified P6 panel mapping")
}

# --- Primary S3 panel and exact extensive/intensive decomposition ------------
DBI::dbExecute(con, "
  CREATE TEMP TABLE s3_map AS
  SELECT w.*,u.roster_row_id
  FROM s3w w JOIN p6_units u
    ON w.cohort=u.cohort AND w.deal_id=u.deal_id
   AND w.codinv=u.codinv
   AND ((w.treated=1 AND u.arm='treated')
     OR (w.treated=0 AND u.arm='control'
         AND w.control_group=u.focal_group_1))
")
DBI::dbExecute(con, "
  CREATE TEMP TABLE s3_panel AS
  SELECT p.roster_row_id,p.deal_id,p.cohort,p.arm,p.codinv,p.event_time,
         m.final_weight weight,p.patent_count,p.active_patenting
  FROM p6_panel p JOIN s3_map m USING(roster_row_id)
")

# Eight level means and their observation-level influence functions. q_g is
# the frozen treated design-mass share, matching the P6/S4 aggregation.
DBI::dbExecute(con, "
  CREATE TEMP TABLE s5_level_influence AS
  WITH dm AS (
    SELECT cohort,SUM(weight) design_mass
    FROM s3_panel WHERE arm='treated' AND event_time=-1 GROUP BY cohort
  ), q AS (
    SELECT cohort,design_mass/SUM(design_mass) OVER() q_g FROM dm
  ), long AS (
    SELECT roster_row_id,deal_id,cohort,arm,codinv,weight,
           CASE WHEN event_time=-1 THEN 'ref' ELSE 'post' END period,
           patent_count,active_patenting
    FROM s3_panel WHERE event_time=-1 OR event_time BETWEEN 1 AND 5
  ), cells AS (
    SELECT cohort,arm,period,
           SUM(weight) mass,
           SUM(weight*patent_count)/SUM(weight) y_count,
           SUM(weight*active_patenting)/SUM(weight) y_active
    FROM long GROUP BY ALL
  )
  SELECT l.roster_row_id,l.deal_id,l.cohort,l.arm,l.codinv,l.period,
         q.q_g*l.weight/c.mass scale,
         c.y_count,c.y_active,l.patent_count,l.active_patenting,
         q.q_g*l.weight/c.mass *
           (l.patent_count-c.y_count) if_count,
         q.q_g*l.weight/c.mass *
           (l.active_patenting-c.y_active) if_active
  FROM long l JOIN cells c USING(cohort,arm,period) JOIN q USING(cohort)
")
levels <- DBI::dbGetQuery(con, "
  SELECT arm,period,
         SUM(scale*patent_count) patent_count,
         SUM(scale*active_patenting) active_patenting
  FROM s5_level_influence GROUP BY ALL ORDER BY arm,period
")
get_level <- function(arm, period, outcome) {
  levels[levels$arm == arm & levels$period == period, outcome][[1]]
}
yt <- get_level("treated", "post", "patent_count")
pt <- get_level("treated", "post", "active_patenting")
yc <- get_level("treated", "ref", "patent_count") +
  get_level("control", "post", "patent_count") -
  get_level("control", "ref", "patent_count")
pc <- get_level("treated", "ref", "active_patenting") +
  get_level("control", "post", "active_patenting") -
  get_level("control", "ref", "active_patenting")
mu_t <- yt / pt
mu_c <- yc / pc
extensive <- (pt - pc) * (mu_t + mu_c) / 2
intensive <- (mu_t - mu_c) * (pt + pc) / 2
total <- yt - yc

theta_names <- c(
  "count_t_post", "count_t_ref", "count_c_post", "count_c_ref",
  "active_t_post", "active_t_ref", "active_c_post", "active_c_ref")
cluster_matrix <- function(cols) {
  group <- paste(cols, collapse = ",")
  z <- DBI::dbGetQuery(con, sprintf("
    SELECT %s,
      SUM(if_count) FILTER(arm='treated' AND period='post') count_t_post,
      SUM(if_count) FILTER(arm='treated' AND period='ref') count_t_ref,
      SUM(if_count) FILTER(arm='control' AND period='post') count_c_post,
      SUM(if_count) FILTER(arm='control' AND period='ref') count_c_ref,
      SUM(if_active) FILTER(arm='treated' AND period='post') active_t_post,
      SUM(if_active) FILTER(arm='treated' AND period='ref') active_t_ref,
      SUM(if_active) FILTER(arm='control' AND period='post') active_c_post,
      SUM(if_active) FILTER(arm='control' AND period='ref') active_c_ref
    FROM s5_level_influence GROUP BY %s
  ", group, group))
  m <- as.matrix(z[, theta_names])
  m[is.na(m)] <- 0
  storage.mode(m) <- "double"
  sweep(m, 2, colMeans(m), "-")
}
cr1 <- function(m) nrow(m) / (nrow(m) - 1) * crossprod(m)
m_deal <- cluster_matrix("deal_id")
m_inv <- cluster_matrix("codinv")
m_both <- cluster_matrix(c("deal_id", "codinv"))
V <- cr1(m_deal) + cr1(m_inv) - cr1(m_both)
diag(V) <- pmax(diag(V), 0)

theta <- c(
  get_level("treated", "post", "patent_count"),
  get_level("treated", "ref", "patent_count"),
  get_level("control", "post", "patent_count"),
  get_level("control", "ref", "patent_count"),
  get_level("treated", "post", "active_patenting"),
  get_level("treated", "ref", "active_patenting"),
  get_level("control", "post", "active_patenting"),
  get_level("control", "ref", "active_patenting"))
names(theta) <- theta_names
decomp_fun <- function(x) {
  x <- unname(x)
  y_t <- x[1]
  y_c <- x[2] + x[3] - x[4]
  p_t <- x[5]
  p_c <- x[6] + x[7] - x[8]
  mu_t <- y_t / p_t
  mu_c <- y_c / p_c
  c(
    total = y_t - y_c,
    extensive = (p_t - p_c) * (mu_t + mu_c) / 2,
    intensive = (mu_t - mu_c) * (p_t + p_c) / 2,
    treated_active_rate = p_t,
    counterfactual_active_rate = p_c,
    treated_conditional_count = mu_t,
    counterfactual_conditional_count = mu_c)
}
point <- decomp_fun(theta)
h <- 1e-6
grad <- sapply(seq_along(theta), function(j) {
  xp <- xm <- theta
  xp[j] <- xp[j] + h
  xm[j] <- xm[j] - h
  (decomp_fun(xp) - decomp_fun(xm)) / (2 * h)
})
V_fun <- grad %*% V %*% t(grad)
se <- sqrt(pmax(diag(V_fun), 0))
df <- min(nrow(m_deal), nrow(m_inv)) - 1
crit <- stats::qt(0.975, df)
decomp <- data.frame(
  component = names(point), estimate = as.numeric(point),
  se = se, df = df, ci_low = point - crit * se,
  ci_high = point + crit * se,
  p_value = 2 * stats::pt(-abs(point / se), df),
  share_of_total = c(
    1, point[["extensive"]] / point[["total"]],
    point[["intensive"]] / point[["total"]], rep(NA_real_, 4)),
  inference = "two_way_deal_inventor_delta_method",
  stringsAsFactors = FALSE)
write_csv(decomp, "s5_extensive_intensive_decomposition.csv")

# Tooth-check against the frozen S4 magnitude.
frozen_mag <- utils::read.csv(s4_magnitude)
frozen_att <- frozen_mag$average_annual_att[
  frozen_mag$sample == "full_1994_2010" &
    frozen_mag$outcome == "patent_count"]
if (length(frozen_att) != 1L || abs(total - frozen_att) > 1e-9 ||
    abs(total - extensive - intensive) > 1e-10) {
  stop("Decomposition does not reproduce the frozen S4 ATT")
}

# --- Selection diagnostics --------------------------------------------------
pre_characteristics_sql <- sprintf("
  WITH base AS (
    SELECT t.retention_status,w.cohort,w.deal_id,w.codinv,
      w.patent_count_m5,w.patent_count_m4,w.patent_count_m3,
      w.patent_count_m2,w.patent_count_m1,
      w.active_patenting_m5,w.active_patenting_m4,
      w.active_patenting_m3,w.active_patenting_m2,w.active_patenting_m1,
      w.career_age,w.focal_group_exclusivity
    FROM tr t
    LEFT JOIN (
      SELECT * FROM read_parquet(%s)
      WHERE treated=1
    ) w
      ON t.cohort=w.cohort AND t.deal_id=CAST(w.deal_id AS BIGINT)
     AND t.codinv=CAST(w.codinv AS BIGINT)
  ), long AS (
    SELECT *,
      patent_count_m5+patent_count_m4+patent_count_m3+
        patent_count_m2+patent_count_m1 patent_stock_5y,
      active_patenting_m5+active_patenting_m4+active_patenting_m3+
        active_patenting_m2+active_patenting_m1 active_years_5y,
      (2*patent_count_m1+patent_count_m2-patent_count_m4-
        2*patent_count_m5)/10.0 patent_linear_trend
    FROM base WHERE cohort IS NOT NULL
  ), vars AS (
    UNPIVOT long ON patent_stock_5y,active_years_5y,patent_linear_trend,
      career_age,focal_group_exclusivity
    INTO NAME variable VALUE value
  )
  SELECT retention_status,variable,COUNT(*) n,
    AVG(value) mean,MEDIAN(value) median,
    QUANTILE_CONT(value,0.25) p25,QUANTILE_CONT(value,0.75) p75
  FROM vars GROUP BY ALL ORDER BY variable,retention_status
", sql_list(p5c$weight_path))
pre_characteristics <- DBI::dbGetQuery(con, pre_characteristics_sql)
write_csv(pre_characteristics, "s5_selection_pre_characteristics.csv")

DBI::dbExecute(con, "
  CREATE TEMP TABLE p5c_status_units AS
  SELECT p.*,COALESCE(t.retention_status,'not_status_eligible')
    retention_status
  FROM p6_units p LEFT JOIN tr t
    ON p.cohort=t.cohort AND p.deal_id=t.deal_id AND p.codinv=t.codinv
  WHERE p.arm='treated'
  UNION ALL
  SELECT p.*,COALESCE(c.retention_status,'not_initially_retained')
    retention_status
  FROM p6_units p LEFT JOIN cr c
    ON p.cohort=c.cohort AND p.codinv=c.codinv
   AND p.focal_group_1=c.control_group
  WHERE p.arm='control'
")
DBI::dbExecute(con, "
  CREATE TEMP TABLE p5c_outcome_units AS
  SELECT roster_row_id,
    MAX(patent_count) FILTER(event_time=-1) patent_m1,
    MAX(patent_count) FILTER(event_time=0) patent_0,
    AVG(patent_count) FILTER(event_time BETWEEN 1 AND 5) patent_post,
    MAX(active_patenting) FILTER(event_time=-1) active_m1,
    MAX(active_patenting) FILTER(event_time=0) active_0
  FROM p6_panel GROUP BY roster_row_id
")
DBI::dbExecute(con, "
  CREATE TEMP TABLE p5c_status_outcomes AS
  SELECT u.*,o.patent_m1,o.patent_0,o.patent_post,o.active_m1,o.active_0
  FROM p5c_status_units u JOIN p5c_outcome_units o USING(roster_row_id)
")
t0_selection <- DBI::dbGetQuery(con, "
  WITH changes AS (
    SELECT roster_row_id,deal_id,cohort,arm,codinv,
      retention_status,p5c_weight,
      patent_m1,patent_0,active_m1,active_0,
      patent_0-patent_m1 count_change,
      active_0-active_m1 active_change
    FROM p5c_status_outcomes
    WHERE retention_status IS NOT NULL
  ), cells AS (
    SELECT cohort,arm,retention_status,
      SUM(p5c_weight*patent_m1)/SUM(p5c_weight) patent_m1,
      SUM(p5c_weight*patent_0)/SUM(p5c_weight) patent_0,
      SUM(p5c_weight*active_m1)/SUM(p5c_weight) active_m1,
      SUM(p5c_weight*active_0)/SUM(p5c_weight) active_0,
      SUM(p5c_weight*count_change)/SUM(p5c_weight) count_change,
      SUM(p5c_weight*active_change)/SUM(p5c_weight) active_change,
      SUM(p5c_weight) mass
    FROM changes GROUP BY ALL
  ), q AS (
    SELECT cohort,SUM(p5c_weight) mass
    FROM p6_units WHERE arm='treated' GROUP BY cohort
  ), qq AS (
    SELECT cohort,mass/SUM(mass) OVER() q FROM q
  )
  SELECT c.arm,c.retention_status,
    SUM(qq.q*c.patent_m1) patent_count_m1,
    SUM(qq.q*c.patent_0) patent_count_0,
    100*SUM(qq.q*c.active_m1) active_patenting_m1_pp,
    100*SUM(qq.q*c.active_0) active_patenting_0_pp,
    SUM(qq.q*c.count_change) patent_count_change,
    100*SUM(qq.q*c.active_change) active_patenting_change_pp,
    SUM(c.mass) weighted_mass
  FROM cells c JOIN qq USING(cohort)
  GROUP BY ALL ORDER BY arm,retention_status
")
write_csv(t0_selection, "s5_t0_selection_diagnostic.csv")

# Pooled Lee-style trimming of the original P5c post-average-minus-reference
# outcome. The cohort table shows where monotonicity may be questionable.
retention_rates <- DBI::dbGetQuery(con, "
  WITH x AS (
    SELECT cohort,arm,
      SUM(p5c_weight) total_mass,
      SUM(p5c_weight) FILTER(retention_status='initially_retained')
        retained_mass
    FROM p5c_status_units
    GROUP BY cohort,arm
  )
  SELECT cohort,
    MAX(retained_mass/total_mass) FILTER(arm='treated') treated_rate,
    MAX(retained_mass/total_mass) FILTER(arm='control') control_rate,
    treated_rate/control_rate treated_control_ratio,
    treated_control_ratio<=1 monotonicity_direction_holds
  FROM x GROUP BY cohort ORDER BY cohort
")
write_csv(retention_rates, "s5_retention_rates_by_cohort.csv")

lee_units <- DBI::dbGetQuery(con, "
  SELECT roster_row_id,deal_id,cohort,arm,codinv,retention_status,
    p5c_weight weight,patent_post-patent_m1 dy
  FROM p5c_status_outcomes
  WHERE retention_status='initially_retained'
")
weighted_mean <- function(y, w) sum(y * w) / sum(w)
weighted_trim_mean <- function(y, w, keep_share, upper_tail) {
  o <- order(y, decreasing = upper_tail)
  y <- y[o]
  w <- w[o]
  target <- keep_share * sum(w)
  used <- pmin(w, pmax(target - cumsum(w) + w, 0))
  sum(y * used) / sum(used)
}
treated_lee <- lee_units[lee_units$arm == "treated", ]
control_lee <- lee_units[lee_units$arm == "control", ]
treated_rate <- sum(treated_lee$weight) /
  sum(DBI::dbGetQuery(
    con, "SELECT p5c_weight weight FROM p6_units WHERE arm='treated'")$weight)
control_rate <- sum(control_lee$weight) /
  sum(DBI::dbGetQuery(
    con, "SELECT p5c_weight weight FROM p6_units WHERE arm='control'")$weight)
keep_share <- min(1, treated_rate / control_rate)
tmean <- weighted_mean(treated_lee$dy, treated_lee$weight)
c_low <- weighted_trim_mean(
  control_lee$dy, control_lee$weight, keep_share, FALSE)
c_high <- weighted_trim_mean(
  control_lee$dy, control_lee$weight, keep_share, TRUE)
lee <- data.frame(
  treated_retention_rate = treated_rate,
  control_retention_rate = control_rate,
  control_keep_share = keep_share,
  treated_selected_change = tmean,
  control_bottom_trimmed_change = c_low,
  control_top_trimmed_change = c_high,
  lee_upper_att = tmean - c_low,
  lee_lower_att = tmean - c_high,
  descriptive_range_lower = tmean - c_high,
  descriptive_range_upper = tmean - c_low,
  estimand = "pooled_P5c_selected_post_average_minus_tminus1",
  method_status = "pooled_trimming_diagnostic_not_formal_Lee_bound",
  formal_lee_valid = FALSE,
  exact_interpretation = paste(
    "Among inventors observed as initially retained under P5c weights,",
    "compare the treated mean post-minus-t-1 patent change with two control",
    "means. The lower endpoint retains the treated/control selection-rate",
    "share of controls with the most favorable changes; the upper endpoint",
    "retains the same share with the most negative changes. The discarded",
    "control weight is therefore placed at one outcome tail at a time.",
    "The range is a pooled worst-tail selected-control sensitivity, not a",
    "confidence interval, common-support bound, formal Lee identified set,",
    "or always-retained treatment-effect bound."),
  assumption_audit = paste(
    "Ordinary Lee requires treatment independence/as-if random assignment",
    "and a common monotonic selection direction. This observational matched",
    "DiD does not establish level independence, and four cohort selection",
    "rates reverse direction. Point range has no sampling uncertainty."),
  stringsAsFactors = FALSE)
write_csv(lee, "s5_lee_selection_bounds.csv")

lee_assumptions <- data.frame(
  requirement = c(
    "Common retention definition",
    "Treatment exchangeability",
    "Monotone treatment effect on retention",
    "Always-retained principal-stratum interpretation",
    "Outcome availability",
    "Sampling uncertainty"),
  required_for_formal_bound = c(TRUE, TRUE, TRUE, TRUE, FALSE, TRUE),
  status = c(
    "satisfied",
    "not established",
    "violated in pooled cohort implementation",
    "not identified under current assumptions",
    "outcomes are observed even when retention status is zero",
    "not implemented for the descriptive range"),
  evidence = c(
    "The same first-post-patent rule is applied to treated and controls.",
    paste(
      "Entropy balance supports conditional parallel trends for changes;",
      "it does not establish independence of potential retention and",
      "potential outcomes."),
    paste0(
      "The pooled lower-treated-selection direction reverses in ",
      sum(!retention_rates$monotonicity_direction_holds),
      " of 17 cohorts."),
    paste(
      "Observed treated retainers need not equal inventors who would retain",
      "under either acquisition state."),
    paste(
      "Lee's original missing-outcome motivation is not literal here;",
      "retention is an analyst-defined post-treatment subgroup."),
    paste(
      "The current endpoints are point calculations without clustered",
      "confidence sets.")),
  implication = c(
    "No obstacle.",
    "A formal extension needs an explicit conditional principal-stratum assumption.",
    paste(
      "Ordinary pooled Lee trimming is invalid; conditional sign-specific",
      "trimming would be required."),
    "The current range cannot be labelled an always-retained ATT bound.",
    "Use the range only as a selected-sample trimming sensitivity.",
    "Do not attach causal coverage claims to the endpoints."),
  stringsAsFactors = FALSE)
write_csv(lee_assumptions, "s5_lee_assumption_audit.csv")

# Common-support tipping calculation for the 427/3,090 initially retained
# inventors not entering the final S3 supported ATT.
p_supported <- s3_final$inventors / initial$inventors
unsupported_share <- 1 - p_supported
tipping <- -p_supported * frozen_att / unsupported_share
grid <- seq(-1, 1, by = 0.01)
support_bounds <- data.frame(
  unsupported_att = grid,
  all_initially_retained_att =
    p_supported * frozen_att + unsupported_share * grid,
  supported_share = p_supported,
  unsupported_share = unsupported_share,
  stringsAsFactors = FALSE)
write_csv(support_bounds, "s5_common_support_tipping_grid.csv")
write_csv(data.frame(
  supported_inventors = s3_final$inventors,
  all_initially_retained_inventors = initial$inventors,
  supported_share = p_supported,
  supported_att = frozen_att,
  unsupported_att_required_to_reverse = tipping,
  stringsAsFactors = FALSE),
  "s5_common_support_tipping_summary.csv")

# Every narrowed guard gets a positive tooth test.
tooth <- data.frame(
  check = c(
    "pipeline_mapping_fails_after_duplicate",
    "decomposition_fails_after_component_perturbation"),
  pass = c(
    pipeline$s3_rows + 1L != pipeline$mapped_s3_rows,
    abs(total - (extensive + 0.01) - intensive) > 1e-10),
  stringsAsFactors = FALSE)
write_csv(tooth, "s5_tooth_tests.csv")
if (!all(tooth$pass)) stop("At least one S5 tooth test did not fire")

certification <- data.frame(
  check = c(
    "certified_p6_roster_has_500906_rows",
    "certified_p6_panel_has_11_rows_per_roster_row",
    "every_primary_s3_row_maps_once",
    "s2_status_partition_reconciles",
    "p5c_initially_retained_count_is_2678",
    "final_supported_count_is_2663",
    "decomposition_reproduces_frozen_s4_att",
    "decomposition_components_sum_to_total",
    "retention_rates_cover_all_17_cohorts",
    "pooled_trimming_diagnostic_is_ordered",
    "common_support_tipping_value_is_finite",
    "all_positive_tooth_tests_fire"),
  pass = c(
    pipeline$certified_p6_roster_rows == 500906L,
    pipeline$certified_p6_panel_rows ==
      11L * pipeline$certified_p6_roster_rows,
    pipeline$same_certified_panel,
    sum(status_counts$inventors) == 28483L,
    p5c_retained$inventors == 2678L,
    s3_final$inventors == 2663L,
    abs(total - frozen_att) <= 1e-9,
    abs(total - extensive - intensive) <= 1e-10,
    nrow(retention_rates) == 17L,
    lee$lee_lower_att <= lee$lee_upper_att,
    is.finite(tipping),
    all(tooth$pass)),
  detail = c(
    pipeline$certified_p6_roster_rows,
    pipeline$certified_p6_panel_rows,
    pipeline$mapped_s3_rows,
    sum(status_counts$inventors),
    p5c_retained$inventors,
    s3_final$inventors,
    total - frozen_att,
    total - extensive - intensive,
    nrow(retention_rates),
    lee$lee_upper_att - lee$lee_lower_att,
    tipping,
    sum(tooth$pass)),
  stringsAsFactors = FALSE)
write_csv(certification, "s5_certification.csv")
if (!all(certification$pass)) {
  stop("At least one S5 certification check failed")
}

source_paths <- c(
  file.path(cfg$base, "02_analysis", "R",
            "29_run_lmv2_p5b_s5_diagnostics.R"),
  amendment)
source_manifest <- data.frame(
  artifact = basename(source_paths),
  sha256 = vapply(
    source_paths, digest::digest, character(1),
    algo = "sha256", file = TRUE, serialize = FALSE),
  stringsAsFactors = FALSE)
write_csv(source_manifest, "s5_source_manifest.csv")

manifest_paths <- list.files(
  out_dir, pattern = "\\.(csv)$", full.names = TRUE)
manifest_paths <- manifest_paths[
  basename(manifest_paths) != "s5_manifest.csv"]
manifest <- data.frame(
  artifact = basename(manifest_paths),
  rows = vapply(
    manifest_paths,
    function(x) nrow(utils::read.csv(x, stringsAsFactors = FALSE)),
    integer(1)),
  sha256 = vapply(
    manifest_paths, digest::digest, character(1),
    algo = "sha256", file = TRUE, serialize = FALSE),
  stringsAsFactors = FALSE)
write_csv(manifest, "s5_manifest.csv")
message("P5b S5 diagnostics complete: ", out_dir)
