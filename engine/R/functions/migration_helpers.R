#' Migrate a legacy project to the consolidated settings.yaml
#'
#' @description
#' Phase C of SETTINGS_CONSOLIDATION_PLAN.md. Reads everything a legacy
#' project scattered across `project_config.R`, the auto-written
#' `analysis_config.yaml`, and the `data/dictionary/*.yaml` files, and writes
#' a single `settings.yaml`. Nothing is deleted: superseded files are renamed
#' to `*.migrated`.
#'
#' @keywords internal

# ---------------------------------------------------------------------------
# READ THE OLD PIECES
# ---------------------------------------------------------------------------

#' Source a legacy project_config.R without running anything else
#' @keywords internal
.migrate_read_project_config <- function(project_root) {
  path <- file.path(project_root, "project_config.R")
  if (!file.exists(path)) return(list())
  value <- tryCatch(source(path, local = new.env())$value, error = function(e) NULL)
  if (is.null(value)) {
    cli::cli_alert_warning("Could not read {.path project_config.R}; migrating without it.")
    return(list())
  }
  value
}

#' Read the pipeline's saved analysis_config.yaml, ignoring the template
#' @keywords internal
.migrate_read_saved_config <- function(project_root) {
  path <- file.path(project_root, "data", "dictionary", "analysis_config.yaml")
  if (!file.exists(path)) return(list())
  saved <- tryCatch(yaml::read_yaml(path), error = function(e) list())

  placeholders <- c("attribute_1", "attribute_2", "attribute_3")
  dvs <- saved$analysis$dependent_variables
  if (length(dvs) > 0 && all(unlist(dvs) %in% placeholders)) {
    cli::cli_alert_info("Ignoring {.path analysis_config.yaml}: it is still the distributed template.")
    return(list())
  }
  saved
}

#' Make a data path relative to the project, so the folder stays portable
#'
#' The old `analysis_config.yaml` stored absolute paths. A path inside the
#' project becomes relative to it; a path elsewhere is matched by file name
#' against `data/raw` (projects that were moved or copied); anything else is
#' kept verbatim.
#'
#' @keywords internal
.migrate_relative_path <- function(paths, project_root) {
  root <- normalizePath(project_root, mustWork = FALSE)
  vapply(as.character(paths), function(p) {
    full <- normalizePath(p, mustWork = FALSE)
    if (startsWith(full, paste0(root, .Platform$file.sep))) {
      return(substring(full, nchar(root) + 2L))
    }
    in_raw <- file.path(root, "data", "raw", basename(p))
    if (file.exists(in_raw)) {
      return(file.path("data", "raw", basename(p)))
    }
    p
  }, character(1), USE.NAMES = FALSE)
}

# ---------------------------------------------------------------------------
# BUILD THE NEW SETTINGS
# ---------------------------------------------------------------------------

#' Turn the legacy pieces into a settings list
#'
#' Values are taken from, in order of precedence: the explicit
#' `project_config.R`, then the selections the pipeline saved in
#' `analysis_config.yaml` (what the next legacy run would actually have used),
#' then the Sensanalyser defaults. Only values that differ from the defaults
#' are written out, so the resulting file stays short and readable.
#'
#' @keywords internal
.migrate_build_settings <- function(project_root, project_config, saved) {
  defaults <- sensanalyser_default_settings()

  # Reproduce the engine's own precedence rule (.phase2_data_import): when
  # project_config.R leaves dependent_variables unset, the saved
  # analysis_config.yaml replaces the whole analysis block - its factors and
  # subject_id included. Otherwise project_config.R is authoritative.
  pc_analysis <- .sens_or(project_config$analysis, list())
  pc_dvs <- pc_analysis$dependent_variables
  saved_wins <- (is.null(pc_dvs) || identical(pc_dvs, "auto")) &&
    length(.sens_or(saved$analysis, list())) > 0

  analysis <- if (saved_wins) {
    saved$analysis
  } else {
    utils::modifyList(.sens_or(saved$analysis, list()), Filter(Negate(is.null), pc_analysis))
  }
  # The saved toggles record the effective switches of the last real run
  # (global_toggles merged with the project's overrides), which is exactly
  # what we want to reproduce.
  toggles <- utils::modifyList(
    .sens_or(saved$toggles, list()),
    Filter(Negate(is.null), .sens_or(project_config$toggles, list()))
  )
  fig <- .sens_or(project_config$fig_options, list())
  tbl <- .sens_or(project_config$table_options, list())
  der <- .sens_or(project_config$derived_attribute_options, list())

  pick <- function(value, default) if (is.null(value)) default else value
  as_list <- function(x) if (is.null(x)) list() else as.list(unlist(x, use.names = FALSE))

  # ── data files ───────────────────────────────────────────────────────────
  files <- .sens_or(project_config$paths$raw_data, saved$meta$data_file)
  files <- if (is.null(files) || identical(files, "not set")) {
    SENS_AUTO
  } else {
    as.list(.migrate_relative_path(unlist(files), project_root))
  }

  # ── variables ────────────────────────────────────────────────────────────
  dvs <- unlist(analysis$dependent_variables)
  attributes <- if (is.null(dvs) || identical(dvs, "auto") || length(dvs) == 0) {
    SENS_AUTO
  } else {
    if (length(dvs) < 2) {
      cli::cli_alert_warning(paste0(
        "The saved selections analyse a single attribute ({.field ", dvs[[1]],
        "}). If that looks wrong, set {.field variables.attributes: auto} in settings.yaml."
      ))
    }
    as.list(dvs)
  }
  panelist <- pick(analysis$subject_id, defaults$variables$panelist)
  factors <- unlist(.sens_or(analysis$factors, "product"))

  # A panelist column listed among the fixed factors makes the first factor -
  # the one PCA, HCPC and the descriptives group by - the assessor rather than
  # the product. Old interactive runs sometimes recorded this.
  if (!is.null(panelist) && panelist %in% factors && length(factors) > 1) {
    cli::cli_alert_warning(paste0(
      "The saved selections list the panelist column {.field ", panelist,
      "} as a fixed factor. Removing it from {.field variables.extra_factors}; ",
      "check the result before running."
    ))
    factors <- setdiff(factors, panelist)
  }

  product <- factors[[1]]
  extra_factors <- if (length(factors) > 1) as.list(factors[-1]) else list()

  # ── hcpc clusters ────────────────────────────────────────────────────────
  k <- analysis$hcpc_n_clusters
  clusters <- if (is.null(k) || identical(k, "auto") || identical(as.numeric(k), -1)) {
    SENS_AUTO
  } else if (identical(as.numeric(k), 0)) {
    "click"
  } else {
    as.integer(k)
  }

  # ── labels + derived attributes from the dictionary YAMLs ────────────────
  dict_dir <- file.path(project_root, "data", "dictionary")
  dict_path <- file.path(dict_dir, "renaming_dictionary.yaml")
  dict <- if (file.exists(dict_path)) {
    .sens_or(tryCatch(yaml::read_yaml(dict_path), error = function(e) NULL), list())
  } else {
    list()
  }
  derived_path <- file.path(dict_dir, "derived_attributes.yaml")
  derived_defs <- if (file.exists(derived_path)) {
    cfg <- tryCatch(yaml::read_yaml(derived_path), error = function(e) NULL)
    .sens_or(.sens_or(cfg, list())$derived_attributes, list())
  } else {
    list()
  }

  settings <- list(
    project = list(name = basename(project_root)),
    data = list(files = files),
    variables = list(
      attributes    = attributes,
      exclude       = list(),
      product       = product,
      panelist      = panelist,
      extra_factors = extra_factors
    ),
    model = list(
      type              = pick(analysis$model_type, defaults$model$type),
      fixed_effects     = analysis$model_fixed_effects,
      random_effects    = as_list(analysis$random_effects),
      repeated_measures = as_list(analysis$repeated_measures_factors),
      alpha             = pick(analysis$alpha, defaults$model$alpha),
      run_anova         = isTRUE(pick(toggles$run_anova_models, defaults$model$run_anova)),
      run_mixed         = isTRUE(pick(toggles$run_mixed_models, defaults$model$run_mixed)),
      posthoc = list(
        run         = isTRUE(pick(toggles$run_posthoc, defaults$model$posthoc$run)),
        method      = pick(analysis$posthoc_method, defaults$model$posthoc$method),
        focal_terms = analysis$posthoc_focal_terms
      )
    ),
    outliers = list(
      detect           = isTRUE(pick(toggles$run_outlier_detection, defaults$outliers$detect)),
      apply_policy     = isTRUE(pick(toggles$apply_outlier_policy, defaults$outliers$apply_policy)),
      policy           = pick(analysis$outlier_policy, defaults$outliers$policy),
      action           = pick(analysis$outlier_removal_action, defaults$outliers$action),
      grouping_factors = analysis$outlier_grouping_factors
    ),
    multivariate = list(
      pca  = list(run = isTRUE(pick(toggles$run_pca, defaults$multivariate$pca$run)),
                  significant_only = isTRUE(pick(analysis$pca_significant_only,
                                                 defaults$multivariate$pca$significant_only))),
      hcpc = list(run = isTRUE(pick(toggles$run_hcpc, defaults$multivariate$hcpc$run)),
                  clusters = clusters),
      mfa  = list(run = isTRUE(pick(toggles$run_mfa, defaults$multivariate$mfa$run)))
    ),
    outputs = list(
      descriptives   = isTRUE(pick(toggles$run_descriptives, defaults$outputs$descriptives)),
      tables         = isTRUE(pick(toggles$create_tables, defaults$outputs$tables)),
      figures = list(
        # A legacy run wrote PCA/HCPC/MFA figures regardless of create_figures,
        # which only ever gated the spider plots.
        spider = isTRUE(pick(toggles$create_figures, defaults$outputs$figures$spider)),
        pca    = TRUE,
        hcpc   = TRUE,
        mfa    = TRUE
      ),
      report         = isTRUE(pick(toggles$render_quarto_report, defaults$outputs$report)),
      report_formats = defaults$outputs$report_formats,
      table = list(
        digits  = pick(tbl$digits, defaults$outputs$table$digits),
        mean_se = isTRUE(pick(tbl$include_mean_se, defaults$outputs$table$mean_se)),
        letters = isTRUE(pick(tbl$include_letters, defaults$outputs$table$letters))
      ),
      figure = list(
        width   = pick(fig$width, defaults$outputs$figure$width),
        height  = pick(fig$height, defaults$outputs$figure$height),
        dpi     = pick(fig$dpi, defaults$outputs$figure$dpi),
        palette = pick(fig$palette, defaults$outputs$figure$palette)
      ),
      spider = list(
        top_n_attributes = fig$top_n_attributes,
        significant_only = isTRUE(pick(fig$spider_significant_only,
                                       defaults$outputs$spider$significant_only)),
        attributes       = fig$spider_outcomes,
        comparisons      = .sens_or(fig$spider_comparisons, list())
      )
    ),
    derived = list(
      enabled      = isTRUE(pick(toggles$create_derived_attributes, defaults$derived$enabled)),
      digits       = der$digits,
      output_label = der$output_label
    ),
    labels = list(
      aliases    = .sens_or(dict$aliases, list()),
      variables  = .sens_or(dict$variables, list()),
      levels     = .sens_or(dict$levels, list()),
      attributes = .sens_or(dict$outcomes, list())
    ),
    derived_attributes = derived_defs,
    subsets = .sens_or(project_config$product_subsets, list()),
    advanced = list(
      # The selections above are now explicit, so the console prompts that
      # interactive_setup triggered are no longer needed.
      interactive_setup            = FALSE,
      discover_variables           = FALSE,
      descriptive_grouping_factors = analysis$descriptive_grouping_factors
    )
  )

  settings
}

# ---------------------------------------------------------------------------
# WRITE
# ---------------------------------------------------------------------------

#' Serialise a settings list to a commented settings.yaml
#' @keywords internal
.migrate_write_settings <- function(settings, path, sources) {
  # yaml::write_yaml drops comments, so the guidance goes in a header.
  header <- c(
    "# ==========================================================================",
    "# SENSANALYSER PROJECT SETTINGS",
    "# ==========================================================================",
    "#",
    "# Migrated automatically on " ,
    "#   from: " ,
    "#",
    "# This is now the only file you edit for this project. Every option is",
    "# documented in templates/settings.yaml. Check what will run with:",
    "#   settings_summary(\"<this project folder>\")",
    "# --------------------------------------------------------------------------",
    ""
  )
  header[5] <- paste0("# Migrated automatically on ", format(Sys.Date()))
  header[6] <- paste0("#   from: ", paste(sources, collapse = ", "))

  # Emit `true` / `false` rather than yaml's default `yes` / `no`, matching
  # the template the user will compare against.
  body <- yaml::as.yaml(
    settings, indent = 2,
    handlers = list(logical = function(x) {
      result <- ifelse(x, "true", "false")
      class(result) <- "verbatim"
      result
    })
  )
  writeLines(c(header, strsplit(body, "\n", fixed = TRUE)[[1]]), path)
  invisible(path)
}

#' Retire a superseded file by renaming it to *.migrated
#' @keywords internal
.migrate_retire <- function(path) {
  if (!file.exists(path)) return(FALSE)
  file.rename(path, paste0(path, ".migrated"))
  TRUE
}

#' Convert a legacy project to a consolidated settings.yaml
#'
#' Reads `project_config.R`, the pipeline's saved `analysis_config.yaml` and
#' the `data/dictionary/*.yaml` files, and writes one `settings.yaml`
#' reproducing the project's current behaviour. Superseded files are renamed
#' to `*.migrated` rather than deleted, so nothing is lost.
#'
#' Interactive setup is switched off: the variable selections that used to
#' come from console prompts (and were remembered in `analysis_config.yaml`)
#' are now written explicitly into `settings.yaml`.
#'
#' @param project_dir Path to the project folder.
#' @param overwrite Overwrite an existing `settings.yaml`?
#' @return The path to the written `settings.yaml`, invisibly.
#' @export
sensanalyser_migrate_project <- function(project_dir, overwrite = FALSE) {
  project_root <- sensanalyser_resolve_project_root(project_dir)
  target <- sensanalyser_settings_path(project_root)

  cli::cli_h2("Migrating {.path {project_dir}}")

  if (file.exists(target) && !overwrite) {
    cli::cli_abort(c(
      "{.path settings.yaml} already exists in {.path {project_dir}}.",
      "i" = "Pass {.code overwrite = TRUE} to replace it."
    ))
  }

  project_config <- .migrate_read_project_config(project_root)
  saved <- .migrate_read_saved_config(project_root)

  sources <- character(0)
  if (length(project_config) > 0) sources <- c(sources, "project_config.R")
  if (length(saved) > 0) sources <- c(sources, "data/dictionary/analysis_config.yaml")
  dict_dir <- file.path(project_root, "data", "dictionary")
  for (f in c("renaming_dictionary.yaml", "derived_attributes.yaml")) {
    if (file.exists(file.path(dict_dir, f))) sources <- c(sources, file.path("data/dictionary", f))
  }
  if (length(sources) == 0) {
    cli::cli_abort("Nothing to migrate in {.path {project_dir}}: no legacy config files found.")
  }

  settings <- .migrate_build_settings(project_root, project_config, saved)

  # Validate before writing, so a broken migration never lands on disk.
  check <- settings
  check$project_root <- project_root
  sensanalyser_validate_settings(.sens_normalise_figures(check))

  .migrate_write_settings(settings, target, sources)
  cli::cli_alert_success("Wrote {.path {target}}")

  retired <- c(
    file.path(project_root, "project_config.R"),
    file.path(dict_dir, "analysis_config.yaml"),
    file.path(dict_dir, "renaming_dictionary.yaml"),
    file.path(dict_dir, "derived_attributes.yaml")
  )
  retired <- retired[vapply(retired, .migrate_retire, logical(1))]
  if (length(retired) > 0) {
    cli::cli_alert_info("Renamed to {.field *.migrated} (nothing deleted): {.path {basename(retired)}}")
  }

  # model_presets.yaml is an engine asset again; a project copy would silently
  # override templates/. Retire an untouched copy, keep a customised one.
  presets <- file.path(dict_dir, "model_presets.yaml")
  template_presets <- here::here("engine", "templates", "data", "dictionary", "model_presets.yaml")
  if (file.exists(presets) && file.exists(template_presets)) {
    same <- identical(tools::md5sum(presets)[[1]], tools::md5sum(template_presets)[[1]])
    if (same) {
      .migrate_retire(presets)
      cli::cli_alert_info("Retired the unmodified {.path model_presets.yaml} (now read from templates/).")
    } else {
      cli::cli_alert_warning("Keeping your customised {.path model_presets.yaml}; it overrides the engine's.")
    }
  }

  if (isTRUE(project_config$toggles$interactive_setup)) {
    cli::cli_alert_info(paste(
      "This project used {.field interactive_setup}. The selections it asked for",
      "are now written into settings.yaml, so it will no longer prompt."
    ))
  }

  cli::cli_h3("Check the result")
  cli::cli_text("Run {.code settings_summary('{project_dir}')} to see what the next run will do.")

  invisible(target)
}
