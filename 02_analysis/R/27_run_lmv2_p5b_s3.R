# Reproducible P5b S3 runner. This package remains outcome-blind.

source(file.path("02_analysis", "R", "27a_lmv2_p5b_s3_config.R"))
source(file.path("02_analysis", "R", "27b_build_lmv2_p5b_s3_support.R"))
source(file.path("02_analysis", "R", "27c_run_lmv2_p5b_s3_weights.R"))
source(file.path("02_analysis", "R", "27d_certify_lmv2_p5b_s3.R"))

lmv2_run_p5b_s3 <- function(run_stress_tests = FALSE) {
  config <- lmv2_p5b_s3_config()
  lmv2_build_p5b_s3_support(config)
  specs <- if (isTRUE(run_stress_tests)) {
    names(config$weight_specs)
  } else {
    config$production_specs
  }
  cohorts <- if (isTRUE(run_stress_tests)) {
    config$production_cohorts
  } else {
    config$production_cohorts
  }
  lmv2_run_p5b_s3_weights(config, specs, cohorts)
  lmv2_certify_p5b_s3(config)
}

if (sys.nframe() == 0L) {
  stress <- "--stress" %in% commandArgs(trailingOnly = TRUE)
  lmv2_run_p5b_s3(run_stress_tests = stress)
}
