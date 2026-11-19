# Versioned instructions for extracting foods from one event description.
#
# The prompt includes examples showing how to distinguish:
# - definite consumption from uncertain consumption;
# - food items from their explicitly stated ingredients;
# - respondent consumption from other people's consumption;
# - consumption from explicit denial.
#
# Restaurant names, dates, locations, and identifiers remain managed by R.
#
# This is a development prompt, not yet validated for routine use.
# Questionnaire-specific implied consumption still needs testing.


# -------------------------------------------------------------------------
# Prompt version
# -------------------------------------------------------------------------

#' Return the event-food prompt version
#'
#' Update this version whenever the extraction instructions or examples change.
#'
#' @return A character value.
event_food_prompt_version <- function() {
  "0.1.0"
}


# -------------------------------------------------------------------------
# System instructions
# -------------------------------------------------------------------------

#' Build the event-food extraction system prompt
#'
#' Returns instructions and examples for extracting food mentions,
#' explicitly stated ingredients, respondent relationships, uncertainty,
#' and exact supporting quotations.
#'
#' This function only constructs text. It does not call Ollama.
#'
#' @return A character value containing the system prompt.
event_food_system_prompt <- function() {
  paste(
    # Extraction scope: retain all food mentions, not only consumed foods.
    "Extract ALL food mentions from the answer.",
    "Include respondent-consumed foods, other people's foods,",
    "and explicitly denied foods. Return one entry per food.",

    # Relationship categories.
    "Use consumed for explicit respondent consumption.",
    "Use other_person_consumed for another person's consumption.",
    "Use explicitly_not_consumed for explicit respondent denial.",

    # Certainty describes the reported statement, not model confidence.
    "Use certain for definite statements, including definite denials.",
    "Use uncertain only when the wording expresses uncertainty.",

    # Ingredients must be stated, not inferred or copied from the food name.
    "explicit_components contains stated ingredients only.",
    "Do not repeat the food itself as an ingredient.",

    # Evidence is copied from the input without paraphrasing.
    "evidence_text must be an exact supporting quote.",

    # Example: definite consumption with no stated ingredients.
    "Example input: I ate noodles.",
    'Example output: {"foods":[{"food_text":"noodles",',
    '"explicit_components":[],"respondent_relationship":"consumed",',
    '"uncertainty":"certain","evidence_text":"I ate noodles."}]}',

    # Example: uncertain consumption with an explicitly stated ingredient.
    "Example input: Maybe I ate a wrap with cabbage.",
    'Example output: {"foods":[{"food_text":"wrap",',
    '"explicit_components":["cabbage"],',
    '"respondent_relationship":"unclear","uncertainty":"uncertain",',
    '"evidence_text":"Maybe I ate a wrap with cabbage."}]}',

    # Additional interpretation rules.
    "Use unclear when respondent consumption itself is uncertain.",
    "Explicitly listed ingredients belong in explicit_components;",
    "do not also create separate food rows for those ingredients.",

    sep = "\n"
  )
}