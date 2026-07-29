# Build tables, figures, and magnitude diagnostics for certified S4 results.

source(file.path("02_analysis", "R", "28a_lmv2_p5b_s4_config.R"))
config <- lmv2_p5b_s4_config()
source(file.path("02_analysis", "R", "00_utils.R"))
use_project_library()
shared_lib <- file.path(
  Sys.getenv("USERPROFILE"), "Documents", "Thesis", ".r_libs")
if (dir.exists(shared_lib)) {
  .libPaths(unique(c(shared_lib, .libPaths())))
}
required_packages <- c("DBI", "duckdb", "ggplot2")
for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Missing package: ", pkg)
  }
}
source(file.path(
  config$p6_r_dir, "00_lmv2_visual_style.R"))

certification <- utils::read.csv(
  file.path(config$output_dir, "s4_certification.csv"),
  stringsAsFactors = FALSE)
if (!nrow(certification) || !all(certification$pass)) {
  stop("S4 results must be certified before summarization")
}
dynamic <- utils::read.csv(
  file.path(config$output_dir, "s4_event_study_dynamic.csv"),
  stringsAsFactors = FALSE)
pretrend <- utils::read.csv(
  file.path(config$output_dir, "s4_joint_pretrend_tests.csv"),
  stringsAsFactors = FALSE)
headline <- utils::read.csv(
  file.path(config$output_dir, "s4_headline_post_att.csv"),
  stringsAsFactors = FALSE)

assets_dir <- file.path(config$output_dir, "reporting")
dir.create(assets_dir, recursive = TRUE, showWarnings = FALSE)
write_csv <- function(x, name) {
  utils::write.csv(
    x, file.path(assets_dir, name), row.names = FALSE, na = "")
}

annual <- headline[
  headline$summary == "average_annual_t1_to_t5", ]
governing <- annual[annual$governing, ]
governing <- governing[order(
  governing$outcome, governing$sample,
  match(governing$spec, config$production_specs)), ]
write_csv(governing, "s4_governing_results.csv")

primary <- annual[
  annual$spec == config$production_specs[[1L]], ]
primary <- primary[order(
  primary$outcome, primary$sample, primary$inference), ]
write_csv(primary, "s4_primary_inference_comparison.csv")

# Thesis reporting decision made in S5: use two-way deal/inventor clustering
# as primary and retain the deal wild bootstrap as a conservative sensitivity.
two_way_reporting <- annual[
  annual$inference == "two_way_deal_inventor", ]
two_way_reporting <- two_way_reporting[order(
  two_way_reporting$outcome, two_way_reporting$sample,
  match(two_way_reporting$spec, config$production_specs)), ]
write_csv(two_way_reporting, "s4_two_way_primary_results.csv")

loyo <- rbind(
  dynamic[
    dynamic$spec == "primary_count_active_scale_loyo_m3" &
      dynamic$event_time == -3, ],
  dynamic[
    dynamic$spec == "primary_count_active_scale_loyo_m2" &
      dynamic$event_time == -2, ])
loyo$equivalence_band_low <- -0.05
loyo$equivalence_band_high <- 0.05
loyo$ci_contained_in_equivalence_band <-
  loyo$ci_low >= -0.05 & loyo$ci_high <= 0.05
loyo <- merge(
  loyo,
  pretrend[c("spec", "sample", "outcome", "p_value")],
  by = c("spec", "sample", "outcome"),
  suffixes = c("", "_joint_pretrend"),
  all.x = TRUE)
write_csv(loyo, "s4_loyo_heldout_diagnostics.csv")

# Recover weighted outcome levels to express the first-difference estimate
# relative to the observed pre-period and matched post-period counterfactual.
panel_files <- sort(list.files(
  config$base_panel_dir,
  pattern = "^lmv2_event_panel_c[0-9]+\\.parquet$",
  full.names = TRUE))
primary_weights <- file.path(
  config$s3$output_dir, "s3_primary_weights.parquet")
sql_string <- function(x) {
  paste0("'", gsub("'", "''", gsub("\\\\", "/", x)), "'")
}
panel_sql <- paste0(
  "read_parquet([",
  paste(vapply(panel_files, sql_string, character(1)), collapse = ","),
  "])")
con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=8")
DBI::dbExecute(con, "PRAGMA memory_limit='5GB'")
levels <- DBI::dbGetQuery(con, sprintf("
  WITH p AS (
    SELECT
      roster_row_id, CAST(cohort AS INTEGER) cohort,
      CAST(deal_id AS INTEGER) deal_id, arm, CAST(codinv AS BIGINT) codinv,
      CAST(focal_group_1 AS BIGINT) focal_group_1,
      CAST(event_time AS INTEGER) event_time,
      CAST(patent_count AS DOUBLE) patent_count,
      CAST(active_patenting AS DOUBLE) active_patenting
    FROM %s
  ),
  b AS (
    SELECT roster_row_id,cohort,deal_id,arm,codinv,focal_group_1
    FROM p WHERE event_time=-1
  ),
  w AS (
    SELECT * FROM read_parquet(%s)
  ),
  m AS (
    SELECT b.roster_row_id,w.final_weight
    FROM w JOIN b
      ON w.cohort=b.cohort AND w.deal_id=b.deal_id
     AND w.codinv=b.codinv AND b.arm='treated'
    WHERE w.treated=1
    UNION ALL
    SELECT b.roster_row_id,w.final_weight
    FROM w JOIN b
      ON w.cohort=b.cohort AND w.deal_id=b.deal_id
     AND w.codinv=b.codinv AND w.control_group=b.focal_group_1
     AND b.arm='control'
    WHERE w.treated=0
  ),
  long AS (
    SELECT
      p.cohort,p.event_time,p.arm,'patent_count' outcome,
      p.patent_count AS outcome_value,
      m.final_weight AS analysis_weight
    FROM p JOIN m USING(roster_row_id)
    UNION ALL
    SELECT
      p.cohort,p.event_time,p.arm,'active_patenting' outcome,
      p.active_patenting AS outcome_value,
      m.final_weight AS analysis_weight
    FROM p JOIN m USING(roster_row_id)
  )
  SELECT
    cohort,event_time,arm,outcome,
    SUM(outcome_value*analysis_weight)/SUM(analysis_weight) weighted_mean,
    SUM(analysis_weight) weight_mass
  FROM long
  GROUP BY cohort,event_time,arm,outcome
", panel_sql, sql_string(primary_weights)))

summarize_magnitude <- function(sample_id, cohorts, outcome) {
  x <- levels[
    levels$cohort %in% cohorts & levels$outcome == outcome, ]
  treated_mass <- x[
    x$event_time == -1 & x$arm == "treated",
    c("cohort", "weight_mass")]
  treated_mass$q <- treated_mass$weight_mass / sum(treated_mass$weight_mass)
  wide <- reshape(
    x[c("cohort", "event_time", "arm", "weighted_mean")],
    idvar = c("cohort", "event_time"), timevar = "arm",
    direction = "wide")
  names(wide) <- sub("^weighted_mean\\.", "", names(wide))
  reference <- wide[wide$event_time == -1, c("cohort", "treated", "control")]
  names(reference)[2:3] <- c("treated_ref", "control_ref")
  wide <- merge(wide, reference, by = "cohort")
  wide <- merge(wide, treated_mass[c("cohort", "q")], by = "cohort")
  post <- wide[wide$event_time %in% config$post_window, ]
  pre <- wide[wide$event_time %in% -5:-1, ]
  post$att <- (post$treated - post$treated_ref) -
    (post$control - post$control_ref)
  post$counterfactual <- post$treated_ref +
    (post$control - post$control_ref)
  weighted_horizon_mean <- function(value) {
    mean(vapply(
      config$post_window,
      function(e) sum(post$q[post$event_time == e] *
                        value[post$event_time == e]),
      numeric(1)))
  }
  pre_mean <- mean(vapply(
    -5:-1,
    function(e) sum(pre$q[pre$event_time == e] *
                      pre$treated[pre$event_time == e]),
    numeric(1)))
  att <- weighted_horizon_mean(post$att)
  counterfactual <- weighted_horizon_mean(post$counterfactual)
  observed <- weighted_horizon_mean(post$treated)
  data.frame(
    sample = sample_id,
    outcome = outcome,
    observed_treated_post_mean = observed,
    matched_counterfactual_post_mean = counterfactual,
    average_annual_att = att,
    cumulative_five_year_att = 5 * att,
    average_pre_treatment_mean = pre_mean,
    att_share_of_counterfactual = att / counterfactual,
    att_share_of_pre_treatment_mean = att / pre_mean,
    stringsAsFactors = FALSE)
}
magnitude <- do.call(rbind, unlist(
  lapply(names(config$samples), function(sample_id) {
    lapply(config$outcomes, function(outcome) {
      summarize_magnitude(
        sample_id, config$samples[[sample_id]], outcome)
    })
  }), recursive = FALSE))

primary_point <- primary[
  primary$inference == "two_way_deal_inventor",
  c("sample", "outcome", "estimate")]
magnitude <- merge(
  magnitude, primary_point,
  by = c("sample", "outcome"), all.x = TRUE)
magnitude$point_estimator_gap <-
  magnitude$average_annual_att - magnitude$estimate
if (max(abs(magnitude$point_estimator_gap)) > 1e-8) {
  stop("Magnitude decomposition does not reproduce the certified S4 estimate")
}
magnitude$estimate <- NULL
write_csv(magnitude, "s4_primary_magnitude.csv")

# Weighted patent-count paths clarify that the positive t=0 DiD coefficient
# reflects a larger transition-year decline among controls, not an increase
# in treated inventors' patenting.
patent_levels <- levels[
  levels$outcome == "patent_count" &
    levels$cohort %in% config$samples$full_1994_2010, ]
path_mass <- patent_levels[
  patent_levels$event_time == -1 &
    patent_levels$arm == "treated",
  c("cohort", "weight_mass")]
path_mass$cohort_weight <-
  path_mass$weight_mass / sum(path_mass$weight_mass)
patent_levels <- merge(
  patent_levels, path_mass[c("cohort", "cohort_weight")],
  by = "cohort")
patent_levels$weighted_component <-
  patent_levels$weighted_mean * patent_levels$cohort_weight
patent_paths <- stats::aggregate(
  weighted_component ~ event_time + arm,
  data = patent_levels, FUN = sum)
names(patent_paths)[names(patent_paths) == "weighted_component"] <-
  "weighted_mean"
patent_paths$series <- ifelse(
  patent_paths$arm == "treated",
  "Initially retained treated", "Retained controls")
write_csv(patent_paths, "s4_primary_weighted_patent_paths.csv")

# Primary event-study plot.
plot_dynamic <- dynamic[
  dynamic$spec == config$production_specs[[1L]] &
    dynamic$sample == "full_1994_2010", ]
plot_dynamic$outcome_label <- ifelse(
  plot_dynamic$outcome == "patent_count",
  "A. Annual patent count",
  "B. Probability of patenting")
transition_facets <- unique(plot_dynamic["outcome_label"])
transition_facets$xmin <- -0.5
transition_facets$xmax <- 0.5
transition_facets$ymin <- -Inf
transition_facets$ymax <- Inf
event_plot <- ggplot2::ggplot(
  plot_dynamic,
  ggplot2::aes(x = event_time, y = estimate)) +
  ggplot2::geom_rect(
    data = transition_facets,
    ggplot2::aes(
      xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
    inherit.aes = FALSE, fill = LMV2_COLOURS["pale_blue"],
    alpha = 0.55) +
  ggplot2::geom_hline(
    yintercept = 0, colour = LMV2_COLOURS["mid_grey"],
    linewidth = 0.4) +
  ggplot2::geom_vline(
    xintercept = 0, colour = LMV2_COLOURS["mid_grey"],
    linewidth = 0.45) +
  ggplot2::geom_ribbon(
    ggplot2::aes(ymin = ci_low, ymax = ci_high),
    fill = LMV2_COLOURS["pale_sage"], alpha = 0.75) +
  ggplot2::geom_line(
    colour = LMV2_COLOURS["forest"], linewidth = 0.8) +
  ggplot2::geom_point(
    colour = LMV2_COLOURS["forest"], size = 1.9) +
  ggplot2::geom_point(
    data = plot_dynamic[plot_dynamic$event_time == 0, ],
    shape = 21, fill = LMV2_COLOURS["white"],
    colour = LMV2_COLOURS["brick"], size = 2.5,
    stroke = 0.8) +
  ggplot2::facet_wrap(
    ~outcome_label, scales = "free_y", ncol = 1) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::labs(
    title = "Initially retained inventors after acquisition",
    subtitle = paste(
      "Shaded t = 0 is the deal-year transition and is excluded from",
      "the t = +1,...,+5 headline ATT"),
    x = "Event time", y = "Difference relative to t = -1",
    caption = paste0(
      "The hollow point marks the transition-year contrast; ",
      "95% two-way deal/inventor intervals.\n",
      "All five pre-period outcomes are balanced in the headline design.")) +
  lmv2_theme(base_size = 10.5, legend_position = "none")
lmv2_save_figure(
  event_plot,
  file.path(assets_dir, "figure_s4_primary_event_study"),
  width = 7.4, height = 6.5)

# Supervisor-facing patent figure: levels first, then the DiD contrast. This
# prevents a relative t=0 coefficient from being mistaken for a level increase.
path_panel <- "A. Weighted patent-count levels"
did_panel <- "B. Difference relative to t = -1"
patent_paths$panel <- path_panel
patent_dynamic <- plot_dynamic[
  plot_dynamic$outcome == "patent_count", ]
patent_dynamic$panel <- did_panel
transition_panels <- data.frame(
  panel = c(path_panel, did_panel),
  xmin = -0.5, xmax = 0.5, ymin = -Inf, ymax = Inf,
  stringsAsFactors = FALSE)
supervisor_plot <- ggplot2::ggplot() +
  ggplot2::geom_rect(
    data = transition_panels,
    ggplot2::aes(
      xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
    inherit.aes = FALSE, fill = LMV2_COLOURS["pale_blue"],
    alpha = 0.55) +
  ggplot2::geom_hline(
    data = data.frame(panel = did_panel),
    ggplot2::aes(yintercept = 0),
    colour = LMV2_COLOURS["mid_grey"], linewidth = 0.4) +
  ggplot2::geom_vline(
    xintercept = 0, colour = LMV2_COLOURS["mid_grey"],
    linewidth = 0.45) +
  ggplot2::geom_line(
    data = patent_paths,
    ggplot2::aes(
      x = event_time, y = weighted_mean,
      colour = series, linetype = series),
    linewidth = 0.8) +
  ggplot2::geom_point(
    data = patent_paths,
    ggplot2::aes(
      x = event_time, y = weighted_mean,
      colour = series, shape = series),
    size = 1.9) +
  ggplot2::geom_ribbon(
    data = patent_dynamic,
    ggplot2::aes(
      x = event_time, ymin = ci_low, ymax = ci_high),
    fill = LMV2_COLOURS["pale_sage"], alpha = 0.75) +
  ggplot2::geom_line(
    data = patent_dynamic,
    ggplot2::aes(x = event_time, y = estimate),
    colour = LMV2_COLOURS["forest"], linewidth = 0.8) +
  ggplot2::geom_point(
    data = patent_dynamic[patent_dynamic$event_time != 0, ],
    ggplot2::aes(x = event_time, y = estimate),
    colour = LMV2_COLOURS["forest"], size = 1.9) +
  ggplot2::geom_point(
    data = patent_dynamic[patent_dynamic$event_time == 0, ],
    ggplot2::aes(x = event_time, y = estimate),
    shape = 21, fill = LMV2_COLOURS["white"],
    colour = LMV2_COLOURS["brick"], size = 2.7,
    stroke = 0.8) +
  ggplot2::facet_wrap(~panel, scales = "free_y", ncol = 1) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::scale_colour_manual(values = c(
    "Initially retained treated" = unname(LMV2_COLOURS["forest"]),
    "Retained controls" = unname(LMV2_COLOURS["slate_blue"]))) +
  ggplot2::scale_linetype_manual(values = c(
    "Initially retained treated" = "solid",
    "Retained controls" = "longdash")) +
  ggplot2::scale_shape_manual(values = c(
    "Initially retained treated" = 16,
    "Retained controls" = 17)) +
  ggplot2::labs(
    title = "The positive deal-year contrast is not a patenting increase",
    subtitle = paste(
      "Both groups decline at t = 0, but retained controls decline more;",
      "the headline ATT begins at t = +1"),
    x = "Event time", y = NULL,
    caption = paste0(
      "Shading marks the deal-year transition. Panel B reports 95% ",
      "two-way deal/inventor intervals.\n",
      "The deal year is excluded from the headline ATT over ",
      "t = +1,...,+5.")) +
  lmv2_theme(base_size = 10.5, legend_position = "bottom")
lmv2_save_figure(
  supervisor_plot,
  file.path(assets_dir, "figure_s4_patent_paths_and_event_study"),
  width = 7.4, height = 6.5)

# Forest plot of the frozen patent-count specifications.
forest <- two_way_reporting[
  two_way_reporting$outcome == "patent_count" &
    two_way_reporting$sample == "full_1994_2010", ]
spec_labels <- c(
  primary_count_active_scale = "Headline",
  primary_count_active_scale_loyo_m3 = "LOYO t = -3",
  primary_count_active_scale_loyo_m2 = "LOYO t = -2",
  route_consistent_count_active_scale = "Route-consistent",
  raw_unmixed_count_active_scale = "Raw-unmixed",
  timing_t2_count_active_scale = "Retention from t = +2")
forest$label <- factor(
  unname(spec_labels[forest$spec]),
  levels = rev(unname(spec_labels[config$production_specs])))
forest_plot <- ggplot2::ggplot(
  forest,
  ggplot2::aes(y = label, x = estimate)) +
  ggplot2::geom_vline(
    xintercept = 0, colour = LMV2_COLOURS["mid_grey"],
    linewidth = 0.45) +
  ggplot2::geom_errorbar(
    ggplot2::aes(xmin = ci_low, xmax = ci_high),
    width = 0.18, orientation = "y",
    colour = LMV2_COLOURS["slate_blue"], linewidth = 0.7) +
  ggplot2::geom_point(
    colour = LMV2_COLOURS["forest"], size = 2.2) +
  ggplot2::labs(
    title = "The negative stayer contrast is stable across specifications",
    subtitle = paste(
      "Average annual patent-count contrast, t = +1,...,+5;",
      "two-way deal/inventor 95% interval"),
    x = "Patents per inventor-year", y = NULL,
    caption = paste(
      "The deal-level wild bootstrap remains a conservative sensitivity.",
      "The result conditions on observed initial retention.")) +
  lmv2_theme(base_size = 10.5, legend_position = "none")
lmv2_save_figure(
  forest_plot,
  file.path(assets_dir, "figure_s4_patent_sensitivity"),
  width = 7.4, height = 4.7)

message("S4 reporting assets written to ", assets_dir)
