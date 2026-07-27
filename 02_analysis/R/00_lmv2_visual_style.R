# Shared visual identity for Local Match v2 thesis figures.
#
# Source this file after ggplot2 is available:
#   source("02_analysis/R/00_lmv2_visual_style.R")

LMV2_COLOURS <- c(
  forest = "#1B4332",
  sage = "#8FAF9D",
  pale_sage = "#DCE8E1",
  slate_blue = "#4F6F8F",
  pale_blue = "#DDE6EE",
  amber = "#C28B3C",
  brick = "#A65F5B",
  plum = "#766A8F",
  charcoal = "#2F3A3F",
  mid_grey = "#6B7280",
  light_grey = "#D9DEE3",
  white = "#FFFFFF"
)

LMV2_TREATMENT_COLOURS <- c(
  "Acquisition-treated" = unname(LMV2_COLOURS["forest"]),
  "Placebo-treated controls" = unname(LMV2_COLOURS["slate_blue"])
)

LMV2_TREATMENT_LINETYPES <- c(
  "Acquisition-treated" = "solid",
  "Placebo-treated controls" = "longdash"
)

LMV2_TREATMENT_SHAPES <- c(
  "Acquisition-treated" = 16,
  "Placebo-treated controls" = 17
)

LMV2_DIAGNOSTIC_COLOURS <- c(
  "Headline estimate" = unname(LMV2_COLOURS["forest"]),
  "Robustness estimate" = unname(LMV2_COLOURS["slate_blue"]),
  "Held-out diagnostic" = unname(LMV2_COLOURS["amber"]),
  "Identification caution" = unname(LMV2_COLOURS["brick"])
)

LMV2_CATEGORICAL_5 <- unname(LMV2_COLOURS[
  c("forest", "slate_blue", "amber", "plum", "brick")
])

LMV2_SEQUENTIAL_GREEN <- c(
  "#DCE8E1", "#AFC8BA", "#789F8A", "#47745F", "#1B4332"
)

lmv2_theme <- function(base_size = 10.5, legend_position = "bottom") {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("lmv2_theme() requires ggplot2")
  }

  ggplot2::theme_minimal(base_size = base_size, base_family = "sans") +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_blank(),
      panel.grid.major.y = ggplot2::element_line(
        colour = LMV2_COLOURS["light_grey"], linewidth = 0.35
      ),
      plot.title = ggplot2::element_text(
        face = "bold", colour = LMV2_COLOURS["forest"],
        size = base_size + 1.5
      ),
      plot.subtitle = ggplot2::element_text(
        colour = LMV2_COLOURS["mid_grey"], size = base_size - 0.5
      ),
      plot.caption = ggplot2::element_text(
        colour = LMV2_COLOURS["mid_grey"], size = base_size - 1.5,
        hjust = 0
      ),
      axis.title = ggplot2::element_text(colour = LMV2_COLOURS["charcoal"]),
      axis.text = ggplot2::element_text(colour = LMV2_COLOURS["charcoal"]),
      strip.text = ggplot2::element_text(
        face = "bold", colour = LMV2_COLOURS["charcoal"]
      ),
      legend.position = legend_position,
      legend.title = ggplot2::element_blank(),
      plot.background = ggplot2::element_rect(
        fill = LMV2_COLOURS["white"], colour = NA
      ),
      panel.background = ggplot2::element_rect(
        fill = LMV2_COLOURS["white"], colour = NA
      ),
      plot.margin = ggplot2::margin(8, 10, 8, 10)
    )
}

lmv2_treatment_scales <- function() {
  list(
    ggplot2::scale_colour_manual(values = LMV2_TREATMENT_COLOURS),
    ggplot2::scale_linetype_manual(values = LMV2_TREATMENT_LINETYPES),
    ggplot2::scale_shape_manual(values = LMV2_TREATMENT_SHAPES)
  )
}

lmv2_save_figure <- function(
    plot, stem, width = 7.2, height = 4.5, dpi = 320) {
  dir.create(dirname(stem), recursive = TRUE, showWarnings = FALSE)
  ggplot2::ggsave(
    paste0(stem, ".png"), plot,
    width = width, height = height, units = "in", dpi = dpi,
    bg = LMV2_COLOURS["white"]
  )
  ggplot2::ggsave(
    paste0(stem, ".pdf"), plot,
    width = width, height = height, units = "in",
    device = grDevices::cairo_pdf
  )
  invisible(c(paste0(stem, ".png"), paste0(stem, ".pdf")))
}
