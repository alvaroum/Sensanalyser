#' Install Sensanalyser dependencies
#'
#' @description
#' Installs missing CRAN packages required by the Sensanalyser pipeline. The
#' package list is defined in `R/functions/package_list.R`, which is the single
#' source of truth for dependency names and categories.
#'
#' Uses only base R output (message/cat) so it runs even before any packages
#' are installed.
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

  source(file.path("R", "functions", "package_list.R"))

  if (identical(categories, "all")) {
    packages_to_check <- sensanalyser_get_all_packages(include_optional = TRUE)
  } else {
    packages_to_check <- unique(unlist(
      lapply(categories, sensanalyser_get_packages_by_category),
      use.names = FALSE
    ))
  }

  message("\n── Sensanalyser dependency installation ──────────────────────────────────")
  message(sprintf("Checking %d package(s).", length(packages_to_check)))

  already_installed <- packages_to_check[vapply(
    packages_to_check,
    requireNamespace,
    quietly = TRUE,
    FUN.VALUE = logical(1)
  )]

  to_install <- setdiff(packages_to_check, already_installed)

  if (length(already_installed) > 0) {
    message(sprintf("v Already installed: %d", length(already_installed)))
  }

  if (length(to_install) == 0) {
    message("v All selected dependencies are already installed.")
    return(invisible(list(
      success = character(0),
      already_installed = already_installed,
      failed = character(0),
      missing_after_install = character(0)
    )))
  }

  message(sprintf("! Missing packages: %d", length(to_install)))
  for (pkg in to_install) message(sprintf("  - %s", pkg))

  if (ask_user) {
    response <- readline("Proceed with installation? (yes/no): ")
    if (tolower(substr(response, 1, 1)) != "y") {
      message("Installation cancelled by user.")
      return(invisible(list(
        success = character(0),
        already_installed = already_installed,
        failed = character(0),
        missing_after_install = to_install
      )))
    }
  }

  success <- character(0)
  failed  <- character(0)

  message("\n── Installing missing packages ───────────────────────────────────────────")

  for (pkg in to_install) {
    message(sprintf("  Installing %s ...", pkg))

    tryCatch(
      {
        install.packages(pkg, repos = repos, quiet = TRUE)

        # Verify installation rather than assuming install.packages() succeeded.
        if (requireNamespace(pkg, quietly = TRUE)) {
          success <- c(success, pkg)
          message(sprintf("  v %s installed.", pkg))
        } else {
          failed <- c(failed, pkg)
          message(sprintf("  x %s: install.packages() ran but package not found afterwards.", pkg))
        }
      },
      error = function(e) {
        message(sprintf("  x %s: %s", pkg, e$message))
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

  message("\n── Installation summary ──────────────────────────────────────────────────")
  message(sprintf("  Installed now:                  %d", length(success)))
  message(sprintf("  Already installed before run:   %d", length(already_installed)))
  message(sprintf("  Still missing:                  %d", length(missing_after_install)))

  if (length(missing_after_install) > 0) {
    message("! Packages still missing after installation attempt:")
    for (pkg in missing_after_install) message(sprintf("  - %s", pkg))
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
