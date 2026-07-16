# Regression tests for the guided first-run setup: the console helpers, the
# commented settings writeback, and the general/subsets output routing.
# Run with:  Rscript engine/tests/test_interactive_setup.R
suppressWarnings(suppressMessages(source(here::here("engine", "R", "load_sensanalyser.R"))))

pass <- 0; fail <- 0
ok <- function(cond, msg) {
  if (isTRUE(cond)) { pass <<- pass + 1; cat("ok  ", msg, "\n") }
  else { fail <<- fail + 1; cat("FAIL", msg, "\n") }
}

# --- readline / askYesNo stubs (queues) ---
.Q <- character(0); .I <- 0
feed <- function(...) { .Q <<- c(...); .I <<- 0 }
readline <- function(prompt = "") { .I <<- .I + 1; if (.I <= length(.Q)) .Q[.I] else "" }
assign("readline", readline, envir = globalenv())
.YN <- logical(0); .YI <- 0
feedYN <- function(...) { .YN <<- c(...); .YI <<- 0 }
askYesNo <- function(msg, default = FALSE) { .YI <<- .YI + 1; if (.YI <= length(.YN)) .YN[.YI] else default }
assignInNamespace("askYesNo", askYesNo, ns = "utils")

# --- helpers ---
ok(exists("sensanalyser_clean_raw_excel", mode = "function"),
   "guided setup loads QDA cleaning helpers before importing data")

no_numeric_error <- tryCatch({
  .interactive_select_columns(
    data.frame(product = c("A", "B"), notes = c("x", "y")),
    role = "dependent_variables"
  )
  NULL
}, error = function(e) conditionMessage(e))
ok(!is.null(no_numeric_error) && grepl("No numeric dependent-variable columns", no_numeric_error),
   "dependent-variable selection explains an empty numeric candidate list")

feed("1,3")
ok(identical(.interactive_pick_from(c("a","b","c","d"), "p"), c("a","c")), "pick_from numbers+range")
feed("")
ok(identical(.interactive_pick_from(c("a","b"), "p", allow_empty = TRUE), character(0)), "pick_from empty skip")

feed("2")
ok(identical(.interactive_select_model(list(a = list(description="A"), b = list(description="B"))), "b"),
   "select_model picks 2nd")

df <- data.frame(user = 1:4, product = rep(c("P1","P2"), 2), sweet = rnorm(4),
                 notes = letters[1:4], stringsAsFactors = FALSE)
feed("4")
ok(identical(.interactive_remove_columns(df), "notes"), "remove_columns")

df2 <- data.frame(product = c("Control","Trial A","Trial B","Trial C"), v = 1:4, stringsAsFactors = FALSE)
feed("2", "gluten free", "2,3"); feedYN(FALSE)
res <- .interactive_select_scope_and_subsets(df2, "product")
ok(res$scope == "subsets", "scope subsets")
ok(!is.null(res$subsets$gluten_free), "subset name slugified")
ok(identical(unlist(res$subsets$gluten_free$include), c("Trial A","Trial B")), "subset products")

tmp <- tempfile("proj"); dir.create(tmp)
.write_data_summary(tmp, df2, "product", c("sweet","sour"))
s <- yaml::read_yaml(file.path(tmp, "data_summary.yaml"))
ok(identical(sort(unlist(s$products)), sort(unique(df2$product))), "data_summary products")
ok(identical(unlist(s$attributes), c("sweet","sour")), "data_summary attributes")

# --- commented settings writeback round-trip ---
proj <- file.path(tempdir(), "wc_proj"); unlink(proj, recursive = TRUE)
sensanalyser_create_project(proj, overwrite = TRUE)
ok(dir.exists(file.path(proj, "outputs")) && !any(dir.exists(file.path(
  proj, "outputs", c("tables", "figures", "diagnostics", "logs")
))), "new project leaves scope-specific output folders uncreated")
dir.create(file.path(proj, "outputs", "tables"), recursive = TRUE)
sensanalyser_validate_project(proj)
ok(!dir.exists(file.path(proj, "outputs", "tables")),
   "validation removes an obsolete empty legacy output folder")
writeLines("x", file.path(proj, "data", "raw", "d.csv"))
selections <- list(dependent_variables = c("sweet","sour"), factors = c("product","session"),
                   subject_id = "user", random_effects = "user", repeated_measures_factors = character(0))
.sens_write_choices(proj, selections,
  data_files = file.path(proj, "data", "raw", "d.csv"),
  model_type = "linear_mixed_model", exclude = c("notes"), scope = "both",
  subsets = list(grp1 = list(include = list("Trial A","Trial B"))))
r <- sensanalyser_load_settings(proj)
ok(identical(unlist(r$variables$attributes), c("sweet","sour")), "writeback attributes")
ok(identical(unlist(r$variables$exclude), "notes"), "writeback exclude")
ok(identical(unlist(r$variables$extra_factors), "session"), "writeback extra_factors")
ok(r$model$type == "linear_mixed_model", "writeback model")
ok(r$scope == "both", "writeback scope")
ok(identical(unlist(r$subsets$grp1$include), c("Trial A","Trial B")), "writeback subset")
ok(isFALSE(r$advanced$interactive_setup), "writeback interactive off")
ok(identical(unlist(r$data$files), "data/raw/d.csv"), "writeback data relative")
rendered_settings <- readLines(file.path(proj, "settings.yaml"))
ok(any(grepl("guided setup", rendered_settings)), "writeback comments present")
ok(any(grepl("data_summary.yaml", rendered_settings)) &&
   any(grepl("labels.aliases.product", rendered_settings, fixed = TRUE)) &&
   any(grepl("Derived attributes", rendered_settings)),
   "guided writeback documents names, aliases, and every settings section")

# --- output routing: general/ + subsets/, and scope gating ---
cfg <- sensanalyser_settings_to_config(r)
ok(grepl("outputs/general/tables$", cfg$paths$table_root), "adapter general/ path")
ok(cfg$analysis_scope == "both", "adapter scope both")

captured <- list(); preparation_calls <- 0L
.sensanalyser_prepare_batch <- function(config) {
  preparation_calls <<- preparation_calls + 1L
  list(
    data_raw = data.frame(product = character()), data = data.frame(product = character()),
    selections = selections, config = config
  )
}
run_sensanalyser_pipeline <- function(config, prepared_batch = NULL) {
  captured[[length(captured) + 1]] <<- list(
    table_root = config$paths$table_root, batch = prepared_batch
  )
  list(ok = TRUE)
}
assign(".sensanalyser_prepare_batch", .sensanalyser_prepare_batch, envir = globalenv())
assign("run_sensanalyser_pipeline", run_sensanalyser_pipeline, envir = globalenv())
invisible(.sensanalyser_run_config(cfg))
captured_roots <- vapply(captured, `[[`, character(1), "table_root")
ok(any(grepl("outputs/general/tables$", captured_roots)), "general pass -> general/")
ok(any(grepl("outputs/subsets/grp1/tables$", captured_roots)), "subset pass -> subsets/<name>/")
ok(preparation_calls == 1L && all(vapply(captured, function(x) !is.null(x$batch), logical(1))),
   "general and subset scopes reuse one prepared batch")

cfg2 <- cfg; cfg2$analysis_scope <- "subsets"; captured <- list(); preparation_calls <- 0L
invisible(.sensanalyser_run_config(cfg2))
captured_roots <- vapply(captured, `[[`, character(1), "table_root")
ok(!any(grepl("outputs/general/tables$", captured_roots)), "scope=subsets skips general")
ok(preparation_calls == 1L, "subset-only run prepares one shared batch")

cat(sprintf("\nAll %d interactive-setup checks passed.\n", pass))
if (fail > 0) { cat(fail, "FAILED\n"); quit(status = 1) }
