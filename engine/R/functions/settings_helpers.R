#' Consolidated Project Settings for Sensanalyser
#'
#' @description
#' Phase A of SETTINGS_CONSOLIDATION_PLAN.md. Everything a user configures
#' for a project lives in a single `settings.yaml` at the project root.
#' This file defines the schema and its defaults, loads and validates a
#' project's settings, prints the effective configuration (highlighting what
#' deviates from the defaults), and adapts the settings onto the `config`
#' structure `run_sensanalyser_pipeline()` already consumes.
#'
#' No engine module reads `settings.yaml` directly: `settings_to_config()`
#' is the only translation point, so the pipeline is unchanged.
#'
#' @keywords internal

# Values a user may write for a "let Sensanalyser decide" choice.
SENS_AUTO <- "auto"
# Sentinel asking Sensanalyser to prompt for this choice on the next
# interactive run (used by reset_project() to reproduce a fresh setup).
SENS_ASK <- "ask"

.sens_or <- function(x, default) if (is.null(x)) default else x

# ---------------------------------------------------------------------------
# SCHEMA + DEFAULTS
# ---------------------------------------------------------------------------

#' Default project settings
#'
#' @description
#' The complete settings schema with its default values. Any key a user
#' omits from `settings.yaml` falls back to the value here, and
#' [sensanalyser_settings_summary()] compares against it to show what was
#' customised. This list is also the source of truth for validation: keys
#' not present here (outside the free-form sections) are rejected.
#'
#' @return Nested list of defaults.
#' @export
sensanalyser_default_settings <- function() {
  list(
    project = list(
      name = NULL                      # defaults to the folder name
    ),

    data = list(
      files = SENS_AUTO                # auto = every data file in data/raw
    ),

    variables = list(
      attributes    = SENS_AUTO,       # auto = all numeric non-design columns
      exclude       = NULL,            # attributes to leave out of everything
      product       = "product",
      panelist      = "user",
      extra_factors = NULL
    ),

    model = list(
      type              = "linear_mixed_model",
      fixed_effects     = NULL,        # NULL = derived from the preset/factors
      random_effects    = NULL,
      repeated_measures = NULL,
      alpha             = 0.05,
      run_anova         = FALSE,
      run_mixed         = TRUE,
      posthoc = list(
        run         = FALSE,
        method      = "tukey",
        focal_terms = NULL
      )
    ),

    outliers = list(
      detect           = TRUE,
      apply_policy     = TRUE,
      policy           = "remove_extreme",
      action           = "set_na",
      grouping_factors = NULL
    ),

    multivariate = list(
      pca  = list(run = TRUE,  significant_only = FALSE),
      hcpc = list(run = TRUE,  clusters = SENS_AUTO),   # auto | click | integer
      mfa  = list(run = FALSE)
    ),

    outputs = list(
      descriptives   = TRUE,
      tables         = TRUE,
      # Which figures to save. `figures: true` / `false` switches them all;
      # a map switches them per analysis. The analyses still run (their
      # tables are written) - only the image files are affected.
      figures = list(
        spider = TRUE,
        pca    = TRUE,
        hcpc   = TRUE,
        mfa    = TRUE
      ),
      report         = FALSE,
      report_formats = c("html", "docx"),
      table  = list(digits = 1, mean_se = TRUE, letters = TRUE),
      figure = list(width = 9, height = 6, dpi = 300, palette = "Set1"),
      spider = list(
        top_n_attributes = NULL,
        significant_only = TRUE,
        attributes       = NULL,
        label_size       = NULL,       # NULL = auto; relative size of axis labels
        legend           = "auto",     # "auto" (hide for single group) / TRUE / FALSE
        colors           = list(),     # free-form: product display name -> colour
        scale_min        = 0,          # radial axis minimum
        scale_max        = NULL,       # NULL = auto-fit per chart; or a fixed number
        axis_labels      = "value",    # "value" / "percent" / "none"
        axis_unit        = "",         # suffix on value labels, e.g. "%" or " cm"
        axis_steps       = 4,          # number of rings / axis segments
        comparisons      = list()      # free-form: name -> product vector or {title, products}
      )
    ),

    derived = list(
      enabled      = FALSE,
      digits       = NULL,
      output_label = NULL
    ),

    # Display labels (absorbs data/dictionary/renaming_dictionary.yaml)
    labels = list(
      aliases    = list(),             # factor -> raw name -> canonical name
      variables  = list(),             # column -> heading
      levels     = list(),             # factor -> level -> label
      attributes = list()              # attribute -> label
    ),

    # Derived attribute definitions (absorbs derived_attributes.yaml)
    derived_attributes = list(),

    subsets = list(),                  # free-form: name -> include/exclude

    advanced = list(
      interactive_setup            = FALSE,
      discover_variables           = FALSE,
      descriptive_grouping_factors = NULL
    )
  )
}

# Sections whose keys are user-invented (data, not schema) and must not be
# key-checked: subset names, spider comparison names, column and attribute
# names in the label maps, derived attribute names.
.sens_freeform_paths <- function() {
  c("subsets", "outputs.spider.comparisons", "outputs.spider.colors",
    "labels.aliases", "labels.variables", "labels.levels", "labels.attributes",
    "derived_attributes")
}

# Names of the figures that can be switched on or off individually.
.sens_figure_kinds <- function() c("spider", "pca", "hcpc", "mfa")

.sens_enums <- function() {
  list(
    "model.type" = c("one_way_anova", "two_way_anova", "three_way_anova",
                     "one_way_repeated", "two_way_repeated", "two_way_mixed",
                     "three_way_repeated", "linear_mixed_model"),
    "model.posthoc.method" = c("tukey", "bonferroni", "lsd"),
    "outliers.policy" = c("keep_all", "remove_extreme", "remove_all"),
    "outliers.action" = c("set_na", "drop_row"),
    "outputs.spider.axis_labels" = c("value", "percent", "none")
  )
}

# ---------------------------------------------------------------------------
# MERGE + VALIDATE
# ---------------------------------------------------------------------------

#' Deep-merge user settings over the defaults
#'
#' Unlike [utils::modifyList()], a free-form section in `user` replaces the
#' default wholesale rather than merging key by key (subset names are data,
#' not schema). A `NULL` value means "keep the default".
#'
#' @keywords internal
.sens_merge_settings <- function(default, user, prefix = character(0)) {
  if (is.null(user)) return(default)
  for (key in names(user)) {
    path <- paste(c(prefix, key), collapse = ".")
    value <- user[[key]]
    if (is.null(value)) next
    if (path %in% .sens_freeform_paths()) {
      default[[key]] <- value
    } else if (is.list(value) && is.list(default[[key]]) &&
               !is.null(names(value))) {
      default[[key]] <- .sens_merge_settings(default[[key]], value, c(prefix, key))
    } else {
      default[[key]] <- value
    }
  }
  default
}

#' Expand `outputs.figures` into one flag per figure kind
#'
#' Users may write `figures: true` / `figures: false` to switch every figure
#' at once, or a map to choose per analysis. Internally it is always a
#' complete named list of logicals.
#'
#' @keywords internal
.sens_normalise_figures <- function(settings) {
  kinds <- .sens_figure_kinds()
  value <- settings$outputs$figures

  if (is.logical(value) && length(value) == 1 && !is.na(value)) {
    settings$outputs$figures <- stats::setNames(as.list(rep(value, length(kinds))), kinds)
    return(settings)
  }
  if (is.list(value)) {
    defaults <- sensanalyser_default_settings()$outputs$figures
    for (k in kinds) {
      if (is.null(value[[k]])) value[[k]] <- defaults[[k]]
    }
    settings$outputs$figures <- value[kinds]
  }
  settings
}

#' Suggest the closest known key for a typo
#' @keywords internal
.sens_nearest <- function(key, known) {
  if (length(known) == 0) return(NULL)
  d <- utils::adist(tolower(key), tolower(known))[1, ]
  best <- known[which.min(d)]
  if (min(d) <= max(2, floor(nchar(key) / 3))) best else NULL
}

#' Validate a merged settings list
#'
#' Rejects unknown keys (with a nearest-match suggestion), wrong enum values
#' and obviously wrong types, so mistakes surface before the pipeline runs
#' rather than as a cryptic error three phases in.
#'
#' @param settings Merged settings list.
#' @param user_settings The raw user list, used to check only the keys the
#'   user actually wrote.
#' @return `settings`, invisibly. Aborts on the first fatal problem.
#' @export
sensanalyser_validate_settings <- function(settings, user_settings = NULL) {
  problems <- character(0)
  defaults <- sensanalyser_default_settings()

  # 1. Unknown keys (only where the user wrote something) -------------------
  check_keys <- function(user, default, prefix = character(0)) {
    if (!is.list(user) || is.null(names(user))) return(invisible())
    # Free-form sections hold user-invented names (subset names, spider
    # comparisons): their keys are data, not schema.
    if (paste(prefix, collapse = ".") %in% .sens_freeform_paths()) return(invisible())
    for (key in names(user)) {
      path <- paste(c(prefix, key), collapse = ".")
      if (!key %in% names(default)) {
        hint <- .sens_nearest(key, names(default))
        problems <<- c(problems, sprintf(
          "Unknown setting %s%s", path,
          if (is.null(hint)) "" else sprintf(" - did you mean '%s'?", hint)
        ))
        next
      }
      if (is.list(user[[key]]) && is.list(default[[key]]) &&
          !path %in% .sens_freeform_paths()) {
        check_keys(user[[key]], default[[key]], c(prefix, key))
      }
    }
  }
  if (!is.null(user_settings)) {
    known_user <- user_settings
    # `figures: true|false` is a valid shorthand for the per-figure map.
    if (!is.null(known_user$outputs) && is.logical(known_user$outputs$figures)) {
      known_user$outputs$figures <- NULL
    }
    check_keys(known_user, defaults)
  }

  # 2. Enum values ----------------------------------------------------------
  get_path <- function(x, path) {
    for (p in strsplit(path, ".", fixed = TRUE)[[1]]) x <- x[[p]]
    x
  }
  for (path in names(.sens_enums())) {
    value <- tryCatch(get_path(settings, path), error = function(e) NULL)
    allowed <- .sens_enums()[[path]]
    if (!is.null(value) && !(length(value) == 1 && value %in% allowed)) {
      hint <- .sens_nearest(as.character(value)[1], allowed)
      problems <- c(problems, sprintf(
        "%s = '%s' is not valid. Choose one of: %s.%s",
        path, paste(value, collapse = ", "), paste(allowed, collapse = ", "),
        if (is.null(hint)) "" else sprintf(" (did you mean '%s'?)", hint)
      ))
    }
  }

  # 3. Types and ranges -----------------------------------------------------
  logicals <- c("model.run_anova", "model.run_mixed", "model.posthoc.run",
                "outliers.detect", "outliers.apply_policy",
                "multivariate.pca.run", "multivariate.pca.significant_only",
                "multivariate.hcpc.run", "multivariate.mfa.run",
                "outputs.descriptives", "outputs.tables",
                paste0("outputs.figures.", .sens_figure_kinds()),
                "outputs.report", "derived.enabled",
                "advanced.interactive_setup", "advanced.discover_variables")
  for (path in logicals) {
    value <- tryCatch(get_path(settings, path), error = function(e) NULL)
    if (!is.null(value) && !(is.logical(value) && length(value) == 1 && !is.na(value))) {
      problems <- c(problems, sprintf(
        "%s must be true or false (got '%s').", path, paste(value, collapse = ", ")
      ))
    }
  }

  alpha <- settings$model$alpha
  if (!is.numeric(alpha) || length(alpha) != 1 || is.na(alpha) ||
      alpha <= 0 || alpha >= 1) {
    problems <- c(problems, "model.alpha must be a number between 0 and 1.")
  }

  clusters <- settings$multivariate$hcpc$clusters
  clusters_ok <- (length(clusters) == 1) &&
    (identical(clusters, SENS_AUTO) || identical(clusters, "click") ||
       (is.numeric(clusters) && !is.na(clusters) && clusters >= 2))
  if (!clusters_ok) {
    problems <- c(problems, paste(
      "multivariate.hcpc.clusters must be 'auto', 'click', or a whole number >= 2",
      sprintf("(got '%s').", paste(clusters, collapse = ", "))
    ))
  }

  # 4. Derived attributes ---------------------------------------------------
  for (name in names(settings$derived_attributes)) {
    def <- settings$derived_attributes[[name]]
    if (!is.list(def) || length(def$source_variables) < 2) {
      problems <- c(problems, sprintf(
        "derived_attributes.%s needs a 'source_variables:' list of at least two attributes.", name
      ))
    }
    method <- .sens_or(def$method, "mean")
    if (!identical(method, "mean")) {
      problems <- c(problems, sprintf(
        "derived_attributes.%s: method '%s' is not supported (only 'mean').", name, method
      ))
    }
  }

  # 5. Common variable mistakes --------------------------------------------
  product  <- settings$variables$product
  panelist <- settings$variables$panelist
  if (!is.null(product) && !is.null(panelist) &&
      !identical(product, SENS_ASK) && !identical(panelist, SENS_ASK) &&
      nzchar(panelist) && identical(product, panelist)) {
    problems <- c(problems, sprintf(
      "variables.product and variables.panelist are both '%s'. The product and the assessor must be different columns.",
      product
    ))
  }
  extra <- as.character(unlist(settings$variables$extra_factors))
  if (!is.null(product) && product %in% extra) {
    problems <- c(problems, sprintf(
      "variables.product ('%s') is also listed in variables.extra_factors. List it only as the product.", product
    ))
  }
  bad_formats <- setdiff(as.character(unlist(settings$outputs$report_formats)),
                         c("html", "docx", "pdf"))
  if (length(bad_formats) > 0) {
    problems <- c(problems, sprintf(
      "outputs.report_formats: '%s' is not supported (use html, docx or pdf).",
      paste(bad_formats, collapse = ", ")
    ))
  }

  # 6. Subsets --------------------------------------------------------------
  for (name in names(settings$subsets)) {
    def <- settings$subsets[[name]]
    if (!is.list(def) || !any(c("include", "exclude") %in% names(def))) {
      problems <- c(problems, sprintf(
        "subsets.%s must contain an 'include:' or an 'exclude:' list of products.", name
      ))
    } else if (all(c("include", "exclude") %in% names(def))) {
      problems <- c(problems, sprintf(
        "subsets.%s has both 'include' and 'exclude'. Use only one.", name
      ))
    }
  }

  if (length(problems) > 0) {
    cli::cli_abort(c(
      "Problems in {.path settings.yaml}:",
      stats::setNames(problems, rep("x", length(problems))),
      "i" = "See {.path SETTINGS_CONSOLIDATION_PLAN.md} or the template for the full schema."
    ))
  }

  invisible(settings)
}

# ---------------------------------------------------------------------------
# LOAD
# ---------------------------------------------------------------------------

#' Path to a project's settings file
#' @export
sensanalyser_settings_path <- function(project_dir) {
  file.path(project_dir, "settings.yaml")
}

#' Serialise a list to YAML using true/false (not yaml's yes/no)
#'
#' Keeps written settings.yaml files consistent with the template a user
#' compares against.
#'
#' @keywords internal
.sens_as_yaml <- function(x) {
  yaml::as.yaml(x, indent = 2, handlers = list(
    logical = function(v) {
      out <- ifelse(v, "true", "false")
      class(out) <- "verbatim"
      out
    }
  ))
}

#' Load, merge and validate a project's settings.yaml
#'
#' @param project_dir Path to the project folder.
#' @return The merged settings list, with `project_root` and `project$name`
#'   resolved. Aborts if the file is missing or invalid.
#' @export
sensanalyser_load_settings <- function(project_dir) {
  path <- sensanalyser_settings_path(project_dir)
  if (!file.exists(path)) {
    cli::cli_abort("No {.path settings.yaml} found in {.path {project_dir}}.")
  }

  user <- tryCatch(
    yaml::read_yaml(path),
    error = function(e) cli::cli_abort(c(
      "Could not parse {.path {path}}: {conditionMessage(e)}",
      "i" = "YAML is indentation-sensitive: use two spaces, never tabs."
    ))
  )
  if (is.null(user)) user <- list()

  settings <- .sens_merge_settings(sensanalyser_default_settings(), user)
  settings <- .sens_normalise_figures(settings)
  sensanalyser_validate_settings(settings, user_settings = user)

  settings$project$name <- .sens_or(settings$project$name, basename(normalizePath(project_dir)))
  settings$project_root <- normalizePath(project_dir)
  settings
}

#' Resolve the data files for a project
#'
#' `data.files: auto` lists every supported file in `data/raw`. An explicit
#' list is taken as-is (project-relative paths are resolved against the
#' project root), so a project folder stays portable.
#'
#' @keywords internal
.sens_resolve_data_files <- function(settings) {
  files <- settings$data$files
  root <- settings$project_root

  # `ask` -> NULL so an interactive run prompts with the file picker.
  if (identical(files, SENS_ASK)) {
    return(NULL)
  }

  if (identical(files, SENS_AUTO)) {
    raw_dir <- file.path(root, "data", "raw")
    found <- list.files(raw_dir, pattern = "\\.(csv|tsv|txt|xlsx|xls)$",
                        full.names = TRUE, ignore.case = TRUE)
    if (length(found) == 0) {
      cli::cli_abort(c(
        "No data files found in {.path {raw_dir}}.",
        "i" = "Copy your csv/xlsx files there, or list them under {.field data.files} in settings.yaml."
      ))
    }
    return(sort(found))
  }

  files <- as.character(unlist(files))
  absolute <- file.path(root, files)
  files <- ifelse(file.exists(files), files, absolute)
  missing <- files[!file.exists(files)]
  if (length(missing) > 0) {
    cli::cli_abort("Data file{?s} listed in settings.yaml not found: {.path {missing}}")
  }
  normalizePath(files)
}

# ---------------------------------------------------------------------------
# WRITE CHOICES BACK: turn an interactive run into an explicit settings.yaml
# ---------------------------------------------------------------------------

#' Write the choices from an interactive run back into settings.yaml
#'
#' @description
#' When a project is set up interactively (console prompts for data files and
#' variables), the answers used to disappear into a hidden
#' `analysis_config.yaml`. Instead, they are written back into the user's own
#' `settings.yaml`: the resolved data files, attribute list, product/panelist
#' columns and design factors become explicit, and `interactive_setup` is
#' turned off so the next run reproduces the choices without prompting.
#'
#' The user's other settings and section order are preserved (the raw YAML is
#' updated in place); YAML comments are not, so a note records when and why
#' the file changed.
#'
#' @param project_root Project folder.
#' @param selections The resolved selection list from the pipeline
#'   (`pipeline_state$selections`).
#' @return The settings path, invisibly.
#' @keywords internal
.sens_write_choices <- function(project_root, selections) {
  path <- sensanalyser_settings_path(project_root)
  if (!file.exists(path)) return(invisible(path))

  user <- tryCatch(yaml::read_yaml(path), error = function(e) NULL)
  if (is.null(user)) user <- list()

  as_list <- function(x) {
    x <- x[!is.na(x) & nzchar(as.character(x))]
    if (length(x) == 0) list() else as.list(as.character(x))
  }

  # Data files are not chosen interactively in settings mode (data.files
  # already resolves to concrete paths), so `auto` is left untouched here.

  # ── variables ────────────────────────────────────────────────────────────
  dvs <- selections$dependent_variables
  if (length(dvs) > 0) user$variables$attributes <- as_list(dvs)
  factors <- as.character(selections$factors)
  if (length(factors) > 0) {
    user$variables$product <- factors[[1]]
    user$variables$extra_factors <- as_list(factors[-1])
  }
  if (length(selections$subject_id) > 0) {
    user$variables$panelist <- as.character(selections$subject_id)[[1]]
  }

  # ── model design columns ─────────────────────────────────────────────────
  user$model$random_effects    <- as_list(selections$random_effects)
  user$model$repeated_measures <- as_list(selections$repeated_measures_factors)

  # ── stop prompting next time ─────────────────────────────────────────────
  user$advanced$interactive_setup <- FALSE

  header <- c(
    "# ==========================================================================",
    "# SENSANALYSER PROJECT SETTINGS",
    "# ==========================================================================",
    "#",
    paste0("# Variable selections written from an interactive run on ", format(Sys.Date()), "."),
    "# interactive_setup was turned off so future runs reproduce these choices.",
    "# Every option is documented in templates/settings.yaml.",
    "# --------------------------------------------------------------------------",
    ""
  )
  writeLines(c(header, strsplit(.sens_as_yaml(user), "\n", fixed = TRUE)[[1]]), path)
  cli::cli_alert_success("Saved your choices into {.path settings.yaml} (interactive setup turned off).")
  invisible(path)
}

# ---------------------------------------------------------------------------
# MACHINE STATE: files the pipeline owns, never the user
# ---------------------------------------------------------------------------

#' Folder holding pipeline-owned files for a project
#'
#' The user edits `settings.yaml`; everything Sensanalyser generates or
#' remembers lives here, so the two never get confused.
#'
#' @param project_root Project folder.
#' @param create Create the folder if missing?
#' @export
sensanalyser_state_dir <- function(project_root, create = FALSE) {
  path <- file.path(project_root, "data", "dictionary", "state")
  if (create) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  path
}

#' Locate an engine asset, letting a project override it
#'
#' Model presets and the report template are engine assets. They are read
#' from `templates/` unless the project ships its own customised copy.
#'
#' @keywords internal
.sens_engine_asset <- function(project_root, project_rel, template_rel) {
  project_copy <- file.path(project_root, project_rel)
  if (file.exists(project_copy)) return(project_copy)
  template <- tryCatch(here::here(template_rel), error = function(e) template_rel)
  if (file.exists(template)) template else project_copy
}

#' Write the resolved label dictionary and derived attributes into state/
#'
#' `settings.yaml` is the source of truth, but the analysis modules read a
#' dictionary YAML by path. Rather than touching seventeen call sites, the
#' resolved content is materialised into `data/dictionary/state/`, which the
#' modules then read. Legacy `data/dictionary/*.yaml` files are still honoured
#' for anything the settings file does not define, so projects that have not
#' migrated keep working.
#'
#' @param settings A loaded settings list.
#' @return Named list of paths (`renaming_dictionary`, `derived_attributes`).
#' @keywords internal
.sens_materialise_state <- function(settings) {
  root <- settings$project_root
  dict_dir <- file.path(root, "data", "dictionary")
  state_dir <- sensanalyser_state_dir(root, create = TRUE)

  # ── Labels ───────────────────────────────────────────────────────────────
  legacy_dict_path <- file.path(dict_dir, "renaming_dictionary.yaml")
  legacy <- if (file.exists(legacy_dict_path)) {
    tryCatch(yaml::read_yaml(legacy_dict_path), error = function(e) list())
  } else {
    list()
  }
  if (is.null(legacy)) legacy <- list()

  labels <- settings$labels
  resolved <- list(
    # `attributes:` reads better than the engine's internal `outcomes:`
    aliases   = if (length(labels$aliases) > 0)    labels$aliases    else .sens_or(legacy$aliases, list()),
    variables = if (length(labels$variables) > 0)  labels$variables  else .sens_or(legacy$variables, list()),
    levels    = if (length(labels$levels) > 0)     labels$levels     else .sens_or(legacy$levels, list()),
    outcomes  = if (length(labels$attributes) > 0) labels$attributes else .sens_or(legacy$outcomes, list())
  )
  dict_path <- file.path(state_dir, "renaming_dictionary.yaml")
  yaml::write_yaml(resolved, dict_path)

  # ── Derived attributes ───────────────────────────────────────────────────
  legacy_derived_path <- file.path(dict_dir, "derived_attributes.yaml")
  derived <- settings$derived_attributes
  if (length(derived) == 0 && file.exists(legacy_derived_path)) {
    legacy_derived <- tryCatch(yaml::read_yaml(legacy_derived_path), error = function(e) list())
    derived <- .sens_or(legacy_derived$derived_attributes, list())
  }
  derived_path <- file.path(state_dir, "derived_attributes.yaml")
  yaml::write_yaml(list(derived_attributes = derived), derived_path)

  # ── Relocate pipeline-owned decisions ────────────────────────────────────
  legacy_splits <- file.path(dict_dir, "factor_splits.yaml")
  state_splits <- file.path(state_dir, "factor_splits.yaml")
  if (file.exists(legacy_splits) && !file.exists(state_splits)) {
    file.rename(legacy_splits, state_splits)
    cli::cli_alert_info("Moved {.path factor_splits.yaml} into {.path data/dictionary/state/} (Sensanalyser maintains it).")
  }

  list(renaming_dictionary = dict_path, derived_attributes = derived_path)
}

# ---------------------------------------------------------------------------
# ADAPTER: settings -> the config the engine already consumes
# ---------------------------------------------------------------------------

#' Translate settings.yaml into the engine's config list
#'
#' The single translation point between the user-facing schema and the
#' internal `config` structure of `run_sensanalyser_pipeline()`. Engine
#' modules are untouched.
#'
#' @param settings A list from [sensanalyser_load_settings()].
#' @return The `config` list expected by `run_sensanalyser_pipeline()`.
#' @export
sensanalyser_settings_to_config <- function(settings) {
  root <- settings$project_root

  # hcpc: auto -> -1 (FactoMineR chooses), click -> 0 (interactive cut)
  clusters <- settings$multivariate$hcpc$clusters
  hcpc_n <- if (identical(clusters, SENS_AUTO)) {
    -1
  } else if (identical(clusters, "click")) {
    0
  } else {
    as.integer(clusters)
  }

  # `ask` on a variable field -> NULL, so an interactive run prompts for it
  # (used by reset_project). `auto` keeps auto-detection.
  ask_or <- function(x, otherwise) if (identical(x, SENS_ASK)) NULL else otherwise

  attributes <- settings$variables$attributes
  if (identical(attributes, SENS_ASK)) {
    attributes <- NULL
  } else if (!identical(attributes, SENS_AUTO)) {
    attributes <- setdiff(as.character(unlist(attributes)),
                          as.character(unlist(settings$variables$exclude)))
  }

  product  <- ask_or(settings$variables$product, settings$variables$product)
  panelist <- ask_or(settings$variables$panelist, settings$variables$panelist)
  factors <- if (is.null(product)) {
    NULL
  } else {
    unique(c(product, as.character(unlist(settings$variables$extra_factors))))
  }

  state <- .sens_materialise_state(settings)

  config <- list(
    paths = list(
      raw_data            = .sens_resolve_data_files(settings),
      analysis_config     = file.path(root, "data/dictionary/state/resolved_run.yaml"),
      renaming_dictionary = state$renaming_dictionary,
      derived_attributes  = state$derived_attributes,
      model_presets       = .sens_engine_asset(root, "data/dictionary/model_presets.yaml",
                                               "engine/templates/data/dictionary/model_presets.yaml"),
      report_template     = .sens_engine_asset(root, "reports/sensanalyser_results_report.qmd",
                                               "engine/templates/reports/sensanalyser_results_report.qmd"),
      derived_data        = file.path(root, "data/processed/derived_attribute_dataset.csv"),
      table_root          = file.path(root, "outputs/tables"),
      figure_root         = file.path(root, "outputs/figures"),
      diagnostics_root    = file.path(root, "outputs/diagnostics"),
      logs_root           = file.path(root, "outputs/logs")
    ),

    toggles = list(
      interactive_setup         = settings$advanced$interactive_setup,
      discover_variables        = settings$advanced$discover_variables,
      run_outlier_detection     = settings$outliers$detect,
      apply_outlier_policy      = settings$outliers$apply_policy,
      run_descriptives          = settings$outputs$descriptives,
      run_anova_models          = settings$model$run_anova,
      run_mixed_models          = settings$model$run_mixed,
      run_posthoc               = settings$model$posthoc$run,
      run_pca                   = settings$multivariate$pca$run,
      run_mfa                   = settings$multivariate$mfa$run,
      run_hcpc                  = settings$multivariate$hcpc$run,
      create_tables             = settings$outputs$tables,
      # The spider-plot module is the one gated by create_figures; PCA, HCPC
      # and MFA check figure_toggles when saving their own images.
      create_figures            = isTRUE(settings$outputs$figures$spider),
      render_quarto_report      = settings$outputs$report,
      create_derived_attributes = settings$derived$enabled
    ),

    figure_toggles = settings$outputs$figures,

    analysis = list(
      dependent_variables          = attributes,
      exclude_attributes           = as.character(unlist(settings$variables$exclude)),
      factors                      = factors,
      subject_id                   = panelist,
      random_effects               = as.character(unlist(settings$model$random_effects)),
      repeated_measures_factors    = as.character(unlist(settings$model$repeated_measures)),
      model_type                   = settings$model$type,
      model_fixed_effects          = settings$model$fixed_effects,
      posthoc_method               = settings$model$posthoc$method,
      posthoc_focal_terms          = settings$model$posthoc$focal_terms,
      outlier_policy               = settings$outliers$policy,
      outlier_removal_action       = settings$outliers$action,
      outlier_grouping_factors     = settings$outliers$grouping_factors,
      descriptive_grouping_factors = settings$advanced$descriptive_grouping_factors,
      pca_significant_only         = settings$multivariate$pca$significant_only,
      hcpc_n_clusters              = hcpc_n,
      alpha                        = settings$model$alpha
    ),

    table_options = list(
      digits          = settings$outputs$table$digits,
      include_mean_se = settings$outputs$table$mean_se,
      include_letters = settings$outputs$table$letters
    ),

    fig_options = list(
      width                   = settings$outputs$figure$width,
      height                  = settings$outputs$figure$height,
      dpi                     = settings$outputs$figure$dpi,
      palette                 = settings$outputs$figure$palette,
      top_n_attributes        = settings$outputs$spider$top_n_attributes,
      spider_significant_only = settings$outputs$spider$significant_only,
      spider_outcomes         = settings$outputs$spider$attributes,
      spider_label_size       = settings$outputs$spider$label_size,
      spider_legend           = settings$outputs$spider$legend,
      spider_colors           = settings$outputs$spider$colors,
      spider_scale_min        = settings$outputs$spider$scale_min,
      spider_scale_max        = settings$outputs$spider$scale_max,
      spider_axis_labels      = settings$outputs$spider$axis_labels,
      spider_axis_unit        = settings$outputs$spider$axis_unit,
      spider_axis_steps       = settings$outputs$spider$axis_steps,
      spider_comparisons      = settings$outputs$spider$comparisons
    ),

    derived_attribute_options = list(
      digits       = settings$derived$digits,
      output_label = settings$derived$output_label
    ),

    report_options = list(output_formats = settings$outputs$report_formats),

    product_subsets = settings$subsets,
    project_root    = root,

    # Tells the engine that settings.yaml is authoritative, so a stale
    # analysis_config.yaml must not override these values.
    settings_driven = TRUE
  )

  # Empty character vectors mean "not set" to the engine, which expects NULL.
  for (key in c("random_effects", "repeated_measures_factors", "exclude_attributes")) {
    if (length(config$analysis[[key]]) == 0) config$analysis[[key]] <- NULL
  }
  if (!nzchar(.sens_or(config$analysis$subject_id, ""))) {
    config$analysis$subject_id <- NULL
  }

  config
}

#' Should this analysis save its figures?
#'
#' Analyses always compute their tables; this only decides whether the image
#' files are written. Legacy `project_config.R` runs carry no
#' `figure_toggles`, so figures stay on for them.
#'
#' @param config The engine config list.
#' @param kind One of "spider", "pca", "hcpc", "mfa".
#' @return TRUE when the figures for `kind` should be saved.
#' @export
sensanalyser_save_figures <- function(config, kind) {
  toggles <- config$figure_toggles
  if (is.null(toggles) || is.null(toggles[[kind]])) return(TRUE)
  isTRUE(toggles[[kind]])
}

# ---------------------------------------------------------------------------
# SUMMARY: what will run, and what did I change?
# ---------------------------------------------------------------------------

.sens_fmt <- function(x) {
  if (is.null(x) || length(x) == 0) return("not set")
  if (is.logical(x)) return(if (isTRUE(x)) "yes" else "no")
  if (length(x) > 4) return(sprintf("%s, ... (%d total)", paste(utils::head(x, 3), collapse = ", "), length(x)))
  paste(as.character(x), collapse = ", ")
}

#' Print the effective settings for the next run
#'
#' Shows the configuration the pipeline will use, marking every value that
#' deviates from the default so the user can see at a glance what they have
#' customised - the question "what did I change?" answered without diffing
#' files.
#'
#' @param project_dir Path to the project folder, or a settings list.
#' @return The settings list, invisibly.
#' @export
sensanalyser_settings_summary <- function(project_dir) {
  settings <- if (is.list(project_dir)) project_dir else sensanalyser_load_settings(project_dir)
  defaults <- sensanalyser_default_settings()

  get_path <- function(x, path) {
    for (p in strsplit(path, ".", fixed = TRUE)[[1]]) x <- x[[p]]
    x
  }
  line <- function(label, path) {
    value <- tryCatch(get_path(settings, path), error = function(e) NULL)
    default <- tryCatch(get_path(defaults, path), error = function(e) NULL)
    shown <- .sens_fmt(value)
    if (!identical(value, default)) {
      shown_default <- .sens_fmt(default)
      cli::cli_li("{label}: {.strong {shown}} {.emph [default: {shown_default}]}")
    } else {
      cli::cli_li("{label}: {shown}")
    }
  }

  cli::cli_h2("Settings for project '{settings$project$name}'")

  files <- tryCatch(.sens_resolve_data_files(settings), error = function(e) character(0))
  cli::cli_h3("Data")
  cli::cli_ul()
  cli::cli_li("Files: {length(files)} found{if (identical(settings$data$files, SENS_AUTO)) ' (auto from data/raw)' else ' (listed in settings.yaml)'}")
  line("Attributes", "variables.attributes")
  if (length(settings$variables$exclude) > 0) line("Excluded attributes", "variables.exclude")
  line("Product column", "variables.product")
  line("Panelist column", "variables.panelist")
  if (length(settings$variables$extra_factors) > 0) line("Extra factors", "variables.extra_factors")
  cli::cli_end()

  cli::cli_h3("Model")
  cli::cli_ul()
  line("Type", "model.type")
  line("Random effects", "model.random_effects")
  line("Alpha", "model.alpha")
  line("Post-hoc", "model.posthoc.run")
  if (isTRUE(settings$model$posthoc$run)) line("Post-hoc method", "model.posthoc.method")
  cli::cli_end()

  cli::cli_h3("Analyses")
  cli::cli_ul()
  line("Outlier detection", "outliers.detect")
  if (isTRUE(settings$outliers$detect)) line("Outlier policy", "outliers.policy")
  line("Descriptives", "outputs.descriptives")
  line("PCA", "multivariate.pca.run")
  line("HCPC", "multivariate.hcpc.run")
  if (isTRUE(settings$multivariate$hcpc$run)) line("HCPC clusters", "multivariate.hcpc.clusters")
  line("MFA", "multivariate.mfa.run")
  cli::cli_end()

  cli::cli_h3("Outputs")
  cli::cli_ul()
  line("Tables", "outputs.tables")
  figs <- settings$outputs$figures
  on_kinds <- names(figs)[vapply(figs, isTRUE, logical(1))]
  off_kinds <- setdiff(names(figs), on_kinds)
  figs_shown <- if (length(on_kinds) == 0) {
    "none"
  } else if (length(off_kinds) == 0) {
    "all (spider, pca, hcpc, mfa)"
  } else {
    sprintf("%s (off: %s)", paste(on_kinds, collapse = ", "), paste(off_kinds, collapse = ", "))
  }
  if (length(off_kinds) > 0) {
    cli::cli_li("Figures: {.strong {figs_shown}}")
  } else {
    cli::cli_li("Figures: {figs_shown}")
  }
  line("Quarto report", "outputs.report")
  line("Derived attributes", "derived.enabled")
  n_labels <- length(settings$labels$variables) + length(settings$labels$levels) +
    length(settings$labels$attributes)
  cli::cli_li("Display labels: {n_labels} defined{if (length(settings$labels$aliases) > 0) ' (+ product aliases)' else ''}")
  if (length(settings$derived_attributes) > 0) {
    cli::cli_li("Derived attribute definitions: {paste(names(settings$derived_attributes), collapse = ', ')}")
  }
  cli::cli_li("Subsets: {if (length(settings$subsets) == 0) 'none' else paste(names(settings$subsets), collapse = ', ')}")
  cli::cli_end()

  invisible(settings)
}
