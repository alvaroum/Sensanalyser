#' Table System for Sensanalyser
#'
#' @description
#' Phase 7 table helpers: combine Phase 4 (descriptives), Phase 5 (models),
#' and Phase 6 (post-hoc) outputs into manuscript-ready report tables with
#' optional display-name conversion from renaming_dictionary.yaml.
#'
#' Core outputs:
#' - report_format_wide.csv — manuscript table: rows = outcomes,
#'   columns = factor levels, cells = "mean ± SE" + post-hoc letter superscripts
#' - run_configuration_summary.csv — audit trail of analysis settings
#'
#' @keywords internal

# ---------------------------------------------------------------------------
# UTILITIES
# ---------------------------------------------------------------------------

#' Prepare metadata for manuscript tables
#'
#' @param config Full config
#' @return Named list with model type, method, alpha, outlier policy
#' @keywords internal
.prepare_manuscript_metadata <- function(config) {
  list(
    model_type = config$analysis$model_type,
    posthoc_method = tolower(config$analysis$posthoc_method),
    alpha = config$analysis$alpha,
    outlier_policy = config$analysis$outlier_policy
  )
}

# ---------------------------------------------------------------------------
# MANUSCRIPT TABLE BUILDERS
# ---------------------------------------------------------------------------

#' Create manuscript-style wide table: outcomes as rows, factor levels as columns
#'
#' @description
#' Joins post-hoc letters onto the descriptives, then pivots so that each row
#' is one outcome (using its display label) and each column is one factor level.
#' Cell values are "mean ± SE" with post-hoc letters appended when the omnibus
#' test was significant (e.g., "17.1 ± 5.4a").  When letters are suppressed
#' (non-significant omnibus) the cell value is just "mean ± SE".
#'
#' @param desc_long Long-format descriptives from Phase 4.  Must contain columns:
#'   outcome, outcome_display, <factor_col>, mean_se.  Factor-level values in
#'   <factor_col> must already be display-mapped (as produced by Phase 4).
#' @param letters_tbl Post-hoc letters table from Phase 6 (optional).  Factor-
#'   level values in <factor_col> are raw (un-mapped) integers or strings.
#' @param grouping_factors Character vector of grouping factor names.  The first
#'   element is used as the column-header source.
#' @param include_letters Logical.  Append post-hoc letters?
#' @param renaming_dictionary Optional dictionary list (from
#'   load_renaming_dictionary()) used to map raw factor levels in letters_tbl to
#'   display names so the join with desc_long succeeds.
#' @return Tibble with one row per outcome and one column per factor level.
#' @export
create_report_wide <- function(desc_long,
                               letters_tbl = NULL,
                               grouping_factors = NULL,
                               include_letters = TRUE,
                               renaming_dictionary = NULL) {
  if (is.null(desc_long) || nrow(desc_long) == 0) return(tibble::tibble())

  if (is.null(grouping_factors) || length(grouping_factors) == 0) {
    stat_cols <- c("outcome", "outcome_display", "n", "mean", "sd", "se", "mean_se")
    grouping_factors <- setdiff(names(desc_long), stat_cols)
  }

  factor_col <- grouping_factors[1]

  tbl <- desc_long %>%
    dplyr::select("outcome", "outcome_display", dplyr::all_of(factor_col), "mean_se")

  # Integrate post-hoc letters when available
  if (isTRUE(include_letters) &&
      !is.null(letters_tbl) && nrow(letters_tbl) > 0 &&
      factor_col %in% names(letters_tbl)) {

    letters_mapped <- letters_tbl %>%
      dplyr::filter(.data$spec == factor_col) %>%
      dplyr::select("outcome", dplyr::all_of(factor_col), ".group", "letters_suppressed") %>%
      dplyr::distinct()

    # Raw factor levels in letters_tbl → display names to match desc_long
    if (!is.null(renaming_dictionary)) {
      letters_mapped[[factor_col]] <- .apply_level_labels(
        as.character(letters_mapped[[factor_col]]), factor_col, renaming_dictionary
      )
    } else {
      letters_mapped[[factor_col]] <- as.character(letters_mapped[[factor_col]])
    }

    tbl <- tbl %>%
      dplyr::left_join(letters_mapped, by = c("outcome", factor_col)) %>%
      dplyr::mutate(
        formatted_cell = dplyr::case_when(
          !is.na(.data$letters_suppressed) &
            !.data$letters_suppressed &
            !is.na(.data$.group) ~ paste0(.data$mean_se, "^", trimws(.data$.group), "^"),
          TRUE ~ .data$mean_se
        )
      )
  } else {
    tbl <- tbl %>% dplyr::mutate(formatted_cell = .data$mean_se)
  }

  # Pivot: rows = outcomes (outcome_display), columns = factor levels
  tbl %>%
    dplyr::select("outcome_display", dplyr::all_of(factor_col), "formatted_cell") %>%
    tidyr::pivot_wider(
      names_from  = dplyr::all_of(factor_col),
      values_from = "formatted_cell"
    ) %>%
    dplyr::rename(outcome = "outcome_display")
}

#' Create mean-only wide table with post-hoc letters but without SE
#'
#' @description
#' Same orientation as create_report_wide() but cells contain only the rounded
#' mean value with post-hoc letters appended (e.g., "32.4b"), without ± SE.
#'
#' @param desc_long Long-format descriptives from Phase 4
#' @param letters_tbl Post-hoc letters table from Phase 6 (optional)
#' @param grouping_factors Character vector of grouping factor names
#' @param include_letters Logical. Append post-hoc letters?
#' @param digits Integer decimal places for rounded means
#' @param renaming_dictionary Optional dictionary list for level label mapping
#' @return Tibble with one row per outcome and one column per factor level
#' @export
create_report_wide_means <- function(desc_long,
                                     letters_tbl = NULL,
                                     grouping_factors = NULL,
                                     include_letters = TRUE,
                                     digits = 1,
                                     renaming_dictionary = NULL) {
  if (is.null(desc_long) || nrow(desc_long) == 0) return(tibble::tibble())

  if (is.null(grouping_factors) || length(grouping_factors) == 0) {
    stat_cols <- c("outcome", "outcome_display", "n", "mean", "sd", "se", "mean_se")
    grouping_factors <- setdiff(names(desc_long), stat_cols)
  }

  factor_col <- grouping_factors[1]

  tbl <- desc_long %>%
    dplyr::mutate(mean_value = as.character(round(.data$mean, digits))) %>%
    dplyr::select("outcome", "outcome_display", dplyr::all_of(factor_col), "mean_value")

  # Integrate post-hoc letters (same join logic as create_report_wide)
  if (isTRUE(include_letters) &&
      !is.null(letters_tbl) && nrow(letters_tbl) > 0 &&
      factor_col %in% names(letters_tbl)) {

    letters_mapped <- letters_tbl %>%
      dplyr::filter(.data$spec == .env$factor_col) %>%
      dplyr::select("outcome", dplyr::all_of(factor_col), ".group", "letters_suppressed") %>%
      dplyr::distinct()

    if (!is.null(renaming_dictionary)) {
      letters_mapped[[factor_col]] <- .apply_level_labels(
        as.character(letters_mapped[[factor_col]]), factor_col, renaming_dictionary
      )
    } else {
      letters_mapped[[factor_col]] <- as.character(letters_mapped[[factor_col]])
    }

    tbl <- tbl %>%
      dplyr::left_join(letters_mapped, by = c("outcome", factor_col)) %>%
      dplyr::mutate(
        formatted_cell = dplyr::case_when(
          !is.na(.data$letters_suppressed) &
            !.data$letters_suppressed &
            !is.na(.data$.group) ~ paste0(.data$mean_value, "^", trimws(.data$.group), "^"),
          TRUE ~ .data$mean_value
        )
      )
  } else {
    tbl <- tbl %>% dplyr::mutate(formatted_cell = .data$mean_value)
  }

  tbl %>%
    dplyr::select("outcome_display", dplyr::all_of(factor_col), "formatted_cell") %>%
    tidyr::pivot_wider(
      names_from  = dplyr::all_of(factor_col),
      values_from = "formatted_cell"
    ) %>%
    dplyr::rename(outcome = "outcome_display")
}

#' Create long-format manuscript table combining descriptives and model results
#'
#' @param desc_long Descriptives long table from Phase 4
#' @param results_model Model results table from Phase 5
#' @return Long tibble with descriptives and, when available, omnibus p-values
#' @export
create_manuscript_table_long <- function(desc_long, results_model = NULL) {
  if (is.null(desc_long) || nrow(desc_long) == 0) return(tibble::tibble())

  out_tbl <- desc_long

  if (!is.null(results_model) && nrow(results_model) > 0 && "p" %in% names(results_model)) {
    model_p_tbl <- results_model %>%
      dplyr::select("outcome", "term", "p") %>%
      dplyr::distinct() %>%
      dplyr::group_by(.data$outcome) %>%
      dplyr::slice(1) %>%
      dplyr::ungroup() %>%
      dplyr::select("outcome", omnibus_p = "p")

    out_tbl <- out_tbl %>%
      dplyr::left_join(model_p_tbl, by = "outcome")
  }

  out_tbl
}

# ---------------------------------------------------------------------------
# CONFIGURATION SUMMARY
# ---------------------------------------------------------------------------

#' Write analysis configuration summary
#'
#' @param selections Variable selections from Phase 2
#' @param config Full pipeline config
#' @param model_result Phase 5 results (optional)
#' @param posthoc_result Phase 6 results (optional)
#' @return Tibble with configuration details
#' @export
create_run_configuration_summary <- function(selections, config,
                                             model_result = NULL,
                                             posthoc_result = NULL) {
  tibble::tibble(
    run_date                 = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    data_file                = config$paths$raw_data %||% "not set",
    dependent_variables      = paste(selections$dependent_variables, collapse = "; "),
    fixed_factors            = paste(selections$factors, collapse = "; "),
    subject_id               = selections$subject_id %||% "none",
    repeated_measures_factors = paste(selections$repeated_measures_factors %||% character(0),
                                      collapse = "; "),
    model_type               = config$analysis$model_type,
    outlier_policy           = config$analysis$outlier_policy,
    outlier_removal_action   = config$analysis$outlier_removal_action,
    posthoc_method           = config$analysis$posthoc_method,
    posthoc_focal_terms      = paste(config$analysis$posthoc_focal_terms %||% "all significant",
                                     collapse = "; "),
    alpha                    = config$analysis$alpha,
    run_outlier_detection    = config$toggles$run_outlier_detection,
    apply_outlier_policy     = config$toggles$apply_outlier_policy,
    run_descriptives         = config$toggles$run_descriptives,
    run_anova_models         = config$toggles$run_anova_models,
    run_mixed_models         = config$toggles$run_mixed_models,
    run_posthoc              = config$toggles$run_posthoc,
    n_outcomes_analyzed      = if (!is.null(model_result) &&
                                   !is.null(model_result$results_model)) {
      dplyr::n_distinct(model_result$results_model$outcome)
    } else {
      length(selections$dependent_variables)
    },
    n_posthoc_comparisons    = if (!is.null(posthoc_result) &&
                                   !is.null(posthoc_result$posthoc_pairwise)) {
      nrow(posthoc_result$posthoc_pairwise)
    } else {
      0L
    }
  )
}

# ---------------------------------------------------------------------------
# ORCHESTRATORS
# ---------------------------------------------------------------------------

#' Save all Phase 7 tables and return computed results
#'
#' @param config Full config
#' @param desc_long Long descriptives from Phase 4
#' @param results_model Model results from Phase 5
#' @param posthoc_result Post-hoc results from Phase 6
#' @param selections Variable selections from Phase 2
#' @return Named list: report_format_wide, run_configuration_summary, file_paths
#' @export
save_analysis_tables <- function(config,
                                 desc_long = NULL,
                                 results_model = NULL,
                                 posthoc_result = NULL,
                                 selections = NULL) {
  table_root <- config$paths$table_root
  if (is.null(table_root) || !nzchar(table_root)) table_root <- "outputs/tables"
  dir.create(here::here(table_root), recursive = TRUE, showWarnings = FALSE)

  # Load renaming dictionary for display-name mapping of factor levels in letters
  dict <- if (!is.null(config$paths$renaming_dictionary)) {
    load_renaming_dictionary(config$paths$renaming_dictionary)
  } else {
    list(variables = list(), levels = list(), outcomes = list())
  }

  file_list         <- list()
  report_wide       <- NULL
  report_wide_means <- NULL
  config_summ       <- NULL

  # ── Report-format wide table (outcomes as rows, factor levels as columns) ──
  if (!is.null(desc_long) && nrow(desc_long) > 0) {
    grouping_factors <- config$analysis$descriptive_grouping_factors
    if (is.null(grouping_factors) || length(grouping_factors) == 0) {
      grouping_factors <- selections$factors
    }

    report_wide <- create_report_wide(
      desc_long          = desc_long,
      letters_tbl        = if (!is.null(posthoc_result)) posthoc_result$posthoc_letters else NULL,
      grouping_factors   = grouping_factors,
      include_letters    = TRUE,
      renaming_dictionary = dict
    )

    report_wide_path <- here::here(table_root, "report_format_wide.csv")
    readr::write_csv(report_wide, report_wide_path)
    cli::cli_alert_success("Saved: {report_wide_path}")
    file_list$report_format_wide <- report_wide_path

    # Mean-only table (letters shown, SE omitted)
    digits <- config$table_options$digits
    if (is.null(digits) || length(digits) == 0 || is.na(digits)) digits <- 1L

    report_wide_means <- create_report_wide_means(
      desc_long           = desc_long,
      letters_tbl         = if (!is.null(posthoc_result)) posthoc_result$posthoc_letters else NULL,
      grouping_factors    = grouping_factors,
      include_letters     = TRUE,
      digits              = digits,
      renaming_dictionary = dict
    )

    means_path <- here::here(table_root, "report_format_wide_means.csv")
    readr::write_csv(report_wide_means, means_path)
    cli::cli_alert_success("Saved: {means_path}")
    file_list$report_format_wide_means <- means_path
  }

  # ── Configuration summary ─────────────────────────────────────────────────
  if (!is.null(selections)) {
    config_summ <- create_run_configuration_summary(
      selections    = selections,
      config        = config,
      model_result  = if (!is.null(results_model)) list(results_model = results_model) else NULL,
      posthoc_result = posthoc_result
    )

    config_path <- here::here(table_root, "run_configuration_summary.csv")
    readr::write_csv(config_summ, config_path)
    cli::cli_alert_success("Saved: {config_path}")
    file_list$run_configuration_summary <- config_path
  }

  list(
    report_format_wide        = report_wide,
    report_format_wide_means  = report_wide_means,
    run_configuration_summary = config_summ,
    file_paths                = file_list
  )
}

#' Run full Phase 7 table orchestration
#'
#' @param pipeline_state Full pipeline state
#' @return Named list: report_format_wide, run_configuration_summary, file_paths
#' @export
run_table_phase <- function(pipeline_state) {
  cli::cli_h2("Phase 7: Table System")

  config       <- pipeline_state$config
  selections   <- pipeline_state$selections
  desc_result  <- pipeline_state$results$descriptives
  model_result <- pipeline_state$results$models
  posthoc_result <- pipeline_state$results$posthoc

  desc_long     <- if (!is.null(desc_result))  desc_result$descriptives_long  else NULL
  results_model <- if (!is.null(model_result)) model_result$results_model      else NULL

  result <- save_analysis_tables(
    config         = config,
    desc_long      = desc_long,
    results_model  = results_model,
    posthoc_result = posthoc_result,
    selections     = selections
  )

  result
}

# ---------------------------------------------------------------------------
# REPORT TABLE FORMATTING AND RENDERING
# ---------------------------------------------------------------------------

#' Format column cells element-wise with superscript using flextable
#'
#' @keywords internal
.compose_superscript_col <- function(ft, col, base_part, letter_part) {
  flextable::compose(
    x = ft,
    j = col,
    value = flextable::as_paragraph(
      base_part,
      flextable::as_sup(letter_part)
    )
  )
}

#' Render executive table with superscript post-hoc letters
#'
#' @param tbl Tibble or data frame to render
#' @param title Optional caption/title
#' @param digits Number of digits to round numeric columns
#' @return A flextable or kable object
#' @export
render_executive_table <- function(tbl, title = NULL, digits = 2) {
  if (is.null(tbl) || nrow(tbl) == 0) {
    return("No data available for this section.")
  }

  tbl_formatted <- tbl |>
    dplyr::mutate(dplyr::across(
      dplyr::where(is.numeric) & !dplyr::any_of(c("p", "DFn", "DFd", "df", "n")),
      ~ round(.x, digits)
    ))

  if (requireNamespace("flextable", quietly = TRUE)) {
    ft <- flextable::flextable(tbl_formatted) |>
      flextable::theme_booktabs() |>
      flextable::autofit() |>
      flextable::fontsize(size = 10, part = "all") |>
      flextable::bold(part = "header") |>
      flextable::align(align = "left", part = "all")

    cols_to_check <- names(tbl_formatted)[-1]
    for (col in cols_to_check) {
      vals <- as.character(tbl_formatted[[col]])
      
      # Check if any value contains the caret superscript pattern, e.g. "^a^" at the end
      if (any(grepl("\\^[a-zA-Z]+\\^$", vals))) {
        has_letters <- grepl("\\^[a-zA-Z]+\\^$", vals)
        base_part <- ifelse(has_letters, sub("\\^[a-zA-Z]+\\^$", "", vals), vals)
        letter_part <- ifelse(has_letters, gsub(".*\\^([a-zA-Z]+)\\^$", "\\1", vals), "")
        
        ft <- .compose_superscript_col(ft, col, base_part, letter_part)
      } else if (any(grepl("[a-zA-Z]+$", vals))) {
        # Fallback for plain letter suffixes (e.g. "a" at the end)
        has_letters <- grepl("[a-zA-Z]+$", vals)
        base_part <- ifelse(has_letters, sub("[a-zA-Z]+$", "", vals), vals)
        letter_part <- ifelse(has_letters, regmatches(vals, regexpr("[a-zA-Z]+$", vals)), "")
        
        ft <- .compose_superscript_col(ft, col, base_part, letter_part)
      }
    }

    num_cols <- names(tbl_formatted)[sapply(tbl_formatted, is.numeric)]
    if (length(num_cols) > 0) {
      ft <- ft |> flextable::align(j = num_cols, align = "right", part = "all")
    }

    p_col <- grep("p-value|^p$", names(tbl_formatted), value = TRUE)
    if (length(p_col) > 0) {
      p_col_name <- p_col[1]
      sig_rows <- which(as.numeric(tbl[[p_col_name]]) < 0.05)
      if (length(sig_rows) > 0) {
        ft <- ft |>
          flextable::bold(i = sig_rows, j = p_col_name, part = "body") |>
          flextable::color(i = sig_rows, j = p_col_name, color = "#2c6b35", part = "body")
      }
    }

    if (!is.null(title)) {
      ft <- ft |> flextable::set_caption(title)
    }
    return(ft)
  }

  knitr::kable(tbl_formatted, caption = title, digits = digits)
}
