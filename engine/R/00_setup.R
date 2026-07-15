#' Set up the Sensanalyser environment
#'
#' @description
#' Phase 1 setup script for Sensanalyser. It initialises the project folders,
#' checks dependency availability, loads available packages, and prints a concise
#' environment summary. It does not silently change analysis settings or run any
#' statistical workflow.
#'
#' @details
#' Run this from the Sensanalyser project root:
#'
#' ```r
#' source("R/00_setup.R")
#' ```
#'
#' If dependencies are missing, run:
#'
#' ```r
#' source("R/00_install_dependencies.R")
#' sensanalyser_install_dependencies(categories = "all")
#' ```
#'
#' @keywords internal

# Keep the setup script readable while still allowing quiet scripted checks.
if (!exists("SENSANALYSER_SETUP_VERBOSE")) {
  SENSANALYSER_SETUP_VERBOSE <- TRUE
}

if (SENSANALYSER_SETUP_VERBOSE) {
  cli::cli_h1("Sensanalyser project setup")
}

# Step 1 ------------------------------------------------------------------
# Create the Phase 1 folder tree. The function is safe to rerun and will not
# overwrite existing files.
if (SENSANALYSER_SETUP_VERBOSE) {
  cli::cli_h2("Step 1: Checking project structure")
}
source(here::here("engine", "R", "00_initialise_project_structure.R"))
sensanalyser_initialise_structure()

# Step 2 ------------------------------------------------------------------
# Load the dependency catalogue and check which packages are available. The
# actual installation is kept in 00_install_dependencies.R so setup remains
# predictable during tests and non-interactive runs.
if (SENSANALYSER_SETUP_VERBOSE) {
  cli::cli_h2("Step 2: Checking dependencies")
}
source(here::here("engine", "R", "functions", "package_list.R"))

all_packages <- sensanalyser_get_all_packages()
available_packages <- all_packages[vapply(
  all_packages,
  requireNamespace,
  quietly = TRUE,
  FUN.VALUE = logical(1)
)]
missing_packages <- setdiff(all_packages, available_packages)

if (length(missing_packages) == 0) {
  cli::cli_alert_success("All Sensanalyser dependencies are installed.")
} else {
  cli::cli_alert_warning("Missing {length(missing_packages)} package{?s}.")
  cli::cli_ul(missing_packages)
  cli::cli_inform("Install missing packages with:")
  cli::cli_code("source(\"engine/R/00_bootstrap.R\"); sensanalyser_install_all()")
}

# Step 3 ------------------------------------------------------------------
# Load only packages that are actually available. Missing packages are reported
# above and do not cause Phase 1 setup to abort.
if (SENSANALYSER_SETUP_VERBOSE) {
  cli::cli_h2("Step 3: Loading available packages")
}

loaded_packages <- character(0)
failed_to_load <- character(0)

for (pkg in available_packages) {
  tryCatch(
    {
      library(pkg, character.only = TRUE, quietly = TRUE)
      loaded_packages <- c(loaded_packages, pkg)
    },
    error = function(e) {
      failed_to_load <<- c(failed_to_load, pkg)
    }
  )
}

if (SENSANALYSER_SETUP_VERBOSE) {
  cli::cli_alert_success("Loaded {length(loaded_packages)} package{?s}.")

  if (length(failed_to_load) > 0) {
    cli::cli_alert_warning("Available but failed to load:")
    cli::cli_ul(failed_to_load)
  }
}

# Step 4 ------------------------------------------------------------------
# Save a small setup summary object that can be inspected after sourcing.
sensanalyser_setup_summary <- list(
  project_root = here::here(),
  r_version = R.version$version.string,
  dependency_count = length(all_packages),
  available_packages = available_packages,
  missing_packages = missing_packages,
  loaded_packages = loaded_packages,
  failed_to_load = failed_to_load
)

if (SENSANALYSER_SETUP_VERBOSE) {
  cli::cli_h2("Environment summary")
  cli::cli_inform("R version: {R.version$version.string}")
  cli::cli_inform("Project root: {here::here()}")
  cli::cli_inform("Dependencies available: {length(available_packages)}/{length(all_packages)}")
  cli::cli_inform("Packages loaded: {length(loaded_packages)}")
  cli::cli_alert_success("Phase 1 setup check complete.")
}

# Remove temporary loop/control variables but keep sensanalyser_setup_summary.
rm(
  SENSANALYSER_SETUP_VERBOSE,
  all_packages,
  available_packages,
  missing_packages,
  loaded_packages,
  failed_to_load,
  pkg
)
