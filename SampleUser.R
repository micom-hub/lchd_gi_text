here::i_am("SampleUser.R")
# An example of how a user might go about using this stuff
# this loads all dependencies and sources all of our functions
# equivalenet to library(`whatever this package ends up called`)

load_project_path <- here::here("R/load_project.R")
source(load_project_path)

# OLLAMA SETUP --------

# 1) Make and inspect a local ollama config
config <- ollama_config()
config

# 2) Check the config status (is it installed, is it running)
status <- ollama_status(config)
status

# 3) If not installed, open the instructions
if (!status$installed) {
  ollama_installation_help(open_webpage = TRUE)
}

# 4) If it is installed, but it isn't running, start it
if (status$installed && !status$reachable) {
  status <- ollama_start(config)
}
#run: ollama_restart(confirm = TRUE) if R session doesn't like whats going on

# Looking at models 

# 5) List models currently installed
if (status$reachable) {
  models <- ollama_model_list(config)
  print(models)
}

# 6) Run the combined diagnostic to identify next steps
print.system_check()

# 7. Download a model (deliberately not automatic, we can figure out how to handle this later)
#
# ollama_model_pull(
#   model = "model_we_like:tag",
#   config = config,
#   confirm_download = TRUE
# )

# MDSS Pipeline ------

library(tidyverse)

# read in MDSS data
path_to_cyclo <- 'C:/Users/alvarojh/University of Michigan Dropbox/Alvaro Hurtado/20261027_livingston_cyclo.csv'

df <- read_csv(path_to_cyclo)

# Deterministic pre-processing of MDSS exposure data

prepared <- prepare_mdss_exposures(
  data = df,
  id = InvestigationID,
  onset_date = Onset_Date,
  interview_date = Date_of_interview,
  drop_without_exposure = TRUE
)

print(prepared)


# Inspect one compact payload before model use.
cat(
  jsonlite::toJSON(
    prepared$llm_payload[[1]],
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null",
    na = "null"
  )
)

# Reconcile a small subset
test_prepared <- prepared |>
  slice_sample(n = 3L)

test_results <- reconcile_prepared_exposures(
  prepared = test_prepared,
  model = "llama3.2:1b",
  max_attempts = 2L,
  progress = TRUE
)

# Inspect outputs

exposure_events(test_results)

exposure_foods(test_results)

unlinked_exposure_foods(test_results)

exposure_diagnostics(test_results)

# Full wrapper -------

# results <- process_mdss_exposures(
#   data = df,
#   id = InvestigationID,
#   onset_date = Onset_Date,
#   interview_date = Date_of_interview,
#   model = "your-installed-model:tag",
#   checkpoint_path = "results/mdss_checkpoint.rds"
# )