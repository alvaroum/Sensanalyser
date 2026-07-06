#' HCPC / Hierarchical Cluster Helpers for Sensanalyser
#'
#' @description
#' Phase 8 hierarchical clustering module based on the archived HCPC workflow.
#' Product-level means are analysed with FactoMineR::PCA and then clustered
#' with FactoMineR::HCPC. The module exports cluster memberships, cluster
#' profiles, variable descriptors, a dendrogram, and a PCA cluster map.
#'
#' @keywords internal

#' Flatten HCPC quantitative descriptors
#'
#' @param hcpc_fit Result from FactoMineR::HCPC().
#' @return Tibble with one row per cluster-variable descriptor.
#' @keywords internal
.flatten_hcpc_quanti_descriptors <- function(hcpc_fit) {
  quanti <- hcpc_fit$desc.var$quanti
  if (is.null(quanti) || length(quanti) == 0) return(tibble::tibble())

  purrr::map_dfr(names(quanti), function(cluster_id) {
    tbl <- quanti[[cluster_id]]
    if (is.null(tbl) || nrow(tbl) == 0) return(tibble::tibble())
    tibble::as_tibble(tbl, rownames = "variable") |>
      dplyr::mutate(cluster = cluster_id, .before = 1)
  })
}

#' Run sensory HCPC / hierarchical cluster analysis
#'
#' @param data Working dataset.
#' @param selections Variable selections.
#' @param config Full config list.
#' @return List with HCPC object, exported tables, and figure paths.
#' @export
run_sensory_hcpc <- function(data, selections, config) {
  if (!isTRUE(config$toggles$run_hcpc)) {
    return(list(skipped = TRUE, reason = "run_hcpc is FALSE"))
  }

  cli::cli_h3("Phase 8D: Hierarchical Clustering (HCPC)")

  grouping_factor <- selections$factors[[1]]
  if (is.null(grouping_factor) || !grouping_factor %in% names(data)) {
    cli::cli_alert_warning("Skipping HCPC: no valid grouping factor available.")
    return(list(skipped = TRUE, reason = "No valid grouping factor"))
  }

  dvs <- intersect(
    selections$dependent_variables,
    names(data)[vapply(data, is.numeric, logical(1))]
  )

  if (length(dvs) < 2) {
    cli::cli_alert_warning("Skipping HCPC: need at least 2 numeric dependent variables.")
    return(list(skipped = TRUE, reason = "Insufficient numeric DVs"))
  }

  # Product-level means, equivalent in spirit to the archived res.adjmean table.
  mean_tbl <- data |>
    dplyr::group_by(.data[[grouping_factor]]) |>
    dplyr::summarise(dplyr::across(dplyr::all_of(dvs), ~ mean(.x, na.rm = TRUE)), .groups = "drop")

  dict <- if (!is.null(config$paths$renaming_dictionary) &&
              file.exists(config$paths$renaming_dictionary)) {
    load_renaming_dictionary(config$paths$renaming_dictionary)
  } else {
    list(variables = list(), levels = list(), outcomes = list())
  }

  row_ids <- .apply_level_labels(as.character(mean_tbl[[grouping_factor]]), grouping_factor, dict)

  x <- mean_tbl |>
    dplyr::select(dplyr::all_of(dvs)) |>
    as.data.frame()
  rownames(x) <- row_ids
  colnames(x) <- .apply_outcome_labels(colnames(x), dict)

  # Remove zero-variance variables at product-mean level because scaled PCA and
  # HCPC cannot use them reliably.
  variable_sd <- vapply(x, stats::sd, numeric(1), na.rm = TRUE)
  x <- x[, is.finite(variable_sd) & variable_sd > 0, drop = FALSE]

  if (ncol(x) < 2 || nrow(x) < 3) {
    cli::cli_alert_warning("Skipping HCPC: insufficient non-constant variables or product levels.")
    return(list(skipped = TRUE, reason = "Insufficient data after zero-variance filtering"))
  }

  ncp <- min(nrow(x) - 1L, ncol(x))
  pca_fit <- FactoMineR::PCA(x, scale.unit = TRUE, ncp = ncp, graph = FALSE)

  hcpc_n_clusters <- config$analysis$hcpc_n_clusters
  if (is.null(hcpc_n_clusters) || length(hcpc_n_clusters) == 0 || is.na(hcpc_n_clusters) || identical(hcpc_n_clusters, "auto")) {
    hcpc_n_clusters <- -1
  } else {
    hcpc_n_clusters <- as.integer(hcpc_n_clusters)
  }

  if (hcpc_n_clusters == 0 && !interactive()) {
    cli::cli_alert_warning("HCPC interactive mode (0) requires an interactive R session. Falling back to automatic (-1).")
    hcpc_n_clusters <- -1
  }

  interactive_hcpc <- (hcpc_n_clusters == 0)

  if (interactive_hcpc) {
    # FactoMineR's built-in click-to-cut (nb.clust = 0, graph = TRUE) relies on
    # locator(), which fails in many environments (RStudio on macOS, Positron,
    # off-screen devices). Instead: draw the dendrogram ourselves, ask the user
    # to type the cluster count, then call HCPC with that fixed number.
    cli::cli_alert_info("Displaying dendrogram — review it, then type the number of clusters at the prompt.")

    coord_preview <- as.data.frame(pca_fit$ind$coord)
    hc_preview    <- stats::hclust(stats::dist(coord_preview), method = "ward.D2")

    grDevices::dev.new()
    graphics::plot(
      hc_preview,
      main = "HCPC – Dendrogram (review, then type cluster count in the console)",
      xlab = NULL, sub = NULL
    )

    repeat {
      cat("\nHow many clusters? Enter a whole number >= 2:\n> ")
      k <- suppressWarnings(as.integer(trimws(readline())))
      if (!is.na(k) && k >= 2 && k < nrow(coord_preview)) {
        hcpc_n_clusters <- k
        break
      }
      cli::cli_alert_danger(
        "Please enter a whole number between 2 and {nrow(coord_preview) - 1}."
      )
    }

    grDevices::dev.off()
    interactive_hcpc <- FALSE
  }

  hcpc_fit <- FactoMineR::HCPC(
    pca_fit,
    nb.clust = hcpc_n_clusters,
    consol = FALSE,
    graph = FALSE
  )

  cluster_tbl <- tibble::as_tibble(hcpc_fit$data.clust, rownames = "product") |>
    dplyr::select("product", cluster = "clust") |>
    dplyr::mutate(cluster = as.character(.data$cluster))

  mean_tbl_labelled <- tibble::as_tibble(x, rownames = "product")

  cluster_profiles <- mean_tbl_labelled |>
    dplyr::left_join(cluster_tbl, by = "product") |>
    dplyr::group_by(.data$cluster) |>
    dplyr::summarise(dplyr::across(where(is.numeric), ~ mean(.x, na.rm = TRUE)), .groups = "drop")

  desc_quanti <- .flatten_hcpc_quanti_descriptors(hcpc_fit)

  pca_scores <- tibble::as_tibble(pca_fit$ind$coord, rownames = "product") |>
    dplyr::left_join(cluster_tbl, by = "product")

  table_root <- config$paths$table_root
  if (is.null(table_root) || !nzchar(table_root)) table_root <- "outputs/tables"
  figure_root <- config$paths$figure_root
  if (is.null(figure_root) || !nzchar(figure_root)) figure_root <- "outputs/figures"

  dir.create(here::here(table_root, "hcpc"), recursive = TRUE, showWarnings = FALSE)
  dir.create(here::here(figure_root, "hcpc"), recursive = TRUE, showWarnings = FALSE)

  cluster_path <- here::here(table_root, "hcpc", "hcpc_clusters.csv")
  profile_path <- here::here(table_root, "hcpc", "hcpc_cluster_profiles.csv")
  desc_path <- here::here(table_root, "hcpc", "hcpc_quanti_descriptors.csv")
  scores_path <- here::here(table_root, "hcpc", "hcpc_pca_scores.csv")
  dendro_path <- here::here(figure_root, "hcpc", "hcpc_dendrogram.png")
  map_path <- here::here(figure_root, "hcpc", "hcpc_cluster_map.png")

  readr::write_csv(cluster_tbl, cluster_path)
  readr::write_csv(cluster_profiles, profile_path)
  readr::write_csv(desc_quanti, desc_path)
  readr::write_csv(pca_scores, scores_path)

  width <- config$fig_options$width; if (is.null(width) || is.na(width)) width <- 9
  height <- config$fig_options$height; if (is.null(height) || is.na(height)) height <- 6
  dpi <- config$fig_options$dpi; if (is.null(dpi) || is.na(dpi)) dpi <- 300

  # Dendrogram from PCA coordinates using Ward clustering, aligned with HCPC logic.
  coord <- as.data.frame(pca_fit$ind$coord)
  hc <- stats::hclust(stats::dist(coord), method = "ward.D2")

  grDevices::png(dendro_path, width = width, height = height, units = "in", res = dpi)
  graphics::plot(hc, main = "HCPC – Hierarchical clustering of products", xlab = NULL, sub = NULL)

  # Highlight the selected cluster cut directly on the dendrogram. When the
  # user fixes nb.clust (e.g. 4), draw rectangles for that solution; otherwise
  # fall back to the number of clusters returned by HCPC.
  k_rect <- if (!is.null(config$analysis$hcpc_n_clusters) &&
                length(config$analysis$hcpc_n_clusters) == 1 &&
                is.finite(config$analysis$hcpc_n_clusters) &&
                config$analysis$hcpc_n_clusters > 1) {
    as.integer(config$analysis$hcpc_n_clusters)
  } else {
    length(unique(cluster_tbl$cluster))
  }

  if (is.finite(k_rect) && k_rect > 1 && k_rect < nrow(coord)) {
    stats::rect.hclust(hc, k = k_rect, border = seq_len(k_rect) + 1)
  }

  grDevices::dev.off()

  if (all(c("Dim.1", "Dim.2") %in% names(pca_scores))) {
    map_plot <- ggplot2::ggplot(pca_scores, ggplot2::aes(x = .data$Dim.1, y = .data$Dim.2, color = .data$cluster)) +
      ggplot2::geom_hline(yintercept = 0, color = "grey85") +
      ggplot2::geom_vline(xintercept = 0, color = "grey85") +
      ggplot2::geom_point(size = 3) +
      ggrepel::geom_text_repel(ggplot2::aes(label = .data$product), size = 3.5) +
      ggplot2::labs(title = "HCPC – Product clusters on PCA map", x = "Dimension 1", y = "Dimension 2", color = "Cluster") +
      ggplot2::theme_minimal(base_size = 11)

    ggplot2::ggsave(map_path, map_plot, width = width, height = height, dpi = dpi)
  }

  cli::cli_alert_success("Saved: {cluster_path}")
  cli::cli_alert_success("Saved: {profile_path}")
  cli::cli_alert_success("Saved: {desc_path}")
  cli::cli_alert_success("Saved: {dendro_path}")
  cli::cli_alert_success("Saved: {map_path}")

  list(
    skipped = FALSE,
    pca_object = pca_fit,
    hcpc_object = hcpc_fit,
    clusters = cluster_tbl,
    cluster_profiles = cluster_profiles,
    quanti_descriptors = desc_quanti,
    file_paths = list(
      clusters = cluster_path,
      cluster_profiles = profile_path,
      quanti_descriptors = desc_path,
      pca_scores = scores_path,
      dendrogram = dendro_path,
      cluster_map = map_path
    )
  )
}
