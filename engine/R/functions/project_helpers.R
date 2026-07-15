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

#' Put a settings list into a fresh interactive-setup state and write it out
#'
#' Sets the data/variable fields to `ask` and turns `interactive_setup` on, so
#' the next run prompts for the data files and variables and writes the answers
#' back into settings.yaml. Shared by [sensanalyser_create_project()] and
#' [sensanalyser_reset_project()] so a brand-new project and a reset project
#' behave identically on their first run.
#'
#' @param settings_file Destination settings.yaml path.
#' @param project_name Value for `project.name`.
#' @param settings Settings list to modify and write.
#' @param note One or more `#`-prefixed comment lines describing why the file
#'   is in this state (e.g. "created" vs "reset").
#' @keywords internal
.sens_write_fresh_settings <- function(settings_file, project_name, settings, note) {
  settings$project$name          <- project_name
  settings$data$files            <- SENS_ASK
  settings$variables$attributes  <- SENS_ASK
  settings$variables$product     <- SENS_ASK
  settings$variables$panelist    <- SENS_ASK
  settings$variables$extra_factors <- list()
  settings$advanced$interactive_setup <- TRUE

  header <- c(
    "# ==========================================================================",
    "# SENSANALYSER PROJECT SETTINGS",
    "# ==========================================================================",
    "#",
    note,
    "# Your answers are then written back here. See templates/settings.yaml",
    "# for every documented option.",
    "# --------------------------------------------------------------------------",
    ""
  )
  writeLines(c(header, strsplit(.sens_as_yaml(settings), "\n", fixed = TRUE)[[1]]), settings_file)
  invisible(settings_file)
}

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
  template_dir <- here::here("engine", "templates")
  if (file.exists(file.path(template_dir, "settings.yaml"))) {
    settings_dest <- file.path(project_dir, "settings.yaml")
    file.copy(file.path(template_dir, "settings.yaml"), settings_dest)
    # Start the project in interactive first-run state: the first run asks for
    # the data files and variables, then writes the choices back here. Without
    # this the template's `auto` defaults would silently auto-detect and never
    # prompt.
    settings <- tryCatch(yaml::read_yaml(settings_dest), error = function(e) list())
    if (is.null(settings)) settings <- list()
    .sens_write_fresh_settings(
      settings_dest, basename(project_dir), settings,
      note = c(
        paste0("# New project created on ", format(Sys.Date()), "."),
        "# The next run will ask for the data files and variables."
      )
    )
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

#' Reset a project to a clean, start-from-scratch state
#'
#' @description
#' Wipes everything the pipeline generated (all of `outputs/`, the cleaned
#' CSVs in `data/clean/`, the run record and rendered reports) and rewrites
#' `settings.yaml` so the next run behaves like a fresh project: it prompts
#' you to pick the raw data files and the variables again. Your raw data in
#' `data/raw/` is never touched.
#'
#' By default the analysis settings you tuned - model, outliers, figures,
#' display labels, derived attributes and subsets - are kept. Pass
#' `full = TRUE` for a completely blank project (template defaults only).
#'
#' @param project_dir Path to the project folder.
#' @param full Reset every setting to the template defaults, not just the
#'   data and variable selections?
#' @param ask Confirm before deleting? Defaults to TRUE in an interactive
#'   session. Set FALSE to reset non-interactively (e.g. in a script).
#' @return The project path, invisibly.
#' @export
sensanalyser_reset_project <- function(project_dir, full = FALSE, ask = interactive()) {
  project_root <- sensanalyser_resolve_project_root(project_dir)

  cli::cli_h2("Reset project {.path {project_dir}}")
  cli::cli_text(paste(
    "This deletes all outputs, cleaned data and rendered reports, and makes",
    "the next run ask again for the data files and variables.",
    if (full) "Every setting is reset to the template defaults."
    else "Your model, labels and other settings are kept.",
    "Raw data in {.path data/raw} is not touched."
  ))

  if (isTRUE(ask)) {
    ok <- utils::askYesNo("Reset this project now?", default = FALSE)
    if (!isTRUE(ok)) {
      cli::cli_alert_info("Reset cancelled.")
      return(invisible(project_root))
    }
  }

  # 1. Delete generated artifacts (reuse the pipeline's own cleaner). Build the
  #    minimal config it needs from the current settings, if any.
  settings_file <- sensanalyser_settings_path(project_root)
  clear_config <- list(
    project_root = project_root,
    paths = list(
      analysis_config  = file.path(project_root, "data/dictionary/state/resolved_run.yaml"),
      table_root       = file.path(project_root, "outputs/general/tables"),
      figure_root      = file.path(project_root, "outputs/general/figures"),
      diagnostics_root = file.path(project_root, "outputs/general/diagnostics"),
      logs_root        = file.path(project_root, "outputs/general/logs"),
      report_template  = file.path(project_root, "reports/sensanalyser_results_report.qmd")
    )
  )
  .sensanalyser_clear_outputs(clear_config)

  # Also clear the materialised state so nothing stale survives the reset.
  state_dir <- file.path(project_root, "data", "dictionary", "state")
  if (dir.exists(state_dir)) {
    unlink(list.files(state_dir, full.names = TRUE), recursive = TRUE)
  }

  # 2. Rewrite settings.yaml so the next run is a fresh interactive setup.
  if (full || !file.exists(settings_file)) {
    template <- here::here("engine", "templates", "settings.yaml")
    if (file.exists(template)) file.copy(template, settings_file, overwrite = TRUE)
    settings <- tryCatch(yaml::read_yaml(settings_file), error = function(e) list())
    if (is.null(settings)) settings <- list()
  } else {
    settings <- tryCatch(yaml::read_yaml(settings_file), error = function(e) list())
    if (is.null(settings)) settings <- list()
  }

  .sens_write_fresh_settings(
    settings_file, basename(project_root), settings,
    note = c(
      paste0("# Reset to a clean state on ", format(Sys.Date()), "."),
      "# The next run will ask for the data files and variables again."
    )
  )

  cli::cli_alert_success("Project reset. Run {.code run_project('{project_dir}')} to set it up again.")
  invisible(project_root)
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
  # A first (interactive) run walks the user through data selection, column
  # removal, model choice, variables and subset/scope, writes everything back
  # into settings.yaml (+ a data_summary.yaml), then runs the pipeline from the
  # completed settings. Later runs are fully specified and just run.
  if (isTRUE(settings$advanced$interactive_setup)) {
    return(invisible(.sensanalyser_interactive_setup(settings)))
  }
  invisible(.sensanalyser_run_config(sensanalyser_settings_to_config(settings)))
}

#' Guided first-run setup: prompt for everything, save it, then run.
#'
#' Walks a new project through: pick raw data (dialog opens in data/raw) ->
#' remove unwanted columns -> choose the statistical model -> choose variables
#' -> choose scope and define subsets. Writes a `data_summary.yaml` and a
#' fully-commented `settings.yaml`, then runs the pipeline non-interactively
#' from those settings (general and/or subsets). Later runs skip all of this.
#'
#' @param settings A settings list from [sensanalyser_load_settings()] with
#'   `advanced$interactive_setup == TRUE`.
#' @keywords internal
.sensanalyser_interactive_setup <- function(settings) {
  root <- settings$project_root
  cli::cli_h1("Sensanalyser - guided project setup")

  base_cfg <- sensanalyser_settings_to_config(settings)

  # 1. Pick + load the raw data (picker opens in projects/<p>/data/raw).
  start_dir <- file.path(root, "data", "raw")
  paths <- .resolve_data_path(NULL, multiple = TRUE, start_dir = start_dir)
  if (is.null(paths) || !nzchar(paths[[1]])) {
    cli::cli_abort("No data file selected - setup cancelled.")
  }
  data <- load_sensanalyser_data(path = paths, interactive_setup = FALSE,
                                 config = base_cfg)

  # 2. Remove unwanted columns completely.
  remove_cols <- .interactive_remove_columns(data)
  if (length(remove_cols) > 0) {
    data <- data[, setdiff(names(data), remove_cols), drop = FALSE]
  }

  # 3. Choose the statistical model.
  presets <- tryCatch(yaml::read_yaml(base_cfg$paths$model_presets),
                      error = function(e) NULL)
  model_type <- if (!is.null(presets)) .interactive_select_model(presets) else settings$model$type

  # 4. Choose variables (attributes / product / panelist / design columns),
  #    reusing the existing model-aware selector.
  sel_cfg <- base_cfg
  sel_cfg$toggles$interactive_setup     <- TRUE
  sel_cfg$analysis$model_type           <- model_type
  sel_cfg$analysis$dependent_variables  <- NULL
  sel_cfg$analysis$factors              <- NULL
  sel_cfg$analysis$subject_id           <- NULL
  selections  <- select_analysis_variables(data, sel_cfg)
  product_col <- (selections$factors %||% character(0))[1]
  attributes  <- selections$dependent_variables

  # 5. Reference file with the product and attribute lists.
  .write_data_summary(root, data, product_col, attributes)

  # 6. Scope + subset definitions.
  scope_res <- if (!is.null(product_col) && product_col %in% names(data)) {
    .interactive_select_scope_and_subsets(data, product_col)
  } else {
    list(scope = "general", subsets = list())
  }

  # 7. Save everything into a commented settings.yaml (turns interactivity off).
  .sens_write_choices(
    project_root = root,
    selections   = selections,
    data_files   = paths,
    model_type   = model_type,
    exclude      = remove_cols,
    scope        = scope_res$scope,
    subsets      = scope_res$subsets
  )

  # 8. Reload the now-complete settings and run non-interactively.
  cli::cli_h1("Running the analysis with your choices")
  settings2 <- sensanalyser_load_settings(root)
  invisible(.sensanalyser_run_config(sensanalyser_settings_to_config(settings2)))
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

  # Which analyses to run. Absent (legacy project_config.R path) -> "both".
  scope <- final_config$analysis_scope %||% "both"
  run_general <- scope %in% c("general", "both")
  run_subsets <- scope %in% c("subsets", "both")

  # outputs/subsets/<name>/... sits beside outputs/general/... The general
  # roots look like <root>/outputs/general/tables, so the shared outputs base
  # is two levels up and each leaf ("tables", "figures", ...) is the basename.
  outputs_base <- dirname(dirname(final_config$paths$table_root))
  subset_root  <- function(path, name) {
    file.path(outputs_base, "subsets", name, basename(path))
  }

  main_state <- if (run_general) run_sensanalyser_pipeline(final_config) else NULL

  # ── PRODUCT SUBSET ANALYSES ──────────────────────────────────────────────
  # Each named entry reruns the full pipeline on a filtered dataset and writes
  # its outputs to outputs/subsets/<name>/, so subset results never overwrite
  # the general analysis outputs.
  if (run_subsets && !is.null(subsets) && length(subsets) > 0) {

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

        # Redirect all outputs to outputs/subsets/<name>/...
        subset_config$paths$table_root       <- subset_root(final_config$paths$table_root,       subset_name)
        subset_config$paths$figure_root      <- subset_root(final_config$paths$figure_root,      subset_name)
        subset_config$paths$diagnostics_root <- subset_root(final_config$paths$diagnostics_root, subset_name)
        subset_config$paths$logs_root        <- subset_root(final_config$paths$logs_root,        subset_name)

        # Attach the filter definition so core_engine applies it after data load.
        subset_config$product_subset <- c(subset_def, list(label = subset_name))

        # A single bad subset (e.g. too few products for clustering) must not
        # abort the general analysis or the other subsets.
        tryCatch(
          run_sensanalyser_pipeline(subset_config),
          error = function(e) {
            cli::cli_alert_danger(
              "Subset '{subset_name}' failed and was skipped: {conditionMessage(e)}"
            )
          }
        )
      }
    }
  }

  invisible(list(main = main_state))
}
