#' Descriptive Helpers for Sensanalyser
#'
#' @description
#' Phase 4 descriptive statistics engine.
#' Generates long and wide descriptive tables for selected outcomes and factors,
#' with optional display-name mapping from renaming_dictionary.yaml.
#'
#' Core outputs:
#' - descriptives_long.csv
#' - descriptives_wide_mean_se.csv
#' - descriptives_wide_means_only.csv
#' - profile_table.csv
#'
#' @keywords internal

# ---------------------------------------------------------------------------
# DICTIONARY HELPERS
# ---------------------------------------------------------------------------

#' Load renaming dictionary safely
#'
#' @param path Path to renaming_dictionary.yaml
#' @return Named list with variables, levels, outcomes entries (possibly empty)
#' @export
load_renaming_dictionary <- function(path) {
  if (is.null(path) || !nzchar(path) || !file.exists(path)) {
    return(list(variables = list(), levels = list(), outcomes = list()))
  }

  dict <- yaml::read_yaml(path)
  if (is.null(dict$variables)) dict$variables <- list()
  if (is.null(dict$levels)) dict$levels <- list()
  if (is.null(dict$outcomes)) dict$outcomes <- list()
  dict
}

#' Format an internal sensory-attribute name for presentation
#'
#' Converts a recognised terminal modality code into a parenthetical label,
#' while retaining the raw identifier for all analysis operations. For example,
#' `darkness_crumb_ap` becomes `Darkness crumb (Appearance)`. Names without a
#' recognised terminal code fall back to a sentence-cased, underscore-free form.
#'
#' @param x One internal outcome name.
#' @return A presentation label.
#' @keywords internal
.format_attribute_label <- function(x) {
  modality_labels <- c(
    ap = "Appearance",
    a  = "Aroma",
    f  = "Flavour",
    m  = "Mouthfeel",
    t  = "Texture",
    af = "Aftertaste"
  )

  parts <- regmatches(x, regexec("^(.*)_([a-z]+)$", x))[[1]]
  base <- x
  modality <- NULL
  if (length(parts) == 3 && parts[3] %in% names(modality_labels) && nzchar(parts[2])) {
    base <- parts[2]
    modality <- unname(modality_labels[[parts[3]]])
  }

  label <- gsub("_", " ", base)
  if (nzchar(label)) {
    label <- paste0(toupper(substr(label, 1, 1)), substr(label, 2, nchar(label)))
  }
  if (!is.null(modality)) paste0(label, " (", modality, ")") else label
}

#' Apply display labels to outcome names
#'
#' Explicit `labels.attributes` mappings take precedence. All other names use
#' `.format_attribute_label()` so tables, figures and multivariate outputs get
#' consistent presentation labels without changing the underlying data columns.
#'
#' @param outcome_chr Character vector of outcome internal names
#' @param dict Renaming dictionary list from load_renaming_dictionary()
#' @return Character vector of display names
#' @keywords internal
.apply_outcome_labels <- function(outcome_chr, dict) {
  mapped <- vapply(outcome_chr, function(x) {
    if (!is.null(dict$outcomes[[x]])) {
      as.character(dict$outcomes[[x]])
    } else {
      .format_attribute_label(x)
    }
  }, character(1))
  mapped
}

#' Apply level labels to one factor column
#'
#' @param x Column vector
#' @param factor_name Name of factor column
#' @param dict Renaming dictionary list
#' @return Character vector with level labels applied when available
#' @keywords internal
.apply_level_labels <- function(x, factor_name, dict) {
  if (is.null(dict$levels[[factor_name]])) {
    return(as.character(x))
  }

  lvl_map <- dict$levels[[factor_name]]
  out <- as.character(x)
  for (k in names(lvl_map)) {
    out[out == k] <- as.character(lvl_map[[k]])
  }
  out
}

# ---------------------------------------------------------------------------
# CORE DESCRIPTIVES
# ---------------------------------------------------------------------------

#' Validate inputs for descriptive statistics
#'
#' @param data Data frame.
#' @param dependent_variables Character vector of numeric outcome columns.
#' @param grouping_factors Character vector of grouping columns.
#' @return Invisibly returns TRUE or aborts with a clear message.
#' @keywords internal
.validate_descriptive_inputs <- function(data, dependent_variables, grouping_factors) {
  errors <- character(0)

  if (length(dependent_variables) == 0) {
    errors <- c(errors, "No dependent variables provided for descriptives.")
  }

  missing_dvs <- setdiff(dependent_variables, names(data))
  if (length(missing_dvs) > 0) {
    errors <- c(errors, paste0("Dependent variable columns not found: ", paste(missing_dvs, collapse = ", ")))
  }

  missing_groups <- setdiff(grouping_factors, names(data))
  if (length(missing_groups) > 0) {
    errors <- c(errors, paste0("Grouping columns not found: ", paste(missing_groups, collapse = ", ")))
  }

  available_dvs <- intersect(dependent_variables, names(data))
  non_numeric_dvs <- available_dvs[!vapply(available_dvs, function(x) is.numeric(data[[x]]), logical(1))]
  if (length(non_numeric_dvs) > 0) {
    errors <- c(errors, paste0("Dependent variables must be numeric: ", paste(non_numeric_dvs, collapse = ", ")))
  }

  overlapping_roles <- intersect(dependent_variables, grouping_factors)
  if (length(overlapping_roles) > 0) {
    errors <- c(errors, paste0("Columns cannot be both dependent variables and grouping factors: ", paste(overlapping_roles, collapse = ", ")))
  }

  if (length(errors) > 0) {
    cli::cli_abort(c("Descriptive input validation failed:", setNames(errors, rep("x", length(errors)))))
  }

  invisible(TRUE)
}

#' Create long-format descriptives
#'
#' @param data Working dataset
#' @param dependent_variables Character vector of DVs
#' @param grouping_factors Character vector of grouping factors
#' @param digits Decimal places for rounded summaries
#' @param renaming_dictionary Optional dictionary list
#' @return Tibble with long descriptives
#' @export
create_descriptives_long <- function(data,
                                     dependent_variables,
                                     grouping_factors,
                                     digits = 1,
                                     renaming_dictionary = NULL) {
  if (is.null(grouping_factors)) grouping_factors <- character(0)
  .validate_descriptive_inputs(data, dependent_variables, grouping_factors)

  long_tbl <- data %>%
    tidyr::pivot_longer(
      cols = dplyr::all_of(dependent_variables),
      names_to = "outcome",
      values_to = "value"
    ) %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(c(grouping_factors, "outcome")))) %>%
    dplyr::summarise(
      n = sum(!is.na(.data$value)),
      mean = mean(.data$value, na.rm = TRUE),
      sd = stats::sd(.data$value, na.rm = TRUE),
      # SE is only defined when at least two non-missing observations are
      # available. For n = 0 or n = 1, keep SE as NA rather than printing NaN.
      se = dplyr::if_else(.data$n > 1, .data$sd / sqrt(.data$n), as.numeric(NA_real_)),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      mean = round(.data$mean, digits),
      sd = round(.data$sd, digits),
      se = round(.data$se, digits),
      mean_se = dplyr::if_else(
        is.na(.data$mean),
        NA_character_,
        paste0(
          formatC(.data$mean, format = "f", digits = digits),
          " ± ",
          dplyr::if_else(is.na(.data$se), "NA", formatC(.data$se, format = "f", digits = digits))
        )
      )
    )

  if (!is.null(renaming_dictionary)) {
    long_tbl <- long_tbl %>%
      dplyr::mutate(
        outcome_display = .apply_outcome_labels(.data$outcome, renaming_dictionary)
      )

    for (gf in grouping_factors) {
      if (gf %in% names(long_tbl)) {
        long_tbl[[gf]] <- .apply_level_labels(long_tbl[[gf]], gf, renaming_dictionary)
      }
    }
  } else {
    long_tbl <- long_tbl %>% dplyr::mutate(outcome_display = gsub("_", " ", .data$outcome))
  }

  long_tbl
}

#' Create wide descriptives with mean ± SE cells
#'
#' @param descriptives_long_tbl Output of create_descriptives_long
#' @param grouping_factors Character vector
#' @return Wide tibble
#' @export
create_descriptives_wide_outcomes <- function(descriptives_long_tbl, grouping_factors) {
  if (nrow(descriptives_long_tbl) == 0) return(descriptives_long_tbl)

  descriptives_long_tbl %>%
    dplyr::select(dplyr::all_of(grouping_factors), "outcome_display", "mean_se") %>%
    tidyr::pivot_wider(names_from = "outcome_display", values_from = "mean_se")
}

#' Create wide descriptives with means only
#'
#' @param descriptives_long_tbl Output of create_descriptives_long
#' @param grouping_factors Character vector
#' @return Wide tibble
#' @export
create_descriptives_wide_outcomes_means <- function(descriptives_long_tbl, grouping_factors) {
  if (nrow(descriptives_long_tbl) == 0) return(descriptives_long_tbl)

  descriptives_long_tbl %>%
    dplyr::select(dplyr::all_of(grouping_factors), "outcome_display", "mean") %>%
    tidyr::pivot_wider(names_from = "outcome_display", values_from = "mean")
}

#' Create profile table for reporting
#'
#' @description
#' A report-friendly table format equivalent to wide mean ± SE output.
#'
#' @param descriptives_long_tbl Output of create_descriptives_long
#' @param grouping_factors Character vector
#' @return Tibble
#' @export
create_profile_table <- function(descriptives_long_tbl, grouping_factors) {
  create_descriptives_wide_outcomes(descriptives_long_tbl, grouping_factors)
}

# ---------------------------------------------------------------------------
# ORCHESTRATOR
# ---------------------------------------------------------------------------

#' Run Phase 4 descriptives
#'
#' @param data Working dataset
#' @param selections Selection list from Phase 2
#' @param config Full pipeline config
#' @return List with long/wide/profile tables
#' @export
run_descriptive_phase <- function(data, selections, config) {
  cli::cli_h2("Phase 4: Descriptives")

  grouping_factors <- config$analysis$descriptive_grouping_factors
  if (is.null(grouping_factors) || length(grouping_factors) == 0) {
    grouping_factors <- selections$factors
  }

  dict <- load_renaming_dictionary(config$paths$renaming_dictionary)

  digits <- config$table_options$digits
  if (is.null(digits) || length(digits) == 0 || is.na(digits)) digits <- 1L

  long_tbl <- create_descriptives_long(
    data = data,
    dependent_variables = selections$dependent_variables,
    grouping_factors = grouping_factors,
    digits = digits,
    renaming_dictionary = dict
  )

  wide_mean_se <- create_descriptives_wide_outcomes(long_tbl, grouping_factors)
  wide_means <- create_descriptives_wide_outcomes_means(long_tbl, grouping_factors)
  profile_tbl <- create_profile_table(long_tbl, grouping_factors)

  table_root <- config$paths$table_root
  if (is.null(table_root) || !nzchar(table_root)) table_root <- "outputs/tables"
  dir.create(here::here(table_root), recursive = TRUE, showWarnings = FALSE)

  file_long <- here::here(table_root, "descriptives_long.csv")
  file_wide_mean_se <- here::here(table_root, "descriptives_wide_mean_se.csv")
  file_wide_means <- here::here(table_root, "descriptives_wide_means_only.csv")
  file_profile <- here::here(table_root, "profile_table.csv")

  readr::write_csv(long_tbl, file_long)
  readr::write_csv(wide_mean_se, file_wide_mean_se)
  readr::write_csv(wide_means, file_wide_means)
  readr::write_csv(profile_tbl, file_profile)

  cli::cli_alert_success("Saved: {file_long}")
  cli::cli_alert_success("Saved: {file_wide_mean_se}")
  cli::cli_alert_success("Saved: {file_wide_means}")
  cli::cli_alert_success("Saved: {file_profile}")

  list(
    grouping_factors = grouping_factors,
    descriptives_long = long_tbl,
    descriptives_wide_mean_se = wide_mean_se,
    descriptives_wide_means_only = wide_means,
    profile_table = profile_tbl
  )
}
