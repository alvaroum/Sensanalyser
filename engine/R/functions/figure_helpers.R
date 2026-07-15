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

#' Resolve one colour per group, honouring a fixed colour map
#'
#' Starts from the Brewer palette (assigned in group order) and then overrides
#' with any colours the user pinned. `color_map` may be:
#' \itemize{
#'   \item a named vector/list \code{c("Control" = "#E41A1C")} — matched by group
#'     display name, so a product keeps its colour across every chart; or
#'   \item an unnamed vector — applied positionally in group order.
#' }
#' Unmapped groups fall back to the palette.
#'
#' @keywords internal
.resolve_spider_colors <- function(group_rows, color_map, palette_name) {
  n <- length(group_rows)
  base <- RColorBrewer::brewer.pal(min(8, max(3, n)), palette_name)
  base <- if (n > length(base)) grDevices::colorRampPalette(base)(n) else base[seq_len(n)]
  out  <- stats::setNames(base, group_rows)

  if (!is.null(color_map) && length(color_map) > 0) {
    color_map <- unlist(color_map)
    if (!is.null(names(color_map)) && any(nzchar(names(color_map)))) {
      hit <- intersect(names(color_map), group_rows)
      out[hit] <- color_map[hit]
    } else {
      k <- min(length(color_map), n)
      out[seq_len(k)] <- color_map[seq_len(k)]
    }
  }
  unname(out[group_rows])
}

#' Build the radial axis tick labels
#'
#' fmsb's `axistype = 1` default labels the rings as percent of the axis range
#' (`"25 (%)"`, ...), which rarely matches a sensory scale. This returns explicit
#' ring labels instead.
#' \itemize{
#'   \item \code{mode = "value"} — the actual scale values from min to max
#'     (e.g. 0, 3, 6, 9, 12, 15), with \code{unit} appended.
#'   \item \code{mode = "percent"} — NULL, so fmsb keeps its 0-100% default.
#'   \item \code{mode = "none"} — blank labels.
#' }
#'
#' @keywords internal
.spider_axis_labels <- function(scale_min, scale_max, steps, mode = "value", unit = "") {
  if (identical(mode, "percent")) return(NULL)
  if (identical(mode, "none"))    return(rep("", steps + 1))
  vals <- seq(scale_min, scale_max, length.out = steps + 1)
  txt  <- if (isTRUE(all.equal(vals, round(vals)))) {
    format(round(vals))
  } else {
    format(round(vals, 1), nsmall = 1)
  }
  paste0(trimws(txt), unit)
}

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
#' @param label_size Optional relative size (cex) of the axis labels. NULL auto-
#'   scales down as the number of axes grows so long labels stay legible.
#' @param show_legend Legend control: "auto" (hidden for a single group), TRUE
#'   or FALSE.
#' @param color_map Optional fixed colours. A named vector keyed by group display
#'   name pins a colour per product across charts; an unnamed vector is applied in
#'   group order. Unmapped groups fall back to the palette.
#' @param axis_labels Radial tick labels: "value" (actual scale values),
#'   "percent" (fmsb's 0-100% default) or "none".
#' @param axis_unit String appended to each value label, e.g. "%" or " cm".
#' @param axis_steps Number of rings / axis segments (default 4).
#' @return Output path (invisibly)
#' @export
plot_spider_profiles <- function(spider_data,
                                 output_path,
                                 palette_name = "Set1",
                                 title        = "Sensory Profile",
                                 width        = 9,
                                 height       = 7,
                                 dpi          = 300,
                                 label_size   = NULL,
                                 show_legend  = "auto",
                                 color_map    = NULL,
                                 axis_labels  = "value",
                                 axis_unit    = "",
                                 axis_steps   = 4) {
  radar_data <- spider_data$radar_data
  group_rows <- rownames(radar_data)[-(1:2)]
  n_groups   <- length(group_rows)

  # Only draw a legend when it adds information: a single-group chart is already
  # named by its title, and its lone legend entry just collides with the axis
  # labels at the bottom vertex.
  legend_on <- if (identical(show_legend, "auto")) n_groups > 1 else isTRUE(show_legend)

  # Fixed per-group colours (stable across charts) fall back to the palette.
  colors <- .resolve_spider_colors(group_rows, color_map, palette_name)

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

  # Wrap long attribute labels onto two lines so neighbouring axes don't collide.
  n_axes  <- ncol(radar_data)
  vlabels <- vapply(
    colnames(radar_data),
    function(lbl) paste(strwrap(lbl, width = 16), collapse = "\n"),
    character(1)
  )

  # Auto-scale label size: shrink as axes get crowded, unless overridden.
  vlcex <- if (!is.null(label_size) && is.finite(label_size)) {
    label_size
  } else if (n_axes <= 8) 0.9 else if (n_axes <= 14) 0.75 else 0.65

  grDevices::png(output_path, width = width, height = height, units = "in", res = dpi)
  old_par <- graphics::par(no.readonly = TRUE)
  on.exit({
    graphics::par(old_par)
    grDevices::dev.off()
  }, add = TRUE)

  # Give the wrapped outer labels breathing room; reserve extra bottom space
  # only when a legend is actually drawn there.
  graphics::par(mar = c(if (legend_on) 4.5 else 3, 3, 3.5, 3))

  # Radial tick labels reflect the actual scale (min..max) rather than fmsb's
  # default 0-100% of the range.
  caxislabels <- .spider_axis_labels(
    spider_data$scale_min, spider_data$scale_max, axis_steps, axis_labels, axis_unit
  )

  fmsb::radarchart(
    radar_data,
    axistype    = 1,
    seg         = axis_steps,
    caxislabels = caxislabels,
    calcex      = 0.8,
    vlabels     = vlabels,
    pcol        = colors,
    pfcol       = scales::alpha(colors, 0.25),
    plwd        = 2,
    plty        = 1,
    cglcol      = "grey80",
    cglty       = 1,
    cglwd       = 0.8,
    axislabcol  = "grey40",
    vlcex       = vlcex,
    title       = title
  )

  if (legend_on) {
    # Sit the legend just below the bottom axis label (fmsb draws on a roughly
    # [-1.2, 1.2] square) so it never overlaps the attribute labels. A single row
    # reads best for a few groups; stack into columns once there are many.
    legend_args <- list(
      x      = 0, y = -1.28,
      xjust  = 0.5, yjust = 1,
      legend = group_rows,
      bty    = "n",
      pch    = 15,
      col    = colors,
      cex    = 0.75,
      xpd    = TRUE
    )
    if (n_groups <= 4) {
      legend_args$horiz <- TRUE
    } else {
      legend_args$ncol <- ceiling(n_groups / 2)
    }
    do.call(graphics::legend, legend_args)
  }

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
  label_size   <- config$fig_options$spider_label_size
  legend_opt   <- config$fig_options$spider_legend; if (is.null(legend_opt)) legend_opt <- "auto"
  global_colors <- config$fig_options$spider_colors   # named product -> colour

  # Axis scale + units (NULL scale_max = auto-fit each chart).
  scale_min_g  <- config$fig_options$spider_scale_min;  if (is.null(scale_min_g)) scale_min_g <- 0
  scale_max_g  <- config$fig_options$spider_scale_max
  axis_labels  <- config$fig_options$spider_axis_labels; if (is.null(axis_labels) || !nzchar(axis_labels)) axis_labels <- "value"
  axis_unit    <- config$fig_options$spider_axis_unit;   if (is.null(axis_unit)) axis_unit <- ""
  axis_steps   <- config$fig_options$spider_axis_steps;  if (is.null(axis_steps) || is.na(axis_steps)) axis_steps <- 4

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
    comp_spec <- comparisons[[comp_name]]
    safe_name <- gsub("[^a-zA-Z0-9_]", "_", comp_name)

    # A comparison value is either the products directly (NULL = all, or a
    # character vector), or a mapping {title:, products:, colors:} that overrides
    # the defaults. The default title is the key with underscores as spaces.
    plot_colors <- global_colors
    scale_min   <- scale_min_g
    scale_max   <- scale_max_g
    if (is.list(comp_spec) &&
        !is.null(names(comp_spec)) &&
        any(c("title", "products", "groups", "colors", "scale_min", "scale_max") %in%
            names(comp_spec))) {
      group_filter <- comp_spec$products %||% comp_spec$groups
      plot_title   <- comp_spec$title %||% gsub("_", " ", comp_name)
      if (!is.null(comp_spec$scale_min)) scale_min <- comp_spec$scale_min
      if (!is.null(comp_spec$scale_max)) scale_max <- comp_spec$scale_max
      if (!is.null(comp_spec$colors)) {
        cc <- unlist(comp_spec$colors)
        # A named per-plot map merges over the global one; a positional vector
        # replaces it for this chart.
        plot_colors <- if (!is.null(names(cc)) && any(nzchar(names(cc)))) {
          utils::modifyList(as.list(global_colors %||% list()), as.list(cc))
        } else cc
      }
    } else {
      group_filter <- comp_spec
      plot_title   <- gsub("_", " ", comp_name)
    }
    if (!is.null(group_filter)) group_filter <- unlist(group_filter, use.names = FALSE)

    spider_data <- tryCatch(
      create_spider_plot_data(
        data                = data,
        grouping_factor     = grouping_factor,
        outcomes            = outcomes,
        group_filter        = group_filter,
        top_n               = top_n,
        scale_min           = scale_min,
        scale_max           = scale_max,
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
      dpi          = dpi,
      label_size   = label_size,
      show_legend  = legend_opt,
      color_map    = plot_colors,
      axis_labels  = axis_labels,
      axis_unit    = axis_unit,
      axis_steps   = axis_steps
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
