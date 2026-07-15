#' Initialise the Sensanalyser project structure
#'
#' @description
#' Creates the required Sensanalyser folder tree if any folders are missing.
#' The function is deliberately idempotent: it can be rerun safely and will not
#' overwrite existing files or delete existing outputs.
#'
#' @param root Character path to the project root. Defaults to `here::here()`.
#'
#' @return Invisibly returns a character vector with the directories that were
#'   created during this call.
#'
#' @examples
#' \dontrun{
#'   source("R/00_initialise_project_structure.R")
#'   sensanalyser_initialise_structure()
#' }
sensanalyser_initialise_structure <- function(root = here::here()) {
  # These folders are the Phase 1 scaffold for the reusable Sensanalyser
  # workflow. Later phases will add files inside these folders, but the folder
  # names should remain stable so paths in mission_control.R can be reused.
  required_dirs <- c(
    "R/functions",
    "archive",
    "projects",
    "templates"
  )

  created_dirs <- character(0)

  for (dir in required_dirs) {
    full_path <- file.path(root, dir)

    # recursive = TRUE allows parent folders to be created at the same time.
    # showWarnings = FALSE avoids noisy messages when folders already exist.
    if (!dir.exists(full_path)) {
      dir.create(full_path, recursive = TRUE, showWarnings = FALSE)
      created_dirs <- c(created_dirs, dir)
    }
  }

  if (length(created_dirs) > 0) {
    cli::cli_alert_success("Created {length(created_dirs)} director{?y/ies}.")
    cli::cli_ul(created_dirs)
  } else {
    cli::cli_alert_info("All required Sensanalyser directories already exist.")
  }

  invisible(created_dirs)
}
