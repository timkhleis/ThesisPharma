# ============================================================================
# 11p_plot_nt2010_balance.R -- nt2010 design balance figures (from diagnostics)
# ----------------------------------------------------------------------------
# Package 2. Reads the nt2010 balance/era diagnostics (11o outputs) and writes
# versioned nt2010 figures. Does NOT re-run ebal and does NOT replace any
# existing figure. Full-horizon (1994-2010) P0H5 + P5.
# ============================================================================
BASE <- normalizePath("02_analysis", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
source(file.path(BASE, "R", "11a_main_design_config.R"))
source(file.path(BASE, "R", "11i_robustness_config.R"))
if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Missing package: ggplot2")
suppressMessages(library(ggplot2))

res <- function(name) paste0(NT2010_RESULTS_PREFIX, "_", name)
fig <- function(name) paste0(NT2010_FIGS_PREFIX, "_", name)

covariate_labels <- c(
  log_firm_patent_stock = "Firm patent stock (log)",
  log_firm_inventor_count = "Firm inventor count (log)",
  observed_firm_patent_age = "Firm patent age",
  log_patents_early = "Early firm patents g-6..g-5 (log)",
  log_patents_recent = "Recent firm patents g-4..g-3 (log)",
  share_small_molecule = "Small-molecule share", share_biotech = "Biotech share",
  share_formulation = "Formulation share", no_firm_patent_by_g3 = "No firm patent by g-3",
  no_technology_activity_g6_g3 = "No technology activity g-6..g-3",
  observed_inventor_career_age = "Inventor career age",
  observed_target_patent_tenure = "Target-affiliation tenure",
  log_inventor_patent_stock = "Inventor patent stock (log)",
  target_exclusivity = "Target exclusivity")
covariate_groups <- c(
  stats::setNames(rep("Firm-level", length(FIRM_COVARS)), FIRM_COVARS),
  stats::setNames(rep("Inventor-level", length(INV_COVARS)), INV_COVARS))

# ---- Figure 1: love plot, full-horizon P0H5 + P5 ----
bal <- utils::read.csv(res("balance_all_covariates.csv"), stringsAsFactors = FALSE)
bal <- bal[bal$spec %in% c("P0H5_nt2010", "P5_nt2010") & bal$covariate %in% names(covariate_groups), ]
bal$group <- unname(covariate_groups[bal$covariate])
bal$label <- unname(covariate_labels[bal$covariate])
bal$abs_before <- abs(bal$smd_unweighted)
bal$abs_after  <- abs(bal$abs_smd_weighted)
bal$spec_lab <- ifelse(bal$spec == "P0H5_nt2010", "P0H5 (inventor-weighted)", "P5 (deal-weighted)")
ord <- bal[bal$spec == "P5_nt2010", ]
ord <- ord[order(ord$group, -ord$abs_before), ]
bal$label <- factor(bal$label, levels = rev(unique(ord$label)))

xb <- c(1e-6, 1e-5, 1e-4, 1e-3, 1e-2, 0.05, 0.10, 0.5, 1, 2)
p1 <- ggplot(bal, aes(x = pmax(abs_after, 1e-6), y = label)) +
  geom_segment(aes(x = pmax(abs_after, 1e-6), xend = pmax(abs_before, 1e-6), yend = label),
               color = "#D9D9D9", linewidth = 0.45) +
  geom_vline(xintercept = 0.05, linetype = "dotted", color = "#7A7A7A") +
  geom_vline(xintercept = 0.10, linetype = "dashed", color = "#7A7A7A") +
  geom_point(aes(x = pmax(abs_before, 1e-6)), color = "#B20A2C", shape = 17, size = 2) +
  geom_point(color = "#174A3A", shape = 16, size = 2.4) +
  facet_grid(group ~ spec_lab, scales = "free_y", space = "free_y") +
  scale_x_log10(breaks = xb, labels = as.character(xb), limits = c(1e-6, 2)) +
  labs(title = "nt2010 expanded never-target balance (1994-2010)",
       subtitle = "Absolute SMD: red = before weighting, green = after two-stage EB; dotted 0.05, dashed 0.10",
       x = "Absolute standardized mean difference (log scale)", y = NULL,
       caption = sprintf("Source: %s. P0H5 max|SMD|=%.1e, P5 max|SMD|=%.1e (global).",
         basename(res("balance_all_covariates.csv")),
         max(bal$abs_after[bal$spec == "P0H5_nt2010"]), max(bal$abs_after[bal$spec == "P5_nt2010"]))) +
  theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold", color = "#174A3A"),
        strip.background = element_rect(fill = "#F1F5F3", color = NA),
        strip.text = element_text(face = "bold", color = "#174A3A"),
        axis.text.x = element_text(angle = 30, hjust = 1, size = 8),
        panel.grid.minor = element_blank())
ggplot2::ggsave(fig("balance_loveplot.png"), p1, width = 11.5, height = 7.8, dpi = 300, bg = "white")
message("Wrote ", fig("balance_loveplot.png"))

# ---- Figure 2: per-era max |SMD| with 2009-2010 diagnostic highlighted ----
era <- utils::read.csv(res("era_balance.csv"), stringsAsFactors = FALSE)
era <- era[era$spec %in% c("P0H5_nt2010", "P5_nt2010"), ]
era$spec_lab <- ifelse(era$spec == "P0H5_nt2010", "P0H5 (inventor-weighted)", "P5 (deal-weighted)")
era$diagnostic <- era$era == "2009-2010"
p2 <- ggplot(era, aes(x = era, y = max_abs_smd, fill = diagnostic)) +
  geom_col(width = 0.65) +
  geom_hline(yintercept = 0.05, linetype = "dotted", color = "#7A7A7A") +
  geom_hline(yintercept = 0.10, linetype = "dashed", color = "#7A7A7A") +
  geom_text(aes(label = sprintf("%.2f", max_abs_smd)), vjust = -0.3, size = 3) +
  facet_wrap(~ spec_lab) +
  scale_fill_manual(values = c("FALSE" = "#174A3A", "TRUE" = "#C77A0A"),
                    labels = c("FALSE" = "Established era", "TRUE" = "2009-2010 (expanded diagnostic)")) +
  labs(title = "nt2010 per-era weighted balance (max |SMD|)",
       subtitle = "Global ebal balances across all units; per-era SMDs are a within-window diagnostic",
       x = NULL, y = "Max absolute weighted SMD", fill = NULL) +
  theme_minimal(base_size = 11) +
  theme(plot.title = element_text(face = "bold", color = "#174A3A"),
        strip.background = element_rect(fill = "#F1F5F3", color = NA),
        strip.text = element_text(face = "bold", color = "#174A3A"),
        legend.position = "bottom")
ggplot2::ggsave(fig("era_balance.png"), p2, width = 10.5, height = 5.5, dpi = 300, bg = "white")
message("Wrote ", fig("era_balance.png"))
message("11p DONE")
