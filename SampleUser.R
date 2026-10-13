# An example of how a user might go about using this stuff

# this loads all dependencies and sources all of our functions
# equivalenet to library(`whatever this package ends up called`)

load_project_path <- file.path(getwd(), "R/load_project.R")
source(load_project_path)

# Set-up -------

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

# Looking at models ---------

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
