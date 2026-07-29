# Build publication-ready thesis assets for the patenting-exit decomposition.

BASE <- normalizePath("02_analysis", winslash = "/", mustWork = TRUE)
source(file.path(BASE, "R", "00_utils.R"))
use_project_library()
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) {
  .libPaths(unique(c(shared_lib, .libPaths())))
}
if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("Missing package: ggplot2")
}
source(file.path(BASE, "R", "00_lmv2_visual_style.R"))

audit_root <- file.path(
  BASE, "output", "audit", "local_match_v2")
main_dir <- file.path(audit_root, "P8_EXIT_DECOMPOSITION")
recurrent_dir <- file.path(audit_root, "P8_RECURRENT_INVENTORS")
figure_dir <- file.path(
  BASE, "output", "figures", "local_match_v2", "patenting_exit")
table_dir <- file.path(
  BASE, "output", "results", "local_match_v2", "patenting_exit")
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

required <- c(
  file.path(main_dir, "exit_decomposition_certification.csv"),
  file.path(main_dir, "exit_decomposition_components.csv"),
  file.path(main_dir, "exit_post_att.csv"),
  file.path(recurrent_dir, "recurrent_certification.csv"),
  file.path(recurrent_dir, "recurrent_decomposition_components.csv"),
  file.path(recurrent_dir, "recurrent_exit_post_att.csv"))
if (any(!file.exists(required))) {
  stop("Missing certified P8 input: ",
       paste(required[!file.exists(required)], collapse = ", "))
}
main_cert <- utils::read.csv(required[[1L]], stringsAsFactors = FALSE)
recurrent_cert <- utils::read.csv(required[[4L]], stringsAsFactors = FALSE)
if (!all(main_cert$pass) || !all(recurrent_cert$pass)) {
  stop("P8 source results are not certified")
}

main <- utils::read.csv(required[[2L]], stringsAsFactors = FALSE)
main <- main[
  main$sample == "headline_1994_2010" &
    main$population %in%
      c("full_cohort", "initially_retained_broad"), ]
recurrent <- utils::read.csv(required[[5L]], stringsAsFactors = FALSE)
component_columns <- c(
  "population", "sample", "component", "estimate",
  "ci_low", "ci_high", "share_of_total")
if (!all(component_columns %in% names(main)) ||
    !all(component_columns %in% names(recurrent))) {
  stop("Component input schema changed")
}
components <- rbind(
  main[component_columns], recurrent[component_columns])
components <- components[
  components$component %in%
    c("cessation", "active_given_survival",
      "patents_per_active_year", "total"), ]

population_labels <- c(
  full_cohort = "Full pre-deal cohort",
  initially_retained_broad = "Initially retained (broad)",
  recurrent_predeal_inventors = "Recurrent pre-deal inventors")
component_labels <- c(
  cessation = "Patenting cessation",
  active_given_survival = "Active years among survivors",
  patents_per_active_year = "Patents per active year")
population_order <- c(
  "Recurrent pre-deal inventors",
  "Initially retained (broad)",
  "Full pre-deal cohort")

components$population_label <- unname(
  population_labels[components$population])
if (anyNA(components$population_label)) {
  stop("Unlabelled population in decomposition inputs")
}
components$population_label <- factor(
  components$population_label, levels = population_order)
component_rows <- components[components$component != "total", ]
component_rows$component_label <- factor(
  unname(component_labels[component_rows$component]),
  levels = unname(component_labels))
component_rows$magnitude <- -component_rows$estimate
if (any(component_rows$magnitude < -1e-12)) {
  stop("The thesis stacked-bar design assumes decline contributions")
}
total_rows <- components[components$component == "total", ]
total_rows$magnitude <- -total_rows$estimate
total_rows$total_label <- sprintf("\u2212%.3f", total_rows$magnitude)

identity <- stats::aggregate(
  estimate ~ population, component_rows, sum)
identity <- merge(
  identity,
  total_rows[c("population", "estimate")],
  by = "population", suffixes = c("_components", "_total"))
if (any(abs(
    identity$estimate_components - identity$estimate_total) > 1e-10)) {
  stop("Thesis figure components do not sum to the total ATT")
}

plot <- ggplot2::ggplot(
  component_rows,
  ggplot2::aes(
    x = magnitude, y = population_label, fill = component_label)) +
  ggplot2::geom_col(
    width = 0.58,
    position = ggplot2::position_stack(reverse = TRUE)) +
  ggplot2::geom_text(
    data = total_rows,
    ggplot2::aes(
      x = magnitude + 0.004, y = population_label,
      label = total_label),
    inherit.aes = FALSE, hjust = 0,
    colour = unname(LMV2_COLOURS["charcoal"]),
    size = 3.4, fontface = "bold") +
  ggplot2::scale_fill_manual(
    values = c(
      "Patenting cessation" = unname(LMV2_COLOURS["forest"]),
      "Active years among survivors" =
        unname(LMV2_COLOURS["slate_blue"]),
      "Patents per active year" =
        unname(LMV2_COLOURS["amber"])),
    drop = FALSE) +
  ggplot2::scale_x_continuous(
    breaks = seq(0, 0.20, by = 0.05),
    limits = c(0, 0.20),
    labels = function(x) sprintf("%.2f", x),
    expand = ggplot2::expansion(mult = c(0, 0))) +
  ggplot2::labs(
    title = "Post-acquisition patent-count decomposition",
    subtitle = NULL,
    x = "Absolute reduction in patents per inventor-year",
    y = NULL,
    caption = paste(strwrap(paste(
      "Notes: Colored segments sum exactly to the total printed at the",
      "end of each bar. Components are Shapley accounting contributions,",
      "not causal mediation effects. Component confidence intervals are",
      "withheld because at least one cohort-arm cell has zero active",
      "patenting."), width = 84), collapse = "\n")) +
  lmv2_theme(base_size = 10.5, legend_position = "bottom") +
  ggplot2::theme(
    panel.grid.major.y = ggplot2::element_blank(),
    legend.box = "vertical",
    legend.text = ggplot2::element_text(size = 9.2),
    axis.text.y = ggplot2::element_text(face = "bold"))

figure_stem <- file.path(
  figure_dir, "figure_patenting_exit_decomposition")
lmv2_save_figure(
  plot, figure_stem, width = 7.4, height = 4.6, dpi = 320)

main_exit <- utils::read.csv(required[[3L]], stringsAsFactors = FALSE)
main_exit <- main_exit[
  main_exit$sample == "headline_1994_2010" &
    main_exit$inference == "deal_wild_bootstrap_t", ]
recurrent_exit <- utils::read.csv(required[[6L]], stringsAsFactors = FALSE)
recurrent_exit <- recurrent_exit[
  recurrent_exit$inference == "deal_wild_bootstrap_t", ]
exit <- rbind(main_exit, recurrent_exit)
exit <- exit[c(
  "population", "estimate", "ci_low", "ci_high", "p_value")]
names(exit)[-1L] <- paste0("exit_", names(exit)[-1L])

table_data <- merge(
  total_rows[c(
    "population", "estimate", "ci_low", "ci_high")],
  exit, by = "population", all.x = TRUE)
names(table_data)[2:4] <- c(
  "total_att", "total_ci_low", "total_ci_high")
for (component in names(component_labels)) {
  z <- component_rows[
    component_rows$component == component,
    c("population", "estimate", "share_of_total")]
  names(z)[2:3] <- paste0(
    component, c("_estimate", "_share"))
  table_data <- merge(table_data, z, by = "population", all.x = TRUE)
}
table_data$population_label <- unname(
  population_labels[table_data$population])
table_data <- table_data[
  match(rev(population_order), table_data$population_label), ]

fmt <- function(x, digits = 3L) {
  formatC(x, digits = digits, format = "f")
}
fmt_ci <- function(lo, hi, scale = 1, digits = 3L) {
  paste0(
    "$[", fmt(scale * lo, digits), ",\\ ",
    fmt(scale * hi, digits), "]$")
}
component_cell <- function(estimate, share) {
  sprintf(
    "\\shortstack{$%s$\\\\(%.1f\\%%)}",
    fmt(estimate), 100 * share)
}
rows <- vapply(seq_len(nrow(table_data)), function(i) {
  z <- table_data[i, ]
  paste0(
    z$population_label, " & ",
    sprintf(
      "\\shortstack{$%s$\\\\%s}",
      fmt(z$total_att), fmt_ci(z$total_ci_low, z$total_ci_high)),
    " & ",
    component_cell(
      z$cessation_estimate, z$cessation_share),
    " & ",
    component_cell(
      z$active_given_survival_estimate,
      z$active_given_survival_share),
    " & ",
    component_cell(
      z$patents_per_active_year_estimate,
      z$patents_per_active_year_share),
    " & ",
    sprintf(
      "\\shortstack{$%s$\\\\%s}",
      fmt(100 * z$exit_estimate, 2L),
      fmt_ci(
        z$exit_ci_low, z$exit_ci_high, scale = 100, digits = 2L)),
    " \\\\")
}, character(1))

table_tex <- c(
  "% Requires booktabs, tabularx, array, and the project \\sourceNote macro.",
  "\\begin{table}[htbp]",
  "\\centering",
  "\\caption{Decomposing the post-acquisition decline in inventor patenting}",
  "\\label{tab:patenting-exit-decomposition}",
  "\\small",
  "\\setlength{\\tabcolsep}{4pt}",
  "\\begin{tabularx}{\\textwidth}{@{}>{\\raggedright\\arraybackslash}Xrrrrr@{}}",
  "\\toprule",
  paste0(
    "Population & \\shortstack{Total ATT\\\\(95\\% CI)}",
    " & \\shortstack{Patenting\\\\cessation}",
    " & \\shortstack{Active years\\\\among survivors}",
    " & \\shortstack{Patents per\\\\active year}",
    " & \\shortstack{$\\Delta\\Pr(Exit)$, pp\\\\(95\\% CI)} \\\\"),
  "\\midrule",
  rows,
  "\\bottomrule",
  "\\end{tabularx}",
  "\\begin{minipage}{\\textwidth}",
  "\\raggedright",
  paste0(
    "\\sourceNote{The first four numerical columns are measured in patents ",
    "per inventor-year. Parentheses below each component report its share ",
    "of the total decline. Components sum exactly to the total ATT and are ",
    "accounting contributions, not causal mediation effects. Total-ATT ",
    "intervals use two-way deal--inventor clustered inference; exit intervals ",
    "use 9,999-replication deal-level wild-bootstrap inference. Patenting ",
    "cessation means reaching the end of observed patenting anywhere in the ",
    "database. Initially retained is the broad certified retained-inventor ",
    "population. Recurrent inventors patent in at least two distinct years ",
    "during $t=-5,\\ldots,-1$. Component intervals are withheld because at ",
    "least one cohort--arm cell has zero active patenting.}"),
  "\\end{minipage}",
  "\\end{table}")
table_path <- file.path(
  table_dir, "table_patenting_exit_decomposition.tex")
writeLines(table_tex, table_path, useBytes = TRUE)

standalone_tex <- c(
  "\\documentclass[10pt,a4paper,landscape]{article}",
  "\\usepackage[a4paper,landscape,left=12mm,right=12mm,top=14mm,bottom=14mm]{geometry}",
  "\\usepackage[T1]{fontenc}",
  "\\usepackage[utf8]{inputenc}",
  "\\usepackage{helvet}",
  "\\renewcommand{\\familydefault}{\\sfdefault}",
  "\\usepackage{booktabs}",
  "\\usepackage{tabularx}",
  "\\usepackage{array}",
  "\\usepackage{xcolor}",
  "\\definecolor{ThesisGrey}{HTML}{6B7280}",
  "\\newcommand{\\sourceNote}[1]{%",
  "  \\par\\smallskip{\\footnotesize\\color{ThesisGrey}\\textit{Notes:} #1}}",
  "\\pagestyle{empty}",
  "\\begin{document}",
  "\\input{table_patenting_exit_decomposition.tex}",
  "\\end{document}")
standalone_tex_path <- file.path(
  table_dir, "table_patenting_exit_decomposition_standalone.tex")
writeLines(standalone_tex, standalone_tex_path, useBytes = TRUE)
pdflatex <- Sys.which("pdflatex")
standalone_pdf_path <- file.path(
  table_dir, "table_patenting_exit_decomposition_standalone.pdf")
if (identical(Sys.getenv("LMV2_COMPILE_TABLE"), "1") &&
    nzchar(pdflatex)) {
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(table_dir)
  status <- system2(
    pdflatex,
    c(
      "-interaction=nonstopmode", "-halt-on-error",
      basename(standalone_tex_path)),
    stdout = "table_patenting_exit_decomposition_standalone.log",
    stderr = "table_patenting_exit_decomposition_standalone.log")
  setwd(old_wd)
  if (!identical(status, 0L) || !file.exists(standalone_pdf_path)) {
    stop("Standalone thesis table failed to compile")
  }
  generated_stem <- tools::file_path_sans_ext(standalone_tex_path)
  unlink(paste0(generated_stem, c(".aux", ".out")))
}

figure_tex <- c(
  "% Requires graphicx and the project \\sourceNote macro.",
  "\\begin{figure}[htbp]",
  "\\centering",
  paste0(
    "\\includegraphics[width=0.94\\textwidth]{",
    "02_analysis/output/figures/local_match_v2/patenting_exit/",
    "figure_patenting_exit_decomposition.pdf}"),
  "\\caption{Accounting decomposition of the post-acquisition patent decline}",
  "\\label{fig:patenting-exit-decomposition}",
  paste0(
    "\\sourceNote{Bars report absolute annual patent-count reductions over ",
    "$t=+1,\\ldots,+5$. Colored segments sum exactly to the total printed ",
    "beside each bar. The components are accounting contributions, not ",
    "causal mediation effects.}"),
  "\\end{figure}")
writeLines(
  figure_tex,
  file.path(table_dir, "figure_patenting_exit_decomposition.tex"),
  useBytes = TRUE)

utils::write.csv(
  table_data,
  file.path(table_dir, "table_patenting_exit_decomposition.csv"),
  row.names = FALSE, na = "")
manifest <- data.frame(
  artifact = c(
    paste0(figure_stem, ".pdf"),
    paste0(figure_stem, ".png"),
    table_path,
    standalone_tex_path,
    if (file.exists(standalone_pdf_path)) standalone_pdf_path else character(),
    file.path(table_dir, "figure_patenting_exit_decomposition.tex"),
    file.path(table_dir, "table_patenting_exit_decomposition.csv")),
  stringsAsFactors = FALSE)
manifest$artifact <- normalizePath(
  manifest$artifact, winslash = "/", mustWork = TRUE)
manifest$bytes <- file.info(manifest$artifact)$size
utils::write.csv(
  manifest, file.path(table_dir, "asset_manifest.csv"),
  row.names = FALSE)

message("Saved thesis figure: ", paste0(figure_stem, ".pdf"))
message("Saved thesis table: ", table_path)
