# Package D1: analyze predetermined career-age and productivity distributions.

if (!exists("lmv2_d1_config")) {
  source(file.path(
    "02_analysis", "R", "42a_lmv2_stayer_descriptives_config.R"
  ))
}

lmv2_d1_distribution_summary <- function(x) {
  x <- x[is.finite(x)]
  q <- stats::quantile(
    x, probs = c(0.10, 0.25, 0.50, 0.75, 0.90),
    names = FALSE, type = 7
  )
  data.frame(
    n = length(x),
    mean = mean(x),
    sd = stats::sd(x),
    p10 = q[[1L]],
    p25 = q[[2L]],
    median = q[[3L]],
    p75 = q[[4L]],
    p90 = q[[5L]],
    stringsAsFactors = FALSE
  )
}

lmv2_d1_smd <- function(x, y) {
  pooled_sd <- sqrt(
    ((length(x) - 1) * stats::var(x) +
       (length(y) - 1) * stats::var(y)) /
      (length(x) + length(y) - 2)
  )
  if (!is.finite(pooled_sd) || pooled_sd == 0) return(NA_real_)
  (mean(x) - mean(y)) / pooled_sd
}

lmv2_d1_analyze_distributions <- function(config = lmv2_d1_config()) {
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
  input_path <- file.path(
    config$output_dir, "status_predeal_metrics.parquet"
  )
  if (!file.exists(input_path)) {
    stop("Run the D1 status-path builder first.", call. = FALSE)
  }
  dir.create(config$output_dir, recursive = TRUE, showWarnings = FALSE)

  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  metrics <- DBI::dbGetQuery(con, sprintf(
    "SELECT * FROM read_parquet(%s)",
    lmv2_d1_sql_string(input_path)
  ))
  if (!identical(
    sort(unique(metrics$retention_status)),
    sort(config$status_groups)
  )) {
    stop("D1 status groups do not match the freeze.", call. = FALSE)
  }

  variables <- c(
    career_age_t_minus_1 = "Career age at t=-1",
    patent_stock_5y = "Patent stock, t=-5 to t=-1"
  )
  summaries <- list()
  k <- 1L
  for (variable in names(variables)) {
    for (status in config$status_groups) {
      row <- lmv2_d1_distribution_summary(
        metrics[metrics$retention_status == status, variable]
      )
      row$variable <- variable
      row$variable_label <- variables[[variable]]
      row$retention_status <- status
      summaries[[k]] <- row[
        c(
          "variable", "variable_label", "retention_status",
          "n", "mean", "sd", "p10", "p25", "median", "p75", "p90"
        )
      ]
      k <- k + 1L
    }
  }
  summary_table <- do.call(rbind, summaries)

  comparisons <- list(
    c("no_post_patent", "initially_retained"),
    c("no_post_patent", "leaver"),
    c("initially_retained", "leaver")
  )
  tests <- list()
  k <- 1L
  for (variable in names(variables)) {
    for (pair in comparisons) {
      x <- metrics[
        metrics$retention_status == pair[[1L]], variable
      ]
      y <- metrics[
        metrics$retention_status == pair[[2L]], variable
      ]
      x <- x[is.finite(x)]
      y <- y[is.finite(y)]
      ks <- suppressWarnings(stats::ks.test(x, y, exact = FALSE))
      tests[[k]] <- data.frame(
        variable = variable,
        variable_label = variables[[variable]],
        group_a = pair[[1L]],
        group_b = pair[[2L]],
        n_a = length(x),
        n_b = length(y),
        mean_a = mean(x),
        mean_b = mean(y),
        median_a = stats::median(x),
        median_b = stats::median(y),
        mean_difference_a_minus_b = mean(x) - mean(y),
        median_difference_a_minus_b =
          stats::median(x) - stats::median(y),
        standardized_mean_difference = lmv2_d1_smd(x, y),
        ks_statistic = unname(ks$statistic),
        ks_p_value = ks$p.value,
        stringsAsFactors = FALSE
      )
      k <- k + 1L
    }
  }
  pairwise_tests <- do.call(rbind, tests)

  career_tests <- pairwise_tests[
    pairwise_tests$variable == "career_age_t_minus_1" &
      pairwise_tests$group_a == "no_post_patent" &
      pairwise_tests$group_b %in% c("initially_retained", "leaver"),
    ,
    drop = FALSE
  ]
  management_plausible <- nrow(career_tests) == 2L &&
    all(
      career_tests$standardized_mean_difference >=
        config$management_smd_threshold
    )
  management <- data.frame(
    diagnostic = "management_transition_plausibility",
    decision = if (management_plausible) {
      "plausible"
    } else {
      "not_supported_by_frozen_effect_size_rule"
    },
    rule = paste0(
      "no_post_patent career age SMD >= ",
      format(config$management_smd_threshold, nsmall = 2),
      " versus both initially_retained and leaver"
    ),
    smd_vs_initially_retained = career_tests$standardized_mean_difference[
      career_tests$group_b == "initially_retained"
    ],
    smd_vs_leaver = career_tests$standardized_mean_difference[
      career_tests$group_b == "leaver"
    ],
    median_gap_vs_initially_retained =
      career_tests$median_difference_a_minus_b[
        career_tests$group_b == "initially_retained"
      ],
    median_gap_vs_leaver =
      career_tests$median_difference_a_minus_b[
        career_tests$group_b == "leaver"
      ],
    stringsAsFactors = FALSE
  )

  status_counts <- as.data.frame(table(
    factor(metrics$retention_status, levels = config$status_groups)
  ))
  names(status_counts) <- c("retention_status", "inventors")
  status_counts$share <- status_counts$inventors /
    sum(status_counts$inventors)

  summary_path <- file.path(
    config$output_dir, "status_distribution_summary.csv"
  )
  test_path <- file.path(
    config$output_dir, "status_distribution_pairwise_tests.csv"
  )
  management_path <- file.path(
    config$output_dir, "management_transition_diagnostic.csv"
  )
  counts_path <- file.path(
    config$output_dir, "status_partition_counts.csv"
  )
  lmv2_d1_write_csv(summary_table, summary_path)
  lmv2_d1_write_csv(pairwise_tests, test_path)
  lmv2_d1_write_csv(management, management_path)
  lmv2_d1_write_csv(status_counts, counts_path)

  invisible(list(
    summary = summary_table,
    tests = pairwise_tests,
    management = management,
    counts = status_counts
  ))
}

if (sys.nframe() == 0L) {
  lmv2_d1_analyze_distributions()
  message("D1 status distributions analyzed.")
}
