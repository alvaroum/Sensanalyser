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
    verbose           = TRUE) {

  # Resolve file path and read data --------------------------------------------
  data <- NULL
  if (interactive_setup) {
    while (TRUE) {
      resolved_path <- .resolve_data_path(path)

      if (is.null(resolved_path) || !nzchar(resolved_path)) {
        abort_choice <- utils::askYesNo("No file selected. Do you want to abort the pipeline?", default = TRUE)
        if (isTRUE(abort_choice) || is.na(abort_choice)) {
          cli::cli_abort("Data loading cancelled by user.")
        }
        path <- NULL
        next
      }

      if (!file.exists(resolved_path)) {
        cli::cli_alert_danger("File not found: {resolved_path}. Please try again.")
        path <- NULL
        next
      }

      ext <- tolower(tools::file_ext(resolved_path))
      supported_exts <- c("csv", "tsv", "txt", "xlsx", "xls")
      if (!ext %in% supported_exts) {
        cli::cli_alert_danger(
          "Unsupported file format: .{ext}. Expected one of: .csv, .tsv, .txt, .xlsx, .xls. Please try again."
        )
        path <- NULL
        next
      }

      # Attempt to read the file
      loaded_data <- tryCatch({
        if (verbose) {
          cli::cli_h2("Loading Data")
          cli::cli_inform("File: {.path {resolved_path}}")
          cli::cli_inform("Format: .{ext}")
        }

        switch(
          ext,
          csv  = .read_delimited(resolved_path, sep = ",", skip = skip, na_strings = na_strings),
          tsv  = .read_delimited(resolved_path, sep = "\t", skip = skip, na_strings = na_strings),
          txt  = .read_delimited(resolved_path, sep = NULL, skip = skip, na_strings = na_strings),
          xlsx = .read_excel_file(resolved_path, sheet = sheet, skip = skip, na_strings = na_strings),
          xls  = .read_excel_file(resolved_path, sheet = sheet, skip = skip, na_strings = na_strings)
        )
      }, error = function(e) {
        cli::cli_alert_danger("Failed to parse the file: {e$message}")
        NULL
      })

      if (!is.null(loaded_data)) {
        path <- resolved_path
        data <- loaded_data
        break
      }

      path <- NULL
    }
  } else {
    path <- .resolve_data_path(path)

    if (is.null(path) || !nzchar(path)) {
      cli::cli_abort("No file selected. Aborting data load.")
    }

    if (!file.exists(path)) {
      cli::cli_abort("File not found: {path}")
    }

    ext <- tolower(tools::file_ext(path))
    supported_exts <- c("csv", "tsv", "txt", "xlsx", "xls")
    if (!ext %in% supported_exts) {
      cli::cli_abort("Unsupported file format: .{ext}\nExpected one of: .csv, .tsv, .txt, .xlsx, .xls")
    }

    if (verbose) {
      cli::cli_h2("Loading Data")
      cli::cli_inform("File: {.path {path}}")
      cli::cli_inform("Format: .{ext}")
    }

    data <- switch(
      ext,
      csv  = .read_delimited(path, sep = ",", skip = skip, na_strings = na_strings),
      tsv  = .read_delimited(path, sep = "\t", skip = skip, na_strings = na_strings),
      txt  = .read_delimited(path, sep = NULL, skip = skip, na_strings = na_strings),
      xlsx = .read_excel_file(path, sheet = sheet, skip = skip, na_strings = na_strings),
      xls  = .read_excel_file(path, sheet = sheet, skip = skip, na_strings = na_strings)
    )
  }

  # Clean column names --------------------------------------------------------
  if (clean_names) {
    data <- janitor::clean_names(data)
  }

  # Store the resolved source path on the tibble. The core engine uses this
  # attribute to write reproducible YAML configs and run logs. Without this,
  # a dataset selected interactively would load correctly but the selected file
  # path would be lost after import.
  attr(data, "source_path") <- normalizePath(path, mustWork = TRUE)

  # Log file path and session info --------------------------------------------
  .log_data_load(attr(data, "source_path"), data)

  # Print summary -------------------------------------------------------------
  if (verbose) {
    .print_data_summary(data)
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
.resolve_data_path <- function(path) {
  if (!is.null(path)) {
    return(normalizePath(path, mustWork = FALSE))
  }

  cli::cli_alert_info("No data file specified. Please select one now.")

  # 1. Native macOS AppleScript Dialog — very robust on macOS, works in RStudio/Positron/Terminal
  if (identical(Sys.info()[["sysname"]], "Darwin")) {
    selected <- .choose_file_macos()
    if (!is.null(selected) && nzchar(selected)) return(selected)
  }

  # 2. RStudio API picker (available in both RStudio and Positron if compatibility layer supports it)
  if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
    selected <- tryCatch(
      rstudioapi::selectFile(
        caption  = "Select Sensory Data File",
        filter   = "Data Files (*.csv *.tsv *.txt *.xlsx *.xls)",
        existing = TRUE
      ),
      error = function(e) NULL
    )
    if (!is.null(selected) && nzchar(selected)) return(selected)
  }

  # 3. IDE native dialogs (RStudio/Positron) — file.choose() invokes
  #    the native IDE dialog window, working even during source().
  if (.is_rstudio_session()) {
    selected <- tryCatch(file.choose(), error = function(e) NULL)
    if (!is.null(selected) && nzchar(selected)) return(selected)
  }

  # 4. Tcl/Tk picker — macOS standard R build includes Tcl/Tk by default
  if (.can_use_gui_dialog() && requireNamespace("tcltk", quietly = TRUE)) {
    selected <- tryCatch(
      tcltk::tk_choose.files(
        caption = "Select Sensory Data File",
        multi   = FALSE,
        filters = matrix(
          c("Data files", "*.csv *.tsv *.txt *.xlsx *.xls",
            "All files",  "*"),
          ncol = 2, byrow = TRUE
        )
      ),
      error = function(e) NULL
    )
    if (!is.null(selected) && length(selected) > 0 && nzchar(selected[1])) {
      return(selected[1])
    }
  }

  # 5. svDialogs picker
  if (.can_use_gui_dialog() && requireNamespace("svDialogs", quietly = TRUE)) {
    selected <- tryCatch(
      svDialogs::dlg_open(
        title   = "Select Sensory Data File",
        filters = matrix(
          c("Data files", "*.csv;*.tsv;*.txt;*.xlsx;*.xls",
            "CSV files",  "*.csv",
            "Excel files","*.xlsx;*.xls",
            "All files",  "*.*"),
          ncol = 2, byrow = TRUE
        )
      )$res,
      error = function(e) NULL
    )
    if (!is.null(selected) && length(selected) > 0 && nzchar(selected)) {
      return(selected)
    }
  }

  # 6. Base R file.choose() — only reliable in truly interactive sessions
  if (interactive()) {
    selected <- tryCatch(file.choose(), error = function(e) NULL)
    if (!is.null(selected) && nzchar(selected)) return(selected)
  }

  # 7. Console readline fallback (headless / CI)
  .readline_path_prompt()
}

#' Native macOS file picker helper using AppleScript
#'
#' @keywords internal
.choose_file_macos <- function() {
  script <- 'POSIX path of (choose file with prompt "Select Sensory Data File")'
  tryCatch({
    res <- system2(
      "osascript",
      args = c("-e", shQuote(script)),
      stdout = TRUE,
      stderr = FALSE
    )
    if (length(res) > 0 && nzchar(res[1])) {
      path <- trimws(res[1])
      if (file.exists(path)) {
        return(path)
      }
    }
    NULL
  }, error = function(e) NULL)
}

#' Ask the user to type a file path in the console
#'
#' @keywords internal
.readline_path_prompt <- function() {
  cat("\nEnter the full path to your data file:\n> ")
  path <- readline()
  path <- trimws(path)

  if (!nzchar(path)) {
    return(NULL)
  }

  # Remove surrounding quotes if present
  path <- gsub('^["\']|["\']$', "", path)
  path
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
.log_data_load <- function(path, data) {
  log_path <- here::here("outputs", "logs", "data_load_log.csv")

  record <- data.frame(
    timestamp    = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    file_path    = path,
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
