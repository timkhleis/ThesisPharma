#!/usr/bin/env Rscript

# Run Package N0: outcome-blind network census and freeze.

started <- Sys.time()
source(file.path(
  "02_analysis", "R", "43a_lmv2_network_freeze_config.R"
))
source(file.path(
  "02_analysis", "R", "43b_build_lmv2_predeal_dyads.R"
))
source(file.path(
  "02_analysis", "R", "43c_census_lmv2_network_support.R"
))
source(file.path(
  "02_analysis", "R", "43d_certify_lmv2_network_census.R"
))

config <- lmv2_n0_config()
message("N0 stage 1/3: constructing pre-deal dyads and baseline ties...")
lmv2_n0_build_predeal_dyads(config)
message("N0 stage 2/3: auditing support and validation denominators...")
lmv2_n0_census_support(config)
message("N0 stage 3/3: certifying the outcome-blind census...")
result <- lmv2_n0_certify(config)

message(sprintf(
  "Package N0 complete in %.2f minutes; %d/%d checks pass; decision: %s.",
  as.numeric(difftime(Sys.time(), started, units = "mins")),
  sum(result$checks$pass),
  nrow(result$checks),
  result$decision$decision
))
