# Package D1: report and certify descriptive retained-status evidence.

if (!exists("lmv2_d1_config")) {
  source(file.path(
    "02_analysis", "R", "42a_lmv2_stayer_descriptives_config.R"
  ))
}

lmv2_d1_all_pass <- function(path) {
  x <- utils::read.csv(
    path, stringsAsFactors = FALSE, check.names = FALSE
  )
  all(c("check", "pass") %in% names(x)) &&
    nrow(x) > 0L &&
    !anyNA(x$pass) &&
    all(tolower(as.character(x$pass)) == "true")
}

lmv2_d1_fmt <- function(x, digits = 3L) {
  formatC(as.numeric(x), digits = digits, format = "f")
}

lmv2_d1_report_certify <- function(config = lmv2_d1_config()) {
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
  for (pkg in c("digest", "ggplot2", "DBI", "duckdb")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop("Missing package: ", pkg, call. = FALSE)
    }
  }
  required <- c(
    file.path(config$output_dir, c(
      "status_predeal_metrics.parquet",
      "d1_global_career_endpoints.parquet",
      "annual_status_paths.parquet",
      "annual_status_transition.csv",
      "persistent_inside.csv",
      "endpoint_activity_rows.parquet",
      "endpoint_activity_summary.csv",
      "status_path_construction_audit.csv",
      "matched_annual_status_paths.parquet",
      "matched_annual_status_transition.csv",
      "matched_persistent_inside.csv",
      "status_distribution_summary.csv",
      "status_distribution_pairwise_tests.csv",
      "management_transition_diagnostic.csv",
      "status_partition_counts.csv"
    )),
    config$completion_year_results,
    config$completion_year_dynamic,
    config$completion_year_certification,
    config$master_inventory,
    config$freeze_file,
    config$source_files
  )
  if (any(!file.exists(required))) {
    stop(
      "Missing D1 reporting input(s): ",
      paste(required[!file.exists(required)], collapse = ", "),
      call. = FALSE
    )
  }
  dir.create(config$results_dir, recursive = TRUE, showWarnings = FALSE)

  read_output <- function(name) {
    utils::read.csv(
      file.path(config$output_dir, name),
      stringsAsFactors = FALSE, check.names = FALSE
    )
  }
  construction <- read_output("status_path_construction_audit.csv")
  distributions <- read_output("status_distribution_summary.csv")
  pairwise <- read_output("status_distribution_pairwise_tests.csv")
  management <- read_output("management_transition_diagnostic.csv")
  counts <- read_output("status_partition_counts.csv")
  transitions <- read_output("annual_status_transition.csv")
  persistence <- read_output("persistent_inside.csv")
  matched_transitions <- read_output(
    "matched_annual_status_transition.csv"
  )
  matched_persistence <- read_output("matched_persistent_inside.csv")
  endpoints <- read_output("endpoint_activity_summary.csv")
  inventory <- utils::read.csv(
    config$master_inventory,
    stringsAsFactors = FALSE, check.names = FALSE
  )
  completion <- utils::read.csv(
    config$completion_year_results,
    stringsAsFactors = FALSE, check.names = FALSE
  )
  dynamic <- utils::read.csv(
    config$completion_year_dynamic,
    stringsAsFactors = FALSE, check.names = FALSE
  )

  t0 <- dynamic[
    dynamic$sample == "full_1994_2010" &
      dynamic$outcome == "patent_count" &
      dynamic$event_time == 0 &
      dynamic$inference == "two_way_deal_inventor",
    ,
    drop = FALSE
  ]
  inclusive <- completion[
    completion$sample == "full_1994_2010" &
      completion$outcome == "patent_count" &
      completion$governing &
      completion$summary %in% c(
        "average_annual_t0_to_t5", "cumulative_t0_to_t5"
      ),
    ,
    drop = FALSE
  ]
  timing <- rbind(
    data.frame(
      estimand = "completion_year_t0",
      estimate = t0$estimate,
      ci_low = t0$ci_low,
      ci_high = t0$ci_high,
      p_value = 2 * stats::pt(
        -abs(t0$estimate / t0$se), df = t0$df
      ),
      inference = t0$inference,
      stringsAsFactors = FALSE
    ),
    data.frame(
      estimand = inclusive$summary,
      estimate = inclusive$estimate,
      ci_low = inclusive$ci_low,
      ci_high = inclusive$ci_high,
      p_value = inclusive$p_value,
      inference = inclusive$inference,
      stringsAsFactors = FALSE
    )
  )
  lmv2_d1_write_csv(
    timing,
    file.path(config$results_dir, "completion_year_reporting.csv")
  )

  arm_label <- c(
    treated = "Acquired-target retained",
    control = "Matched-control retained"
  )
  persistence_long <- rbind(
    transform(
      matched_persistence[c(
        "arm", "horizon", "persistent_inside_share_all"
      )],
      measure = "Endpoint focal, no outside-only path",
      share = persistent_inside_share_all
    )[c("arm", "horizon", "measure", "share")],
    transform(
      matched_persistence[c(
        "arm", "horizon", "uninterrupted_annual_focal_share"
      )],
      measure = "Focal evidence in every year",
      share = uninterrupted_annual_focal_share
    )[c("arm", "horizon", "measure", "share")]
  )
  persistence_long$arm_label <- unname(arm_label[persistence_long$arm])
  persistence_long$horizon_label <- paste0("+", persistence_long$horizon)
  figure <- ggplot2::ggplot(
    persistence_long,
    ggplot2::aes(
      x = horizon_label, y = share, fill = arm_label
    )
  ) +
    ggplot2::geom_col(
      position = ggplot2::position_dodge(width = 0.75),
      width = 0.68
    ) +
    ggplot2::geom_text(
      ggplot2::aes(label = sprintf("%.1f%%", 100 * share)),
      position = ggplot2::position_dodge(width = 0.75),
      vjust = -0.35, size = 3.5
    ) +
    ggplot2::scale_y_continuous(
      limits = c(0, max(persistence_long$share) * 1.22),
      labels = function(x) paste0(round(100 * x), "%")
    ) +
    ggplot2::scale_fill_manual(
      values = c("#1B5E77", "#C98B2E")
    ) +
    ggplot2::facet_wrap(~measure) +
    ggplot2::labs(
      x = "Event-time horizon",
      y = "Weighted share of retained-design rows",
      fill = NULL,
      title = "Persistence of focal patent affiliation by design arm",
      subtitle = paste(
        "Patent-location evidence, not employment;",
        "no-patent gaps are allowed in the endpoint measure"
      )
    ) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      legend.position = "bottom",
      panel.grid.major.x = ggplot2::element_blank(),
      plot.title.position = "plot"
    )
  figure_path <- file.path(
    config$results_dir, "figure_persistent_inside.png"
  )
  ggplot2::ggsave(
    figure_path, figure,
    width = 7.2, height = 4.6, dpi = 300
  )

  status_label <- c(
    initially_retained = "Initially retained",
    leaver = "Leaver",
    no_post_patent = "No observed post-deal patent"
  )
  table_rows <- vapply(seq_len(nrow(distributions)), function(i) {
    r <- distributions[i, ]
    paste0(
      r$variable_label, " & ",
      status_label[[r$retention_status]], " & ",
      format(r$n, big.mark = ","), " & ",
      lmv2_d1_fmt(r$mean), " & ",
      lmv2_d1_fmt(r$sd), " & ",
      lmv2_d1_fmt(r$p10), " & ",
      lmv2_d1_fmt(r$p25), " & ",
      lmv2_d1_fmt(r$median), " & ",
      lmv2_d1_fmt(r$p75), " & ",
      lmv2_d1_fmt(r$p90), " \\\\"
    )
  }, character(1))
  distribution_tex <- c(
    "\\begin{tabular}{llrrrrrrrr}",
    "\\toprule",
    "Measure & Status & N & Mean & SD & P10 & P25 & P50 & P75 & P90 \\\\",
    "\\midrule",
    table_rows,
    "\\bottomrule",
    "\\end{tabular}"
  )
  writeLines(
    distribution_tex,
    file.path(config$results_dir, "table_status_distributions.tex"),
    useBytes = TRUE
  )

  state_label <- c(
    focal_group_only = "Focal group only",
    outside_group_only = "Outside/no focal evidence",
    both_focal_and_outside = "Both focal and outside",
    no_patent_later_patent_exists =
      "No patent this year; later patent exists",
    end_of_observed_patenting = "End of observed patenting",
    right_censored_not_observable = "Right-censored/not observable"
  )
  transition_rows <- vapply(seq_len(nrow(transitions)), function(i) {
    r <- transitions[i, ]
    paste0(
      "+", r$event_time, " & ",
      state_label[[r$annual_state]], " & ",
      format(r$inventor_rows, big.mark = ","), " & ",
      sprintf("%.1f\\%%", 100 * r$share), " \\\\"
    )
  }, character(1))
  transition_tex <- c(
    "\\begin{tabular}{llrr}",
    "\\toprule",
    "Event time & Annual patent-location state & N & Share \\\\",
    "\\midrule",
    transition_rows,
    "\\bottomrule",
    "\\end{tabular}"
  )
  writeLines(
    transition_tex,
    file.path(config$results_dir, "table_status_paths.tex"),
    useBytes = TRUE
  )

  matched_transition_rows <- vapply(
    seq_len(nrow(matched_transitions)),
    function(i) {
      r <- matched_transitions[i, ]
      paste0(
        arm_label[[r$arm]], " & +", r$event_time, " & ",
        state_label[[r$annual_state]], " & ",
        sprintf("%.1f\\%%", 100 * r$weighted_share), " \\\\"
      )
    },
    character(1)
  )
  matched_transition_tex <- c(
    "\\begin{tabular}{lllr}",
    "\\toprule",
    "Design arm & Event time & Annual patent-location state & Weighted share \\\\",
    "\\midrule",
    matched_transition_rows,
    "\\bottomrule",
    "\\end{tabular}"
  )
  writeLines(
    matched_transition_tex,
    file.path(config$results_dir, "table_matched_status_paths.tex"),
    useBytes = TRUE
  )

  get_summary <- function(variable, status) {
    distributions[
      distributions$variable == variable &
        distributions$retention_status == status,
      ,
      drop = FALSE
    ]
  }
  age_retained <- get_summary(
    "career_age_t_minus_1", "initially_retained"
  )
  age_leaver <- get_summary("career_age_t_minus_1", "leaver")
  age_no_post <- get_summary(
    "career_age_t_minus_1", "no_post_patent"
  )
  stock_retained <- get_summary(
    "patent_stock_5y", "initially_retained"
  )
  stock_leaver <- get_summary("patent_stock_5y", "leaver")
  stock_no_post <- get_summary(
    "patent_stock_5y", "no_post_patent"
  )
  retained_leaver_age <- pairwise[
    pairwise$variable == "career_age_t_minus_1" &
      pairwise$group_a == "initially_retained" &
      pairwise$group_b == "leaver",
    ,
    drop = FALSE
  ]
  retained_leaver_stock <- pairwise[
    pairwise$variable == "patent_stock_5y" &
      pairwise$group_a == "initially_retained" &
      pairwise$group_b == "leaver",
    ,
    drop = FALSE
  ]
  retained_count <- counts$inventors[
    counts$retention_status == "initially_retained"
  ]
  unresolved_share <- construction$unresolved_patent_location_rows /
    construction$path_rows
  endpoint5 <- endpoints[endpoints$event_time == 5, , drop = FALSE]
  endpoint6 <- endpoints[endpoints$event_time == 6, , drop = FALSE]
  transition5 <- transitions[
    transitions$event_time == 5, , drop = FALSE
  ]
  share_at_5 <- function(state) {
    value <- transition5$share[transition5$annual_state == state]
    if (length(value)) value[[1L]] else 0
  }
  persistence_at <- function(arm, horizon, variable) {
    matched_persistence[
      matched_persistence$arm == arm &
        matched_persistence$horizon == horizon,
      variable
    ][[1L]]
  }
  timing_t0 <- timing[timing$estimand == "completion_year_t0", ]
  timing_avg <- timing[
    timing$estimand == "average_annual_t0_to_t5", ]
  timing_cum <- timing[
    timing$estimand == "cumulative_t0_to_t5", ]

  registration_specs <- data.frame(
    package_estimand = c(
      "completion_year_t0",
      "average_annual_t0_to_t5",
      "cumulative_t0_to_t5",
      "frozen_cumulative_t1_to_t5"
    ),
    inventory_analysis = c(
      "completion-year ATT (partially exposed calendar year)",
      "completion-through-plus-five average annual ATT",
      "completion-through-plus-five cumulative effect",
      "entropy-balanced ATT"
    ),
    expected_status = c(
      "companion", "companion", "companion", "primary"
    ),
    role = c(
      "completion_year_companion",
      "completion_year_companion",
      "completion_year_companion",
      "primary_full_calendar_year"
    ),
    stringsAsFactors = FALSE
  )
  registration <- do.call(
    rbind,
    lapply(seq_len(nrow(registration_specs)), function(i) {
      spec <- registration_specs[i, ]
      hit <- inventory[
        inventory$population == "full target-inventor cohort" &
          inventory$outcome == "patent_count" &
          inventory$sample == "full_1994_2010" &
          inventory$analysis == spec$inventory_analysis,
        ,
        drop = FALSE
      ]
      expected_estimate <- if (
        spec$package_estimand == "frozen_cumulative_t1_to_t5"
      ) {
        hit$five_year_effect
      } else {
        timing$estimate[timing$estimand == spec$package_estimand]
      }
      inventory_estimate <- if (
        spec$package_estimand == "frozen_cumulative_t1_to_t5"
      ) {
        hit$five_year_effect
      } else {
        hit$estimate
      }
      registered <- nrow(hit) == 1L &&
        length(expected_estimate) == 1L &&
        is.finite(expected_estimate) &&
        abs(inventory_estimate - expected_estimate) < 1e-12 &&
        hit$status == spec$expected_status &&
        !is.na(hit$main_text_eligible)
      data.frame(
        package_estimand = spec$package_estimand,
        result_id = if (nrow(hit) == 1L) hit$result_id else NA_character_,
        estimate = if (length(inventory_estimate) == 1L) {
          inventory_estimate
        } else {
          NA_real_
        },
        inventory_status = if (nrow(hit) == 1L) {
          hit$status
        } else {
          NA_character_
        },
        main_text_eligible = if (nrow(hit) == 1L) {
          hit$main_text_eligible
        } else {
          NA
        },
        role = spec$role,
        registered = registered,
        stringsAsFactors = FALSE
      )
    })
  )
  lmv2_d1_write_csv(
    registration,
    file.path(config$results_dir, "reportable_result_registration.csv")
  )

  note <- c(
    "# Package D1 retained-status descriptive results",
    "",
    "Status: implemented and certified",
    "",
    "## Population and selection",
    "",
    paste0(
      "The certified primary partition contains ",
      format(sum(counts$inventors), big.mark = ","), " inventors: ",
      format(retained_count, big.mark = ","), " initially retained, ",
      format(
        counts$inventors[counts$retention_status == "leaver"],
        big.mark = ","
      ), " leavers, and ",
      format(
        counts$inventors[
          counts$retention_status == "no_post_patent"
        ],
        big.mark = ","
      ), " with no observed post-deal patent."
    ),
    "",
    paste0(
      "Median career age at t=-1 is ",
      lmv2_d1_fmt(age_retained$median, 1), " years for initially retained, ",
      lmv2_d1_fmt(age_leaver$median, 1), " for leavers, and ",
      lmv2_d1_fmt(age_no_post$median, 1),
      " for the no-post-patent group."
    ),
    paste0(
      "Median five-year pre-deal patent stock is ",
      lmv2_d1_fmt(stock_retained$median, 1), ", ",
      lmv2_d1_fmt(stock_leaver$median, 1), ", and ",
      lmv2_d1_fmt(stock_no_post$median, 1), ", respectively."
    ),
    paste0(
      "Initially retained inventors and leavers have effectively identical",
      " career age (SMD ",
      lmv2_d1_fmt(
        retained_leaver_age$standardized_mean_difference
      ), "), while initially retained inventors have a modestly higher",
      " pre-deal patent stock (SMD ",
      lmv2_d1_fmt(
        retained_leaver_stock$standardized_mean_difference
      ), "). This raw retained-leaver difference documents status sorting.",
      " It does not sign bias in the selected-group ATT; the P5b design",
      " separately balances pre-deal patent counts between treated and",
      " control retained rows."
    ),
    paste0(
      "The management-transition interpretation is not supported under the",
      " frozen effect-size rule (diagnostic: **",
      management$decision, "**). The no-post-patent career-age SMD is ",
      lmv2_d1_fmt(management$smd_vs_initially_retained),
      " versus initially retained inventors and ",
      lmv2_d1_fmt(management$smd_vs_leaver),
      " versus leavers."
    ),
    "",
    "## Patent-location paths",
    "",
    paste0(
      "The endpoint-based persistent-inside share is ",
      sprintf(
        "%.1f%%",
        100 * persistence$persistent_inside_share_all[
          persistence$horizon == 3
        ]
      ), " through +3 and ",
      sprintf(
        "%.1f%%",
        100 * persistence$persistent_inside_share_all[
          persistence$horizon == 5
        ]
      ), " through +5."
    ),
    paste0(
      "At +3, this is ",
      sprintf(
        "%.1f%%",
        100 * persistence$persistent_inside_share_first_post_observed[
          persistence$horizon == 3
        ]
      ), " among inventors whose first post-deal patent is observed by +3,",
      " compared with ",
      sprintf(
        "%.1f%%",
        100 * persistence$persistent_inside_share_all[
          persistence$horizon == 3
        ]
      ), " of all initially retained inventors."
    ),
    paste0(
      "The stricter uninterrupted annual-focal shares are ",
      sprintf(
        "%.1f%%",
        100 * persistence$uninterrupted_annual_focal_share[
          persistence$horizon == 3
        ]
      ), " and ",
      sprintf(
        "%.1f%%",
        100 * persistence$uninterrupted_annual_focal_share[
          persistence$horizon == 5
        ]
      ), "."
    ),
    paste0(
      "At +5, ",
      sprintf("%.1f%%", 100 * share_at_5("focal_group_only")),
      " are focal-only, ",
      sprintf(
        "%.1f%%", 100 * share_at_5("both_focal_and_outside")
      ), " have both focal and outside evidence, ",
      sprintf("%.1f%%", 100 * share_at_5("outside_group_only")),
      " have outside/no-focal evidence, ",
      sprintf(
        "%.1f%%",
        100 * share_at_5("no_patent_later_patent_exists")
      ), " have no patent that year but patent later, and ",
      sprintf(
        "%.1f%%", 100 * share_at_5("end_of_observed_patenting")
      ), " have reached the end of observed patenting; ",
      sprintf(
        "%.1f%%",
        100 * share_at_5("right_censored_not_observable")
      ), " are right-censored."
    ),
    paste0(
      "Focal-only patent affiliation falls from ",
      sprintf(
        "%.1f%%",
        100 * transitions$share[
          transitions$event_time == 1 &
            transitions$annual_state == "focal_group_only"
        ]
      ), " at +1 to ",
      sprintf("%.1f%%", 100 * share_at_5("focal_group_only")),
      " at +5. Initial retention therefore records a first post-deal",
      " patent-location state, not durable organizational attachment."
    ),
    paste0(
      "In the separately balanced retained design, the endpoint-based",
      " persistence shares through +3 are ",
      sprintf(
        "%.1f%%", 100 * persistence_at(
          "treated", 3, "persistent_inside_share_all"
        )
      ), " for treated rows and ",
      sprintf(
        "%.1f%%", 100 * persistence_at(
          "control", 3, "persistent_inside_share_all"
        )
      ), " for matched controls; through +5 they are ",
      sprintf(
        "%.1f%%", 100 * persistence_at(
          "treated", 5, "persistent_inside_share_all"
        )
      ), " and ",
      sprintf(
        "%.1f%%", 100 * persistence_at(
          "control", 5, "persistent_inside_share_all"
        )
      ), ". The corresponding uninterrupted annual-focal shares through",
      " +5 are ",
      sprintf(
        "%.1f%%", 100 * persistence_at(
          "treated", 5, "uninterrupted_annual_focal_share"
        )
      ), " and ",
      sprintf(
        "%.1f%%", 100 * persistence_at(
          "control", 5, "uninterrupted_annual_focal_share"
        )
      ), "."
    ),
    paste0(
      construction$unresolved_patent_location_rows,
      " inventor-year(s), or ",
      sprintf("%.3f%%", 100 * unresolved_share),
      " of the annual grid, contain patents without resolvable",
      " company/group evidence. These are flagged and never interpreted as",
      " confirmed outside employment."
    ),
    "",
    "## Endpoint activity",
    "",
    paste0(
      "At +5, the weighted focal-group existence-through-horizon share is ",
      sprintf(
        "%.1f%%",
        100 * endpoint5$weighted_exists_through_horizon_share[
          endpoint5$arm == "treated"
        ]
      ), " for treated retained-design rows and ",
      sprintf(
        "%.1f%%",
        100 * endpoint5$weighted_exists_through_horizon_share[
          endpoint5$arm == "control"
        ]
      ), " for controls. Exact-year patent activity is ",
      sprintf(
        "%.1f%%",
        100 * endpoint5$weighted_patent_active_share[
          endpoint5$arm == "treated"
        ]
      ), " for treated retained-design rows and ",
      sprintf(
        "%.1f%%",
        100 * endpoint5$weighted_patent_active_share[
          endpoint5$arm == "control"
        ]
      ), " for controls."
    ),
    paste0(
      "Among cohorts observable at +6, the corresponding descriptive",
      " existence shares are ",
      sprintf(
        "%.1f%%",
        100 * endpoint6$weighted_exists_through_horizon_share[
          endpoint6$arm == "treated"
        ]
      ), " and ",
      sprintf(
        "%.1f%%",
        100 * endpoint6$weighted_exists_through_horizon_share[
          endpoint6$arm == "control"
        ]
      ), "; exact-year activity shares are ",
      sprintf(
        "%.1f%%",
        100 * endpoint6$weighted_patent_active_share[
          endpoint6$arm == "treated"
        ]
      ), " and ",
      sprintf(
        "%.1f%%",
        100 * endpoint6$weighted_patent_active_share[
          endpoint6$arm == "control"
        ]
      ), ". +6 never enters cohort inclusion or weighting."
    ),
    "",
    "## Completion-year effect",
    "",
    paste0(
      "Event time zero is the merger-completion calendar year: ATT = ",
      lmv2_d1_fmt(timing_t0$estimate, 4), ", 95% CI [",
      lmv2_d1_fmt(timing_t0$ci_low, 4), ", ",
      lmv2_d1_fmt(timing_t0$ci_high, 4), "]."
    ),
    paste0(
      "The completion-through-+5 average annual ATT is ",
      lmv2_d1_fmt(timing_avg$estimate, 4), ", 95% CI [",
      lmv2_d1_fmt(timing_avg$ci_low, 4), ", ",
      lmv2_d1_fmt(timing_avg$ci_high, 4),
      "]; the cumulative effect is ",
      lmv2_d1_fmt(timing_cum$estimate, 4), ", 95% CI [",
      lmv2_d1_fmt(timing_cum$ci_low, 4), ", ",
      lmv2_d1_fmt(timing_cum$ci_high, 4), "]."
    ),
    "Timing is observed only by year, so t=0 cannot be split into",
    "pre- and post-completion months.",
    "",
    "All path results describe patent affiliation, not employment, and are",
    "descriptive rather than a new landmark causal estimand."
  )
  writeLines(note, config$results_note, useBytes = TRUE)

  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  paths <- DBI::dbGetQuery(con, sprintf(
    "SELECT * FROM read_parquet(%s)",
    lmv2_d1_sql_string(file.path(
      config$output_dir, "annual_status_paths.parquet"
    ))
  ))
  matched_paths <- DBI::dbGetQuery(con, sprintf(
    "SELECT * FROM read_parquet(%s)",
    lmv2_d1_sql_string(file.path(
      config$output_dir, "matched_annual_status_paths.parquet"
    ))
  ))
  allowed_states <- all(paths$annual_state %in% config$state_levels)
  share_totals <- aggregate(
    share ~ event_time, data = transitions, sum
  )
  matched_share_totals <- aggregate(
    weighted_share ~ arm + event_time,
    data = matched_transitions, sum
  )
  completion_pass <- lmv2_d1_all_pass(
    config$completion_year_certification
  )
  note_text <- paste(
    readLines(config$results_note, warn = FALSE, encoding = "UTF-8"),
    collapse = "\n"
  )
  checks <- data.frame(
    check = c(
      "status_path_construction_passes",
      "three_status_partition_is_complete",
      "distribution_grid_is_complete",
      "pairwise_effect_size_grid_is_complete",
      "annual_states_are_allowed",
      "annual_states_are_mutually_exclusive",
      "annual_state_shares_sum_to_one",
      "unresolved_location_share_is_below_one_tenth_percent",
      "persistent_inside_horizons_are_complete",
      "matched_persistence_has_both_arms_and_horizons",
      "matched_annual_paths_are_unique",
      "matched_annual_state_shares_sum_to_one",
      "endpoint_audit_has_both_arms_and_horizons",
      "control_groups_exist_through_plus_five",
      "plus_six_does_not_change_retained_design_rows",
      "completion_year_certification_passes",
      "completion_year_reporting_grid_is_complete",
      "completion_cumulative_equals_six_times_average",
      "all_reportable_outputs_registered_in_inventory",
      "frozen_post_completion_cumulative_is_primary",
      "event_year_does_not_define_retention",
      "career_metrics_stop_at_t_minus_one",
      "patent_location_is_not_labelled_employment",
      "figure_exists_and_is_nonempty",
      "all_declared_sources_exist"
    ),
    pass = c(
      isTRUE(construction$pass),
      setequal(counts$retention_status, config$status_groups) &&
        sum(counts$inventors) == construction$status_rows,
      nrow(distributions) ==
        length(config$status_groups) * 2L,
      nrow(pairwise) == 6L &&
        all(is.finite(pairwise$standardized_mean_difference)),
      allowed_states,
      nrow(paths) == nrow(unique(paths[
        c("deal_id", "codinv", "event_time")
      ])),
      all(abs(share_totals$share - 1) < 1e-12),
      unresolved_share < 0.001,
      identical(sort(persistence$horizon), c(3L, 5L)),
      setequal(matched_persistence$arm, c("treated", "control")) &&
        setequal(matched_persistence$horizon, c(3L, 5L)) &&
        nrow(matched_persistence) == 4L,
      nrow(matched_paths) == nrow(unique(matched_paths[
        c("arm", "deal_id", "codinv", "event_time")
      ])),
      all(abs(matched_share_totals$weighted_share - 1) < 1e-12),
      setequal(endpoints$arm, c("treated", "control")) &&
        setequal(endpoints$event_time, c(5L, 6L)),
      endpoints$weighted_exists_through_horizon_share[
        endpoints$arm == "control" & endpoints$event_time == 5
      ] > 0.999999,
      length(unique(endpoints$design_rows[
        endpoints$arm == "treated"
      ])) == 1L &&
        length(unique(endpoints$design_rows[
          endpoints$arm == "control"
        ])) == 1L,
      completion_pass,
      nrow(timing) == 3L,
      abs(
        timing_cum$estimate - 6 * timing_avg$estimate
      ) < 1e-10,
      all(registration$registered) &&
        !anyNA(registration$result_id) &&
        !anyDuplicated(registration$result_id) &&
        all(!is.na(registration$inventory_status)) &&
        all(!is.na(registration$main_text_eligible)),
      registration$inventory_status[
        registration$package_estimand == "frozen_cumulative_t1_to_t5"
      ] == "primary" &&
        registration$role[
          registration$package_estimand == "frozen_cumulative_t1_to_t5"
        ] == "primary_full_calendar_year" &&
        registration$inventory_status[
          registration$package_estimand == "cumulative_t0_to_t5"
        ] == "companion",
      construction$event_year_status_violations == 0L,
      construction$career_age_lookahead_rows == 0L &&
        construction$patent_stock_lookahead_rows == 0L,
      grepl(
        "patent affiliation, not employment",
        note_text, fixed = TRUE
      ),
      file.exists(figure_path) && file.info(figure_path)$size > 10000,
      all(file.exists(config$source_files))
    ),
    stringsAsFactors = FALSE
  )
  certification_path <- file.path(
    config$output_dir, "d1_stayer_descriptives_certification.csv"
  )
  lmv2_d1_write_csv(checks, certification_path)
  if (!all(checks$pass)) {
    stop(
      "D1 certification failed: ",
      paste(checks$check[!checks$pass], collapse = ", "),
      call. = FALSE
    )
  }

  artifact_paths <- c(
    list.files(
      config$output_dir, full.names = TRUE, recursive = FALSE
    ),
    list.files(
      config$results_dir, full.names = TRUE, recursive = FALSE
    ),
    config$results_note
  )
  artifact_paths <- artifact_paths[
    file.exists(artifact_paths) &
      !dir.exists(artifact_paths) &
      basename(artifact_paths) != "d1_stayer_descriptives_manifest.csv"
  ]
  input_paths <- c(
    config$status_partition,
    config$status_certification,
    config$p8_endpoints,
    config$p8_certification,
    config$retained_weights,
    config$retained_weights_certification,
    config$completion_year_results,
    config$completion_year_dynamic,
    config$completion_year_certification,
    config$master_inventory,
    config$freeze_file,
    config$source_files
  )
  manifest_paths <- unique(c(input_paths, artifact_paths))
  manifest <- data.frame(
    role = ifelse(
      manifest_paths %in% input_paths, "input_or_source", "artifact"
    ),
    path = normalizePath(
      manifest_paths, winslash = "/", mustWork = TRUE
    ),
    sha256 = vapply(
      manifest_paths, digest::digest, character(1),
      file = TRUE, algo = "sha256", serialize = FALSE
    ),
    bytes = unname(file.info(manifest_paths)$size),
    stringsAsFactors = FALSE
  )
  lmv2_d1_write_csv(
    manifest,
    file.path(config$output_dir, "d1_stayer_descriptives_manifest.csv")
  )

  invisible(list(
    checks = checks,
    timing = timing,
    persistence = persistence,
    management = management,
    figure = figure_path
  ))
}

if (sys.nframe() == 0L) {
  lmv2_d1_report_certify()
  message("D1 retained-status descriptives reported and certified.")
}
