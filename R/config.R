here::i_am("R/config.R")

# Defines how the repo connects to Ollama
#
# Ollama API intro documentation: https://docs.ollama.com/api/introduction
#
# 127.0.0.1 is the default address to refer to "this computer", sometimes called IPv4 lookback address (localhost)
# Defining a config object puts all the API config settings in one place and lets us pass it from function to function easily

#' Create an Ollama configuration
#'
#' Creates a configuration object that contains the address of the local Ollama API and some default timeout settings
#'
#' @param base_url Address of the local Ollama API
#' @param request_timeout default timeout for short API requests (sec)
#' @param download_timeout Timeout for model downloads (sec)
#'
#' @return A list with the class `foodtextllm_config`
ollama_config <- function(
  base_url = "http://127.0.0.1:11434",
  request_timeout = 10,
  download_timeout = 3600
) {
  # base_url is url-like
  base_url <- validate_local_ollama_url(base_url)

  # request timeout and download timeout are valid/positive
  request_timeout <- validate_positive_number(
    request_timeout,
    "request_timeout"
  )

  download_timeout <- validate_positive_number(
    download_timeout,
    "download_timeout"
  )

  # roll it up in a config
  config <- list(
    base_url = base_url,
    request_timeout = request_timeout,
    download_timeout = download_timeout
  )

  # assign it this class so
  class(config) <- "foodtextllm_config"

  config
}
