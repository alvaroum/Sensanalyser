#' PCA Helpers for Sensanalyser
#'
#' @description
#' Phase 8 PCA module: runs a configurable PCA from selected outcomes,
#' exports tables, and saves scree, individuals, and correlation circle figures.
#'
#' @keywords internal

#' Run sensory PCA
#'
#' @param data Working dataset
#' @param selections Variable selections
#' @param config Full config list
#' @param posthoc_result Optional Phase 6 post-hoc result. Used when
#'   config$analysis$pca_significant_only is TRUE.
#' @return List with PCA object, tables, and file paths
#' @export
run_sensory_pca <- function(data, selections, config, posthoc_result = NULL, hcpc_result = NULL) {
  if (!isTRUE(config$toggles$run_pca)) {
    return(list(skipped = TRUE, reason = "run_pca is FALSE"))
  }

  cli::cli_h3("Phase 8B: PCA")

  grouping_factor <- selections$factors[[1]]
  if (is.null(grouping_factor) || !grouping_factor %in% names(data)) {
    cli::cli_alert_warning("Skipping PCA: no valid grouping factor available.")
    return(list(skipped = TRUE, reason = "No valid grouping factor"))
  }

  dvs <- selections$dependent_variables
  dvs <- dvs[dvs %in% names(data)]
  dvs <- dvs[vapply(dvs, function(x) is.numeric(data[[x]]), logical(1))]

  if (isTRUE(config$analysis$pca_significant_only)) {
    sig_dvs <- character(0)
    if (!is.null(posthoc_result) && !is.null(posthoc_result$posthoc_letters) &&
        nrow(posthoc_result$posthoc_letters) > 0) {
      sig_dvs <- posthoc_result$posthoc_letters |>
        dplyr::filter(.data$omnibus_significant == TRUE) |>
        dplyr::pull(.data$outcome) |>
        unique()
    }
    dvs <- intersect(dvs, sig_dvs)
    cli::cli_alert_info("PCA: restricted to {length(dvs)} significant attribute(s).")
  }

  if (length(dvs) < 2) {
    cli::cli_alert_warning("Skipping PCA: need at least 2 numeric dependent variables.")
    return(list(skipped = TRUE, reason = "Insufficient numeric DVs"))
  }

  pca_input <- data %>%
    dplyr::group_by(.data[[grouping_factor]]) %>%
    dplyr::summarise(dplyr::across(dplyr::all_of(dvs), ~ mean(.x, na.rm = TRUE)), .groups = "drop")

  # Map raw group codes to display names
  dict <- if (!is.null(config$paths$renaming_dictionary) &&
               file.exists(config$paths$renaming_dictionary)) {
    load_renaming_dictionary(config$paths$renaming_dictionary)
  } else {
    list(variables = list(), levels = list(), outcomes = list())
  }
  row_ids <- .apply_level_labels(
    as.character(pca_input[[grouping_factor]]), grouping_factor, dict
  )

  x <- pca_input %>% dplyr::select(dplyr::all_of(dvs)) %>% as.data.frame()
  rownames(x) <- row_ids
  colnames(x) <- .apply_outcome_labels(colnames(x), dict)

  pca_fit <- stats::prcomp(x, center = TRUE, scale. = TRUE)

  eig <- tibble::tibble(
    component         = paste0("PC", seq_along(pca_fit$sdev)),
    std_dev           = pca_fit$sdev,
    variance          = pca_fit$sdev^2,
    variance_percent  = 100 * (pca_fit$sdev^2) / sum(pca_fit$sdev^2),
    cumulative_percent = cumsum(100 * (pca_fit$sdev^2) / sum(pca_fit$sdev^2))
  )

  scores   <- tibble::as_tibble(pca_fit$x,        rownames = "group_level")
  loadings <- tibble::as_tibble(pca_fit$rotation,  rownames = "outcome")

  table_root <- config$paths$table_root
  if (is.null(table_root) || !nzchar(table_root)) table_root <- "outputs/tables"
  figure_root <- config$paths$figure_root
  if (is.null(figure_root) || !nzchar(figure_root)) figure_root <- "outputs/figures"

  dir.create(here::here(table_root,  "pca"), recursive = TRUE, showWarnings = FALSE)
  dir.create(here::here(figure_root, "pca"), recursive = TRUE, showWarnings = FALSE)

  eig_path    <- here::here(table_root,  "pca", "pca_eigenvalues.csv")
  score_path  <- here::here(table_root,  "pca", "pca_group_scores.csv")
  load_path   <- here::here(table_root,  "pca", "pca_variable_coordinates.csv")
  scree_path  <- here::here(figure_root, "pca", "pca_scree_plot.png")
  scores_path <- here::here(figure_root, "pca", "pca_scores_plot.png")
  circle_path <- here::here(figure_root, "pca", "pca_correlation_circle.png")

  readr::write_csv(eig,      eig_path)
  readr::write_csv(scores,   score_path)
  readr::write_csv(loadings, load_path)

  width  <- config$fig_options$width;  if (is.null(width)  || is.na(width))  width  <- 9
  height <- config$fig_options$height; if (is.null(height) || is.na(height)) height <- 6
  dpi    <- config$fig_options$dpi;    if (is.null(dpi)    || is.na(dpi))    dpi    <- 300

  # ── Scree plot ──────────────────────────────────────────────────────────────
  scree_plot <- ggplot2::ggplot(eig, ggplot2::aes(x = .data$component, y = .data$variance_percent)) +
    ggplot2::geom_col(fill = "#2C7FB8") +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.1f%%", .data$variance_percent)),
                       vjust = -0.2, size = 3) +
    ggplot2::labs(title = "PCA Scree Plot", x = "Component", y = "Explained Variance (%)") +
    ggplot2::theme_minimal(base_size = 11)

  ggplot2::ggsave(filename = scree_path, plot = scree_plot,
                  width = width, height = height, dpi = dpi)

  if (!all(c("PC1", "PC2") %in% names(scores))) {
    cli::cli_abort("PCA output does not contain PC1/PC2.")
  }

  scores_2d <- scores %>% dplyr::select("group_level", "PC1", "PC2")

  # Join HCPC cluster membership if available so points can be coloured by cluster.
  has_clusters <- !is.null(hcpc_result) &&
    !isTRUE(hcpc_result$skipped) &&
    !is.null(hcpc_result$clusters) &&
    nrow(hcpc_result$clusters) > 0

  if (has_clusters) {
    scores_2d <- dplyr::left_join(
      scores_2d,
      hcpc_result$clusters,
      by = c("group_level" = "product")
    )
  }

  # ── Individuals (scores) plot ────────────────────────────────────────────────
  if (has_clusters && "cluster" %in% names(scores_2d)) {
    scores_plot <- ggplot2::ggplot(scores_2d,
      ggplot2::aes(x = .data$PC1, y = .data$PC2, color = .data$cluster)) +
      ggplot2::geom_hline(yintercept = 0, color = "grey85") +
      ggplot2::geom_vline(xintercept = 0, color = "grey85") +
      ggplot2::geom_point(size = 3) +
      ggrepel::geom_text_repel(ggplot2::aes(label = .data$group_level), size = 3.5) +
      ggplot2::scale_color_brewer(palette = "Dark2", name = "Cluster") +
      ggplot2::labs(
        title = "PCA – Individuals (coloured by cluster)",
        x = sprintf("PC1 (%.1f%%)", eig$variance_percent[1]),
        y = sprintf("PC2 (%.1f%%)", eig$variance_percent[2])
      ) +
      ggplot2::theme_minimal(base_size = 11)
  } else {
    scores_plot <- ggplot2::ggplot(scores_2d,
      ggplot2::aes(x = .data$PC1, y = .data$PC2)) +
      ggplot2::geom_hline(yintercept = 0, color = "grey85") +
      ggplot2::geom_vline(xintercept = 0, color = "grey85") +
      ggplot2::geom_point(color = "#1B9E77", size = 3) +
      ggrepel::geom_text_repel(ggplot2::aes(label = .data$group_level),
                               color = "#1B9E77", size = 3.5) +
      ggplot2::labs(
        title = "PCA – Individuals",
        x = sprintf("PC1 (%.1f%%)", eig$variance_percent[1]),
        y = sprintf("PC2 (%.1f%%)", eig$variance_percent[2])
      ) +
      ggplot2::theme_minimal(base_size = 11)
  }

  ggplot2::ggsave(filename = scores_path, plot = scores_plot,
                  width = width, height = width, dpi = dpi)

  # ── Correlation circle ───────────────────────────────────────────────────────
  # Variable coordinates on circle: cor(x_j, PC_k) = rotation[j,k] * sdev[k]
  # (valid for scaled PCA; all values lie within the unit circle)
  var_circ <- sweep(pca_fit$rotation[, 1:2], 2, pca_fit$sdev[1:2], "*")
  var_df   <- tibble::tibble(
    outcome = rownames(var_circ),
    PC1     = var_circ[, 1],
    PC2     = var_circ[, 2]
  )

  theta       <- seq(0, 2 * pi, length.out = 200)
  unit_circle <- tibble::tibble(x = cos(theta), y = sin(theta))

  circle_plot <- ggplot2::ggplot() +
    ggplot2::geom_path(data = unit_circle,
                       ggplot2::aes(x = .data$x, y = .data$y), color = "grey70") +
    ggplot2::geom_hline(yintercept = 0, color = "grey85") +
    ggplot2::geom_vline(xintercept = 0, color = "grey85") +
    ggplot2::geom_segment(
      data = var_df,
      ggplot2::aes(x = 0, y = 0, xend = .data$PC1, yend = .data$PC2),
      arrow = ggplot2::arrow(length = grid::unit(0.15, "cm")),
      color = "#D95F02", alpha = 0.7
    ) +
    ggrepel::geom_text_repel(
      data = var_df,
      ggplot2::aes(x = .data$PC1, y = .data$PC2, label = .data$outcome),
      color = "#D95F02", size = 2.5, max.overlaps = 40
    ) +
    ggplot2::coord_fixed(xlim = c(-1.15, 1.15), ylim = c(-1.15, 1.15)) +
    ggplot2::labs(
      title = "PCA – Correlation Circle",
      x = sprintf("PC1 (%.1f%%)", eig$variance_percent[1]),
      y = sprintf("PC2 (%.1f%%)", eig$variance_percent[2])
    ) +
    ggplot2::theme_minimal(base_size = 11)

  ggplot2::ggsave(filename = circle_path, plot = circle_plot,
                  width = width, height = width, dpi = dpi)

  cli::cli_alert_success("Saved: {eig_path}")
  cli::cli_alert_success("Saved: {score_path}")
  cli::cli_alert_success("Saved: {load_path}")
  cli::cli_alert_success("Saved: {scree_path}")
  cli::cli_alert_success("Saved: {scores_path}")
  cli::cli_alert_success("Saved: {circle_path}")

  list(
    skipped              = FALSE,
    pca_object           = pca_fit,
    eigenvalues          = eig,
    group_scores         = scores,
    variable_coordinates = loadings,
    file_paths = list(
      eigenvalues          = eig_path,
      group_scores         = score_path,
      variable_coordinates = load_path,
      scree_plot           = scree_path,
      scores_plot          = scores_path,
      correlation_circle   = circle_path
    )
  )
}
