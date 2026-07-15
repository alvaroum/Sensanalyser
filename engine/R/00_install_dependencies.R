# ==========================================================================
# INSTALL DEPENDENCIES (backward-compatible wrapper)
# ==========================================================================
#
# The real installer now lives in 00_bootstrap.R (`sensanalyser_install_all()`),
# which uses only base R and runs before `here`/`cli` exist. This file is kept
# so the older, documented entry point still works.

#' Install Sensanalyser dependencies
#'
#' Thin wrapper around [sensanalyser_install_all()]. Installs every package the
#' pipeline needs. Uses only base R, so it runs in a brand-new R installation.
#'
#' @param categories Kept for backward compatibility. Any value other than the
#'   default installs everything; the recommended call is simply
#'   `sensanalyser_install_dependencies()`.
#' @param ask_user Prompt before installing? Defaults to an interactive session.
#' @param repos CRAN repository used by `install.packages()`.
#' @return Invisibly `TRUE` when every required package is present afterwards.
#' @examples
#' \dontrun{
#'   source("engine/R/00_install_dependencies.R")
#'   sensanalyser_install_dependencies()
#' }
sensanalyser_install_dependencies <- function(
    categories = "all",
    ask_user = interactive(),
    repos = "https://cloud.r-project.org") {

  if (!exists("sensanalyser_install_all", mode = "function")) {
    root <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
    while (!file.exists(file.path(root, "engine", "R", "00_bootstrap.R")) &&
           !identical(dirname(root), root)) {
      root <- dirname(root)
    }
    source(file.path(root, "engine", "R", "00_bootstrap.R"))
  }

  sensanalyser_install_all(ask = ask_user, repos = repos)
}
