# Fast P6 contract smoke test. Does not build outcomes or estimate effects.

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (length(hit) != 1L) stop("Missing --", name, "=...")
  sub(paste0("^--", name, "="), "", hit)
}

BASE <- normalizePath("02_analysis", mustWork = TRUE)
shared_lib <- normalizePath(
  file.path(BASE, "..", "..", "..", ".r_libs"),
  winslash = "/", mustWork = FALSE)
if (dir.exists(shared_lib)) {
  .libPaths(unique(c(shared_lib, .libPaths())))
}
for (package in c("DBI", "duckdb", "digest")) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop("Missing package: ", package)
  }
}
source(file.path(BASE, "R", "18a_lmv2_outcome_config.R"))
source(file.path(BASE, "R", "18c_materialize_lmv2_outcome_panel.R"))

db_path <- normalizePath(read_arg("db"), winslash = "/", mustWork = TRUE)
roster_path <- normalizePath(
  read_arg("roster"), winslash = "/", mustWork = TRUE)
con <- DBI::dbConnect(duckdb::duckdb(), db_path)
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, sprintf(
  "CREATE OR REPLACE TEMP TABLE p6_primary_roster_smoke AS
   SELECT * FROM read_parquet('%s')",
  gsub("'", "''", roster_path)))
validate_lmv2_roster(
  con, "p6_primary_roster_smoke", mode = "production")
membership <- certify_lmv2_roster_membership(
  con, "p6_primary_roster_smoke")
print(membership)
if (!all(membership$pass)) {
  stop("Primary roster membership smoke test failed")
}
message("P6 primary roster contract smoke test PASS")
