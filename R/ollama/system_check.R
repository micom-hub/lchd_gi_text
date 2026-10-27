here::i_am("R/ollama/system_check.R")
# High level diagnostics check, this could be front facing

system_check <- function(
  config = ollama_config(),
  print_result = TRUE
) {
  # First check the current status
  config <- validate_config(config)
  status <- ollama_status(config)

  # If api is reachable, print a model list, otherwise, empty
  models <- if (status$reachable) {
    tryCatch(
      ollama_model_list(config),
      error = function(error) {
        data.frame()
      }
    )
  } else {
    data.frame()
  }

  #  diagnostic list
  result <- list(
    checked_at = Sys.time(),
    r_version = as.character(getRversion()),
    operating_system = Sys.info()[["sysname"]],
    architecture = Sys.info()[["machine"]],
    ollama_installed = status$installed,
    ollama_reachable = status$reachable,
    ollama_version = status$version,
    ollama_address = status$base_url,
    model_count = nrow(models),
    models = models,
    ready = status$reachable && nrow(models) > 0L
  )

  if (isTRUE(print_result)) {
    print(result)
  }

  # return the result invisibly to allow other funcs to do system checks
  invisible(result)
}

# prettier way to show results and try to provide user guidance
print.system_check <- function(x = system_check(print_result = F)) {
  # Print off the results diagnostics -----
  cat("Local LLM system check\n")
  cat("======================\n")
  cat("Checked at:       ", format(x$checked_at), "\n", sep = "")
  cat("R version:        ", x$r_version, "\n", sep = "")
  cat("Operating system: ", x$operating_system, "\n", sep = "")
  cat("Architecture:     ", x$architecture, "\n", sep = "")
  cat(
    "Ollama installed: ",
    if (x$ollama_installed) "yes" else "no",
    "\n",
    sep = ""
  )
  cat(
    "Ollama reachable: ",
    if (x$ollama_reachable) "yes" else "no",
    "\n",
    sep = ""
  )
  cat("Ollama address:   ", x$ollama_address, "\n", sep = "")
  cat("Installed models: ", x$model_count, "\n", sep = "")
  cat(
    "Ready for use:    ",
    if (x$ready) "yes" else "no",
    "\n",
    sep = ""
  )

  # indicates that install worked, but it can't run
  if (
    x$ollama_installed &&
      !x$ollama_reachable
  ) {
    cat("\nSuggested next step:\n")
    cat("  Run `ollama_start()`.\n")
  }

  if (!x$ollama_installed) {
    cat("\nSuggested next step:\n")
    cat("  Run `ollama_installation_help()`.\n")
  }

  # No models installed yet
  if (
    x$ollama_reachable &&
      x$model_count == 0L
  ) {
    cat("\nSuggested next step:\n")
    cat("  Install a model with `ollama_model_pull()`.\n")
  }

  # Just return installed models
  if (x$model_count > 0L) {
    cat("\nInstalled models:\n")
    print(x$models, row.names = FALSE)
  }

  invisible(x)
}
