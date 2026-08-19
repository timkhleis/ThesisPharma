#!/usr/bin/env Rscript

source(file.path("02_analysis", "R", "71a_lmv2_initially_outside_config.R"))
source(file.path("02_analysis", "R", "72_build_lmv2_initially_outside_s3.R"))

config <- lmv2_io_config()
gate <- lmv2_build_initially_outside_s3(config)
print(gate)
message("Certified initially-outside S3: ", config$s3_dir)
