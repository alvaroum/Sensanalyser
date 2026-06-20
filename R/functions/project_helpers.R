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
  
  # Copy templates if they exist
  template_dir <- here::here("templates")
  if (dir.exists(template_dir)) {
    # We want to copy contents to their respective places
    if (file.exists(file.path(template_dir, "project_config.R"))) {
      file.copy(file.path(template_dir, "project_config.R"), file.path(project_dir, "project_config.R"))
    }
    
    if (dir.exists(file.path(template_dir, "data/dictionary"))) {
      dict_files <- list.files(file.path(template_dir, "data/dictionary"), full.names = TRUE)
      file.copy(dict_files, file.path(project_dir, "data/dictionary"))
    }
    
    if (dir.exists(file.path(template_dir, "reports"))) {
      report_files <- list.files(file.path(template_dir, "reports"), full.names = TRUE)
      file.copy(report_files, file.path(project_dir, "reports"))
    }
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
    "Place your raw data files inside {.path {file.path(project_dir, 'data/raw')}}",
    "Open {.path {file.path(project_dir, 'project_config.R')}} to configure your analysis.",
    "Add {.val {project_dir}} to the {.var active_projects} list in {.path master_mission_control.R}."
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
#' @export
sensanalyser_run_project <- function(project_dir, global_toggles = list()) {
  project_root <- sensanalyser_resolve_project_root(project_dir)
  sensanalyser_validate_project(project_root)
  
  config_file <- file.path(project_root, "project_config.R")
  if (!file.exists(config_file)) {
    cli::cli_abort("No project_config.R found in {.path {project_root}}.")
  }
  
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
    derived_attribute_options = list(digits = NULL),
    report_options = list(output_formats = c("html", "docx"))
  )
  
  # If the project explicitly overrides any toggles, apply them
  if (!is.null(project_config$toggles)) {
    for (nm in names(project_config$toggles)) {
      final_config$toggles[[nm]] <- project_config$toggles[[nm]]
    }
  }
  
  # Tell core engine where the root is
  final_config$project_root <- project_root
  
  run_sensanalyser_pipeline(final_config)
}
