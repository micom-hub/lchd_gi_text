# Defines the structured output expected from the model in the form of ellmer structured-output schema
# unknown text values become an empty struing
reconciliation_vocabularies <- function() {
  list(
    event_type = c(
      "food_consumption",
      "food_purchase",
      "private_group_event",
      "other",
      "unknown"
    ),

    meal_type = c(
      "breakfast",
      "lunch",
      "dinner",
      "snack",
      "beverage_only",
      "multiple_meals",
      "other",
      "unknown"
    ),

    source_type = c(
      "home",
      "restaurant",
      "grocery_store",
      "school",
      "workplace",
      "catered_event",
      "social_event",
      "food_truck",
      "delivery",
      "healthcare_facility",
      "other",
      "unknown"
    ),

    respondent_relationship = c(
      "consumed",
      "explicitly_not_consumed",
      "purchased_not_consumed",
      "handled_not_consumed",
      "prepared_not_consumed",
      "offered_but_declined",
      "other_person_consumed",
      "mentioned_only",
      "unclear"
    ),

    uncertainty = c(
      "certain",
      "uncertain",
      "conflicting"
    ),

    linkage_type = c(
      "explicit_event",
      "explicit_detail_match",
      "supported_reconciliation",
      "unlinked"
    ),

    event_review_reason = c(
      "ambiguous_date",
      "unresolved_relative_date",
      "ambiguous_source",
      "conflicting_statement",
      "possible_duplicate",
      "event_linkage_unclear",
      "unsupported_value",
      "other"
    ),

    food_review_reason = c(
      "ambiguous_food",
      "unclear_consumption",
      "conflicting_statement",
      "possible_duplicate",
      "event_linkage_unclear",
      "unsupported_value",
      "other"
    ),

    record_review_reason = c(
      "no_events_created",
      "unlinked_affirmative_foods",
      "ambiguous_linkage",
      "conflicting_input",
      "output_validation_failed",
      "other"
    )
  )
}


#' Return the reconciliation schema version
#'
#' @return A character value.
reconciliation_schema_version <- function() {
  "1.0.0"
}


#' Build the ellmer structured-output type
#'
#' @return An ellmer structured-output type.
partially_structured_output_type <- function() {
  vocabulary <- reconciliation_vocabularies()

  food_type <- ellmer::type_object(
    food_text = ellmer::type_string(
      description = paste0(
        "Food or beverage supported by the cited input references."
      )
    ),

    explicit_components = ellmer::type_array(
      items = ellmer::type_string(
        description = paste0(
          "An ingredient or component explicitly supported by input data."
        )
      ),
      description = paste0(
        "Components explicitly stated in the input. Use an empty array ",
        "when none are stated."
      )
    ),

    respondent_relationship = ellmer::type_enum(
      values = vocabulary$respondent_relationship,
      description = paste0(
        "Relationship between the respondent and this food."
      )
    ),

    uncertainty = ellmer::type_enum(
      values = vocabulary$uncertainty,
      description = paste0(
        "Certainty expressed by the input, not model confidence."
      )
    ),

    linkage_type = ellmer::type_enum(
      values = vocabulary$linkage_type,
      description = paste0(
        "How this food was linked to its event."
      )
    ),

    supporting_input_refs = ellmer::type_array(
      items = ellmer::type_string(),
      description = paste0(
        "One or more exact input_ref values supporting this food."
      )
    ),

    food_needs_review = ellmer::type_boolean(
      description = paste0(
        "Whether the food extraction needs human review."
      )
    ),

    food_review_reasons = ellmer::type_array(
      items = ellmer::type_enum(
        values = vocabulary$food_review_reason
      ),
      description = paste0(
        "Standardized food-level review reasons."
      )
    )
  )

  event_type <- ellmer::type_object(
    event_type = ellmer::type_enum(
      values = vocabulary$event_type
    ),

    date_text = ellmer::type_string(
      description = paste0(
        "Original event-date text. Use an empty string when absent."
      )
    ),

    resolved_date = ellmer::type_string(
      description = paste0(
        "ISO date supported by the cited input. Use an empty string ",
        "when absent."
      )
    ),

    meal_type = ellmer::type_enum(
      values = vocabulary$meal_type
    ),

    source_name = ellmer::type_string(
      description = paste0(
        "Source name supported by cited input. Use an empty string ",
        "when absent."
      )
    ),

    source_type = ellmer::type_enum(
      values = vocabulary$source_type
    ),

    location_text = ellmer::type_string(
      description = paste0(
        "Location supported by cited input. Use an empty string when absent."
      )
    ),

    linkage_type = ellmer::type_enum(
      values = vocabulary$linkage_type
    ),

    supporting_input_refs = ellmer::type_array(
      items = ellmer::type_string(),
      description = paste0(
        "Input references supporting the event."
      )
    ),

    event_needs_review = ellmer::type_boolean(),

    event_review_reasons = ellmer::type_array(
      items = ellmer::type_enum(
        values = vocabulary$event_review_reason
      )
    ),

    foods = ellmer::type_array(
      items = food_type,
      description = paste0(
        "Foods associated with this event."
      )
    )
  )

  unlinked_type <- ellmer::type_object(
    input_ref = ellmer::type_string(
      description = paste0(
        "The exact affirmative_food input reference."
      )
    ),

    item_id = ellmer::type_string(),

    food_text = ellmer::type_string(),

    reason = ellmer::type_string(
      description = paste0(
        "Why the affirmative food could not safely be linked."
      )
    ),

    needs_review = ellmer::type_boolean()
  )

  ellmer::type_object(
    events = ellmer::type_array(
      items = event_type
    ),

    unlinked_affirmative_foods = ellmer::type_array(
      items = unlinked_type
    ),

    record_needs_review = ellmer::type_boolean(),

    record_review_reasons = ellmer::type_array(
      items = ellmer::type_enum(
        values = vocabulary$record_review_reason
      )
    )
  )
}
