here::i_am("R/utils.R")
# little helper functions to use internally

# replace x with alternative if x is null/empty
`%||%` <- function(x, alternative) {
  if (is.null(x) || length(x) == 0L) {
    alternative
  } else {
    x
  }
}

# validating stuff

# check that x is number + is positive
validate_positive_number <- function(x, argument_name) {
  valid <- is.numeric(x) &&
    length(x) == 1L &&
    !is.na(x) &&
    is.finite(x) &&
    x > 0

  if (!valid) {
    stop(
      "`",
      argument_name,
      "` must be one positive number.",
      call. = FALSE
    )
  }

  x
}

# Helper to run a system command with processx
run_system_command <- function(command, args = character()) {
  result <- processx::run(
    command = command,
    args = args,
    error_on_status = FALSE,
    echo = FALSE
  )

  list(
    command = command,
    args = args,
    status = result$status,
    stdout = result$stdout,
    stderr = result$stderr
  )
}

# check that base_url is 'url-like'
validate_local_ollama_url <- function(base_url) {
  valid_character <- is.character(base_url) &&
    length(base_url) == 1L &&
    !is.na(base_url) &&
    nzchar(trimws(base_url))

  if (!valid_character) {
    stop(
      "`base_url` must be one nonempty character value.",
      call. = FALSE
    )
  }

  base_url <- trimws(base_url)

  # Remove trailing slashes so URLs are constructed consistently.
  base_url <- sub("/+$", "", base_url)

  # Only an explicit IPv4 or IPv6 loopback address is accepted.
  local_pattern <- paste0(
    "^http://",
    "(127\\.0\\.0\\.1|\\[::1\\])",
    ":([0-9]{1,5})$"
  )

  if (!grepl(local_pattern, base_url)) {
    stop(
      paste0(
        "Ollama must use an explicit local loopback address.\n",
        "Expected a URL such as http://127.0.0.1:11434.\n",
        "Received: ",
        base_url
      ),
      call. = FALSE
    )
  }

  # port constraints
  port_text <- sub("^.*:", "", base_url)
  port <- suppressWarnings(as.integer(port_text))

  if (is.na(port) || port < 1L || port > 65535L) {
    stop(
      "The Ollama URL contains an invalid port.",
      call. = FALSE
    )
  }

  base_url
}

# check that config is foodtextllm_config class (therefore created with ollama_config())
validate_config <- function(config) {
  if (!inherits(config, "foodtextllm_config")) {
    stop(
      "`config` must be created with `ollama_config()`.",
      call. = FALSE
    )
  }

  config$base_url <- validate_local_ollama_url(config$base_url)

  config
}


# Validation helper to check if ollama was killed
# validation that the process was killed
validate_process_kill_result <- function(
  result,
  acceptable_statuses = c(0L, 1L),
  description = "process termination"
) {
  if (!is.list(result) || is.null(result$status)) {
    stop(
      "An invalid system-command result was provided.",
      call. = FALSE
    )
  }

  if (!result$status %in% acceptable_statuses) {
    stop(
      paste0(
        "A problem occurred during ",
        description,
        ".\n",
        "Exit status: ",
        result$status,
        if (nzchar(result$stderr)) {
          paste0("\nError output:\n", trimws(result$stderr))
        } else {
          ""
        },
        if (nzchar(result$stdout)) {
          paste0("\nStandard output:\n", trimws(result$stdout))
        } else {
          ""
        }
      ),
      call. = FALSE
    )
  }

  invisible(result)
}

# take a byte amount as an input and manipulate it through hierarchies
format_bytes <- function(bytes) {
  if (length(bytes) != 1L || is.na(bytes)) {
    return(NA_character_)
  }

  units <- c("B", "KB", "MB", "GB", "TB")
  value <- as.numeric(bytes)
  unit_position <- 1L

  # divide it out, check if it makes sense yet, if not, divide it out again
  while (value >= 1024 && unit_position < length(units)) {
    value <- value / 1024
    unit_position <- unit_position + 1L
  }

  paste0(
    format(round(value, 1), trim = TRUE),
    " ",
    units[[unit_position]]
  )
}

# Helper func to validate a model name input
validate_model_name <- function(model) {
  if (
    !is.character(model) ||
      length(model) != 1L ||
      is.na(model) ||
      !nzchar(trimws(model))
  ) {
    stop("`model` must be one nonempty character value.", call. = FALSE)
  }

  model <- trimws(model)

  # Allow common Ollama model identifiers but reject whitespace and shell-like
  # characters. The model name is sent as JSON, not executed as a command.
  if (!grepl("^[A-Za-z0-9._:/-]+$", model)) {
    stop(
      "`model` contains unsupported characters.",
      call. = FALSE
    )
  }

  model
}
