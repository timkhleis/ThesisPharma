#!/usr/bin/env Rscript

# Explicitly exploratory DealSim analysis. The prospective P7 power gate chose
# Path U, so these estimates cannot be presented as the confirmatory inverted-U
# test. They describe the locked Local Match v2 deal-level contrasts, report
# the pre-specified terciles and functional forms, and retain the failed-gate
# label in every output.

options(stringsAsFactors = FALSE, scipen = 999)

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE
)
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib, .libPaths())))
for (pkg in c("DBI", "duckdb", "fixest", "ggplot2")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}

ROOT <- file.path(
  BASE, "output", "audit", "local_match_v2_1993_amendment"
)
GATE <- file.path(ROOT, "P7_DEALSIM_POWER_GATE")
OUT <- file.path(ROOT, "DEALSIM_EXPLORATORY_POSTGATE")
FIG <- file.path(OUT, "figures")
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)
write_csv <- function(x, name) {
  utils::write.csv(x, file.path(OUT, name), row.names = FALSE, na = "")
}

gate <- utils::read.csv(
  file.path(GATE, "dealsim_power_gate.csv"), stringsAsFactors = FALSE
)
if (nrow(gate) != 1L || gate$selected_path[[1L]] != "U" ||
    isTRUE(gate$tercile_power_gate_pass[[1L]])) {
  stop("Expected the certified failed DealSim power gate (Path U)")
}
assignment <- utils::read.csv(
  file.path(GATE, "dealsim_tercile_assignment.csv"),
  stringsAsFactors = FALSE
)
assignment <- assignment[
  assignment$eligible_dealsim & assignment$cohort %in% 1993:2010,
  c("deal_id", "cohort", "acquirer_group", "dealsim", "tercile",
    "treated_weight")
]
if (any(grepl("^999", assignment$acquirer_group))) {
  stop("Placeholder acquirer entered the DealSim assignment")
}

panel_glob <- gsub(
  "\\\\", "/", file.path(ROOT, "P6_BASE", "panel_matched", "*.parquet")
)
con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA memory_limit='9GB'")
DBI::dbExecute(con, "PRAGMA threads=8")
duckdb::duckdb_register(con, "dealsim_assignment", assignment)
on.exit(duckdb::duckdb_unregister(con, "dealsim_assignment"), add = TRUE)

deal_effects <- DBI::dbGetQuery(con, sprintf("
  WITH p AS (
    SELECT x.deal_id, x.cohort, x.arm, x.event_time, x.weight,
      x.patent_count, x.pqii_scaled
    FROM read_parquet('%s') x
    JOIN dealsim_assignment d USING (deal_id)
    WHERE x.cohort BETWEEN 1993 AND 2010
  ), ref AS (
    SELECT deal_id, arm, roster_row_id, patent_count AS patent_ref,
      pqii_scaled AS pqii_ref
    FROM read_parquet('%s')
    WHERE event_time=-1
  ), dy AS (
    SELECT p.deal_id, p.cohort, p.arm, p.event_time, p.weight,
      p.patent_count - r.patent_ref AS dy_patent,
      p.pqii_scaled - r.pqii_ref AS dy_pqii
    FROM (
      SELECT x.* FROM read_parquet('%s') x
      JOIN dealsim_assignment d USING (deal_id)
      WHERE x.cohort BETWEEN 1993 AND 2010
        AND x.event_time BETWEEN 1 AND 5
        AND x.pqii_scaled IS NOT NULL
    ) p
    JOIN ref r USING (deal_id, arm, roster_row_id)
    WHERE r.pqii_ref IS NOT NULL
  ), cells AS (
    SELECT deal_id, cohort, arm,
      SUM(weight * dy_patent) / SUM(weight) AS mean_dy_patent,
      SUM(weight * dy_pqii) / SUM(weight) AS mean_dy_pqii,
      SUM(weight) / 5.0 AS arm_mass
    FROM dy GROUP BY 1, 2, 3
  )
  SELECT t.deal_id, t.cohort,
    t.mean_dy_patent - c.mean_dy_patent AS patent_count_effect,
    t.mean_dy_pqii - c.mean_dy_pqii AS pqii_scaled_effect,
    t.arm_mass AS treated_mass
  FROM cells t JOIN cells c USING (deal_id, cohort)
  WHERE t.arm='treated' AND c.arm='control'
", panel_glob, panel_glob, panel_glob))
deal_effects <- merge(deal_effects, assignment, by = c("deal_id", "cohort"))
deal_effects$analysis_status <- "exploratory_after_failed_power_gate"
write_csv(deal_effects, "dealsim_deal_effects.csv")

wmean <- function(x, w) sum(x * w) / sum(w)
tercile_rows <- list()
for (outcome in c("patent_count_effect", "pqii_scaled_effect")) {
  for (tercile in c("low", "middle", "high")) {
    z <- deal_effects[deal_effects$tercile == tercile, ]
    b <- wmean(z[[outcome]], z$treated_mass)
    # HC1 intercept-only WLS at the deal level.
    m <- fixest::feols(
      stats::as.formula(paste0(outcome, " ~ 1")), data = z,
      weights = ~treated_mass, vcov = "hetero", notes = FALSE
    )
    se <- as.numeric(fixest::se(m)[[1L]])
    tercile_rows[[paste(outcome, tercile)]] <- data.frame(
      outcome = sub("_effect$", "", outcome), tercile = tercile,
      estimate = b, se_hc1 = se,
      ci_low = b - 1.96 * se, ci_high = b + 1.96 * se,
      nominal_deals = nrow(z),
      treated_mass = sum(z$treated_mass),
      status = "exploratory_after_failed_power_gate"
    )
  }
}
terciles <- do.call(rbind, tercile_rows)
write_csv(terciles, "dealsim_tercile_exploratory.csv")

quadratic_rows <- list()
spline_rows <- list()
prediction_rows <- list()
breaks <- as.numeric(stats::quantile(
  deal_effects$dealsim, c(1 / 3, 2 / 3), na.rm = TRUE, type = 7
))
grid <- data.frame(dealsim = seq(
  min(deal_effects$dealsim), max(deal_effects$dealsim), length.out = 100L
))
for (outcome in c("patent_count_effect", "pqii_scaled_effect")) {
  qmod <- fixest::feols(
    stats::as.formula(paste0(
      outcome, " ~ dealsim + I(dealsim^2)"
    )),
    data = deal_effects, weights = ~treated_mass,
    vcov = "hetero", notes = FALSE
  )
  qct <- as.data.frame(fixest::coeftable(qmod))
  qct$term <- rownames(qct)
  b1 <- stats::coef(qmod)[["dealsim"]]
  quadratic_term <- grep(
    "dealsim\\^2", names(stats::coef(qmod)), value = TRUE
  )
  if (length(quadratic_term) != 1L) stop("Quadratic DealSim term not found")
  b2 <- stats::coef(qmod)[[quadratic_term]]
  peak <- if (is.finite(b2) && b2 != 0) -b1 / (2 * b2) else NA_real_
  quadratic_rows[[outcome]] <- data.frame(
    outcome = sub("_effect$", "", outcome),
    linear = b1, quadratic = b2, estimated_turning_point = peak,
    turning_point_in_support = is.finite(peak) &&
      peak >= min(deal_effects$dealsim) && peak <= max(deal_effects$dealsim),
    nominal_deals = stats::nobs(qmod),
    status = "exploratory_after_failed_power_gate"
  )

  smod <- fixest::feols(
    stats::as.formula(paste0(
      outcome, " ~ splines::ns(dealsim, knots=c(",
      paste(format(breaks, scientific = FALSE, digits = 16), collapse = ","),
      "))"
    )),
    data = deal_effects, weights = ~treated_mass,
    vcov = "hetero", notes = FALSE
  )
  spline_rows[[outcome]] <- data.frame(
    outcome = sub("_effect$", "", outcome),
    knot_1 = breaks[[1L]], knot_2 = breaks[[2L]],
    nominal_deals = stats::nobs(smod),
    status = "exploratory_after_failed_power_gate"
  )
  pred_q <- stats::predict(qmod, newdata = grid)
  pred_s <- stats::predict(smod, newdata = grid)
  prediction_rows[[outcome]] <- rbind(
    data.frame(outcome = sub("_effect$", "", outcome),
               dealsim = grid$dealsim, model = "quadratic", estimate = pred_q),
    data.frame(outcome = sub("_effect$", "", outcome),
               dealsim = grid$dealsim, model = "natural_spline", estimate = pred_s)
  )
}
quadratic <- do.call(rbind, quadratic_rows)
spline <- do.call(rbind, spline_rows)
predictions <- do.call(rbind, prediction_rows)
write_csv(quadratic, "dealsim_quadratic_exploratory.csv")
write_csv(spline, "dealsim_spline_exploratory.csv")
write_csv(predictions, "dealsim_functional_form_predictions.csv")

plot_terciles <- terciles
plot_terciles$tercile <- factor(
  plot_terciles$tercile, levels = c("low", "middle", "high")
)
p <- ggplot2::ggplot(plot_terciles, ggplot2::aes(tercile, estimate)) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey55") +
  ggplot2::geom_errorbar(
    ggplot2::aes(ymin = ci_low, ymax = ci_high), width = 0.12
  ) +
  ggplot2::geom_point(size = 2) +
  ggplot2::facet_wrap(~outcome, scales = "free_y") +
  ggplot2::labs(
    x = "DealSim tercile", y = "Matched deal-level contrast",
    title = "Exploratory DealSim contrasts",
    subtitle = "The prospective power gate failed; intervals are descriptive"
  ) +
  ggplot2::theme_minimal(base_size = 10)
ggplot2::ggsave(
  file.path(FIG, "dealsim_terciles_exploratory.png"), p,
  width = 7.2, height = 4.4, dpi = 300, bg = "white"
)

cert <- data.frame(
  check = c(
    "prospective_gate_is_path_U", "confirmatory_att_not_claimed",
    "placeholder_acquirers_excluded", "all_three_terciles_present",
    "quadratic_and_spline_built"
  ),
  pass = c(
    gate$selected_path == "U" && !gate$tercile_power_gate_pass,
    all(deal_effects$analysis_status ==
          "exploratory_after_failed_power_gate"),
    all(assignment$eligible_dealsim),
    all(c("low", "middle", "high") %in% unique(assignment$tercile)),
    nrow(quadratic) == 2L && nrow(spline) == 2L
  ),
  note = c(
    gate$path_description, "no confirmatory p-value or release decision",
    "eligibility inherited from certified P7 assignment",
    paste(sort(unique(assignment$tercile)), collapse = ";"),
    paste("knots", paste(round(breaks, 6), collapse = ";"))
  )
)
write_csv(cert, "dealsim_exploratory_certification.csv")
message("Exploratory DealSim package written to: ", OUT)
if (!all(cert$pass)) quit(status = 1L)
