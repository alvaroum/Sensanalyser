#' MFA Helpers for Sensanalyser
#'
#' @description
#' Phase 8 MFA module. Supports configurable variable groups and exports
#' MFA result tables, individuals map, and variables correlation circle.
#'
#' @keywords internal

#' Normalize MFA group specification
#'
#' @param groups_raw Raw group definition
#' @param available_vars Character vector of available variable names
#' @return Named list of character vectors
#' @keywords internal
.normalize_mfa_groups <- function(groups_raw, available_vars) {
  if (is.null(groups_raw)) return(NULL)

  out <- list()

  if (is.list(groups_raw) && !is.null(names(groups_raw)) && all(nzchar(names(groups_raw)))) {
    for (nm in names(groups_raw)) {
      vars <- as.character(groups_raw[[nm]])
      vars <- intersect(vars, available_vars)
      if (length(vars) > 0) out[[nm]] <- vars
    }
    if (length(out) > 0) return(out)
  }

  if (is.list(groups_raw)) {
    for (g in groups_raw) {
      if (is.list(g) && !is.null(g$name) && !is.null(g$variables)) {
        nm   <- as.character(g$name)[1]
        vars <- intersect(as.character(g$variables), available_vars)
        if (nzchar(nm) && length(vars) > 0) out[[nm]] <- vars
      }
    }
    if (length(out) > 0) return(out)
  }

  NULL
}

#' Resolve MFA groups from config or auto-detection
#'
#' @param data_means Aggregated means data frame (numeric only, no grouping column)
#' @param selections Variable selection list
#' @param config Full config
#' @return Named list of variable groups
#' @keywords internal
.resolve_mfa_groups <- function(data_means, selections, config) {
  vars_available <- names(data_means)

  cfg_groups <- .normalize_mfa_groups(config$analysis$mfa_groups, vars_available)
  if (!is.null(cfg_groups)) return(cfg_groups)

  yaml_path <- config$paths$mfa_groups
  if (!is.null(yaml_path) && nzchar(yaml_path) && file.exists(yaml_path)) {
    yml <- yaml::read_yaml(yaml_path)
    yml_groups <- .normalize_mfa_groups(yml$groups, vars_available)
    if (!is.null(yml_groups)) return(yml_groups)
  }

  dv_group <- intersect(selections$dependent_variables, vars_available)
  others   <- setdiff(vars_available, dv_group)
  others   <- others[seq_len(min(length(others), 4))]

  if (length(dv_group) >= 2 && length(others) >= 1) {
    return(list(
      Sensory_attributes = dv_group,
      Instrumental_proxy = others
    ))
  }

  if (length(dv_group) >= 4) {
    mid <- ceiling(length(dv_group) / 2)
    return(list(
      Sensory_group_1 = dv_group[seq_len(mid)],
      Sensory_group_2 = dv_group[(mid + 1):length(dv_group)]
    ))
  }

  list()
}

#' Run sensory MFA
#'
#' @param data Working dataset
#' @param selections Variable selections
#' @param config Full config list
#' @return List with MFA object, tables, and file paths
#' @export
run_sensory_mfa <- function(data, selections, config) {
  if (!isTRUE(config$toggles$run_mfa)) {
    return(list(skipped = TRUE, reason = "run_mfa is FALSE"))
  }

  cli::cli_h3("Phase 8C: MFA")

  grouping_factor <- selections$factors[[1]]
  if (is.null(grouping_factor) || !grouping_factor %in% names(data)) {
    cli::cli_alert_warning("Skipping MFA: no valid grouping factor available.")
    return(list(skipped = TRUE, reason = "No valid grouping factor"))
  }

  numeric_cols <- intersect(
    selections$dependent_variables,
    names(data)[vapply(data, is.numeric, logical(1))]
  )
  if (length(numeric_cols) < 3) {
    cli::cli_alert_warning("Skipping MFA: insufficient numeric dependent variables.")
    return(list(skipped = TRUE, reason = "Insufficient numeric variables"))
  }

  data_means <- data %>%
    dplyr::group_by(.data[[grouping_factor]]) %>%
    dplyr::summarise(dplyr::across(dplyr::all_of(numeric_cols), ~ mean(.x, na.rm = TRUE)),
                     .groups = "drop")

  # Map raw group codes to display names
  dict <- if (!is.null(config$paths$renaming_dictionary) &&
               file.exists(config$paths$renaming_dictionary)) {
    load_renaming_dictionary(config$paths$renaming_dictionary)
  } else {
    list(variables = list(), levels = list(), outcomes = list())
  }
  row_ids <- .apply_level_labels(
    as.character(data_means[[grouping_factor]]), grouping_factor, dict
  )

  data_means <- data_means %>% dplyr::select(-dplyr::all_of(grouping_factor))
  data_means <- as.data.frame(data_means)
  rownames(data_means) <- row_ids

  groups <- .resolve_mfa_groups(data_means, selections, config)
  groups <- groups[lengths(groups) > 0]

  if (length(groups) < 2) {
    cli::cli_alert_warning("Skipping MFA: could not resolve at least 2 variable groups.")
    return(list(skipped = TRUE, reason = "Could not resolve >=2 MFA groups"))
  }

  mfa_vars  <- unique(unlist(groups, use.names = FALSE))
  mfa_input <- data_means %>% dplyr::select(dplyr::all_of(mfa_vars))
  colnames(mfa_input) <- .apply_outcome_labels(colnames(mfa_input), dict)

  group_sizes <- as.integer(lengths(groups))
  group_names <- names(groups)

  mfa_fit <- FactoMineR::MFA(
    mfa_input,
    group      = group_sizes,
    type       = rep("s", length(group_sizes)),
    name.group = group_names,
    graph      = FALSE
  )

  eig <- tibble::as_tibble(mfa_fit$eig)
  names(eig)[1:3] <- c("eigenvalue", "variance_percent", "cumulative_percent")
  eig <- eig %>%
    dplyr::mutate(component = paste0("Dim", dplyr::row_number())) %>%
    dplyr::select("component", dplyr::everything())

  ind_coord <- tibble::as_tibble(mfa_fit$ind$coord,        rownames = "group_level")
  var_coord <- tibble::as_tibble(mfa_fit$quanti.var$coord,  rownames = "variable")

  table_root  <- config$paths$table_root
  if (is.null(table_root)  || !nzchar(table_root))  table_root  <- "outputs/tables"
  figure_root <- config$paths$figure_root
  if (is.null(figure_root) || !nzchar(figure_root)) figure_root <- "outputs/figures"

  dir.create(here::here(table_root,  "mfa"), recursive = TRUE, showWarnings = FALSE)
  dir.create(here::here(figure_root, "mfa"), recursive = TRUE, showWarnings = FALSE)

  eig_path    <- here::here(table_root,  "mfa", "mfa_eigenvalues.csv")
  ind_path    <- here::here(table_root,  "mfa", "mfa_individual_coordinates.csv")
  var_path    <- here::here(table_root,  "mfa", "mfa_variable_coordinates.csv")
  groups_path <- here::here(table_root,  "mfa", "mfa_group_specification.csv")
  fig_ind     <- here::here(figure_root, "mfa", "mfa_individuals.png")
  fig_var     <- here::here(figure_root, "mfa", "mfa_variables.png")

  readr::write_csv(eig,       eig_path)
  readr::write_csv(ind_coord, ind_path)
  readr::write_csv(var_coord, var_path)

  groups_tbl <- tibble::tibble(
    group_name    = rep(group_names, times = group_sizes),
    variable_raw  = unlist(groups, use.names = FALSE),
    variable      = .apply_outcome_labels(unlist(groups, use.names = FALSE), dict)
  )
  readr::write_csv(groups_tbl, groups_path)

  width  <- config$fig_options$width;  if (is.null(width)  || is.na(width))  width  <- 9
  height <- config$fig_options$height; if (is.null(height) || is.na(height)) height <- 6
  dpi    <- config$fig_options$dpi;    if (is.null(dpi)    || is.na(dpi))    dpi    <- 300

  # ── Individuals map ──────────────────────────────────────────────────────────
  mfa_ind_plot <- factoextra::fviz_mfa_ind(
    mfa_fit,
    repel   = TRUE,
    col.ind = "#2C7FB8"
  ) + ggplot2::ggtitle("MFA – Individuals")

  ggplot2::ggsave(filename = fig_ind, plot = mfa_ind_plot,
                  width = width, height = height, dpi = dpi)

  # ── Variables correlation circle ─────────────────────────────────────────────
  mfa_var_plot <- factoextra::fviz_mfa_var(
    mfa_fit,
    "quanti.var",
    repel      = TRUE,
    col.var    = "#D95F02",
    col.circle = "grey70"
  ) + ggplot2::ggtitle("MFA – Variables")

  ggplot2::ggsave(filename = fig_var, plot = mfa_var_plot,
                  width = width, height = height, dpi = dpi)

  cli::cli_alert_success("Saved: {eig_path}")
  cli::cli_alert_success("Saved: {ind_path}")
  cli::cli_alert_success("Saved: {var_path}")
  cli::cli_alert_success("Saved: {groups_path}")
  cli::cli_alert_success("Saved: {fig_ind}")
  cli::cli_alert_success("Saved: {fig_var}")

  list(
    skipped                = FALSE,
    mfa_object             = mfa_fit,
    eigenvalues            = eig,
    individual_coordinates = ind_coord,
    variable_coordinates   = var_coord,
    groups                 = groups,
    file_paths = list(
      eigenvalues            = eig_path,
      individual_coordinates = ind_path,
      variable_coordinates   = var_path,
      group_specification    = groups_path,
      individuals_plot       = fig_ind,
      variables_plot         = fig_var
    )
  )
}
