# ============================================================================
# 30c_assign_lmv2_dealsim_terciles.R -- deterministic bins and support audit
# ============================================================================

BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
if (!requireNamespace("digest", quietly = TRUE)) stop("Missing package: digest")
source(file.path(BASE, "R", "15a_lmv2_design_lock.R"))
source(file.path(BASE, "R", "30a_lmv2_dealsim_power_config.R"))

out_dir <- LMV2_DEALSIM_POWER$output_dir
deal_path <- file.path(out_dir, "dealsim_by_deal.csv")
build_manifest_path <- file.path(out_dir, "dealsim_build_manifest.csv")
if (!file.exists(deal_path) || !file.exists(build_manifest_path)) {
  stop("Run 30b before assigning DealSim terciles")
}
build_manifest <- utils::read.csv(
  build_manifest_path, stringsAsFactors = FALSE
)
if (nrow(build_manifest) != 1L ||
    build_manifest$dealsim_power_hash != lmv2_dealsim_power_hash()) {
  stop("DealSim build manifest is stale")
}

deals <- utils::read.csv(deal_path, stringsAsFactors = FALSE)
lmv2_assert_dealsim_rows(deals)
deals$tercile <- NA_character_
eligible <- deals$eligible_dealsim
deals$tercile[eligible] <- lmv2_dealsim_assign_terciles(
  deals$deal_id[eligible], deals$dealsim[eligible]
)

summarize_group <- function(x, sample) {
  total_weight <- sum(x$treated_weight)
  data.frame(
    sample = sample,
    tercile = x$tercile[[1]],
    nominal_deals = nrow(x),
    treated_inventors = sum(x$n_treated_inventors),
    treated_weight = total_weight,
    effective_deals = lmv2_effective_count(x$treated_weight),
    largest_deal_share = max(x$treated_weight / total_weight),
    minimum_dealsim = min(x$dealsim),
    maximum_dealsim = max(x$dealsim),
    stringsAsFactors = FALSE
  )
}

eligible_deals <- deals[eligible, ]
all_summary <- do.call(rbind, lapply(
  split(eligible_deals, eligible_deals$tercile),
  summarize_group, sample = "all_eligible_cohorts"
))

cohort_grid <- stats::aggregate(
  deal_id ~ cohort + tercile, eligible_deals, length
)
names(cohort_grid)[[3]] <- "nominal_deals"
wide <- reshape(
  cohort_grid, idvar = "cohort", timevar = "tercile",
  direction = "wide"
)
for (label in LMV2_DEALSIM_POWER$construction$tercile_labels) {
  col <- paste0("nominal_deals.", label)
  if (!col %in% names(wide)) wide[[col]] <- 0L
  wide[[col]][is.na(wide[[col]])] <- 0L
}
wide$common_to_all_terciles <- apply(
  wide[paste0(
    "nominal_deals.", LMV2_DEALSIM_POWER$construction$tercile_labels
  )] > 0L,
  1L, all
)
common_cohorts <- wide$cohort[wide$common_to_all_terciles]
if (!length(common_cohorts)) {
  stop("No acquisition cohort contains all three deterministic terciles")
}
common_deals <- eligible_deals[
  eligible_deals$cohort %in% common_cohorts, ,
  drop = FALSE
]
common_summary <- do.call(rbind, lapply(
  split(common_deals, common_deals$tercile),
  summarize_group, sample = "common_cohort_set"
))
summary <- rbind(all_summary, common_summary)
summary <- summary[order(summary$sample, summary$tercile), ]

utils::write.csv(
  deals, file.path(out_dir, "dealsim_tercile_assignment.csv"),
  row.names = FALSE, na = ""
)
utils::write.csv(
  summary, file.path(out_dir, "dealsim_tercile_support.csv"),
  row.names = FALSE, na = ""
)
utils::write.csv(
  wide[order(wide$cohort), ],
  file.path(out_dir, "dealsim_common_cohort_audit.csv"),
  row.names = FALSE, na = ""
)

manifest <- data.frame(
  dealsim_power_hash = lmv2_dealsim_power_hash(),
  deal_table_sha256 = digest::digest(file = deal_path, algo = "sha256"),
  build_manifest_sha256 = digest::digest(
    file = build_manifest_path, algo = "sha256"
  ),
  assignment_source_sha256 = digest::digest(
    file = file.path(BASE, "R", "30c_assign_lmv2_dealsim_terciles.R"),
    algo = "sha256"
  ),
  eligible_deals = nrow(eligible_deals),
  common_cohort_count = length(common_cohorts),
  common_cohorts = paste(common_cohorts, collapse = ";"),
  deterministic_assignment = TRUE,
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest, file.path(out_dir, "dealsim_assignment_manifest.csv"),
  row.names = FALSE
)
message(
  "Deterministic DealSim terciles assigned across ",
  nrow(eligible_deals), " deals; ", length(common_cohorts),
  " cohorts are common to all three bins."
)
