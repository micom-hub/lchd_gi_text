here::i_am("R/ollama_service.R")
# This file manages interactions with the Ollama app
#
# We create an environment to store info about the Ollama process started by the R session, but not to store narratives, prompts, or responses

# Set the ollama process environemnt and start it null -----
.ollama_process_state <- new.env(parent = emptyenv())
.ollama_process_state$process <- NULL
.ollama_process_state$stdout_file <- NULL
.ollama_process_state$stderr_file <- NULL

# Functions to check Ollama status -------
# Check the status of a config object
ollama_status <- function(config = ollama_config()) {
  config <- validate_config(config)

  # Find the executable
  executable <- ollama_executable()
  reachable <- FALSE
  version <- NA_character_
  error_message <- NULL

  tryCatch(
    {
      # request the version
      response <- ollama_api_request(
        path = "/api/version",
        method = "GET",
        config = config,
        timeout = 2
      )

      # format as JSON
      response_body <- ollama_api_json(
        response,
        simplify = FALSE
      )

      # If it works, it was reachable!
      reachable <- TRUE
      version <- as.character(
        response_body$version %||% NA_character_
      )
    },
    error = function(error) {
      error_message <<- conditionMessage(error)
    }
  )

  # Export status info
  result <- list(
    installed = nzchar(executable),
    executable = if (nzchar(executable)) {
      executable
    } else {
      NA_character_
    },
    reachable = reachable,
    base_url = config$base_url,
    version = version,
    error = error_message
  )

  class(result) <- "ollama_status"

  result
}

# Helper to extract list and print it nicely
# print.ollama_status(ollama_status())
print.ollama_status <- function(x = ollama_status(), ...) {
  cat("Local Ollama status\n")
  cat("-------------------\n")
  cat(
    "Executable found: ",
    if (x$installed) "yes" else "no",
    "\n",
    sep = ""
  )
  cat(
    "API reachable:    ",
    if (x$reachable) "yes" else "no",
    "\n",
    sep = ""
  )
  cat("API address:      ", x$base_url, "\n", sep = "")

  if (!is.na(x$version)) {
    cat("Ollama version:   ", x$version, "\n", sep = "")
  }

  if (!is.null(x$error) && !x$reachable) {
    cat("Status detail:    ", x$error, "\n", sep = "")
  }

  invisible(x)
}

# Functions to start/stop Ollama -----
ollama_start <- function(
  config = ollama_config(),
  wait_seconds = 20
) {
  # validate inputs -----
  config <- validate_config(config)
  wait_seconds <- validate_positive_number(
    wait_seconds,
    "wait_seconds"
  )
  # Handle some cases of ollama already running or not findable -----

  # Check the config current status
  current_status <- ollama_status(config)

  # if it is reachable, then ollama is running
  if (current_status$reachable) {
    message("Ollama is already running.")
    message("If believe this is erroneous, run...  ")
    message(" ")
    message("   ollama_restart(confirm = TRUE)")
    message(" ")
    message("...t o clear stale ollama processes")

    return(invisible(current_status))
  }

  # find executable path
  executable <- ollama_executable()

  # if no executable found, provide some guidance
  if (!nzchar(executable)) {
    stop(
      paste0(
        "The Ollama executable could not be found. ",
        "Run `ollama_installation_help()` for guidance."
      ),
      call. = FALSE
    )
  }
  # null unless already initialized
  existing_process <- .ollama_process_state$process

  # if this isn't null, but also isn't reachable, then R started ollama, but it can't connect to the api
  if (
    !is.null(existing_process) &&
      existing_process$is_alive()
  ) {
    stop(
      paste0(
        "This R session already started an Ollama process, ",
        "but its API is not responding."
      ),
      call. = FALSE
    )
  }

  #

  # Some environment set-up to pass to processx -----
  # Create some logs in R's temp dir
  stdout_file <- tempfile(
    pattern = "ollama-stdout-",
    fileext = ".log"
  )

  stderr_file <- tempfile(
    pattern = "ollama-stderr-",
    fileext = ".log"
  )

  # Ollama expects OLLAMA_HOST as 127.0.0.1:11434 rather than
  # a full URL.

  # drop the http:// from the base url
  ollama_host <- sub(
    "^http://",
    "",
    config$base_url
  )

  # Instantiate process environment, and add ollama host url
  process_environment <- Sys.getenv()
  process_environment[["OLLAMA_HOST"]] <- ollama_host
  #ollama explicitly looks for $HOME, make sure it is present
  # use processx to start the executable,
  home_directory <- process_environment[["HOME"]]
  if (
    is.null(home_directory) ||
      length(home_directory) != 1L ||
      is.na(home_directory) ||
      !nzchar(home_directory)
  ) {
    stop(
      paste0(
        "Ollama cannot be started because the HOME environment variable ",
        "is not defined in this R session."
      ),
      call. = FALSE
    )
  }

  if (!dir.exists(home_directory)) {
    stop(
      paste0(
        "The HOME environment variable does not identify an existing ",
        "directory:\n",
        home_directory
      ),
      call. = FALSE
    )
  }

  # Initiate the process with processx -------
  process <- processx::process$new(
    command = executable,
    args = "serve",
    stdout = stdout_file, # pair out / err files
    stderr = stderr_file,
    cleanup = TRUE, #if R session exits, end the process
    env = process_environment
  ) #give ollama access to OLLAMA_HOST

  # set process state env vars for tracking
  .ollama_process_state$process <- process
  .ollama_process_state$stdout_file <- stdout_file
  .ollama_process_state$stderr_file <- stderr_file

  # set up a check to see when it opens, and kill if not within timelimit
  deadline <- Sys.time() + wait_seconds

  repeat {
    # check the status
    status <- ollama_status(config)

    if (status$reachable) {
      message("The local Ollama service is ready.")
      return(invisible(status))
    }

    if (!process$is_alive()) {
      stop(
        paste0(
          "Ollama stopped before becoming ready. ",
          "Run `ollama_log_files()` to locate its service logs."
        ),
        call. = FALSE
      )
    }

    if (Sys.time() >= deadline) {
      stop(
        paste0(
          "Ollama did not become ready within ",
          wait_seconds,
          " seconds. Run `ollama_log_files()` for details."
        ),
        call. = FALSE
      )
    }

    Sys.sleep(0.25)
  }
}

# Helper to stop an ollama process
# It will also die if the R session exits
ollama_stop <- function() {
  process <- .ollama_process_state$process

  # no process to stop
  if (is.null(process)) {
    message(
      paste0(
        "This R session did not start an Ollama process. ",
        "No process was stopped."
      )
    )

    return(invisible(FALSE))
  }

  # kill the process
  if (process$is_alive()) {
    process$kill()
    process$wait(timeout = 5000)
  }

  # reset the active process to null
  .ollama_process_state$process <- NULL

  message(
    "The Ollama process started by this R session was stopped."
  )

  invisible(TRUE)
}

# Sometimes there may be an existing ollama process in the background that prevents the R session from tracking the process. In these cases, kill the process and restart it
ollama_restart <- function(
  config = ollama_config(),
  confirm = FALSE,
  stop_wait_seconds = 10,
  start_wait_seconds = 20
) {
  # Validate inputs
  config <- validate_config(config)

  stop_wait_seconds <- validate_positive_number(
    stop_wait_seconds,
    "stop_wait_seconds"
  )

  start_wait_seconds <- validate_positive_number(
    start_wait_seconds,
    "start_wait_seconds"
  )

  # Check confirm
  if (!isTRUE(confirm)) {
    stop(
      paste0(
        "`ollama_restart()` will terminate all accessible Ollama processes, ",
        "including processes not started by this R session. This may ",
        "interrupt another program or R session.\n",
        "Run the function again with `confirm = TRUE` to continue."
      ),
      call. = FALSE
    )
  }

  message("Restarting the local Ollama service...")

  # kill the process
  ollama_force_stop(
    config = config,
    confirm = TRUE,
    wait_seconds = stop_wait_seconds
  )

  # remove stale process
  .ollama_process_state$process <- NULL

  # start over
  status <- ollama_start(
    config = config,
    wait_seconds = start_wait_seconds
  )

  if (!status$reachable) {
    stop(
      "Ollama was started, but its local API is not reachable.",
      call. = FALSE
    )
  }

  message("Ollama restarted successfully.")

  return(invisible(status))
}


# Helper to forcibly kill an ollama process, regardless of if this R session started it. Useful if running in the background, use with caution. User won't interface directly
ollama_force_stop <- function(
  config = ollama_config(),
  confirm = FALSE,
  wait_seconds = 10
) {
  config <- validate_config(config)

  wait_seconds <- validate_positive_number(
    wait_seconds,
    "wait_seconds"
  )

  if (!isTRUE(confirm)) {
    stop(
      paste0(
        "This function stops Ollama processes even when they were not ",
        "started by the current R session. This may interrupt other users, ",
        "applications, or R sessions using Ollama.\n",
        "Run the function again with `confirm = TRUE` to continue."
      ),
      call. = FALSE
    )
  }
  operating_system <- Sys.info()[["sysname"]]

  message("Attempting to stop all accessible Ollama processes...")

  # First handle any we are currently tracking
  tracked_process <- .ollama_process_state$process

  if (!is.null(tracked_process)) {
    tryCatch(
      {
        if (tracked_process$is_alive()) {
          tracked_process$kill()
          tracked_process$wait(timeout = 5000)
        }
      },
      error = function(error) {
        warning(
          paste0(
            "The tracked Ollama process could not be stopped cleanly: ",
            conditionMessage(error)
          ),
          call. = FALSE
        )
      }
    )
  }
  .ollama_process_state$process <- NULL

  # Now, check OS, and try standard stop for that one
  stop_results <- switch(
    operating_system,

    "Darwin" = stop_ollama_macos(),

    "Linux" = stop_ollama_linux(),

    "Windows" = stop_ollama_windows(),

    stop(
      paste0(
        "Force-stopping Ollama is not implemented for operating system: ",
        operating_system
      ),
      call. = FALSE
    )
  )

  # Wait for a reasonable amount of time
  deadline <- Sys.time() + wait_seconds

  repeat {
    status <- ollama_status(config)

    if (!status$reachable) {
      message("The previous Ollama service has stopped.")
      return(invisible(stop_results))
    }

    if (Sys.time() >= deadline) {
      stop(
        paste0(
          "An Ollama API is still responding at ",
          config$base_url,
          " after ",
          wait_seconds,
          " seconds.\n\n",
          "Possible explanations include:\n",
          "  - Ollama is running under another user account.\n",
          "  - Ollama is managed by a system service.\n",
          "  - The Ollama desktop application restarted it automatically.\n",
          "  - This R session lacks permission to stop it.\n\n",
          "The function did not attempt to use administrator privileges."
        ),
        call. = FALSE
      )
    }

    Sys.sleep(0.25)
  }
}

#

# get the log files for the user to read
ollama_log_files <- function() {
  c(
    stdout = .ollama_process_state$stdout_file %||% NA_character_,
    stderr = .ollama_process_state$stderr_file %||% NA_character_
  )
}


# OLLAMA Killers, specific to OS
# TESTED: MacOS : )
# STILL TEST: Windows, Linux
# These are OS specific because they use processx to run system commands
# maybe an admin issue with permissions, hopefully not @TODO CH
stop_ollama_macos <- function() {
  results <- list()

  # Ask the Ollama desktop application to quit normally.
  #
  # This is important because killing only the server process may allow the
  # desktop application to start it again automatically.
  results$quit_application <- run_system_command(
    command = "/usr/bin/osascript",
    args = c(
      "-e",
      'tell application "Ollama" to quit'
    )
  )

  # Give the application a brief opportunity to shut down normally.
  Sys.sleep(1)

  # Kill command-line processes named "ollama".
  #
  # pkill status 0 means at least one process was matched.
  # pkill status 1 means no process was matched, which is not an error here.
  results$kill_lowercase <- run_system_command(
    command = "/usr/bin/pkill",
    args = c("-x", "ollama")
  )

  # The desktop application process may be named "Ollama".
  results$kill_application <- run_system_command(
    command = "/usr/bin/pkill",
    args = c("-x", "Ollama")
  )

  validate_process_kill_result(
    results$kill_lowercase,
    acceptable_statuses = c(0L, 1L),
    description = "macOS ollama process termination"
  )

  validate_process_kill_result(
    results$kill_application,
    acceptable_statuses = c(0L, 1L),
    description = "macOS Ollama application termination"
  )

  invisible(results)
}

# linux
stop_ollama_linux <- function() {
  results <- list()

  pkill_path <- Sys.which("pkill")

  if (!nzchar(pkill_path)) {
    stop(
      paste0(
        "The `pkill` command could not be found. ",
        "R cannot force-stop the existing Ollama process."
      ),
      call. = FALSE
    )
  }

  results$kill_ollama <- run_system_command(
    command = pkill_path,
    args = c("-x", "ollama")
  )

  validate_process_kill_result(
    results$kill_ollama,
    acceptable_statuses = c(0L, 1L),
    description = "Linux Ollama process termination"
  )

  invisible(results)
}

# windows
stop_ollama_windows <- function() {
  results <- list()

  taskkill_path <- Sys.which("taskkill")

  if (!nzchar(taskkill_path)) {
    taskkill_path <- file.path(
      Sys.getenv("WINDIR"),
      "System32",
      "taskkill.exe"
    )
  }

  if (!file.exists(taskkill_path) && !nzchar(Sys.which("taskkill"))) {
    stop(
      paste0(
        "The Windows `taskkill` command could not be found. ",
        "R cannot force-stop the existing Ollama process."
      ),
      call. = FALSE
    )
  }

  results$kill_ollama <- run_system_command(
    command = taskkill_path,
    args = c(
      "/F",
      "/T",
      "/IM",
      "ollama.exe"
    )
  )

  # Windows taskkill often returns a nonzero status when no matching process
  # exists. We therefore inspect the result but rely on ollama_status() below
  # to determine whether the service actually stopped.
  if (
    results$kill_ollama$status != 0L &&
      nzchar(results$kill_ollama$stderr)
  ) {
    message(
      "Windows taskkill response: ",
      trimws(results$kill_ollama$stderr)
    )
  }

  invisible(results)
}
