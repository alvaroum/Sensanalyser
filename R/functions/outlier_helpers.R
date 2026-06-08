#' Outlier Helpers for Sensanalyser
#'
#' @description
#' Functions for Phase 3 outlier detection and policy application.
#' Outliers are detected per dependent variable and per grouping-factor
#' combination using `rstatix::identify_outliers()`.
#'
#' Supported policies:
#' - keep_all: detect and report only, no data changes
#' - remove_extreme: remove only extreme outliers
#' - remove_all: remove all detected outliers
#'
#' Supported actions:
#' - set_na: set only the outlying DV cell to NA
#' - drop_row: remove the full row if any targeted outlier is present
#'
#' @keywords internal

# ---------------------------------------------------------------------------
# DETECTION
# ---------------------------------------------------------------------------

#' Identify Sensory Outliers
#'
#' @description
#' Detects outliers for each dependent variable in `dvs`, grouped by
#' `group_factors`. Returns one long table containing all outlier flags.
#'
#' @param data A data frame with an internal `.row_id` column.
#' @param dvs Character vector of dependent variable column names.
#' @param group_factors Character vector of grouping columns used to detect
#'   outliers within each group. Use `character(0)` for global detection.
#'
#' @return A tibble with one row per tested observation and columns:
#'   - `.row_id`, `dv`, `value`, `is.outlier`, `is.extreme`
#'   - grouping factor columns (if provided)
#'
#' @export
identify_sensory_outliers <- function(data, dvs, group_factors = character(0)) {
  if (!".row_id" %in% names(data)) {
    cli::cli_abort("Internal .row_id column is missing. Run Phase 2 first.")
  }

  if (length(dvs) == 0) {
    cli::cli_abort("No dependent variables supplied for outlier detection.")
  }

  missing_dvs <- setdiff(dvs, names(data))
  if (length(missing_dvs) > 0) {
    cli::cli_abort("DV column(s) missing in data: {paste(missing_dvs, collapse = ', ')}")
  }

  missing_groups <- setdiff(group_factors, names(data))
  if (length(missing_groups) > 0) {
    cli::cli_abort("Grouping column(s) missing in data: {paste(missing_groups, collapse = ', ')}")
  }

  non_numeric_dvs <- dvs[!vapply(dvs, function(x) is.numeric(data[[x]]), logical(1))]
  if (length(non_numeric_dvs) > 0) {
    cli::cli_abort("Outlier detection requires numeric DVs. Non-numeric: {paste(non_numeric_dvs, collapse = ', ')}")
  }

  outlier_tables <- lapply(dvs, function(dv_name) {
    dv_data <- dplyr::select(data, ".row_id", dplyr::all_of(group_factors), value = dplyr::all_of(dv_name))
    dv_data <- dplyr::filter(dv_data, !is.na(.data$value))

    if (nrow(dv_data) == 0) {
      return(NULL)
    }

    detected <- tryCatch(
      {
        if (length(group_factors) > 0) {
          dv_data %>%
            dplyr::group_by(dplyr::across(dplyr::all_of(group_factors))) %>%
            rstatix::identify_outliers(value) %>%
            dplyr::ungroup()
        } else {
          rstatix::identify_outliers(dv_data, value)
        }
      },
      error = function(e) {
        cli::cli_alert_warning("Outlier detection failed for {dv_name}: {e$message}")
        NULL
      }
    )

    if (is.null(detected) || nrow(detected) == 0) {
      return(NULL)
    }

    detected %>%
      dplyr::mutate(dv = dv_name, .before = 1) %>%
      dplyr::select("dv", ".row_id", dplyr::all_of(group_factors), "value", "is.outlier", "is.extreme")
  })

  outlier_table <- dplyr::bind_rows(outlier_tables)

  if (nrow(outlier_table) == 0) {
    outlier_table <- tibble::tibble(
      dv = character(0),
      .row_id = integer(0),
      value = numeric(0),
      is.outlier = logical(0),
      is.extreme = logical(0)
    )
  }

  outlier_table
}

# ---------------------------------------------------------------------------
# POLICY APPLICATION
# ---------------------------------------------------------------------------

#' Apply Outlier Policy
#'
#' @description
#' Applies a selected outlier policy and action to the dataset.
#'
#' @param data A data frame with `.row_id`.
#' @param outlier_table Output of `identify_sensory_outliers()`.
#' @param outlier_policy Character: `keep_all`, `remove_extreme`, `remove_all`.
#' @param removal_action Character: `set_na` or `drop_row`.
#' @param apply_policy Logical. If `FALSE`, the function records which values
#'   would be targeted by the selected policy but leaves the data unchanged and
#'   marks decisions as `kept_not_applied`. This is used when
#'   `toggles$apply_outlier_policy = FALSE`.
#'
#' @return A list with:
#'   - `data`: transformed data
#'   - `policy_table`: outlier table augmented with decision columns
#'
#' @export
apply_outlier_policy <- function(data,
                                 outlier_table,
                                 outlier_policy = "remove_extreme",
                                 removal_action = "set_na",
                                 apply_policy = TRUE) {
  valid_policies <- c("keep_all", "remove_extreme", "remove_all")
  valid_actions <- c("set_na", "drop_row")

  if (!outlier_policy %in% valid_policies) {
    cli::cli_abort("Invalid outlier_policy: {outlier_policy}. Valid: {paste(valid_policies, collapse = ', ')}")
  }
  if (!removal_action %in% valid_actions) {
    cli::cli_abort("Invalid removal_action: {removal_action}. Valid: {paste(valid_actions, collapse = ', ')}")
  }

  # If no outliers were detected, return unchanged data with an empty but
  # schema-stable policy table.
  if (nrow(outlier_table) == 0) {
    policy_table <- outlier_table %>%
      dplyr::mutate(
        targeted_by_policy = logical(0),
        applied_to_data = logical(0),
        decision = character(0),
        removal_action = character(0),
        requested_outlier_policy = character(0)
      )

    return(list(data = data, policy_table = policy_table))
  }

  targeted_vec <- if (outlier_policy == "keep_all") {
    rep(FALSE, nrow(outlier_table))
  } else if (outlier_policy == "remove_extreme") {
    outlier_table$is.extreme
  } else {
    outlier_table$is.outlier
  }

  policy_table <- outlier_table %>%
    dplyr::mutate(
      targeted_by_policy = targeted_vec,
      applied_to_data = isTRUE(apply_policy) & .data$targeted_by_policy,
      decision = dplyr::case_when(
        !.data$targeted_by_policy ~ "kept",
        !isTRUE(apply_policy) ~ "kept_not_applied",
        TRUE ~ "removed"
      ),
      removal_action = removal_action,
      requested_outlier_policy = outlier_policy
    )

  # keep_all policy, or an explicit do-not-apply toggle, does not modify data.
  if (outlier_policy == "keep_all" || !isTRUE(apply_policy)) {
    return(list(data = data, policy_table = policy_table))
  }

  updated_data <- data
  targets <- policy_table %>% dplyr::filter(.data$targeted_by_policy)

  if (nrow(targets) == 0) {
    return(list(data = updated_data, policy_table = policy_table))
  }

  if (removal_action == "set_na") {
    for (i in seq_len(nrow(targets))) {
      row_id <- targets$.row_id[[i]]
      dv <- targets$dv[[i]]
      row_index <- which(updated_data$.row_id == row_id)
      if (length(row_index) == 1 && dv %in% names(updated_data)) {
        updated_data[row_index, dv] <- NA
      }
    }
  }

  if (removal_action == "drop_row") {
    drop_ids <- unique(targets$.row_id)
    updated_data <- updated_data %>% dplyr::filter(!(.data$.row_id %in% drop_ids))
  }

  list(data = updated_data, policy_table = policy_table)
}

# ---------------------------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------------------------

#' Summarise Outlier Decisions
#'
#' @description
#' Produces a compact summary table of detected outliers and policy decisions.
#'
#' @param policy_table Output policy table from `apply_outlier_policy()`.
#'
#' @return A tibble with per-DV and overall counts.
#'
#' @export
summarise_outlier_decisions <- function(policy_table) {
  if (nrow(policy_table) == 0) {
    return(tibble::tibble(
      scope = "overall",
      dv = NA_character_,
      total_flagged = 0L,
      total_outliers = 0L,
      total_extreme = 0L,
      targeted_for_removal = 0L,
      applied_to_data = 0L,
      kept = 0L,
      kept_not_applied = 0L,
      removed = 0L
    ))
  }

  per_dv <- policy_table %>%
    dplyr::group_by(.data$dv) %>%
    dplyr::summarise(
      scope = "dv",
      total_flagged = dplyr::n(),
      total_outliers = sum(.data$is.outlier, na.rm = TRUE),
      total_extreme = sum(.data$is.extreme, na.rm = TRUE),
      targeted_for_removal = sum(.data$targeted_by_policy, na.rm = TRUE),
      applied_to_data = sum(.data$applied_to_data, na.rm = TRUE),
      kept = sum(.data$decision == "kept", na.rm = TRUE),
      kept_not_applied = sum(.data$decision == "kept_not_applied", na.rm = TRUE),
      removed = sum(.data$decision == "removed", na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::relocate("scope", .before = "dv")

  overall <- policy_table %>%
    dplyr::summarise(
      scope = "overall",
      dv = NA_character_,
      total_flagged = dplyr::n(),
      total_outliers = sum(.data$is.outlier, na.rm = TRUE),
      total_extreme = sum(.data$is.extreme, na.rm = TRUE),
      targeted_for_removal = sum(.data$targeted_by_policy, na.rm = TRUE),
      applied_to_data = sum(.data$applied_to_data, na.rm = TRUE),
      kept = sum(.data$decision == "kept", na.rm = TRUE),
      kept_not_applied = sum(.data$decision == "kept_not_applied", na.rm = TRUE),
      removed = sum(.data$decision == "removed", na.rm = TRUE)
    )

  dplyr::bind_rows(overall, per_dv)
}

# ---------------------------------------------------------------------------
# ORCHESTRATOR FOR PHASE 3
# ---------------------------------------------------------------------------

#' Run Outlier Phase End-to-End
#'
#' @description
#' Convenience wrapper used by `core_engine.R`. Detects outliers, applies
#' selected policy/action, writes diagnostics CSV files, and returns updated
#' data plus summary outputs.
#'
#' @param data Working dataset.
#' @param selections Output of `select_analysis_variables()`.
#' @param config Full pipeline config list.
#'
#' @return A list with:
#'   - `data`
#'   - `outliers_all`
#'   - `policy_table`
#'   - `summary`
#'
#' @export
run_outlier_phase <- function(data, selections, config) {
  if (!".row_id" %in% names(data)) {
    data <- dplyr::mutate(data, .row_id = dplyr::row_number())
  }

  # Grouping logic: use configured grouping factors when provided,
  # otherwise default to selected fixed factors.
  group_factors <- config$analysis$outlier_grouping_factors
  if (is.null(group_factors) || length(group_factors) == 0) {
    group_factors <- selections$factors
  }

  # Policy behavior. Defaults make the function robust to older YAML configs
  # created before Phase 3 fields existed.
  outlier_policy <- config$analysis$outlier_policy
  if (is.null(outlier_policy) || !nzchar(outlier_policy)) {
    outlier_policy <- "remove_extreme"
  }

  removal_action <- config$analysis$outlier_removal_action
  if (is.null(removal_action) || !nzchar(removal_action)) {
    removal_action <- "set_na"
  }

  apply_policy <- isTRUE(config$toggles$apply_outlier_policy)

  cli::cli_h2("Phase 3: Outlier Detection")
  cli::cli_inform("Policy: {outlier_policy}")
  cli::cli_inform("Action: {removal_action}")
  cli::cli_inform("Apply policy to working data: {apply_policy}")
  cli::cli_inform("Grouping factors: {paste(group_factors, collapse = ', ')}")

  outliers_all <- identify_sensory_outliers(
    data = data,
    dvs = selections$dependent_variables,
    group_factors = group_factors
  )

  policy_result <- apply_outlier_policy(
    data = data,
    outlier_table = outliers_all,
    outlier_policy = outlier_policy,
    removal_action = removal_action,
    apply_policy = apply_policy
  )

  summary_tbl <- summarise_outlier_decisions(policy_result$policy_table)

  diagnostics_root <- config$paths$diagnostics_root
  if (is.null(diagnostics_root) || !nzchar(diagnostics_root)) {
    diagnostics_root <- "outputs/diagnostics"
  }

  dir.create(here::here(diagnostics_root), recursive = TRUE, showWarnings = FALSE)

  outliers_path <- here::here(diagnostics_root, "outliers_all.csv")
  policy_path <- here::here(diagnostics_root, "outlier_policy_applied.csv")
  summary_path <- here::here(diagnostics_root, "outlier_decision_summary.csv")

  readr::write_csv(outliers_all, outliers_path)
  readr::write_csv(policy_result$policy_table, policy_path)
  readr::write_csv(summary_tbl, summary_path)

  cli::cli_alert_success("Saved: {outliers_path}")
  cli::cli_alert_success("Saved: {policy_path}")
  cli::cli_alert_success("Saved: {summary_path}")

  list(
    data = policy_result$data,
    outliers_all = outliers_all,
    policy_table = policy_result$policy_table,
    summary = summary_tbl
  )
}
