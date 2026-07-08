# ==========================================================================
# LOAD SENSANALYSER
# ==========================================================================
#
# Sources everything needed to run a project. `run_sensanalyser.R` sources
# this file; you can also source it directly in the console to get access to
# the helper functions (settings_summary(), create_project(), ...).

library(here)

source(here::here("R", "core_engine.R"))
source(here::here("R", "functions", "settings_helpers.R"))
source(here::here("R", "functions", "project_helpers.R"))

#' Run one project
#'
#' @param project_dir Path to the project folder, e.g. "projects/example_study".
#' @export
run_project <- function(project_dir) {
  message("\n==========================================================================")
  message(sprintf("LAUNCHING SENSANALYSER FOR: %s", project_dir))
  message("==========================================================================\n")
  sensanalyser_run_project(project_dir)
}

#' Run several projects, one after the other
#'
#' @param project_dirs Character vector of project folder paths.
#' @export
run_projects <- function(project_dirs) {
  for (project_dir in project_dirs) run_project(project_dir)
  invisible(TRUE)
}

#' Show the settings a project will run with
#'
#' Prints the effective configuration, marking every value that differs from
#' the Sensanalyser default.
#'
#' @param project_dir Path to the project folder.
#' @export
settings_summary <- function(project_dir) {
  sensanalyser_settings_summary(project_dir)
}

#' Create a new project folder
#'
#' @param project_dir Path for the new project, e.g. "projects/my_study".
#' @export
create_project <- function(project_dir, ...) {
  sensanalyser_create_project(project_dir, ...)
}
