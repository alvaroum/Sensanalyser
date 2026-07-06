#' Derived Attribute Helpers for Sensanalyser
#'
#' @description
#' Project-specific helper functions for creating derived sensory attributes
#' before the normal Sensanalyser pipeline phases run. These helpers preserve
#' raw variables and add new numeric columns, such as an overall fruity score
#' averaged from selected aroma and flavour attributes.
#'
#' @keywords internal

# ---------------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------------

#' Load derived-attribute configuration
#'
#' @param path Path to a YAML file defining derived attributes.
#' @return A list with a `derived_attributes` element. If the file is missing,
#'   an empty derived-attribute list is returned.
#' @export
load_derived_attribute_config <- function(path) {
  if (is.null(path) || !nzchar(path) || !file.exists(path)) {
    return(list(derived_attributes = list()))
  }

  cfg <- yaml::read_yaml(path)
  if (is.null(cfg$derived_attributes)) {
    cfg$derived_attributes <- list()
  }
  cfg
}

#' Validate a derived-attribute configuration against a dataset
#'
#' @param data Data frame containing source variables.
#' @param derived_config Configuration returned by
#'   `load_derived_attribute_config()`.
#' @return Invisibly returns TRUE or aborts with a clear error.
#' @export
validate_derived_attribute_config <- function(data, derived_config) {
  defs <- derived_config$derived_attributes
  if (is.null(defs) || length(defs) == 0) {
    return(invisible(TRUE))
  }

  errors <- character(0)
  created_names <- names(defs)

  for (derived_name in created_names) {
    def <- defs[[derived_name]]
    source_variables <- def$source_variables %||% character(0)

    if (length(source_variables) == 0) {
      errors <- c(errors, paste0("Derived attribute '", derived_name, "' has no source_variables."))
      next
    }

    available_names <- c(names(data), created_names)
    missing_sources <- setdiff(source_variables, available_names)
    if (length(missing_sources) > 0) {
      errors <- c(
        errors,
        paste0(
          "Derived attribute '", derived_name,
          "' references missing source variable(s): ",
          paste(missing_sources, collapse = ", ")
        )
      )
    }
  }

  if (length(errors) > 0) {
    cli::cli_abort(c("Derived-attribute configuration is invalid:", setNames(errors, rep("x", length(errors)))))
  }

  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# DERIVATION ENGINE
# ---------------------------------------------------------------------------

#' Create derived attributes
#'
#' @description
#' Adds derived sensory attributes to a copy of the input dataset. Currently the
#' supported method is row-wise mean averaging. Source variables can refer to
#' raw columns or to previously defined derived attributes, which allows a
#' two-step structure such as Banana = mean(banana_a, banana_f) followed by
#' overall_fruity = mean(Banana, Tropical, Orchard, ...).
#'
#' @param data Data frame.
#' @param derived_config Derived-attribute YAML config as a list.
#' @param digits Optional number of decimals for derived values. If NULL,
#'   values are not rounded.
#' @return The input data frame with additional derived-attribute columns.
#' @export
create_derived_attributes <- function(data, derived_config, digits = NULL) {
  defs <- derived_config$derived_attributes
  if (is.null(defs) || length(defs) == 0) {
    cli::cli_alert_info("No derived attributes configured.")
    return(data)
  }

  validate_derived_attribute_config(data, derived_config)

  out <- data

  for (derived_name in names(defs)) {
    def <- defs[[derived_name]]
    method <- tolower(def$method %||% "mean")
    source_variables <- def$source_variables %||% character(0)
    min_non_missing <- as.integer(def$min_non_missing %||% 1L)

    if (!identical(method, "mean")) {
      cli::cli_abort("Unsupported derived attribute method for '{derived_name}': {method}. Currently only 'mean' is supported.")
    }

    source_data <- out[, source_variables, drop = FALSE]
    non_missing_n <- rowSums(!is.na(source_data))
    derived_value <- rowMeans(source_data, na.rm = TRUE)
    derived_value[non_missing_n < min_non_missing] <- NA_real_

    if (!is.null(digits) && is.numeric(digits) && length(digits) == 1 && !is.na(digits)) {
      derived_value <- round(derived_value, digits)
    }

    out[[derived_name]] <- derived_value
    cli::cli_alert_success(
      "Created derived attribute '{derived_name}' from {length(source_variables)} source variable(s)."
    )
  }

  out
}

#' Save a processed dataset containing derived attributes
#'
#' @param data Data frame with derived attributes.
#' @param path Output CSV path.
#' @return Invisibly returns the output path.
#' @export
save_derived_dataset <- function(data, path) {
  if (is.null(path) || !nzchar(path)) {
    return(invisible(NULL))
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(data, path)
  cli::cli_alert_success("Saved derived dataset: {path}")
  invisible(path)
}

# ---------------------------------------------------------------------------
# PIPELINE ORCHESTRATOR
# ---------------------------------------------------------------------------

#' Scale selected numeric analysis variables
#'
#' @description
#' Project-specific utility for rescaling data before analysis. This is useful
#' when raw data were stored on a 0–100 line scale but should be interpreted as
#' 0–10 by dividing by 10.
#'
#' @param data Data frame.
#' @param variables Character vector of variables to scale.
#' @param divisor Numeric divisor. If NULL, NA, or 1, data are returned unchanged.
#' @return Data frame with selected numeric variables divided by `divisor`.
#' @export
scale_analysis_variables <- function(data, variables, divisor = NULL) {
  if (is.null(divisor) || length(divisor) == 0 || is.na(divisor) || identical(as.numeric(divisor), 1)) {
    return(data)
  }

  divisor <- as.numeric(divisor)
  if (!is.finite(divisor) || divisor == 0) {
    cli::cli_abort("derived_attribute_options$scale_divisor must be a finite non-zero number.")
  }

  vars <- intersect(variables %||% character(0), names(data))
  vars <- vars[vapply(vars, function(x) is.numeric(data[[x]]), logical(1))]

  if (length(vars) == 0) {
    cli::cli_alert_warning("No numeric analysis variables available for scaling.")
    return(data)
  }

  data[vars] <- lapply(data[vars], function(x) x / divisor)
  cli::cli_alert_success("Scaled {length(vars)} analysis variable(s) by dividing by {divisor}.")
  data
}

#' Run derived-attribute creation phase
#'
#' @param data Raw or working dataset.
#' @param config Full Sensanalyser config list.
#' @return Data frame with derived attributes added.
#' @export
run_derived_attribute_phase <- function(data, config) {
  cli::cli_h2("Project-specific derived attributes")

  derived_path <- config$paths$derived_attributes %||% "data/dictionary/derived_attributes.yaml"
  derived_config <- load_derived_attribute_config(derived_path)

  digits <- config$derived_attribute_options$digits %||% NULL
  out <- create_derived_attributes(data, derived_config, digits = digits)

  scale_divisor <- config$derived_attribute_options$scale_divisor %||% NULL
  out <- scale_analysis_variables(
    data = out,
    variables = config$analysis$dependent_variables,
    divisor = scale_divisor
  )

  save_path <- config$paths$derived_data %||% NULL
  if (!is.null(save_path) && nzchar(save_path)) {
    save_derived_dataset(out, save_path)
  }

  out
}
