if (!exists("lmv2_recurrent_config")) {
  source(file.path("02_analysis", "R",
                   "38a_lmv2_recurrent_inventor_config_build.R"))
}
if (!exists("lmv2_exit_write_plot")) {
  source(file.path("02_analysis", "R",
                   "36d_report_certify_lmv2_exit_decomposition.R"))
}

lmv2_estimate_recurrent_inventors <- function(
    config = lmv2_recurrent_config(), smoke = FALSE) {
  lmv2_exit_load_runtime(config)
  required <- c(
    config$recurrent_weights, config$endpoint_path,
    file.path(config$output_dir, "recurrent_certification.csv"))
  if (any(!file.exists(required))) {
    stop("Missing recurrent-inventor input: ",
         paste(required[!file.exists(required)], collapse = ", "))
  }
  gates <- utils::read.csv(
    file.path(config$output_dir, "recurrent_certification.csv"),
    stringsAsFactors = FALSE)
  production_gate_pass <- all(gates$pass)
  status <- data.frame(
    analysis = "recurrent_predeal_inventors",
    definition = "at_least_two_active_patenting_years_in_t_minus_5_to_t_minus_1",
    production_gate_pass = production_gate_pass,
    estimated = smoke || production_gate_pass,
    status = if (smoke || production_gate_pass) {
      if (production_gate_pass) "estimated" else "smoke_only_gate_override"
    } else "omitted_failed_prespecified_balance_or_ess_gate",
    stringsAsFactors = FALSE)
  lmv2_exit_write_csv(
    status, file.path(config$output_dir, "recurrent_estimation_status.csv"))
  if (!status$estimated[[1L]]) {
    writeLines(
      c(
        "The recurrent-inventor companion decomposition was not estimated.",
        "The pre-specified balance/ESS gates did not all pass."),
      file.path(config$output_dir, "RECURRENT_OMITTED.txt"),
      useBytes = TRUE)
    return(invisible(status))
  }
  set.seed(config$bootstrap$seed)
  dqrng::dqset.seed(config$bootstrap$seed)
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(
    con, sprintf("PRAGMA threads=%d", config$execution$threads))
  DBI::dbExecute(
    con, sprintf("PRAGMA memory_limit=%s",
                 lmv2_exit_sql_string(config$execution$memory_limit)))
  panel_checks <- lmv2_exit_prepare_panels(config, con, smoke)
  DBI::dbExecute(con, sprintf("
    CREATE TEMP TABLE recurrent_exit_panel AS
    SELECT e.* EXCLUDE (weight), w.final_weight AS weight
    FROM exit_panel e
    JOIN read_parquet(%s) w USING (roster_row_id)
  ", lmv2_exit_sql_string(config$recurrent_weights)))
  panel <- lmv2_exit_extract_panel(con, "recurrent_exit_panel")
  cohorts <- sort(unique(panel$cohort))
  if (!smoke) cohorts <- intersect(cohorts, 1994:2010)
  sample <- if (smoke) {
    paste0("smoke_", min(cohorts), "_", max(cohorts), "_t1_t5")
  } else "headline_1994_2010_t1_t5"
  decomp <- lmv2_estimate_exit_decomposition(
    panel, cohorts, 1:5, sample, "recurrent_predeal_inventors",
    survival_col = "survival",
    endpoint_definition = "global_last_patent_year_capped_2015",
    active_ess_floor = config$active_ess_floor)
  direct <- lmv2_exit_dynamic_contrast(
    panel, cohorts, 1:5, sample, "recurrent_predeal_inventors",
    bootstrap_reps = if (smoke) config$bootstrap$smoke
    else config$bootstrap$production,
    run_wild = TRUE)
  reference <- lmv2_exit_reference_support(
    panel, cohorts, sample, "recurrent_predeal_inventors")
  components <- decomp$components
  checks <- data.frame(
    check = c(
      "source_panel_passes", "recurrent_weight_join_unique",
      "component_identity_exact", "event_weights_sum_to_one",
      "reference_is_zero"),
    pass = c(
      isTRUE(panel_checks$pass[[1L]]),
      nrow(panel) ==
        data.table::uniqueN(panel[, .(roster_row_id, event_time)]),
      all(components$identity_error < 1e-10),
      all(abs(decomp$weights[
        , .(weight_sum = sum(q_event)), by = event_time]$weight_sum -
          1) < 1e-10),
      all(direct$dynamic$estimate[
        direct$dynamic$event_time == -1L] == 0)),
    stringsAsFactors = FALSE)
  if (!all(checks$pass)) {
    lmv2_exit_write_csv(
      checks, file.path(config$output_dir, "recurrent_result_certification.csv"))
    stop("Recurrent-inventor result certification failed")
  }
  artifacts <- list(
    recurrent_decomposition_components = components,
    recurrent_decomposition_factor_means = decomp$factor_means,
    recurrent_event_weights = decomp$weights,
    recurrent_raw_reference_sensitivity = decomp$raw,
    recurrent_two_factor_reconciliation = decomp$two_factor,
    recurrent_exit_dynamic_att = direct$dynamic,
    recurrent_exit_post_att = direct$headline,
    recurrent_reference_support = reference,
    recurrent_result_certification = checks)
  for (nm in names(artifacts)) {
    lmv2_exit_write_csv(
      artifacts[[nm]], file.path(config$output_dir, paste0(nm, ".csv")))
  }
  figure_dir <- file.path(config$output_dir, "figures")
  dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
  for (ext in c("pdf", "png")) {
    lmv2_exit_write_plot(
      file.path(figure_dir, paste0("figure_recurrent_decomposition.", ext)),
      7, 4.5, function() {
        z <- components[components$component != "total", ]
        labels <- c(
          cessation = "Patenting\ncessation",
          active_given_survival = "Active years\namong survivors",
          patents_per_active_year = "Patents per\nactive year")
        graphics::barplot(
          z$estimate, names.arg = labels[z$component],
          col = ifelse(z$estimate < 0, "#A33A2B", "#2F6B4F"),
          border = NA, ylab = "Patents per inventor-year")
        graphics::abline(h = 0, col = "gray35")
      })
  }
  labels <- c(
    cessation = "Earlier cessation of observed patenting",
    active_given_survival = "Fewer active years among survivors",
    patents_per_active_year = "Fewer patents in active years",
    total = "Total patent-count ATT")
  tex <- c(
    "\\begin{tabular}{lrrr}", "\\toprule",
    "Component & Annual effect & 95\\% CI & Cumulative effect \\\\",
    "\\midrule")
  for (i in seq_len(nrow(components))) {
    ci <- if (is.finite(components$ci_low[[i]])) {
      paste0("[", lmv2_exit_fmt(components$ci_low[[i]]), ", ",
             lmv2_exit_fmt(components$ci_high[[i]]), "]")
    } else ""
    tex <- c(tex, paste0(
      labels[[components$component[[i]]]], " & ",
      lmv2_exit_fmt(components$estimate[[i]]), " & ", ci, " & ",
      lmv2_exit_fmt(
        components$cumulative_post_window_patents[[i]]), " \\\\"))
  }
  tex <- c(tex, "\\bottomrule", "\\end{tabular}")
  writeLines(
    tex, file.path(config$output_dir, "table_recurrent_decomposition.tex"),
    useBytes = TRUE)
  invisible(list(components = components, status = status))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  smoke <- "--smoke" %in% args
  output_arg <- sub(
    "^--output-dir=", "",
    grep("^--output-dir=", args, value = TRUE))
  parent_arg <- sub(
    "^--parent-exit-dir=", "",
    grep("^--parent-exit-dir=", args, value = TRUE))
  config <- lmv2_recurrent_config(
    output_dir = if (length(output_arg)) output_arg[[1L]] else NULL,
    parent_exit_dir = if (length(parent_arg)) parent_arg[[1L]] else NULL)
  lmv2_estimate_recurrent_inventors(config, smoke = smoke)
}
