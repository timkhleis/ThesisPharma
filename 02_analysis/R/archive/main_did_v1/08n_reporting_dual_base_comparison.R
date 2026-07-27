# Dual-base reporting: package the varying-base event study as the primary
# presentation diagnostic (explicit, annotated t=-5 window-boundary artifact)
# alongside the universal-base bootstrap table as the secondary/technical
# table (the actual HonestDiD input). Pure repackaging -- no new att_gt()
# calls; reads outputs already produced by 08d (varying base) and 08h
# (universal base, deal-clustered bootstrap).
#
# Run from the project root after 08d_pretrend_concentration_check.R and
# 08h_primary_matched_bootstrap.R:
#   Rscript 02_analysis/R/08n_reporting_dual_base_comparison.R

BASE    <- normalizePath("02_analysis", mustWork = TRUE)
TRIANG_RESULTS  <- file.path(BASE, "output", "results", "cs2021_triangulation")
SUPPORT_RESULTS <- file.path(BASE, "output", "results", "cs2021_common_support")
RESULTS <- file.path(BASE, "output", "results", "cs2021_reporting")
FIGS    <- file.path(BASE, "output", "figures", "preliminary_results")

source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Missing package: ggplot2")

dir.create(RESULTS, recursive = TRUE, showWarnings = FALSE)
dir.create(FIGS, recursive = TRUE, showWarnings = FALSE)
banner  <- function(x) message("\n", strrep("=", 60), "\n  ", x, "\n", strrep("=", 60))
write_result <- function(df, filename) {
  utils::write.csv(df, file.path(RESULTS, filename), row.names = FALSE, na = "")
}

banner("LOADING VARYING-BASE (PRIMARY DIAGNOSTIC) AND UNIVERSAL-BASE (TECHNICAL) TABLES")

varying <- utils::read.csv(file.path(TRIANG_RESULTS, "pretrend_dynamic_att_varying_base.csv"))
varying$base <- "varying (primary diagnostic)"
varying$se <- NA_real_  # 08d's dynamic table is bstrap=FALSE, diagnostic-only; no SE reported there

universal <- do.call(rbind, lapply(c("active_patenting", "log_patent_count"), function(oc) {
  df <- utils::read.csv(file.path(SUPPORT_RESULTS, paste0("dynamic_att_matched_bootstrap_", oc, ".csv")))
  df$outcome <- oc
  df[c("outcome", "event_time", "att", "se")]
}))
universal$base <- "universal (technical / HonestDiD input)"

banner("COMBINED DUAL-BASE TABLE")

combined <- rbind(
  varying[c("outcome", "event_time", "att", "se", "base")],
  universal[c("outcome", "event_time", "att", "se", "base")]
)
combined$is_boundary_artifact <- combined$event_time == -5 & combined$base == "varying (primary diagnostic)"
combined <- combined[order(combined$outcome, combined$base, combined$event_time), ]
write_result(combined, "reporting_dual_base_table.csv")
print(combined)

# Cross-check: event_time=0 should be closer between the two conventions than
# the pre-period points are (varying-base telescoping mostly affects pre-periods).
banner("CROSS-CHECK AT EVENT_TIME=0")
for (oc in unique(combined$outcome)) {
  v0 <- combined$att[combined$outcome == oc & combined$event_time == 0 & combined$base == "varying (primary diagnostic)"]
  u0 <- combined$att[combined$outcome == oc & combined$event_time == 0 & combined$base == "universal (technical / HonestDiD input)"]
  message(oc, ": varying-base att(0) = ", round(v0, 4), " | universal-base att(0) = ", round(u0, 4),
          " | diff = ", round(v0 - u0, 4))
}

banner("PRIMARY VARYING-BASE FIGURE (t=-5 ANNOTATED)")

label_map <- c(active_patenting = "Active patenting (any patent this year)",
               log_patent_count = "Log(1 + patents)")
plot_data <- varying
plot_data$label_pretty <- label_map[plot_data$outcome]
plot_data$is_artifact <- plot_data$event_time == -5

p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = event_time, y = att)) +
  ggplot2::geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
  ggplot2::geom_vline(xintercept = -0.5, linetype = "dashed", colour = "grey55") +
  ggplot2::geom_rect(
    data = data.frame(xmin = -5.5, xmax = -4.5, ymin = -Inf, ymax = Inf),
    ggplot2::aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
    inherit.aes = FALSE, fill = "#d97706", alpha = 0.12
  ) +
  ggplot2::geom_line(colour = "#1b4332", linewidth = 0.9) +
  ggplot2::geom_point(ggplot2::aes(colour = is_artifact), size = 2.2, show.legend = FALSE) +
  ggplot2::scale_colour_manual(values = c(`FALSE` = "#1b4332", `TRUE` = "#d97706")) +
  ggplot2::facet_wrap(~label_pretty, scales = "free_y", ncol = 2) +
  ggplot2::scale_x_continuous(breaks = -5:5) +
  ggplot2::labs(
    x = "Years relative to acquisition", y = "Group-time average treatment effect",
    subtitle = "Primary diagnostic: varying base period (each pre-period vs. the previous period)",
    caption = "Shaded/orange point at t=-5: documented window-boundary artifact (pre-deal cohort window edge), not a real level deviation -- see 08d/08e. bstrap=FALSE diagnostic (no bootstrap SE); universal-base bootstrap table is the technical HonestDiD input, not shown here."
  ) +
  ggplot2::theme_minimal(base_size = 10) +
  ggplot2::theme(
    panel.grid.minor = ggplot2::element_blank(),
    plot.subtitle = ggplot2::element_text(colour = "#1b4332", face = "italic"),
    plot.caption = ggplot2::element_text(hjust = 0, size = 7),
    plot.background = ggplot2::element_rect(fill = "white", colour = NA)
  )
fig_path <- file.path(FIGS, "figure11_primary_varying_base_annotated.png")
ggplot2::ggsave(fig_path, p, width = 9, height = 4.5, dpi = 300)

banner("DUAL-BASE REPORTING COMPLETE")
message("Outputs: ", RESULTS)
message("Figure: ", fig_path)
