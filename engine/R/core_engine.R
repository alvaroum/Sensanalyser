#' Sensanalyser Core Pipeline Engine
#'
#' @description
#' Orchestrates the full Sensanalyser analysis pipeline. This engine reads
#' the config list produced by mission_control.R and routes through each
#' active phase in sequence.
#'
#' Currently implemented:
#'   Phase 1 — Project setup and environment verification
#'   Phase 2 — Data import and variable selection
#'
#' Stubbed for future phases (3–9):
#'   Phase 3 — Outlier detection
#'   Phase 4 — Descriptives
#'   Phase 5 — Statistical models
#'   Phase 6 — Post-hoc tests
#'   Phase 7 — Table system
#'   Phase 8 — Figures, PCA, MFA
#'   Phase 9 — Quarto report
#'
#' @author Sensanalyser project
#' @keywords internal

# ---------------------------------------------------------------------------
# MAIN ENTRY POINT
# ---------------------------------------------------------------------------

#' Run the Sensanalyser Pipeline
#'
#' @description
#' The single function called by mission_control.R.
#' All pipeline state is contained in the returned list.
#'
#' @param config A list produced by mission_control.R. See that file for
#'   the full structure.
#'
#' @return Invisibly returns a list (`pipeline_state`) with:
#'   - `$data_raw`: the original loaded dataset
#'   - `$data`: the working dataset (after outlier removal if applied)
#'   - `$selections`: variable selection list
#'   - `$config`: the resolved config (potentially updated from YAML)
#'   - `$results`: named list of analysis results (built up through later phases)
#'
#' Delete a project's generated artifacts (outputs, cleaned data, reports)
#'
#' @description
#' Clears everything the pipeline produces so a project can be re-run from a
#' clean slate: the run record, the contents of `outputs/`, the cleaned CSVs
#' in `data/clean/`, and rendered reports. Raw data, `settings.yaml` and the
#' display labels are never touched. Paths are resolved from
#' `config$project_root` so the cleaned-data folder is always `data/clean`.
#'
#' @param config The engine config list (needs `project_root` and `paths`).
#' @return Invisibly, the character vector of locations cleared.
#' @keywords internal
.sensanalyser_clear_outputs <- function(config) {
  cli::cli_alert_info("Clearing outputs and cleaned data to start from scratch...")
  cleared <- character(0)

  root <- config$project_root
  if (is.null(root) && !is.null(config$paths$table_root)) {
    # Fall back to walking up from outputs/tables when project_root is absent.
    root <- dirname(dirname(config$paths$table_root))
  }

  # 1. Run record (settings mode: state/resolved_run.yaml; legacy: analysis_config.yaml)
  saved_cfg_path <- config$paths$analysis_config
  if (!is.null(saved_cfg_path) && file.exists(saved_cfg_path)) {
    file.remove(saved_cfg_path)
    cleared <- c(cleared, saved_cfg_path)
  }

  # 2. Outputs (tables, figures, diagnostics, logs)
  outputs_dirs <- c(config$paths$table_root, config$paths$figure_root,
                    config$paths$diagnostics_root, config$paths$logs_root)
  for (d in outputs_dirs) {
    if (!is.null(d) && dir.exists(d)) {
      unlink(list.files(d, full.names = TRUE), recursive = TRUE)
      cleared <- c(cleared, d)
    }
  }

  # 3. Cleaned data CSVs — resolved from the project root, not the run record.
  if (!is.null(root)) {
    clean_dir <- file.path(root, "data", "clean")
    if (dir.exists(clean_dir)) {
      unlink(list.files(clean_dir, full.names = TRUE), recursive = TRUE)
      cleared <- c(cleared, clean_dir)
    }
  }

  # 4. Rendered reports (keep the .qmd source and the Quarto cache clean)
  if (!is.null(config$paths$report_template)) {
    report_dir <- dirname(config$paths$report_template)
    if (dir.exists(report_dir)) {
      rendered <- list.files(report_dir, pattern = "\\.(html|docx|pdf|tex|aux|log|toc)$",
                             full.names = TRUE)
      rendered <- rendered[!grepl("\\.qmd$", rendered)]
      if (length(rendered) > 0) {
        file.remove(rendered)
        cleared <- c(cleared, report_dir)
      }
      cache_dir <- file.path(report_dir, paste0(
        tools::file_path_sans_ext(basename(config$paths$report_template)), "_files"))
      if (dir.exists(cache_dir)) unlink(cache_dir, recursive = TRUE)
    }
  }

  if (length(cleared) > 0) {
    cli::cli_alert_success("Cleared: {.path {unique(cleared)}}")
  } else {
    cli::cli_alert_info("Nothing to clear.")
  }
  invisible(unique(cleared))
}

#' @examples
#' \dontrun{
#'   source(here::here("engine", "R", "core_engine.R"))
#'   run_sensanalyser_pipeline(config)
#' }
#'
#' @export
run_sensanalyser_pipeline <- function(config) {

  cli::cli_h1("Sensanalyser Pipeline")
  cli::cli_inform("Started: {format(Sys.time(), '%Y-%m-%d %H:%M:%S')}")

  # ── ENVIRONMENT SETUP ───────────────────────────────────────────────────
  .source_all_helpers()

  # In interactive mode, ask if the user wants to start from scratch (delete config, outputs, and rendered reports)
  is_interactive_env <- !identical(Sys.getenv("RSTUDIO"), "") || !identical(Sys.getenv("POSITRON"), "") || interactive()
  if (isTRUE(config$toggles$interactive_setup) && is_interactive_env) {
    outputs_exist <- FALSE
    saved_cfg_path <- config$paths$analysis_config
    if (!is.null(saved_cfg_path) && file.exists(saved_cfg_path)) {
      outputs_exist <- TRUE
    } else {
      outputs_dirs <- c(
        config$paths$table_root,
        config$paths$figure_root,
        config$paths$diagnostics_root,
        config$paths$logs_root
      )
      for (d in outputs_dirs) {
        if (!is.null(d) && dir.exists(d) && length(list.files(d)) > 0) {
          outputs_exist <- TRUE
          break
        }
      }
    }
    
    if (outputs_exist) {
      clear_choice <- utils::askYesNo(
        "Do you want to delete the current environment config and all existing outputs/reports to start from scratch?",
        default = FALSE
      )
      if (isTRUE(clear_choice)) {
        .sensanalyser_clear_outputs(config)
      }
    }
  }

  # Initialise pipeline state object
  pipeline_state <- list(
    data_raw   = NULL,
    data       = NULL,
    selections = NULL,
    config     = config,
    results    = list()
  )

  # ── PHASE 2: DATA IMPORT ────────────────────────────────────────────────
  pipeline_state <- .phase2_data_import(pipeline_state)

  # ── PROJECT-SPECIFIC DERIVED ATTRIBUTES ─────────────────────────────────
  # Optional pre-analysis transformation layer. This adds derived variables to
  # the working dataset while keeping data_raw unchanged for auditability.
  if (isTRUE(pipeline_state$config$toggles$create_derived_attributes)) {
    pipeline_state <- .phase2_derived_attributes(pipeline_state)

    # If output_label is set, redirect all outputs to a named subfolder so
    # derived-attribute runs never overwrite the regular analysis outputs.
    output_label <- trimws(
      pipeline_state$config$derived_attribute_options$output_label %||% ""
    )
    if (nzchar(output_label)) {
      p <- pipeline_state$config$paths
      pipeline_state$config$paths$table_root       <- file.path(p$table_root,       output_label)
      pipeline_state$config$paths$figure_root      <- file.path(p$figure_root,      output_label)
      pipeline_state$config$paths$diagnostics_root <- file.path(p$diagnostics_root, output_label)
      pipeline_state$config$paths$logs_root        <- file.path(p$logs_root,        output_label)
      cli::cli_alert_info(
        "Derived-attribute run — outputs redirected to '{output_label}/' subfolders."
      )
    }
  }

  # ── PRODUCT SUBSET FILTER ───────────────────────────────────────────────
  # Applied only on subset runs launched from project_helpers after the main run.
  if (!is.null(pipeline_state$config$product_subset)) {
    pipeline_state <- .apply_product_subset_filter(pipeline_state)
  }

  # ── DISCOVERY MODE ──────────────────────────────────────────────────────
  # If discover_variables is TRUE, print a data overview and stop the pipeline.
  if (isTRUE(pipeline_state$config$toggles$discover_variables)) {
    cli::cli_h2("Discovery Mode Active")
    discover_dataset_structure(pipeline_state$data_raw, stop_pipeline = TRUE)
    cli::cli_alert_warning(
      "Pipeline halted at discovery mode.\n",
      "Set toggles$discover_variables = FALSE to run the full analysis."
    )
    return(invisible(pipeline_state))
  }

  # ── PHASE 2: VARIABLE SELECTION ─────────────────────────────────────────
  pipeline_state <- .phase2_variable_selection(pipeline_state)

  # ── PHASE 3: OUTLIER DETECTION ──────────────────────────────────────────
  if (isTRUE(pipeline_state$config$toggles$run_outlier_detection)) {
    pipeline_state <- .phase3_outliers(pipeline_state)
  }

  # ── PHASE 4: DESCRIPTIVES ────────────────────────────────────────────────
  if (isTRUE(pipeline_state$config$toggles$run_descriptives)) {
    pipeline_state <- .phase4_descriptives(pipeline_state)
  }

  # ── PHASE 5: STATISTICAL MODELS ─────────────────────────────────────────
  if (isTRUE(pipeline_state$config$toggles$run_anova_models) ||
      isTRUE(pipeline_state$config$toggles$run_mixed_models)) {
    pipeline_state <- .phase5_models(pipeline_state)
  }

  # ── PHASE 6: POST-HOC ────────────────────────────────────────────────────
  if (isTRUE(pipeline_state$config$toggles$run_posthoc)) {
    pipeline_state <- .phase6_posthoc(pipeline_state)
  }

  # ── PHASE 7: TABLES ──────────────────────────────────────────────────────
  if (isTRUE(pipeline_state$config$toggles$create_tables)) {
    pipeline_state <- .phase7_tables(pipeline_state)
  }

  # ── PHASE 8: FIGURES, PCA, MFA ──────────────────────────────────────────
  if (isTRUE(pipeline_state$config$toggles$create_figures) ||
      isTRUE(pipeline_state$config$toggles$run_pca) ||
      isTRUE(pipeline_state$config$toggles$run_mfa)) {
    pipeline_state <- .phase8_multivariate(pipeline_state)
  }

  # ── PHASE 9: REPORT ──────────────────────────────────────────────────────
  if (isTRUE(pipeline_state$config$toggles$render_quarto_report)) {
    pipeline_state <- .phase9_report(pipeline_state)
  }

  # ── DONE ─────────────────────────────────────────────────────────────────
  cli::cli_h2("Pipeline Complete")
  cli::cli_inform("Finished: {format(Sys.time(), '%Y-%m-%d %H:%M:%S')}")
  cli::cli_alert_success("Pipeline complete.")

  invisible(pipeline_state)
}

# ---------------------------------------------------------------------------
# PHASE 2: DATA IMPORT
# ---------------------------------------------------------------------------

#' Internal: Phase 2 — Data Import
#'
#' @keywords internal
.phase2_data_import <- function(pipeline_state) {
  config <- pipeline_state$config

  cli::cli_h2("Phase 2: Data Import")

  # In non-interactive mode, restore settings from the saved analysis_config.yaml.
  # Two independent reasons to load the YAML:
  #   (a) raw_data is NULL  → must restore the data file path
  #   (b) dependent_variables is NULL or "auto"  → restore full analysis selections
  # Explicit character vectors in project_config always take priority over YAML.
  saved_config_path <- config$paths$analysis_config

  needs_yaml_for_path     <- is.null(config$paths$raw_data)
  needs_yaml_for_analysis <- is.null(config$analysis$dependent_variables) ||
                             identical(config$analysis$dependent_variables, "auto")

  # settings.yaml is authoritative: never let a stale analysis_config.yaml
  # silently override what the user wrote (the old two-sources-of-truth bug).
  if (!is.null(saved_config_path) && file.exists(saved_config_path) &&
      !isTRUE(config$toggles$interactive_setup) &&
      !isTRUE(config$settings_driven) &&
      (needs_yaml_for_path || needs_yaml_for_analysis)) {

    cli::cli_alert_info("Loading saved analysis config from YAML.")
    saved_cfg <- read_analysis_config(saved_config_path)

    # Ignore the distributed template, which contains placeholder attributes
    # rather than real column names.
    saved_dvs <- saved_cfg$analysis$dependent_variables
    placeholder_dvs <- c("attribute_1", "attribute_2", "attribute_3")
    is_template <- length(saved_dvs) > 0 && all(saved_dvs %in% placeholder_dvs)

    if (!is_template) {
      # Restore full analysis settings only when DVs were not explicitly set.
      if (needs_yaml_for_analysis) {
        config$analysis <- saved_cfg$analysis

        # Saved toggles are optional. If present, let them override the defaults
        # for reproducible reruns, but keep interactive_setup FALSE because this
        # branch is specifically the non-interactive restore path.
        if (!is.null(saved_cfg$toggles)) {
          config$toggles <- utils::modifyList(config$toggles, saved_cfg$toggles)
          config$toggles$interactive_setup <- FALSE
        }
      }

      # Always restore the data file path when it was not explicitly provided.
      if (needs_yaml_for_path && !is.null(saved_cfg$meta$data_file) &&
          !identical(saved_cfg$meta$data_file, "not set")) {
        config$paths$raw_data <- saved_cfg$meta$data_file
      }
    } else {
      cli::cli_alert_warning(
        "Saved config appears to be the template (placeholder variables). Ignoring."
      )
    }
    pipeline_state$config <- config
  }

  # Load the raw data file.
  data_raw <- load_sensanalyser_data(
    path              = config$paths$raw_data,
    interactive_setup = isTRUE(config$toggles$interactive_setup),
    verbose           = TRUE,
    config            = config
  )

  # Store the resolved path back in config for logging
  pipeline_state$config$paths$raw_data <- attr(data_raw, "source_path")

  pipeline_state$data_raw <- data_raw
  pipeline_state$data     <- data_raw   # working copy

  pipeline_state
}

# ---------------------------------------------------------------------------
# PRODUCT SUBSET FILTER
# ---------------------------------------------------------------------------

#' Internal: filter data to a product subset definition
#'
#' @keywords internal
.apply_product_subset_filter <- function(pipeline_state) {
  subset     <- pipeline_state$config$product_subset
  config     <- pipeline_state$config
  factor_col <- (config$analysis$factors %||% character(0))[1] %||% "product"

  if (!factor_col %in% names(pipeline_state$data)) {
    cli::cli_alert_warning(
      "Product subset '{subset$label}': column '{factor_col}' not found — filter skipped."
    )
    return(pipeline_state)
  }

  n_before <- nrow(pipeline_state$data)

  if (!is.null(subset$exclude) && length(subset$exclude) > 0) {
    keep <- !pipeline_state$data[[factor_col]] %in% subset$exclude
    pipeline_state$data     <- pipeline_state$data[keep, , drop = FALSE]
    pipeline_state$data_raw <- pipeline_state$data_raw[
      !pipeline_state$data_raw[[factor_col]] %in% subset$exclude, , drop = FALSE]
    cli::cli_alert_success(
      "Subset '{subset$label}': excluded {length(subset$exclude)} product(s) — {n_before - nrow(pipeline_state$data)} rows removed."
    )

  } else if (!is.null(subset$include) && length(subset$include) > 0) {
    keep <- pipeline_state$data[[factor_col]] %in% subset$include
    pipeline_state$data     <- pipeline_state$data[keep, , drop = FALSE]
    pipeline_state$data_raw <- pipeline_state$data_raw[
      pipeline_state$data_raw[[factor_col]] %in% subset$include, , drop = FALSE]
    cli::cli_alert_success(
      "Subset '{subset$label}': keeping {length(subset$include)} product(s) — {nrow(pipeline_state$data)} rows retained."
    )
  }

  pipeline_state
}

# ---------------------------------------------------------------------------
# PHASE 2B: PROJECT-SPECIFIC DERIVED ATTRIBUTES
# ---------------------------------------------------------------------------

#' Internal: Phase 2B — Derived Attributes
#'
#' @keywords internal
.phase2_derived_attributes <- function(pipeline_state) {
  config <- pipeline_state$config

  if (!exists("run_derived_attribute_phase", mode = "function")) {
    cli::cli_abort("Derived-attribute helper is not available. Check R/functions/derived_attribute_helpers.R.")
  }

  derived_data <- run_derived_attribute_phase(
    data = pipeline_state$data,
    config = config
  )

  pipeline_state$data <- derived_data
  pipeline_state
}

# ---------------------------------------------------------------------------
# PHASE 2: VARIABLE SELECTION
# ---------------------------------------------------------------------------

#' Internal: Phase 2 — Variable Selection
#'
#' @keywords internal
.phase2_variable_selection <- function(pipeline_state) {
  config <- pipeline_state$config
  data   <- pipeline_state$data

  cli::cli_h2("Phase 2: Variable Selection")

  interactive_mode <- isTRUE(config$toggles$interactive_setup)

  if (interactive_mode) {
    while (TRUE) {
      selections <- tryCatch({
        select_analysis_variables(data, config)
      }, error = function(e) {
        cli::cli_alert_danger("Error during variable selection: {e$message}")
        NULL
      })

      if (is.null(selections)) {
        next
      }

      val_res <- tryCatch({
        validate_variable_selections(data, selections)
        TRUE
      }, error = function(e) {
        cat(conditionMessage(e), "\n")
        FALSE
      })

      if (val_res) {
        break
      }

      retry_choice <- utils::askYesNo("Variable selection validation failed. Do you want to try selecting variables again?", default = TRUE)
      if (!isTRUE(retry_choice)) {
        cli::cli_abort("Pipeline aborted by user due to validation failure.")
      }
    }
  } else {
    selections <- select_analysis_variables(data, config)
    validate_variable_selections(data, selections)
  }

  # Coerce factor columns
  pipeline_state$data <- coerce_to_factors(data, selections)

  # Save config to YAML if this was an interactive run
  if (isTRUE(config$toggles$interactive_setup)) {
    write_analysis_config(
      config      = pipeline_state$config,
      selections  = selections,
      path        = pipeline_state$config$paths$analysis_config,
      overwrite   = TRUE
    )
  }

  pipeline_state$selections <- selections

  # Sync resolved column names back into config$analysis so every downstream
  # phase (models, posthoc, descriptives) can read them from config without
  # needing a separate selections argument.  This matters when the values were
  # determined interactively or via "auto" and config$analysis still holds the
  # original NULL / "auto" values set in mission_control.R.
  pipeline_state$config$analysis$dependent_variables       <- selections$dependent_variables
  pipeline_state$config$analysis$factors                   <- selections$factors
  pipeline_state$config$analysis$subject_id                <- selections$subject_id
  pipeline_state$config$analysis$repeated_measures_factors <- selections$repeated_measures_factors
  pipeline_state$config$analysis$random_effects            <- selections$random_effects
  pipeline_state$config$analysis$blocking_factors          <- selections$blocking_factors

  pipeline_state
}

# ---------------------------------------------------------------------------
# PHASE 3: OUTLIER DETECTION
# ---------------------------------------------------------------------------

#' Internal: Phase 3 — Outlier Detection and Policy
#'
#' @keywords internal
.phase3_outliers <- function(pipeline_state) {
  config <- pipeline_state$config
  data <- pipeline_state$data
  selections <- pipeline_state$selections

  # Use outlier helper orchestrator
  outlier_result <- run_outlier_phase(
    data = data,
    selections = selections,
    config = config
  )

  # Apply policy only when toggle says so
  if (isTRUE(config$toggles$apply_outlier_policy)) {
    pipeline_state$data <- outlier_result$data
  } else {
    cli::cli_alert_info("apply_outlier_policy is FALSE; leaving working data unchanged.")
  }

  pipeline_state$results$outliers <- list(
    outliers_all = outlier_result$outliers_all,
    policy_table = outlier_result$policy_table,
    summary = outlier_result$summary
  )

  pipeline_state
}

# ---------------------------------------------------------------------------
# PHASE 4: DESCRIPTIVES
# ---------------------------------------------------------------------------

#' Internal: Phase 4 — Descriptive Tables
#'
#' @keywords internal
.phase4_descriptives <- function(pipeline_state) {
  config <- pipeline_state$config
  data <- pipeline_state$data
  selections <- pipeline_state$selections

  desc_result <- run_descriptive_phase(
    data = data,
    selections = selections,
    config = config
  )

  pipeline_state$results$descriptives <- desc_result
  pipeline_state
}

# ---------------------------------------------------------------------------
# PHASE 5: MODELS
# ---------------------------------------------------------------------------

#' Internal: Phase 5 — Statistical Models
#'
#' @keywords internal
.phase5_models <- function(pipeline_state) {
  config <- pipeline_state$config
  data <- pipeline_state$data
  selections <- pipeline_state$selections

  model_result <- run_model_phase(
    data = data,
    selections = selections,
    config = config
  )

  pipeline_state$results$models <- model_result
  pipeline_state
}

# ---------------------------------------------------------------------------
# PHASE 6: POST-HOC
# ---------------------------------------------------------------------------

#' Internal: Phase 6 — Post-hoc Tests
#'
#' @keywords internal
.phase6_posthoc <- function(pipeline_state) {
  config <- pipeline_state$config
  data <- pipeline_state$data
  selections <- pipeline_state$selections

  model_result <- pipeline_state$results$models
  if (is.null(model_result)) {
    model_result <- run_model_phase(data, selections, config)
    pipeline_state$results$models <- model_result
  }

  posthoc_result <- run_posthoc_phase(
    data = data,
    selections = selections,
    config = config,
    model_result = model_result
  )

  pipeline_state$results$posthoc <- posthoc_result
  pipeline_state
}

# ---------------------------------------------------------------------------
# PHASE 7: TABLES
# ---------------------------------------------------------------------------

#' Internal: Phase 7 — Table System
#'
#' @keywords internal
.phase7_tables <- function(pipeline_state) {
  table_result <- run_table_phase(pipeline_state)
  pipeline_state$results$tables <- table_result
  pipeline_state
}

# ---------------------------------------------------------------------------
# PHASE 8: FIGURES, PCA, MFA
# ---------------------------------------------------------------------------

#' Internal: Phase 8 — Figures, PCA, MFA
#'
#' @keywords internal
.phase8_multivariate <- function(pipeline_state) {
  phase8_result <- run_phase8(
    data           = pipeline_state$data,
    selections     = pipeline_state$selections,
    config         = pipeline_state$config,
    posthoc_result = pipeline_state$results$posthoc
  )

  pipeline_state$results$phase8 <- phase8_result
  pipeline_state
}

# ---------------------------------------------------------------------------
# PHASE 9: REPORT
# ---------------------------------------------------------------------------

#' Internal: Phase 9 — Quarto Report
#'
#' @keywords internal
.phase9_report <- function(pipeline_state) {
  report_result <- run_report_phase(pipeline_state)
  pipeline_state$results$report <- report_result
  pipeline_state
}

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

#' Source all helper function files
#'
#' @description
#' Called once at the top of run_sensanalyser_pipeline(). Sources every
#' .R file in R/functions/ and the setup scripts needed for Phase 1.
#'
#' @keywords internal
.source_all_helpers <- function() {
  cli::cli_h2("Loading Environment")

  # Setup and package loading
  source(here::here("engine", "R", "00_setup.R"))

  # Phase 2 helpers
  source(here::here("engine", "R", "functions", "data_import_helpers.R"))
  source(here::here("engine", "R", "functions", "variable_selection_helpers.R"))

  # Future helper files (sourced only if they exist yet)
  optional_helpers <- c(
    "settings_helpers.R",
    "data_cleaning_helpers.R",
    "derived_attribute_helpers.R",
    "outlier_helpers.R",
    "descriptive_helpers.R",
    "model_helpers.R",
    "posthoc_helpers.R",
    "table_helpers.R",
    "figure_helpers.R",
    "pca_helpers.R",
    "mfa_helpers.R",
    "hcpc_helpers.R",
    "report_helpers.R"
  )

  for (helper in optional_helpers) {
    fpath <- here::here("engine", "R", "functions", helper)
    if (file.exists(fpath)) {
      source(fpath)
    }
  }

  cli::cli_alert_success("All available helpers loaded")
}
