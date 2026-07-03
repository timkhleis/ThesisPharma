# Build the two-page supervisor memo directly as PDF.
# This is the reproducible fallback when the local MiKTeX installation is unavailable.

BASE <- normalizePath("02_analysis", mustWork = TRUE)
AUDIT <- file.path(BASE, "output", "audit", "preliminary_results")
OUT <- file.path(dirname(BASE), "00_Discussion_Docs", "008_first_results_memo.pdf")
PREVIEW <- file.path(BASE, "output", "figures", "preliminary_results", "memo_page_%02d.png")

read_result <- function(filename) {
  utils::read.csv(file.path(AUDIT, filename), check.names = FALSE)
}

full <- read_result("figure1_event_means_all.csv")
persistent <- read_result("figure2a_event_means_persistent_stayer5.csv")
active <- read_result("figure2b_event_means_patent_active_survivor5.csv")

forest <- "#173F31"
soft_green <- "#EDF4F1"
soft_yellow <- "#FFF8DC"
border <- "#CCD8D2"
grey <- "#4D5B55"

wrapped_text <- function(text, x, y, width = 90, cex = 0.78, line_gap = 0.018,
                         font = 1, col = "#17211D") {
  lines <- unlist(strwrap(text, width = width, simplify = FALSE), use.names = FALSE)
  for (i in seq_along(lines)) {
    graphics::text(x, y - (i - 1) * line_gap, lines[i], adj = c(0, 1),
                   cex = cex, font = font, col = col)
  }
  y - length(lines) * line_gap
}

draw_box <- function(x, y, w, h, fill = soft_green) {
  graphics::rect(x, y - h, x + w, y, col = fill, border = border, lwd = 0.8)
}

draw_table <- function(x, y, w, rows, values, row_h = 0.029, cex = 0.69,
                       header_left = "Stage", header_right = "Count") {
  graphics::segments(x, y, x + w, y, col = forest, lwd = 1.0)
  graphics::text(x, y - row_h * 0.55, header_left, adj = c(0, 0.5), cex = cex, font = 2)
  graphics::text(x + w, y - row_h * 0.55, header_right, adj = c(1, 0.5), cex = cex, font = 2)
  graphics::segments(x, y - row_h, x + w, y - row_h, col = grey, lwd = 0.6)
  for (i in seq_along(rows)) {
    yy <- y - row_h * (i + 0.55)
    graphics::text(x, yy, rows[i], adj = c(0, 0.5), cex = cex)
    graphics::text(x + w, yy, values[i], adj = c(1, 0.5), cex = cex)
    graphics::segments(x, y - row_h * (i + 1), x + w, y - row_h * (i + 1),
                       col = "#D7DFDB", lwd = 0.35)
  }
}

draw_line_plot <- function(df, x, y, w, h, title, y_label, y_limits = NULL) {
  left <- x + 0.085 * w
  right <- x + 0.98 * w
  bottom <- y + 0.15 * h
  top <- y + 0.87 * h
  if (is.null(y_limits)) {
    y_limits <- range(df$patent_count_mean, na.rm = TRUE)
    pad <- diff(y_limits) * 0.08
    y_limits <- y_limits + c(-pad, pad)
  }
  map_x <- function(v) left + (v + 5) / 10 * (right - left)
  map_y <- function(v) bottom + (v - y_limits[1]) / diff(y_limits) * (top - bottom)

  graphics::rect(x, y, x + w, y + h, col = "white", border = NA)
  y_ticks <- pretty(y_limits, n = 4)
  y_ticks <- y_ticks[y_ticks >= y_limits[1] & y_ticks <= y_limits[2]]
  for (tick in y_ticks) {
    yy <- map_y(tick)
    graphics::segments(left, yy, right, yy, col = "#E5E9E7", lwd = 0.6)
    graphics::text(left - 0.012 * w, yy, format(tick, trim = TRUE, digits = 2),
                   adj = c(1, 0.5), cex = 0.55, col = grey)
  }
  for (tick in -5:5) {
    xx <- map_x(tick)
    graphics::segments(xx, bottom, xx, top, col = "#F0F2F1", lwd = 0.45)
    graphics::text(xx, bottom - 0.035 * h, tick, cex = 0.52, col = grey)
  }
  graphics::segments(map_x(-0.5), bottom, map_x(-0.5), top,
                     col = "#777777", lty = 2, lwd = 0.8)
  graphics::lines(map_x(df$event_time), map_y(df$patent_count_mean), col = forest, lwd = 2)
  graphics::points(map_x(df$event_time), map_y(df$patent_count_mean), col = forest, pch = 16, cex = 0.62)
  graphics::text(x + w / 2, y + h - 0.02 * h, title, cex = 0.72, font = 2, col = forest)
  graphics::text(x + w / 2, y + 0.01 * h, "Years relative to acquisition", cex = 0.56)
  graphics::text(x + 0.008 * w, y + h / 2, y_label, srt = 90, cex = 0.56)
}

new_page <- function() {
  graphics::par(mar = c(0, 0, 0, 0), xaxs = "i", yaxs = "i", family = "sans")
  graphics::plot.new()
  graphics::plot.window(xlim = c(0, 1), ylim = c(0, 1))
}

preview_mode <- identical(Sys.getenv("MEMO_PREVIEW"), "1")
if (preview_mode) {
  grDevices::png(PREVIEW, width = 827, height = 1169, res = 100)
} else {
  grDevices::pdf(OUT, width = 8.27, height = 11.69, onefile = TRUE, useDingbats = FALSE)
}
on.exit(grDevices::dev.off(), add = TRUE)

# Page 1
new_page()
graphics::text(0.04, 0.972, "First Results: Acquisitions and Inventor Productivity",
               adj = c(0, 1), cex = 1.45, font = 2, col = forest)
graphics::text(0.96, 0.969, "29 June 2026", adj = c(1, 1), cex = 0.68, col = grey)
wrapped_text(
  "Preliminary descriptive evidence for supervisor discussion. The causal estimation panel is complete, but no CS(2021) coefficient is reported until the official did package runs successfully.",
  0.04, 0.935, width = 135, cex = 0.7, line_gap = 0.016, col = grey
)

draw_box(0.04, 0.895, 0.92, 0.145)
graphics::text(0.055, 0.88, "Three preliminary facts", adj = c(0, 1), cex = 0.78, font = 2)
facts <- c(
  "1. The corrected sample is anchored to the published 513-merger universe. It retains 478 target-spine deals after Cassi's target-side exclusions; 345 lie in the clean window.",
  "2. Among 28,279 clean-sample target inventors, mean annual patenting falls from 0.474 in year -1 to 0.246 in the deal year and 0.113 by year +5. These are descriptive means.",
  "3. Continuing-patenter stayers remain productive, while the broader persistent-stayer sample increasingly includes silent inventors and career exits."
)
yy <- 0.852
for (fact in facts) yy <- wrapped_text(fact, 0.06, yy, width = 133, cex = 0.64, line_gap = 0.015) - 0.004

graphics::text(0.04, 0.72, "Corrected sample construction", adj = c(0, 1), cex = 0.78, font = 2, col = forest)
draw_table(
  0.04, 0.695, 0.30,
  c("Merger-list deals", "Unique spine matches", "After target drop flags",
    "Clean target-spine deals", "Clean deals with inventors",
    "Clean target inventors", "Status-eligible inventors"),
  c("513", "490", "478", "345", "338", "28,279", "27,510"),
  row_h = 0.031, cex = 0.61
)
graphics::text(0.04, 0.435, "Why the deal count changed", adj = c(0, 1), cex = 0.72, font = 2, col = forest)
wrapped_text(
  "The group-history files cover more mergers than the published sample. The corrected code anchors each event to deal_map.deal_id, excludes 22 unmatched deals and one ambiguous match, and then applies Cassi's drop flags.",
  0.04, 0.412, width = 48, cex = 0.61, line_gap = 0.015
)
draw_line_plot(full, 0.37, 0.34, 0.59, 0.39,
               "Full pre-deal target cohort (descriptive)", "Mean patent count")
wrapped_text(
  "Figure 1. Missing inventor-years are coded as zero patent output. The profile contains no comparison group and is not a treatment-effect estimate.",
  0.39, 0.325, width = 83, cex = 0.56, line_gap = 0.013, col = grey
)

draw_box(0.04, 0.19, 0.92, 0.105, fill = soft_yellow)
graphics::text(0.055, 0.175, "Causal estimation status", adj = c(0, 1), cex = 0.72, font = 2)
wrapped_text(
  "The balanced CS(2021) panel contains 903,420 inventor-year observations for 32,265 inventors over 1988-2015 and passes uniqueness and balance checks. CRAN access currently blocks installation of the official did package, so this memo does not substitute an unvalidated estimator.",
  0.055, 0.15, width = 137, cex = 0.62, line_gap = 0.015
)

# Page 2
new_page()
graphics::text(0.04, 0.972, "Stayer Classification and Intensive-Margin Evidence",
               adj = c(0, 1), cex = 1.25, font = 2, col = forest)
draw_line_plot(persistent, 0.04, 0.57, 0.44, 0.34,
               "Persistent stayers (N = 3,696)", "Mean patent count", c(0.4, 1.32))
draw_line_plot(active, 0.52, 0.57, 0.44, 0.34,
               "Continuing patenters (N = 1,309)", "Mean patent count", c(0.5, 1.52))
wrapped_text(
  "Figure 2. Both profiles condition on post-treatment outcomes. The continuing-patenter panel is a selected intensive-margin result, not evidence for the total causal effect on retained inventors.",
  0.05, 0.555, width = 137, cex = 0.58, line_gap = 0.014, col = grey
)

graphics::text(0.04, 0.49, "Comparison with Cassi-Ornaghi", adj = c(0, 1), cex = 0.75, font = 2, col = forest)
draw_table(
  0.04, 0.462, 0.42,
  c("Cassi-Ornaghi", "Thesis, corrected", "Thesis, clean window"),
  c("7,104 / 2,675 / 72.6%", "4,419 / 1,771 / 71.4%", "4,160 / 1,662 / 71.5%"),
  row_h = 0.034, cex = 0.58,
  header_left = "Source", header_right = "Stayers / leavers / share"
)
wrapped_text(
  "Entries show stayers / leavers / stayer share. The composition is close, but the thesis has fewer active inventors because of the matched-spine restriction, fixed windows, stricter affiliation assignment, and first-exposure timing.",
  0.04, 0.33, width = 61, cex = 0.58, line_gap = 0.014
)

graphics::text(0.54, 0.49, "Interpretation discipline", adj = c(0, 1), cex = 0.75, font = 2, col = forest)
interpretation <- c(
  "1. The main full-cohort design is fixed before treatment.",
  "2. T_Ever_Stayed records at least one acquirer patent; it does not imply continuous retention.",
  "3. Persistent-stayer and continuing-patenter profiles describe selected populations.",
  "4. Their divergence shows why career visibility must not be imposed silently."
)
yy <- 0.46
for (line in interpretation) yy <- wrapped_text(line, 0.54, yy, width = 61, cex = 0.59, line_gap = 0.014) - 0.006

draw_box(0.04, 0.225, 0.92, 0.17, fill = soft_yellow)
graphics::text(0.055, 0.207, "Feedback requested from Prof. Cassi", adj = c(0, 1), cex = 0.74, font = 2)
questions <- c(
  "1. Is there an intended mapping for the 22 merger-list deals without an exact group-history match?",
  "2. Which event matches the 2008 acquisition value of 25,000: Curacyte Discovery or Hunter-Fleming?",
  "3. When group-history timing differs from the legal merger year, should treatment follow organizational integration or legal closing?"
)
yy <- 0.18
for (question in questions) yy <- wrapped_text(question, 0.06, yy, width = 133, cex = 0.62, line_gap = 0.015) - 0.006

graphics::text(
  0.04, 0.03,
  "All figures are preliminary. Planned CS(2021): not-yet-treated controls, deal-level clustering, matched-spine sample.",
  adj = c(0, 0), cex = 0.55, col = grey
)

grDevices::dev.off()
message("Written: ", if (preview_mode) PREVIEW else OUT)
