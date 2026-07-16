# Regression tests for presentation CSV and XLSX report exports.
# Run with: Rscript engine/tests/test_presentation_exports.R
suppressMessages({ library(here); library(tibble) })
source(here::here("engine", "R", "functions", "table_helpers.R"))

passed <- 0L
check <- function(label, ...) {
  stopifnot(...)
  passed <<- passed + 1L
  cat("ok  ", label, "\n")
}

tbl <- tibble(
  outcome = "Darkness crumb (Appearance)",
  Control = "3.1 ± 0.2^a^",
  Trial = "4.5 ± 0.3^b^"
)

csv_tbl <- .presentation_csv_table(tbl)
check("CSV uses Unicode superscript glyphs",
      identical(csv_tbl$Control, "3.1 ± 0.2ᵃ"),
      identical(csv_tbl$Trial, "4.5 ± 0.3ᵇ"))

xlsx_path <- tempfile(fileext = ".xlsx")
.write_superscript_xlsx(tbl, xlsx_path)
check("XLSX export is created", file.exists(xlsx_path), file.info(xlsx_path)$size > 0)
xml <- system2("unzip", c("-p", xlsx_path, "xl/worksheets/sheet1.xml"), stdout = TRUE)
check("XLSX stores compact letters as superscript rich text",
      any(grepl('vertAlign val="superscript"', xml, fixed = TRUE)))

unlink(xlsx_path)
cat(sprintf("\nAll %d presentation-export checks passed.\n", passed))
