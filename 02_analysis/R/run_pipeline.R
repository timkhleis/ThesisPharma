scripts <- c(
  file.path("02_analysis", "R", "01_build_data_foundation.R"),
  file.path("02_analysis", "R", "02_build_derived_tables.R")
)

rscript <- file.path(R.home("bin"), "Rscript.exe")

for (script in scripts) {
  message("Running ", script, " ...")
  status <- system2(rscript, script)
  if (!identical(status, 0L)) {
    stop("Pipeline failed while running ", script, call. = FALSE)
  }
}

message("Data-foundation and derived-table pipeline complete.")
