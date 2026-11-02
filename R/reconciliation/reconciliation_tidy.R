# R/reconciliation/reconciliation_tidy.R
#
# Converts nested reconciliation results into tidy output tables that are easier to work with

empty_interview_table <- function() {
  tibble::tibble(
    record_id = character(),
    record_needs_review = logical(),
    record_review_reasons = list(),
    model = character(),
    prompt_version = character(),
    schema_version = character(),
    status = character(),
    elapsed_seconds = double()
  )
}


empty_event_table <- function() {
  tibble::tibble(
    record_id = character(),
    event_id = character(),
    event_type = character(),
    date_text = character(),
    resolved_date = character(),
    meal_type = character(),
    source_name = character(),
    source_type = character(),
    location_text = character(),
    linkage_type = character(),
    supporting_input_refs = list(),
    event_needs_review = logical(),
    event_review_reasons = list()
  )
}


empty_food_table <- function() {
  tibble::tibble(
    record_id = character(),
    event_id = character(),
    food_id = character(),
    food_text = character(),
    explicit_components = list(),
    respondent_relationship = character(),
    uncertainty = character(),
    linkage_type = character(),
    supporting_input_refs = list(),
    food_needs_review = logical(),
    food_review_reasons = list()
  )
}


empty_unlinked_table <- function() {
  tibble::tibble(
    record_id = character(),
    input_ref = character(),
    item_id = character(),
    food_text = character(),
    reason = character(),
    needs_review = logical()
  )
}


tidy_one_reconciliation <- function(result) {
  record_id <- as.character(
    result[["record_id"]]
  )

  output <- result[["output"]]

  if (is.null(output)) {
    return(
      list(
        interviews = tibble::tibble(
          record_id = record_id,
          record_needs_review = TRUE,
          record_review_reasons = list("output_validation_failed"),
          model = result[["model"]],
          prompt_version = result[["prompt_version"]],
          schema_version = result[["schema_version"]],
          status = result[["status"]],
          elapsed_seconds = result[["elapsed_seconds"]]
        ),
        events = empty_event_table(),
        foods = empty_food_table(),
        unlinked_foods = empty_unlinked_table()
      )
    )
  }

  interview_table <- tibble::tibble(
    record_id = record_id,
    record_needs_review = isTRUE(
      output[["record_needs_review"]]
    ),
    record_review_reasons = list(
      normalize_character_array(
        output[["record_review_reasons"]]
      )
    ),
    model = result[["model"]],
    prompt_version = result[["prompt_version"]],
    schema_version = result[["schema_version"]],
    status = result[["status"]],
    elapsed_seconds = result[["elapsed_seconds"]]
  )

  events <- as_object_list(
    output[["events"]]
  )

  event_rows <- list()
  food_rows <- list()

  for (event_index in seq_along(events)) {
    event <- events[[event_index]]

    event_id <- sprintf(
      "event_%03d",
      event_index
    )

    event_rows[[event_index]] <-
      tibble::tibble(
        record_id = record_id,
        event_id = event_id,
        event_type = empty_to_na(
          event[["event_type"]]
        ),
        date_text = empty_to_na(
          event[["date_text"]]
        ),
        resolved_date = empty_to_na(
          event[["resolved_date"]]
        ),
        meal_type = empty_to_na(
          event[["meal_type"]]
        ),
        source_name = empty_to_na(
          event[["source_name"]]
        ),
        source_type = empty_to_na(
          event[["source_type"]]
        ),
        location_text = empty_to_na(
          event[["location_text"]]
        ),
        linkage_type = empty_to_na(
          event[["linkage_type"]]
        ),
        supporting_input_refs = list(
          normalize_character_array(
            event[["supporting_input_refs"]]
          )
        ),
        event_needs_review = isTRUE(
          event[["event_needs_review"]]
        ),
        event_review_reasons = list(
          normalize_character_array(
            event[["event_review_reasons"]]
          )
        )
      )

    foods <- as_object_list(
      event[["foods"]]
    )

    if (length(foods) > 0L) {
      for (food_index in seq_along(foods)) {
        food <- foods[[food_index]]

        food_rows[[length(food_rows) + 1L]] <-
          tibble::tibble(
            record_id = record_id,
            event_id = event_id,
            food_id = sprintf(
              "food_%03d",
              food_index
            ),
            food_text = empty_to_na(
              food[["food_text"]]
            ),
            explicit_components = list(
              normalize_character_array(
                food[["explicit_components"]]
              )
            ),
            respondent_relationship = empty_to_na(
              food[["respondent_relationship"]]
            ),
            uncertainty = empty_to_na(
              food[["uncertainty"]]
            ),
            linkage_type = empty_to_na(
              food[["linkage_type"]]
            ),
            supporting_input_refs = list(
              normalize_character_array(
                food[["supporting_input_refs"]]
              )
            ),
            food_needs_review = isTRUE(
              food[["food_needs_review"]]
            ),
            food_review_reasons = list(
              normalize_character_array(
                food[["food_review_reasons"]]
              )
            )
          )
      }
    }
  }

  event_table <- if (length(event_rows)) {
    dplyr::bind_rows(event_rows)
  } else {
    empty_event_table()
  }

  food_table <- if (length(food_rows)) {
    dplyr::bind_rows(food_rows)
  } else {
    empty_food_table()
  }

  unlinked <- as_object_list(
    output[["unlinked_affirmative_foods"]]
  )

  unlinked_table <- if (length(unlinked)) {
    purrr::map_dfr(
      unlinked,
      function(item) {
        tibble::tibble(
          record_id = record_id,
          input_ref = empty_to_na(
            item[["input_ref"]]
          ),
          item_id = empty_to_na(
            item[["item_id"]]
          ),
          food_text = empty_to_na(
            item[["food_text"]]
          ),
          reason = empty_to_na(
            item[["reason"]]
          ),
          needs_review = isTRUE(
            item[["needs_review"]]
          )
        )
      }
    )
  } else {
    empty_unlinked_table()
  }

  list(
    interviews = interview_table,
    events = event_table,
    foods = food_table,
    unlinked_foods = unlinked_table
  )
}


tidy_reconciliation_batch <- function(batch) {
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

  tidy_results <- lapply(
    batch[["results"]],
    tidy_one_reconciliation
  )

  interviews <- purrr::map_dfr(
    tidy_results,
    "interviews"
  )

  events <- purrr::map_dfr(
    tidy_results,
    "events"
  )

  foods <- purrr::map_dfr(
    tidy_results,
    "foods"
  )

  unlinked_foods <- purrr::map_dfr(
    tidy_results,
    "unlinked_foods"
  )

  diagnostics <- purrr::map_dfr(
    batch[["results"]],
    function(result) {
      validation <- result[["validation"]]

      tibble::tibble(
        record_id = result[["record_id"]],
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
        validation_issue_count = if (is.null(validation)) {
          NA_integer_
        } else {
          nrow(validation[["issues"]])
        },
        invalid_reference_count = if (is.null(validation)) {
          NA_integer_
        } else {
          length(
            validation[["invalid_references"]]
          )
        },
        error_class = result[["error_class"]],
        error_message = result[["error_message"]]
      )
    }
  )

  attempts <- purrr::map_dfr(
    batch[["results"]],
    function(result) {
      attempt_table <- result[["attempts"]]

      if (nrow(attempt_table) == 0L) {
        return(tibble::tibble())
      }

      dplyr::mutate(
        attempt_table,
        record_id = result[["record_id"]],
        .before = 1L
      )
    }
  )

  output <- list(
    interviews = interviews,
    events = events,
    foods = foods,
    unlinked_foods = unlinked_foods,
    diagnostics = diagnostics,
    attempts = attempts,
    prepared_records = batch[["input"]],
    metadata = list(
      model = batch[["model"]],
      prompt_version = batch[["prompt_version"]],
      schema_version = batch[["schema_version"]],
      started_at = batch[["started_at"]],
      completed_at = batch[["completed_at"]],
      elapsed_seconds = batch[["elapsed_seconds"]]
    )
  )

  class(output) <- c(
    "food_exposure_result",
    "list"
  )

  output
}


print.food_exposure_result <- function(x, ...) {
  cat("Food-exposure processing result\n")
  cat("===============================\n")
  cat("Records:          ", nrow(x$interviews), "\n", sep = "")
  cat("Events:           ", nrow(x$events), "\n", sep = "")
  cat("Foods:            ", nrow(x$foods), "\n", sep = "")
  cat(
    "Unlinked foods:   ",
    nrow(x$unlinked_foods),
    "\n",
    sep = ""
  )
  cat(
    "Failed records:   ",
    sum(x$diagnostics$status == "error"),
    "\n",
    sep = ""
  )

  invisible(x)
}


exposure_interviews <- function(x) {
  x[["interviews"]]
}

exposure_events <- function(x) {
  x[["events"]]
}

exposure_foods <- function(x) {
  x[["foods"]]
}

unlinked_exposure_foods <- function(x) {
  x[["unlinked_foods"]]
}

exposure_diagnostics <- function(x) {
  x[["diagnostics"]]
}
