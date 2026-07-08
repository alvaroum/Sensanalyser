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

#' Draw a readable HCPC dendrogram
#'
#' Base-graphics dendrogram tuned for product labels: leaves hang from a
#' common baseline (hang = -1), the bottom margin grows with the longest
#' label so names are never cut off, label size shrinks gently with the
#' number of products, and the default plot.hclust annotations (the
#' dist()/method call printed under the axis) are suppressed.
#'
#' @param hc An stats::hclust object.
#' @param main Plot title.
#' @param k Optional number of clusters to highlight with coloured boxes.
#' @param cut_height Optional height at which to draw a dashed cut line.
#' @keywords internal
.plot_hcpc_dendrogram <- function(hc, main, k = NULL, cut_height = NULL) {
  n <- length(hc$order)
  labels <- if (is.null(hc$labels)) character(0) else hc$labels
  label_cex <- max(0.6, min(1.1, 30 / max(n, 1)))
  longest <- if (length(labels) > 0) max(nchar(labels), na.rm = TRUE) else 8
  bottom_margin <- min(12, max(5, ceiling(longest * label_cex * 0.35)))

  op <- graphics::par(mar = c(bottom_margin, 4.5, 3, 1))
  on.exit(graphics::par(op), add = TRUE)

  graphics::plot(hc, hang = -1, main = main, xlab = "", sub = "",
                 ylab = "Cluster distance (height)", cex = label_cex)
  if (!is.null(cut_height) && is.finite(cut_height)) {
    graphics::abline(h = cut_height, lty = 2, lwd = 1.5, col = "red3")
  }
  if (!is.null(k) && is.finite(k) && k > 1 && k < n) {
    stats::rect.hclust(hc, k = k, border = seq_len(k) + 1)
  }
  invisible(NULL)
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

  # Attributes without scores for some products (sessions measuring different
  # attribute sets) or with zero variance cannot enter the scaled PCA/HCPC;
  # drop them with an explicit warning (helper shared with the PCA module).
  x <- .drop_unmeasured_attributes(x, "HCPC")

  if (ncol(x) < 2 || nrow(x) < 3) {
    cli::cli_alert_warning("Skipping HCPC: insufficient usable variables or product levels after excluding unmeasured/constant attributes.")
    return(list(skipped = TRUE, reason = "Insufficient data after NA/zero-variance filtering"))
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
    # Click-to-cut on our own dendrogram (FactoMineR's nb.clust = 0 flow is
    # avoided because its device handling misbehaves in some environments).
    # The user clicks at a height; the implied cluster count is shown with
    # coloured boxes and confirmed. If clicking is not possible on the
    # current device (locator() unsupported, or the user aborts), fall back
    # to typing the cluster count.
    cli::cli_alert_info("Displaying dendrogram - click at the height where the tree should be cut.")

    coord_preview <- as.data.frame(pca_fit$ind$coord)
    hc_preview    <- stats::hclust(stats::dist(coord_preview), method = "ward.D2")
    n_leaves      <- nrow(coord_preview)

    grDevices::dev.new()
    k_chosen <- NULL
    repeat {
      .plot_hcpc_dendrogram(
        hc_preview,
        main = "HCPC - click at the height where the tree should be cut"
      )
      cat("\nClick on the dendrogram at the height where you want to cut the tree.",
          "\n(To type the number of clusters instead, press Esc in the plot window.)\n")
      click <- tryCatch(graphics::locator(1), error = function(e) NULL)
      if (is.null(click) || length(click$y) == 0 || !is.finite(click$y[[1]])) {
        break  # clicking unavailable or aborted -> typed fallback below
      }
      k <- length(unique(stats::cutree(hc_preview, h = click$y[[1]])))
      if (k < 2 || k >= n_leaves) {
        cli::cli_alert_danger(
          "A cut there gives {k} cluster(s). Click between the branch joins, so the cut line crosses 2 to {n_leaves - 1} branches."
        )
        next
      }
      .plot_hcpc_dendrogram(
        hc_preview,
        main = sprintf("Cut at height %.2f -> %d clusters", click$y[[1]], k),
        k = k, cut_height = click$y[[1]]
      )
      ans <- tolower(trimws(readline(
        sprintf("This cut gives %d clusters (boxes on the plot). Keep it? [Y = yes / n = click again] ", k)
      )))
      if (ans %in% c("", "y", "yes")) {
        k_chosen <- k
        break
      }
    }

    if (is.null(k_chosen)) {
      repeat {
        cat("\nHow many clusters? Enter a whole number >= 2:\n> ")
        k <- suppressWarnings(as.integer(trimws(readline())))
        if (!is.na(k) && k >= 2 && k < n_leaves) {
          k_chosen <- k
          break
        }
        cli::cli_alert_danger(
          "Please enter a whole number between 2 and {n_leaves - 1}."
        )
      }
    }

    hcpc_n_clusters <- k_chosen
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

  # Highlight the selected cluster cut directly on the dendrogram.
  # hcpc_n_clusters holds the resolved choice at this point (fixed number
  # from the config, or the count picked by clicking); -1 (automatic) falls
  # back to the number of clusters HCPC actually returned.
  k_rect <- if (hcpc_n_clusters > 1) {
    as.integer(hcpc_n_clusters)
  } else {
    length(unique(cluster_tbl$cluster))
  }

  # Give each product label breathing room; small panels stay at the
  # configured width.
  dendro_width <- max(width, 0.45 * nrow(coord) + 3)

  grDevices::png(dendro_path, width = dendro_width, height = height, units = "in", res = dpi)
  .plot_hcpc_dendrogram(hc, main = "HCPC - Hierarchical clustering of products", k = k_rect)
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
