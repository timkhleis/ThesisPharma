# ============================================================================
# 65d_report_certify_lmv2_relative_standing.R -- certification and report
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
source(file.path(BASE, "R", "65a_lmv2_relative_standing_config.R"))

cfg <- LMV2_RELSTAND
out_dir <- cfg$output_dir
paths <- list(
  moderator = file.path(out_dir, "relative_standing_moderators.parquet"),
  build_manifest = file.path(out_dir, "relative_standing_build_manifest.csv"),
  build_cert = file.path(out_dir, "relative_standing_build_certification.csv"),
  estimation_manifest = file.path(out_dir, "relative_standing_estimation_manifest.csv"),
  results = file.path(out_dir, "relative_standing_results.csv"),
  headline = file.path(out_dir, "relative_standing_headline_comparison.csv"),
  balance = file.path(out_dir, "relative_standing_balance.csv"),
  gates = file.path(out_dir, "relative_standing_subgroup_gates.csv"),
  pretrend = file.path(out_dir, "relative_standing_pretrend_results.csv"),
  pretrend_omnibus = file.path(out_dir, "relative_standing_pretrend_omnibus.csv"),
  distribution = file.path(out_dir, "relative_standing_distribution.csv"),
  eligibility = file.path(out_dir, "relative_standing_eligibility.csv")
)
missing <- names(paths)[!file.exists(unlist(paths))]
if (length(missing)) stop("Missing reporting input: ", paste(missing, collapse = ", "))

build_manifest <- utils::read.csv(paths$build_manifest, stringsAsFactors = FALSE)
build_cert <- utils::read.csv(paths$build_cert, stringsAsFactors = FALSE)
estimation_manifest <- utils::read.csv(
  paths$estimation_manifest, stringsAsFactors = FALSE
)
results <- utils::read.csv(paths$results, stringsAsFactors = FALSE)
headline <- utils::read.csv(paths$headline, stringsAsFactors = FALSE)
balance <- utils::read.csv(paths$balance, stringsAsFactors = FALSE)
gates <- utils::read.csv(paths$gates, stringsAsFactors = FALSE)
pretrend <- utils::read.csv(paths$pretrend, stringsAsFactors = FALSE)
pretrend_omnibus <- utils::read.csv(
  paths$pretrend_omnibus, stringsAsFactors = FALSE
)
distribution <- utils::read.csv(paths$distribution, stringsAsFactors = FALSE)
eligibility <- utils::read.csv(paths$eligibility, stringsAsFactors = FALSE)

checks <- data.frame(
  check = c(
    "outcome_blind_build_certified",
    "design_hashes_match",
    "moderator_hash_matches",
    "two_primary_outcome_gradients_reported",
    "complete_frozen_result_grid_reported",
    "four_patent_count_preperiod_gradients_reported",
    "eligible_headlines_reported",
    "subgroup_gates_reported",
    "holm_adjustment_applied_to_primary_family"
  ),
  pass = c(
    all(build_cert$pass),
    build_manifest$design_hash == lmv2_relstand_hash() &&
      estimation_manifest$design_hash == lmv2_relstand_hash(),
    build_manifest$relative_standing_sha256 == digest::digest(
      file = paths$moderator, algo = "sha256"
    ) && estimation_manifest$moderator_sha256 == digest::digest(
      file = paths$moderator, algo = "sha256"
    ),
    sum(results$model == "standing_primary") == 2L,
    nrow(results) == 10L,
    nrow(pretrend) == 4L &&
      setequal(pretrend$event_time, cfg$estimand$pretrend_event_times),
    nrow(headline) == 2L,
    nrow(gates) == 4L,
    all(!is.na(results$holm_adjusted_governing_p[
      results$model == "standing_primary"
    ]))
  ),
  stringsAsFactors = FALSE
)
lmv2_relstand_assert(checks)
utils::write.csv(
  checks, file.path(out_dir, "relative_standing_certification.csv"),
  row.names = FALSE
)

get_result <- function(model, outcome, term = NULL) {
  x <- results$Model == model & results$Outcome == outcome
  if (!is.null(term)) x <- x & results$Term == term
  z <- results[x, , drop = FALSE]
  if (nrow(z) != 1L) stop("Expected one result for ", model, "/", outcome)
  z
}

# Preserve lower-case CSV names while allowing readable code below.
names(results)[names(results) == "model"] <- "Model"
names(results)[names(results) == "outcome"] <- "Outcome"
names(results)[names(results) == "term"] <- "Term"

primary_patent <- get_result("standing_primary", "patent_count")
primary_active <- get_result("standing_primary", "active_patenting")
horse_loss <- get_result(
  "standing_productivity_horse_race", "patent_count", "tx_loss"
)
horse_prod <- get_result(
  "standing_productivity_horse_race", "patent_count", "tx_prod"
)
focused <- get_result("productive_3plus_positive_loss", "patent_count")
kapoor <- get_result("kapoor_top20_sensitivity", "patent_count")
headline_patent <- headline[headline$outcome == "patent_count", , drop = FALSE]
dist_treated <- distribution[distribution$arm == "treated", , drop = FALSE]
eligible_treated <- eligibility[
  eligibility$standing_eligibility == "eligible" &
    eligibility$arm == "treated", , drop = FALSE
]
standing_smd <- balance$smd[
  balance$variable == "relative_standing_loss_10pp"
]

preperiod_pass <- pretrend_omnibus$deal_wild_p > 0.10
balance_pass <- abs(standing_smd) <= cfg$diagnostics$max_abs_smd
horse_support <- horse_loss$estimate < 0 && horse_loss$governing_p <= 0.10
interpretation <- if (preperiod_pass && balance_pass && horse_support) {
  paste(
    "The conditional standing-loss gradient is negative, passes the",
    "standing-balance and pre-period trajectory diagnostics, and supports a",
    "mechanism-consistent main-text interpretation."
  )
} else if (horse_loss$estimate < 0) {
  paste(
    "The conditional standing-loss gradient is negative but does not clear",
    "every diagnostic or precision threshold. It is suggestive appendix",
    "evidence rather than a causal mechanism headline."
  )
} else {
  paste(
    "The conditional standing-loss gradient is not negative. The data do not",
    "support relative-standing loss as the explanation for the productivity",
    "heterogeneity result."
  )
}

fmt <- function(x, digits = 3) formatC(x, digits = digits, format = "f")
fmt_p <- function(x) ifelse(x < 0.001, "<0.001", fmt(x, 3))

report <- c(
  "# Local Match v2: predicted relative-standing loss results",
  "",
  "## Result",
  "",
  sprintf(
    paste0(
      "The eligible-sample patent-count ATT is %s (95%% CI [%s, %s]; ",
      "governing p=%s), compared with %s in the complete 1993--2010 sample."
    ),
    fmt(headline_patent$estimate), fmt(headline_patent$ci_low),
    fmt(headline_patent$ci_high), fmt_p(headline_patent$governing_p),
    fmt(headline_patent$full_sample_estimate)
  ),
  "",
  sprintf(
    paste0(
      "In the primary specification, a ten-percentage-point predicted loss ",
      "of standing changes the patent-count ATT by %s (95%% CI [%s, %s]; ",
      "governing p=%s; Holm-adjusted p=%s)."
    ),
    fmt(primary_patent$estimate), fmt(primary_patent$ci_low),
    fmt(primary_patent$ci_high), fmt_p(primary_patent$governing_p),
    fmt_p(primary_patent$holm_adjusted_governing_p)
  ),
  sprintf(
    paste0(
      "The corresponding active-patenting gradient is %s (95%% CI ",
      "[%s, %s]; governing p=%s; Holm-adjusted p=%s)."
    ),
    fmt(primary_active$estimate), fmt(primary_active$ci_low),
    fmt(primary_active$ci_high), fmt_p(primary_active$governing_p),
    fmt_p(primary_active$holm_adjusted_governing_p)
  ),
  "",
  "## Productivity horse race",
  "",
  sprintf(
    paste0(
      "After adding the treatment--absolute-productivity interaction, the ",
      "standing-loss gradient is %s (95%% CI [%s, %s]; p=%s). The ",
      "conditional absolute-productivity gradient is %s (95%% CI [%s, %s]; ",
      "p=%s)."
    ),
    fmt(horse_loss$estimate), fmt(horse_loss$ci_low), fmt(horse_loss$ci_high),
    fmt_p(horse_loss$governing_p), fmt(horse_prod$estimate),
    fmt(horse_prod$ci_low), fmt(horse_prod$ci_high),
    fmt_p(horse_prod$governing_p)
  ),
  "",
  interpretation,
  "",
  "## Focused and literature-replication checks",
  "",
  sprintf(
    paste0(
      "Among inventors with at least three pre-deal patents, positive ",
      "predicted standing loss changes the ATT by %s relative to no loss or a ",
      "rank gain (95%% CI [%s, %s]; p=%s)."
    ),
    fmt(focused$estimate), fmt(focused$ci_low), fmt(focused$ci_high),
    fmt_p(focused$governing_p)
  ),
  sprintf(
    paste0(
      "The Kapoor--Lim top-20 contrast is %s (95%% CI [%s, %s]; p=%s)."
    ),
    fmt(kapoor$estimate), fmt(kapoor$ci_low), fmt(kapoor$ci_high),
    fmt_p(kapoor$governing_p)
  ),
  "",
  "## Diagnostics",
  "",
  sprintf(
    paste0(
      "The construct covers %s treated inventors across %s deals. The treated ",
      "distribution has mean %s, median %s, and 90th percentile %s percentage ",
      "points; %s of treated inventors have positive predicted loss."
    ),
    format(eligible_treated$roster_rows, big.mark = ","),
    eligible_treated$deals, fmt(dist_treated$mean), fmt(dist_treated$p50),
    fmt(dist_treated$p90), fmt(dist_treated$share_positive)
  ),
  sprintf(
    "The weighted treated--control SMD for standing loss is %s.",
    fmt(standing_smd)
  ),
  sprintf(
    paste0(
      "The overlapping-window standing-gradient trajectory diagnostic over ",
      "t=-5,...,-2 has p=%s. Because those years enter the moderator, this ",
      "is not an independent held-out pretrend test."
    ),
    fmt_p(pretrend_omnibus$deal_wild_p)
  ),
  "",
  "Subgroup support and balance gates:",
  "",
  paste0(
    "- ", gates$sample, " / group ", gates$group,
    ": treated N=", gates$treated_inventors,
    ", effective deals=", fmt(gates$effective_deals, 1),
    ", max |SMD|=", fmt(gates$max_abs_smd),
    ", gate pass=", gates$gate_pass, "."
  ),
  "",
  "## Interpretation boundary",
  "",
  paste(
    "The moderator is a patent-based prediction of movement in the local",
    "technical status order. It does not observe actual authority, autonomy,",
    "influence, or perceived standing. Even a diagnostic-passing result is",
    "mechanism-consistent heterogeneity, not a direct mediation estimate."
  )
)
writeLines(
  report, file.path(out_dir, "relative_standing_results.md"),
  useBytes = TRUE
)

labels <- c(
  standing_primary = "Standing loss: primary",
  standing_productivity_horse_race = "Standing/productivity horse race",
  productive_3plus_positive_loss = "Positive loss, 3+ patents",
  kapoor_top20_sensitivity = "Kapoor--Lim top 20\\%"
)
table_rows <- results[results$Outcome == "patent_count", , drop = FALSE]
table_rows$label <- unname(labels[table_rows$Model])
table_rows$label[table_rows$Model == "standing_productivity_horse_race" &
                   table_rows$Term == "tx_loss"] <-
  "Standing gradient, horse race"
table_rows$label[table_rows$Model == "standing_productivity_horse_race" &
                   table_rows$Term == "tx_prod"] <-
  "Productivity gradient, horse race"
tex <- c(
  "\\begin{table}[!htbp]", "\\centering",
  "\\caption{Predicted Relative-Standing Loss and Inventor Patenting}",
  "\\label{tab:relative_standing}", "\\small",
  "\\begin{tabular}{lccc}", "\\toprule",
  "Specification & Estimate & 95\\% CI & Governing $p$ \\\\",
  "\\midrule",
  vapply(seq_len(nrow(table_rows)), function(i) sprintf(
    "%s & %.3f & [%.3f, %.3f] & %.3f \\\\",
    table_rows$label[i], table_rows$estimate[i], table_rows$ci_low[i],
    table_rows$ci_high[i], table_rows$governing_p[i]
  ), character(1)),
  "\\bottomrule", "\\end{tabular}",
  paste0(
    "\\begin{minipage}{0.94\\linewidth}\\footnotesize ",
    "\\textit{Notes:} Estimates use the certified Local Match v2 roster and ",
    "weights. The primary standing coefficient is the differential annual ATT ",
    "associated with a ten-percentage-point predicted loss of rank. Confidence ",
    "intervals use the wider of deal-level Webb wild-bootstrap and two-way ",
    "deal/inventor clustered inference. The 3+ patent and top-20 results are ",
    "secondary.\\end{minipage}"
  ),
  "\\end{table}"
)
writeLines(
  tex, file.path(out_dir, "relative_standing_table.tex"), useBytes = TRUE
)

report_manifest <- data.frame(
  design_hash = lmv2_relstand_hash(),
  results_sha256 = digest::digest(file = paths$results, algo = "sha256"),
  report_sha256 = digest::digest(
    file = file.path(out_dir, "relative_standing_results.md"), algo = "sha256"
  ),
  certification_pass = all(checks$pass),
  preperiod_trajectory_diagnostic_pass = preperiod_pass,
  preperiod_window_overlaps_moderator = TRUE,
  standing_balance_pass = balance_pass,
  conditional_standing_gradient_negative = horse_loss$estimate < 0,
  stringsAsFactors = FALSE
)
utils::write.csv(
  report_manifest, file.path(out_dir, "relative_standing_report_manifest.csv"),
  row.names = FALSE
)
message("Relative-standing results certified and reported.")
