here::i_am("R/setup_dependencies.R")
# run this once while setting up the project on a new computer

# httr2 needed to send requests to local ollama
# processx for starting and managing ollama process
# setup_dependencies.R
#
# Run this script once when setting up the project on a new computer.
# It installs only the R packages needed by the initial Ollama management
# layer.

required_packages <- c(
  # admin
  "here",
  # llm interface
  "ellmer",
  "vitals",

  # ollama process management
  "httr2",
  "processx",

  # processing
  "tidyverse",
  "tidymodels",
  "tidyselect",
  "jsonlite",
  "rlang",
  "cli"
)

installed_packages <- rownames(utils::installed.packages())

missing_packages <- setdiff(
  required_packages,
  installed_packages
)

if (length(missing_packages) == 0L) {
  message("All required R packages are already installed.")
} else {
  message(
    "Installing missing R packages: ",
    paste(missing_packages, collapse = ", ")
  )

  install.packages(
    missing_packages,
    repos = "https://cloud.r-project.org"
  )
}

invisible(lapply(required_packages, library, character.only = T))

message("R dependency setup is complete.")
