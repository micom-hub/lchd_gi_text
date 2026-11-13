# Translate an extraction field into JSON Schema.
compile_extraction_field <- function(field) {
  schema <- switch(
    field$type,

    string = list(type = "string"),

    boolean = list(type = "boolean"),

    enum = list(
      type = "string",
      enum = unname(as.list(field$allowed_values))
    ),

    string_array = list(
      type = "array",
      items = list(type = "string")
    ),

    enum_array = list(
      type = "array",
      items = list(
        type = "string",
        enum = unname(as.list(field$allowed_values))
      )
    ),

    stop(
      "Unsupported extraction field type: ",
      field$type,
      call. = FALSE
    )
  )

  # Nullability is independent of whether the key is required.
  if (isTRUE(field$nullable)) {
    schema <- list(
      anyOf = list(
        schema,
        list(type = "null")
      )
    )
  }

  schema$description <- field$description

  # Defaults are intentionally not applied here.
  # They are R-side processing rules, not extracted facts.
  schema
}


# Build an object schema from named extraction fields.
compile_extraction_object <- function(
  fields,
  extra_properties = list(),
  extra_required = character()
) {
  properties <- lapply(fields, compile_extraction_field)

  collisions <- intersect(
    names(properties),
    names(extra_properties)
  )

  if (length(collisions)) {
    stop(
      "Field names conflict with structural keys: ",
      paste(collisions, collapse = ", "),
      call. = FALSE
    )
  }

  properties <- c(properties, extra_properties)

  # Ensure an empty properties collection becomes {}, not [].
  if (!length(properties)) {
    properties <- stats::setNames(list(), character())
  }

  required_fields <- names(fields)[
    vapply(
      fields,
      function(field) isTRUE(field$required),
      logical(1)
    )
  ]

  list(
    type = "object",
    properties = properties,
    required = unname(
      as.list(unique(c(required_fields, extra_required)))
    ),
    additionalProperties = FALSE
  )
}


# Build the full JSON Schema from the selected components.
extraction_json_schema <- function(specification) {
  validate_food_extraction_spec(specification)

  interview_fields <- extraction_fields_by_scope(
    specification,
    "interview"
  )

  event_fields <- extraction_fields_by_scope(
    specification,
    "event"
  )

  food_fields <- extraction_fields_by_scope(
    specification,
    "food"
  )

  event_properties <- list()
  event_required <- character()

  if (length(food_fields)) {
    food_schema <- compile_extraction_object(food_fields)

    event_properties$foods <- list(
      type = "array",
      description = paste(
        "Food mentions associated with this event.",
        "Return an empty array when none are supported."
      ),
      items = food_schema
    )

    event_required <- "foods"
  }

  interview_properties <- list()
  interview_required <- character()

  if (length(event_fields) || length(food_fields)) {
    event_schema <- compile_extraction_object(
      fields = event_fields,
      extra_properties = event_properties,
      extra_required = event_required
    )

    interview_properties$events <- list(
      type = "array",
      description = paste(
        "Food-related events supported by the narrative.",
        "Return an empty array when none are found."
      ),
      items = event_schema
    )

    interview_required <- "events"
  }

  compile_extraction_object(
    fields = interview_fields,
    extra_properties = interview_properties,
    extra_required = interview_required
  )
}


# Public compiler: return an ellmer type specification.
compile_extraction_type <- function(
  specification = food_extraction_spec()
) {
  schema <- extraction_json_schema(specification)

  schema_json <- jsonlite::toJSON(
    schema,
    auto_unbox = TRUE,
    null = "null",
    pretty = TRUE
  )

  ellmer::type_from_schema(text = schema_json)
}