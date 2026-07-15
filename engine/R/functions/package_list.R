#' Sensanalyser Package Requirements
#'
#' @description
#' Defines all required and optional packages for the Sensanalyser analysis pipeline.
#' Organized by category for clarity and maintenance.
#'
#' @details
#' This file serves as a single source of truth for all package dependencies.
#' Each category represents a functional area of the analysis pipeline.
#'
#' Categories:
#' - core: Essential utilities (tidyverse, here, etc.)
#' - statistics: ANOVA and modeling (rstatix, emmeans, etc.)
#' - multivariate: PCA, MFA (FactoMineR, etc.)
#' - sensory: Sensory-specific tools (SensoMineR, etc.)
#' - reporting: Report generation (quarto, knitr, etc.)
#' - visualization: Plotting tools (ggplot2, etc.)
#'
#' @return
#' List with elements: $core, $statistics, $multivariate, $sensory, $reporting, $visualization
#'
#' @examples
#' \dontrun{
#'   pkg_list <- sensanalyser_get_package_list()
#'   all_pkgs <- unlist(pkg_list)
#' }
#'
#' @export
sensanalyser_get_package_list <- function() {
  list(
    core = c(
      "tidyverse",      # ggplot2, dplyr, tidyr, readr, purrr, tibble, stringr, forcats
      "here",           # Relative path management
      "cli",            # Command-line formatting
      "yaml",           # YAML file reading/writing
      "readxl",         # Read Excel files
      "writexl",        # Write Excel files
      "janitor",        # Data cleaning
      "rlang",          # R language utilities
      "glue"            # String interpolation
    ),

    statistics = c(
      "rstatix",        # User-friendly statistics
      "emmeans",        # Estimated marginal means and post-hoc tests
      "multcomp",       # Multiple comparisons
      "multcompView",   # Compact letter displays
      "agricolae",      # Agricultural statistics (LSD tests, etc.)
      "lme4",           # Linear mixed-effects models
      "lmerTest",       # ANOVA and post-hoc for lme4
      "afex",           # ANOVA for Factors with Error correction
      "performance",    # Model diagnostics and performance
      "broom",          # Tidy statistical model output
      "broom.mixed"     # Tidy output for mixed models
    ),

    multivariate = c(
      "FactoMineR",     # Principal Component Analysis, MFA, etc.
      "factoextra",     # Visualization of FactoMineR outputs
      "corrplot"        # Correlation matrix visualization
    ),

    sensory = c(
      "SensoMineR",     # Sensory-specific statistical methods
      "fmsb"            # Fuzzy multi-membered sets (radar/spider plots)
    ),

    reporting = c(
      "quarto",         # Quarto rendering
      "knitr",          # Dynamic report generation
      "gt",             # Great Tables for formatted output
      "flextable"       # Flexible table formatting for Word/PDF
    ),

    visualization = c(
      "ggplot2",        # Already in tidyverse, listed for clarity
      "cowplot",        # Multi-panel plots
      "ggrepel",        # Smart text placement
      "viridis",        # Colorblind-friendly palettes
      "RColorBrewer",   # Brewer color palettes (spider plot)
      "scales"          # Alpha/color scale utilities (spider plot)
    ),

    # Optional: enhance interactive file/variable pickers but are not required.
    # The code checks requireNamespace() before using these, so they fail
    # gracefully when absent (falls back to console-based prompts).
    optional = c(
      "rstudioapi",     # File picker inside RStudio / Positron
      "svDialogs"       # Native OS dialog boxes for file and list selection
    )
  )
}

#' Get All Required Packages as a Single Vector
#'
#' @description
#' Flattens the package list into a single vector for convenient mass installation.
#' The `optional` category is excluded by default; pass `include_optional = TRUE`
#' to include it.
#'
#' @param include_optional Logical. Include the optional GUI packages?
#'
#' @return
#' Character vector of package names
#'
#' @examples
#' \dontrun{
#'   all_packages <- sensanalyser_get_all_packages()
#' }
#'
#' @export
sensanalyser_get_all_packages <- function(include_optional = FALSE) {
  pkg_list <- sensanalyser_get_package_list()
  if (!include_optional) {
    pkg_list[["optional"]] <- NULL
  }
  unique(unlist(pkg_list, use.names = FALSE))
}

#' Get Optional Packages as a Single Vector
#'
#' @description
#' Returns only the optional (GUI-enhancement) packages.
#'
#' @return
#' Character vector of optional package names
#'
#' @export
sensanalyser_get_optional_packages <- function() {
  sensanalyser_get_package_list()[["optional"]]
}

#' Get Packages by Category
#'
#' @param category Character. One of: "core", "statistics", "multivariate",
#'   "sensory", "reporting", "visualization"
#'
#' @return
#' Character vector of package names in the specified category
#'
#' @examples
#' \dontrun{
#'   stat_pkgs <- sensanalyser_get_packages_by_category("statistics")
#' }
#'
#' @export
sensanalyser_get_packages_by_category <- function(category) {
  pkg_list <- sensanalyser_get_package_list()
  valid_categories <- names(pkg_list)

  if (!(category %in% valid_categories)) {
    stop(
      "Invalid category: '", category, "'\n",
      "Valid options: ", paste(valid_categories, collapse = ", ")
    )
  }

  pkg_list[[category]]
}
