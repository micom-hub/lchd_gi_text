# R/reconciliation/reconciliation_chat.R
#
# Creates fresh ellmer/Ollama chats for exposure reconciliation/structuring
#' Create a local reconciliation chat
#'
#' @param model Exact installed Ollama model tag.
#' @param ollama Local Ollama configuration.
#' @param system_prompt System prompt text.
#'
#' @return An ellmer chat object.
create_reconciliation_chat <- function(
  model,
  ollama = ollama_config(),
  system_prompt = partially_structured_system_prompt()
) {
  ollama <- validate_config(ollama)
  model <- validate_model_name(model)

  status <- ollama_status(ollama)

  if (!status$reachable) {
    stop(
      paste0(
        "The local Ollama service is not reachable at ",
        ollama$base_url,
        "."
      ),
      call. = FALSE
    )
  }

  if (!ollama_model_installed(model, ollama)) {
    stop(
      paste0(
        "The requested Ollama model is not installed: ",
        model
      ),
      call. = FALSE
    )
  }

  constructor_formals <- names(
    formals(ellmer::chat_ollama)
  )

  arguments <- list(
    model = model,
    system_prompt = system_prompt
  )

  if ("base_url" %in% constructor_formals) {
    arguments[["base_url"]] <- ollama$base_url
  } else if ("host" %in% constructor_formals) {
    arguments[["host"]] <- ollama$base_url
  } else if ("url" %in% constructor_formals) {
    arguments[["url"]] <- ollama$base_url
  } else {
    stop(
      paste0(
        "The installed version of `ellmer::chat_ollama()` does not expose ",
        "a recognized local endpoint argument. Review its current API with ",
        "`args(ellmer::chat_ollama)`."
      ),
      call. = FALSE
    )
  }

  do.call(
    ellmer::chat_ollama,
    arguments
  )
}
