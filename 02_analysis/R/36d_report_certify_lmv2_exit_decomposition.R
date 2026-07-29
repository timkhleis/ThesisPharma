# ============================================================================
# 36d_report_certify_lmv2_exit_decomposition.R
# Thesis-facing exhibits, manifest, and fail-closed certification.
# ============================================================================

if (!exists("lmv2_exit_config")) {
  source(file.path(
    "02_analysis", "R", "36a_lmv2_exit_decomposition_config.R"))
}

lmv2_exit_tex_escape <- function(x) {
  x <- gsub("_", "\\\\_", x, fixed = TRUE)
  x <- gsub("%", "\\\\%", x, fixed = TRUE)
  x
}

lmv2_exit_fmt <- function(x, digits = 3L) {
  ifelse(is.finite(x), formatC(x, digits = digits, format = "f"), "")
}

lmv2_exit_write_plot <- function(path, width, height, draw) {
  if (grepl("\\.pdf$", path)) {
    grDevices::pdf(path, width = width, height = height)
  } else {
    grDevices::png(
      path, width = width, height = height, units = "in", res = 220)
  }
  on.exit(grDevices::dev.off(), add = TRUE)
  draw()
  invisible(path)
}

lmv2_exit_report_certify <- function(
    config = lmv2_exit_config(), smoke = FALSE) {
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Missing package: digest")
  }
  required_names <- c(
    "endpoint_construction_audit.csv",
    "endpoint_buffer_audit.csv",
    "exit_panel_certification.csv",
    "exit_decomposition_fixtures.csv",
    "exit_decomposition_components.csv",
    "exit_decomposition_factor_means.csv",
    "exit_decomposition_event_weights.csv",
    "exit_raw_reference_sensitivity.csv",
    "exit_two_vs_three_factor_reconciliation_long.csv",
    "exit_two_vs_three_factor_totals.csv",
    "exit_dynamic_att.csv",
    "exit_post_att.csv",
    "exit_reference_support_diagnostic.csv",
    "exit_certified_total_reconciliation.csv")
  required <- file.path(config$output_dir, required_names)
  if (any(!file.exists(required))) {
    stop("Missing P8 result: ",
         paste(required[!file.exists(required)], collapse = ", "))
  }
  read <- function(name) {
    utils::read.csv(
      file.path(config$output_dir, name),
      stringsAsFactors = FALSE, check.names = FALSE)
  }
  endpoint <- read("endpoint_construction_audit.csv")
  panel <- read("exit_panel_certification.csv")
  fixture <- read("exit_decomposition_fixtures.csv")
  components <- read("exit_decomposition_components.csv")
  weights <- read("exit_decomposition_event_weights.csv")
  totals <- read("exit_two_vs_three_factor_totals.csv")
  dynamic <- read("exit_dynamic_att.csv")
  reference <- read("exit_reference_support_diagnostic.csv")
  certified <- read("exit_certified_total_reconciliation.csv")

  weight_sum <- aggregate(
    q_event ~ population + sample + event_time,
    data = unique(weights[c(
      "population", "sample", "cohort", "event_time", "q_event")]),
    FUN = sum)
  reference_gap <- reference[
    reference$arm == "treated_minus_control", , drop = FALSE]
  checks <- data.frame(
    check = c(
      "endpoint_construction_passes",
      "joined_panel_passes",
      "all_fixtures_pass",
      "component_identities_exact",
      "two_and_three_factor_totals_match",
      "certified_totals_reproduced",
      "event_weights_sum_to_one",
      "dynamic_reference_is_zero",
      "reference_survival_gap_is_later_patent_gap",
      "primary_headline_sample_present",
      "no_left_mislabel"),
    pass = c(
      nrow(endpoint) == 1L && all(endpoint$pass),
      nrow(panel) == 1L && all(panel$pass),
      nrow(fixture) >= 5L && all(fixture$pass),
      all(components$identity_error < 1e-10),
      all(abs(totals$total_difference) < 1e-10),
      all(abs(certified$difference) < 1e-10),
      all(abs(weight_sum$q_event - 1) < 1e-10),
      all(dynamic$estimate[dynamic$event_time == -1L] == 0),
      all(abs(
        reference_gap$survival -
          reference_gap$later_patent_only -
          reference_gap$active_reference) < 1e-10),
      if (smoke) {
        any(grepl("^smoke_", components$sample))
      } else {
        any(
          components$population == "full_cohort" &
            components$sample == config$primary_sample)
      },
      !any(grepl(
        "\\bleft\\b", tolower(c(
          components$endpoint_definition,
          components$component))))),
    detail = c(
      endpoint$pass[[1L]], panel$pass[[1L]],
      sum(!fixture$pass),
      max(components$identity_error),
      max(abs(totals$total_difference)),
      max(abs(certified$difference)),
      max(abs(weight_sum$q_event - 1)),
      max(abs(dynamic$estimate[dynamic$event_time == -1L])),
      max(abs(
        reference_gap$survival -
          reference_gap$later_patent_only -
          reference_gap$active_reference)),
      paste(unique(components$sample), collapse = ";"),
      "patenting exit is distinct from firm leaving"),
    stringsAsFactors = FALSE)
  if (!all(checks$pass)) {
    lmv2_exit_write_csv(
      checks,
      file.path(config$output_dir, "exit_decomposition_certification.csv"))
    stop(
      "P8 certification failed: ",
      paste(checks$check[!checks$pass], collapse = ", "))
  }

  primary_sample <- if (smoke) {
    unique(components$sample)[[1L]]
  } else {
    config$primary_sample
  }
  plot_dynamic <- dynamic[
    dynamic$population == "full_cohort" &
      dynamic$sample == primary_sample, ]
  plot_components <- components[
    components$population == "full_cohort" &
      components$sample == primary_sample &
      components$component != "total", ]
  figure_dir <- file.path(config$output_dir, "figures")
  dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
  for (ext in c("pdf", "png")) {
    lmv2_exit_write_plot(
      file.path(figure_dir, paste0("figure_exit_event_study_full.", ext)),
      7, 4.5, function() {
        graphics::par(mar = c(4, 4.2, 1.5, 1))
        graphics::plot(
          plot_dynamic$event_time, 100 * plot_dynamic$estimate,
          type = "b", pch = 19, xlab = "Event time",
          ylab = "Patenting exit contrast (percentage points)",
          main = "")
        graphics::segments(
          plot_dynamic$event_time, 100 * plot_dynamic$ci_low,
          plot_dynamic$event_time, 100 * plot_dynamic$ci_high)
        graphics::abline(h = 0, lty = 2, col = "gray45")
      })
    lmv2_exit_write_plot(
      file.path(
        figure_dir, paste0("figure_exit_decomposition_full.", ext)),
      7, 4.5, function() {
        labels <- c(
          cessation = "Patenting\ncessation",
          active_given_survival = "Active years\namong survivors",
          patents_per_active_year = "Patents per\nactive year")
        color <- ifelse(plot_components$estimate < 0, "#A33A2B", "#2F6B4F")
        graphics::par(mar = c(5.5, 4.2, 1.5, 1))
        graphics::barplot(
          plot_components$estimate,
          names.arg = labels[plot_components$component],
          col = color, border = NA,
          ylab = "Patents per inventor-year", las = 1)
        graphics::abline(h = 0, col = "gray35")
      })
  }

  table_rows <- components[
    components$sample == primary_sample &
      components$population %in%
        c("full_cohort", "initially_retained_broad"), ]
  label <- c(
    cessation = "Earlier cessation of observed patenting",
    active_given_survival = "Fewer active years among survivors",
    patents_per_active_year = "Fewer patents in active years",
    total = "Total patent-count ATT")
  tex <- c(
    "\\begin{tabular}{lrrrr}",
    "\\toprule",
    "Component & Annual & 95\\% CI & Cumulative & Share \\\\",
    "\\midrule")
  for (population in unique(table_rows$population)) {
    tex <- c(tex, paste0(
      "\\multicolumn{5}{l}{\\textit{",
      lmv2_exit_tex_escape(population), "}} \\\\"))
    z <- table_rows[table_rows$population == population, ]
    for (i in seq_len(nrow(z))) {
      ci <- if (is.finite(z$ci_low[[i]])) {
        paste0(
          "[", lmv2_exit_fmt(z$ci_low[[i]]), ", ",
          lmv2_exit_fmt(z$ci_high[[i]]), "]")
      } else {
        ""
      }
      tex <- c(tex, paste0(
        label[[z$component[[i]]]], " & ",
        lmv2_exit_fmt(z$estimate[[i]]), " & ", ci, " & ",
        lmv2_exit_fmt(z$cumulative_post_window_patents[[i]]), " & ",
        lmv2_exit_fmt(100 * z$share_of_total[[i]], 1L), "\\% \\\\"))
    }
    tex <- c(tex, "\\addlinespace")
  }
  tex <- c(
    tex, "\\bottomrule", "\\end{tabular}",
    "% Broad initially-retained cessation is an audit reconciliation only.")
  writeLines(
    tex,
    file.path(config$output_dir, "table_exit_decomposition.tex"),
    useBytes = TRUE)

  buffer <- components[
    components$population == "full_cohort" &
      components$component %in% c("cessation", "total"), ]
  buffer_tex <- c(
    "\\begin{tabular}{lrr}",
    "\\toprule",
    "Sample & Cessation contribution & Total ATT \\\\",
    "\\midrule")
  for (sample in unique(buffer$sample)) {
    z <- buffer[buffer$sample == sample, ]
    buffer_tex <- c(buffer_tex, paste0(
      lmv2_exit_tex_escape(sample), " & ",
      lmv2_exit_fmt(z$estimate[z$component == "cessation"]), " & ",
      lmv2_exit_fmt(z$estimate[z$component == "total"]), " \\\\"))
  }
  buffer_tex <- c(buffer_tex, "\\bottomrule", "\\end{tabular}")
  writeLines(
    buffer_tex,
    file.path(config$output_dir, "table_exit_buffer_sensitivity.tex"),
    useBytes = TRUE)

  reconciliation_tex <- c(
    "\\begin{tabular}{lrrr}",
    "\\toprule",
    "Population/sample & Three-factor total & Two-factor total & Difference \\\\",
    "\\midrule")
  for (i in seq_len(nrow(totals))) {
    reconciliation_tex <- c(reconciliation_tex, paste0(
      lmv2_exit_tex_escape(paste(
        totals$population[[i]], totals$sample[[i]], sep = ": ")), " & ",
      lmv2_exit_fmt(totals$total_three[[i]]), " & ",
      lmv2_exit_fmt(totals$total_two[[i]]), " & ",
      formatC(totals$total_difference[[i]], digits = 2, format = "e"),
      " \\\\"))
  }
  reconciliation_tex <- c(
    reconciliation_tex, "\\bottomrule", "\\end{tabular}")
  writeLines(
    reconciliation_tex,
    file.path(config$output_dir, "table_exit_reconciliation.tex"),
    useBytes = TRUE)

  lmv2_exit_write_csv(
    checks,
    file.path(config$output_dir, "exit_decomposition_certification.csv"))
  artifact_paths <- list.files(
    config$output_dir, recursive = TRUE, full.names = TRUE)
  artifact_paths <- artifact_paths[file.info(artifact_paths)$isdir %in% FALSE]
  artifact_paths <- artifact_paths[
    basename(artifact_paths) != "exit_decomposition_manifest.csv" &
      !grepl("\\.log$", artifact_paths, ignore.case = TRUE)]
  manifest <- data.frame(
    artifact = basename(artifact_paths),
    path = normalizePath(
      artifact_paths, winslash = "/", mustWork = TRUE),
    sha256 = vapply(
      artifact_paths, lmv2_exit_sha256, character(1)),
    execution_hash = lmv2_exit_execution_hash(config),
    stringsAsFactors = FALSE)
  lmv2_exit_write_csv(
    manifest,
    file.path(config$output_dir, "exit_decomposition_manifest.csv"))
  invisible(checks)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  smoke <- "--smoke" %in% args
  output_arg <- sub(
    "^--output-dir=", "", grep(
      "^--output-dir=", args, value = TRUE))
  config <- lmv2_exit_config(
    output_dir = if (length(output_arg)) output_arg[[1L]] else NULL)
  lmv2_exit_report_certify(config, smoke = smoke)
}
