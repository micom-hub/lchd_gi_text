here::i_am("R/ollama/ollama_installation.R")

# Functions to check if/where Ollama is installed, or link user to the download link

# Return the path to the ollama executable using a few inferred locations. If it isn't found, return ""
ollama_executable <- function() {
  # First look for Ollama on the OS .exe path
  from_path <- Sys.which("ollama")

  # if that's a path, then cool! normalize and return
  if (nzchar(from_path)) {
    return(
      normalizePath(
        from_path,
        winslash = "/",
        mustWork = TRUE
      )
    )
  }
  
operating_system <- Sys.info()[["sysname"]]

  # If that doesn't work, extract candidates based on OS
  candidates <- switch(
    operating_system,

    # if windows, look in local_app_data and program_files
    "Windows" = {
      local_app_data <- Sys.getenv("LOCALAPPDATA")
      program_files <- Sys.getenv("ProgramFiles")

      c(
        if (nzchar(local_app_data)) {
          file.path(
            local_app_data,
            "Programs",
            "Ollama",
            "ollama.exe"
          )
        },
        if (nzchar(program_files)) {
          file.path(
            program_files,
            "Ollama",
            "ollama.exe"
          )
        }
      )
    },

    # if Mac, look upder Applications for Ollama.app
    "Darwin" = c(
      "/Applications/Ollama.app/Contents/Resources/ollama",
      path.expand(
        "~/Applications/Ollama.app/Contents/Resources/ollama"
      )
    ),

    # if Linux, check the bins
    "Linux" = c(
      "/usr/local/bin/ollama",
      "/usr/bin/ollama",
      path.expand("~/.local/bin/ollama")
    ),

    character()
  )

  candidates <- candidates[
    !is.na(candidates) & nzchar(candidates)
  ]

  # see if any of the candidates are out there
  matches <- candidates[file.exists(candidates)]

  # return blank for ollama_executable if it doesn't exist
  if (length(matches) == 0L) {
    return("")
  }

  # otherwise, return the normalized path that matches
  return(
    normalizePath(
      matches[[1]],
      winslash = "/",
      mustWork = TRUE
    )
  )
}

# check if ollama_executable doesn't return ""
ollama_is_installed <- function() {
  nzchar(ollama_executable())
}

# Silly function to give ollama installation help, try to open the download link if in an IDE (likely)
ollama_installation_help <- function(open_webpage = interactive()) {
  download_url <- "https://ollama.com/download"

  operating_system <- Sys.info()[["sysname"]]

  cat("----------------------------\n")
  cat("Ollama installation guidance\n")
  cat("----------------------------\n")
  cat("Detected operating system: ", operating_system, "\n", sep = "")
  cat("\n")
  cat(
    "Ollama is system software required to run LLMs locally and is not installed by R.\n"
  )
  cat("\n")
  cat("Visit the Official download page...\n")
  cat("  ", download_url, "\n", sep = "")
  cat("... for instructions to download manually, or via terminal\n")

  cat("\n")
  cat("After installation, return to R and run:\n")
  cat("  ollama_status()\n")
  cat("to verify the installation worked")

  if (isTRUE(open_webpage)) {
    cat("\n", "Linking to download page now...")

    utils::browseURL(download_url)
  }

  invisible(download_url)
}
