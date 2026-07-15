#' Post-hoc Helpers for Sensanalyser
#'
#' @description
#' Phase 6 post-hoc engine built on top of Phase 5 model settings.
#' Supports Tukey, Bonferroni, and Fisher LSD workflows using emmeans,
#' with compact letter displays and cautious suppression when the matching
#' omnibus term is non-significant.
#'
#' @keywords internal

# ---------------------------------------------------------------------------
# SPEC PARSING
# ---------------------------------------------------------------------------

#' Parse one post-hoc focal term into executable specs
#'
#' @param term Character focal term (e.g. product, product|age, product:age)
#' @return List of spec records
#' @keywords internal
.parse_posthoc_term <- function(term) {
  if (grepl("\\|", term)) {
    parts <- strsplit(term, "\\|", fixed = FALSE)[[1]]
    spec <- trimws(parts[1])
    by <- trimws(parts[2])
    return(list(list(requested_term = term, spec = spec, by = by, omnibus_term = paste(spec, by, sep = ":"))))
  }

  if (grepl(":", term, fixed = TRUE)) {
    parts <- trimws(strsplit(term, ":", fixed = TRUE)[[1]])
    if (length(parts) == 2) {
      return(list(
        list(requested_term = term, spec = parts[1], by = parts[2], omnibus_term = term),
        list(requested_term = term, spec = parts[2], by = parts[1], omnibus_term = term)
      ))
    }
  }

  list(list(requested_term = term, spec = term, by = NULL, omnibus_term = term))
}

#' Derive post-hoc focal terms from model results when not explicitly set
#'
#' @param results_model Results table from Phase 5
#' @param alpha Significance threshold
#' @return Named list outcome -> character vector of focal terms
#' @keywords internal
.derive_focal_terms <- function(results_model, alpha) {
  if (nrow(results_model) == 0 || !all(c("outcome", "term", "p") %in% names(results_model))) {
    return(list())
  }

  valid_rows <- results_model %>%
    dplyr::filter(!is.na(.data$p)) %>%
    dplyr::filter(.data$p < alpha) %>%
    dplyr::filter(!grepl("Intercept|Residual|Error", .data$term, ignore.case = TRUE))

  split(valid_rows$term, valid_rows$outcome)
}

#' Find omnibus p-value for one outcome and term
#'
#' @param results_model Phase 5 results_model table
#' @param outcome Outcome name
#' @param omnibus_term Matching model term
#' @return Numeric p-value or NA_real_
#' @keywords internal
.get_omnibus_p <- function(results_model, outcome, omnibus_term) {
  if (is.null(results_model) || nrow(results_model) == 0 ||
      !all(c("outcome", "term") %in% names(results_model))) {
    return(NA_real_)
  }
  # Match interaction terms regardless of the order their components are written
  # in (e.g. "product:session" vs "session:product"), which differs between the
  # ANOVA table and the requested focal term.
  norm <- function(t) vapply(
    strsplit(as.character(t), ":", fixed = TRUE),
    function(parts) paste(sort(trimws(parts)), collapse = ":"),
    character(1)
  )
  hit <- results_model[
    results_model$outcome == outcome & norm(results_model$term) == norm(omnibus_term),
    , drop = FALSE
  ]
  if (nrow(hit) == 0 || !"p" %in% names(hit)) return(NA_real_)
  suppressWarnings(as.numeric(hit$p[[1]]))
}

# ---------------------------------------------------------------------------
# LETTER DISPLAY
# ---------------------------------------------------------------------------

#' Create compact letter display from emmeans results and pairwise p-values
#'
#' @param emm_grid emmeans object
#' @param pairwise_tbl Pairwise comparison tibble from emmeans::contrast summary
#' @param spec Factor being contrasted
#' @param by Optional by-factor name
#' @param alpha Significance threshold used for letter grouping.
#' @return Tibble with letters and estimated means
#' @export
create_compact_letter_display <- function(emm_grid, pairwise_tbl, spec, by = NULL, alpha = 0.05) {
  emm_tbl <- tibble::as_tibble(summary(emm_grid))

  if (!spec %in% names(emm_tbl)) {
    cli::cli_abort("Cannot create letter display: spec column '{spec}' not present in emmeans summary.")
  }

  build_letters_for_slice <- function(pair_slice, level_values) {
    if (nrow(pair_slice) == 0) {
      return(stats::setNames(rep("a", length(level_values)), level_values))
    }

    cmp_vec <- stats::setNames(pair_slice$p.value, gsub(" - ", "-", pair_slice$contrast, fixed = TRUE))
    letter_result <- multcompView::multcompLetters(cmp_vec, threshold = alpha)$Letters

    # emmeans prepends the factor name to numeric level values in contrast labels
    # (e.g. "product1 - product2" → key "product1" in the letter map).
    # Strip the prefix so keys match the bare level values in emm_tbl.
    names(letter_result) <- sub(paste0("^", spec), "", names(letter_result))

    letter_result
  }

  if (is.null(by) || !nzchar(by) || !by %in% names(emm_tbl)) {
    levels_all <- as.character(emm_tbl[[spec]])
    letter_map <- build_letters_for_slice(pairwise_tbl, levels_all)
    emm_tbl$.group <- unname(letter_map[as.character(emm_tbl[[spec]])])
    return(emm_tbl)
  }

  slices <- split(emm_tbl, emm_tbl[[by]], drop = TRUE)
  out <- lapply(names(slices), function(by_level) {
    emm_slice <- slices[[by_level]]
    pair_slice <- pairwise_tbl[pairwise_tbl[[by]] == by_level, , drop = FALSE]
    level_values <- as.character(emm_slice[[spec]])
    letter_map <- build_letters_for_slice(pair_slice, level_values)
    emm_slice$.group <- unname(letter_map[as.character(emm_slice[[spec]])])
    emm_slice
  })

  dplyr::bind_rows(out)
}

#' Suppress letters when omnibus term is not significant
#'
#' @param letters_tbl Letter table
#' @param omnibus_p Numeric p-value
#' @param alpha Significance threshold
#' @return Letter table with suppression columns
#' @export
suppress_non_significant_letters <- function(letters_tbl, omnibus_p, alpha = 0.05) {
  omnibus_known       <- !is.na(omnibus_p)
  omnibus_significant <- omnibus_known && omnibus_p < alpha

  # Only suppress the compact-letter display when we positively know the omnibus
  # factor is non-significant. If the omnibus p-value could not be located
  # (NA — e.g. a term-name mismatch), keep the pairwise-derived letters rather
  # than dropping them silently, which previously hid significant differences.
  suppress <- isTRUE(omnibus_known && !omnibus_significant)

  # A single omnibus p-value gates the whole table, so set the columns directly
  # (avoids vctrs size-recycling issues with a scalar condition in if_else).
  letters_tbl$omnibus_p           <- omnibus_p
  letters_tbl$omnibus_significant <- omnibus_significant
  letters_tbl$letters_suppressed  <- suppress
  if (suppress) {
    letters_tbl$.group             <- NA_character_
    letters_tbl$suppression_reason <- "Omnibus term non-significant"
  } else {
    letters_tbl$suppression_reason <- NA_character_
  }
  letters_tbl
}

# ---------------------------------------------------------------------------
# POST-HOC RUNNERS
# ---------------------------------------------------------------------------

#' Run emmeans-based post-hoc comparisons
#'
#' @param model_object Fitted model object
#' @param outcome Outcome name
#' @param spec Factor being contrasted
#' @param by Optional by-factor for conditional post-hoc
#' @param method tukey or bonferroni or lsd
#' @param omnibus_p Numeric omnibus p-value
#' @param alpha Significance threshold
#' @return List(pairwise, letters, summary)
#' @export
run_emmeans_posthoc <- function(model_object,
                                outcome,
                                spec,
                                by = NULL,
                                method = "tukey",
                                omnibus_p = NA_real_,
                                alpha = 0.05,
                                requested_term = spec,
                                omnibus_term = spec) {
  adjust <- switch(
    tolower(method),
    tukey = "tukey",
    bonferroni = "bonferroni",
    lsd = "none",
    "tukey"
  )

  emm <- if (is.null(by)) {
    emmeans::emmeans(model_object, specs = spec)
  } else {
    emmeans::emmeans(model_object, specs = spec, by = by)
  }

  pair_tbl <- summary(emmeans::contrast(emm, method = "pairwise", adjust = adjust), infer = TRUE) %>%
    tibble::as_tibble() %>%
    dplyr::mutate(
      outcome = outcome,
      requested_term = requested_term,
      spec = spec,
      by = if (is.null(by)) NA_character_ else by,
      omnibus_term = omnibus_term,
      method = tolower(method),
      adjust = adjust,
      omnibus_p = omnibus_p,
      omnibus_significant = !is.na(omnibus_p) & omnibus_p < alpha,
      .before = 1
    )

  letters_tbl <- create_compact_letter_display(emm, pair_tbl, spec = spec, by = by, alpha = alpha) %>%
    suppress_non_significant_letters(omnibus_p = omnibus_p, alpha = alpha) %>%
    dplyr::mutate(
      outcome = outcome,
      requested_term = requested_term,
      spec = spec,
      by = if (is.null(by)) NA_character_ else by,
      omnibus_term = omnibus_term,
      method = tolower(method),
      adjust = adjust,
      .before = 1
    )

  summary_tbl <- tibble::tibble(
    outcome = outcome,
    requested_term = requested_term,
    spec = spec,
    by = if (is.null(by)) NA_character_ else by,
    omnibus_term = omnibus_term,
    omnibus_p = omnibus_p,
    omnibus_significant = !is.na(omnibus_p) & omnibus_p < alpha,
    method = tolower(method),
    adjust = adjust,
    letters_suppressed = all(is.na(letters_tbl$.group)),
    n_pairwise_rows = nrow(pair_tbl),
    n_letter_rows = nrow(letters_tbl)
  )

  list(pairwise = pair_tbl, letters = letters_tbl, summary = summary_tbl)
}

#' Run Fisher LSD post-hoc
#'
#' @param model_object Fitted model object
#' @param outcome Outcome name
#' @param spec Factor being contrasted
#' @param by Optional by-factor
#' @param omnibus_p Numeric omnibus p-value
#' @param alpha Significance threshold
#' @return List(pairwise, letters, summary)
#' @export
run_lsd_posthoc <- function(model_object,
                            outcome,
                            spec,
                            by = NULL,
                            omnibus_p = NA_real_,
                            alpha = 0.05,
                            requested_term = spec,
                            omnibus_term = spec) {
  run_emmeans_posthoc(
    model_object = model_object,
    outcome = outcome,
    spec = spec,
    by = by,
    method = "lsd",
    omnibus_p = omnibus_p,
    alpha = alpha,
    requested_term = requested_term,
    omnibus_term = omnibus_term
  )
}

# ---------------------------------------------------------------------------
# SUITE
# ---------------------------------------------------------------------------

#' Run post-hoc suite across all requested outcomes/terms
#'
#' @param data Working data
#' @param selections Phase 2 selections
#' @param config Full config
#' @param model_result Optional Phase 5 results list
#' @return List(pairwise, letters, method_summary)
#' @export
run_posthoc_suite <- function(data, selections, config, model_result = NULL) {
  cli::cli_h2("Phase 6: Post-hoc Tests")

  if (is.null(model_result)) {
    model_result <- run_model_phase(data, selections, config)
  }

  settings <- resolve_model_settings(config, selections)
  results_model <- model_result$results_model
  alpha <- config$analysis$alpha
  if (is.null(alpha) || length(alpha) == 0 || is.na(alpha)) alpha <- 0.05

  method <- config$analysis$posthoc_method
  if (is.null(method) || length(method) == 0 || !nzchar(method)) method <- "tukey"
  method <- tolower(method)
  valid_methods <- c("tukey", "bonferroni", "lsd")
  if (!method %in% valid_methods) {
    cli::cli_abort("Invalid posthoc_method: {method}. Valid options: {paste(valid_methods, collapse = ', ')}")
  }

  # Ensure any design columns used only through model_fixed_effects are treated
  # as factors during the refit for emmeans. This mirrors the Phase 5 model
  # suite behaviour and avoids numeric covariate handling for coded factors.
  design_cols <- unique(c(settings$fixed_effects, settings$repeated_measures_factors, settings$random_effects, selections$subject_id))
  design_cols <- design_cols[!is.na(design_cols) & nzchar(design_cols) & design_cols %in% names(data)]
  for (col in design_cols) {
    data[[col]] <- as.factor(data[[col]])
  }

  explicit_terms <- config$analysis$posthoc_focal_terms
  derived_terms <- .derive_focal_terms(results_model, alpha)

  pairwise_out <- list()
  letters_out <- list()
  summary_out <- list()

  for (outcome in selections$dependent_variables) {
    focal_terms <- if (!is.null(explicit_terms) && length(explicit_terms) > 0) {
      explicit_terms
    } else {
      derived_terms[[outcome]]
    }

    if (is.null(focal_terms) || length(focal_terms) == 0) {
      next
    }

    fit_result <- tryCatch(
      run_model_for_outcome(data, outcome, settings, selections),
      error = function(e) NULL
    )

    if (is.null(fit_result) || is.null(fit_result$model_object)) {
      next
    }

    for (term in focal_terms) {
      spec_records <- .parse_posthoc_term(term)

      for (rec in spec_records) {
        omnibus_p <- .get_omnibus_p(results_model, outcome, rec$omnibus_term)

        one_result <- tryCatch(
          {
            if (method == "lsd") {
              run_lsd_posthoc(
                model_object = fit_result$model_object,
                outcome = outcome,
                spec = rec$spec,
                by = rec$by,
                omnibus_p = omnibus_p,
                alpha = alpha,
                requested_term = rec$requested_term,
                omnibus_term = rec$omnibus_term
              )
            } else {
              run_emmeans_posthoc(
                model_object = fit_result$model_object,
                outcome = outcome,
                spec = rec$spec,
                by = rec$by,
                method = method,
                omnibus_p = omnibus_p,
                alpha = alpha,
                requested_term = rec$requested_term,
                omnibus_term = rec$omnibus_term
              )
            }
          },
          error = function(e) {
            tibble_warn <- tibble::tibble(
              outcome = outcome,
              requested_term = rec$requested_term,
              spec = rec$spec,
              by = if (is.null(rec$by)) NA_character_ else rec$by,
              omnibus_term = rec$omnibus_term,
              omnibus_p = omnibus_p,
              omnibus_significant = !is.na(omnibus_p) & omnibus_p < alpha,
              method = method,
              adjust = if (method == "lsd") "none" else method,
              letters_suppressed = NA,
              n_pairwise_rows = 0L,
              n_letter_rows = 0L,
              error = conditionMessage(e)
            )
            list(pairwise = tibble::tibble(), letters = tibble::tibble(), summary = tibble_warn)
          }
        )

        pairwise_out[[length(pairwise_out) + 1]] <- one_result$pairwise
        letters_out[[length(letters_out) + 1]] <- one_result$letters
        summary_out[[length(summary_out) + 1]] <- one_result$summary
      }
    }
  }

  pairwise_tbl <- dplyr::bind_rows(pairwise_out)
  letters_tbl <- dplyr::bind_rows(letters_out)
  summary_tbl <- dplyr::bind_rows(summary_out)

  list(
    posthoc_pairwise = pairwise_tbl,
    posthoc_letters = letters_tbl,
    posthoc_method_summary = summary_tbl
  )
}

# ---------------------------------------------------------------------------
# OUTPUTS
# ---------------------------------------------------------------------------

#' Save post-hoc outputs
#'
#' @param posthoc_result Output of run_posthoc_suite
#' @param config Full config
#' @return Named list of file paths
#' @export
save_posthoc_outputs <- function(posthoc_result, config) {
  table_root <- config$paths$table_root
  if (is.null(table_root) || !nzchar(table_root)) table_root <- "outputs/tables"
  dir.create(here::here(table_root), recursive = TRUE, showWarnings = FALSE)

  pairwise_path <- here::here(table_root, "posthoc_pairwise.csv")
  letters_path <- here::here(table_root, "posthoc_letters.csv")
  summary_path <- here::here(table_root, "posthoc_method_summary.csv")

  readr::write_csv(posthoc_result$posthoc_pairwise, pairwise_path)
  readr::write_csv(posthoc_result$posthoc_letters, letters_path)
  readr::write_csv(posthoc_result$posthoc_method_summary, summary_path)

  cli::cli_alert_success("Saved: {pairwise_path}")
  cli::cli_alert_success("Saved: {letters_path}")
  cli::cli_alert_success("Saved: {summary_path}")

  list(
    posthoc_pairwise = pairwise_path,
    posthoc_letters = letters_path,
    posthoc_method_summary = summary_path
  )
}

#' Run full Phase 6 orchestration
#'
#' @param data Working data
#' @param selections Variable selections
#' @param config Full config
#' @param model_result Optional Phase 5 results list
#' @return List with posthoc outputs and paths
#' @export
run_posthoc_phase <- function(data, selections, config, model_result = NULL) {
  posthoc_result <- run_posthoc_suite(data, selections, config, model_result)
  file_paths <- save_posthoc_outputs(posthoc_result, config)

  c(posthoc_result, list(file_paths = file_paths))
}
