# Structured output for food extraction from one MDSS event.
event_food_output_type <- function() {
  vocabulary <- reconciliation_vocabularies()

  food_type <- ellmer::type_object(
    food_text = ellmer::type_string(
      "Food or beverage exactly as stated in the event text."
    ),

    explicit_components = ellmer::type_array(
  items = ellmer::type_string(),
  description = paste(
    "Only ingredients explicitly stated as components of this food.",
    "Never repeat food_text itself.",
    "For 'I ate pasta', return [].",
    "For 'sandwich with lettuce and tomato', return",
    "['lettuce', 'tomato']."
  )
),

    respondent_relationship = ellmer::type_enum(
      values = vocabulary$respondent_relationship,
      description = "The respondent's relationship to this food."
    ),

    uncertainty = ellmer::type_enum(
  values = vocabulary$uncertainty,
  description = paste(
    "certain: a definite statement, including a definite denial",
    "or another person's definite consumption.",
    "uncertain: explicit doubt such as 'maybe' or 'cannot remember'.",
    "conflicting: unresolved contradictory statements.",
    "Missing ingredients or dates do not imply uncertainty."
  )
),


    evidence_text = ellmer::type_string(
      paste(
        "An exact contiguous quote from food_text in the input",
        "supporting this food and its relationship to the respondent."
      )
    )
  )

  ellmer::type_object(
    foods = ellmer::type_array(
      items = food_type,
      description = paste(
        "Food mentions supported by this event.",
        "Return an empty array when no specific food is mentioned."
      )
    )
  )
}