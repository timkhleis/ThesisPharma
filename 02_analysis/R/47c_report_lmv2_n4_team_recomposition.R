# Package N4: summarize and report exploratory team recomposition.

if (!exists("lmv2_n4_config")) {
  source(file.path(
    "02_analysis", "R", "47a_lmv2_n4_team_config.R"
  ))
}

lmv2_n4_report <- function(config = lmv2_n4_config()) {
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
  for (pkg in c("DBI", "duckdb", "ggplot2")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop("Missing package: ", pkg, call. = FALSE)
    }
  }
  dir.create(config$results_dir, recursive = TRUE, showWarnings = FALSE)
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, "PRAGMA threads=8")
  read_out <- function(name) {
    lmv2_n4_sql_string(file.path(config$output_dir, name))
  }
  DBI::dbExecute(con, sprintf(
    "CREATE TEMP TABLE roster AS SELECT * FROM read_parquet(%s)",
    read_out("n4_roster.parquet")
  ))
  DBI::dbExecute(con, sprintf(
    "CREATE TEMP TABLE appearances AS SELECT * FROM read_parquet(%s)",
    read_out("post_collaborator_appearances.parquet")
  ))
  DBI::dbExecute(con, sprintf(
    "CREATE TEMP TABLE ties AS SELECT * FROM read_parquet(%s)",
    read_out("baseline_ties.parquet")
  ))
  DBI::dbExecute(con, sprintf(
    "CREATE TEMP TABLE recurrence AS SELECT * FROM read_parquet(%s)",
    read_out("tie_recurrence.parquet")
  ))
  DBI::dbExecute(con, sprintf(
    "CREATE TEMP TABLE focal_years AS SELECT * FROM read_parquet(%s)",
    read_out("focal_year_team_denominators.parquet")
  ))

  composition_annual <- DBI::dbGetQuery(con, "
    WITH categories AS (
      SELECT * FROM (
        VALUES
          ('legacy_target'),
          ('legacy_acquirer'),
          ('new_to_both'),
          ('outside_group')
      ) AS x(category)
    ),
    focal_category AS (
      SELECT
        cohort, deal_id, focal_codinv, weight, event_time,
        collaborator_category AS category,
        COUNT(*) AS category_n
      FROM appearances
      WHERE composition_defined
      GROUP BY ALL
    ),
    focal_year AS (
      SELECT *,
        SUM(category_n) OVER (
          PARTITION BY cohort, deal_id, focal_codinv, event_time
        ) AS total_n
      FROM focal_category
    ),
    focal_grid AS (
      SELECT DISTINCT
        cohort, deal_id, focal_codinv, weight, event_time, total_n
      FROM focal_year
    ),
    complete AS (
      SELECT
        g.*, c.category,
        COALESCE(f.category_n, 0) / g.total_n AS focal_year_share
      FROM focal_grid g
      CROSS JOIN categories c
      LEFT JOIN focal_year f
        USING (
          cohort, deal_id, focal_codinv, weight, event_time,
          total_n, category
        )
    )
    SELECT
      event_time, category,
      SUM(weight * focal_year_share) / SUM(weight) AS weighted_share,
      COUNT(DISTINCT focal_codinv) AS focal_inventors,
      COUNT(DISTINCT deal_id) AS deals
    FROM complete
    GROUP BY ALL
    ORDER BY event_time, category
  ")
  composition_pooled <- DBI::dbGetQuery(con, "
    WITH categories AS (
      SELECT * FROM (
        VALUES
          ('legacy_target'),
          ('legacy_acquirer'),
          ('new_to_both'),
          ('outside_group')
      ) AS x(category)
    ),
    focal_category AS (
      SELECT
        cohort, deal_id, focal_codinv, weight, event_time,
        collaborator_category AS category,
        COUNT(*) AS category_n
      FROM appearances
      WHERE composition_defined
      GROUP BY ALL
    ),
    focal_year AS (
      SELECT *,
        SUM(category_n) OVER (
          PARTITION BY cohort, deal_id, focal_codinv, event_time
        ) AS total_n
      FROM focal_category
    ),
    focal_grid AS (
      SELECT DISTINCT
        cohort, deal_id, focal_codinv, weight, event_time, total_n
      FROM focal_year
    ),
    complete AS (
      SELECT
        g.*, c.category,
        COALESCE(f.category_n, 0) / g.total_n AS focal_year_share
      FROM focal_grid g
      CROSS JOIN categories c
      LEFT JOIN focal_year f
        USING (
          cohort, deal_id, focal_codinv, weight, event_time,
          total_n, category
        )
    )
    SELECT
      category,
      SUM(weight * focal_year_share) /
        SUM(weight) AS weighted_share
    FROM complete
    GROUP BY category
    ORDER BY category
  ")
  raw_composition <- DBI::dbGetQuery(con, "
    SELECT
      collaborator_category AS category,
      COUNT(*) AS collaborator_appearances,
      COUNT(*) / SUM(COUNT(*)) OVER () AS raw_share
    FROM appearances
    WHERE composition_defined
    GROUP BY collaborator_category
    ORDER BY collaborator_category
  ")
  tie_coverage <- DBI::dbGetQuery(con, "
    WITH long AS (
      SELECT cohort, deal_id, focal_codinv, weight,
        'weak_one_patent' AS tie_definition, partner_codinv
      FROM ties WHERE weak_tie
      UNION ALL
      SELECT cohort, deal_id, focal_codinv, weight,
        'strict_persistent' AS tie_definition, partner_codinv
      FROM ties WHERE strict_tie
    ),
    focal AS (
      SELECT
        tie_definition, cohort, deal_id, focal_codinv, weight,
        COUNT(DISTINCT partner_codinv) AS anchor_partners
      FROM long
      GROUP BY ALL
    ),
    roster_total AS (
      SELECT COUNT(*) AS inventors, SUM(weight) AS weight FROM roster
    )
    SELECT
      tie_definition,
      COUNT(*) AS focal_inventors,
      COUNT(DISTINCT deal_id) AS nominal_deals,
      SUM(focal.weight) / MAX(roster_total.weight) AS weighted_coverage,
      AVG(anchor_partners) AS mean_anchor_partners
    FROM focal
    CROSS JOIN roster_total
    GROUP BY tie_definition
    ORDER BY tie_definition
  ")
  tie_recurrence <- DBI::dbGetQuery(con, "
    WITH long AS (
      SELECT
        cohort, deal_id, focal_codinv, weight, partner_codinv, horizon,
        recurred_by_horizon, 'weak_one_patent' AS tie_definition
      FROM recurrence WHERE weak_tie
      UNION ALL
      SELECT
        cohort, deal_id, focal_codinv, weight, partner_codinv, horizon,
        recurred_by_horizon, 'strict_persistent' AS tie_definition
      FROM recurrence WHERE strict_tie
    ),
    focal AS (
      SELECT
        tie_definition, cohort, deal_id, focal_codinv, weight, horizon,
        AVG(CAST(recurred_by_horizon AS DOUBLE)) AS focal_recurrence_share,
        COUNT(*) AS anchor_partners
      FROM long
      GROUP BY ALL
    )
    SELECT
      tie_definition, horizon,
      SUM(weight * focal_recurrence_share) / SUM(weight)
        AS weighted_recurrence_share,
      COUNT(*) AS focal_inventors,
      SUM(anchor_partners) AS anchor_dyads
    FROM focal
    GROUP BY tie_definition, horizon
    ORDER BY tie_definition, horizon
  ")
  denominator_audit <- DBI::dbGetQuery(con, "
    SELECT
      event_time,
      COUNT(*) AS focal_years,
      SUM(CAST(patent_active AS INTEGER)) AS patent_active_focal_years,
      SUM(CAST(has_collaborator AS INTEGER)) AS team_focal_years,
      SUM(CAST(solo_only AS INTEGER)) AS solo_only_focal_years,
      SUM(CAST(defined_collaborators > 0 AS INTEGER))
        AS composition_defined_focal_years
    FROM focal_years
    GROUP BY event_time
    ORDER BY event_time
  ")
  mixed_audit <- DBI::dbGetQuery(con, "
    SELECT
      COUNT(*) AS post_appearances,
      COUNT(*) FILTER (WHERE NOT composition_defined)
        AS unresolved_appearances,
      COUNT(*) FILTER (WHERE mixed_focal_outside)
        AS mixed_focal_outside_appearances
    FROM appearances
  ")

  outputs <- list(
    composition_annual = composition_annual,
    composition_pooled = composition_pooled,
    raw_composition = raw_composition,
    tie_coverage = tie_coverage,
    tie_recurrence = tie_recurrence,
    denominator_audit = denominator_audit,
    mixed_audit = mixed_audit
  )
  for (nm in names(outputs)) {
    lmv2_n4_write_csv(
      outputs[[nm]], file.path(config$results_dir, paste0(nm, ".csv"))
    )
  }

  category_labels <- c(
    legacy_target = "Legacy target",
    legacy_acquirer = "Legacy acquirer",
    new_to_both = "New to both groups",
    outside_group = "Outside focal group"
  )
  composition_annual$label <- unname(
    category_labels[composition_annual$category]
  )
  composition_annual$label <- factor(
    composition_annual$label,
    levels = unname(category_labels)
  )
  figure <- ggplot2::ggplot(
    composition_annual,
    ggplot2::aes(
      x = event_time, y = weighted_share,
      color = label, group = label
    )
  ) +
    ggplot2::geom_line(linewidth = 0.9) +
    ggplot2::geom_point(size = 2) +
    ggplot2::scale_x_continuous(breaks = 1:5) +
    ggplot2::scale_y_continuous(
      labels = function(x) paste0(round(100 * x), "%"),
      limits = c(0, NA)
    ) +
    ggplot2::labs(
      x = "Years after completion",
      y = "Weighted within-inventor-year collaborator share",
      color = NULL,
      title = "Team composition of initially retained inventors",
      subtitle = "Exploratory treated-only description; no causal comparison"
    ) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      legend.position = "bottom",
      panel.grid.minor = ggplot2::element_blank(),
      plot.title.position = "plot"
    )
  figure_path <- file.path(
    config$results_dir, "figure_team_recomposition.png"
  )
  ggplot2::ggsave(
    figure_path, figure, width = 7.4, height = 4.7, dpi = 300
  )

  get_share <- function(category) {
    composition_pooled$weighted_share[
      composition_pooled$category == category
    ]
  }
  coverage_at <- function(definition, field) {
    tie_coverage[
      tie_coverage$tie_definition == definition, field, drop = TRUE
    ]
  }
  recur_at <- function(definition, horizon = 5L) {
    tie_recurrence$weighted_recurrence_share[
      tie_recurrence$tie_definition == definition &
        tie_recurrence$horizon == horizon
    ]
  }
  table_lines <- c(
    "\\begin{tabular}{lrr}",
    "\\toprule",
    "Measure & Strict persistent tie & Weak one-patent tie \\\\",
    "\\midrule",
    paste0(
      "Focal inventors with anchor tie & ",
      format(coverage_at("strict_persistent", "focal_inventors"),
             big.mark = ","), " & ",
      format(coverage_at("weak_one_patent", "focal_inventors"),
             big.mark = ","), " \\\\"
    ),
    paste0(
      "Share of retained focal inventors & ",
      sprintf("%.1f\\%%", 100 * coverage_at(
        "strict_persistent", "weighted_coverage"
      )), " & ",
      sprintf("%.1f\\%%", 100 * coverage_at(
        "weak_one_patent", "weighted_coverage"
      )), " \\\\"
    ),
    paste0(
      "Baseline ties recurring by +5 & ",
      sprintf("%.1f\\%%", 100 * recur_at("strict_persistent")), " & ",
      sprintf("%.1f\\%%", 100 * recur_at("weak_one_patent")), " \\\\"
    ),
    "\\bottomrule",
    "\\end{tabular}"
  )
  writeLines(
    table_lines,
    file.path(config$results_dir, "table_tie_recurrence.tex"),
    useBytes = TRUE
  )

  note <- c(
    "# N4 exploratory retained-inventor team recomposition",
    "",
    "Status: implemented and certified as treated-only descriptive evidence",
    "",
    paste0(
      "Across composition-defined focal-inventor-years, ",
      sprintf("%.1f%%", 100 * get_share("legacy_target")),
      " of collaborator weight is attached to legacy target colleagues, ",
      sprintf("%.1f%%", 100 * get_share("legacy_acquirer")),
      " to legacy acquirer colleagues, ",
      sprintf("%.1f%%", 100 * get_share("new_to_both")),
      " to collaborators new to both pre-deal groups, and ",
      sprintf("%.1f%%", 100 * get_share("outside_group")),
      " to outside-group collaboration."
    ),
    paste0(
      "The strict persistent-tie anchor covers ",
      format(coverage_at("strict_persistent", "focal_inventors"),
             big.mark = ","), " of 2,663 retained focal inventors (",
      sprintf("%.1f%%", 100 * coverage_at(
        "strict_persistent", "weighted_coverage"
      )), "). The exploratory weak one-patent anchor covers ",
      format(coverage_at("weak_one_patent", "focal_inventors"),
             big.mark = ","), " (",
      sprintf("%.1f%%", 100 * coverage_at(
        "weak_one_patent", "weighted_coverage"
      )), ")."
    ),
    paste0(
      "By +5, ",
      sprintf("%.1f%%", 100 * recur_at("strict_persistent")),
      " of strict baseline ties and ",
      sprintf("%.1f%%", 100 * recur_at("weak_one_patent")),
      " of weak baseline ties have reappeared, after first normalizing",
      " within focal inventor."
    ),
    "",
    paste0(
      mixed_audit$unresolved_appearances, " of ",
      mixed_audit$post_appearances,
      " post collaborator appearances lack a resolvable group link and",
      " are excluded from composition shares. ",
      mixed_audit$mixed_focal_outside_appearances,
      " appearances contain both focal and outside group evidence and follow",
      " the frozen inside-category priority rule."
    ),
    "",
    "Every value in this note is exploratory and descriptive. N4 has no",
    "control comparison, treatment-effect estimate, or mechanism test. The",
    "N0 Path Q decision remains unchanged."
  )
  writeLines(note, config$results_note, useBytes = TRUE)
  invisible(c(outputs, list(figure = figure_path)))
}

if (sys.nframe() == 0L) {
  lmv2_n4_report()
  message("N4 exploratory team-recomposition results reported.")
}
