#!/usr/bin/env Rscript

# Run Package D1: descriptive retained-status completion.

started <- Sys.time()
source(file.path(
  "02_analysis", "R", "42a_lmv2_stayer_descriptives_config.R"
))
source(file.path(
  "02_analysis", "R", "42b_build_lmv2_stayer_status_paths.R"
))
source(file.path(
  "02_analysis", "R", "42c_analyze_lmv2_stayer_distributions.R"
))
source(file.path(
  "02_analysis", "R",
  "42d_report_certify_lmv2_stayer_descriptives.R"
))

config <- lmv2_d1_config()
message("D1 stage 1/3: building status paths and endpoint audit...")
lmv2_d1_build_status_paths(config)
message("D1 stage 2/3: analyzing predetermined distributions...")
lmv2_d1_analyze_distributions(config)
message("D1 stage 3/3: reporting and certifying...")
result <- lmv2_d1_report_certify(config)

message(sprintf(
  "Package D1 complete in %.2f minutes; %d/%d checks pass.",
  as.numeric(difftime(Sys.time(), started, units = "mins")),
  sum(result$checks$pass),
  nrow(result$checks)
))
