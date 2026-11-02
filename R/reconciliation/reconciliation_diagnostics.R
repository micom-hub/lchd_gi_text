# R/reconciliation/reconciliation_diagnostics.R
#
# Tools for investigating reconciliation validation failures.

empty_validation_issue_table <- function() {
  tibble::tibble(
    record_id = character(),
    status = character(),
    code = character(),
    severity = character(),
    message = character(),
    input_ref = character()
  )
}


#' Collect validation issues from a reconciliation batch
#'
#' @param batch An object returned by `reconcile_exposure_records()`.
#'
#' @return A tibble with one row per validation issue.
collect_reconciliation_issues <- function(batch) {
  if (
    !inherits(
      batch,
      "exposure_reconciliation_batch"
    )
  ) {
    stop(
      "`batch` must be created by `reconcile_exposure_records()`.",
      call. = FALSE
    )
  }

  issue_tables <- lapply(
    batch[["results"]],
    function(result) {
      validation <- result[["validation"]]

      if (
        is.null(validation) ||
          is.null(validation[["issues"]]) ||
          nrow(validation[["issues"]]) == 0L
      ) {
        return(empty_validation_issue_table())
      }

      issues <- validation[["issues"]]

      issues |>
        dplyr::mutate(
          record_id = as.character(
            result[["record_id"]]
          ),
          status = result[["status"]],
          .before = 1L
        )
    }
  )

  dplyr::bind_rows(issue_tables)
}


#' Summarize validation issues
#'
#' @param issues A tibble returned by
#'   `collect_reconciliation_issues()`.
#'
#' @return A tibble with issue counts.
summarize_reconciliation_issues <- function(issues) {
  if (!is.data.frame(issues)) {
    stop(
      "`issues` must be a data frame.",
      call. = FALSE
    )
  }

  if (nrow(issues) == 0L) {
    return(
      tibble::tibble(
        code = character(),
        severity = character(),
        affected_records = integer(),
        issue_count = integer()
      )
    )
  }

  issues |>
    dplyr::group_by(
      .data$code,
      .data$severity
    ) |>
    dplyr::summarise(
      affected_records = dplyr::n_distinct(
        .data$record_id
      ),
      issue_count = dplyr::n(),
      .groups = "drop"
    ) |>
    dplyr::arrange(
      dplyr::desc(.data$issue_count),
      .data$code
    )
}

#' Summarize reconciliation status by record
#'
#' @param batch A reconciliation batch.
#'
#' @return A tibble with one row per record.
summarize_reconciliation_records <- function(batch) {
  issues <- collect_reconciliation_issues(batch)

  issue_counts <- issues |>
    dplyr::group_by(.data$record_id) |>
    dplyr::summarise(
      validation_issue_count = dplyr::n(),
      validation_error_count = sum(
        .data$severity == "error"
      ),
      validation_warning_count = sum(
        .data$severity == "warning"
      ),
      validation_review_count = sum(
        .data$severity == "review"
      ),
      .groups = "drop"
    )

  result_summary <- purrr::map_dfr(
    batch[["results"]],
    function(result) {
      validation <- result[["validation"]]

      tibble::tibble(
        record_id = as.character(
          result[["record_id"]]
        ),
        status = result[["status"]],
        valid = if (is.null(validation)) {
          FALSE
        } else {
          isTRUE(validation[["valid"]])
        },
        attempt_count = nrow(
          result[["attempts"]]
        ),
        elapsed_seconds = result[["elapsed_seconds"]],
        error_class = result[["error_class"]],
        error_message = result[["error_message"]]
      )
    }
  )

  result_summary |>
    dplyr::left_join(
      issue_counts,
      by = "record_id"
    ) |>
    dplyr::mutate(
      dplyr::across(
        c(
          .data$validation_issue_count,
          .data$validation_error_count,
          .data$validation_warning_count,
          .data$validation_review_count
        ),
        ~ tidyr::replace_na(.x, 0L)
      )
    )
}
