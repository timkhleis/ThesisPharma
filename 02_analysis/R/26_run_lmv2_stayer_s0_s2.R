# Run and certify the P5b S0-S2 package.

source(file.path("02_analysis", "R", "26a_lmv2_stayer_config.R"))
source(file.path("02_analysis", "R", "26b_build_lmv2_stayer_s0_s2.R"))
source(file.path("02_analysis", "R", "26c_certify_lmv2_stayer_s0_s2.R"))

config <- lmv2_stayer_config()
started <- Sys.time()

message("Building P5b S0-S2 retention interfaces...")
lmv2_build_stayer_s0_s2(config)

message("Certifying P5b S0-S2...")
result <- lmv2_certify_stayer_s0_s2(config)

elapsed <- as.numeric(difftime(Sys.time(), started, units = "mins"))
message(sprintf(
  "P5b S0-S2 complete in %.2f minutes; execution hash %s",
  elapsed, result$manifest$execution_hash[[1L]]))
