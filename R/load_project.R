here::i_am("R/load_project.R")
# Loader for experimentation at this point. This will go away once it's in a package

packages_script <- here::here("R/setup_dependencies.R")
this_script <- here::here("R/load_project.R")

source(packages_script)

function_files <- c(
  # Existing utilities and Ollama infrastructure
  "R/utils.R",
  "R/ollama/config.R",
  "R/ollama/ollama_api.R",
  "R/ollama/ollama_service.R",
  "R/ollama/ollama_models.R",
  "R/ollama/ollama_installation.R",
  "R/ollama/system_check.R",

  # MDSS Files
  "R/MDSS/partially_structured_json.R",
  "R/MDSS/exposure_payload.R",
  "R/MDSS/mdss_wrappers.R",


  # Reconciliation infrastructure - partially structured -> structured
  "R/reconciliation/reconciliation_schema.R",
  "R/reconciliation/reconciliation_prompt.R",
  "R/reconciliation/reconciliation_chat.R",
  "R/reconciliation/reconciliation_validate.R",
  "R/reconciliation/reconciliation_single.R",
  "R/reconciliation/reconciliation_batch.R",
  "R/reconciliation/reconciliation_tidy.R",

  # Wrappers
  "R/workflows/process_exposures.R"
)

for (file in function_files) {
  if (!file.exists(file)) {
    stop(
      "Missing project file: ",
      file,
      call. = FALSE
    )
  }

  source(file, local = globalenv())
}

print("All repo scripts under ./R/ have been sourced")
