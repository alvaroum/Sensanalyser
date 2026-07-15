#' Data Import Helpers for Sensanalyser
#'
#' @description
#' Functions for loading raw sensory data files from multiple formats.
#' Supports CSV, TSV, XLSX, and XLS files. When no path is provided, an
#' interactive file picker is offered. All functions return a clean tibble
#' with column types detected automatically.
#'
#' @author Sensanalyser project
#' @keywords internal

# ---------------------------------------------------------------------------
# PRIMARY EXPORT FUNCTION
# ---------------------------------------------------------------------------

#' Load Sensanalyser Data
#'
#' @description
#' Main entry point for loading a raw data file into the Sensanalyser pipeline.
#' If `path` is NULL, an interactive file-picker dialog or console prompt is
#' used, depending on the current session type.
#'
#' Supported file formats: .csv, .tsv, .txt, .xlsx, .xls
#'
#' After loading, the function:
#' - Cleans column names to snake_case via janitor
#' - Records the file path in the run log
#' - Prints a brief data summary
#'
#' @param path Character or NULL. Path to the raw data file. If NULL,
#'   the user will be prompted to choose a file interactively.
#' @param clean_names Logical. If TRUE (default), column names are cleaned
#'   to snake_case using janitor::clean_names().
#' @param sheet Integer or character. Which sheet to import when reading an
#'   Excel file. Defaults to 1 (first sheet).
#' @param skip Integer. Number of rows to skip at the top of the file.
#'   Defaults to 0.
#' @param na_strings Character vector. Values to treat as NA.
#'   Defaults to c("", "NA", "N/A", "na", "n/a", ".", "-").
#' @param verbose Logical. If TRUE (default), prints a summary of the
#'   loaded dataset.
#'
#' @return A tibble with the raw data. All factor columns remain as
#'   character at this stage; coercion happens later in the pipeline.
#'
#' @examples
#' \dontrun{
#'   # Interactive file selection
#'   data <- load_sensanalyser_data()
#'
#'   # Explicit path
#'   data <- load_sensanalyser_data("data/raw/my_sensory_study.csv")
#'
#'   # Excel with sheet selection
#'   data <- load_sensanalyser_data("data/raw/panel_data.xlsx", sheet = 2)
#' }
#'
#' @export
load_sensanalyser_data <- function(
    path              = NULL,
    interactive_setup = FALSE,
    clean_names       = TRUE,
    sheet             = 1,
    skip              = 0,
    na_strings        = c("", "NA", "N/A", "na", "n/a", ".", "-"),
    verbose           = TRUE,
    config            = NULL) {

  # Resolve file paths ---------------------------------------------------------
  # Open the picker in the project's data/raw folder when we know the project.
  start_dir <- if (!is.null(config) && !is.null(config$project_root)) {
    file.path(config$project_root, "data", "raw")
  } else NULL
  if (interactive_setup && is.null(path)) {
    while (TRUE) {
      resolved_path <- .resolve_data_path(NULL, multiple = TRUE, start_dir = start_dir)
      if (is.null(resolved_path) || !nzchar(resolved_path[1])) {
        abort_choice <- utils::askYesNo("No file selected. Do you want to abort the pipeline?", default = TRUE)
        if (isTRUE(abort_choice) || is.na(abort_choice)) {
          cli::cli_abort("Data loading cancelled by user.")
        }
        next
      }
      path <- resolved_path
      break
    }
  } else {
    if (is.null(path)) {
      cli::cli_abort("No file selected. Aborting data load.")
    }
    path <- .resolve_data_path(path)
  }

  if (any(!file.exists(path))) {
    cli::cli_abort("One or more files not found: {paste(path[!file.exists(path)], collapse = ', ')}")
  }

  # Read and bind data --------------------------------------------------------
  if (verbose && length(path) > 1) {
    cli::cli_h2("Loading Multiple Data Files")
  }
  
  data_list <- lapply(path, function(p) {
    ext <- tolower(tools::file_ext(p))
    supported_exts <- c("csv", "tsv", "txt", "xlsx", "xls")
    if (!ext %in% supported_exts) {
      cli::cli_abort("Unsupported file format: .{ext} for file {p}. Expected one of: .csv, .tsv, .txt, .xlsx, .xls")
    }

    if (verbose) {
      if (length(path) == 1) cli::cli_h2("Loading Data")
      cli::cli_inform("File: {.path {p}}")
      if (length(path) == 1) cli::cli_inform("Format: .{ext}")
    }

    loaded_data <- tryCatch({
      switch(
        ext,
        csv  = .read_delimited(p, sep = ",", skip = skip, na_strings = na_strings),
        tsv  = .read_delimited(p, sep = "\t", skip = skip, na_strings = na_strings),
        txt  = .read_delimited(p, sep = NULL, skip = skip, na_strings = na_strings),
        xlsx = .clean_or_read_excel(p, sheet = sheet, skip = skip, na_strings = na_strings),
        xls  = .clean_or_read_excel(p, sheet = sheet, skip = skip, na_strings = na_strings)
      )
    }, error = function(e) {
      cli::cli_abort("Failed to parse the file {p}: {e$message}")
    })
    
    # Add source_file tracker if multiple files
    if (length(path) > 1) {
      loaded_data$source_file <- basename(p)
    }
    
    return(loaded_data)
  })

  # Bind them all
  data <- tryCatch({
    dplyr::bind_rows(data_list)
  }, error = function(e) {
    cli::cli_abort("Failed to combine multiple data files. Do they have the same column structure? Error: {e$message}")
  })

  # Clean column names --------------------------------------------------------
  if (clean_names) {
    data <- janitor::clean_names(data)
  }

  # Collapse case-only variants (e.g. "panelist a" / "panelist a", "Test" / "test") so
  # the same panelist, product, or factor level isn't split into duplicate
  # categories just because capitalization drifted across raw files/sessions.
  data <- .canonicalize_case_variants(data)

  # Store the resolved source path on the tibble. The core engine uses this
  # attribute to write reproducible YAML configs and run logs. Without this,
  # a dataset selected interactively would load correctly but the selected file
  # path would be lost after import.
  attr(data, "source_path") <- path

  # Log file path and session info --------------------------------------------
  .log_data_load(attr(data, "source_path"), data, config)

  # Print summary -------------------------------------------------------------
  if (verbose) {
    .print_data_summary(data)
  }

  data
}

#' Collapse case-only variants within character columns
#'
#' @description
#' For every character column, values that are identical once lower-cased
#' and trimmed (e.g. "panelist a" / "panelist a", "Test" / "test") are rewritten to a
#' single canonical spelling — the most frequently occurring original
#' casing for that value, with ties broken by first appearance. This runs
#' on the fully combined dataset so drift across different raw files (e.g.
#' one QDA session typing a name in Title Case, another in lower case) is
#' unified rather than treated as distinct panelists/products/factor levels.
#'
#' @param data A tibble/data frame.
#' @param exclude Character vector of column names to leave untouched.
#'   Defaults to \code{"source_file"}, whose casing reflects a real file
#'   name rather than a data value.
#' @return \code{data} with character columns case-unified.
#' @keywords internal
.canonicalize_case_variants <- function(data, exclude = "source_file") {
  char_cols <- names(data)[vapply(data, is.character, logical(1))]
  char_cols <- setdiff(char_cols, exclude)

  for (col in char_cols) {
    x   <- data[[col]]
    key <- tolower(trimws(x))

    non_na <- !is.na(x)
    if (!any(non_na)) next

    canon_by_key <- tapply(x[non_na], key[non_na], function(v) {
      counts <- table(v)
      top    <- names(counts)[counts == max(counts)]
      if (length(top) == 1) top else v[v %in% top][1]
    })

    data[[col]][non_na] <- unname(canon_by_key[key[non_na]])
  }

  data
}

# ---------------------------------------------------------------------------
# INTERNAL READERS
# ---------------------------------------------------------------------------

#' Read a delimited text file (CSV / TSV / TXT)
#'
#' @keywords internal
.read_delimited <- function(path, sep, skip, na_strings) {
  if (is.null(sep)) {
    # Auto-detect delimiter for .txt files
    first_line <- readLines(path, n = 1 + skip)
    last_line  <- first_line[length(first_line)]
    tab_count  <- lengths(regmatches(last_line, gregexpr("\t", last_line)))
    comma_count <- lengths(regmatches(last_line, gregexpr(",",  last_line)))
    sep <- if (tab_count >= comma_count) "\t" else ","
  }

  tryCatch(
    readr::read_delim(
      file      = path,
      delim     = sep,
      skip      = skip,
      na        = na_strings,
      show_col_types = FALSE,
      trim_ws   = TRUE
    ),
    error = function(e) {
      # Fallback to base R read.table for unusual encodings
      cli::cli_alert_warning("readr failed, falling back to base R reader: {e$message}")
      tibble::as_tibble(read.table(
        file    = path,
        header  = TRUE,
        sep     = sep,
        dec     = ".",
        skip    = skip,
        na.strings = na_strings,
        stringsAsFactors = FALSE,
        check.names = FALSE
      ))
    }
  )
}

#' Read an Excel file
#'
#' @keywords internal
.read_excel_file <- function(path, sheet, skip, na_strings) {
  if (!requireNamespace("readxl", quietly = TRUE)) {
    cli::cli_abort("Package 'readxl' is required to read Excel files. Install it with install.packages('readxl').")
  }
  readxl::read_excel(
    path  = path,
    sheet = sheet,
    skip  = skip,
    na    = na_strings,
    trim_ws = TRUE
  )
}

#' Clean a QDA Excel export or fall back to a plain read
#'
#' When `sensanalyser_clean_raw_excel` is available (loaded from
#' data_cleaning_helpers.R), it is used to clean the file and the result is
#' also saved to a sibling `data/clean/` folder. Otherwise, falls back to
#' `.read_excel_file` so the function is safe to call before the cleaning
#' helpers are sourced.
#'
#' @keywords internal
.clean_or_read_excel <- function(path, sheet, skip, na_strings) {
  if (!exists("sensanalyser_clean_raw_excel", mode = "function")) {
    return(.read_excel_file(path, sheet = sheet, skip = skip, na_strings = na_strings))
  }

  cli::cli_inform("Cleaning QDA Excel export: {.path {basename(path)}}")
  cleaned <- sensanalyser_clean_raw_excel(path)

  # Save a clean CSV alongside the raw file for reproducibility
  clean_dir <- file.path(dirname(dirname(path)), "clean")
  if (!dir.exists(clean_dir)) dir.create(clean_dir, recursive = TRUE)
  clean_csv <- file.path(clean_dir, paste0(tools::file_path_sans_ext(basename(path)), ".csv"))
  readr::write_csv(cleaned, clean_csv)
  cli::cli_alert_success("Saved clean CSV: {.path {clean_csv}}")

  cleaned
}

# ---------------------------------------------------------------------------
# INTERACTIVE FILE SELECTION
# ---------------------------------------------------------------------------

#' Resolve the data file path
#'
#' @description
#' If path is not NULL, validates and returns it.
#' If path is NULL, opens a native file-picker dialog. The dialog strategy
#' is tried in this order:
#'   1. RStudio API (rstudioapi::selectFile) — works even during source()
#'   2. Tcl/Tk picker (tcltk::tk_choose.files) — macOS / Linux with X11
#'   3. svDialogs picker (svDialogs::dlg_open)
#'   4. Base R file.choose() — interactive sessions only
#'   5. Console readline fallback (headless / CI environments)
#'
#' @keywords internal
.resolve_data_path <- function(path, multiple = FALSE, start_dir = NULL) {
  if (!is.null(path)) {
    return(normalizePath(path, mustWork = FALSE))
  }

  # Where the dialog should open. Defaults to the project's data/raw folder so
  # the user starts exactly where their raw files live.
  if (!is.null(start_dir) && !dir.exists(start_dir)) start_dir <- NULL

  cli::cli_alert_info("No data file specified. Please select one now.")
  if (!is.null(start_dir)) cli::cli_alert_info("Opening in {.path {start_dir}}.")

  # 1. Native macOS AppleScript Dialog — very robust on macOS, works in RStudio/Positron/Terminal
  if (identical(Sys.info()[["sysname"]], "Darwin")) {
    selected <- .choose_file_macos(multiple = multiple, start_dir = start_dir)
    if (!is.null(selected) && all(nzchar(selected))) return(selected)
  }

  # 2. RStudio API picker (available in both RStudio and Positron if compatibility layer supports it)
  if (!multiple && requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
    selected <- tryCatch(
      rstudioapi::selectFile(
        caption  = "Select Sensory Data File",
        path     = if (!is.null(start_dir)) start_dir else rstudioapi::getActiveProject(),
        filter   = "Data Files (*.csv *.tsv *.txt *.xlsx *.xls)",
        existing = TRUE
      ),
      error = function(e) NULL
    )
    if (!is.null(selected) && nzchar(selected)) return(selected)
  }

  # 3. IDE native dialogs (RStudio/Positron) — file.choose() invokes
  #    the native IDE dialog window, working even during source().
  if (!multiple && .is_rstudio_session()) {
    selected <- tryCatch(file.choose(), error = function(e) NULL)
    if (!is.null(selected) && nzchar(selected)) return(selected)
  }

  # 4. Tcl/Tk picker — macOS standard R build includes Tcl/Tk by default
  if (.can_use_gui_dialog() && requireNamespace("tcltk", quietly = TRUE)) {
    selected <- tryCatch(
      tcltk::tk_choose.files(
        caption = "Select Sensory Data File",
        multi   = multiple,
        default = if (!is.null(start_dir)) file.path(start_dir, "") else "",
        filters = matrix(
          c("Data files", "*.csv *.tsv *.txt *.xlsx *.xls",
            "All files",  "*"),
          ncol = 2, byrow = TRUE
        )
      ),
      error = function(e) NULL
    )
    if (!is.null(selected) && length(selected) > 0 && all(nzchar(selected))) {
      return(selected)
    }
  }

  # 5. svDialogs picker
  if (.can_use_gui_dialog() && requireNamespace("svDialogs", quietly = TRUE)) {
    selected <- tryCatch(
      svDialogs::dlg_open(
        title    = "Select Sensory Data File",
        multiple = multiple,
        filters  = matrix(
          c("Data files", "*.csv;*.tsv;*.txt;*.xlsx;*.xls",
            "CSV files",  "*.csv",
            "Excel files","*.xlsx;*.xls",
            "All files",  "*.*"),
          ncol = 2, byrow = TRUE
        )
      )$res,
      error = function(e) NULL
    )
    if (!is.null(selected) && length(selected) > 0 && all(nzchar(selected))) {
      return(selected)
    }
  }

  # 6. Base R file.choose() — only reliable in truly interactive sessions
  if (!multiple && interactive()) {
    selected <- tryCatch(file.choose(), error = function(e) NULL)
    if (!is.null(selected) && nzchar(selected)) return(selected)
  }

  # 7. Console readline fallback (headless / CI)
  .readline_path_prompt()
}

#' Native macOS file picker helper using AppleScript
#'
#' @keywords internal
.choose_file_macos <- function(multiple = FALSE, start_dir = NULL) {
  # AppleScript can open the dialog at a given folder via `default location`.
  loc <- if (!is.null(start_dir) && dir.exists(start_dir)) {
    sprintf(' default location (POSIX file "%s")', normalizePath(start_dir))
  } else ""

  if (multiple) {
    script <- sprintf('
    set fileList to choose file with prompt "Select Sensory Data File(s)"%s multiple selections allowed true
    set posixPaths to {}
    repeat with aFile in fileList
      set end of posixPaths to POSIX path of aFile
    end repeat
    set AppleScript\'s text item delimiters to "\n"
    return posixPaths as string
    ', loc)
  } else {
    script <- sprintf('POSIX path of (choose file with prompt "Select Sensory Data File"%s)', loc)
  }
  tryCatch({
    res <- system2(
      "osascript",
      args = c("-e", script),
      stdout = TRUE,
      stderr = FALSE
    )
    if (length(res) > 0 && nzchar(res[1])) {
      paths <- trimws(res)
      if (all(file.exists(paths))) {
        return(paths)
      }
    }
    NULL
  }, error = function(e) NULL)
}

#' Ask the user to type a file path in the console
#'
#' @keywords internal
.readline_path_prompt <- function() {
  cat("\nEnter the full path to your data file (separate multiple files with a semicolon ';'):\n> ")
  path <- readline()
  path <- trimws(path)

  if (!nzchar(path)) {
    return(NULL)
  }

  paths <- strsplit(path, ";")[[1]]
  paths <- trimws(paths)
  paths <- gsub('^["\']|["\']$', "", paths)
  paths
}

#' Detect whether this R session is running inside a supported GUI IDE
#'
#' @description
#' Returns TRUE for RStudio (RSTUDIO=1) and Positron (POSITRON=1).
#' Both IDEs run sourced scripts in a non-interactive R process, so
#' interactive() alone is not a reliable GUI-availability signal.
#'
#' @keywords internal
.is_rstudio_session <- function() {
  !identical(Sys.getenv("RSTUDIO"), "") || !identical(Sys.getenv("POSITRON"), "")
}

#' Detect whether a graphical display is available for file/list pickers
#'
#' @description
#' Returns TRUE when a GUI dialog (tcltk, svDialogs, file.choose) can be
#' attempted. RStudio and Positron are checked via .is_rstudio_session()
#' because both IDEs support GUI widgets even in sourced (non-interactive)
#' scripts. Outside those IDEs the standard interactive() + display check
#' is used to avoid hanging headless / CI sessions.
#'
#' @keywords internal
.can_use_gui_dialog <- function() {
  if (.is_rstudio_session()) return(TRUE)

  interactive() && (
    !identical(Sys.getenv("DISPLAY"), "") ||
    !identical(Sys.getenv("WAYLAND_DISPLAY"), "") ||
    identical(Sys.info()[["sysname"]], "Darwin")
  )
}

# ---------------------------------------------------------------------------
# LOGGING
# ---------------------------------------------------------------------------

#' Log a data load event
#'
#' @description
#' Appends a record to outputs/logs/data_load_log.csv each time data is loaded.
#' Creates the file if it does not exist.
#'
#' @keywords internal
.log_data_load <- function(path, data, config = NULL) {
  if (!is.null(config) && !is.null(config$paths$logs_root)) {
    log_dir <- config$paths$logs_root
  } else {
    log_dir <- here::here("outputs", "logs")
  }
  
  if (!dir.exists(log_dir)) {
    dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  }
  
  log_path <- file.path(log_dir, "data_load_log.csv")

  record <- data.frame(
    timestamp    = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    file_path    = paste(path, collapse = "; "),
    n_rows       = nrow(data),
    n_cols       = ncol(data),
    r_version    = paste0(R.version$major, ".", R.version$minor),
    stringsAsFactors = FALSE
  )

  if (file.exists(log_path)) {
    existing <- utils::read.csv(log_path, stringsAsFactors = FALSE)
    combined <- rbind(existing, record)
  } else {
    combined <- record
  }

  utils::write.csv(combined, log_path, row.names = FALSE)
}

# ---------------------------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------------------------

#' Print a compact summary of the loaded dataset
#'
#' @description
#' Shows row/column counts, detected column types, and missing-value flags.
#'
#' @param data A tibble returned by load_sensanalyser_data().
#' @return Invisibly returns NULL. Called for its side effect.
#'
#' @export
.print_data_summary <- function(data) {
  n_numeric <- sum(sapply(data, is.numeric))
  n_char    <- sum(sapply(data, is.character))
  n_factor  <- sum(sapply(data, is.factor))
  n_logical <- sum(sapply(data, is.logical))
  has_na    <- any(is.na(data))
  na_count  <- sum(is.na(data))

  cli::cli_h3("Dataset Summary")
  cli::cli_inform("Rows       : {nrow(data)}")
  cli::cli_inform("Columns    : {ncol(data)}")
  cli::cli_inform("Numeric    : {n_numeric}")
  cli::cli_inform("Character  : {n_char}")
  cli::cli_inform("Factor     : {n_factor}")
  cli::cli_inform("Logical    : {n_logical}")

  if (has_na) {
    cli::cli_alert_warning("Missing values: {na_count} total NA cells")
  } else {
    cli::cli_alert_success("No missing values detected")
  }

  invisible(NULL)
}
