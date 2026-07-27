# HonestDiD (Rambachan & Roth 2021/2023) sensitivity analysis.
#
# IMPORTANT COMPATIBILITY FINDING (discovered while building this script):
# The official honest_did.AGGTEobj() helper (credited to Pedro Sant'Anna,
# distributed as example code in the HonestDiD README, not as an exported
# package function -- CRAN v0.2.8 exports only the low-level
# createSensitivityResults()/createSensitivityResults_relativeMagnitudes())
# hardcodes referencePeriod <- -1 and splits pre/post periods via
# `npre <- sum(es$egt < referencePeriod)`. This is exactly correct under
# anticipation=0 (base_period="universal" then sets the reference to t-1,
# cleanly dividing every earlier period as "pre" and t=0 onward as "post").
#
# It is NOT correct for our anticipation=1 objects: there, the reference is
# t-2, and t=-1 (a genuine pre-treatment / anticipation-window point, with a
# real non-zero estimated coefficient) sits numerically ABOVE the reference,
# so the helper's naive split would silently fold it into the "post" set and
# corrupt both the pre-period count used to build Delta and the post-period
# indexing used by basisVector(e+1, ...). This is a structural incompatibility
# in the helper's pre/post split logic, not something fixable by just
# swapping referencePeriod to -2.
#
# Resolution: run HonestDiD on the saved ANTICIPATION=0 aggte objects
# (aggte_matched_bootstrap_anticipation0_<outcome>.rds, from 08i), where the
# official helper's assumptions hold exactly, unmodified. Flagged clearly in
# output/reporting -- see 08i's own side-by-side anticipation comparison for
# why anticipation=0 is a defensible, independently-motivated choice on its
# own terms (not merely "whichever makes HonestDiD easier").
#
# Run from the project root after 08i_anticipation_comparison.R:
#   Rscript 02_analysis/R/08l_honestdid_sensitivity.R

BASE    <- normalizePath("02_analysis", mustWork = TRUE)
RESULTS <- file.path(BASE, "output", "results", "cs2021_honestdid")
SUPPORT_RESULTS <- file.path(BASE, "output", "results", "cs2021_common_support")
FIGS    <- file.path(BASE, "output", "figures", "preliminary_results")

source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
for (pkg in c("HonestDiD", "ggplot2")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
library(HonestDiD)
dir.create(RESULTS, recursive = TRUE, showWarnings = FALSE)
dir.create(FIGS, recursive = TRUE, showWarnings = FALSE)
banner  <- function(x) message("\n", strrep("=", 60), "\n  ", x, "\n", strrep("=", 60))
section <- function(x) message("\n--- ", x, " ---")
write_result <- function(df, filename) {
  utils::write.csv(df, file.path(RESULTS, filename), row.names = FALSE, na = "")
}

# --- official honest_did.AGGTEobj helper, verbatim from the HonestDiD README
# (asheshrambachan/HonestDiD), credited to Pedro Sant'Anna -----------------
honest_did <- function(...) UseMethod("honest_did")

honest_did.AGGTEobj <- function(es, e = 0, type = c("smoothness", "relative_magnitude"),
                                 gridPoints = 100, ...) {
  type <- match.arg(type)
  if (es$type != "dynamic") stop("need to pass in an event study")
  if (es$DIDparams$base_period != "universal") stop("Use a universal base period for honest_did")

  es_inf_func <- es$inf.function$dynamic.inf.func.e
  n <- nrow(es_inf_func)
  V <- t(es_inf_func) %*% es_inf_func / n / n

  referencePeriod <- -1
  consecutivePre  <- !all(diff(es$egt[es$egt <= referencePeriod]) == 1)
  consecutivePost <- !all(diff(es$egt[es$egt >= referencePeriod]) == 1)
  if (consecutivePre | consecutivePost) {
    stop("honest_did expects a time vector with consecutive time periods; please re-code your event study and interpret the results accordingly.")
  }

  hasReference <- any(es$egt == referencePeriod)
  if (hasReference) {
    referencePeriodIndex <- which(es$egt == referencePeriod)
    V    <- V[-referencePeriodIndex, -referencePeriodIndex]
    beta <- es$att.egt[-referencePeriodIndex]
  } else {
    beta <- es$att.egt
  }

  nperiods <- nrow(V)
  npre     <- sum(1 * (es$egt < referencePeriod))
  npost    <- nperiods - npre
  if (!hasReference & (min(c(npost, npre)) <= 0)) {
    stop(if (npost <= 0) "not enough post-periods" else "not enough pre-periods")
  }

  baseVec1 <- basisVector(index = (e + 1), size = npost)
  orig_ci  <- constructOriginalCS(
    betahat = beta, sigma = V, numPrePeriods = npre, numPostPeriods = npost, l_vec = baseVec1
  )

  if (type == "relative_magnitude") {
    robust_ci <- createSensitivityResults_relativeMagnitudes(
      betahat = beta, sigma = V, numPrePeriods = npre, numPostPeriods = npost,
      l_vec = baseVec1, gridPoints = gridPoints, ...
    )
  } else {
    robust_ci <- createSensitivityResults(
      betahat = beta, sigma = V, numPrePeriods = npre, numPostPeriods = npost,
      l_vec = baseVec1, ...
    )
  }
  list(robust_ci = robust_ci, orig_ci = orig_ci, type = type)
}

banner("HONESTDID SENSITIVITY ANALYSIS (anticipation=0 objects)")

outcomes <- c("active_patenting", "log_patent_count")
e_values <- c(0, 3, 5)

breakdown_summary <- list()
all_robust_ci <- list()

for (outcome in outcomes) {
  es <- readRDS(file.path(SUPPORT_RESULTS, paste0("aggte_matched_bootstrap_anticipation0_", outcome, ".rds")))
  section(paste(outcome, "| es$type =", es$type, "| base_period =", es$DIDparams$base_period))

  pre_atts <- es$att.egt[es$egt < -1]
  pre_range <- max(abs(pre_atts), na.rm = TRUE)
  mvec_scale <- seq(0, round(2 * pre_range, 3), length.out = 8)
  message("Pre-period att range for Mvec scaling: max abs = ", round(pre_range, 4),
          " -> Mvec = ", paste(round(mvec_scale, 4), collapse = ", "))

  for (e in e_values) {
    for (type in c("relative_magnitude", "smoothness")) {
      key <- paste(outcome, type, paste0("e", e), sep = "_")
      section(paste("type =", type, "| e =", e))

      result <- tryCatch({
        if (type == "relative_magnitude") {
          honest_did(es, e = e, type = type, Mbarvec = seq(0, 2, by = 0.25))
        } else {
          honest_did(es, e = e, type = type, Mvec = mvec_scale)
        }
      }, error = function(err) {
        message("ERROR for ", key, ": ", conditionMessage(err))
        NULL
      })
      if (is.null(result)) next

      ci_df <- result$robust_ci
      ci_df$outcome <- outcome
      ci_df$e <- e
      ci_df$sensitivity_type <- type
      all_robust_ci[[key]] <- ci_df
      write_result(ci_df, paste0("honestdid_", type, "_", outcome, "_e", e, ".csv"))

      # breakdown value: smallest M/Mbar at which the robust CI first includes zero
      m_col <- if ("Mbar" %in% names(ci_df)) "Mbar" else if ("M" %in% names(ci_df)) "M" else NA
      breakdown_val <- NA_real_
      if (!is.na(m_col)) {
        crosses_zero <- ci_df$lb <= 0 & ci_df$ub >= 0
        if (any(crosses_zero)) breakdown_val <- min(ci_df[[m_col]][crosses_zero])
      }
      breakdown_summary[[key]] <- data.frame(
        outcome = outcome, sensitivity_type = type, e = e,
        original_att = es$att.egt[which(es$egt == e)],
        breakdown_value = breakdown_val,
        robust_at_max_grid = !any(ci_df$lb <= 0 & ci_df$ub >= 0)
      )
      message("Breakdown value: ", round(breakdown_val, 3),
              " | robust across full grid: ", !any(ci_df$lb <= 0 & ci_df$ub >= 0))
    }
  }
}

banner("BREAKDOWN SUMMARY")
breakdown_df <- do.call(rbind, breakdown_summary)
write_result(breakdown_df, "honestdid_breakdown_summary.csv")
print(breakdown_df)

banner("HONESTDID SENSITIVITY COMPLETE")
message("Outputs: ", RESULTS)
message("NOTE: run on anticipation=0 aggte objects -- see script header for why anticipation=1")
message("objects are structurally incompatible with the official honest_did.AGGTEobj() helper.")
