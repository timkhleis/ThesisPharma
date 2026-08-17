# Build thesis Data-section exhibits from the certified local-match-v2 1993
# amendment P2/P3 package. Matching weights are deliberately not used here:
# P4 is not frozen.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
FOUNDATION <- normalizePath(file.path(".worktrees", "lmv2-1993-amendment", "02_analysis"),
                            mustWork = TRUE)
PAR <- file.path(FOUNDATION, "output", "parquet")
P2_AUDIT <- file.path(FOUNDATION, "output", "audit", "local_match_v2", "P2")
RES <- file.path(BASE, "output", "results", "data_section")
FIG <- file.path(BASE, "output", "figures", "data_section")

source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
for (pkg in c("DBI", "duckdb", "ggplot2", "cowplot", "scales")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("Missing package: ", pkg)
}
dir.create(RES, recursive = TRUE, showWarnings = FALSE)
dir.create(FIG, recursive = TRUE, showWarnings = FALSE)

paths <- list(
  treated = file.path(PAR, "derived", "lmv2_treated_primary.parquet"),
  inventor_covariates = file.path(PAR, "derived", "lmv2_p3_treated_inventor_units.parquet"),
  firm_covariates = file.path(PAR, "derived", "lmv2_p3_firm_units.parquet"),
  deal_assignment = file.path(BASE, "output", "parquet", "helper", "deal_assignment.parquet"),
  package_status = file.path(P2_AUDIT, "p2_package_status.csv"),
  cassi_replication = file.path(P2_AUDIT, "cassi_ornaghi_exact_reproduction.csv"),
  cassi_crosswalk = file.path(P2_AUDIT, "cassi_ornaghi_thesis_sample_crosswalk.csv")
)
missing <- names(paths)[!file.exists(unlist(paths))]
if (length(missing)) stop("Missing certified lm_v2 artifacts: ", paste(missing, collapse = ", "))

package_status <- utils::read.csv(paths$package_status, stringsAsFactors = FALSE)
if (!any(package_status$package_status == "PASS")) stop("P2 package is not certified PASS.")
DESIGN_HASH <- unique(package_status$design_hash)
if (length(DESIGN_HASH) != 1L ||
    DESIGN_HASH != "877fff88c2fa107800800f4983721835e92aab51fdaed9b9b0c5f0dacd161930") {
  stop("Unexpected P2 design hash.")
}

sql_path <- function(x) gsub("'", "''", gsub("\\\\", "/", normalizePath(x, mustWork = TRUE)))
p <- lapply(paths[c("treated", "inventor_covariates", "firm_covariates",
                    "deal_assignment")], sql_path)
con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, "PRAGMA threads=2")
DBI::dbExecute(con, "PRAGMA memory_limit='4GB'")

write_csv <- function(x, name) {
  utils::write.csv(x, file.path(RES, paste0(name, ".csv")), row.names = FALSE, na = "")
}
save_figure <- function(plot, stem, width, height) {
  ggplot2::ggsave(file.path(FIG, paste0(stem, ".pdf")), plot,
                  width = width, height = height, units = "in",
                  device = grDevices::cairo_pdf)
  ggplot2::ggsave(file.path(FIG, paste0(stem, ".png")), plot,
                  width = width, height = height, units = "in", dpi = 320, bg = "white")
}
fmt <- function(x, digits = 2) {
  ifelse(is.na(x), "--", formatC(x, digits = digits, format = "f", big.mark = ","))
}
tex_count <- function(x) {
  ifelse(is.na(x), "--", format(x, big.mark = ",", scientific = FALSE, trim = TRUE))
}
tex_escape <- function(x) {
  x <- gsub("&", "\\\\&", x, fixed = TRUE)
  gsub("%", "\\\\%", x, fixed = TRUE)
}

# Thesis template palette (see thesis_template/main.tex).
THESIS_ACCENT <- "#9B1B30"
THESIS_ACCENT_DARK <- "#671522"
THESIS_WARM_GREY <- "#756A67"
THESIS_TINT <- "#F7F1F3"
THESIS_TEXT <- "#2F2A2B"
THESIS_MUTED_ROSE <- "#C39AA1"
THESIS_LINE <- "#625A5C"
LIGHT_GREY <- "#DDD6D8"

# Cohort figures reserve the accent for the two focal reads (deals line and
# the n= inventor capsules); deal-value bars stay neutral grey so they read
# as context rather than competing for the same red channel.
COHORT_BAR <- "#DAD3D1"
COHORT_LINE <- THESIS_ACCENT
COHORT_CAPSULE_FILL <- THESIS_TINT
COHORT_CAPSULE_TEXT <- THESIS_ACCENT_DARK

# Retain the semantic names used by the figure code below while mapping every
# element to the thesis template palette.
GREEN <- THESIS_ACCENT_DARK
MID_GREEN <- THESIS_MUTED_ROSE
PALE_GREEN <- THESIS_TINT
ORANGE <- THESIS_WARM_GREY
MUTED_ORANGE <- THESIS_LINE
GREY <- THESIS_WARM_GREY

paper_theme <- function(base_size = 10) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      panel.grid = ggplot2::element_blank(),
      plot.title = ggplot2::element_text(
        face = "bold", colour = THESIS_ACCENT,
        size = base_size + 2.5, margin = ggplot2::margin(b = 4)
      ),
      plot.subtitle = ggplot2::element_text(
        colour = THESIS_WARM_GREY, size = base_size - 1, margin = ggplot2::margin(b = 10)
      ),
      plot.caption = ggplot2::element_text(colour = THESIS_WARM_GREY, size = base_size - 2, hjust = 0),
      axis.line.x = ggplot2::element_line(colour = LIGHT_GREY, linewidth = 0.4),
      axis.ticks.x = ggplot2::element_line(colour = LIGHT_GREY, linewidth = 0.4),
      axis.ticks.length.x = grid::unit(0.12, "lines"),
      axis.text = ggplot2::element_text(colour = THESIS_TEXT),
      axis.title = ggplot2::element_text(colour = THESIS_TEXT),
      plot.background = ggplot2::element_rect(fill = "white", colour = NA),
      plot.margin = ggplot2::margin(12, 14, 10, 12)
    )
}

# One row per certified treated inventor-deal unit. P2 status is defined from
# the first post-deal patent in t=0,...,5; P3 supplies all pre-deal covariates.
units <- DBI::dbGetQuery(con, sprintf("
  WITH t AS (
    SELECT CAST(codinv AS BIGINT) codinv, CAST(deal_id AS BIGINT) deal_id,
           CAST(deal_year AS INTEGER) deal_year, CAST(cohort AS INTEGER) cohort,
           buffered_cohort, target_group, acquirer_group, deal_value, big_deal,
           status_eligible, qualification_route, first_post_patent_year,
           status_eligible_stayer_first_post_t0_t5
    FROM read_parquet('%s')
  ), x AS (
    SELECT CAST(codinv AS BIGINT) codinv, CAST(deal_id AS BIGINT) deal_id,
           active_pre_years, patent_count_5y, patents_early, patents_recent,
           career_age, focal_group_tenure, focal_group_exclusivity,
           patent_trajectory, has_target_company_focal_evidence
    FROM read_parquet('%s')
  )
  SELECT t.*, x.* EXCLUDE(codinv, deal_id),
    CASE
      WHEN t.status_eligible_stayer_first_post_t0_t5 THEN 'P2_STAYER'
      WHEN t.status_eligible AND t.first_post_patent_year IS NOT NULL THEN 'P2_LEAVER'
      WHEN t.status_eligible AND t.first_post_patent_year IS NULL THEN 'P2_NO_POST_5Y'
      ELSE 'NOT_STATUS_ELIGIBLE'
    END AS status_type
  FROM t JOIN x USING(codinv, deal_id)
  ORDER BY deal_year, deal_id, codinv
", p$treated, p$inventor_covariates))

if (nrow(units) != 29694L || length(unique(units$deal_id)) != 345L) {
  stop("Certified P2 contract failed: expected 29,694 inventors and 345 deals.")
}
if (anyDuplicated(units[c("codinv", "deal_id")])) stop("Duplicate P2 inventor-deal rows.")
cohort_range <- range(units$cohort)
if (cohort_range[1] < 1993L || cohort_range[2] != 2010L) {
  stop("Unexpected cohort range.")
}
units$annual_patents_pre5 <- units$patent_count_5y / 5

# P3 firm covariates are joined at deal level. They replace legacy group
# production calculations that were inflated before the P1 repair.
deals <- DBI::dbGetQuery(con, sprintf("
  WITH t AS (
    SELECT CAST(deal_id AS BIGINT) deal_id, CAST(deal_year AS INTEGER) deal_year,
           target_group, MAX(deal_value) deal_value, MAX(big_deal) big_deal,
           COUNT(*)::INTEGER affected_inventors
    FROM read_parquet('%s')
    GROUP BY deal_id, deal_year, target_group
  ), f AS (
    SELECT CAST(deal_id AS BIGINT) deal_id, patent_stock_5y, inventor_count_5y
    FROM read_parquet('%s')
    WHERE role = 'treated'
  ), d AS (
    SELECT CAST(deal_id AS BIGINT) deal_id, target, acquirer
    FROM read_parquet('%s')
  )
  SELECT t.*, t.deal_value / 1000000.0 AS deal_value_billions,
         f.patent_stock_5y AS target_patents_pre5,
         f.inventor_count_5y AS target_inventors_pre5,
         d.target, d.acquirer
  FROM t LEFT JOIN f USING(deal_id)
  LEFT JOIN d USING(deal_id)
  ORDER BY deal_year, deal_id
", p$treated, p$firm_covariates, p$deal_assignment))
if (nrow(deals) != 345L || anyDuplicated(deals$deal_id)) {
  stop("Certified deal sample is not 345 unique deals.")
}
if (anyNA(deals$target_patents_pre5)) stop("Missing P3 firm covariates.")

duckdb::duckdb_register(con, "deals_for_summary", deals)
cohorts <- DBI::dbGetQuery(con, "
  SELECT deal_year, COUNT(*)::INTEGER n_deals,
         SUM(affected_inventors)::INTEGER n_inventors,
         SUM(deal_value_billions) total_value_billions
  FROM deals_for_summary
  GROUP BY deal_year ORDER BY deal_year
")
duckdb::duckdb_unregister(con, "deals_for_summary")
write_csv(cohorts, "cohort_summary_lmv2_p2")

# Concentration of the treated inventor cohort across acquisition deals.
company_case <- function(x) {
  out <- tools::toTitleCase(tolower(x))
  out <- gsub("\\bPlc\\b", "PLC", out)
  out <- gsub("\\bSa\\b", "SA", out)
  out <- gsub("\\bAg\\b", "AG", out)
  out <- gsub("\\bLlc\\b", "LLC", out)
  out <- gsub("\\bAb\\b", "AB", out)
  out <- gsub("\\bInc\\.?\\b", "Inc.", out)
  out <- gsub("\\bLtd\\.?\\b", "Ltd.", out)
  out <- gsub("Smithkline", "SmithKline", out, fixed = TRUE)
  out <- gsub("Glaxosmithkline", "GlaxoSmithKline", out, fixed = TRUE)
  out <- gsub("Inc..", "Inc.", out, fixed = TRUE)
  out <- gsub("Ltd..", "Ltd.", out, fixed = TRUE)
  out
}
deals_ranked <- deals[order(-deals$affected_inventors, deals$deal_id), ]
deals_ranked$rank <- seq_len(nrow(deals_ranked))
deals_ranked$inventor_share <- deals_ranked$affected_inventors /
  sum(deals_ranked$affected_inventors)
deals_ranked$cumulative_share <- cumsum(deals_ranked$inventor_share)
target_name <- ifelse(is.na(deals_ranked$target) | deals_ranked$target == "",
                      paste0("Target group ", deals_ranked$target_group),
                      company_case(deals_ranked$target))
acquirer_name <- ifelse(is.na(deals_ranked$acquirer) | deals_ranked$acquirer == "",
                        "acquirer unavailable", company_case(deals_ranked$acquirer))
deals_ranked$acquisition <- paste0(target_name, " acquired by ", acquirer_name)
deal_name_overrides <- c(
  "70" = "SmithKline Beecham--Glaxo Wellcome merger (forming GlaxoSmithKline)",
  "209" = paste0(
    "Sumitomo Pharmaceuticals--Dainippon Pharmaceutical merger ",
    "(forming Dainippon Sumitomo Pharma)"
  ),
  "47" = "Astra--Zeneca merger (forming AstraZeneca)",
  "46" = "Rhone-Poulenc--Hoechst merger (forming Aventis)"
)
override_index <- match(as.character(deals_ranked$deal_id), names(deal_name_overrides))
has_override <- !is.na(override_index)
deals_ranked$acquisition[has_override] <-
  unname(deal_name_overrides[override_index[has_override]])

top_share <- function(k) sum(head(deals_ranked$inventor_share, k))
inventor_hhi <- sum(deals_ranked$inventor_share^2)
deal_concentration <- data.frame(
  statistic = c("Largest deal share", "Top 3 deal share", "Top 5 deal share",
                "Top 10 deal share", "Top 20 deal share",
                "Inventor-share HHI", "Effective number of equally sized deals",
                "Median inventors per deal", "Maximum inventors in one deal"),
  value = c(top_share(1), top_share(3), top_share(5), top_share(10),
            top_share(20), inventor_hhi, 1 / inventor_hhi,
            stats::median(deals_ranked$affected_inventors),
            max(deals_ranked$affected_inventors)),
  unit = c(rep("share", 5), "index", "deals", "inventors", "inventors"),
  stringsAsFactors = FALSE
)
top_deals <- deals_ranked[1:10, c(
  "rank", "deal_id", "deal_year", "acquisition", "affected_inventors",
  "inventor_share", "cumulative_share", "deal_value_billions"
)]
names(top_deals)[names(top_deals) == "deal_year"] <- "year"
write_csv(deal_concentration, "deal_inventor_concentration_summary")
write_csv(top_deals, "table4_largest_deals_by_target_inventors")

# Figure 1A: two-panel academic version. Bars encode value, line encodes deals.
value_scale <- max(cohorts$total_value_billions) / max(cohorts$n_deals)
cohorts$deals_on_value_axis <- cohorts$n_deals * value_scale
p_deal_value <- ggplot2::ggplot(cohorts, ggplot2::aes(x = deal_year)) +
  ggplot2::geom_col(ggplot2::aes(y = total_value_billions, fill = "Deal value (bars)"),
                    width = 0.68) +
  ggplot2::geom_line(ggplot2::aes(y = deals_on_value_axis, colour = "Deals (line)"),
                     linewidth = 0.85) +
  ggplot2::geom_point(ggplot2::aes(y = deals_on_value_axis, colour = "Deals (line)"),
                      shape = 21, fill = "white", stroke = 0.85, size = 1.9) +
  ggplot2::scale_fill_manual(values = c("Deal value (bars)" = COHORT_BAR), name = NULL) +
  ggplot2::scale_colour_manual(values = c("Deals (line)" = COHORT_LINE), name = NULL) +
  ggplot2::scale_x_continuous(breaks = seq(1993, 2010, 2),
                              limits = c(1992.5, 2010.5)) +
  ggplot2::scale_y_continuous(
    "Aggregate deal value (EUR bn)",
    sec.axis = ggplot2::sec_axis(~ . / value_scale, name = "Number of deals",
                                 labels = scales::label_number(accuracy = 1)),
    expand = ggplot2::expansion(mult = c(0, 0.08))
  ) +
  ggplot2::labs(x = NULL, title = "Acquisition activity and aggregate deal value",
                subtitle = "Treated acquisition cohorts, 1993–2010") +
  paper_theme(10) +
  ggplot2::theme(
    panel.grid.major.y = ggplot2::element_line(colour = LIGHT_GREY, linewidth = 0.3),
    legend.position = "top", legend.justification = "left",
    legend.margin = ggplot2::margin(t = 0, b = 0),
    legend.box.spacing = grid::unit(0.4, "lines"),
    legend.key.size = grid::unit(0.85, "lines"),
    legend.text = ggplot2::element_text(size = 9),
    axis.title.y.right = ggplot2::element_text(colour = COHORT_LINE),
    axis.text.x = ggplot2::element_blank()
  )

p_inventors <- ggplot2::ggplot(cohorts, ggplot2::aes(deal_year, n_inventors)) +
  ggplot2::geom_col(fill = COHORT_BAR, width = 0.68) +
  ggplot2::geom_text(ggplot2::aes(label = scales::comma(n_inventors)),
                     vjust = -0.35, size = 2.6, colour = "grey25") +
  ggplot2::scale_x_continuous(breaks = seq(1993, 2010, 2),
                              limits = c(1992.5, 2010.5)) +
  ggplot2::scale_y_continuous(labels = scales::label_number(big.mark = ","),
                              expand = ggplot2::expansion(mult = c(0, 0.12))) +
  ggplot2::labs(x = "Treatment cohort", y = "Target inventors",
                title = "Assigned target inventors") +
  paper_theme(10)

figure1a <- cowplot::plot_grid(p_deal_value, p_inventors, labels = c("A", "B"),
                               ncol = 1, rel_heights = c(1.08, 1),
                               align = "v", axis = "lr")
save_figure(figure1a, "figure1a_cohorts_two_panel", 8.4, 6.5)

# Figure 1B: compact MBB-style alternative with highlighted inventor capsules.
# All 17 cohort labels stay on one row: the "n = " prefix is dropped and the
# capsule is trimmed to the narrowest pill that still separates cleanly from
# its neighbours. The legend identifies the capsules as affected inventors.
bar_max <- max(cohorts$total_value_billions)
label_row_y <- bar_max * 1.18
ylim_top <- label_row_y * 1.12
p_mbb <- ggplot2::ggplot(cohorts, ggplot2::aes(x = deal_year)) +
  ggplot2::geom_col(ggplot2::aes(y = total_value_billions, fill = "Deal value (bars)"),
                    width = 0.68) +
  ggplot2::geom_line(ggplot2::aes(y = deals_on_value_axis, colour = "Deals (line)"),
                     linewidth = 0.85) +
  ggplot2::geom_point(ggplot2::aes(y = deals_on_value_axis, colour = "Deals (line)"),
                      shape = 21, fill = "white", stroke = 0.85, size = 1.9) +
  ggplot2::geom_label(
    ggplot2::aes(y = label_row_y, label = scales::comma(n_inventors),
                colour = "Affected inventors (labels)"),
    fill = COHORT_CAPSULE_FILL, size = 2.55,
    fontface = "bold", linewidth = 0.28,
    label.padding = grid::unit(0.12, "lines"), label.r = grid::unit(0.35, "lines")
  ) +
  ggplot2::scale_fill_manual(values = c("Deal value (bars)" = COHORT_BAR), name = NULL) +
  ggplot2::scale_colour_manual(values = c("Deals (line)" = COHORT_LINE,
                                          "Affected inventors (labels)" = COHORT_CAPSULE_TEXT),
                               name = NULL) +
  ggplot2::guides(colour = ggplot2::guide_legend(override.aes = list(label = "n"))) +
  ggplot2::scale_x_continuous(breaks = 1993:2010,
                              limits = c(1992.5, 2010.5)) +
  ggplot2::scale_y_continuous(
    "Aggregate deal value (EUR bn)", limits = c(0, ylim_top),
    sec.axis = ggplot2::sec_axis(~ . / value_scale, name = "Number of deals",
                                 labels = scales::label_number(accuracy = 1)),
    expand = ggplot2::expansion(mult = c(0, 0.01))
  ) +
  ggplot2::labs(
    x = "Treatment cohort"
  ) +
  paper_theme(10) +
  ggplot2::theme(
    panel.grid.major.y = ggplot2::element_line(colour = LIGHT_GREY, linewidth = 0.3),
    legend.position = "bottom", legend.justification = "right",
    legend.margin = ggplot2::margin(t = 0, b = 0),
    legend.box.spacing = grid::unit(0.4, "lines"),
    legend.key.size = grid::unit(0.85, "lines"),
    legend.text = ggplot2::element_text(size = 9),
    axis.title.y.right = ggplot2::element_text(colour = COHORT_LINE),
    axis.text.x = ggplot2::element_text(size = 8.5)
  )
save_figure(p_mbb, "figure1b_cohorts_mbb", 10.6, 5.0)

# Figure 2: one combined recruitment/classification flow. Ineligible candidates
# visibly branch out of the main flow.
flow_nodes <- data.frame(
  id = c("clock", "pre", "affiliation", "pool", "post",
         "stay", "leave", "exit", "drop_activity", "drop_link"),
  x = c(1.15, 3.55, 5.95, 8.35, 10.75, 13.25, 13.25, 13.25, 3.55, 5.95),
  y = c(0, 0, 0, 0, 0, 1.45, 0, -1.45, -1.35, -1.35),
  label = c(
    "Assign treatment or\nplacebo year, g",
    "Observe EPO patenting\nfrom g-5 to g-1",
    "Use latest pre-deal\npatent affiliation",
    "Recruit into target or\nnon-target inventor pool",
    "Observe EPO patenting\nfrom g to g+5",
    "STAYER\nFirst post-deal patent\nwith relevant group",
    "LEAVER\nFirst post-deal patent\noutside relevant group",
    "EXIT\nNo post-deal EPO patent\nwithin five years",
    "DROP\nNo pre-deal patent activity",
    "DROP\nNo qualifying group link"
  ),
  fill = c(PALE_GREEN, PALE_GREEN, PALE_GREEN, "#C8DED3", PALE_GREEN,
           "#C8DED3", "#F8DEC2", "#E5E7EB", "#F8F1E7", "#F8F1E7"),
  border = c(rep(GREEN, 8), ORANGE, ORANGE),
  stringsAsFactors = FALSE
)
flow_nodes$xmin <- flow_nodes$x - 0.92
flow_nodes$xmax <- flow_nodes$x + 0.92
flow_nodes$ymin <- flow_nodes$y - 0.48
flow_nodes$ymax <- flow_nodes$y + 0.48
flow_edges <- data.frame(x = c(2.07, 4.47, 6.87, 9.27),
                         xend = c(2.63, 5.03, 7.43, 9.83), y = 0, yend = 0)
branch_edges <- data.frame(x = 11.67, xend = 12.31, y = 0,
                           yend = c(1.45, 0, -1.45))
drop_edges <- data.frame(x = c(3.55, 5.95), xend = c(3.55, 5.95),
                         y = c(-0.48, -0.48), yend = c(-0.79, -0.79))
p_flow <- ggplot2::ggplot() +
  ggplot2::geom_segment(
    data = flow_edges, ggplot2::aes(x, y, xend = xend, yend = yend),
    colour = GREEN, linewidth = 0.7,
    arrow = grid::arrow(length = grid::unit(0.12, "inches"), type = "closed")
  ) +
  ggplot2::geom_segment(
    data = branch_edges, ggplot2::aes(x, y, xend = xend, yend = yend),
    colour = GREEN, linewidth = 0.7,
    arrow = grid::arrow(length = grid::unit(0.12, "inches"), type = "closed")
  ) +
  ggplot2::geom_segment(
    data = drop_edges, ggplot2::aes(x, y, xend = xend, yend = yend),
    colour = ORANGE, linewidth = 0.65,
    arrow = grid::arrow(length = grid::unit(0.11, "inches"), type = "closed")
  ) +
  ggplot2::geom_rect(
    data = flow_nodes,
    ggplot2::aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax,
                 fill = fill, colour = border), linewidth = 0.65
  ) +
  ggplot2::geom_text(data = flow_nodes, ggplot2::aes(x, y, label = label),
                     size = 3.05, lineheight = 0.95, colour = "grey18") +
  ggplot2::annotate("segment", x = 1.15, xend = 8.35, y = 2.25, yend = 2.25,
                    colour = GREEN, linewidth = 0.65) +
  ggplot2::annotate("segment", x = 10.75, xend = 13.25, y = 2.25, yend = 2.25,
                    colour = ORANGE, linewidth = 0.65) +
  ggplot2::annotate("text", x = 4.75, y = 2.47, label = "PRE-DEAL RECRUITMENT",
                    size = 2.8, fontface = "bold", colour = GREEN) +
  ggplot2::annotate("text", x = 12, y = 2.47, label = "POST-DEAL CLASSIFICATION",
                    size = 2.8, fontface = "bold", colour = ORANGE) +
  ggplot2::scale_fill_identity() + ggplot2::scale_colour_identity() +
  ggplot2::coord_cartesian(xlim = c(0.05, 14.35), ylim = c(-2.15, 2.75), clip = "off") +
  ggplot2::labs(
    title = "Inventor recruitment and post-deal classification",
    subtitle = "Actual acquisitions and assigned placebo cohorts use the same event-time windows"
  ) +
  ggplot2::theme_void(base_size = 10) +
  ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", colour = GREEN),
                 plot.subtitle = ggplot2::element_text(colour = GREY, size = 9),
                 plot.margin = ggplot2::margin(12, 12, 12, 12))
save_figure(p_flow, "figure2_inventor_assignment_flow", 12.5, 4.8)

# Sample construction. Observations are potential balanced event-time rows,
# making the unit explicit without pretending P4 matching is already complete.
buffered <- units$buffered_cohort
sample_steps <- data.frame(
  sample = c("Cassi--Ornaghi merger universe",
             "Full treated cohort, 1993--2010",
             "Buffered treated cohort, 1993--2008"),
  deals = c(513L, length(unique(units$deal_id)), length(unique(units$deal_id[buffered]))),
  target_inventors = c(NA_integer_, nrow(units), sum(buffered)),
  inventor_year_observations = c(NA_integer_, nrow(units) * 11L, sum(buffered) * 11L),
  status_eligible_stayers = c(NA_integer_,
                              sum(units$status_type == "P2_STAYER"),
                              sum(units$status_type[buffered] == "P2_STAYER")),
  stringsAsFactors = FALSE
)
write_csv(sample_steps, "table1_sample_construction")

status_order <- c("P2_STAYER", "P2_LEAVER", "P2_NO_POST_5Y", "NOT_STATUS_ELIGIBLE")
status_labels <- c(P2_STAYER = "Stayer", P2_LEAVER = "Leaver",
                   P2_NO_POST_5Y = "Exit / no post-deal patent within five years",
                   NOT_STATUS_ELIGIBLE = "Not status-eligible")
status_counts <- as.data.frame(table(factor(units$status_type, levels = status_order)))
names(status_counts) <- c("status_type", "inventors")
status_counts$status <- unname(status_labels[as.character(status_counts$status_type)])
status_counts$share <- status_counts$inventors / nrow(units)
write_csv(status_counts, "status_composition_lmv2_p2")

summarise_vars <- function(dat, variables, labels, sample_name) {
  do.call(rbind, lapply(seq_along(variables), function(i) {
    x <- dat[[variables[i]]]
    x <- x[is.finite(x)]
    data.frame(sample = sample_name, variable = labels[i], n = length(x),
               mean = mean(x), sd = stats::sd(x), median = stats::median(x),
               p25 = unname(stats::quantile(x, 0.25)),
               p75 = unname(stats::quantile(x, 0.75)))
  }))
}
deal_vars <- c("deal_value_billions", "big_deal", "affected_inventors",
               "target_patents_pre5", "target_inventors_pre5")
deal_labs <- c("Target deal value (EUR bn)", "Deal value above EUR 5bn",
               "Assigned target inventors",
               "Distinct target-group patent applications, prior five years",
               "Target-group inventors, prior five years")
deal_stats <- summarise_vars(deals, deal_vars, deal_labs, "Deals in certified P2 cohort")
inv_vars <- c("patent_count_5y", "annual_patents_pre5", "active_pre_years",
              "career_age", "focal_group_tenure", "focal_group_exclusivity",
              "patents_early", "patents_recent")
inv_labs <- c("Inventor patents, prior five years", "Annual patents, prior five years",
              "Active patenting years, prior five years", "Career age (years)",
              "Focal-group tenure (years)", "Focal-group patent exclusivity",
              "Patents in early pre-period", "Patents in recent pre-period")
inv_full <- summarise_vars(units, inv_vars, inv_labs, "All P2 treated inventors")
write_csv(deal_stats, "table3_panel_a_deal_characteristics")
write_csv(inv_full, "table3_panel_b_inventor_characteristics")

pre_patent_groups <- list(
  "Overall treated cohort" = rep(TRUE, nrow(units)),
  "Status-eligible stayers + leavers" =
    units$status_type %in% c("P2_STAYER", "P2_LEAVER"),
  "Stayers" = units$status_type == "P2_STAYER",
  "Leavers" = units$status_type == "P2_LEAVER",
  "Exit / no post-deal patent within five years" =
    units$status_type == "P2_NO_POST_5Y"
)
pre_patent_means <- do.call(rbind, lapply(names(pre_patent_groups), function(label) {
  x <- units$annual_patents_pre5[pre_patent_groups[[label]]]
  data.frame(sample = label, n = length(x), mean_annual_patents_pre5 = mean(x),
             sd_annual_patents_pre5 = stats::sd(x))
}))
rownames(pre_patent_means) <- NULL
write_csv(pre_patent_means, "audit_pre_patent_means_by_status")

# Certified appendix replication: these counts validate ingestion and merging
# of the original replication files. They do not define thesis treatment/status.
cassi_raw <- utils::read.csv(paths$cassi_replication, stringsAsFactors = FALSE)
write_csv(cassi_raw, "table2_cassi_ornaghi_exact_replication_source")
cassi_target_total <- cassi_raw$reproduced_target_leavers +
  cassi_raw$reproduced_target_stayers
cassi_nontarget_total <- cassi_raw$reproduced_nontarget_leavers +
  cassi_raw$reproduced_nontarget_stayers
cassi_counts <- data.frame(
  status = c("Leave", "Stay", "Leave + Stay"),
  target = c(cassi_raw$reproduced_target_leavers,
             cassi_raw$reproduced_target_stayers, cassi_target_total),
  target_share = 100 * c(cassi_raw$reproduced_target_leavers,
                         cassi_raw$reproduced_target_stayers,
                         cassi_target_total) / cassi_target_total,
  non_target = c(cassi_raw$reproduced_nontarget_leavers,
                 cassi_raw$reproduced_nontarget_stayers, cassi_nontarget_total),
  non_target_share = 100 * c(cassi_raw$reproduced_nontarget_leavers,
                             cassi_raw$reproduced_nontarget_stayers,
                             cassi_nontarget_total) / cassi_nontarget_total,
  stringsAsFactors = FALSE
)
if (!identical(as.integer(cassi_counts$target), c(2675L, 7104L, 9779L)) ||
    !identical(as.integer(cassi_counts$non_target),
               c(107001L, 643267L, 750268L))) {
  stop("Certified Cassi--Ornaghi reproduction counts changed.")
}
write_csv(cassi_counts, "table2_cassi_ornaghi_mobility_replication")
write_csv(utils::read.csv(paths$cassi_crosswalk, stringsAsFactors = FALSE),
          "appendix_cassi_ornaghi_thesis_sample_crosswalk")

# LaTeX: Table 1.
table1_tex <- c(
  "\\begin{table}[!htbp]", "\\centering",
  "\\caption{Construction of the Treated Analysis Samples}",
  "\\label{tab:sample_construction}", "\\footnotesize",
  "\\begin{tabularx}{\\textwidth}{@{}Xrrrr@{}}", "\\toprule",
  "Sample & Deals & Target inventors & Inventor-year observations & Status-eligible stayers \\\\",
  "\\midrule"
)
for (i in seq_len(nrow(sample_steps))) {
  r <- sample_steps[i, ]
  table1_tex <- c(table1_tex, sprintf("%s & %s & %s & %s & %s \\\\",
    r$sample, tex_count(r$deals), tex_count(r$target_inventors),
    tex_count(r$inventor_year_observations), tex_count(r$status_eligible_stayers)))
}
table1_tex <- c(
  table1_tex, "\\bottomrule", "\\end{tabularx}",
  "\\begin{minipage}{0.98\\linewidth}\\footnotesize",
  "\\textit{Notes:} The full sample covers acquisition cohorts 1993--2010. The buffered sample ends in 2008 and is retained for designs requiring additional post-deal support. Inventor-year observations show the potential balanced $g-5$ to $g+5$ grid before applying estimation weights.",
  "\\end{minipage}", "\\end{table}"
)
writeLines(table1_tex, file.path(RES, "table1_sample_construction.tex"), useBytes = TRUE)

# LaTeX: Appendix Table 2.
table2_tex <- c(
  "\\begin{table}[!htbp]", "\\centering",
  "\\caption{Replication of the Cassi--Ornaghi Mobility Classification}",
  "\\label{tab:cassi_mobility_replication}", "\\small",
  "\\begin{tabular}{lrr}", "\\toprule",
  "\\# Observations (\\%) & Target & Non-target \\\\", "\\midrule"
)
for (i in seq_len(nrow(cassi_counts))) {
  r <- cassi_counts[i, ]
  label <- if (r$status == "Leave + Stay") "\\textit{Leave + Stay}" else paste0("\\textit{", r$status, "}")
  table2_tex <- c(table2_tex, sprintf("%s & %s (%.1f) & %s (%.1f) \\\\",
    label, tex_count(r$target), r$target_share,
    tex_count(r$non_target), r$non_target_share))
}
table2_tex <- c(
  table2_tex, "\\bottomrule", "\\end{tabular}",
  "\\begin{minipage}{0.94\\linewidth}\\footnotesize",
  "\\textit{Notes:} Appendix replication check. Applying the published restrictions to the supplied replication files reproduces the reported target and non-target leave/stay counts exactly. This validates data ingestion and merging; these benchmark classifications are not used to define the thesis treatment sample.",
  "\\end{minipage}", "\\end{table}"
)
writeLines(table2_tex, file.path(RES, "table2_cassi_ornaghi_mobility.tex"), useBytes = TRUE)

# LaTeX: pooled P2/P3 descriptives, with the level and unit explicit.
table3_tex <- c(
  "\\begin{table}[!htbp]", "\\centering",
  "\\caption{Characteristics of the 1993--2010 Treated Target-Inventor Cohort}",
  "\\label{tab:overall_descriptives}", "\\small",
  "\\begin{tabular}{lrrrrrr}", "\\toprule",
  "Variable & N & Mean & SD & P25 & Median & P75 \\\\", "\\midrule",
  "\\multicolumn{7}{l}{\\textit{Panel A: Deal-level characteristics}} \\\\"
)
for (i in seq_len(nrow(deal_stats))) {
  r <- deal_stats[i, ]
  table3_tex <- c(table3_tex, sprintf("%s & %s & %s & %s & %s & %s & %s \\\\",
    tex_escape(r$variable), tex_count(r$n), fmt(r$mean), fmt(r$sd),
    fmt(r$p25), fmt(r$median), fmt(r$p75)))
}
table3_tex <- c(table3_tex, "\\addlinespace",
                "\\multicolumn{7}{l}{\\textit{Panel B: Inventor-level pre-deal characteristics}} \\\\")
for (i in seq_len(nrow(inv_full))) {
  r <- inv_full[i, ]
  table3_tex <- c(table3_tex, sprintf("%s & %s & %s & %s & %s & %s & %s \\\\",
    tex_escape(r$variable), tex_count(r$n), fmt(r$mean), fmt(r$sd),
    fmt(r$p25), fmt(r$median), fmt(r$p75)))
}
table3_tex <- c(
  table3_tex, "\\bottomrule", "\\end{tabular}",
  "\\begin{minipage}{0.98\\linewidth}\\footnotesize",
  sprintf("\\textit{Notes:} Panel A is deal-level ($N=%s$); Panel B is inventor--deal-level ($N=%s$). Pre-deal measures cover $g-5$ through $g-1$. Target-group patents count distinct EPO applications and give each deal equal weight. Deal values are in EUR billions.",
          tex_count(nrow(deals)), tex_count(nrow(units))),
  "\\end{minipage}", "\\end{table}"
)
writeLines(table3_tex, file.path(RES, "table3_overall_descriptives.tex"), useBytes = TRUE)

# LaTeX: concentration and named mega-deals.
overall_concentration <- data.frame(
  measure = c("Inventor-share HHI", "Effective number of equally sized deals",
              "Largest deal share", "Top 3 deal share", "Top 5 deal share",
              "Top 10 deal share"),
  value = c(sprintf("%.3f", inventor_hhi), sprintf("%.1f", 1 / inventor_hhi),
            sprintf("%.1f\\%%", 100 * top_share(1)),
            sprintf("%.1f\\%%", 100 * top_share(3)),
            sprintf("%.1f\\%%", 100 * top_share(5)),
            sprintf("%.1f\\%%", 100 * top_share(10))),
  stringsAsFactors = FALSE
)
table4_tex <- c(
  "\\begin{table}[!htbp]", "\\centering",
  "\\caption{Concentration of Treated Inventors Across Acquisition Deals}",
  "\\label{tab:deal_concentration}", "\\footnotesize",
  "\\textit{Panel A: Overall concentration}\\\\[2pt]",
  "\\begin{tabular}{lr}", "\\toprule",
  paste0("Measure & Value ", strrep("\\", 2)), "\\midrule"
)
for (i in seq_len(nrow(overall_concentration))) {
  r <- overall_concentration[i, ]
  table4_tex <- c(table4_tex, sprintf("%s & %s %s", r$measure, r$value,
                                      strrep("\\", 2)))
}
table4_tex <- c(
  table4_tex, "\\bottomrule", "\\end{tabular}", "\\par\\vspace{0.8em}",
  "\\noindent\\textit{Panel B: Largest acquisition deals by assigned target inventors}\\\\[2pt]",
  "\\begin{tabularx}{\\textwidth}{@{}rXrrrr@{}}", "\\toprule",
  "Rank & Acquisition & Year & Target inventors & Share (\\%) & Cumulative (\\%) \\\\",
  "\\midrule"
)
for (i in seq_len(nrow(top_deals))) {
  r <- top_deals[i, ]
  table4_tex <- c(table4_tex, sprintf(
    "%s & %s & %s & %s & %.1f & %.1f \\\\",
    r$rank, tex_escape(r$acquisition), r$year,
    tex_count(r$affected_inventors), 100 * r$inventor_share,
    100 * r$cumulative_share
  ))
}
table4_tex <- c(
  table4_tex, "\\bottomrule", "\\end{tabularx}",
  "\\begin{minipage}{0.98\\linewidth}\\footnotesize",
  sprintf(
    paste0(
      "\\textit{Notes:} The table ranks the ten largest deals in the unweighted ",
      "1993--2010 treated cohort of %s inventor--deal assignments. The five ",
      "largest deals account for %.1f\\%% of treated inventors and the ten ",
      "largest for %.1f\\%%. The inventor-share HHI (the sum of squared ",
      "deal-level inventor shares) is %.3f, equivalent to %.1f equally sized ",
      "deals. Because each inventor contributes the same potential ",
      "eleven-year event grid, unweighted inventor-year shares are identical. ",
      "Estimation uses deal-clustered inference; leave-one-mega-deal-out results ",
      "should be reported as a sensitivity check."
    ),
    tex_count(nrow(units)), 100 * top_share(5), 100 * top_share(10),
    inventor_hhi, 1 / inventor_hhi
  ),
  "\\end{minipage}", "\\end{table}"
)
writeLines(table4_tex, file.path(RES, "table4_deal_inventor_concentration.tex"),
           useBytes = TRUE)

concentration_paragraph <- sprintf(
  paste0(
    "The treated inventor sample has an inventor-share HHI of %.3f, equivalent ",
    "to %.1f equally sized deals. Concentration is nevertheless meaningful in ",
    "the upper tail: the five largest deals account for %.1f\\%% of ",
    "treated inventor--deal assignments, while the ten largest account for ",
    "%.1f\\%%. The three largest cohorts---the SmithKline Beecham--Glaxo ",
    "Wellcome merger, Sanofi-Synth\\'elabo's acquisition of Aventis, and the ",
    "Sumitomo--Dainippon merger---alone account for %.1f\\%%. These rankings ",
    "measure inventor exposure rather than transaction value: a transaction ",
    "can have a large research footprint without being among the sample's ",
    "highest-value deals. This concentration motivates deal-clustered ",
    "inference and leave-one-mega-deal-out sensitivity checks."
  ),
  inventor_hhi, 1 / inventor_hhi, 100 * top_share(5), 100 * top_share(10),
  100 * top_share(3)
)
writeLines(concentration_paragraph,
           file.path(RES, "data_section_deal_concentration_paragraph.tex"),
           useBytes = TRUE)

# LaTeX: status-specific productivity requested for alignment with Cassi--Ornaghi.
productivity_tex <- c(
  "\\begin{table}[!htbp]", "\\centering",
  "\\caption{Pre-Deal Inventor Productivity by Post-Deal Status}",
  "\\label{tab:predeal_productivity}", "\\small",
  "\\begin{tabular}{lrrr}", "\\toprule",
  "Sample & N & Mean annual patents & SD \\\\", "\\midrule"
)
for (i in seq_len(nrow(pre_patent_means))) {
  r <- pre_patent_means[i, ]
  productivity_tex <- c(productivity_tex, sprintf("%s & %s & %.3f & %.3f \\\\",
    r$sample, tex_count(r$n), r$mean_annual_patents_pre5, r$sd_annual_patents_pre5))
}
productivity_tex <- c(
  productivity_tex, "\\bottomrule", "\\end{tabular}",
  "\\begin{minipage}{0.94\\linewidth}\\footnotesize",
  "\\textit{Notes:} Productivity equals each inventor's total patents from $g-5$ through $g-1$, divided by five. Status is determined by the first observed post-deal patent within $g$ through $g+5$. These inventor--deal moments are not directly comparable to Cassi--Ornaghi's inventor-status-spell observations.",
  "\\end{minipage}", "\\end{table}"
)
writeLines(productivity_tex, file.path(RES, "audit_predeal_productivity.tex"), useBytes = TRUE)

inspection_tex <- c(
  "\\documentclass[11pt]{article}",
  "\\usepackage[margin=0.55in]{geometry}",
  "\\usepackage{booktabs}", "\\usepackage{array}",
  "\\usepackage{tabularx}", "\\usepackage[T1]{fontenc}",
  "\\begin{document}",
  "\\input{table1_sample_construction.tex}", "\\clearpage",
  "\\input{table2_cassi_ornaghi_mobility.tex}", "\\clearpage",
  "\\input{table3_overall_descriptives.tex}", "\\clearpage",
  "\\input{table4_deal_inventor_concentration.tex}", "\\clearpage",
  "\\input{audit_predeal_productivity.tex}",
  "\\end{document}"
)
writeLines(inspection_tex, file.path(RES, "inspection_tables.tex"), useBytes = TRUE)

manifest <- data.frame(
  artifact = c("figure1a_cohorts_two_panel.pdf/png",
               "figure1b_cohorts_mbb.pdf/png",
               "figure2_inventor_assignment_flow.pdf/png",
               "table1_sample_construction.tex",
               "table2_cassi_ornaghi_mobility.tex",
               "table3_overall_descriptives.tex",
               "table4_deal_inventor_concentration.tex",
               "data_section_deal_concentration_paragraph.tex",
               "audit_predeal_productivity.tex"),
  role = c("Main-text candidate A", "Main-text candidate B", "Main text",
           "Main text", "Appendix replication check", "Main text",
           "Appendix descriptive; main-text sentence",
           "Main-text prose",
           "Internal alignment diagnostic"),
  source = c(rep("Certified lm_v2 P2/P3 package", 4),
             "Certified Cassi--Ornaghi exact-reproduction audit",
             rep("Certified lm_v2 P2/P3 package", 4)),
  design_hash = DESIGN_HASH,
  stringsAsFactors = FALSE
)
write_csv(manifest, "inspection_manifest")

message("Data-section descriptives complete from certified lm_v2 P2/P3 artifacts.")
message("Results: ", RES)
message("Figures: ", FIG)
