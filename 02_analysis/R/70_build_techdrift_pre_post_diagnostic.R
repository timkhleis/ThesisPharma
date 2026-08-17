# Compare average annual TechDrift in the five years before and after each
# acquisition. This is a descriptive within-inventor diagnostic, not a DiD:
# the pre-acquisition years define the fixed IPC baseline used by TechDrift.

source(file.path("02_analysis", "R", "00_utils.R"))
use_project_library()
for (pkg in c("DBI", "duckdb")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

p6_root <- file.path(".worktrees", "lmv2-p6-outcomes")
panel_glob <- file.path(
  p6_root, "02_analysis", "output", "audit", "local_match_v2",
  "P6_V3_STAYER_SECONDARY_REFRESH", "panel_matched",
  "lmv2_event_panel_c*.parquet"
)
weights_path <- file.path(
  p6_root, "02_analysis", "output", "audit", "local_match_v2",
  "P5B_STAYER_S3", "s3_production_weights.parquet"
)
out_dir <- file.path(
  "02_analysis", "output", "audit", "local_match_v2",
  "TECHDRIFT_PRE_POST_DIAGNOSTIC"
)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

panel_files <- Sys.glob(panel_glob)
if (length(panel_files) != 17L) {
  stop("Expected 17 certified TechDrift panel shards; found ",
       length(panel_files))
}
if (!file.exists(weights_path)) stop("Missing certified stayer weights")

sql_path <- function(path, must_work = TRUE) {
  path <- normalizePath(path, winslash = "/", mustWork = must_work)
  gsub("'", "''", path, fixed = TRUE)
}

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
invisible(DBI::dbExecute(con, "SET threads=4"))

invisible(DBI::dbExecute(con, sprintf("
  CREATE TEMP TABLE supported_treated AS
  SELECT DISTINCT cohort, deal_id, codinv
  FROM read_parquet('%s')
  WHERE spec='primary_count_active_scale' AND treated=1
", sql_path(weights_path))))

invisible(DBI::dbExecute(con, sprintf("
  CREATE TEMP TABLE techdrift_units AS
  WITH treated_panel AS (
    SELECT p.*,
           s.codinv IS NOT NULL AS in_supported_stayer_sample
    FROM read_parquet('%s') p
    LEFT JOIN supported_treated s
      ON s.cohort=p.cohort AND s.deal_id=p.deal_id AND s.codinv=p.codinv
    WHERE p.arm='treated'
  )
  SELECT
    deal_id, cohort, codinv, roster_row_id,
    BOOL_OR(status_eligible_stayer_first_post_t0_t5) AS initially_retained,
    BOOL_OR(in_supported_stayer_sample) AS in_supported_stayer_sample,
    AVG(tech_drift) FILTER (WHERE event_time BETWEEN -5 AND -1) AS pre_mean,
    AVG(tech_drift) FILTER (WHERE event_time BETWEEN 1 AND 5) AS post_mean,
    COUNT(tech_drift) FILTER (WHERE event_time BETWEEN -5 AND -1) AS n_pre,
    COUNT(tech_drift) FILTER (WHERE event_time BETWEEN 1 AND 5) AS n_post
  FROM treated_panel
  GROUP BY deal_id, cohort, codinv, roster_row_id
", sql_path(panel_glob, must_work = FALSE))))

range_check <- DBI::dbGetQuery(con, "
  SELECT COUNT(*) AS invalid
  FROM techdrift_units
  WHERE pre_mean NOT BETWEEN -1e-12 AND 1 + 1e-12
     OR post_mean NOT BETWEEN -1e-12 AND 1 + 1e-12
")$invalid[[1L]]
if (range_check != 0L) stop("TechDrift lies outside [0,1]")

invisible(DBI::dbExecute(con, "
  CREATE TEMP TABLE paired_samples AS
  SELECT 'full_treated' AS sample_id, * FROM techdrift_units
  UNION ALL
  SELECT 'initially_retained_all' AS sample_id, *
  FROM techdrift_units WHERE initially_retained
  UNION ALL
  SELECT 'initially_retained_supported' AS sample_id, *
  FROM techdrift_units WHERE in_supported_stayer_sample
"))

summary <- DBI::dbGetQuery(con, "
  SELECT
    sample_id,
    COUNT(*) AS all_units,
    COUNT(*) FILTER (WHERE n_pre>0) AS units_with_pre,
    COUNT(*) FILTER (WHERE n_post>0) AS units_with_post,
    COUNT(*) FILTER (WHERE n_pre>0 AND n_post>0) AS paired_units,
    AVG(pre_mean) FILTER (WHERE n_pre>0 AND n_post>0) AS mean_pre,
    AVG(post_mean) FILTER (WHERE n_pre>0 AND n_post>0) AS mean_post,
    AVG(post_mean-pre_mean) FILTER (WHERE n_pre>0 AND n_post>0)
      AS mean_paired_change,
    MEDIAN(post_mean-pre_mean) FILTER (WHERE n_pre>0 AND n_post>0)
      AS median_paired_change,
    AVG(n_pre) FILTER (WHERE n_pre>0 AND n_post>0)
      AS mean_observed_pre_years,
    AVG(n_post) FILTER (WHERE n_pre>0 AND n_post>0)
      AS mean_observed_post_years,
    COUNT(DISTINCT deal_id) FILTER (WHERE n_pre>0 AND n_post>0)
      AS paired_deals
  FROM paired_samples
  GROUP BY sample_id
  ORDER BY sample_id
")

paired <- DBI::dbGetQuery(con, "
  SELECT sample_id, deal_id, post_mean-pre_mean AS change
  FROM paired_samples
  WHERE n_pre>0 AND n_post>0
")

# CR1 deal-clustered uncertainty for the descriptive paired mean.
cluster_interval <- function(d) {
  n <- nrow(d)
  g <- length(unique(d$deal_id))
  estimate <- mean(d$change)
  cluster_score <- rowsum(d$change - estimate, d$deal_id, reorder = FALSE)
  se <- sqrt((g / (g - 1)) * sum(cluster_score^2) / n^2)
  critical <- stats::qt(0.975, df = g - 1)
  data.frame(
    sample_id = d$sample_id[[1L]],
    cluster_se = se,
    ci_low = estimate - critical * se,
    ci_high = estimate + critical * se
  )
}
intervals <- do.call(rbind, lapply(split(paired, paired$sample_id),
                                  cluster_interval))
summary <- merge(summary, intervals, by = "sample_id", sort = FALSE)
summary <- summary[match(c(
  "full_treated", "initially_retained_all",
  "initially_retained_supported"
), summary$sample_id), ]

event_time <- DBI::dbGetQuery(con, sprintf("
  WITH supported_panel AS (
    SELECT p.*
    FROM read_parquet('%s') p
    JOIN supported_treated s
      ON s.cohort=p.cohort AND s.deal_id=p.deal_id AND s.codinv=p.codinv
    WHERE p.arm='treated' AND p.event_time<>0
  ), paired AS (
    SELECT roster_row_id
    FROM supported_panel
    GROUP BY roster_row_id
    HAVING COUNT(tech_drift) FILTER (WHERE event_time BETWEEN -5 AND -1)>0
       AND COUNT(tech_drift) FILTER (WHERE event_time BETWEEN 1 AND 5)>0
  )
  SELECT
    event_time,
    AVG(tech_drift) AS mean_techdrift,
    MEDIAN(tech_drift) AS median_techdrift,
    COUNT(tech_drift) AS observed_inventor_years,
    COUNT(DISTINCT p.roster_row_id) FILTER (WHERE tech_drift IS NOT NULL)
      AS observed_inventors
  FROM supported_panel p
  JOIN paired q USING (roster_row_id)
  GROUP BY event_time
  ORDER BY event_time
", sql_path(panel_glob, must_work = FALSE)))

utils::write.csv(
  summary, file.path(out_dir, "techdrift_pre_post_summary.csv"),
  row.names = FALSE, na = ""
)
utils::write.csv(
  event_time, file.path(out_dir, "techdrift_event_time_raw_means.csv"),
  row.names = FALSE, na = ""
)

primary <- summary[summary$sample_id == "initially_retained_supported", ]
note <- c(
  "# TechDrift five-year pre/post diagnostic",
  "",
  "No earlier output directly compared the raw five-year pre- and post-acquisition averages. Existing TechDrift results are matched DiD estimates relative to event time t=-1.",
  "",
  sprintf(
    "In the certified supported initially retained sample, %s inventor-deal units across %s deals have observable TechDrift in both windows. Mean annual TechDrift is %.3f over t=-5,...,-1 and %.3f over t=+1,...,+5. The equal-inventor paired increase is %.3f (deal-clustered 95%% CI %.3f to %.3f); the median paired increase is %.3f.",
    format(primary$paired_units, big.mark = ","), primary$paired_deals,
    primary$mean_pre, primary$mean_post, primary$mean_paired_change,
    primary$ci_low, primary$ci_high, primary$median_paired_change
  ),
  "",
  "Interpret this as a descriptive scale comparison, not an acquisition effect. The fixed TechDrift baseline is constructed from t=-5,...,-1, so pre-period similarity is mechanically high. TechDrift is also undefined in years without a patent/IPC vector, which conditions the paired comparison on post-acquisition patenting. The matched DiD remains the relevant counterfactual estimate.",
  "",
  "The acquisition year t=0 is excluded. Each inventor-deal unit receives equal weight within a sample; annual values are first averaged within each five-year window and then averaged across paired units."
)
writeLines(note, file.path(out_dir, "techdrift_pre_post_note.md"))

print(summary, row.names = FALSE)
