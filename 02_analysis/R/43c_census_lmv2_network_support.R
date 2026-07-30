# Package N0: summarize baseline-tie support and validation denominators.

if (!exists("lmv2_n0_config")) {
  source(file.path(
    "02_analysis", "R", "43a_lmv2_network_freeze_config.R"
  ))
}

lmv2_n0_census_support <- function(config = lmv2_n0_config()) {
  source(file.path(config$base, "02_analysis", "R", "00_utils.R"))
  use_project_library()
  shared_lib <- file.path(
    normalizePath(
      file.path(config$base, "..", ".."),
      winslash = "/", mustWork = TRUE
    ),
    ".r_libs"
  )
  if (dir.exists(shared_lib)) {
    .libPaths(unique(c(shared_lib, .libPaths())))
  }
  for (pkg in c("DBI", "duckdb")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop("Missing package: ", pkg, call. = FALSE)
    }
  }
  inputs <- file.path(
    config$output_dir,
    c(
      "network_focal_support.parquet",
      "validation_denominator_support.parquet",
      "network_construction_audit.csv"
    )
  )
  if (any(!file.exists(inputs))) {
    stop(
      "Missing N0 census input(s): ",
      paste(inputs[!file.exists(inputs)], collapse = ", "),
      call. = FALSE
    )
  }
  construction <- utils::read.csv(
    inputs[[3L]], stringsAsFactors = FALSE, check.names = FALSE
  )
  if (nrow(construction) != 1L || !isTRUE(construction$pass[[1L]])) {
    stop("N0 construction audit is not certified.", call. = FALSE)
  }
  dir.create(config$results_dir, recursive = TRUE, showWarnings = FALSE)

  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, "PRAGMA threads=8")
  DBI::dbExecute(con, sprintf(
    "CREATE TEMP TABLE support AS SELECT * FROM read_parquet(%s)",
    lmv2_n0_sql_string(inputs[[1L]])
  ))
  DBI::dbExecute(con, sprintf(
    "CREATE TEMP TABLE validation AS SELECT * FROM read_parquet(%s)",
    lmv2_n0_sql_string(inputs[[2L]])
  ))

  coverage <- DBI::dbGetQuery(con, "
    WITH deal_mass AS (
      SELECT
        arm,
        deal_id,
        SUM(weight) AS deal_weight
      FROM support
      WHERE has_persistent_baseline_tie
      GROUP BY 1, 2
    ),
    concentration AS (
      SELECT
        arm,
        COUNT(*) AS network_deals,
        1.0 / SUM(POWER(deal_weight / total_weight, 2))
          AS effective_deals,
        MAX(deal_weight / total_weight) AS maximum_deal_weight_share
      FROM (
        SELECT
          *,
          SUM(deal_weight) OVER (PARTITION BY arm) AS total_weight
        FROM deal_mass
      )
      GROUP BY 1
    ),
    arm_summary AS (
      SELECT
        arm,
        COUNT(*) AS original_roster_rows,
        COUNT(DISTINCT codinv) AS original_unique_inventors,
        COUNT(DISTINCT deal_id) AS original_deals,
        SUM(weight) AS original_weight,
        COUNT(*) FILTER (WHERE has_persistent_baseline_tie)
          AS network_roster_rows,
        COUNT(DISTINCT codinv) FILTER (
          WHERE has_persistent_baseline_tie
        ) AS network_unique_inventors,
        COUNT(DISTINCT deal_id) FILTER (
          WHERE has_persistent_baseline_tie
        ) AS network_nominal_deals,
        SUM(weight) FILTER (WHERE has_persistent_baseline_tie)
          AS network_weight,
        SUM(weight) FILTER (WHERE has_persistent_baseline_tie) /
          SUM(weight) AS weighted_network_coverage,
        POWER(
          SUM(weight) FILTER (WHERE has_persistent_baseline_tie), 2
        ) / SUM(POWER(weight, 2)) FILTER (
          WHERE has_persistent_baseline_tie
        ) AS network_row_weight_ess,
        AVG(baseline_collaborator_count) FILTER (
          WHERE has_persistent_baseline_tie
        ) AS mean_baseline_collaborators,
        MEDIAN(baseline_collaborator_count) FILTER (
          WHERE has_persistent_baseline_tie
        ) AS median_baseline_collaborators,
        AVG(strongest_tie_concentration) FILTER (
          WHERE has_persistent_baseline_tie
        ) AS mean_strongest_tie_concentration
      FROM support
      GROUP BY 1
    )
    SELECT
      a.*,
      c.effective_deals,
      c.maximum_deal_weight_share
    FROM arm_summary a
    JOIN concentration c USING (arm)
    ORDER BY arm
  ")

  deal_concentration <- DBI::dbGetQuery(con, "
    WITH mass AS (
      SELECT
        arm,
        deal_id,
        COUNT(*) AS network_roster_rows,
        COUNT(DISTINCT codinv) AS network_unique_inventors,
        SUM(weight) AS deal_weight
      FROM support
      WHERE has_persistent_baseline_tie
      GROUP BY 1, 2
    )
    SELECT
      *,
      deal_weight / SUM(deal_weight) OVER (PARTITION BY arm)
        AS deal_weight_share,
      ROW_NUMBER() OVER (
        PARTITION BY arm ORDER BY deal_weight DESC, deal_id
      ) AS weight_rank
    FROM mass
    ORDER BY arm, weight_rank
  ")

  cohort_coverage <- DBI::dbGetQuery(con, "
    SELECT
      arm,
      cohort,
      COUNT(*) AS original_roster_rows,
      COUNT(*) FILTER (WHERE has_persistent_baseline_tie)
        AS network_roster_rows,
      COUNT(DISTINCT codinv) FILTER (
        WHERE has_persistent_baseline_tie
      ) AS network_unique_inventors,
      COUNT(DISTINCT deal_id) FILTER (
        WHERE has_persistent_baseline_tie
      ) AS network_deals,
      SUM(weight) AS original_weight,
      SUM(weight) FILTER (WHERE has_persistent_baseline_tie)
        AS network_weight,
      SUM(weight) FILTER (WHERE has_persistent_baseline_tie) /
        SUM(weight) AS weighted_network_coverage
    FROM support
    GROUP BY 1, 2
    ORDER BY arm, cohort
  ")

  validation_coverage <- DBI::dbGetQuery(con, "
    WITH defined_deal_mass AS (
      SELECT
        arm,
        event_time,
        deal_id,
        SUM(weight) AS deal_weight
      FROM validation
      WHERE composition_defined
      GROUP BY 1, 2, 3
    ),
    concentration AS (
      SELECT
        arm,
        event_time,
        1.0 / SUM(POWER(deal_weight / total_weight, 2))
          AS composition_effective_deals,
        MAX(deal_weight / total_weight)
          AS composition_maximum_deal_weight_share
      FROM (
        SELECT
          *,
          SUM(deal_weight) OVER (
            PARTITION BY arm, event_time
          ) AS total_weight
        FROM defined_deal_mass
      )
      GROUP BY 1, 2
    ),
    summary AS (
      SELECT
        arm,
        event_time,
        COUNT(*) AS network_rows,
        COUNT(DISTINCT focal_codinv) AS network_unique_inventors,
        COUNT(DISTINCT deal_id) AS network_deals,
        SUM(weight) AS network_weight,
        COUNT(*) FILTER (WHERE composition_defined)
          AS composition_defined_rows,
        COUNT(DISTINCT focal_codinv) FILTER (
          WHERE composition_defined
        ) AS composition_defined_unique_inventors,
        COUNT(DISTINCT deal_id) FILTER (
          WHERE composition_defined
        ) AS composition_defined_deals,
        SUM(weight) FILTER (WHERE composition_defined)
          AS composition_defined_weight,
        SUM(weight) FILTER (WHERE composition_defined) /
          SUM(weight) AS weighted_composition_defined_share,
        SUM(
          partner_persistence_denominator_defined::INTEGER
        ) AS partner_denominator_defined_rows
      FROM validation
      GROUP BY 1, 2
    )
    SELECT s.*, c.composition_effective_deals,
      c.composition_maximum_deal_weight_share
    FROM summary s
    LEFT JOIN concentration c USING (arm, event_time)
    ORDER BY arm, event_time
  ")

  treated <- coverage[coverage$arm == "treated", , drop = FALSE]
  control <- coverage[coverage$arm == "control", , drop = FALSE]
  treated_validation <- validation_coverage[
    validation_coverage$arm == "treated", , drop = FALSE
  ]
  control_validation <- validation_coverage[
    validation_coverage$arm == "control", , drop = FALSE
  ]
  gates <- config$gates
  checks <- data.frame(
    check = c(
      "minimum_treated_focal_inventors",
      "minimum_treated_deals",
      "minimum_effective_treated_deals",
      "maximum_treated_deal_weight_share",
      "minimum_effective_control_deals",
      "maximum_control_deal_weight_share",
      "partner_denominator_complete_at_both_validation_leads",
      "minimum_treated_composition_rows_each_lead",
      "minimum_treated_composition_deals_each_lead",
      "minimum_composition_effective_treated_deals_each_lead",
      "minimum_composition_effective_control_deals_each_lead",
      "maximum_composition_control_deal_weight_share_each_lead",
      "both_arms_have_network_support"
    ),
    pass = c(
      treated$network_unique_inventors >=
        gates$minimum_treated_inventors,
      treated$network_nominal_deals >= gates$minimum_treated_deals,
      treated$effective_deals >= gates$minimum_effective_treated_deals,
      treated$maximum_deal_weight_share <=
        gates$maximum_treated_deal_weight_share,
      control$effective_deals >= gates$minimum_effective_control_deals,
      control$maximum_deal_weight_share <=
        gates$maximum_control_deal_weight_share,
      nrow(treated_validation) == 2L &&
        all(
          treated_validation$partner_denominator_defined_rows ==
            treated_validation$network_rows
        ),
      nrow(treated_validation) == 2L &&
        all(
          treated_validation$composition_defined_rows >=
            gates$minimum_treated_composition_rows
        ),
      nrow(treated_validation) == 2L &&
        all(
          treated_validation$composition_defined_deals >=
            gates$minimum_treated_composition_deals
        ),
      nrow(treated_validation) == 2L &&
        all(
          treated_validation$composition_effective_deals >=
            gates$minimum_composition_effective_treated_deals
        ),
      nrow(control_validation) == 2L &&
        all(
          control_validation$composition_effective_deals >=
            gates$minimum_composition_effective_control_deals
        ),
      nrow(control_validation) == 2L &&
        all(
          control_validation$composition_maximum_deal_weight_share <=
            gates$maximum_composition_control_deal_weight_share
        ),
      setequal(coverage$arm, c("treated", "control")) &&
        all(coverage$network_roster_rows > 0L)
    ),
    value = c(
      as.character(treated$network_unique_inventors),
      as.character(treated$network_nominal_deals),
      format(treated$effective_deals, digits = 12),
      format(treated$maximum_deal_weight_share, digits = 12),
      format(control$effective_deals, digits = 12),
      format(control$maximum_deal_weight_share, digits = 12),
      paste(
        treated_validation$partner_denominator_defined_rows,
        treated_validation$network_rows,
        sep = "/", collapse = ";"
      ),
      paste(
        treated_validation$composition_defined_rows,
        collapse = ";"
      ),
      paste(
        treated_validation$composition_defined_deals,
        collapse = ";"
      ),
      paste(
        format(
          treated_validation$composition_effective_deals,
          digits = 12
        ),
        collapse = ";"
      ),
      paste(
        format(
          control_validation$composition_effective_deals,
          digits = 12
        ),
        collapse = ";"
      ),
      paste(
        format(
          control_validation$composition_maximum_deal_weight_share,
          digits = 12
        ),
        collapse = ";"
      ),
      paste(coverage$network_roster_rows, collapse = ";")
    ),
    detail = c(
      paste0("threshold >= ", gates$minimum_treated_inventors),
      paste0("threshold >= ", gates$minimum_treated_deals),
      paste0("threshold >= ", gates$minimum_effective_treated_deals),
      paste0(
        "threshold <= ", gates$maximum_treated_deal_weight_share
      ),
      paste0("threshold >= ", gates$minimum_effective_control_deals),
      paste0(
        "threshold <= ", gates$maximum_control_deal_weight_share
      ),
      "defined rows / network rows at event times -2 and -1",
      paste0(
        "threshold >= ", gates$minimum_treated_composition_rows,
        " at each lead"
      ),
      paste0(
        "threshold >= ", gates$minimum_treated_composition_deals,
        " at each lead"
      ),
      paste0(
        "threshold >= ",
        gates$minimum_composition_effective_treated_deals,
        " at each treated lead"
      ),
      paste0(
        "threshold >= ",
        gates$minimum_composition_effective_control_deals,
        " at each control lead"
      ),
      paste0(
        "threshold <= ",
        gates$maximum_composition_control_deal_weight_share,
        " at each control lead"
      ),
      "treated and control rows must both remain"
    ),
    stringsAsFactors = FALSE
  )
  release_decision <- if (all(checks$pass)) {
    "release_N1_preperiod_validation"
  } else {
    "feasibility_only_stop_before_N1"
  }
  decision <- data.frame(
    package = "N0_NETWORK_CENSUS",
    decision = release_decision,
    all_support_gates_pass = all(checks$pass),
    meaningful_effect_threshold = config$meaningful_effect,
    post_treatment_effects_opened = FALSE,
    stringsAsFactors = FALSE
  )
  failed_gate_names <- checks$check[!checks$pass]

  paths <- c(
    network_coverage_by_arm = file.path(
      config$output_dir, "network_coverage_by_arm.csv"
    ),
    network_coverage_by_cohort = file.path(
      config$output_dir, "network_coverage_by_cohort.csv"
    ),
    network_deal_concentration = file.path(
      config$output_dir, "network_deal_concentration.csv"
    ),
    validation_denominator_coverage = file.path(
      config$output_dir, "validation_denominator_coverage.csv"
    ),
    n0_support_gate_checks = file.path(
      config$output_dir, "n0_support_gate_checks.csv"
    ),
    n0_support_decision = file.path(
      config$output_dir, "n0_support_decision.csv"
    )
  )
  lmv2_n0_write_csv(coverage, paths[["network_coverage_by_arm"]])
  lmv2_n0_write_csv(
    cohort_coverage, paths[["network_coverage_by_cohort"]]
  )
  lmv2_n0_write_csv(
    deal_concentration, paths[["network_deal_concentration"]]
  )
  lmv2_n0_write_csv(
    validation_coverage,
    paths[["validation_denominator_coverage"]]
  )
  lmv2_n0_write_csv(checks, paths[["n0_support_gate_checks"]])
  lmv2_n0_write_csv(decision, paths[["n0_support_decision"]])

  arm_labels <- c(
    treated = "Treated focal inventors",
    control = "Weighted control rows"
  )
  census_rows <- vapply(seq_len(nrow(coverage)), function(i) {
    z <- coverage[i, ]
    paste0(
      arm_labels[[z$arm]], " & ",
      format(z$network_roster_rows, big.mark = ","), " & ",
      format(z$network_unique_inventors, big.mark = ","), " & ",
      format(z$network_nominal_deals, big.mark = ","), " & ",
      sprintf("%.1f\\%%", 100 * z$weighted_network_coverage), " & ",
      sprintf("%.1f", z$effective_deals), " & ",
      sprintf("%.1f\\%%", 100 * z$maximum_deal_weight_share),
      " \\\\"
    )
  }, character(1))
  writeLines(
    c(
      "\\begin{tabular}{lrrrrrr}",
      "\\toprule",
      paste(
        "Arm & Rows & Inventors & Deals & Weighted coverage",
        "& Effective deals & Largest deal share \\\\"
      ),
      "\\midrule",
      census_rows,
      "\\bottomrule",
      "\\end{tabular}"
    ),
    file.path(config$results_dir, "table_network_census.tex"),
    useBytes = TRUE
  )

  validation_rows <- vapply(
    seq_len(nrow(validation_coverage)),
    function(i) {
      z <- validation_coverage[i, ]
      paste0(
        arm_labels[[z$arm]], " & ", z$event_time, " & ",
        format(z$network_rows, big.mark = ","), " & ",
        format(z$composition_defined_rows, big.mark = ","), " & ",
        format(z$composition_defined_deals, big.mark = ","), " & ",
        sprintf("%.1f\\%%", 100 * z$weighted_composition_defined_share),
        " & ", sprintf("%.1f", z$composition_effective_deals), " \\\\"
      )
    },
    character(1)
  )
  writeLines(
    c(
      "\\begin{tabular}{lrrrrrr}",
      "\\toprule",
      paste(
        "Arm & Lead & Network rows & Composition rows & Deals",
        "& Weighted defined share & Effective deals \\\\"
      ),
      "\\midrule",
      validation_rows,
      "\\bottomrule",
      "\\end{tabular}"
    ),
    file.path(
      config$results_dir,
      "table_network_validation_denominators.tex"
    ),
    useBytes = TRUE
  )

  treated_minus2 <- treated_validation[
    treated_validation$event_time == -2, , drop = FALSE
  ]
  treated_minus1 <- treated_validation[
    treated_validation$event_time == -1, , drop = FALSE
  ]
  note <- c(
    "# Package N0 network census results",
    "",
    paste0("Status: ", release_decision),
    "",
    "N0 uses only event times -5 through -1 and opens no post-acquisition",
    "network outcome.",
    "",
    paste0(
      "The -5 through -3 persistent-tie anchor retains ",
      format(treated$network_unique_inventors, big.mark = ","),
      " treated focal inventors across ",
      format(treated$network_nominal_deals, big.mark = ","),
      " deals. The effective treated-deal count is ",
      sprintf("%.1f", treated$effective_deals),
      ", and the largest deal carries ",
      sprintf("%.1f%%", 100 * treated$maximum_deal_weight_share),
      " of treated network weight."
    ),
    paste0(
      "Weighted treated-row coverage is ",
      sprintf("%.1f%%", 100 * treated$weighted_network_coverage),
      ". The mean persistent baseline-collaborator count is ",
      sprintf("%.2f", treated$mean_baseline_collaborators), "."
    ),
    "",
    paste0(
      "The partner-behavior denominator is defined for every treated",
      " network row at -2 and -1. The conditional composition denominator",
      " is defined for ",
      format(treated_minus2$composition_defined_rows, big.mark = ","),
      " treated rows at -2 and ",
      format(treated_minus1$composition_defined_rows, big.mark = ","),
      " at -1."
    ),
    "",
    paste0(
      "The frozen smallest main-text-relevant effect is ",
      sprintf("%.2f", config$meaningful_effect),
      " on the share scale. N1 remains pre-treatment and may proceed only",
      " under the recorded support decision."
    ),
    if (length(failed_gate_names)) {
      paste0(
        "The frozen support gate fails on: ",
        paste(failed_gate_names, collapse = ", "),
        ". N1 and all post-acquisition network effects remain closed."
      )
    } else {
      "All frozen N0 support gates pass; only pre-treatment N1 is released."
    }
  )
  writeLines(note, config$results_note, useBytes = TRUE)

  invisible(list(
    coverage = coverage,
    validation = validation_coverage,
    checks = checks,
    decision = decision
  ))
}

if (sys.nframe() == 0L) {
  lmv2_n0_census_support()
  message("N0 network support census completed.")
}
