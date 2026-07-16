# =============================================================================
# Data Cleaning Helpers
#
# Handles the standard raw-export format produced by the QDA software:
#   Row 1  — short metadata codes (user, product, sequence, code, ...) + Q-codes (Q1…Qn)
#   Row 2  — descriptive names ("product or block", "blinding code", ...) + attribute names (vinegar_a, ...)
#   Rows 3–5 — empty / legend rows (B5 holds the product key "1=Name, 2=Name, ...")
#   Row 6+ — actual data
# =============================================================================


# ── Internal helpers ──────────────────────────────────────────────────────────

#' Parse the B5 product key string into a named lookup vector
#'
#' @param key_string Character. E.g. "1=Product A, 2=Product B,3=Product C".
#' @return Named character vector: names are the numeric codes ("1","2",...),
#'   values are the product names.
#' @keywords internal
.parse_product_key <- function(key_string) {
  if (is.na(key_string) || !nzchar(trimws(key_string))) return(NULL)

  # Split only on commas that are immediately followed by a digit= so that
  # commas inside product names are preserved.
  pairs <- strsplit(trimws(key_string), ",\\s*(?=[0-9]+=)", perl = TRUE)[[1]]

  codes  <- character(length(pairs))
  labels <- character(length(pairs))

  for (i in seq_along(pairs)) {
    eq <- regexpr("=", pairs[[i]], fixed = TRUE)
    if (eq > 0) {
      codes[i]  <- trimws(substr(pairs[[i]], 1, eq - 1))
      labels[i] <- trimws(substr(pairs[[i]], eq + 1, nchar(pairs[[i]])))
    }
  }

  keep <- nzchar(codes)
  stats::setNames(labels[keep], codes[keep])
}


#' Find every "+"-delimited split point in a raw product name
#'
#' A name with \code{n} segments (\code{n - 1} "+" characters) yields
#' \code{n - 1} candidate splits — one per "+" position — so that names
#' with multiple pluses (e.g. \code{"A+High+Line2"}) can have exactly one
#' of the candidates accepted rather than forcing an all-or-nothing split.
#'
#' @param raw_name Character scalar, e.g. \code{"ProductA+High"}.
#' @return A list of \code{list(product = ..., factor = ...)} candidates,
#'   empty if \code{raw_name} contains no "+".
#' @keywords internal
.find_plus_split_candidates <- function(raw_name) {
  parts <- strsplit(raw_name, "+", fixed = TRUE)[[1]]
  n <- length(parts)
  if (n < 2) return(list())

  lapply(seq_len(n - 1), function(i) {
    list(
      product = trimws(paste(parts[seq_len(i)], collapse = "+")),
      factor  = trimws(paste(parts[(i + 1):n], collapse = "+"))
    )
  })
}


#' Ask the user, one candidate split at a time, whether to separate a factor
#'
#' Stops at the first accepted candidate. If none are accepted, the name is
#' left untouched.
#'
#' @param raw_name Character scalar raw product name containing "+".
#' @return \code{list(split = TRUE, product = ..., factor = ...)} or
#'   \code{list(split = FALSE)}.
#' @keywords internal
.resolve_product_factor_split <- function(raw_name) {
  for (cand in .find_plus_split_candidates(raw_name)) {
    ans <- utils::askYesNo(
      sprintf(
        "Product name '%s' contains '+'. Split into product = '%s' and a Yes/No factor column '%s'?",
        raw_name, cand$product, cand$factor
      ),
      default = FALSE
    )
    if (isTRUE(ans)) {
      return(list(split = TRUE, product = cand$product, factor = cand$factor))
    }
  }
  list(split = FALSE)
}


#' Read accepted product+factor split decisions from factor_splits.yaml
#'
#' @param dict_dir Path to the project's \code{data/dictionary} folder.
#' @return The parsed decision list (raw name -> \code{list(split, product, factor)}),
#'   empty list if the file doesn't exist or has no entries.
#' @keywords internal
.read_factor_splits <- function(dict_dir) {
  splits_path <- .dict_path(dict_dir, "factor_splits.yaml")
  splits <- if (file.exists(splits_path)) yaml::read_yaml(splits_path)[["product"]] else NULL
  if (is.null(splits)) splits <- list()
  splits
}


#' Resolve a dictionary file, preferring the pipeline-owned state copy
#'
#' Sensanalyser writes what it maintains (resolved labels, split decisions)
#' into \code{data/dictionary/state/}. Legacy projects keep their files
#' directly in \code{data/dictionary/}, which is used as the fallback.
#'
#' @param dict_dir Path to the project's \code{data/dictionary} folder.
#' @param file_name e.g. \code{"factor_splits.yaml"}.
#' @param for_writing When TRUE, always return the state path (creating the
#'   folder), because Sensanalyser owns the file it is about to write.
#' @return Path to the file (may not exist yet).
#' @keywords internal
.dict_path <- function(dict_dir, file_name, for_writing = FALSE) {
  state_dir <- file.path(dict_dir, "state")
  state_file <- file.path(state_dir, file_name)
  if (for_writing) {
    dir.create(state_dir, recursive = TRUE, showWarnings = FALSE)
    return(state_file)
  }
  if (file.exists(state_file)) state_file else file.path(dict_dir, file_name)
}


#' Map factor split labels to clean, case/whitespace-insensitive column names
#'
#' @description
#' Two labels that only differ in case or surrounding whitespace (e.g.
#' \code{"Panelist A 0,07\%"} vs \code{"panelist a 0,07\%"}) represent the same
#' factor and must map to the same column. Calling
#' \code{janitor::make_clean_names()} directly on the full label vector
#' would instead disambiguate them into two separate columns (e.g. with a
#' \code{_2} suffix), because it only guarantees uniqueness among the
#' exact strings it's given — it has no notion that two inputs "mean" the
#' same thing. This groups labels by a case/whitespace-insensitive key
#' first, so each group shares one clean column name.
#'
#' @param factor_labels Character vector of (possibly duplicate-by-case) factor labels.
#' @return Named character vector: names are the original labels, values
#'   are the shared clean column name for that label's case-insensitive group.
#' @keywords internal
.factor_label_columns <- function(factor_labels) {
  keys        <- tolower(trimws(factor_labels))
  unique_keys <- unique(keys)

  # One representative label per key (first-seen) drives the clean name,
  # so make_clean_names() only ever sees already-distinct inputs.
  representative <- vapply(unique_keys, function(k) factor_labels[keys == k][1], character(1))
  clean_by_key   <- stats::setNames(janitor::make_clean_names(representative), unique_keys)

  stats::setNames(unname(clean_by_key[keys]), factor_labels)
}


#' List the Yes/No column names created by accepted product+factor splits
#'
#' @description
#' Each distinct factor value that was accepted (across all raw product
#' names) becomes its own binary column, named after the factor value via
#' \code{\link{.factor_label_columns}} so it is safe to use in model
#' formulas and case/whitespace variants of the same factor share one column.
#'
#' @param dict_dir Path to the project's \code{data/dictionary} folder.
#' @return Character vector of clean column names (empty if none).
#' @keywords internal
.list_factor_split_columns <- function(dict_dir) {
  splits   <- .read_factor_splits(dict_dir)
  accepted <- Filter(function(d) isTRUE(d$split), splits)
  if (length(accepted) == 0) return(character(0))

  factor_labels <- unique(vapply(accepted, function(d) d$factor, character(1)))
  unique(.factor_label_columns(factor_labels))
}


#' Detect "product+factor" naming and split it into a product name and Yes/No columns
#'
#' @description
#' Some raw product names encode an extra factor using "+" as a separator
#' (e.g. \code{"ProductA+High"}). This asks the user, once per distinct
#' raw name (and once per candidate split point within that name), whether
#' to separate it out. Decisions are persisted to \code{factor_splits.yaml}
#' next to the renaming dictionary so the same raw name is never asked
#' about twice.
#'
#' Each distinct accepted factor value becomes its own binary column (e.g.
#' a factor value of \code{"Powder 1.0%"} becomes a column named
#' \code{powder_1_0_percent}, containing \code{"Yes"} for rows whose raw
#' product name carried that factor and \code{"No"} otherwise) — so a
#' product can carry more than one independent split factor.
#'
#' When not running interactively, undecided names are left untouched (no
#' prompt, no file write) so the pipeline never blocks.
#'
#' @param data A tibble with a \code{product} column.
#' @param dict_dir Path to the project's \code{data/dictionary} folder.
#' @return A list with \code{data} (product rewritten, one Yes/No column per
#'   accepted factor value) and \code{new_columns} (character vector of the
#'   column names added, empty if none).
#' @keywords internal
.apply_product_factor_splits <- function(data, dict_dir) {
  empty_result <- list(data = data, new_columns = character(0))
  if (!"product" %in% names(data)) return(empty_result)

  raw_values <- unique(as.character(data$product))
  candidates_present <- raw_values[grepl("+", raw_values, fixed = TRUE)]
  if (length(candidates_present) == 0) return(empty_result)

  splits <- .read_factor_splits(dict_dir)

  is_interactive_session <- !identical(Sys.getenv("RSTUDIO"), "") ||
    !identical(Sys.getenv("POSITRON"), "") || interactive()

  updated <- FALSE
  for (raw_name in candidates_present) {
    if (!is.null(splits[[raw_name]])) next
    if (!is_interactive_session) next

    splits[[raw_name]] <- .resolve_product_factor_split(raw_name)
    updated <- TRUE
  }

  if (updated) {
    yaml::write_yaml(list(product = splits),
                     .dict_path(dict_dir, "factor_splits.yaml", for_writing = TRUE))
  }

  accepted <- Filter(function(d) isTRUE(d$split), splits)
  if (length(accepted) == 0) return(empty_result)

  original_product <- as.character(data$product)

  factor_labels <- unique(vapply(accepted, function(d) d$factor, character(1)))
  col_by_label  <- .factor_label_columns(factor_labels)

  for (col_name in unique(col_by_label)) {
    data[[col_name]] <- "No"
  }

  for (raw_name in names(accepted)) {
    d           <- accepted[[raw_name]]
    match_rows  <- original_product == raw_name
    data$product[match_rows] <- d$product
    data[[col_by_label[[d$factor]]]][match_rows] <- "Yes"
  }

  list(data = data, new_columns = unique(unname(col_by_label)))
}


#' Build column names from rows 1 and 2 of the raw Excel header
#'
#' Uses row 1 names for metadata columns (cleaner: "product", "code") and
#' row 2 names for Q-attribute columns (descriptive: "vinegar_a", "lactic_acid_a").
#'
#' @param row1 Character vector — values from row 1.
#' @param row2 Character vector — values from row 2.
#' @return Clean character vector of column names, same length as row1/row2.
#' @keywords internal
.build_column_names <- function(row1, row2) {
  is_q_col <- grepl("^Q[0-9]+$", row1, ignore.case = FALSE)
  col_names <- ifelse(is_q_col, row2, row1)
  janitor::make_clean_names(col_names)
}


# ── Public API ────────────────────────────────────────────────────────────────

#' Clean a single raw QDA Excel export
#'
#' @description
#' Reads a raw Excel file produced by the QDA platform and returns a tidy
#' tibble ready for analysis:
#' \itemize{
#'   \item Column names from rows 1 (metadata) and 2 (attributes).
#'   \item Product codes in the \code{product} column replaced with real names
#'         decoded from cell B5.
#'   \item Raw names encoding "product+factor" (e.g. \code{"A+High"}) optionally
#'         split into \code{product} plus a Yes/No column named after the
#'         factor value (e.g. \code{high}) — confirmed interactively per
#'         name, remembered in \code{data/dictionary/factor_splits.yaml}.
#'   \item All-NA columns removed.
#'   \item Columns auto-typed (numeric / character) via \code{readr::type_convert}.
#'   \item Excel serial timestamps in \code{time} converted to \code{POSIXct}.
#' }
#'
#' @param file_path Path to the raw \code{.xlsx} file.
#' @return A tibble.
#' @export
sensanalyser_clean_raw_excel <- function(file_path) {
  stopifnot(file.exists(file_path))

  # ── Step 1: Read the 5-row header block ─────────────────────────────────────
  header <- readxl::read_excel(
    file_path,
    col_names = FALSE,
    n_max     = 5,
    .name_repair = "minimal"
  )

  row1 <- as.character(header[1, ])
  row2 <- as.character(header[2, ])

  # ── Step 2: Build column names ───────────────────────────────────────────────
  col_names <- .build_column_names(row1, row2)

  # ── Step 3: Parse product key from B5 ───────────────────────────────────────
  product_map <- .parse_product_key(as.character(header[5, 2]))

  # ── Step 4: Read data (skip header rows 1–5) ────────────────────────────────
  data <- readxl::read_excel(
    file_path,
    skip        = 5,
    col_names   = col_names,
    col_types   = "text",  # read all as text; type_convert handles the rest
    .name_repair = "minimal"
  )

  # ── Step 5: Remove all-NA rows and columns, then drop unneeded metadata ──────
  data <- janitor::remove_empty(data, which = c("rows", "cols"))
  drop_cols <- c("age", "session", "category", "gender", "sessionid", "time", "position", "sequence", "design")
  data <- dplyr::select(data, -dplyr::any_of(drop_cols))

  # ── Step 6: Auto-detect column types ────────────────────────────────────────
  data <- suppressMessages(readr::type_convert(data, guess_integer = FALSE))

  # ── Step 7: Replace product codes with product names ────────────────────────
  if (!is.null(product_map) && "product" %in% names(data)) {
    data$product <- dplyr::recode(as.character(data$product), !!!product_map)
  }

  dict_dir <- file.path(dirname(dirname(file_path)), "dictionary")

  # ── Step 7a: Detect "product+factor" names and offer to split them ───────
  # Some raw product names encode an extra factor with "+" (e.g. "A+High").
  # Interactively asks, per raw name, whether to separate it into `product`
  # plus a Yes/No column named after the factor value; decisions persist in
  # factor_splits.yaml.
  split_result       <- .apply_product_factor_splits(data, dict_dir)
  data               <- split_result$data
  factor_split_cols  <- split_result$new_columns

  # ── Step 7b: Apply product aliases from renaming dictionary ──────────────
  # Unifies names that differ across QDA sessions but refer to the same product.
  # Aliases come from settings.yaml (labels.aliases), materialised into
  # data/dictionary/state/, falling back to the legacy dictionary file.
  dict_path <- .dict_path(dict_dir, "renaming_dictionary.yaml")
  if (file.exists(dict_path) && "product" %in% names(data)) {
    dict    <- yaml::read_yaml(dict_path)
    aliases <- dict[["aliases"]][["product"]]
    if (!is.null(aliases) && length(aliases) > 0) {
      data$product <- dplyr::recode(data$product, !!!unlist(aliases))
    }
  }

  # ── Step 8: Remove "other..." columns (open-ended free-text responses) ───────
  data <- dplyr::select(data, -dplyr::starts_with("other"))

  # ── Step 9: Remove any remaining character columns except key identifiers ────
  # Drops columns like "design" that contain non-numeric data not useful for
  # analysis. "user" and "product" are kept as the essential row identifiers,
  # plus any Yes/No columns Step 7a created from accepted product+factor splits.
  keep_char <- c("user", "product", factor_split_cols)
  text_cols <- names(data)[vapply(data, is.character, logical(1)) & !names(data) %in% keep_char]
  if (length(text_cols) > 0) {
    data <- dplyr::select(data, -dplyr::all_of(text_cols))
  }

  data
}


#' Clean all raw Excel files in a project's data/raw/ folder
#'
#' @description
#' Iterates over every \code{.xlsx} file in \code{<project_dir>/data/raw/},
#' cleans each one with \code{\link{sensanalyser_clean_raw_excel}}, and saves
#' the result as a \code{.csv} in \code{<project_dir>/data/clean/}.
#'
#' By default, a file is skipped when a clean CSV already exists **and** is
#' newer than the corresponding raw Excel. Pass \code{overwrite = TRUE} to
#' force re-cleaning of all files.
#'
#' @param project_dir Path to the project folder (e.g. \code{"projects/example_study"}).
#' @param overwrite   Logical. Re-clean even if the CSV is up-to-date?
#' @return Invisibly returns a data frame summarising what was done
#'   (\code{file}, \code{status}).
#' @export
sensanalyser_clean_project_raw_data <- function(project_dir, overwrite = FALSE) {
  raw_dir   <- file.path(project_dir, "data", "raw")
  clean_dir <- file.path(project_dir, "data", "clean")

  if (!dir.exists(raw_dir)) {
    message(sprintf("[Sensanalyser] No data/raw/ folder found in '%s'. Nothing to clean.", project_dir))
    return(invisible(data.frame(file = character(), status = character())))
  }

  raw_files <- list.files(raw_dir, pattern = "[.]xlsx$", full.names = TRUE)

  if (length(raw_files) == 0) {
    message(sprintf("[Sensanalyser] No .xlsx files found in '%s'.", raw_dir))
    return(invisible(data.frame(file = character(), status = character())))
  }

  if (!dir.exists(clean_dir)) {
    dir.create(clean_dir, recursive = TRUE)
  }

  results <- vector("list", length(raw_files))

  for (i in seq_along(raw_files)) {
    raw_path   <- raw_files[[i]]
    base_name  <- tools::file_path_sans_ext(basename(raw_path))
    clean_path <- file.path(clean_dir, paste0(base_name, ".csv"))

    # Check if cleaning is needed
    if (!overwrite && file.exists(clean_path)) {
      raw_mtime   <- file.mtime(raw_path)
      clean_mtime <- file.mtime(clean_path)
      if (clean_mtime >= raw_mtime) {
        message(sprintf("  [skip]  %s  (clean CSV is up to date)", basename(raw_path)))
        results[[i]] <- data.frame(file = basename(raw_path), status = "skipped")
        next
      }
    }

    message(sprintf("  [clean] %s", basename(raw_path)))

    tryCatch({
      cleaned <- sensanalyser_clean_raw_excel(raw_path)
      readr::write_csv(cleaned, clean_path)
      results[[i]] <- data.frame(file = basename(raw_path), status = "cleaned")
    }, error = function(e) {
      message(sprintf("  [ERROR] %s: %s", basename(raw_path), e$message))
      results[[i]] <<- data.frame(file = basename(raw_path), status = paste0("error: ", e$message))
    })
  }

  summary_df <- do.call(rbind, results)

  n_cleaned <- sum(summary_df$status == "cleaned")
  n_skipped <- sum(summary_df$status == "skipped")
  n_errors  <- sum(startsWith(summary_df$status, "error"))

  message(sprintf(
    "[Sensanalyser] Cleaning complete — %d cleaned, %d skipped (up to date), %d error(s).",
    n_cleaned, n_skipped, n_errors
  ))

  invisible(summary_df)
}
