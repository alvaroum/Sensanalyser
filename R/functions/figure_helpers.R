#' Figure Helpers for Sensanalyser
#'
#' @description
#' Phase 8 helper functions for spider/radar plot generation.
#' Supports flexible group comparisons and attribute filtering.
#'
#' @keywords internal

# ---------------------------------------------------------------------------
# INTERNAL HELPERS
# ---------------------------------------------------------------------------

#' Determine which outcomes to include in spider plots
#'
#' @param selections Variable selection list
#' @param config Full config list
#' @param posthoc_result Phase 6 results (optional)
#' @return Character vector of outcome column names
#' @keywords internal
.get_spider_outcomes <- function(selections, config, posthoc_result = NULL) {
  outcomes <- selections$dependent_variables

  # Filter to significant attributes only when requested
  if (isTRUE(config$fig_options$spider_significant_only) &&
      !is.null(posthoc_result) &&
      !is.null(posthoc_result$posthoc_letters)) {
    sig_outcomes <- posthoc_result$posthoc_letters %>%
      dplyr::filter(.data$omnibus_significant == TRUE) %>%
      dplyr::pull(.data$outcome) %>%
      unique()
    outcomes <- intersect(outcomes, sig_outcomes)
    cli::cli_alert_info("Spider: restricted to {length(outcomes)} significant attribute(s).")
  }

  # Apply explicit attribute list when provided
  explicit <- config$fig_options$spider_outcomes
  if (!is.null(explicit) && length(explicit) > 0) {
    outcomes <- intersect(outcomes, explicit)
  }

  outcomes
}

# ---------------------------------------------------------------------------
# DATA PREPARATION
# ---------------------------------------------------------------------------

#' Create radar/spider plot input data
#'
#' @param data Working dataset
#' @param grouping_factor Grouping column name
#' @param outcomes Character vector of outcome columns
#' @param group_filter Optional character vector of group display names to keep.
#'   NULL keeps all groups. Values must match post-renaming labels.
#' @param top_n Optional integer: keep top-n outcomes by global mean (applied
#'   before group filtering so ranking reflects the full dataset).
#' @param scale_min Radar minimum axis value
#' @param scale_max Optional radar maximum axis value
#' @param renaming_dictionary Optional dictionary list for label mapping
#' @return List with radar_data, means_table, selected_outcomes, grouping_factor
#' @export
create_spider_plot_data <- function(data,
                                    grouping_factor,
                                    outcomes,
                                    group_filter        = NULL,
                                    top_n               = NULL,
                                    scale_min           = 0,
                                    scale_max           = NULL,
                                    renaming_dictionary = NULL) {
  if (is.null(grouping_factor) || !grouping_factor %in% names(data)) {
    cli::cli_abort("Spider plot requires a valid grouping factor column.")
  }

  outcomes <- outcomes[outcomes %in% names(data)]
  outcomes <- outcomes[vapply(outcomes, function(x) is.numeric(data[[x]]), logical(1))]

  if (length(outcomes) == 0) {
    cli::cli_abort("Spider plot requires at least one numeric dependent variable.")
  }

  # Compute group means across ALL groups (used for top_n ranking)
  means_tbl <- data %>%
    dplyr::group_by(.data[[grouping_factor]]) %>%
    dplyr::summarise(dplyr::across(dplyr::all_of(outcomes), ~ mean(.x, na.rm = TRUE)),
                     .groups = "drop")

  # Apply top_n on all groups before subsetting
  if (!is.null(top_n) && is.numeric(top_n) && top_n > 0 && top_n < length(outcomes)) {
    ranked <- means_tbl %>%
      tidyr::pivot_longer(cols = dplyr::all_of(outcomes),
                          names_to = "outcome", values_to = "value") %>%
      dplyr::group_by(.data$outcome) %>%
      dplyr::summarise(global_mean = mean(.data$value, na.rm = TRUE), .groups = "drop") %>%
      dplyr::arrange(dplyr::desc(.data$global_mean)) %>%
      dplyr::slice(seq_len(top_n)) %>%
      dplyr::pull(.data$outcome)
    outcomes  <- ranked
    means_tbl <- means_tbl %>% dplyr::select(dplyr::all_of(c(grouping_factor, outcomes)))
  }

  # Map raw group codes to display names
  if (!is.null(renaming_dictionary)) {
    means_tbl[[grouping_factor]] <- .apply_level_labels(
      as.character(means_tbl[[grouping_factor]]), grouping_factor, renaming_dictionary
    )
  } else {
    means_tbl[[grouping_factor]] <- as.character(means_tbl[[grouping_factor]])
  }

  # Filter to requested groups (by display name)
  if (!is.null(group_filter) && length(group_filter) > 0) {
    means_tbl <- means_tbl %>%
      dplyr::filter(.data[[grouping_factor]] %in% group_filter)
    if (nrow(means_tbl) == 0) {
      cli::cli_abort(
        "No groups matched group_filter: {paste(group_filter, collapse=', ')}."
      )
    }
  }

  # Map attribute column names to display names
  if (!is.null(renaming_dictionary)) {
    display_outcomes <- .apply_outcome_labels(outcomes, renaming_dictionary)
    # dplyr::rename() any_of() expects c(new_name = "old_name")
    rename_map <- stats::setNames(outcomes, display_outcomes)
    means_tbl <- dplyr::rename(means_tbl, dplyr::any_of(rename_map))
    outcomes  <- display_outcomes
  }

  # Build fmsb radar data frame (first two rows = max / min scale bounds)
  radar_core <- means_tbl %>%
    tibble::column_to_rownames(var = grouping_factor) %>%
    as.data.frame()

  if (is.null(scale_max) || !is.finite(scale_max)) {
    max_val   <- suppressWarnings(max(as.matrix(radar_core), na.rm = TRUE))
    if (!is.finite(max_val)) max_val <- 1
    scale_max <- ceiling(max_val * 1.1)
    if (scale_max <= scale_min) scale_max <- scale_min + 1
  }

  max_row <- as.data.frame(t(rep(scale_max, ncol(radar_core))))
  min_row <- as.data.frame(t(rep(scale_min, ncol(radar_core))))
  colnames(max_row) <- colnames(min_row) <- colnames(radar_core)
  rownames(max_row) <- "Max"; rownames(min_row) <- "Min"

  radar_data <- rbind(max_row, min_row, radar_core)

  list(
    radar_data        = radar_data,
    means_table       = means_tbl,
    selected_outcomes = outcomes,
    grouping_factor   = grouping_factor,
    scale_min         = scale_min,
    scale_max         = scale_max
  )
}

# ---------------------------------------------------------------------------
# PLOTTING
# ---------------------------------------------------------------------------

#' Plot spider/radar profiles
#'
#' @param spider_data Output of create_spider_plot_data
#' @param output_path File path for PNG output
#' @param palette_name Brewer palette name
#' @param title Plot title
#' @param width Plot width in inches
#' @param height Plot height in inches
#' @param dpi Resolution
#' @return Output path (invisibly)
#' @export
plot_spider_profiles <- function(spider_data,
                                 output_path,
                                 palette_name = "Set1",
                                 title        = "Sensory Profile",
                                 width        = 9,
                                 height       = 7,
                                 dpi          = 300) {
  radar_data <- spider_data$radar_data
  group_rows <- rownames(radar_data)[-(1:2)]
  n_groups   <- length(group_rows)

  colors <- RColorBrewer::brewer.pal(min(8, max(3, n_groups)), palette_name)
  if (n_groups > length(colors)) {
    colors <- grDevices::colorRampPalette(colors)(n_groups)
  } else {
    colors <- colors[seq_len(n_groups)]
  }

  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)

  # fmsb radar charts require at least three axes. For project-specific derived
  # analyses with one or two conceptual outcomes, save a simple profile bar
  # chart instead of failing the figure phase.
  if (ncol(radar_data) < 3) {
    plot_tbl <- radar_data[-c(1, 2), , drop = FALSE] |>
      tibble::rownames_to_column(var = "group") |>
      tidyr::pivot_longer(-"group", names_to = "attribute", values_to = "mean") |>
      dplyr::mutate(
        group = factor(.data$group, levels = group_rows),
        mean = as.numeric(.data$mean)
      )

    p <- ggplot2::ggplot(plot_tbl, ggplot2::aes(x = .data$group, y = .data$mean, fill = .data$group)) +
      ggplot2::geom_col(width = 0.7, show.legend = FALSE) +
      ggplot2::facet_wrap(~ attribute, scales = "free_y") +
      ggplot2::scale_fill_manual(values = stats::setNames(colors, group_rows)) +
      ggplot2::labs(title = title, x = NULL, y = "Mean score") +
      ggplot2::theme_minimal(base_size = 12) +
      ggplot2::theme(
        plot.title = ggplot2::element_text(face = "bold"),
        axis.text.x = ggplot2::element_text(angle = 30, hjust = 1)
      )

    ggplot2::ggsave(output_path, p, width = width, height = height, dpi = dpi)
    return(invisible(output_path))
  }

  grDevices::png(output_path, width = width, height = height, units = "in", res = dpi)
  old_par <- graphics::par(no.readonly = TRUE)
  on.exit({
    graphics::par(old_par)
    grDevices::dev.off()
  }, add = TRUE)

  graphics::par(mar = c(2, 2, 3, 2))

  fmsb::radarchart(
    radar_data,
    axistype   = 1,
    pcol       = colors,
    pfcol      = scales::alpha(colors, 0.25),
    plwd       = 2,
    plty       = 1,
    cglcol     = "grey80",
    cglty      = 1,
    cglwd      = 0.8,
    axislabcol = "grey40",
    vlcex      = 0.8,
    title      = title
  )

  graphics::legend(
    "bottom",
    legend = group_rows,
    horiz  = TRUE,
    bty    = "n",
    pch    = 15,
    col    = colors,
    cex    = 0.8
  )

  invisible(output_path)
}

# ---------------------------------------------------------------------------
# PHASE ORCHESTRATORS
# ---------------------------------------------------------------------------

#' Run figure generation phase (spider profiles)
#'
#' @description
#' Generates one spider plot per entry in \code{config$fig_options$spider_comparisons}.
#' Each entry is a named element whose value is either NULL (all groups) or a
#' character vector of display-name group labels to include.
#'
#' Attribute selection is controlled by:
#' \itemize{
#'   \item \code{config$fig_options$spider_outcomes} — explicit attribute list (NULL = all DVs)
#'   \item \code{config$fig_options$spider_significant_only} — TRUE restricts to
#'     attributes with a significant omnibus test (requires posthoc_result)
#'   \item \code{config$fig_options$top_n_attributes} — further limit to top-N by
#'     global mean after the above filters
#' }
#'
#' @param data Working dataset
#' @param selections Variable selections
#' @param config Full config list
#' @param posthoc_result Phase 6 results (optional; needed for significant_only)
#' @return List with skipped flag, spider_data list, and file_paths list
#' @export
run_figure_phase <- function(data, selections, config, posthoc_result = NULL) {
  if (!isTRUE(config$toggles$create_figures)) {
    return(list(skipped = TRUE, reason = "create_figures is FALSE"))
  }

  cli::cli_h3("Phase 8A: Figures (Spider Profiles)")

  grouping_factor <- selections$factors[[1]]
  if (is.null(grouping_factor) || !grouping_factor %in% names(data)) {
    cli::cli_alert_warning("Skipping spider plot: no valid grouping factor available.")
    return(list(skipped = TRUE, reason = "No valid grouping factor"))
  }

  fig_root   <- config$paths$figure_root
  if (is.null(fig_root)   || !nzchar(fig_root))   fig_root   <- "outputs/figures"
  table_root <- config$paths$table_root
  if (is.null(table_root) || !nzchar(table_root)) table_root <- "outputs/tables"

  # Load renaming dictionary for display-name group labels
  dict <- if (!is.null(config$paths$renaming_dictionary) &&
               file.exists(config$paths$renaming_dictionary)) {
    load_renaming_dictionary(config$paths$renaming_dictionary)
  } else {
    list(variables = list(), levels = list(), outcomes = list())
  }

  width        <- config$fig_options$width;        if (is.null(width)        || is.na(width))        width        <- 9
  height       <- config$fig_options$height;       if (is.null(height)       || is.na(height))       height       <- 7
  dpi          <- config$fig_options$dpi;          if (is.null(dpi)          || is.na(dpi))          dpi          <- 300
  palette_name <- config$fig_options$palette;      if (is.null(palette_name) || !nzchar(palette_name)) palette_name <- "Set1"
  top_n        <- config$fig_options$top_n_attributes

  # Determine outcome pool (all DVs / explicit list / significant only)
  outcomes <- .get_spider_outcomes(selections, config, posthoc_result)
  if (length(outcomes) == 0) {
    cli::cli_alert_warning("Skipping spider plots: no valid outcomes after filtering.")
    return(list(skipped = TRUE, reason = "No valid outcomes"))
  }

  # Comparisons: named list; NULL value = all groups
  comparisons <- config$fig_options$spider_comparisons
  if (is.null(comparisons) || length(comparisons) == 0) {
    comparisons <- list(all_products = NULL)
  }

  dir.create(here::here(fig_root,   "spiderplots"), recursive = TRUE, showWarnings = FALSE)
  dir.create(here::here(table_root, "spiderplots"), recursive = TRUE, showWarnings = FALSE)

  file_paths       <- list()
  spider_data_list <- list()

  for (comp_name in names(comparisons)) {
    group_filter <- comparisons[[comp_name]]
    safe_name    <- gsub("[^a-zA-Z0-9_]", "_", comp_name)
    plot_title   <- gsub("_", " ", comp_name)

    spider_data <- tryCatch(
      create_spider_plot_data(
        data                = data,
        grouping_factor     = grouping_factor,
        outcomes            = outcomes,
        group_filter        = group_filter,
        top_n               = top_n,
        scale_min           = 0,
        renaming_dictionary = dict
      ),
      error = function(e) {
        cli::cli_alert_warning("Spider '{comp_name}': {conditionMessage(e)}")
        NULL
      }
    )
    if (is.null(spider_data)) next

    fig_path <- here::here(fig_root,   "spiderplots", paste0("spider_", safe_name, ".png"))
    tbl_path <- here::here(table_root, "spiderplots", paste0("spider_", safe_name, "_means.csv"))

    plot_spider_profiles(
      spider_data  = spider_data,
      output_path  = fig_path,
      palette_name = palette_name,
      title        = plot_title,
      width        = width,
      height       = height,
      dpi          = dpi
    )

    readr::write_csv(spider_data$means_table, tbl_path)

    cli::cli_alert_success("Saved: {fig_path}")
    cli::cli_alert_success("Saved: {tbl_path}")

    file_paths[[paste0(safe_name, "_plot")]]  <- fig_path
    file_paths[[paste0(safe_name, "_table")]] <- tbl_path
    spider_data_list[[comp_name]]             <- spider_data
  }

  list(
    skipped     = FALSE,
    spider_data = spider_data_list,
    file_paths  = file_paths
  )
}

#' Run full Phase 8 orchestration
#'
#' @param data Working dataset
#' @param selections Variable selections
#' @param config Full config list
#' @param posthoc_result Phase 6 post-hoc results (optional)
#' @return List with figure, PCA, and MFA outputs
#' @export
run_phase8 <- function(data, selections, config, posthoc_result = NULL) {
  cli::cli_h2("Phase 8: Figures, PCA, MFA")

  figure_result <- run_figure_phase(data, selections, config, posthoc_result = posthoc_result)
  # HCPC runs before PCA so cluster memberships can be used to colour the scores plot.
  hcpc_result   <- run_sensory_hcpc(data, selections, config)
  pca_result    <- run_sensory_pca(data, selections, config,
                                   posthoc_result = posthoc_result,
                                   hcpc_result    = hcpc_result)
  mfa_result    <- run_sensory_mfa(data, selections, config)

  list(
    figures = figure_result,
    hcpc    = hcpc_result,
    pca     = pca_result,
    mfa     = mfa_result
  )
}
