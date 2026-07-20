# ============================================================================
# 11m_plot_never_target_balance.R -- Grouped love plot for never-target stage 2
# ============================================================================
BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "11a_main_design_config.R"))

if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Missing package: ggplot2")
suppressMessages(library(ggplot2))

balance_path <- file.path(AUDIT_DIR, "never_target_stage2_balance.csv")
figure_path  <- file.path(FIGS_DIR, "never_target_stage2_balance_loveplot.png")

covariate_labels <- c(
  log_firm_patent_stock = "Firm patent stock (log)",
  log_firm_inventor_count = "Firm inventor count (log)",
  observed_firm_patent_age = "Firm patent age",
  log_patents_early = "Early firm patents, g-6 to g-5 (log)",
  log_patents_recent = "Recent firm patents, g-4 to g-3 (log)",
  share_small_molecule = "Small-molecule patent share",
  share_biotech = "Biotech patent share",
  share_formulation = "Formulation patent share",
  no_firm_patent_by_g3 = "No firm patent by g-3",
  no_technology_activity_g6_g3 = "No technology activity, g-6 to g-3",
  observed_inventor_career_age = "Inventor career age",
  observed_target_patent_tenure = "Target-affiliation tenure",
  log_inventor_patent_stock = "Inventor patent stock (log)",
  target_exclusivity = "Target exclusivity"
)

covariate_groups <- c(
  stats::setNames(rep("Firm-level covariates", length(FIRM_COVARS)), FIRM_COVARS),
  stats::setNames(rep("Inventor-level covariates", length(INV_COVARS)), INV_COVARS)
)

bal <- utils::read.csv(balance_path, stringsAsFactors = FALSE)
bal <- bal[bal$covariate %in% names(covariate_groups), , drop = FALSE]
bal$group <- unname(covariate_groups[bal$covariate])
bal$label <- unname(covariate_labels[bal$covariate])
bal$abs_before <- abs(bal$smd_unweighted)
bal$abs_after  <- abs(bal$smd_final)

bal <- bal[order(bal$group, -bal$abs_before), ]
bal$label <- factor(bal$label, levels = rev(bal$label))

plot_data <- rbind(
  data.frame(group = bal$group, label = bal$label,
             stage = "After two-stage EB", smd = bal$abs_after),
  data.frame(group = bal$group, label = bal$label,
             stage = "Before weighting", smd = bal$abs_before)
)
plot_data$stage <- factor(plot_data$stage,
  levels = c("After two-stage EB", "Before weighting"))

x_breaks <- c(1e-8, 1e-7, 1e-6, 1e-5, 1e-4, 1e-3, 1e-2, 0.05, 0.10, 0.5, 1, 2)
x_labels <- c("1e-8", "1e-7", "1e-6", "1e-5", "1e-4", "1e-3", "0.01",
              "0.05", "0.10", "0.5", "1", "2")

p <- ggplot(plot_data, aes(x = smd, y = label, color = stage, shape = stage)) +
  geom_segment(data = bal, aes(x = abs_after, xend = abs_before, y = label, yend = label),
               inherit.aes = FALSE, color = "#D9D9D9", linewidth = 0.45) +
  geom_vline(xintercept = 0.05, linetype = "dotted", color = "#8B8B8B", linewidth = 0.45) +
  geom_vline(xintercept = 0.10, linetype = "dashed", color = "#6F6F6F", linewidth = 0.55) +
  geom_point(size = 2.8, stroke = 0.2) +
  facet_grid(group ~ ., scales = "free_y", space = "free_y") +
  scale_x_log10(breaks = x_breaks, labels = x_labels, limits = c(1e-8, 2)) +
  scale_color_manual(values = c("After two-stage EB" = "#174A3A",
                                "Before weighting" = "#B20A2C")) +
  scale_shape_manual(values = c("After two-stage EB" = 16,
                                "Before weighting" = 17)) +
  labs(
    title = "Never-target two-stage entropy balancing",
    subtitle = "Absolute SMDs before and after weighting; dotted = 0.05, dashed = 0.10",
    x = "Absolute standardized mean difference (log scale)",
    y = NULL,
    color = NULL,
    shape = NULL,
    caption = sprintf("Source: %s. Final max |SMD| = %.2e.",
                      basename(balance_path), max(bal$abs_after, na.rm = TRUE))
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 16, color = "#174A3A"),
    plot.subtitle = element_text(size = 11, color = "#5D6674"),
    panel.grid.minor = element_blank(),
    panel.grid.major.y = element_line(color = "#EAEAEA"),
    panel.grid.major.x = element_line(color = "#ECECEC"),
    strip.background = element_rect(fill = "#F1F5F3", color = NA),
    strip.text.y = element_text(face = "bold", color = "#174A3A"),
    panel.spacing.y = grid::unit(0.7, "lines"),
    axis.text.y = element_text(size = 10.5, color = "#4D4D4D"),
    axis.text.x = element_text(size = 9, color = "#4D4D4D", angle = 30, hjust = 1),
    legend.position = "bottom",
    legend.text = element_text(size = 10.5),
    plot.caption = element_text(size = 9.5, color = "#5D6674", hjust = 1),
    plot.margin = margin(8, 12, 8, 8)
  )

ggplot2::ggsave(figure_path, p, width = 11.2, height = 7.6, dpi = 300, bg = "white")
message("Wrote ", figure_path)
