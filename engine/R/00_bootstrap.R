# ==========================================================================
# BOOTSTRAP — first-run package installation
# ==========================================================================
#
# This file uses ONLY base R. It must run in a brand-new R installation where
# none of Sensanalyser's packages (not even `here` or `cli`) are installed yet.
# Everything the engine needs is installed from here, before any package is
# loaded. `run_sensanalyser.R` sources this first; you can also source it by
# hand:  source("engine/R/00_bootstrap.R"); sensanalyser_install_all()

#' Find the Sensanalyser repo root without `here`.
#'
#' Walks up from `start` until it finds the engine's package list. Returns
#' `NA_character_` if it never does.
#' @keywords internal
.sensanalyser_find_root <- function(start = getwd()) {
  root <- normalizePath(start, winslash = "/", mustWork = FALSE)
  repeat {
    if (file.exists(file.path(root, "engine", "R", "functions", "package_list.R"))) {
      return(root)
    }
    parent <- dirname(root)
    if (identical(parent, root)) break   # reached the filesystem root
    root <- parent
  }
  NA_character_
}

#' Install every package Sensanalyser needs, if not already present.
#'
#' Safe to call in a fresh R install: it uses only base R, so it works before
#' `here`/`cli`/the analysis packages exist. Required packages must all end up
#' installed for the pipeline to run; the optional GUI helpers are installed
#' best-effort and never block a run.
#'
#' @param root Repo root. Auto-detected from `getwd()` when `NULL`.
#' @param ask Prompt before installing? Defaults to an interactive session.
#' @param include_optional Also install the optional GUI helper packages
#'   (`rstudioapi`, `svDialogs`) that improve the interactive pickers?
#' @param repos CRAN mirror.
#' @return Invisibly `TRUE` when every *required* package is present afterwards,
#'   otherwise `FALSE`.
#' @export
sensanalyser_install_all <- function(root = NULL,
                                     ask = interactive(),
                                     include_optional = TRUE,
                                     repos = "https://cloud.r-project.org") {
  if (is.null(root)) root <- .sensanalyser_find_root()
  if (is.na(root)) {
    stop("Could not find the Sensanalyser project root. Open the project's ",
         ".Rproj file (or setwd() to the project folder), then try again.",
         call. = FALSE)
  }

  source(file.path(root, "engine", "R", "functions", "package_list.R"))

  required <- sensanalyser_get_all_packages(include_optional = FALSE)
  optional <- if (include_optional) {
    setdiff(sensanalyser_get_all_packages(include_optional = TRUE), required)
  } else {
    character(0)
  }

  is_installed <- function(p) requireNamespace(p, quietly = TRUE)
  missing_req <- required[!vapply(required, is_installed, logical(1))]
  missing_opt <- optional[!vapply(optional, is_installed, logical(1))]
  to_install  <- c(missing_req, missing_opt)

  if (length(to_install) == 0) {
    message(sprintf("✔ Sensanalyser: all %d required packages are already installed.",
                    length(required)))
    return(invisible(TRUE))
  }

  message("\n── Sensanalyser first-run setup ─────────────────────────")
  message(sprintf("Missing packages: %d of %d required%s.",
                  length(missing_req), length(required),
                  if (length(missing_opt)) sprintf(" (+%d optional)", length(missing_opt)) else ""))
  message("  ", paste(to_install, collapse = ", "))
  message("Installing them lets Sensanalyser run. This can take several minutes.")

  if (isTRUE(ask)) {
    ans <- readline("Install now? [Y/n]: ")
    if (nzchar(ans) && tolower(substr(ans, 1, 1)) == "n") {
      message("Setup cancelled. Sensanalyser cannot run until the required ",
              "packages are installed.")
      return(invisible(FALSE))
    }
  }

  message("\nInstalling from ", repos, " ...")
  # One install.packages() call so shared dependencies resolve together.
  utils::install.packages(to_install, repos = repos)

  still_req <- missing_req[!vapply(missing_req, is_installed, logical(1))]
  still_opt <- missing_opt[!vapply(missing_opt, is_installed, logical(1))]

  if (length(still_opt) > 0) {
    message(sprintf("⚠ Optional package(s) not installed (Sensanalyser still runs): %s",
                    paste(still_opt, collapse = ", ")))
  }

  if (length(still_req) == 0) {
    message("✔ All required packages are installed. Continuing ...\n")
    invisible(TRUE)
  } else {
    message("\n✖ These REQUIRED packages could not be installed:")
    message("  ", paste(still_req, collapse = ", "))
    message("They may need system libraries (see the install log above). ",
            "Install them manually, then run again.")
    invisible(FALSE)
  }
}
