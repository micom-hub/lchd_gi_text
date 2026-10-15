here::i_am("R/ollama_api.R")

# This file contains the code to communicate with Ollama
# ollama_api_request() will be wrapped up in future code

# validate a path, fetch a config, and combine them to make an api url
ollama_api_url <- function(
  path,
  config = ollama_config()
) {
  # Validate inputs

  # check that the fresh config is valid
  config <- validate_config(config)

  valid_path <- is.character(path) &&
    length(path) == 1L &&
    !is.na(path) &&
    nzchar(path)

  if (!valid_path) {
    stop(
      "`path` must be one nonempty character value.",
      call. = FALSE
    )
  }

  if (!startsWith(path, "/")) {
    path <- paste0("/", path)
  }

  paste0(config$base_url, path)
}

ollama_api_request <- function(
  path,
  method = c("GET", "POST", "DELETE"),
  body = NULL,
  config = ollama_config(),
  timeout = NULL
) {
  # Handling inputs ------
  config <- validate_config(config)
  method <- match.arg(method)

  # grab defaults from config object
  if (is.null(timeout)) {
    timeout <- config$request_timeout
  } else {
    timeout <- validate_positive_number(timeout, "timeout")
  }

  # get url from config url + path
  url <- ollama_api_url(path, config)

  # HTTP request config ------
  request <- httr2::request(url)
  # tell request if it is GET, POST, or DELETE
  request <- httr2::req_method(request, method)
  # add timeout
  request <- httr2::req_timeout(
    request,
    seconds = timeout
  )
  # Disallow any kind of HTTP proxy as a safeguard against local traffic going anywhere else, this might be too strict depending on how org proxys work
  request <- httr2::req_options(
    request,
    proxy = ""
  )

  # HTTR request body -----
  if (!is.null(body)) {
    # body might be an R list, encode it as JSON
    request <- httr2::req_body_json(
      request,
      data = body,
      auto_unbox = TRUE
    )
  }
  # prevent req_perform from throwing R errors
  # we will catch them instead to extract info
  request <- httr2::req_error(
    request,
    is_error = function(response) FALSE
  )

  # perform the request
  response <- httr2::req_perform(request)

  # if we errrored, extract status code and stop
  if (httr2::resp_is_error(response)) {
    status_code <- httr2::resp_status(response)

    stop(
      paste0(
        "The local Ollama API returned HTTP status ",
        status_code,
        "."
      ),
      call. = FALSE
    )
  }

  # if we didn't error, return the response
  return(response)
}

ollama_api_json <- function(response, simplify = FALSE) {
  httr2::resp_body_json(
    response,
    simplifyVector = simplify
  )
}
