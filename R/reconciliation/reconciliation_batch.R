# R/reconciliation/reconciliation_batch.R
#
# Sequential, failure-tolerant batch reconciliation.

safe_checkpoint_write <- function(
  object,
  path
) {
  directory <- dirname(path)

  if (
    !identical(directory, ".") &&
      !dir.exists(directory)
  ) {
    dir.create(
      directory,
      recursive = TRUE,
      showWarnings = FALSE
    )
  }

  temporary_path <- paste0(
    path,
    ".temporary"
  )

  saveRDS(
    object,
    temporary_path
  )

  if (file.exists(path)) {
    file.remove(path)
  }

  renamed <- file.rename(
    temporary_path,
    path
  )

  if (!renamed) {
    stop(
      "Could not finalize the checkpoint file.",
      call. = FALSE
    )
  }

  invisible(path)
}


#' Reconcile exposure payloads in a data frame
#'
#' @param data A data frame containing a payload list-column.
#' @param record Payload list-column, supplied with tidy selection.
#' @param model Exact local Ollama model tag.
#' @param ollama Local Ollama configuration.
#' @param max_attempts Maximum attempts per record.
#' @param continue_on_error Whether processing should continue after errors.
#' @param checkpoint_path Optional RDS checkpoint path.
#' @param checkpoint_every Number of processed records between checkpoints.
#' @param progress Whether to print safe progress messages.
#'
#' @return An object of class `exposure_reconciliation_batch`.
reconcile_exposure_records <- function(
  data,
  record,
  model,
  ollama = ollama_config(),
  max_attempts = 2L,
  continue_on_error = TRUE,
  checkpoint_path = NULL,
  checkpoint_every = 5L,
  progress = interactive()
) {
  validate_data_frame(data)

  record_quo <- rlang::enquo(record)

  record_selection <- tidyselect::eval_select(
    record_quo,
    data = data
  )

  if (length(record_selection) != 1L) {
    stop(
      "`record` must select exactly one payload column.",
      call. = FALSE
    )
  }

  record_column <- names(record_selection)[[1]]

  payloads <- data[[record_column]]

  if (!is.list(payloads)) {
    stop(
      "The selected payload column must be a list-column.",
      call. = FALSE
    )
  }

  results <- vector(
    mode = "list",
    length = length(payloads)
  )

  batch_started <- Sys.time()

  for (index in seq_along(payloads)) {
    payload <- payloads[[index]]
    record_id <- payload[["record_id"]] %||%
      paste0("row_", index)

    if (isTRUE(progress)) {
      message(
        "[",
        index,
        "/",
        length(payloads),
        "] Processing record ",
        record_id
      )
    }

    result <- tryCatch(
      {
        reconcile_exposure_record(
          payload = payload,
          model = model,
          ollama = ollama,
          max_attempts = max_attempts
        )
      },
      error = function(error) {
        failed <- list(
          record_id = record_id,
          status = "error",
          output = NULL,
          validation = NULL,
          attempts = tibble::tibble(),
          model = model,
          prompt_version = reconciliation_prompt_version(),
          schema_version = reconciliation_schema_version(),
          started_at = Sys.time(),
          completed_at = Sys.time(),
          elapsed_seconds = NA_real_,
          error_class = class(error)[[1]],
          error_message = conditionMessage(error)
        )

        class(failed) <- c(
          "exposure_reconciliation",
          "list"
        )

        failed
      }
    )

    results[[index]] <- result

    if (
      identical(result$status, "error") &&
        !isTRUE(continue_on_error)
    ) {
      stop(
        paste0(
          "Reconciliation failed for record ",
          record_id,
          ": ",
          result$error_message
        ),
        call. = FALSE
      )
    }

    if (
      !is.null(checkpoint_path) &&
        (index %% checkpoint_every == 0L ||
          index == length(payloads))
    ) {
      safe_checkpoint_write(
        object = list(
          model = model,
          prompt_version = reconciliation_prompt_version(),
          schema_version = reconciliation_schema_version(),
          completed_count = index,
          results = results[
            seq_len(index)
          ]
        ),
        path = checkpoint_path
      )
    }
  }

  batch_completed <- Sys.time()

  output <- list(
    model = model,
    prompt_version = reconciliation_prompt_version(),
    schema_version = reconciliation_schema_version(),
    started_at = batch_started,
    completed_at = batch_completed,
    elapsed_seconds = as.numeric(
      difftime(
        batch_completed,
        batch_started,
        units = "secs"
      )
    ),
    input = data,
    results = results
  )

  class(output) <- c(
    "exposure_reconciliation_batch",
    "list"
  )

  output
}
