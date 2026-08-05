# Create thesis-facing tables, figures, and a concise results note for the
# certified pooled-window TechDrift amendment.

source(file.path("02_analysis", "R", "50a_lmv2_techdrift_window_config.R"))
config <- lmv2_techdrift_window_config()
shared_lib <- file.path(
  Sys.getenv("USERPROFILE"),"Documents","Thesis",".r_libs")
if (dir.exists(shared_lib)) .libPaths(unique(c(shared_lib,.libPaths())))
source(file.path(config$p6_root,"02_analysis","R",
                 "00_lmv2_visual_style.R"))
if (!requireNamespace("ggplot2",quietly=TRUE)) stop("Missing ggplot2")

certification <- utils::read.csv(
  file.path(config$output_dir,"techdrift_certification.csv"),
  stringsAsFactors=FALSE)
if (!all(certification$pass)) stop("TechDrift certification is not clean")

estimates <- utils::read.csv(
  file.path(config$output_dir,"techdrift_window_estimates.csv"),
  stringsAsFactors=FALSE)
legacy <- utils::read.csv(
  file.path(config$output_dir,"techdrift_legacy_annual_results.csv"),
  stringsAsFactors=FALSE)
coverage <- utils::read.csv(
  file.path(config$output_dir,"techdrift_main_coverage_summary.csv"),
  stringsAsFactors=FALSE)
count_bins <- utils::read.csv(
  file.path(config$output_dir,"techdrift_post_count_bins.csv"),
  stringsAsFactors=FALSE)
count_decomp <- utils::read.csv(
  file.path(config$output_dir,"techdrift_post_count_decomposition.csv"),
  stringsAsFactors=FALSE)
eligibility <- utils::read.csv(
  file.path(config$output_dir,"techdrift_eligibility_audit.csv"),
  stringsAsFactors=FALSE)

report_dir <- file.path(config$output_dir,"reporting")
dir.create(report_dir,recursive=TRUE,showWarnings=FALSE)

wild <- estimates[estimates$inference=="deal_wild_bootstrap_t",]
labels <- c(
  pooled_recent5_main="Pooled post, recent five-year baseline",
  pooled_fullstock_sensitivity="Pooled post, complete observed stock",
  pooled_recent5_binary_sensitivity="Pooled post, binary IPC4 presence",
  pooled_early_post="Early pooled post (t = 1, 2)",
  pooled_late_post="Late pooled post (t = 3, ..., 5)",
  pooled_recent5_exclude_2010="Pooled post, excluding 2010 cohort",
  restricted_prepre_placebo="Restricted pre/pre diagnostic")
wild$label <- unname(labels[wild$specification])

legacy_stayer <- legacy[
  legacy$population=="initially_retained_inventors" &
    legacy$inference=="deal_wild_bootstrap_t",]
legacy_row <- data.frame(
  specification="legacy_annual_stayer",
  label="Prespecified annual TechDrift",
  estimate=legacy_stayer$estimate,
  ci_low=legacy_stayer$ci_low,
  ci_high=legacy_stayer$ci_high,
  p_value=legacy_stayer$p_value,
  role="prespecified_legacy",
  population="initially_retained_inventors",
  estimand="annual_selected_group_contrast",
  stringsAsFactors=FALSE)
wild$population <- "initially_retained_inventors_with_defined_window_ipc4"
wild$estimand <- "windowed_selected_group_portfolio_contrast"
reporting_table <- rbind(
  legacy_row,
  wild[,c("specification","label","estimate","ci_low","ci_high",
          "p_value","role","population","estimand")])
utils::write.csv(
  reporting_table,
  file.path(report_dir,"table_techdrift_measurement_amendment.csv"),
  row.names=FALSE,na="")

plot_levels <- c(
  "Prespecified annual TechDrift",
  "Pooled post, recent five-year baseline",
  "Pooled post, complete observed stock",
  "Pooled post, binary IPC4 presence",
  "Early pooled post (t = 1, 2)",
  "Late pooled post (t = 3, ..., 5)",
  "Pooled post, excluding 2010 cohort",
  "Restricted pre/pre diagnostic")
reporting_table$label <- factor(
  reporting_table$label,levels=rev(plot_levels))
p_est <- ggplot2::ggplot(
  reporting_table,
  ggplot2::aes(x=estimate,y=label,xmin=ci_low,xmax=ci_high))+
  ggplot2::geom_vline(xintercept=0,colour="#6B7280",linewidth=0.4)+
  ggplot2::geom_errorbar(orientation="y",width=0,linewidth=0.55,colour="#355C7D")+
  ggplot2::geom_point(size=2.1,colour="#1F3A5F")+
  ggplot2::labs(
    title="Acquisition and technological portfolio displacement",
    subtitle=paste0(
      "Positive estimates indicate greater displacement among treated ",
      "retained inventors"),
    x="Treated minus matched-control cosine distance",
    y=NULL,
    caption=paste0(
      "Deal wild-bootstrap 95% intervals. The annual and pooled measures ",
      "have different estimands."))+
  lmv2_theme(base_size=10.2,legend_position="none")
lmv2_save_figure(
  p_est,file.path(report_dir,"figure_techdrift_measurement_amendment"),
  width=7.6,height=4.8)

bin_levels <- c("1","2","3-4","5+")
count_bins <- count_bins[count_bins$post_patent_bin %in% bin_levels,]
count_bins$post_patent_bin <- factor(
  count_bins$post_patent_bin,levels=bin_levels)
count_bins$arm_label <- ifelse(
  count_bins$arm=="treated","Treated stayers","Matched controls")
p_count <- ggplot2::ggplot(
  count_bins,
  ggplot2::aes(
    x=post_patent_bin,y=mean_tech_drift,group=arm_label,
    colour=arm_label))+
  ggplot2::geom_line(linewidth=0.7)+
  ggplot2::geom_point(size=2)+
  ggplot2::scale_colour_manual(values=c(
    "Treated stayers"="#A23B3B","Matched controls"="#355C7D"))+
  ggplot2::labs(
    title="Pooled TechDrift and post-acquisition patent support",
    subtitle="Descriptive weighted means; post-patent count is treatment-affected",
    x="Patents during t = 1, ..., 5",
    y="Recent-pre to pooled-post cosine distance",
    colour=NULL)+
  lmv2_theme(base_size=10.2,legend_position="bottom")
lmv2_save_figure(
  p_count,file.path(report_dir,"figure_techdrift_by_post_patent_count"),
  width=7.2,height=4.7)

fmt <- function(x,digits=4) formatC(x,format="f",digits=digits)
row_for <- function(spec) wild[wild$specification==spec,,drop=FALSE]
main <- row_for("pooled_recent5_main")
full <- row_for("pooled_fullstock_sensitivity")
binary <- row_for("pooled_recent5_binary_sensitivity")
early <- row_for("pooled_early_post")
late <- row_for("pooled_late_post")
tail <- row_for("pooled_recent5_exclude_2010")
placebo <- row_for("restricted_prepre_placebo")
common_gap <- count_decomp$estimate[
  count_decomp$diagnostic=="common_count_distribution_gap"]

results_note <- c(
  "# Pooled-window TechDrift amendment results",
  "",
  paste0("**Design:** patent-count-weighted recent pre-acquisition IPC4 ",
         "portfolio (`g-5,...,g-1`) versus the patent-count-weighted pooled ",
         "post-acquisition portfolio (`g+1,...,g+5`). Count weighting is the ",
         "headline construction because it captures technological intensity ",
         "and follows Verginer et al.; binary IPC4 presence is a sensitivity."),
  "",
  "## Governing estimates",
  "",
  paste0("- Prespecified annual stayer TechDrift: ",
         fmt(legacy_stayer$estimate), " [",fmt(legacy_stayer$ci_low),", ",
         fmt(legacy_stayer$ci_high),"], p=",fmt(legacy_stayer$p_value,3),"."),
  paste0("- Amended pooled main contrast: ",fmt(main$estimate)," [",
         fmt(main$ci_low),", ",fmt(main$ci_high),"], p=",
         fmt(main$p_value,3),"."),
  paste0("- Complete observed-stock sensitivity: ",fmt(full$estimate)," [",
         fmt(full$ci_low),", ",fmt(full$ci_high),"], p=",
         fmt(full$p_value,3),"."),
  paste0("- Binary IPC4-presence sensitivity: ",fmt(binary$estimate)," [",
         fmt(binary$ci_low),", ",fmt(binary$ci_high),"], p=",
         fmt(binary$p_value,3),"."),
  paste0("- Early pooled contrast: ",fmt(early$estimate)," [",
         fmt(early$ci_low),", ",fmt(early$ci_high),"], p=",
         fmt(early$p_value,3),"."),
  paste0("- Late pooled contrast: ",fmt(late$estimate)," [",
         fmt(late$ci_low),", ",fmt(late$ci_high),"], p=",
         fmt(late$p_value,3),"."),
  paste0("- Excluding the 2010 cohort: ",fmt(tail$estimate)," [",
         fmt(tail$ci_low),", ",fmt(tail$ci_high),"], p=",
         fmt(tail$p_value,3),"."),
  paste0("- Restricted pre/pre diagnostic: ",fmt(placebo$estimate)," [",
         fmt(placebo$ci_low),", ",fmt(placebo$ci_high),"], p=",
         fmt(placebo$p_value,3),"."),
  "",
  "## Measurement diagnostics",
  "",
  paste0("TechDrift is defined only for inventor-deal stacks with nonempty ",
         "classified IPC4 portfolios before and after the acquisition. ",
         "Joint weighted coverage is ",
         paste(sprintf("%.1f%% for %s",
           100*eligibility$joint_ipc_weight_coverage,eligibility$arm),
           collapse=" and "),"."),
  paste0("The pooled main outcome retains ",
         paste(sprintf("%.1f%% of %s weight",
           100*coverage$weight_coverage,coverage$arm),collapse=" and "),"."),
  paste0("The descriptive contrast standardized to a common post-patent-count ",
         "distribution is ",fmt(common_gap),". Because post-period patent ",
         "count is treatment-affected, this is not a causal controlled-direct-effect estimate."),
  "",
  "The prespecified annual result remains visible. The pooled measure is a",
  "documented post-result measurement amendment and is interpreted as a",
  "matched contrast in five-year portfolio displacement among initially",
  "retained inventors, not the main full-cohort DiD ATT. Initial retention is",
  "measured after treatment, so the result remains a selected-group contrast.")
writeLines(
  results_note,
  file.path(report_dir,"techdrift_window_results.md"),useBytes=TRUE)

message("TechDrift amendment reporting assets created: ",report_dir)
