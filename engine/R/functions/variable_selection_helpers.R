#' Variable Selection Helpers for Sensanalyser
#'
#' @description
#' Functions for discovering dataset structure, selecting analysis variables
#' interactively or from a YAML configuration file, and saving/reading those
#' selections so every run is reproducible.
#'
#' The workflow:
#' 1. Call `discover_dataset_structure()` to inspect available columns.
#' 2. Call `select_analysis_variables()` to choose DVs, factors, and subject ID.
#' 3. Call `write_analysis_config()` to save the selections to YAML.
#' 4. On subsequent runs, call `read_analysis_config()` to restore selections.
#'
#' @author Sensanalyser project
#' @keywords internal

# ---------------------------------------------------------------------------
# DISCOVERY
# ---------------------------------------------------------------------------

#' Discover Dataset Structure
#'
#' @description
#' Prints a detailed profile of all columns in the dataset: detected type,
#' unique value count, number of NAs, and for factors their unique levels.
#'
#' This function is designed to run with `toggles$discover_variables = TRUE` in
#' mission_control.R. It helps the user understand the data before configuring
#' the analysis.
#'
#' @param data A tibble returned by `load_sensanalyser_data()`.
#' @param max_levels Integer. Maximum number of unique levels to print for
#'   character/factor columns. Defaults to 10.
#' @param stop_pipeline Logical. If TRUE (default), prints the discovery
#'   output and returns invisibly without running the analysis.
#'
#' @return A list (invisibly) with elements:
#'   - `$all_cols`: all column names
#'   - `$numeric_cols`: names of numeric columns
#'   - `$categorical_cols`: names of character/factor columns
#'   - `$missing_counts`: named vector of NA counts per column
#'
#' @examples
#' \dontrun{
#'   data <- load_sensanalyser_data("data/raw/raw_data.csv")
#'   structure_info <- discover_dataset_structure(data)
#' }
#'
#' @export
discover_dataset_structure <- function(data,
                                       max_levels     = 10,
                                       stop_pipeline  = FALSE) {
  cli::cli_h2("Dataset Structure Discovery")
  cli::cli_inform("Rows: {nrow(data)} | Columns: {ncol(data)}")

  numeric_cols     <- names(data)[sapply(data, is.numeric)]
  categorical_cols <- names(data)[sapply(data, function(x) is.character(x) || is.factor(x))]
  logical_cols     <- names(data)[sapply(data, is.logical)]
  missing_counts   <- sapply(data, function(x) sum(is.na(x)))

  # ---- Categorical columns ---------------------------------------------------
  if (length(categorical_cols) > 0) {
    cli::cli_h3("Categorical / Factor Columns ({length(categorical_cols)})")
    for (col in categorical_cols) {
      unique_vals <- sort(unique(as.character(data[[col]])))
      n_unique    <- length(unique_vals)
      na_count    <- missing_counts[[col]]

      display_vals <- if (n_unique <= max_levels) {
        paste(unique_vals, collapse = ", ")
      } else {
        paste0(paste(unique_vals[1:max_levels], collapse = ", "),
               " ... (", n_unique - max_levels, " more)")
      }

      na_msg <- if (na_count > 0) cli::col_red(paste0(" [", na_count, " NA]")) else ""
      cli::cli_inform("  {.strong {col}} ({n_unique} levels){na_msg}: {display_vals}")
    }
  }

  # ---- Numeric columns -------------------------------------------------------
  if (length(numeric_cols) > 0) {
    cli::cli_h3("Numeric / Dependent Variable Columns ({length(numeric_cols)})")
    for (col in numeric_cols) {
      vals     <- data[[col]]
      na_count <- missing_counts[[col]]
      rng      <- if (all(is.na(vals))) "all NA" else {
        sprintf("%.2f – %.2f", min(vals, na.rm = TRUE), max(vals, na.rm = TRUE))
      }
      na_msg <- if (na_count > 0) cli::col_red(paste0(" [", na_count, " NA]")) else ""
      cli::cli_inform("  {.strong {col}}{na_msg}: range {rng}")
    }
  }

  # ---- Logical columns -------------------------------------------------------
  if (length(logical_cols) > 0) {
    cli::cli_h3("Logical Columns ({length(logical_cols)})")
    for (col in logical_cols) {
      cli::cli_inform("  {col}")
    }
  }

  result <- list(
    all_cols         = names(data),
    numeric_cols     = numeric_cols,
    categorical_cols = categorical_cols,
    missing_counts   = missing_counts
  )

  if (stop_pipeline) {
    cli::cli_alert_warning("Discovery mode active — pipeline stopped before analysis.")
  }

  invisible(result)
}

# ---------------------------------------------------------------------------
# VARIABLE SELECTION
# ---------------------------------------------------------------------------

#' Select Analysis Variables
#'
#' @description
#' Determines which columns to use as dependent variables, fixed factors,
#' subject/panelist ID, repeated-measures factors, and blocking covariates.
#'
#' Selection happens in two modes:
#' - **Config mode** (default): reads `config$analysis` values directly. Use
#'   this when all selections have been specified in `mission_control.R` or
#'   loaded from a YAML config file with `read_analysis_config()`.
#' - **Interactive mode**: shows console prompts or GUI dialogs for each role
#'   when `config$toggles$interactive_setup = TRUE` and a selection is NULL.
#'
#' @param data A tibble returned by `load_sensanalyser_data()`.
#' @param config The full config list from mission_control.R.
#'
#' @return A list with elements:
#'   - `$dependent_variables`: character vector of DV column names
#'   - `$factors`: character vector of fixed factor column names
#'   - `$subject_id`: character (single column name for panelist/assessor)
#'   - `$repeated_measures_factors`: character vector (can be NULL/empty)
#'   - `$random_effects`: character vector (can be NULL/empty)
#'   - `$blocking_factors`: character vector (can be NULL/empty)
#'
#' @examples
#' \dontrun{
#'   selections <- select_analysis_variables(data, config)
#' }
#'
#' @export
select_analysis_variables <- function(data, config) {
  cli::cli_h2("Variable Selection")

  analysis_cfg  <- config$analysis
  interactive_mode <- isTRUE(config$toggles$interactive_setup)
  model_type <- if (!is.null(analysis_cfg$model_type) && nzchar(analysis_cfg$model_type))
    analysis_cfg$model_type else "one_way_anova"

  # If any "product+factor" names were split during cleaning, the resulting
  # Yes/No columns (named after each factor value) exist in `data` but
  # predate any hardcoded factor list in project_config.R, so they would
  # otherwise never be offered. Ask about each one here, before roles are
  # resolved, for every role where it's missing.
  split_cols <- tryCatch({
    dict_dir <- if (!is.null(config$paths$renaming_dictionary)) {
      dirname(config$paths$renaming_dictionary)
    } else NULL
    if (!is.null(dict_dir)) intersect(.list_factor_split_columns(dict_dir), names(data)) else character(0)
  }, error = function(e) character(0))

  if (interactive_mode && length(split_cols) > 0) {
    for (role in c("factors", "repeated_measures_factors")) {
      current <- analysis_cfg[[role]]
      is_hardcoded <- !is.null(current) && length(current) > 0 && !identical(current, "auto")
      if (!is_hardcoded) next

      for (col in setdiff(split_cols, current)) {
        add_it <- utils::askYesNo(
          sprintf(
            "'%s' is a Yes/No factor split from product names. Add it to '%s' (currently: %s)?",
            col, role, paste(current, collapse = ", ")
          ),
          default = TRUE
        )
        if (isTRUE(add_it)) {
          analysis_cfg[[role]] <- union(analysis_cfg[[role]], col)
        }
      }
    }
  }

  # Slots that must be selected for this specific model
  required_slots <- .required_variable_slots(model_type)

  if (interactive_mode) {
    cli::cli_inform("Model type: {.strong {model_type}}")
    cli::cli_inform(
      "Only the variable roles required for this model will be requested. \\
       Set {.code blocking_factors} in mission_control.R if needed."
    )
  }

  # Helper: resolve one variable slot ------------------------------------------
  # In interactive mode, only prompts when the role is in required_slots.
  # Blocking factors are never prompted interactively (set in mission_control.R).
  resolve <- function(current, role, data, multi = TRUE, is_required = TRUE) {
    if (!is.null(current) && length(current) > 0) {
      if (identical(current, "auto")) return("auto")
      missing_cols <- setdiff(current, names(data))
      if (length(missing_cols) > 0) {
        if (interactive_mode) {
          cli::cli_alert_danger(
            "Column(s) specified for '{role}' not found in data: {paste(missing_cols, collapse = ', ')}"
          )
          current <- NULL
        } else {
          cli::cli_abort(
            "Column(s) specified for '{role}' not found in data: {paste(missing_cols, collapse = ', ')}"
          )
        }
      } else {
        return(current)
      }
    }

    if (is.null(current) || length(current) == 0) {
      if (!interactive_mode) {
        if (is_required) {
          cli::cli_abort(
            "'{role}' is NULL and interactive_setup is FALSE.\n",
            "Set config$analysis${gsub(' ', '_', tolower(role))} or enable interactive_setup."
          )
        }
        return(NULL)
      }

      # In interactive mode, skip slots not needed by this model
      if (!role %in% required_slots) return(NULL)

      return(.interactive_select_columns(data, role = role, multi = multi, required = is_required,
                                         model_type = model_type))
    }
  }

  # Expand column-range syntax (e.g. "5:20") before passing to resolve()
  if (interactive_mode) {
    analysis_cfg$dependent_variables <- tryCatch({
      .expand_column_spec(analysis_cfg$dependent_variables, data)
    }, error = function(e) {
      cli::cli_alert_danger("Invalid column range in configuration: {e$message}")
      NULL
    })
  } else {
    analysis_cfg$dependent_variables <- .expand_column_spec(
      analysis_cfg$dependent_variables, data
    )
  }

  # 1. Dependent variables --------------------------------------------------
  dvs <- resolve(analysis_cfg$dependent_variables, "dependent_variables", data,
                 multi = TRUE, is_required = TRUE)

  if (identical(dvs, "auto")) {
    known_meta <- c(
      analysis_cfg$factors, analysis_cfg$subject_id,
      analysis_cfg$repeated_measures_factors, analysis_cfg$random_effects,
      analysis_cfg$blocking_factors
    )
    dvs <- names(data)[sapply(data, is.numeric)]
    dvs <- setdiff(dvs, known_meta)
    dvs <- .filter_sensory_attributes(dvs)
    cli::cli_alert_info("Auto-detected {length(dvs)} numeric dependent variable{?s}")
  }

  # Attributes the user asked to leave out of the whole analysis
  # (settings.yaml `variables.exclude`). Applied after auto-detection so it
  # also works when the attribute list is discovered rather than listed.
  excluded <- analysis_cfg$exclude_attributes
  if (!is.null(excluded) && length(excluded) > 0) {
    dropped <- intersect(dvs, excluded)
    dvs <- setdiff(dvs, excluded)
    if (length(dropped) > 0) {
      cli::cli_alert_info("Excluded {length(dropped)} attribute{?s} on request: {paste(dropped, collapse = ', ')}")
    }
    unknown <- setdiff(excluded, dropped)
    if (length(unknown) > 0) {
      cli::cli_alert_warning(
        "These excluded attribute{?s} were not found in the data: {paste(unknown, collapse = ', ')}"
      )
    }
  }

  # 2. Fixed factors --------------------------------------------------------
  factors <- resolve(analysis_cfg$factors, "factors", data,
                     multi = TRUE, is_required = TRUE)

  # 3. Subject / panelist ID ------------------------------------------------
  # Required for any model that needs within-subjects error terms or random effects
  sid_required <- model_type %in% c("one_way_repeated", "two_way_repeated",
                                    "two_way_mixed", "three_way_repeated",
                                    "linear_mixed_model")
  subject_id <- resolve(analysis_cfg$subject_id, "subject_id", data,
                        multi = FALSE, is_required = sid_required)

  # 4. Repeated-measures factors (RM ANOVA models only) ---------------------
  rm_factors <- resolve(analysis_cfg$repeated_measures_factors,
                        "repeated_measures_factors", data,
                        multi = TRUE, is_required = FALSE)

  # 5. Random effects (linear mixed model only) -----------------------------
  random_effects <- resolve(analysis_cfg$random_effects, "random_effects", data,
                            multi = TRUE, is_required = FALSE)

  # 6. Blocking factors — never prompted; must be set in mission_control.R ---
  blocking <- if (!is.null(analysis_cfg$blocking_factors) &&
                  length(analysis_cfg$blocking_factors) > 0) {
    missing_b <- setdiff(analysis_cfg$blocking_factors, names(data))
    if (length(missing_b) > 0) {
      cli::cli_abort(
        "Blocking factor column(s) not found in data: {paste(missing_b, collapse = ', ')}"
      )
    }
    analysis_cfg$blocking_factors
  } else {
    NULL
  }

  selections <- list(
    dependent_variables       = dvs,
    factors                   = factors,
    subject_id                = subject_id,
    repeated_measures_factors = rm_factors,
    random_effects            = random_effects,
    blocking_factors          = blocking
  )

  # Print summary -----------------------------------------------------------
  cli::cli_h3("Variable Selection Summary")
  cli::cli_inform("Dependent variables : {length(dvs)} selected")
  dv_preview <- if (length(dvs) > 5) {
    paste0(paste(head(dvs, 5), collapse = ", "), " (+ ", length(dvs) - 5, " more)")
  } else {
    paste(dvs, collapse = ", ")
  }
  cli::cli_inform("  {dv_preview}")
  cli::cli_inform("Fixed factors       : {paste(factors, collapse = ', ')}")
  if (!is.null(subject_id))    cli::cli_inform("Subject ID          : {subject_id}")
  if (length(rm_factors) > 0)  cli::cli_inform("Repeated measures   : {paste(rm_factors, collapse = ', ')}")
  if (length(random_effects) > 0) cli::cli_inform("Random effects   : {paste(random_effects, collapse = ', ')}")
  if (length(blocking) > 0)    cli::cli_inform("Blocking factors    : {paste(blocking, collapse = ', ')}")

  selections
}

# ---------------------------------------------------------------------------
# MODEL-AWARE SLOT REQUIREMENTS
# ---------------------------------------------------------------------------

#' Return which variable roles are required for a given model type
#'
#' @description
#' Controls which interactive prompts appear during variable selection.
#' Roles not listed here are silently skipped when in interactive mode.
#' Blocking factors are never in this list — they must be set explicitly in
#' mission_control.R because they are dataset-specific and optional.
#'
#' @param model_type Character. Value of config$analysis$model_type.
#' @return Character vector of role names.
#' @keywords internal
.required_variable_slots <- function(model_type) {
  rm_anova <- c("one_way_repeated", "two_way_repeated",
                "two_way_mixed",    "three_way_repeated")
  lmm      <- c("linear_mixed_model")

  slots <- c("dependent_variables", "factors", "subject_id")

  if (model_type %in% rm_anova) slots <- c(slots, "repeated_measures_factors")
  if (model_type %in% lmm)      slots <- c(slots, "random_effects")

  slots
}

#' Return a human-readable description + example for a variable role
#'
#' @description
#' The description is model-type aware so the prompt explains exactly what
#' is expected in the context of the user's chosen design.
#'
#' @param role Character. One of the standard role names.
#' @param model_type Character. Value of config$analysis$model_type.
#' @return A single character string (may contain newlines for indenting).
#' @keywords internal
.get_slot_description <- function(role, model_type = NULL) {
  mt <- if (!is.null(model_type) && nzchar(model_type)) model_type else ""

  switch(role,

    dependent_variables = paste0(
      "Sensory attributes / outcomes to analyse.\n",
      "  Examples: sweetness_m, bitterness_m, floral_a, body_m"
    ),

    factors = {
      detail <- switch(mt,
        one_way_anova      = "the single treatment factor (each panelist sees one level)",
        two_way_anova      = "two between-subjects factors (panelists assigned to one combination)",
        three_way_anova    = "three between-subjects factors",
        one_way_repeated   = "the within-subjects treatment factor (every panelist evaluates ALL levels)",
        two_way_repeated   = "both within-subjects factors (all panelists complete all combinations)",
        two_way_mixed      = "both factors: the WITHIN-subjects one (e.g. product) AND the BETWEEN-subjects one (e.g. group)",
        three_way_repeated = "all three within-subjects factors",
        linear_mixed_model = "fixed effects of interest — the systematic factors whose effect you want to estimate",
        "independent variables / treatment factors"
      )
      paste0("Fixed factors — ", detail, ".\n  Examples: product, session, treatment, group")
    },

    subject_id = paste0(
      "Panelist / assessor / subject ID column — the column that identifies who made each rating.\n",
      "  Examples: user, assessor, panelist, judge, subject_id"
    ),

    repeated_measures_factors = {
      detail <- switch(mt,
        one_way_repeated   = "the within-subjects factor — typically the SAME column as your fixed factor (e.g. product)",
        two_way_repeated   = "BOTH within-subjects factors (e.g. product and session)",
        two_way_mixed      = "ONLY the within-subjects factor (e.g. product) — NOT the between-subjects factor",
        three_way_repeated = "all three within-subjects factors",
        "the factor(s) for which each panelist provides multiple observations"
      )
      paste0("Repeated-measures factors — ", detail, ".\n  Examples: product, session")
    },

    random_effects = paste0(
      "Random effects — the grouping variable that accounts for between-panelist differences.\n",
      "  Usually the SAME column as subject_id (e.g. user, assessor, panelist).\n",
      "  In the model formula this becomes: (1 | user)"
    ),

    role  # fallback: return the raw role name
  )
}

# ---------------------------------------------------------------------------
# COLUMN RANGE EXPANSION
# ---------------------------------------------------------------------------

#' Expand a column range specification to a character vector of column names
#'
#' @description
#' Accepts a single string in range notation (`"5:20"` or `"5-20"`) and
#' returns the corresponding column names from `data`. All other inputs
#' (NULL, "auto", character vectors) are returned unchanged so this helper
#' is safe to call unconditionally.
#'
#' @param spec The value of `config$analysis$dependent_variables` (or any
#'   variable slot). Can be NULL, "auto", a character vector, or a range string.
#' @param data A tibble returned by `load_sensanalyser_data()`.
#'
#' @return The expanded character vector, or `spec` unchanged.
#'
#' @keywords internal
.expand_column_spec <- function(spec, data) {
  # Pass through anything that is not a single non-auto string
  if (is.null(spec) || identical(spec, "auto") ||
      length(spec) != 1 || !is.character(spec)) {
    return(spec)
  }

  # Match "5:20" or "5-20" (digits, colon or hyphen, digits)
  if (!grepl("^\\d+[:\\-]\\d+$", spec)) {
    return(spec)
  }

  parts     <- as.integer(strsplit(spec, "[:\\-]")[[1]])
  start_col <- parts[1]
  end_col   <- parts[2]
  n_cols    <- ncol(data)

  if (start_col < 1 || end_col > n_cols || start_col > end_col) {
    cli::cli_abort(c(
      "Column range {.val {spec}} is out of bounds.",
      "i" = "Dataset has {n_cols} column{?s} (indices 1 to {n_cols})."
    ))
  }

  col_names <- names(data)[start_col:end_col]
  cli::cli_alert_info(
    "Column range {.val {spec}} expanded to {length(col_names)} column{?s}: \\
     {.val {names(data)[start_col]}} – {.val {names(data)[end_col]}}"
  )
  col_names
}

# ---------------------------------------------------------------------------
# INTERACTIVE HELPERS
# ---------------------------------------------------------------------------

#' Interactively select columns from a dataset
#'
#' @description
#' Offers a list of column names for the user to choose from. Shows a
#' model-type-aware description and example for the role being requested.
#' Uses svDialogs::dlg_list() in RStudio / Positron / X11 GUI sessions;
#' falls back to a numbered console menu otherwise.
#'
#' @param data A tibble.
#' @param role Character. One of the standard variable role names.
#' @param multi Logical. Allow multiple selections? Default TRUE.
#' @param required Logical. If TRUE and user selects nothing, aborts.
#' @param model_type Character. Current model type for contextual descriptions.
#'
#' @return Character vector of selected column names.
#'
#' @keywords internal
.interactive_select_columns <- function(data, role, multi = TRUE, required = TRUE,
                                        model_type = NULL) {
  cols  <- names(data)

  if (identical(role, "dependent_variables")) {
    # DVs must be numeric
    cols <- cols[sapply(data, is.numeric)]
    # Exclude common design/metadata columns
    cols <- .filter_sensory_attributes(cols)
  }

  label <- .get_slot_description(role, model_type)

  # Use GUI only for short lists in an interactive session — for large lists the
  # console grid is faster and supports range input which the OS dialog cannot.
  is_interactive_session <- !identical(Sys.getenv("RSTUDIO"), "") ||
                            !identical(Sys.getenv("POSITRON"), "") ||
                            interactive()
  use_gui <- is_interactive_session && length(cols) <= 20

  while (TRUE) {
    cat("\n")
    cli::cli_rule(paste("Select:", role))
    cat(label, "\n")
    if (multi) cat("(Multiple selections: comma-separated numbers, ranges, or mixed — e.g. '1,3', '5-20', '1,5-20,25')\n")

    # 1. GUI picker for short lists
    if (use_gui && requireNamespace("svDialogs", quietly = TRUE)) {
      res <- tryCatch({
        svDialogs::dlg_list(
          choices  = cols,
          multiple = multi,
          title    = paste("Select:", role)
        )$res
      }, error = function(e) NULL)

      if (!is.null(res)) {
        if (length(res) == 0 || all(!nzchar(res))) {
          if (required) {
            abort_choice <- utils::askYesNo(
              paste0("No column selected for '", role, "'. Do you want to abort the pipeline?"),
              default = TRUE
            )
            if (isTRUE(abort_choice) || is.na(abort_choice)) {
              cli::cli_abort("Pipeline execution aborted by user.")
            }
            next
          } else {
            return(NULL)
          }
        }
        return(res)
      }
    }

    # 2. Console: numbered grid + range/mixed input
    cat("\nAvailable columns:\n")
    .print_cols_grid(cols, width = 3, col_width = 32)

    cat("\n")
    cli::cli_rule(paste("Prompt:", role))
    cat(label, "\n")
    if (multi) cat("-> Enter numbers, ranges, or mixed (e.g. '1,3,5', '5-20', '1,5-20,25')\n")
    else cat("-> Single selection only\n")

    cat("\nEnter column number(s) or press Enter to skip:\n> ")
    input <- trimws(readline())

    if (!nzchar(input)) {
      if (required) {
        abort_choice <- utils::askYesNo(
          paste0("No column selected for '", role, "'. Do you want to abort the pipeline?"),
          default = TRUE
        )
        if (isTRUE(abort_choice) || is.na(abort_choice)) {
          cli::cli_abort("Pipeline execution aborted by user.")
        }
        next
      } else {
        return(NULL)
      }
    }

    indices <- .parse_selection_input(input, length(cols))
    if (is.null(indices)) {
      cli::cli_alert_danger(
        "Invalid input '{input}'. Use numbers, ranges (5-20), or mixed (1,5-20,25)."
      )
      next
    }

    invalid <- indices[indices < 1 | indices > length(cols)]
    if (length(invalid) > 0) {
      cli::cli_alert_danger("Out-of-range number{?s}: {paste(invalid, collapse = ', ')} (max {length(cols)})")
      next
    }

    if (!multi && length(indices) > 1) {
      cli::cli_alert_warning("Only one column allowed for '{role}'. Using first selection.")
      indices <- indices[1]
    }

    return(cols[indices])
  }
}

# ---------------------------------------------------------------------------
# YAML CONFIG MANAGEMENT
# ---------------------------------------------------------------------------

#' Write Analysis Configuration to YAML
#'
#' @description
#' Saves the current analysis selections (variable names, factor names,
#' model type, outlier policy, post-hoc method, etc.) to a YAML file so
#' the run can be reproduced exactly without dialogs.
#'
#' @param config The full config list from mission_control.R (including
#'   selections already resolved by `select_analysis_variables()`).
#' @param selections List returned by `select_analysis_variables()`.
#' @param path Character. Path to write the YAML file. Defaults to
#'   `data/dictionary/analysis_config.yaml`.
#' @param overwrite Logical. If FALSE (default) and the file already
#'   exists, asks the user before overwriting. If TRUE, overwrites silently.
#'
#' @return Invisibly returns the path written.
#'
#' @examples
#' \dontrun{
#'   write_analysis_config(config, selections)
#' }
#'
#' @export
write_analysis_config <- function(config,
                                  selections,
                                  path      = here::here("data", "dictionary", "analysis_config.yaml"),
                                  overwrite = FALSE) {
  if (file.exists(path) && !overwrite) {
    if (interactive()) {
      response <- readline(
        prompt = paste0("analysis_config.yaml already exists. Overwrite? (yes/no): ")
      )
      if (tolower(substr(response, 1, 1)) != "y") {
        cli::cli_alert_info("Config not overwritten. Using existing file.")
        return(invisible(path))
      }
    } else {
      cli::cli_alert_info("Config already exists and overwrite = FALSE. Skipping write.")
      return(invisible(path))
    }
  }

  # Ensure target directory exists before writing. This allows custom config
  # paths under data/dictionary/ or elsewhere in the project.
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)

  # Build the config record
  config_record <- list(
    meta = list(
      created_at  = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      r_version   = paste0(R.version$major, ".", R.version$minor),
      data_file   = if (!is.null(config$paths$raw_data)) config$paths$raw_data else "not set"
    ),
    analysis = list(
      dependent_variables       = as.list(selections$dependent_variables),
      factors                   = as.list(selections$factors),
      subject_id                = selections$subject_id,
      repeated_measures_factors = if (length(selections$repeated_measures_factors) > 0)
                                    as.list(selections$repeated_measures_factors) else list(),
      random_effects            = if (length(selections$random_effects) > 0)
                                    as.list(selections$random_effects) else list(),
      blocking_factors          = if (length(selections$blocking_factors) > 0)
                                    as.list(selections$blocking_factors) else list(),
      model_type                = config$analysis$model_type,
      model_fixed_effects       = if (length(config$analysis$model_fixed_effects) > 0)
                as.list(config$analysis$model_fixed_effects) else NULL,
      posthoc_method            = config$analysis$posthoc_method,
      posthoc_focal_terms       = if (length(config$analysis$posthoc_focal_terms) > 0)
                                    as.list(config$analysis$posthoc_focal_terms) else NULL,
      outlier_policy            = config$analysis$outlier_policy,
      outlier_removal_action    = config$analysis$outlier_removal_action,
      outlier_grouping_factors  = if (length(config$analysis$outlier_grouping_factors) > 0)
                                    as.list(config$analysis$outlier_grouping_factors) else NULL,
      descriptive_grouping_factors = if (length(config$analysis$descriptive_grouping_factors) > 0)
                                       as.list(config$analysis$descriptive_grouping_factors) else NULL,
      alpha                     = config$analysis$alpha
    ),
    toggles = config$toggles
  )

  yaml::write_yaml(config_record, path)
  cli::cli_alert_success("Analysis config saved: {.path {path}}")
  invisible(path)
}

#' Read Analysis Configuration from YAML
#'
#' @description
#' Loads a previously saved analysis configuration from a YAML file and
#' merges it back into the config list for reproducible pipeline runs.
#'
#' @param path Character. Path to the YAML file. Defaults to
#'   `data/dictionary/analysis_config.yaml`.
#' @param verbose Logical. If TRUE (default), prints a summary of the
#'   loaded configuration.
#'
#' @return A list matching the structure of `config$analysis` in mission_control.R,
#'   plus a `$meta` element with creation timestamp and R version.
#'
#' @examples
#' \dontrun{
#'   saved_config <- read_analysis_config()
#'   config$analysis <- saved_config$analysis
#' }
#'
#' @export
read_analysis_config <- function(
    path    = here::here("data", "dictionary", "analysis_config.yaml"),
    verbose = TRUE) {

  if (!file.exists(path)) {
    cli::cli_abort(
      "Analysis config file not found: {.path {path}}\n",
      "Run write_analysis_config() first, or set variables manually in mission_control.R."
    )
  }

  cfg <- yaml::read_yaml(path)

  # Convert YAML lists back to character vectors. Empty YAML lists become NULL
  # so optional roles behave the same whether they came from YAML or
  # mission_control.R.
  as_chr_or_null <- function(x) {
    if (is.null(x) || length(x) == 0) return(NULL)
    out <- unlist(x, use.names = FALSE)
    if (length(out) == 0) NULL else as.character(out)
  }

  cfg$analysis$dependent_variables <- as_chr_or_null(cfg$analysis$dependent_variables)
  cfg$analysis$factors <- as_chr_or_null(cfg$analysis$factors)
  cfg$analysis$subject_id <- as_chr_or_null(cfg$analysis$subject_id)
  cfg$analysis$model_fixed_effects <- as_chr_or_null(cfg$analysis$model_fixed_effects)
  cfg$analysis$repeated_measures_factors <- as_chr_or_null(cfg$analysis$repeated_measures_factors)
  cfg$analysis$random_effects <- as_chr_or_null(cfg$analysis$random_effects)
  cfg$analysis$blocking_factors <- as_chr_or_null(cfg$analysis$blocking_factors)
  cfg$analysis$posthoc_focal_terms <- as_chr_or_null(cfg$analysis$posthoc_focal_terms)
  cfg$analysis$outlier_grouping_factors <- as_chr_or_null(cfg$analysis$outlier_grouping_factors)
  cfg$analysis$descriptive_grouping_factors <- as_chr_or_null(cfg$analysis$descriptive_grouping_factors)

  if (verbose) {
    cli::cli_h3("Loaded Analysis Configuration")
    cli::cli_inform("Created   : {cfg$meta$created_at}")
    cli::cli_inform("Data file : {cfg$meta$data_file}")
    cli::cli_inform("DVs       : {length(cfg$analysis$dependent_variables)}")
    cli::cli_inform("Factors   : {paste(cfg$analysis$factors, collapse = ', ')}")
    cli::cli_inform("Model     : {cfg$analysis$model_type}")
    cli::cli_inform("Post-hoc  : {cfg$analysis$posthoc_method}")
    cli::cli_inform("Outliers  : {cfg$analysis$outlier_policy}")
  }

  cfg
}

# ---------------------------------------------------------------------------
# COERCION HELPERS
# ---------------------------------------------------------------------------

#' Coerce Identified Factor Columns to Factor Type
#'
#' @description
#' Takes the `selections$factors` and `selections$subject_id` columns and
#' converts them from character/numeric to R factors.
#'
#' @param data A tibble.
#' @param selections List returned by `select_analysis_variables()`.
#'
#' @return The same tibble with the specified columns coerced to factor.
#'
#' @examples
#' \dontrun{
#'   data <- coerce_to_factors(data, selections)
#' }
#'
#' @export
coerce_to_factors <- function(data, selections) {
  factor_cols <- unique(c(
    selections$factors,
    selections$subject_id,
    selections$repeated_measures_factors,
    selections$blocking_factors
  ))
  factor_cols <- factor_cols[!is.null(factor_cols) & nzchar(factor_cols)]

  for (col in factor_cols) {
    if (col %in% names(data)) {
      data[[col]] <- as.factor(data[[col]])
    }
  }

  cli::cli_alert_success(
    "Coerced {length(factor_cols)} column{?s} to factor: {paste(factor_cols, collapse = ', ')}"
  )

  data
}

#' Validate Variable Selections Against Dataset
#'
#' @description
#' Checks that:
#' 1. All named columns actually exist in the dataset.
#' 2. Dependent variables are numeric.
#' 3. Factor columns are not numeric.
#' 4. Subject ID column is not already a DV.
#'
#' @param data A tibble (after column name cleaning).
#' @param selections List returned by `select_analysis_variables()`.
#'
#' @return Invisibly returns TRUE if all checks pass.
#'   Calls `cli::cli_abort()` with a detailed message on failure.
#'
#' @export
validate_variable_selections <- function(data, selections) {
  errors <- character(0)

  all_named <- c(
    selections$dependent_variables,
    selections$factors,
    selections$subject_id,
    selections$repeated_measures_factors,
    selections$random_effects,
    selections$blocking_factors
  )
  all_named <- all_named[!is.null(all_named) & nzchar(all_named)]

  # Check all columns exist
  missing_cols <- setdiff(all_named, names(data))
  if (length(missing_cols) > 0) {
    errors <- c(errors, paste0("Columns not found in data: ",
                               paste(missing_cols, collapse = ", ")))
  }

  # Check DVs are numeric
  non_numeric_dvs <- selections$dependent_variables[
    !sapply(selections$dependent_variables, function(col) {
      col %in% names(data) && is.numeric(data[[col]])
    })
  ]
  if (length(non_numeric_dvs) > 0) {
    errors <- c(errors, paste0("Dependent variables are not numeric: ",
                               paste(non_numeric_dvs, collapse = ", ")))
  }

  # Check subject_id is not also a DV
  if (!is.null(selections$subject_id) &&
      selections$subject_id %in% selections$dependent_variables) {
    errors <- c(errors,
                paste0("Subject ID '", selections$subject_id,
                       "' is also listed as a dependent variable."))
  }

  if (length(errors) > 0) {
    cli::cli_abort(c(
      "Variable selection validation failed:",
      setNames(errors, rep("x", length(errors)))
    ))
  }

  cli::cli_alert_success("Variable selections validated successfully")
  invisible(TRUE)
}

#' Filter out metadata/design columns from sensory attribute selections
#'
#' @keywords internal
.filter_sensory_attributes <- function(cols) {
  # Common non-sensory design or metadata column names/patterns in sensory studies
  ignored_patterns <- c(
    "^user$", "^assessor$", "^panelist$", "^judge$", "^subject",
    "^product$", "^treatment$", "^session$", "^replica$", "^rep$",
    "^blinding", "^sample$", "^run$", "^block$", "^order$", "^id$"
  )
  
  exclude_mask <- logical(length(cols))
  for (pat in ignored_patterns) {
    exclude_mask <- exclude_mask | grepl(pat, cols, ignore.case = TRUE)
  }
  
  cols[!exclude_mask]
}

#' Parse a selection input string into a vector of integer indices
#'
#' Supports individual numbers, ranges, and any mix:
#'   "5"          -> 5
#'   "5-20"       -> 5,6,...,20
#'   "1,3,5-10"   -> 1,3,5,6,7,8,9,10
#'
#' Returns NULL if any token is not a valid number or range.
#'
#' @keywords internal
.parse_selection_input <- function(input, max_idx) {
  tokens  <- strsplit(trimws(input), "[,\\s]+")[[1]]
  tokens  <- tokens[nzchar(tokens)]
  indices <- integer(0)

  for (tok in tokens) {
    if (grepl("^\\d+[:\\-]\\d+$", tok)) {
      parts <- as.integer(strsplit(tok, "[:\\-]")[[1]])
      if (parts[1] > parts[2]) return(NULL)
      indices <- c(indices, seq(parts[1], parts[2]))
    } else {
      n <- suppressWarnings(as.integer(tok))
      if (is.na(n)) return(NULL)
      indices <- c(indices, n)
    }
  }

  unique(sort(indices))
}

#' Print column list in a clean multi-column grid
#'
#' @keywords internal
.print_cols_grid <- function(cols, width = 3, col_width = 32) {
  n <- length(cols)
  rows <- ceiling(n / width)
  for (r in 1:rows) {
    row_str <- ""
    for (c in 1:width) {
      idx <- r + (c - 1) * rows
      if (idx <= n) {
        item <- sprintf("  [%3d] %s", idx, cols[idx])
        if (nchar(item) < col_width) {
          item <- paste0(item, paste(rep(" ", col_width - nchar(item)), collapse = ""))
        }
        row_str <- paste0(row_str, item)
      }
    }
    cat(row_str, "\n")
  }
}

# ---------------------------------------------------------------------------
# GUIDED FIRST-RUN SETUP HELPERS
# ---------------------------------------------------------------------------
# Small console prompts used by .sensanalyser_interactive_setup() to walk a new
# project through data, columns, model, and subsets. All degrade to readline in
# headless sessions (no GUI dependency).

#' Pick items from a list by number/range in the console.
#' @keywords internal
.interactive_pick_from <- function(choices, prompt, multi = TRUE, allow_empty = TRUE) {
  if (length(choices) == 0) return(character(0))
  repeat {
    cat("\n"); cli::cli_rule(prompt)
    .print_cols_grid(choices, width = 3, col_width = 32)
    if (multi) {
      cat("\n-> Enter numbers/ranges (e.g. '1,3', '5-20', '1,5-20')",
          if (allow_empty) ", or press Enter to skip" else "", ":\n> ", sep = "")
    } else {
      cat("\n-> Enter one number:\n> ")
    }
    input <- trimws(readline())
    if (!nzchar(input)) {
      if (allow_empty) return(character(0))
      cli::cli_alert_danger("A selection is required here."); next
    }
    idx <- .parse_selection_input(input, length(choices))
    if (is.null(idx) || any(idx < 1 | idx > length(choices))) {
      cli::cli_alert_danger("Invalid input. Use numbers or ranges within 1-{length(choices)}."); next
    }
    if (!multi) idx <- idx[1]
    return(choices[idx])
  }
}

#' Ask the user to choose a statistical model from the presets.
#' @param presets Named list read from model_presets.yaml (name -> {description}).
#' @return The chosen model_type (a preset name).
#' @keywords internal
.interactive_select_model <- function(presets) {
  types <- names(presets)
  cat("\n"); cli::cli_rule("Choose the statistical model")
  for (i in seq_along(types)) {
    d <- gsub("\\s+", " ", trimws(presets[[types[i]]]$description %||% ""))
    cli::cli_text("{i}. {.strong {types[i]}} - {d}")
  }
  repeat {
    cat("\n-> Enter the model number:\n> ")
    n <- suppressWarnings(as.integer(trimws(readline())))
    if (!is.na(n) && n >= 1 && n <= length(types)) {
      cli::cli_alert_success("Model: {.strong {types[n]}}")
      return(types[n])
    }
    cli::cli_alert_danger("Enter a number between 1 and {length(types)}.")
  }
}

#' Show every column and let the user drop unwanted ones completely.
#' @return Character vector of column names to exclude from all analyses.
#' @keywords internal
.interactive_remove_columns <- function(data) {
  cli::cli_h2("Remove unwanted columns")
  cli::cli_text(paste(
    "Below are all columns in your data. Select any you want to drop completely",
    "(e.g. notes, barcodes, blank columns). They are excluded from every analysis."
  ))
  chosen <- .interactive_pick_from(names(data), "Columns to remove (optional)",
                                   multi = TRUE, allow_empty = TRUE)
  if (length(chosen)) {
    cli::cli_alert_info("Removing: {paste(chosen, collapse = ', ')}")
  } else {
    cli::cli_alert_info("Keeping all columns.")
  }
  chosen
}

#' Ask whether to analyse the whole dataset, subsets, or both; define subsets.
#' @return list(scope = "general"|"subsets"|"both", subsets = named include-lists)
#' @keywords internal
.interactive_select_scope_and_subsets <- function(data, product_col) {
  products <- sort(unique(as.character(data[[product_col]])))

  cli::cli_h2("Analysis scope")
  cli::cli_text("Analyse the whole dataset, only subsets of products, or both?")
  cli::cli_text("1. general - whole dataset only")
  cli::cli_text("2. subsets - only the product subsets you define")
  cli::cli_text("3. both    - whole dataset AND subsets")
  scope <- NULL
  repeat {
    cat("\n-> Enter 1, 2 or 3:\n> ")
    n <- suppressWarnings(as.integer(trimws(readline())))
    if (!is.na(n) && n %in% 1:3) { scope <- c("general", "subsets", "both")[n]; break }
    cli::cli_alert_danger("Enter 1, 2 or 3.")
  }

  subsets <- list()
  if (scope %in% c("subsets", "both")) {
    repeat {
      cat("\n-> Name for this subset (e.g. gluten_free):\n> ")
      raw_name <- trimws(readline())
      name <- gsub("[^a-z0-9]+", "_", tolower(raw_name))
      name <- gsub("^_|_$", "", name)
      if (!nzchar(name)) { cli::cli_alert_danger("Please enter a name."); next }
      picked <- .interactive_pick_from(
        products, sprintf("Products in subset '%s'", name),
        multi = TRUE, allow_empty = FALSE
      )
      subsets[[name]] <- list(include = as.list(picked))
      cli::cli_alert_success("Subset '{name}': {length(picked)} product(s).")
      more <- utils::askYesNo("Define another subset?", default = FALSE)
      if (!isTRUE(more)) break
    }
  }
  list(scope = scope, subsets = subsets)
}

#' Write a products + attributes reference file (data_summary.yaml).
#' @keywords internal
.write_data_summary <- function(project_root, data, product_col, attributes) {
  products <- if (!is.null(product_col) && product_col %in% names(data)) {
    sort(unique(as.character(data[[product_col]])))
  } else character(0)
  summary <- list(
    generated      = as.character(Sys.time()),
    rows           = nrow(data),
    product_column = product_col %||% "",
    products       = as.list(products),
    attributes     = as.list(as.character(attributes))
  )
  path <- file.path(project_root, "data_summary.yaml")
  yaml::write_yaml(summary, path)
  cli::cli_alert_success(
    "Wrote {.path data_summary.yaml} ({length(products)} products, {length(attributes)} attributes)."
  )
  invisible(path)
}
