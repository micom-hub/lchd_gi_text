# experiments/baseline_relationships.R
#
# Development test for food identification and respondent relationships.
# Run manually. Do not add this file to the project loader.

source("R/load_project.R")

# -------------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------------

config <- validate_config(ollama_config())
model_tag <- "llama3.2:3b"

# Preserve the prompt used in the successful baseline.
diagnostic_prompt <- paste(
  "Extract ALL food mentions from the answer.",
  "Include respondent-consumed foods, other people's foods,",
  "and explicitly denied foods. Return one entry per food.",
  "Use consumed for explicit respondent consumption.",
  "Use other_person_consumed for another person's consumption.",
  "Use explicitly_not_consumed for explicit respondent denial.",
  "Use certain for definite statements, including definite denials.",
  "Use uncertain only when the wording expresses uncertainty.",
  "explicit_components contains stated ingredients only.",
  "Do not repeat the food itself as an ingredient.",
  "evidence_text must be an exact supporting quote.",
  sep = "\n"
)

# -------------------------------------------------------------------------
# Minimal output schema
# -------------------------------------------------------------------------

minimal_schema <- ellmer::type_object(
  foods = ellmer::type_array(
    items = ellmer::type_object(
      food_text = ellmer::type_string(),
      respondent_relationship = ellmer::type_enum(
        values = c(
          "consumed",
          "other_person_consumed",
          "explicitly_not_consumed",
          "unclear"
        )
      )
    )
  )
)

# -------------------------------------------------------------------------
# Fixed development examples
# -------------------------------------------------------------------------

baseline_tests <- c(
  "I ate pasta. My husband ate soup. I did not eat bread.",
  "My sister ate pizza. I ate carrots. I did not eat cake.",
  "I did not eat chicken. My friend ate rice. I ate beans."
)

expected <- tibble::tribble(
  ~test_id, ~food_text, ~respondent_relationship,
  1L, "pasta",   "consumed",
  1L, "soup",    "other_person_consumed",
  1L, "bread",   "explicitly_not_consumed",
  2L, "pizza",   "other_person_consumed",
  2L, "carrots", "consumed",
  2L, "cake",    "explicitly_not_consumed",
  3L, "chicken", "explicitly_not_consumed",
  3L, "rice",    "other_person_consumed",
  3L, "beans",   "consumed"
)

# -------------------------------------------------------------------------
# Run each example in a fresh conversation
# -------------------------------------------------------------------------

baseline_results <- lapply(baseline_tests, function(text) {
  fresh_chat <- ellmer::chat_ollama(
    base_url = config$base_url,
    model = model_tag,
    system_prompt = diagnostic_prompt,
    params = ellmer::params(
      temperature = 0,
      seed = 123,
      max_tokens = 512
    )
  )

  list(
    input = text,
    output = fresh_chat$chat_structured(
      text,
      type = minimal_schema
    )
  )
})

# Inspect outputs.
baseline_results