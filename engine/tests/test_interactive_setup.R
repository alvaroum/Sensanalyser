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
ok(any(grepl("guided setup", readLines(file.path(proj, "settings.yaml")))), "writeback comments present")

# --- output routing: general/ + subsets/, and scope gating ---
cfg <- sensanalyser_settings_to_config(r)
ok(grepl("outputs/general/tables$", cfg$paths$table_root), "adapter general/ path")
ok(cfg$analysis_scope == "both", "adapter scope both")

captured <- list()
run_sensanalyser_pipeline <- function(config) { captured[[length(captured)+1]] <<- config$paths$table_root; list(ok = TRUE) }
assign("run_sensanalyser_pipeline", run_sensanalyser_pipeline, envir = globalenv())
invisible(.sensanalyser_run_config(cfg))
ok(any(grepl("outputs/general/tables$", unlist(captured))), "general pass -> general/")
ok(any(grepl("outputs/subsets/grp1/tables$", unlist(captured))), "subset pass -> subsets/<name>/")

cfg2 <- cfg; cfg2$analysis_scope <- "subsets"; captured <- list()
invisible(.sensanalyser_run_config(cfg2))
ok(!any(grepl("outputs/general/tables$", unlist(captured))), "scope=subsets skips general")

cat(sprintf("\nAll %d interactive-setup checks passed.\n", pass))
if (fail > 0) { cat(fail, "FAILED\n"); quit(status = 1) }
