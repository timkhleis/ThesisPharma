#!/usr/bin/env Rscript

# Root runner for exploratory N4 retained-inventor team recomposition.

started <- Sys.time()
source(file.path(
  "02_analysis", "R", "47a_lmv2_n4_team_config.R"
))
source(file.path(
  "02_analysis", "R", "47b_build_lmv2_n4_team_recomposition.R"
))
source(file.path(
  "02_analysis", "R", "47c_report_lmv2_n4_team_recomposition.R"
))
source(file.path(
  "02_analysis", "R", "47d_certify_lmv2_n4_team_recomposition.R"
))

message("N4 stage 1/3: constructing frozen team measures...")
lmv2_n4_build()
message("N4 stage 2/3: reporting exploratory team recomposition...")
lmv2_n4_report()
message("N4 stage 3/3: certifying...")
checks <- lmv2_n4_certify()
message(
  "Package N4 complete in ",
  sprintf("%.2f", as.numeric(difftime(
    Sys.time(), started, units = "mins"
  ))),
  " minutes; ", sum(checks$pass), "/", nrow(checks),
  " checks pass."
)
