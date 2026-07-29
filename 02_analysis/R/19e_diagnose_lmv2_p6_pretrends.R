# ============================================================================
# 19e_diagnose_lmv2_p6_pretrends.R -- wild joint test for frozen P6 leads
# ============================================================================
# Rebuilds only compact pre-period sufficient statistics. It does not alter
# P5 weights or the certified point estimates.

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag) {
  hit <- grep(paste0("^", flag, "="), args, value = TRUE)
  if (length(hit) != 1L) return(NA_character_)
  sub(paste0("^", flag, "="), "", hit)
}
PANEL_DIR <- get_arg("--panel-dir")
OUTPUT_PATH <- get_arg("--output")
if (any(is.na(c(PANEL_DIR, OUTPUT_PATH)))) {
  stop("19e requires --panel-dir= and --output=")
}

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c(
  "DBI", "duckdb", "digest", "fixest", "fwildclusterboot", "dqrng"
)) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "19a_lmv2_p6_estimation_config.R"))
source(file.path(BASE, "R", "19b_lmv2_p6_estimation_core.R"))

panel_files <- sort(list.files(
  PANEL_DIR, pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE
))
if (length(panel_files) != 17L) stop("Expected 17 panel shards")
panel_sql <- lmv2_panel_sql(panel_files)

con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='5GB'")
DBI::dbExecute(con, "PRAGMA threads=8")

run_one <- function(outcome, sample_id, cohorts) {
  pair_table <- lmv2_build_pair_table(
    con, panel_sql, outcome, cohorts, paste0(sample_id, "_wild_pre")
  )
  influence_table <- lmv2_prepare_influence_table(
    con, pair_table, panel_sql, cohorts
  )
  DBI::dbExecute(con, sprintf("DROP TABLE %s", pair_table))
  periods <- LMV2_P6_ESTIMATION$pretrend_window
  estimates <- lmv2_event_estimates(
    con, influence_table, outcome, sample_id
  )
  keep <- match(periods, estimates$event_time)
  b <- estimates$estimate[keep]
  deal <- lmv2_cluster_influence_wide(
    con, influence_table, "deal_id", periods
  )
  DBI::dbExecute(con, sprintf("DROP TABLE %s", influence_table))
  V <- lmv2_cr1_covariance(deal$matrix)
  inv_V <- solve(V)
  observed_stat <- as.numeric(t(b) %*% inv_V %*% b)
  seed <- LMV2_P6_ESTIMATION$inference$seed
  set.seed(seed)
  dqrng::dqset.seed(seed)
  webb <- c(-sqrt(1.5), -1, -sqrt(0.5), sqrt(0.5), 1, sqrt(1.5))
  B <- LMV2_P6_ESTIMATION$inference$replications
  multipliers <- matrix(
    sample(webb, deal$n_clusters * B, replace = TRUE),
    nrow = deal$n_clusters, ncol = B
  )
  boot_b <- crossprod(deal$matrix, multipliers)
  boot_stat <- colSums(boot_b * (inv_V %*% boot_b))
  p_value <- (1 + sum(boot_stat >= observed_stat)) / (B + 1)
  data.frame(
    outcome = outcome,
    sample = sample_id,
    periods = paste(periods, collapse = ";"),
    p_value = p_value,
    statistic = observed_stat,
    bootstrap_replications = B,
    treated_deal_clusters = deal$n_clusters,
    method = "deal_level_webb_multiplier_score_joint_test",
    stringsAsFactors = FALSE
  )
}

out <- do.call(rbind, lapply(names(LMV2_P6_ESTIMATION$samples), function(s) {
  do.call(rbind, lapply(
    c("patent_count", "active_patenting"),
    run_one, sample_id = s, cohorts = LMV2_P6_ESTIMATION$samples[[s]]
  ))
}))
dir.create(dirname(OUTPUT_PATH), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(out, OUTPUT_PATH, row.names = FALSE)
print(out)
