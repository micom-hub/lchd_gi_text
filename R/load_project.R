
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
  
  # Narrative extraction
  "R/extraction_specifications_legacy/extraction_spec.R",
  "R/extraction/extraction_schema.R",
  "R/extraction/extraction_prompt.R",
  "R/extraction/event_food_schema.R",
  "R/extraction/event_food_prompt.R",

  # Wrappers
  "R/workflows/process_exposures.R"
)



for (file in function_files) {
  file_path <- here::here(file)

  if (!file.exists(file_path)) {
    stop("Missing project file: ", file_path, call. = FALSE)
  }

  source(file_path, local = globalenv())
}

message("All listed project scripts have been sourced.")