here::i_am("R/ollama_models.R")
# These functions interact with ollama to list, download, check, or delete ollama models

# Return a list of installed models available in Ollama
ollama_model_list <- function(config = ollama_config()) {
  config <- validate_config(config)

  # from Ollama website:
  response <- ollama_api_request(
    path = "/api/tags",
    method = "GET",
    config = config
  )

  #jsonify it
  response_body <- ollama_api_json(
    response,
    simplify = FALSE
  )

  models <- response_body$models %||% list()

  if (length(models) == 0L) {
    return(
      data.frame(
        name = character(),
        size_bytes = numeric(),
        size_display = character(),
        modified_at = character(),
        stringsAsFactors = FALSE
      )
    )
  }

  model_rows <- lapply(
    models,
    function(model) {
      size_bytes <- as.numeric(
        model$size %||% NA_real_
      )

      data.frame(
        name = as.character(
          model$name %||% NA_character_
        ),
        size_bytes = size_bytes,
        size_display = format_bytes(size_bytes),
        modified_at = as.character(
          model$modified_at %||% NA_character_
        ),
        stringsAsFactors = FALSE
      )
    }
  )

  # return a row for each model, bound
  do.call(rbind, model_rows)
}


# Check if a model name is within a model list
ollama_model_installed <- function(
  model,
  config = ollama_config()
) {
  model <- validate_model_name(model)
  models <- ollama_model_list(config)

  if (nrow(models) == 0L) {
    return(FALSE)
  }

  model %in% models$name
}

# Equivalent of ollamaR "pull" to download an ollama model
ollama_model_pull <- function(
  model,
  config = ollama_config(),
  confirm_download = FALSE
) {
  # validate inputs
  config <- validate_config(config)
  model <- validate_model_name(model)

  # check confirm
  if (confirm_download) {
    stop(
      paste0(
        "Downloading a model requires internet access and may use ",
        "several gigabytes of disk space. Run the function again with ",
        "`confirm_download = TRUE` to proceed."
      ),
      call. = FALSE
    )
  }

  # check that we have ollama running
  status <- ollama_status(config)

  # if not reachable, prompt to start it up
  if (!status$reachable) {
    stop(
      paste0(
        "The local Ollama service is not reachable. ",
        "Run `ollama_start()` first."
      ),
      call. = FALSE
    )
  }

  # check if it's already installed and quit out
  if (ollama_model_installed(model, config)) {
    message(
      "The model is already installed: ",
      model
    )

    return(invisible(TRUE))
  }

  # begin download process -------
  message("Downloading model: ", model)
  message(
    paste0(
      "This can take several minutes. You will be notified when the process completes"
    )
  )

  # post a pull request
  response <- ollama_api_request(
    path = "/api/pull",
    method = "POST",
    body = list(
      model = model,
      stream = FALSE
    ),
    config = config,
    timeout = config$download_timeout
  )

  # Responds with status updates and a current status message
  result <- ollama_api_json(
    response,
    simplify = FALSE
  )

  if (!ollama_model_installed(model, config)) {
    warning(
      paste0(
        "Ollama completed the request, but the exact model name was ",
        "not found in the installed-model list."
      ),
      call. = FALSE
    )
  } else {
    message("Model download completed: ", model)
  }

  invisible(result)
}

ollama_model_remove <- function(
  model,
  config = ollama_config(),
  confirm_removal = FALSE
) {
  config <- validate_config(config)
  model <- validate_model_name(model)

  if (!confirm_removal) {
    stop(
      paste0(
        "Model removal is permanent. Run the function again with ",
        "`confirm_removal = TRUE` to proceed."
      ),
      call. = FALSE
    )
  }

  if (!ollama_model_installed(model, config)) {
    message("The model is not installed: ", model)
    return(invisible(FALSE))
  }

  ollama_api_request(
    path = "/api/delete",
    method = "DELETE",
    body = list(model = model),
    config = config
  )

  message("Removed model: ", model)

  invisible(TRUE)
}
