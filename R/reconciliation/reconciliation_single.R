# R/reconciliation/reconciliation_single.R
#
# Runs one local structured reconciliation request.

reconciliation_attempt <- function(
  attempt,
  status,
  started_at,
  completed_at,
  error_class = NA_character_,
  error_message = NA_character_
) {
  tibble::tibble(
    attempt = as.integer(attempt),
    status = status,
    started_at = started_at,
    completed_at = completed_at,
    elapsed_seconds = as.numeric(
      difftime(
        completed_at,
        started_at,
        units = "secs"
      )
    ),
    error_class = error_class,
    error_message = error_message
  )
}


#' Reconcile one deterministic exposure payload
#'
#' @param payload A compact payload created by
#'   `make_exposure_llm_payload()`.
#' @param model Exact local Ollama model tag.
#' @param ollama Local Ollama configuration.
#' @param max_attempts Maximum number of attempts.
#'
#' @return A nested reconciliation result.
reconcile_exposure_record <- function(
  payload,
  model,
  ollama = ollama_config(),
  max_attempts = 2L
) {
  if (!is.list(payload)) {
    stop("`payload` must be a list.", call. = FALSE)
  }

  if (
    !is.numeric(max_attempts) ||
      length(max_attempts) != 1L ||
      is.na(max_attempts) ||
      max_attempts < 1L
  ) {
    stop(
      "`max_attempts` must be a positive whole number.",
      call. = FALSE
    )
  }

  max_attempts <- as.integer(max_attempts)

  record_id <- payload[["record_id"]] %||%
    NA_character_

  overall_started <- Sys.time()
  attempts <- list()
  final_output <- NULL
  final_validation <- NULL
  final_status <- "error"
  final_error_class <- NA_character_
  final_error_message <- NA_character_

  for (attempt_number in seq_len(max_attempts)) {
    attempt_started <- Sys.time()

    attempt_result <- tryCatch(
      {
        # Fresh chat context for each attempt and record.
        chat <- create_reconciliation_chat(
          model = model,
          ollama = ollama
        )

        output <- chat$chat_structured(
          build_reconciliation_prompt(payload),
          type = partially_structured_output_type()
        )

        validation <- validate_reconciled_exposure(
          output = output,
          payload = payload
        )

        list(
          status = if (validation$valid) {
            "success"
          } else {
            "validation_error"
          },
          output = output,
          validation = validation,
          error_class = NA_character_,
          error_message = NA_character_
        )
      },
      error = function(error) {
        list(
          status = "error",
          output = NULL,
          validation = NULL,
          error_class = class(error)[[1]],
          error_message = conditionMessage(error)
        )
      }
    )

    attempt_completed <- Sys.time()

    attempts[[attempt_number]] <-
      reconciliation_attempt(
        attempt = attempt_number,
        status = attempt_result$status,
        started_at = attempt_started,
        completed_at = attempt_completed,
        error_class = attempt_result$error_class,
        error_message = attempt_result$error_message
      )

    final_output <- attempt_result$output
    final_validation <-
      attempt_result$validation

    final_status <- attempt_result$status
    final_error_class <-
      attempt_result$error_class

    final_error_message <-
      attempt_result$error_message

    if (identical(final_status, "success")) {
      break
    }
  }

  overall_completed <- Sys.time()

  result <- list(
    record_id = record_id,
    status = final_status,
    output = final_output,
    validation = final_validation,
    attempts = dplyr::bind_rows(attempts),
    model = model,
    prompt_version = reconciliation_prompt_version(),
    schema_version = reconciliation_schema_version(),
    started_at = overall_started,
    completed_at = overall_completed,
    elapsed_seconds = as.numeric(
      difftime(
        overall_completed,
        overall_started,
        units = "secs"
      )
    ),
    error_class = final_error_class,
    error_message = final_error_message
  )

  class(result) <- c(
    "exposure_reconciliation",
    "list"
  )

  result
}
