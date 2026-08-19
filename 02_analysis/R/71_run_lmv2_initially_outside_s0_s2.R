#!/usr/bin/env Rscript

source(file.path("02_analysis", "R", "71a_lmv2_initially_outside_config.R"))
source(file.path("02_analysis", "R", "71b_build_lmv2_initially_outside_s0_s2.R"))
source(file.path("02_analysis", "R", "71c_certify_lmv2_initially_outside_s0_s2.R"))

config <- lmv2_io_config()
lmv2_build_initially_outside_s0_s2(config)
lmv2_certify_initially_outside_s0_s2(config)
message("Certified initially-outside S0-S2: ", config$s0_dir)
