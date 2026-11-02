# Convert the deterministic exposure jsons for MDSS into LLM input payloads

# -------------------------------------------------------------------------
# Input references
# -------------------------------------------------------------------------

#' Add sequential references to deterministic exposure facts
#'
#' References allow the LLM to cite input facts without depending on MDSS
#' column names. References are sequential identifiers, not hashes.
#'
#' @param record One nested record returned by `build_exposure_json()` with
#'   `output = "list"`.
#'
#' @return The record with `input_ref` added to explicit events and
#'   affirmative food responses.
add_exposure_input_references <- function(record) {
  if (!is.list(record)) {
    stop("`record` must be a list.", call. = FALSE)
  }

  known_exposures <- record[["known_exposures"]]

  if (is.null(known_exposures)) {
    stop(
      "`record` does not contain `known_exposures`.",
      call. = FALSE
    )
  }

  explicit_events <-
    known_exposures[["explicit_events"]]

  affirmative_foods <-
    known_exposures[["affirmative_food_questionnaire"]]

  explicit_events <- explicit_events %||% list()
  affirmative_foods <- affirmative_foods %||% list()

  if (length(explicit_events) > 0L) {
    for (index in seq_along(explicit_events)) {
      explicit_events[[index]][["input_ref"]] <-
        sprintf("explicit_event_%03d", index)
    }
  }

  if (length(affirmative_foods) > 0L) {
    for (index in seq_along(affirmative_foods)) {
      affirmative_foods[[index]][["input_ref"]] <-
        sprintf("affirmative_food_%03d", index)
    }
  }

  record[["known_exposures"]][["explicit_events"]] <-
    explicit_events

  record[["known_exposures"]][[
    "affirmative_food_questionnaire"
  ]] <- affirmative_foods

  record
}


# -------------------------------------------------------------------------
# Compact payload construction
# -------------------------------------------------------------------------

compact_explicit_event <- function(event) {
  compact_nulls(
    list(
      input_ref = event[["input_ref"]],
      event_type = event[["event_type"]],
      date_text = event[["date_text"]],
      resolved_date = event[["resolved_date"]],
      source_name = event[["source_name"]],
      location_text = event[["location_text"]],
      food_text = event[["food_text"]]
    )
  )
}


compact_affirmative_food <- function(food) {
  compact_nulls(
    list(
      input_ref = food[["input_ref"]],
      item_id = food[["item_id"]],
      food_label = food[["food_label"]],
      response = food[["response"]],
      details = food[["details"]]
    )
  )
}


#' Create a compact LLM payload
#'
#' Removes provenance details that the model doesn't need for
#' reconciliation while keeping input references.
#'
#' @param record A deterministic exposure record with input references.
#' @param include_record_id Whether to include the source record ID.
#'
#' @return A JSON-ready nested list.
make_exposure_llm_payload <- function(
  record,
  include_record_id = TRUE
) {
  if (!is.list(record)) {
    stop("`record` must be a list.", call. = FALSE)
  }

  known_exposures <- record[["known_exposures"]]

  if (is.null(known_exposures)) {
    stop(
      "`record` does not contain `known_exposures`.",
      call. = FALSE
    )
  }

  explicit_events <-
    known_exposures[["explicit_events"]] %||%
    list()

  affirmative_foods <-
    known_exposures[["affirmative_food_questionnaire"]] %||%
    list()

  explicit_events <- lapply(
    explicit_events,
    compact_explicit_event
  )

  affirmative_foods <- lapply(
    affirmative_foods,
    compact_affirmative_food
  )

  payload <- list(
    date_context = record[["date_context"]] %||%
      list(),
    explicit_events = explicit_events,
    affirmative_foods = affirmative_foods
  )

  if (isTRUE(include_record_id)) {
    payload <- c(
      list(record_id = record[["record_id"]]),
      payload
    )
  }

  compact_nulls(payload)
}


#' Prepare deterministic records and LLM payloads
#'
#' @param exposure_data A tibble returned by `build_exposure_json()` with
#'   `output = "tibble"`.
#'
#' @return A tibble containing `record_id`, `audit_record`, and
#'   `llm_payload`.
prepare_exposure_payloads <- function(exposure_data) {
  if (!is.data.frame(exposure_data)) {
    stop(
      "`exposure_data` must be a data frame or tibble.",
      call. = FALSE
    )
  }

  required_columns <- c(
    "record_id",
    "exposure_record"
  )

  missing_columns <- setdiff(
    required_columns,
    names(exposure_data)
  )

  if (length(missing_columns) > 0L) {
    stop(
      paste0(
        "`exposure_data` is missing: ",
        paste(missing_columns, collapse = ", "),
        "."
      ),
      call. = FALSE
    )
  }

  exposure_data |>
    dplyr::transmute(
      record_id = as.character(.data$record_id),

      audit_record = purrr::map(
        .data$exposure_record,
        add_exposure_input_references
      ),

      llm_payload = purrr::map(
        .data$audit_record,
        make_exposure_llm_payload
      ),

      explicit_event_count = purrr::map_int(
        .data$llm_payload,
        function(payload) {
          length(payload[["explicit_events"]])
        }
      ),

      affirmative_food_count = purrr::map_int(
        .data$llm_payload,
        function(payload) {
          length(payload[["affirmative_foods"]])
        }
      )
    )
}


# -------------------------------------------------------------------------
# Reference lookup
# -------------------------------------------------------------------------

#' Create a lookup table for one LLM payload
#'
#' @param payload A compact LLM payload.
#'
#' @return A tibble containing one row per input reference.
exposure_reference_table <- function(payload) {
  explicit_events <- payload[["explicit_events"]] %||%
    list()

  affirmative_foods <-
    payload[["affirmative_foods"]] %||%
    list()

  event_rows <- purrr::map_dfr(
    explicit_events,
    function(event) {
      tibble::tibble(
        input_ref = event[["input_ref"]] %||% NA_character_,
        input_type = "explicit_event",
        event_type = event[["event_type"]] %||% NA_character_,
        food_text = event[["food_text"]] %||% NA_character_,
        source_name = event[["source_name"]] %||% NA_character_,
        date_text = event[["date_text"]] %||% NA_character_,
        resolved_date = event[["resolved_date"]] %||% NA_character_,
        item_id = NA_character_
      )
    }
  )

  food_rows <- purrr::map_dfr(
    affirmative_foods,
    function(food) {
      details <- food[["details"]] %||% list()

      source_name <- details[["establishment"]] %||%
        details[["purchase_location"]] %||%
        NA_character_

      tibble::tibble(
        input_ref = food[["input_ref"]] %||% NA_character_,
        input_type = "affirmative_food",
        event_type = NA_character_,
        food_text = food[["food_label"]] %||% NA_character_,
        source_name = source_name,
        date_text = NA_character_,
        resolved_date = NA_character_,
        item_id = food[["item_id"]] %||% NA_character_
      )
    }
  )

  dplyr::bind_rows(event_rows, food_rows)
}
