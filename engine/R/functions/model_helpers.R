#' Model Helpers for Sensanalyser
#'
#' @description
#' Phase 5 statistical model engine.
#' Supports configurable between-subject ANOVA and linear mixed models,
#' with robust per-outcome error handling and diagnostics export.
#'
#' Core outputs:
#' - outputs/tables/results_model.csv
#' - outputs/diagnostics/model_warnings.csv
#'
#' @keywords internal

# ---------------------------------------------------------------------------
# MODEL PRESET RESOLUTION
# ---------------------------------------------------------------------------

#' Resolve model settings from config + preset YAML
#'
#' @description
#' Presets define structural properties only (engine, interaction flags,
#' repeated_measures flag). Column names — fixed_effects, random_effects,
#' repeated_measures_factors — ALWAYS come from user selections and are
#' never overwritten by the preset.
#'
#' Column name resolution order:
#'   1. config$analysis$model_fixed_effects (explicit override)
#'   2. config$analysis$factors (synced from Phase 2 selections)
#'   3. selections$factors (direct fallback for call sites that pass it)
#'
#' @param config Full pipeline config list
#' @param selections Variable selections list from Phase 2 (optional fallback)
#' @return List with resolved settings
#' @export
resolve_model_settings <- function(config, selections = NULL) {
  model_type <- config$analysis$model_type

  # ── Column names: resolve from config first, then selections fallback ────
  user_fixed <- if (!is.null(config$analysis$model_fixed_effects) &&
                    length(config$analysis$model_fixed_effects) > 0) {
    config$analysis$model_fixed_effects
  } else if (!is.null(config$analysis$factors) &&
             length(config$analysis$factors) > 0) {
    config$analysis$factors
  } else if (!is.null(selections$factors) && length(selections$factors) > 0) {
    selections$factors
  } else {
    NULL
  }

  user_random <- if (!is.null(config$analysis$random_effects) &&
                     length(config$analysis$random_effects) > 0) {
    config$analysis$random_effects
  } else if (!is.null(selections$random_effects) &&
             length(selections$random_effects) > 0) {
    selections$random_effects
  } else {
    NULL   # formula builder will fall back to subject_id
  }

  user_rm <- if (!is.null(config$analysis$repeated_measures_factors) &&
                 length(config$analysis$repeated_measures_factors) > 0) {
    config$analysis$repeated_measures_factors
  } else if (!is.null(selections$repeated_measures_factors) &&
             length(selections$repeated_measures_factors) > 0) {
    selections$repeated_measures_factors
  } else {
    NULL   # defaulted after preset merge for all-within designs
  }

  # ── Initial settings (structural defaults) ───────────────────────────────
  settings <- list(
    model_type                = model_type,
    fixed_effects             = user_fixed,
    interactions              = TRUE,
    three_way_interactions    = TRUE,
    repeated_measures         = FALSE,
    repeated_measures_factors = user_rm,
    random_effects            = user_random,
    engine = if (identical(model_type, "linear_mixed_model")) "lmerTest_lmer" else "rstatix_anova_test"
  )

  # ── Merge STRUCTURAL properties from preset only ─────────────────────────
  # Never apply fixed_effects, random_effects, or repeated_measures_factors
  # from the preset — those are dataset-specific column names and must come
  # from the user's selections above.
  structural_keys <- c("engine", "interactions", "three_way_interactions", "repeated_measures")

  preset_path <- config$paths$model_presets
  if (!is.null(preset_path) && nzchar(preset_path) && file.exists(preset_path)) {
    presets <- yaml::read_yaml(preset_path)
    if (!is.null(presets[[model_type]])) {
      preset <- presets[[model_type]]
      for (key in structural_keys) {
        if (!is.null(preset[[key]])) settings[[key]] <- preset[[key]]
      }
    }
  }

  # ── Re-apply user column names (never let preset overwrite them) ─────────
  settings$fixed_effects  <- user_fixed
  settings$random_effects <- user_random

  # Repeated-measures factors: use user selection when provided.
  # For all-within designs with no explicit RM selection, default to fixed_effects.
  if (!is.null(user_rm) && length(user_rm) > 0) {
    settings$repeated_measures_factors <- user_rm
  } else if (isTRUE(settings$repeated_measures)) {
    settings$repeated_measures_factors <- user_fixed
  }

  settings
}

# ---------------------------------------------------------------------------
# FORMULA BUILDER
# ---------------------------------------------------------------------------

#' Build fixed-effect right-hand side
#'
#' @param fixed_effects Character vector of fixed-effect columns.
#' @param interactions Logical. Include interactions?
#' @param three_way_interactions Logical. Include three-way and higher interactions?
#' @return Character formula RHS for fixed effects.
#' @keywords internal
.build_fixed_rhs <- function(fixed_effects, interactions = TRUE, three_way_interactions = TRUE) {
  if (is.null(fixed_effects) || length(fixed_effects) == 0) {
    cli::cli_abort("Model requires at least one fixed effect.")
  }

  if (!isTRUE(interactions) || length(fixed_effects) == 1) {
    return(paste(fixed_effects, collapse = " + "))
  }

  if (length(fixed_effects) >= 3 && !isTRUE(three_way_interactions)) {
    return(paste0("(", paste(fixed_effects, collapse = " + "), ")^2"))
  }

  paste(fixed_effects, collapse = " * ")
}

#' Build model formula for one outcome
#'
#' @param outcome Dependent variable name
#' @param settings Resolved model settings from resolve_model_settings()
#' @param selections Variable selection list
#' @return Formula object
#' @export
build_model_formula <- function(outcome, settings, selections) {
  fixed_effects <- settings$fixed_effects
  fixed_rhs <- .build_fixed_rhs(
    fixed_effects = fixed_effects,
    interactions = settings$interactions,
    three_way_interactions = settings$three_way_interactions
  )

  # Repeated-measures ANOVA style. afex::aov_car requires an Error() term.
  if (identical(settings$engine, "afex_aov_car")) {
    subject_id <- selections$subject_id
    if (is.null(subject_id) || length(subject_id) == 0) {
      cli::cli_abort("Repeated-measures ANOVA requires a subject_id column.")
    }

    within_terms <- settings$repeated_measures_factors
    if (is.null(within_terms) || length(within_terms) == 0) {
      within_terms <- fixed_effects
    }

    error_term <- if (length(within_terms) > 0) {
      paste0("Error(", subject_id, "/(", paste(within_terms, collapse = " * "), "))")
    } else {
      paste0("Error(", subject_id, ")")
    }

    return(stats::as.formula(paste(outcome, "~", fixed_rhs, "+", error_term)))
  }

  # Between-subject ANOVA style.
  if (!identical(settings$engine, "lmerTest_lmer")) {
    return(stats::as.formula(paste(outcome, "~", fixed_rhs)))
  }

  # Mixed model style: add random effects terms.
  random_effects <- settings$random_effects
  if (is.null(random_effects) || length(random_effects) == 0) {
    random_effects <- selections$random_effects
  }
  if (is.null(random_effects) || length(random_effects) == 0) {
    random_effects <- selections$subject_id
  }

  if (is.null(random_effects) || length(random_effects) == 0) {
    cli::cli_abort("linear_mixed_model selected but no random effects / subject_id provided.")
  }

  rand_terms <- paste0("(1|", random_effects, ")", collapse = " + ")
  stats::as.formula(paste(outcome, "~", fixed_rhs, "+", rand_terms))
}

# ---------------------------------------------------------------------------
# SINGLE MODEL RUN
# ---------------------------------------------------------------------------

#' Run model for one outcome
#'
#' @param data Working dataset
#' @param outcome Dependent variable name
#' @param settings Resolved model settings
#' @param selections Variable selection list
#' @return List(model_table, warning_table, model_object, formula)
#' @export
run_model_for_outcome <- function(data, outcome, settings, selections) {
  formula <- build_model_formula(outcome, settings, selections)

  warnings_collected <- character(0)

  model_exec <- withCallingHandlers(
    {
      if (identical(settings$engine, "lmerTest_lmer")) {
        model_obj <- lmerTest::lmer(formula, data = data)
        anova_tbl <- tryCatch(
          {
            as.data.frame(stats::anova(model_obj))
          },
          error = function(e) {
            as.data.frame(lmerTest::anova(model_obj))
          }
        )

        # Normalize column names
        anova_tbl <- tibble::as_tibble(anova_tbl, rownames = "term")
        if ("Pr(>F)" %in% names(anova_tbl)) {
          anova_tbl <- dplyr::rename(anova_tbl, p = `Pr(>F)`)
        }
        if ("NumDF" %in% names(anova_tbl)) {
          anova_tbl <- dplyr::rename(anova_tbl, df = NumDF)
        }
        if ("F.value" %in% names(anova_tbl)) {
          anova_tbl <- dplyr::rename(anova_tbl, statistic = F.value)
        }
        if ("F value" %in% names(anova_tbl)) {
          anova_tbl <- dplyr::rename(anova_tbl, statistic = `F value`)
        }

        model_tbl <- anova_tbl %>%
          dplyr::mutate(
            outcome = outcome,
            model_type = settings$model_type,
            engine = settings$engine,
            formula = as.character(formula)[3],
            .before = 1
          )

        list(model_table = model_tbl, model_object = model_obj)
      } else if (identical(settings$engine, "afex_aov_car")) {
        model_obj <- afex::aov_car(
          formula = formula,
          data = data,
          factorize = FALSE,
          anova_table = list(correction = "GG", es = "ges")
        )

        anova_tbl <- as.data.frame(model_obj$anova_table) %>%
          tibble::as_tibble(rownames = "term")

        if ("Pr(>F)" %in% names(anova_tbl)) {
          anova_tbl <- dplyr::rename(anova_tbl, p = `Pr(>F)`)
        }
        if ("num Df" %in% names(anova_tbl)) {
          anova_tbl <- dplyr::rename(anova_tbl, DFn = `num Df`)
        }
        if ("den Df" %in% names(anova_tbl)) {
          anova_tbl <- dplyr::rename(anova_tbl, DFd = `den Df`)
        }

        model_tbl <- anova_tbl %>%
          dplyr::mutate(
            outcome = outcome,
            model_type = settings$model_type,
            engine = settings$engine,
            formula = as.character(formula)[3],
            .before = 1
          )

        list(model_table = model_tbl, model_object = model_obj)
      } else {
        model_obj <- stats::aov(formula, data = data)
        aov_tbl <- rstatix::anova_test(data = data, formula = formula)
        model_tbl <- tibble::as_tibble(aov_tbl)
        if ("Effect" %in% names(model_tbl)) {
          model_tbl <- dplyr::rename(model_tbl, term = Effect)
        }
        model_tbl <- model_tbl %>%
          dplyr::mutate(
            outcome = outcome,
            model_type = settings$model_type,
            engine = settings$engine,
            formula = as.character(formula)[3],
            .before = 1
          )

        list(model_table = model_tbl, model_object = model_obj)
      }
    },
    warning = function(w) {
      warnings_collected <<- c(warnings_collected, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )

  warning_table <- if (length(warnings_collected) > 0) {
    tibble::tibble(
      outcome = outcome,
      model_type = settings$model_type,
      formula = as.character(formula)[3],
      warning = unique(warnings_collected)
    )
  } else {
    tibble::tibble(
      outcome = character(0),
      model_type = character(0),
      formula = character(0),
      warning = character(0)
    )
  }

  list(
    model_table = model_exec$model_table,
    warning_table = warning_table,
    model_object = model_exec$model_object,
    formula = formula
  )
}

# ---------------------------------------------------------------------------
# MODEL SUITE
# ---------------------------------------------------------------------------

#' Validate model settings against the dataset
#'
#' @param data Working dataset.
#' @param settings Resolved model settings.
#' @param selections Variable selection list.
#' @return Invisibly TRUE or aborts with a clear message.
#' @keywords internal
validate_model_settings <- function(data, settings, selections) {
  errors <- character(0)

  fixed_effects <- settings$fixed_effects
  missing_fixed <- setdiff(fixed_effects, names(data))
  if (length(missing_fixed) > 0) {
    errors <- c(errors, paste0("Fixed effect column(s) missing: ", paste(missing_fixed, collapse = ", ")))
  }

  if (identical(settings$engine, "afex_aov_car")) {
    if (is.null(selections$subject_id) || length(selections$subject_id) == 0) {
      errors <- c(errors, "Repeated-measures ANOVA requires subject_id.")
    } else if (!selections$subject_id %in% names(data)) {
      errors <- c(errors, paste0("Subject ID column missing: ", selections$subject_id))
    }

    rm_factors <- settings$repeated_measures_factors
    if (is.null(rm_factors) || length(rm_factors) == 0) {
      errors <- c(errors, "Repeated-measures ANOVA requires repeated_measures_factors.")
    } else {
      missing_rm <- setdiff(rm_factors, names(data))
      if (length(missing_rm) > 0) {
        errors <- c(errors, paste0("Repeated-measures factor column(s) missing: ", paste(missing_rm, collapse = ", ")))
      }
    }
  }

  if (identical(settings$engine, "lmerTest_lmer")) {
    random_effects <- settings$random_effects
    if (is.null(random_effects) || length(random_effects) == 0) random_effects <- selections$random_effects
    if (is.null(random_effects) || length(random_effects) == 0) random_effects <- selections$subject_id

    if (is.null(random_effects) || length(random_effects) == 0) {
      errors <- c(errors, "Linear mixed model requires random_effects or subject_id.")
    } else {
      missing_random <- setdiff(random_effects, names(data))
      if (length(missing_random) > 0) {
        errors <- c(errors, paste0("Random-effect column(s) missing: ", paste(missing_random, collapse = ", ")))
      }
    }
  }

  if (length(errors) > 0) {
    cli::cli_abort(c("Model setting validation failed:", setNames(errors, rep("x", length(errors)))))
  }

  invisible(TRUE)
}

#' Run model suite across all selected outcomes
#'
#' @param data Working dataset
#' @param selections Variable selection list
#' @param config Full pipeline config list
#' @return List(results_model, warnings, failures)
#' @export
run_model_suite <- function(data, selections, config) {
  cli::cli_h2("Phase 5: Statistical Models")

  settings <- resolve_model_settings(config, selections)
  validate_model_settings(data, settings, selections)

  # Ensure design columns are treated categorically even when they were supplied
  # only through model_fixed_effects (and therefore not coerced in Phase 2).
  design_cols <- unique(c(settings$fixed_effects, settings$repeated_measures_factors, settings$random_effects, selections$subject_id))
  design_cols <- design_cols[!is.na(design_cols) & nzchar(design_cols) & design_cols %in% names(data)]
  for (col in design_cols) {
    data[[col]] <- as.factor(data[[col]])
  }

  outcomes <- selections$dependent_variables
  if (is.null(outcomes) || length(outcomes) == 0) {
    cli::cli_abort("No dependent variables available for model suite.")
  }

  model_tables <- list()
  warning_tables <- list()
  failures <- list()

  for (outcome in outcomes) {
    if (!outcome %in% names(data)) {
      failures[[length(failures) + 1]] <- tibble::tibble(
        outcome = outcome,
        stage = "precheck",
        error = "Outcome column missing in dataset"
      )
      next
    }

    if (!is.numeric(data[[outcome]])) {
      failures[[length(failures) + 1]] <- tibble::tibble(
        outcome = outcome,
        stage = "precheck",
        error = "Outcome is not numeric"
      )
      next
    }

    result <- tryCatch(
      run_model_for_outcome(data, outcome, settings, selections),
      error = function(e) {
        failures[[length(failures) + 1]] <<- tibble::tibble(
          outcome = outcome,
          stage = "model_fit",
          error = conditionMessage(e)
        )
        NULL
      }
    )

    if (!is.null(result)) {
      model_tables[[length(model_tables) + 1]] <- result$model_table
      if (nrow(result$warning_table) > 0) {
        warning_tables[[length(warning_tables) + 1]] <- result$warning_table
      }
    }
  }

  results_model <- dplyr::bind_rows(model_tables)
  model_warnings <- dplyr::bind_rows(warning_tables)
  model_failures <- dplyr::bind_rows(failures)

  if (nrow(model_failures) > 0) {
    # Track failures in the same diagnostics table format
    fail_as_warn <- model_failures %>%
      dplyr::transmute(
        outcome = .data$outcome,
        model_type = settings$model_type,
        formula = NA_character_,
        warning = paste0("ERROR [", .data$stage, "]: ", .data$error)
      )
    model_warnings <- dplyr::bind_rows(model_warnings, fail_as_warn)
  }

  list(
    settings = settings,
    results_model = results_model,
    warnings = model_warnings,
    failures = model_failures
  )
}

# ---------------------------------------------------------------------------
# OUTPUT WRITERS
# ---------------------------------------------------------------------------

#' Save model diagnostics and tables
#'
#' @param model_result Output of run_model_suite()
#' @param config Full config
#' @return Named list of file paths
#' @export
save_model_diagnostics <- function(model_result, config) {
  table_root <- config$paths$table_root
  if (is.null(table_root) || !nzchar(table_root)) table_root <- "outputs/tables"

  diagnostics_root <- config$paths$diagnostics_root
  if (is.null(diagnostics_root) || !nzchar(diagnostics_root)) diagnostics_root <- "outputs/diagnostics"

  dir.create(here::here(table_root), recursive = TRUE, showWarnings = FALSE)
  dir.create(here::here(diagnostics_root), recursive = TRUE, showWarnings = FALSE)

  model_path <- here::here(table_root, "results_model.csv")
  warnings_path <- here::here(diagnostics_root, "model_warnings.csv")

  readr::write_csv(model_result$results_model, model_path)
  readr::write_csv(model_result$warnings, warnings_path)

  cli::cli_alert_success("Saved: {model_path}")
  cli::cli_alert_success("Saved: {warnings_path}")

  list(results_model = model_path, model_warnings = warnings_path)
}

#' Run full model phase orchestration
#'
#' @param data Working dataset
#' @param selections Variable selections
#' @param config Full config
#' @return List including model results, warnings, settings, and file paths
#' @export
run_model_phase <- function(data, selections, config) {
  model_result <- run_model_suite(data, selections, config)
  file_paths <- save_model_diagnostics(model_result, config)

  list(
    settings = model_result$settings,
    results_model = model_result$results_model,
    warnings = model_result$warnings,
    failures = model_result$failures,
    file_paths = file_paths
  )
}
