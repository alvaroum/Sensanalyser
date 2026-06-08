#' Report Helpers for Sensanalyser
#'
#' @description
#' Phase 9 report engine. Renders a Quarto report from already-generated
#' outputs in outputs/tables and outputs/figures without re-running analyses.
#'
#' @keywords internal

#' Render the Sensanalyser results report
#'
#' @param config Full config list
#' @param output_formats Character vector of Quarto output formats.
#'   Defaults to c("html", "docx"). Add "pdf" only when LaTeX/TinyTeX is installed.
#' @return Named list with rendered report paths by format
#' @export
render_sensanalyser_report <- function(config,
                                       output_formats = c("html", "docx")) {
  cli::cli_h3("Phase 9A: Render Quarto Report")

  template_path <- config$paths$report_template
  if (is.null(template_path) || !nzchar(template_path)) {
    template_path <- "reports/sensanalyser_results_report.qmd"
  }
  template_path <- here::here(template_path)

  if (!file.exists(template_path)) {
    cli::cli_abort("Report template not found: {template_path}")
  }

  output_dir    <- dirname(template_path)
  rendered_paths <- list()

  for (output_format in output_formats) {
    output_file <- paste0(
      tools::file_path_sans_ext(basename(template_path)), ".", output_format
    )

    tryCatch({
      quarto::quarto_render(
        input         = template_path,
        output_format = output_format,
        output_file   = output_file,
        quiet         = TRUE
      )

      rendered_path <- file.path(output_dir, output_file)
      if (!file.exists(rendered_path)) {
        cli::cli_warn("Quarto render completed but expected output not found: {rendered_path}")
      } else {
        cli::cli_alert_success("Saved: {rendered_path}")
        rendered_paths[[output_format]] <- rendered_path
      }
    }, error = function(e) {
      cli::cli_warn("Failed to render {output_format}: {conditionMessage(e)}")
    })
  }

  list(
    template_path  = template_path,
    rendered_paths = rendered_paths,
    output_formats = output_formats
  )
}

#' Run Phase 9 report orchestration
#'
#' @param pipeline_state Full pipeline state
#' @return List with rendered report metadata
#' @export
run_report_phase <- function(pipeline_state) {
  cli::cli_h2("Phase 9: Quarto Report")

  config <- pipeline_state$config

  output_formats <- config$report_options$output_formats
  if (is.null(output_formats) || length(output_formats) == 0) {
    output_formats <- c("html", "docx")
  }

  report_result <- render_sensanalyser_report(
    config         = config,
    output_formats = output_formats
  )

  ai_prompt_path <- here::here("reports", "ai_summary_prompt.md")

  list(
    report = report_result,
    ai_prompt_path = ai_prompt_path
  )
}
