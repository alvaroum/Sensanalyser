# ==========================================================================
# PROJECT HELPERS
# ==========================================================================
#
# Purpose:
#   Functions to manage isolated project workspaces, resolve paths, and
#   safely run the pipeline without mixing data/outputs.

library(cli)
library(yaml)
library(here)

#' Create a new isolated project folder
#' 
#' @param project_dir Directory path for the new project
#' @param project_id Optional string ID
#' @param overwrite Boolean to allow overwriting an existing project
#' @export
sensanalyser_create_project <- function(project_dir, project_id = NULL, overwrite = FALSE) {
  
  if (dir.exists(project_dir) && !overwrite) {
    if (length(list.files(project_dir)) > 0) {
      cli::cli_abort("Project directory already exists and is not empty. Set overwrite = TRUE to force.")
    }
  }
  
  cli::cli_h1("Creating new Sensanalyser project")
  cli::cli_alert_info("Path: {.path {project_dir}}")
  
  # Create standard subfolders
  folders <- c(
    "data/raw", "data/processed", "data/dictionary",
    "outputs/tables", "outputs/figures", "outputs/diagnostics", "outputs/logs",
    "reports"
  )
  
  for (f in folders) {
    dir.create(file.path(project_dir, f), recursive = TRUE, showWarnings = FALSE)
  }
  
  # A new project gets exactly one file to edit. Model presets and the report
  # template are engine assets, resolved from templates/ at run time; copy one
  # into the project only if you want to customise it.
  template_dir <- here::here("templates")
  if (file.exists(file.path(template_dir, "settings.yaml"))) {
    settings_dest <- file.path(project_dir, "settings.yaml")
    file.copy(file.path(template_dir, "settings.yaml"), settings_dest)
    lines <- readLines(settings_dest, warn = FALSE)
    lines <- sub("^(  name: )my_study", paste0("\\1", basename(project_dir)), lines)
    writeLines(lines, settings_dest)
  }

  # Write manifest
  manifest <- list(
    project_id = ifelse(is.null(project_id), basename(project_dir), project_id),
    created_at = as.character(Sys.Date()),
    status = "draft"
  )
  yaml::write_yaml(manifest, file.path(project_dir, "project_manifest.yaml"))
  
  cli::cli_alert_success("Project created successfully at {.path {project_dir}}")
  cli::cli_h2("Next Steps:")
  cli::cli_ul(c(
    "Place your data files inside {.path {file.path(project_dir, 'data/raw')}}",
    "Open {.path {file.path(project_dir, 'settings.yaml')}} - the only file you edit.",
    "Run {.code run_project('{project_dir}')} (or {.code settings_summary('{project_dir}')} first)."
  ))
  
  return(invisible(TRUE))
}

#' Resolve the project root safely
#' @export
sensanalyser_resolve_project_root <- function(project_dir) {
  if (is.null(project_dir)) {
    cli::cli_abort("project_dir cannot be NULL.")
  }
  
  if (!dir.exists(project_dir)) {
    cli::cli_abort("Project directory {.path {project_dir}} does not exist.")
  }
  
  # Return absolute path safely
  return(normalizePath(project_dir))
}

#' Return named list of project paths
#' @export
sensanalyser_project_paths <- function(project_root) {
  list(
    raw_data         = file.path(project_root, "data", "raw"),
    processed_data   = file.path(project_root, "data", "processed"),
    dictionary       = file.path(project_root, "data", "dictionary"),
    tables           = file.path(project_root, "outputs", "tables"),
    figures          = file.path(project_root, "outputs", "figures"),
    diagnostics      = file.path(project_root, "outputs", "diagnostics"),
    logs             = file.path(project_root, "outputs", "logs"),
    reports          = file.path(project_root, "reports")
  )
}

#' Validate project structure
#' @export
sensanalyser_validate_project <- function(project_root) {
  paths <- sensanalyser_project_paths(project_root)
  for (p in names(paths)) {
    if (!dir.exists(paths[[p]])) {
      cli::cli_alert_warning("Missing project folder: {.path {paths[[p]]}}. Creating it...")
      dir.create(paths[[p]], recursive = TRUE, showWarnings = FALSE)
    }
  }
}

#' Run a project with global toggles
#'
#' Configuration comes from the project's `settings.yaml` (the consolidated
#' file every user edits). Projects still carrying the legacy
#' `project_config.R` keep working: that path is used when no settings.yaml
#' exists, and `global_toggles` only apply to it.
#'
#' @export
sensanalyser_run_project <- function(project_dir, global_toggles = list()) {
  project_root <- sensanalyser_resolve_project_root(project_dir)
  sensanalyser_validate_project(project_root)

  settings_file <- sensanalyser_settings_path(project_root)
  config_file   <- file.path(project_root, "project_config.R")

  if (file.exists(settings_file)) {
    if (file.exists(config_file)) {
      cli::cli_alert_warning(
        "Both {.path settings.yaml} and {.path project_config.R} exist - using settings.yaml."
      )
    }
    if (length(global_toggles) > 0) {
      cli::cli_alert_info(
        "Ignoring global_toggles: every setting for this project lives in {.path settings.yaml}."
      )
    }
    settings <- sensanalyser_load_settings(project_root)
    sensanalyser_settings_summary(settings)
    return(invisible(.sensanalyser_run_settings(settings)))
  }

  if (!file.exists(config_file)) {
    cli::cli_abort(c(
      "No {.path settings.yaml} found in {.path {project_root}}.",
      "i" = "Create one from {.path templates/settings.yaml}, or migrate an old project_config.R."
    ))
  }

  cli::cli_alert_info(
    "Using the legacy {.path project_config.R}. Consider consolidating into {.path settings.yaml}."
  )
  project_config <- source(config_file)$value

  # Build a combined config object.
  # This merges the global defaults from the engine, global toggles from 
  # master_mission_control, and the specific project settings.
  
  # Base default config structure expected by core_engine
  final_config <- list(
    paths = list(
      raw_data = project_config$paths$raw_data, # Can be null or vector of files
      analysis_config = file.path(project_root, "data/dictionary/analysis_config.yaml"),
      renaming_dictionary = file.path(project_root, "data/dictionary/renaming_dictionary.yaml"),
      model_presets = file.path(project_root, "data/dictionary/model_presets.yaml"),
      derived_attributes = file.path(project_root, "data/dictionary/derived_attributes.yaml"),
      derived_data       = file.path(project_root, "data/processed/derived_attribute_dataset.csv"),
      table_root       = file.path(project_root, "outputs/tables"),
      figure_root      = file.path(project_root, "outputs/figures"),
      diagnostics_root = file.path(project_root, "outputs/diagnostics"),
      logs_root        = file.path(project_root, "outputs/logs"),
      report_template = file.path(project_root, "reports/sensanalyser_results_report.qmd")
    ),
    toggles = global_toggles,
    analysis = project_config$analysis,
    fig_options = project_config$fig_options,
    # Adding defaults for those not explicitly in project_config
    table_options = list(
      digits = 1,
      include_mean_se = TRUE,
      include_letters = TRUE
    ),
    derived_attribute_options = list(digits = NULL, output_label = NULL),
    report_options = list(output_formats = c("html", "docx"))
  )

  # If the project explicitly overrides any toggles, apply them
  if (!is.null(project_config$toggles)) {
    for (nm in names(project_config$toggles)) {
      final_config$toggles[[nm]] <- project_config$toggles[[nm]]
    }
  }

  # Merge project-level derived_attribute_options (e.g. output_label, digits)
  if (!is.null(project_config$derived_attribute_options)) {
    final_config$derived_attribute_options <- utils::modifyList(
      final_config$derived_attribute_options,
      project_config$derived_attribute_options
    )
  }
  
  # Tell core engine where the root is
  final_config$project_root <- project_root

  final_config$product_subsets <- project_config$product_subsets
  .sensanalyser_run_config(final_config)
}

#' Run a project described by a consolidated settings.yaml
#'
#' @param settings A list from [sensanalyser_load_settings()].
#' @keywords internal
.sensanalyser_run_settings <- function(settings) {
  interactive_run <- isTRUE(settings$advanced$interactive_setup)
  result <- .sensanalyser_run_config(sensanalyser_settings_to_config(settings))

  # An interactive run resolved the data files and variables through console
  # prompts; write those choices back into settings.yaml so the project is now
  # fully specified and never prompts again.
  if (interactive_run && !is.null(result$main) && !is.null(result$main$selections)) {
    .sens_write_choices(
      project_root = settings$project_root,
      selections   = result$main$selections
    )
  }
  invisible(result)
}

#' Run the main pipeline followed by any product subsets
#'
#' Shared by the settings.yaml and the legacy project_config.R paths, so both
#' produce identical outputs.
#'
#' @param final_config Fully resolved engine config, optionally carrying a
#'   `product_subsets` element.
#' @keywords internal
.sensanalyser_run_config <- function(final_config) {
  subsets <- final_config$product_subsets
  final_config$product_subsets <- NULL

  main_state <- run_sensanalyser_pipeline(final_config)

  # ── PRODUCT SUBSET ANALYSES ──────────────────────────────────────────────
  # Each named entry reruns the full pipeline on a filtered dataset and writes
  # its outputs to a dedicated subfolder, so subset results never overwrite
  # the main analysis outputs.
  if (!is.null(subsets) && length(subsets) > 0) {

    # A settings.yaml run already carries every selection, so it needs no
    # saved YAML to reproduce them for the subsets.
    saved_cfg_path <- final_config$paths$analysis_config
    settings_driven <- isTRUE(final_config$settings_driven)
    if (!settings_driven && (is.null(saved_cfg_path) || !file.exists(saved_cfg_path))) {
      cli::cli_alert_warning(
        "Product subsets skipped: no analysis_config.yaml found at {saved_cfg_path}.",
        "Run the main analysis first so variable selections are saved."
      )
    } else {
      for (subset_name in names(subsets)) {
        subset_def <- subsets[[subset_name]]

        cli::cli_rule()
        cli::cli_h1(sprintf("Sensanalyser — Product Subset: %s", subset_name))

        subset_config <- final_config

        # Non-interactive: no prompts, no YAML write.
        subset_config$toggles$interactive_setup <- FALSE
        if (!settings_driven) {
          # Setting dependent_variables to NULL triggers the YAML-load block in
          # core_engine so this subset uses the same variable selections as the
          # main run rather than re-running auto-detection.
          subset_config$analysis$dependent_variables <- NULL
        }

        # Redirect all outputs to a dedicated subfolder.
        subset_config$paths$table_root       <- file.path(final_config$paths$table_root,       subset_name)
        subset_config$paths$figure_root      <- file.path(final_config$paths$figure_root,      subset_name)
        subset_config$paths$diagnostics_root <- file.path(final_config$paths$diagnostics_root, subset_name)
        subset_config$paths$logs_root        <- file.path(final_config$paths$logs_root,        subset_name)

        # Attach the filter definition so core_engine applies it after data load.
        subset_config$product_subset <- c(subset_def, list(label = subset_name))

        run_sensanalyser_pipeline(subset_config)
      }
    }
  }

  invisible(list(main = main_state))
}
