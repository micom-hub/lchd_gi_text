# R/reconciliation/reconciliation_validate.R
#
# Deterministic validation of model reconciliation output.

as_object_list <- function(x) {
  if (is.null(x)) {
    return(list())
  }

  if (is.data.frame(x)) {
    return(
      lapply(
        seq_len(nrow(x)),
        function(index) {
          as.list(x[index, , drop = FALSE])
        }
      )
    )
  }

  if (!is.list(x)) {
    return(list())
  }

  # A named list representing one object.
  if (
    length(x) > 0L &&
      !is.null(names(x)) &&
      any(nzchar(names(x)))
  ) {
    return(list(x))
  }

  x
}


normalize_character_array <- function(x) {
  if (is.null(x)) {
    return(character())
  }

  values <- unlist(
    x,
    recursive = TRUE,
    use.names = FALSE
  )

  values <- as.character(values)

  values[
    !is.na(values) &
      nzchar(trimws(values))
  ]
}


empty_to_na <- function(x) {
  if (is.null(x) || length(x) == 0L) {
    return(NA_character_)
  }

  x <- as.character(x[[1]])

  if (is.na(x) || !nzchar(trimws(x))) {
    return(NA_character_)
  }

  x
}


collect_reconciliation_references <- function(output) {
  events <- as_object_list(output[["events"]])

  event_refs <- character()
  food_refs <- character()

  for (event in events) {
    event_refs <- c(
      event_refs,
      normalize_character_array(
        event[["supporting_input_refs"]]
      )
    )

    foods <- as_object_list(event[["foods"]])

    for (food in foods) {
      food_refs <- c(
        food_refs,
        normalize_character_array(
          food[["supporting_input_refs"]]
        )
      )
    }
  }

  unlinked <- as_object_list(
    output[["unlinked_affirmative_foods"]]
  )

  unlinked_refs <- vapply(
    unlinked,
    function(item) {
      empty_to_na(item[["input_ref"]])
    },
    FUN.VALUE = character(1)
  )

  unlinked_refs <- stats::na.omit(
    unlinked_refs
  )

  list(
    event_refs = unique(event_refs),
    food_refs = unique(food_refs),
    unlinked_refs = unique(
      as.character(unlinked_refs)
    ),
    all_refs = unique(
      c(
        event_refs,
        food_refs,
        unlinked_refs
      )
    )
  )
}


validation_issue <- function(
  code,
  severity,
  message,
  input_ref = NA_character_
) {
  tibble::tibble(
    code = code,
    severity = severity,
    message = message,
    input_ref = input_ref
  )
}


validate_reconciled_exposure <- function(
  output,
  payload
) {
  if (!is.list(output)) {
    stop("`output` must be a list.", call. = FALSE)
  }

  reference_table <- exposure_reference_table(
    payload
  )

  valid_refs <- reference_table$input_ref[
    !is.na(reference_table$input_ref)
  ]

  references <- collect_reconciliation_references(
    output
  )

  issues <- list()

  invalid_refs <- setdiff(
    references$all_refs,
    valid_refs
  )

  if (length(invalid_refs) > 0L) {
    issues[[length(issues) + 1L]] <-
      purrr::map_dfr(
        invalid_refs,
        function(input_ref) {
          validation_issue(
            code = "invalid_input_reference",
            severity = "error",
            message = paste0(
              "Output cites an input reference that does not exist: ",
              input_ref
            ),
            input_ref = input_ref
          )
        }
      )
  }

  affirmative_refs <- reference_table |>
    dplyr::filter(
      .data$input_type == "affirmative_food"
    ) |>
    dplyr::pull(.data$input_ref)

  accounted_affirmative_refs <- unique(
    c(
      references$food_refs,
      references$unlinked_refs
    )
  )

  missing_affirmative_refs <- setdiff(
    affirmative_refs,
    accounted_affirmative_refs
  )

  if (length(missing_affirmative_refs) > 0L) {
    issues[[length(issues) + 1L]] <-
      purrr::map_dfr(
        missing_affirmative_refs,
        function(input_ref) {
          validation_issue(
            code = "affirmative_food_not_accounted",
            severity = "error",
            message = paste0(
              "Affirmative food was neither linked nor preserved as ",
              "unlinked: ",
              input_ref
            ),
            input_ref = input_ref
          )
        }
      )
  }

  events <- as_object_list(output[["events"]])

  for (event_index in seq_along(events)) {
    event <- events[[event_index]]

    event_refs <- normalize_character_array(
      event[["supporting_input_refs"]]
    )

    cited_rows <- reference_table |>
      dplyr::filter(
        .data$input_ref %in% event_refs
      )

    output_date <- empty_to_na(
      event[["resolved_date"]]
    )

    if (!is.na(output_date)) {
      supported_dates <- cited_rows$resolved_date[
        !is.na(cited_rows$resolved_date)
      ]

      if (!output_date %in% supported_dates) {
        issues[[length(issues) + 1L]] <-
          validation_issue(
            code = "unsupported_event_date",
            severity = "error",
            message = paste0(
              "Event ",
              event_index,
              " contains an unsupported resolved date: ",
              output_date
            )
          )
      }
    }

    output_source <- empty_to_na(
      event[["source_name"]]
    )

    if (!is.na(output_source)) {
      supported_sources <- cited_rows$source_name[
        !is.na(cited_rows$source_name)
      ]

      if (
        !tolower(trimws(output_source)) %in%
          tolower(trimws(supported_sources))
      ) {
        issues[[length(issues) + 1L]] <-
          validation_issue(
            code = "unsupported_source_name",
            severity = "error",
            message = paste0(
              "Event ",
              event_index,
              " contains an unsupported source name: ",
              output_source
            )
          )
      }
    }

    foods <- as_object_list(event[["foods"]])

    for (food_index in seq_along(foods)) {
      food <- foods[[food_index]]

      food_refs <- normalize_character_array(
        food[["supporting_input_refs"]]
      )

      food_reference_rows <- reference_table |>
        dplyr::filter(
          .data$input_ref %in% food_refs
        )

      if (length(food_refs) == 0L) {
        issues[[length(issues) + 1L]] <-
          validation_issue(
            code = "food_without_reference",
            severity = "error",
            message = paste0(
              "Event ",
              event_index,
              ", food ",
              food_index,
              " has no supporting input reference."
            )
          )
      }

      relationship <- empty_to_na(
        food[["respondent_relationship"]]
      )

      purchase_only <- nrow(food_reference_rows) > 0L &&
        all(
          food_reference_rows$input_type == "explicit_event" &
            food_reference_rows$event_type == "food_purchase"
        )

      if (
        purchase_only &&
          identical(relationship, "consumed")
      ) {
        issues[[length(issues) + 1L]] <-
          validation_issue(
            code = "purchase_changed_to_consumption",
            severity = "error",
            message = paste0(
              "Event ",
              event_index,
              ", food ",
              food_index,
              " classifies a purchase-only input as consumed."
            )
          )
      }
    }
  }

  issue_table <- if (length(issues) == 0L) {
    tibble::tibble(
      code = character(),
      severity = character(),
      message = character(),
      input_ref = character()
    )
  } else {
    dplyr::bind_rows(issues)
  }

  list(
    valid = !any(
      issue_table$severity == "error"
    ),
    issues = issue_table,
    invalid_references = invalid_refs,
    missing_affirmative_references = missing_affirmative_refs,
    referenced_inputs = references$all_refs
  )
}
