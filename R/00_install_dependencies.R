#' Install Sensanalyser dependencies
#'
#' @description
#' Installs missing CRAN packages required by the Sensanalyser pipeline. The
#' package list is defined in `R/functions/package_list.R`, which is the single
#' source of truth for dependency names and categories.
#'
#' @param categories Character vector with dependency categories to check. Use
#'   `"all"` to install every category.
#' @param ask_user Logical. If `TRUE`, ask before installing missing packages.
#'   In non-interactive runs this should normally be `FALSE`.
#' @param repos CRAN repository used by `install.packages()`.
#'
#' @return Invisibly returns a list with `success`, `already_installed`,
#'   `failed`, and `missing_after_install` character vectors.
#'
#' @examples
#' \dontrun{
#'   source("R/00_install_dependencies.R")
#'   sensanalyser_install_dependencies(categories = "core")
#'   sensanalyser_install_dependencies(categories = "all", ask_user = FALSE)
#' }
sensanalyser_install_dependencies <- function(
    categories = "all",
    ask_user = interactive(),
    repos = "https://cloud.r-project.org") {

  source(here::here("R", "functions", "package_list.R"))

  package_list <- sensanalyser_get_package_list()

  if (identical(categories, "all")) {
    packages_to_check <- sensanalyser_get_all_packages()
  } else {
    packages_to_check <- unique(unlist(
      lapply(categories, sensanalyser_get_packages_by_category),
      use.names = FALSE
    ))
  }

  cli::cli_h1("Sensanalyser dependency installation")
  cli::cli_inform("Checking {length(packages_to_check)} package{?s}.")

  already_installed <- packages_to_check[vapply(
    packages_to_check,
    requireNamespace,
    quietly = TRUE,
    FUN.VALUE = logical(1)
  )]

  to_install <- setdiff(packages_to_check, already_installed)

  if (length(already_installed) > 0) {
    cli::cli_alert_success("Already installed: {length(already_installed)}")
  }

  if (length(to_install) == 0) {
    cli::cli_alert_success("All selected dependencies are already installed.")
    return(invisible(list(
      success = character(0),
      already_installed = already_installed,
      failed = character(0),
      missing_after_install = character(0)
    )))
  }

  cli::cli_alert_warning("Missing packages: {length(to_install)}")
  cli::cli_ul(to_install)

  if (ask_user) {
    response <- readline("Proceed with installation? (yes/no): ")
    if (tolower(substr(response, 1, 1)) != "y") {
      cli::cli_alert_info("Installation cancelled by user.")
      return(invisible(list(
        success = character(0),
        already_installed = already_installed,
        failed = character(0),
        missing_after_install = to_install
      )))
    }
  }

  success <- character(0)
  failed <- character(0)

  cli::cli_h2("Installing missing packages")

  for (pkg in to_install) {
    cli::cli_progress_step("Installing {.pkg {pkg}}")

    tryCatch(
      {
        install.packages(pkg, repos = repos, quiet = TRUE)

        # Verify installation rather than assuming install.packages() succeeded.
        if (requireNamespace(pkg, quietly = TRUE)) {
          success <- c(success, pkg)
        } else {
          failed <- c(failed, pkg)
        }
      },
      error = function(e) {
        cli::cli_alert_danger("Failed to install {.pkg {pkg}}: {e$message}")
        failed <<- c(failed, pkg)
      }
    )
  }

  installed_now <- packages_to_check[vapply(
    packages_to_check,
    requireNamespace,
    quietly = TRUE,
    FUN.VALUE = logical(1)
  )]
  missing_after_install <- setdiff(packages_to_check, installed_now)

  cli::cli_h2("Installation summary")
  cli::cli_inform("Installed now: {length(success)}")
  cli::cli_inform("Already installed before this run: {length(already_installed)}")
  cli::cli_inform("Still missing: {length(missing_after_install)}")

  if (length(missing_after_install) > 0) {
    cli::cli_alert_warning("Packages still missing after installation attempt:")
    cli::cli_ul(missing_after_install)
  }

  invisible(list(
    success = success,
    already_installed = already_installed,
    failed = failed,
    missing_after_install = missing_after_install
  ))
}

#' Format a package/version string
#'
#' @param pkg Package name.
#' @return Character string such as `dplyr (1.1.4)`.
#' @keywords internal
pkg_version_string <- function(pkg) {
  tryCatch(
    paste0(pkg, " (", utils::packageVersion(pkg), ")"),
    error = function(e) pkg
  )
}
