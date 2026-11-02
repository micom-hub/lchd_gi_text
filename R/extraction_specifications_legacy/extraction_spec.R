here::i_am("R/extraction/extraction_spec.R")
#
# Machine-readable version of the food-event extraction spec described in extraction_v1.md
#
# We define
#
# 1. Extraction fields
# 2. Groups of fields (components) that can be requested
# 3. Controlled vocabularies (when fields are "choose one")
# 4. Default component registry if user doesn't specify
# 5. Functions for building or changing specs
# 6. Functions to inspect specs as a table
# -----

# Internal helpers for validation-------
is_one_nonempty_string <- function(x) {
  is.character(x) &&
    length(x) == 1L &&
    !is.na(x) &&
    nzchar(trimws(x))
}


validate_logical_flag <- function(x, argument_name) {
  valid <- is.logical(x) &&
    length(x) == 1L &&
    !is.na(x)

  if (!valid) {
    stop(
      "`",
      argument_name,
      "` must be either TRUE or FALSE.",
      call. = FALSE
    )
  }

  x
}


validate_unique_character_vector <- function(
  x,
  argument_name,
  allow_empty = TRUE
) {
  valid <- is.character(x) &&
    !anyNA(x) &&
    all(nzchar(trimws(x))) &&
    !anyDuplicated(x)

  if (!allow_empty) {
    valid <- valid && length(x) > 0L
  }

  if (!valid) {
    stop(
      "`",
      argument_name,
      "` must contain unique, nonmissing, nonempty character values.",
      call. = FALSE
    )
  }

  x
}

# Field constructors  ------

# Function that allows a user to configure a new field to be extracted from the model

#' Define an extraction field
#'
#' Creates an abstract description of one field that may be requested from
#' the language model.
#'
#' The abstract field definition is intentionally independent of `ellmer`.
#' A later compiler will translate these field types into the corresponding
#' `ellmer::type_*()` objects.
#'
#' @param name Output field name.
#' @param scope Structural level at which the field occurs. One of
#'   `"interview"`, `"event"`, or `"food"`.
#' @param type Abstract field type. One of `"string"`, `"boolean"`,
#'   `"enum"`, `"string_array"`, or `"enum_array"`.
#' @param description Concise instructions describing the field.
#' @param required Whether the field must appear in the structured response.
#' @param nullable Whether the field may contain a null value.
#' @param allowed_values Controlled values for `"enum"` and `"enum_array"`
#'   fields.
#' @param default Optional default value that R may apply after extraction.
#'
#' @return An object of class `extraction_field`.
define_extraction_field <- function(
  name,
  scope,
  type,
  description,
  required = TRUE,
  nullable = FALSE,
  allowed_values = character(),
  default = NULL
) {
  # The extraction field needs a string name
  if (!is_one_nonempty_string(name)) {
    stop(
      "`name` must be one nonempty character value.",
      call. = FALSE
    )
  }
  # Scope must be interview, event, or food
  scope <- match.arg(
    scope,
    choices = c(
      "interview",
      "event",
      "food"
    )
  )
  # type will need to match the ellmer structured output types
  type <- match.arg(
    type,
    choices = c(
      "string",
      "boolean",
      "enum",
      "string_array",
      "enum_array"
    )
  )
  # description fed to the llm, must be str
  if (!is_one_nonempty_string(description)) {
    stop(
      "`description` must be one nonempty character value.",
      call. = FALSE
    )
  }

  # whether the field is required, bool
  required <- validate_logical_flag(
    required,
    "required"
  )
  # whether it can be null (bool)
  nullable <- validate_logical_flag(
    nullable,
    "nullable"
  )
  # character vector of unique choices
  allowed_values <- validate_unique_character_vector(
    allowed_values,
    argument_name = "allowed_values",
    allow_empty = TRUE
  )

  # these types need to have corresponding allowed_values
  if (type %in% c("enum", "enum_array") && length(allowed_values) == 0L) {
    stop(
      paste0(
        "Field `",
        name,
        "` has type `",
        type,
        "` and therefore requires `allowed_values`."
      ),
      call. = FALSE
    )
  }
  # allowed values makes no sense for other types
  if (
    !type %in% c("enum", "enum_array") &&
      length(allowed_values) > 0L
  ) {
    stop(
      paste0(
        "`allowed_values` can be supplied only for `enum` and ",
        "`enum_array` fields. Field: ",
        name
      ),
      call. = FALSE
    )
  }

  # return the specs for the field as a list
  field <- list(
    name = name,
    scope = scope,
    type = type,
    description = description,
    required = required,
    nullable = nullable,
    allowed_values = allowed_values,
    default = default
  )

  class(field) <- "extraction_field"

  field
}

# Component constructor -----
# allow users to define extraction components as groups of fields
#' Define an extraction component
#'
#' An extraction component is a related group of fields that can be included
#' in or excluded from an extraction operation.
#'
#' @param name Unique component name.
#' @param description Description of the extraction task represented by this
#'   component.
#' @param fields Named list of fields created with
#'   `define_extraction_field()`.
#' @param dependencies Other components that must be included whenever this
#'   component is selected.
#' @param recommended_inputs Input roles that improve the component, such as
#'   `"interview_date"`.
#' @param enabled_by_default Whether the component is selected by the
#'   `"default"` preset.
#'
#' @return An object of class `extraction_component`.
define_extraction_component <- function(
  name,
  description,
  fields,
  dependencies = character(),
  recommended_inputs = character(),
  enabled_by_default = FALSE
) {
  if (!is_one_nonempty_string(name)) {
    stop(
      "`name` must be one nonempty character value.",
      call. = FALSE
    )
  }

  if (!is_one_nonempty_string(description)) {
    stop(
      "`description` must be one nonempty character value.",
      call. = FALSE
    )
  }

  if (
    !is.list(fields) ||
      length(fields) == 0L ||
      is.null(names(fields)) ||
      any(!nzchar(names(fields))) ||
      anyDuplicated(names(fields))
  ) {
    stop(
      "`fields` must be a named, nonempty list with unique names.",
      call. = FALSE
    )
  }

  valid_fields <- vapply(
    fields,
    inherits,
    logical(1),
    what = "extraction_field"
  )

  if (!all(valid_fields)) {
    stop(
      paste0(
        "Every field must be created with ",
        "`define_extraction_field()`."
      ),
      call. = FALSE
    )
  }

  internal_field_names <- vapply(
    fields,
    function(field) {
      field$name
    },
    FUN.VALUE = character(1)
  )

  if (
    !identical(
      unname(internal_field_names),
      names(fields)
    )
  ) {
    stop(
      paste0(
        "Each field's internal name must match its list name. ",
        "For example: `food_text = define_extraction_field(",
        "name = \"food_text\", ...)`."
      ),
      call. = FALSE
    )
  }

  dependencies <- validate_unique_character_vector(
    dependencies,
    argument_name = "dependencies",
    allow_empty = TRUE
  )

  recommended_inputs <- validate_unique_character_vector(
    recommended_inputs,
    argument_name = "recommended_inputs",
    allow_empty = TRUE
  )

  enabled_by_default <- validate_logical_flag(
    enabled_by_default,
    "enabled_by_default"
  )

  component <- list(
    name = name,
    description = description,
    fields = fields,
    dependencies = dependencies,
    recommended_inputs = recommended_inputs,
    enabled_by_default = enabled_by_default
  )

  class(component) <- "extraction_component"

  component
}

# Controlled vocabularies
# Function for food-extraction controlled vocabs that correspond with extraction_v1, as of 10/27/2026 and are preconfigured
#' Return food-extraction controlled vocabularies
#'
#' These values come directly from `extraction_v1.md`.
#'
#' @return A named list of character vectors.
food_extraction_vocabularies <- function() {
  list(
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

    interview_review_reason = c(
      "onset_not_reported",
      "no_food_events_found",
      "narrative_incomplete",
      "date_context_missing",
      "exposure_window_unclear",
      "conflicting_narrative",
      "output_requires_review",
      "other"
    ),

    event_review_reason = c(
      "ambiguous_date",
      "unresolved_relative_date",
      "ambiguous_source",
      "conflicting_statement",
      "possible_duplicate",
      "outside_requested_window",
      "event_linkage_unclear",
      "other"
    ),

    food_review_reason = c(
      "ambiguous_food",
      "ambiguous_subject",
      "unclear_consumption",
      "conflicting_statement",
      "evidence_not_exact",
      "possible_duplicate",
      "other"
    )
  )
}

# Default component registry based on v1 --------
#' Return the extraction component registry
#'
#' The registry is the complete collection of extraction components available
#' under specification version 1.
#'
#' @return A named list of `extraction_component` objects.
extraction_component_registry <- function() {
  vocabulary <- food_extraction_vocabularies()

  list(
    onset = define_extraction_component(
      name = "onset",
      description = paste0(
        "Extract illness-onset wording and normalize the onset date when ",
        "the available narrative and date context support it."
      ),
      recommended_inputs = "interview_date",
      enabled_by_default = FALSE,
      fields = list(
        onset_text = define_extraction_field(
          name = "onset_text",
          scope = "interview",
          type = "string",
          description = paste0(
            "Exact text describing illness onset. Use null when onset is ",
            "not reported."
          ),
          required = FALSE,
          nullable = TRUE
        ),

        onset_date_text = define_extraction_field(
          name = "onset_date_text",
          scope = "interview",
          type = "string",
          description = paste0(
            "The onset date expression exactly as stated in the narrative. ",
            "Use null when no onset date expression is reported."
          ),
          required = FALSE,
          nullable = TRUE
        ),

        resolved_onset_date = define_extraction_field(
          name = "resolved_onset_date",
          scope = "interview",
          type = "string",
          description = paste0(
            "Onset date normalized to YYYY-MM-DD when reasonably ",
            "resolvable. Use null rather than guessing."
          ),
          required = FALSE,
          nullable = TRUE
        )
      )
    ),

    interview_review = define_extraction_component(
      name = "interview_review",
      description = paste0(
        "Return interview-level review recommendations and standardized ",
        "reasons."
      ),
      enabled_by_default = FALSE,
      fields = list(
        interview_needs_review = define_extraction_field(
          name = "interview_needs_review",
          scope = "interview",
          type = "boolean",
          description = paste0(
            "Whether the interview-level extraction requires further ",
            "review."
          ),
          required = TRUE,
          nullable = FALSE,
          default = FALSE
        ),

        interview_review_reasons = define_extraction_field(
          name = "interview_review_reasons",
          scope = "interview",
          type = "enum_array",
          description = paste0(
            "Zero or more standardized interview-level reasons for review."
          ),
          required = TRUE,
          nullable = FALSE,
          allowed_values = vocabulary$interview_review_reason,
          default = character()
        )
      )
    ),

    timing = define_extraction_component(
      name = "timing",
      description = paste0(
        "Extract original and normalized date information for each event."
      ),
      recommended_inputs = "interview_date",
      enabled_by_default = FALSE,
      fields = list(
        date_text = define_extraction_field(
          name = "date_text",
          scope = "event",
          type = "string",
          description = paste0(
            "The event date expression exactly as stated in the narrative. ",
            "Use null when no event date is reported."
          ),
          required = FALSE,
          nullable = TRUE
        ),

        resolved_date = define_extraction_field(
          name = "resolved_date",
          scope = "event",
          type = "string",
          description = paste0(
            "Event date normalized to YYYY-MM-DD when reasonably ",
            "resolvable. Use null when unavailable or ambiguous."
          ),
          required = FALSE,
          nullable = TRUE
        )
      )
    ),

    meal = define_extraction_component(
      name = "meal",
      description = paste0(
        "Classify the meal or eating occasion associated with an event."
      ),
      enabled_by_default = FALSE,
      fields = list(
        meal_type = define_extraction_field(
          name = "meal_type",
          scope = "event",
          type = "enum",
          description = paste0(
            "Meal or eating occasion supported by the narrative."
          ),
          required = TRUE,
          nullable = FALSE,
          allowed_values = vocabulary$meal_type
        )
      )
    ),

    source = define_extraction_component(
      name = "source",
      description = paste0(
        "Extract the stated restaurant, store, household, institution, ",
        "event, or other source associated with a food event."
      ),
      enabled_by_default = FALSE,
      fields = list(
        source_name = define_extraction_field(
          name = "source_name",
          scope = "event",
          type = "string",
          description = paste0(
            "The restaurant, store, household, institution, event, or ",
            "other source exactly as stated. Use null when absent."
          ),
          required = FALSE,
          nullable = TRUE
        ),

        source_type = define_extraction_field(
          name = "source_type",
          scope = "event",
          type = "enum",
          description = paste0(
            "General type of source supported by the narrative."
          ),
          required = TRUE,
          nullable = FALSE,
          allowed_values = vocabulary$source_type
        ),

        source_text = define_extraction_field(
          name = "source_text",
          scope = "event",
          type = "string",
          description = paste0(
            "Exact quotation supporting the identified source. Use null ",
            "when no source is reported."
          ),
          required = FALSE,
          nullable = TRUE
        )
      )
    ),

    event_review = define_extraction_component(
      name = "event_review",
      description = paste0(
        "Return event-level review recommendations and standardized reasons."
      ),
      enabled_by_default = FALSE,
      fields = list(
        event_needs_review = define_extraction_field(
          name = "event_needs_review",
          scope = "event",
          type = "boolean",
          description = paste0(
            "Whether this food-related event should receive independent ",
            "review."
          ),
          required = TRUE,
          nullable = FALSE,
          default = FALSE
        ),

        event_review_reasons = define_extraction_field(
          name = "event_review_reasons",
          scope = "event",
          type = "enum_array",
          description = paste0(
            "Zero or more standardized event-level reasons for review."
          ),
          required = TRUE,
          nullable = FALSE,
          allowed_values = vocabulary$event_review_reason,
          default = character()
        )
      )
    ),

    food = define_extraction_component(
      name = "food",
      description = paste0(
        "Extract each food or beverage mention and any explicitly stated ",
        "components."
      ),
      enabled_by_default = TRUE,
      fields = list(
        food_text = define_extraction_field(
          name = "food_text",
          scope = "food",
          type = "string",
          description = paste0(
            "Food or beverage exactly as stated in the narrative."
          ),
          required = TRUE,
          nullable = FALSE
        ),

        explicit_components = define_extraction_field(
          name = "explicit_components",
          scope = "food",
          type = "string_array",
          description = paste0(
            "Components or ingredients explicitly stated in the narrative. ",
            "Do not infer typical ingredients. Return an empty list when ",
            "none are stated."
          ),
          required = TRUE,
          nullable = FALSE,
          default = character()
        )
      )
    ),

    relationship = define_extraction_component(
      name = "relationship",
      description = paste0(
        "Classify the relationship between the respondent and each food."
      ),
      dependencies = "food",
      enabled_by_default = TRUE,
      fields = list(
        respondent_relationship = define_extraction_field(
          name = "respondent_relationship",
          scope = "food",
          type = "enum",
          description = paste0(
            "The respondent's relationship to the food mention. Do not ",
            "treat purchasing, handling, preparation, or another person's ",
            "consumption as respondent consumption."
          ),
          required = TRUE,
          nullable = FALSE,
          allowed_values = vocabulary$respondent_relationship
        )
      )
    ),

    uncertainty = define_extraction_component(
      name = "uncertainty",
      description = paste0(
        "Represent certainty, uncertainty, or unresolved conflict in each ",
        "food statement."
      ),
      dependencies = "food",
      enabled_by_default = FALSE,
      fields = list(
        uncertainty = define_extraction_field(
          name = "uncertainty",
          scope = "food",
          type = "enum",
          description = paste0(
            "Certainty expressed in the interview statement, not the ",
            "model's confidence."
          ),
          required = TRUE,
          nullable = FALSE,
          allowed_values = vocabulary$uncertainty
        )
      )
    ),

    evidence = define_extraction_component(
      name = "evidence",
      description = paste0(
        "Extract an exact supporting quotation for every food mention."
      ),
      dependencies = "food",
      enabled_by_default = TRUE,
      fields = list(
        evidence_text = define_extraction_field(
          name = "evidence_text",
          scope = "food",
          type = "string",
          description = paste0(
            "Exact quotation from the narrative supporting the food ",
            "mention and its relationship to the respondent. Do not ",
            "paraphrase."
          ),
          required = TRUE,
          nullable = FALSE
        )
      )
    ),

    food_review = define_extraction_component(
      name = "food_review",
      description = paste0(
        "Return food-level review recommendations and standardized reasons."
      ),
      dependencies = "food",
      enabled_by_default = FALSE,
      fields = list(
        food_needs_review = define_extraction_field(
          name = "food_needs_review",
          scope = "food",
          type = "boolean",
          description = paste0(
            "Whether this food-level extraction should receive independent ",
            "review."
          ),
          required = TRUE,
          nullable = FALSE,
          default = FALSE
        ),

        food_review_reasons = define_extraction_field(
          name = "food_review_reasons",
          scope = "food",
          type = "enum_array",
          description = paste0(
            "Zero or more standardized food-level reasons for review."
          ),
          required = TRUE,
          nullable = FALSE,
          allowed_values = vocabulary$food_review_reason,
          default = character()
        )
      )
    )
  )
}

# Registry validation
# function to validate an extraction spec
#' Validate an extraction component registry
#'
#' @param registry A named list of extraction components.
#' @param require_resolved_dependencies Whether every declared dependency
#'   must also be present in the registry.
#'
#' @return `TRUE`, invisibly.
validate_extraction_component_registry <- function(
  registry,
  require_resolved_dependencies = TRUE
) {
  if (!is.list(registry)) {
    stop(
      paste0(
        "`registry` must be a list. Its type is `",
        typeof(registry),
        "`."
      ),
      call. = FALSE
    )
  }

  if (length(registry) == 0L) {
    stop(
      "`registry` must contain at least one component.",
      call. = FALSE
    )
  }

  registry_names <- names(registry)

  if (
    is.null(registry_names) ||
      anyNA(registry_names) ||
      any(!nzchar(registry_names)) ||
      anyDuplicated(registry_names)
  ) {
    stop(
      paste0(
        "`registry` must have unique, nonmissing, nonempty names."
      ),
      call. = FALSE
    )
  }

  all_field_names <- character()
  all_dependencies <- character()

  for (component_name in registry_names) {
    component <- registry[[component_name]]

    if (!is.list(component)) {
      stop(
        paste0(
          "Registry component `",
          component_name,
          "` must be a list. Its type is `",
          typeof(component),
          "`."
        ),
        call. = FALSE
      )
    }

    if (
      !inherits(
        component,
        "extraction_component"
      )
    ) {
      stop(
        paste0(
          "Registry component `",
          component_name,
          "` does not inherit from `extraction_component`."
        ),
        call. = FALSE
      )
    }

    if (
      !identical(
        component[["name"]],
        component_name
      )
    ) {
      stop(
        paste0(
          "Registry name `",
          component_name,
          "` does not match the component's internal name."
        ),
        call. = FALSE
      )
    }

    fields <- component[["fields"]]

    if (
      !is.list(fields) ||
        length(fields) == 0L ||
        is.null(names(fields)) ||
        anyNA(names(fields)) ||
        any(!nzchar(names(fields))) ||
        anyDuplicated(names(fields))
    ) {
      stop(
        paste0(
          "Component `",
          component_name,
          "` must contain a named, nonempty `fields` list."
        ),
        call. = FALSE
      )
    }

    for (field_name in names(fields)) {
      field <- fields[[field_name]]

      if (!is.list(field)) {
        stop(
          paste0(
            "Field `",
            field_name,
            "` in component `",
            component_name,
            "` must be a list. Its type is `",
            typeof(field),
            "`."
          ),
          call. = FALSE
        )
      }

      if (
        !inherits(
          field,
          "extraction_field"
        )
      ) {
        stop(
          paste0(
            "Field `",
            field_name,
            "` in component `",
            component_name,
            "` does not inherit from `extraction_field`."
          ),
          call. = FALSE
        )
      }

      if (
        !identical(
          field[["name"]],
          field_name
        )
      ) {
        stop(
          paste0(
            "Field `",
            field_name,
            "` in component `",
            component_name,
            "` has a nonmatching internal name."
          ),
          call. = FALSE
        )
      }
    }

    all_field_names <- c(
      all_field_names,
      names(fields)
    )

    all_dependencies <- c(
      all_dependencies,
      component[["dependencies"]]
    )
  }

  duplicate_fields <- unique(
    all_field_names[
      duplicated(all_field_names)
    ]
  )

  if (length(duplicate_fields) > 0L) {
    stop(
      paste0(
        "Field names must be unique across components. Duplicates: ",
        paste(
          duplicate_fields,
          collapse = ", "
        ),
        "."
      ),
      call. = FALSE
    )
  }

  if (isTRUE(require_resolved_dependencies)) {
    unknown_dependencies <- setdiff(
      unique(all_dependencies),
      registry_names
    )

    if (length(unknown_dependencies) > 0L) {
      stop(
        paste0(
          "The registry contains unknown dependencies: ",
          paste(
            unknown_dependencies,
            collapse = ", "
          ),
          "."
        ),
        call. = FALSE
      )
    }
  }

  invisible(TRUE)
}

#' List available extraction components
#'
#' @param registry Complete extraction component registry.
#'
#' @return A tibble with one row per component.
available_extraction_components <- function(
  registry = extraction_component_registry()
) {
  validate_extraction_component_registry(
    registry
  )

  component_names <- names(registry)

  rows <- vector(
    mode = "list",
    length = length(registry)
  )

  for (index in seq_along(registry)) {
    component_name <- component_names[[index]]
    component_object <- registry[[index]]

    if (!is.list(component_object)) {
      stop(
        paste0(
          "Component `",
          component_name,
          "` must be a list. Its type is `",
          typeof(component_object),
          "`."
        ),
        call. = FALSE
      )
    }

    fields <- component_object[["fields"]]

    if (!is.list(fields)) {
      stop(
        paste0(
          "The `fields` element of component `",
          component_name,
          "` must be a list. Its type is `",
          typeof(fields),
          "`."
        ),
        call. = FALSE
      )
    }

    field_scopes <- character(
      length(fields)
    )

    field_names <- names(fields)

    for (field_index in seq_along(fields)) {
      field_name <- field_names[[field_index]]
      field_object <- fields[[field_index]]

      if (!is.list(field_object)) {
        stop(
          paste0(
            "Field `",
            field_name,
            "` in component `",
            component_name,
            "` must be a list. Its type is `",
            typeof(field_object),
            "`."
          ),
          call. = FALSE
        )
      }

      field_scope <- field_object[["scope"]]

      if (!is_one_nonempty_string(field_scope)) {
        stop(
          paste0(
            "Field `",
            field_name,
            "` in component `",
            component_name,
            "` has an invalid scope."
          ),
          call. = FALSE
        )
      }

      field_scopes[[field_index]] <- field_scope
    }

    rows[[index]] <- tibble::tibble(
      component = component_name,
      scopes = list(unique(field_scopes)),
      field_count = length(fields),
      dependencies = list(
        component_object[["dependencies"]]
      ),
      recommended_inputs = list(
        component_object[["recommended_inputs"]]
      ),
      enabled_by_default = component_object[["enabled_by_default"]],
      description = component_object[["description"]]
    )
  }

  dplyr::bind_rows(rows)
}

resolve_extraction_components <- function(
  components,
  registry
) {
  validate_extraction_component_registry(registry)

  available <- names(registry)

  if (
    !is.character(components) ||
      length(components) == 0L ||
      anyNA(components) ||
      any(!nzchar(trimws(components)))
  ) {
    stop(
      paste0(
        "`components` must be a nonempty character vector, ",
        "`\"default\"`, or `\"all\"`."
      ),
      call. = FALSE
    )
  }

  if ("all" %in% components && length(components) > 1L) {
    stop(
      "`\"all\"` cannot be combined with other component names.",
      call. = FALSE
    )
  }

  if ("default" %in% components && length(components) > 1L) {
    stop(
      "`\"default\"` cannot be combined with other component names.",
      call. = FALSE
    )
  }

  if (identical(components, "all")) {
    selected <- available
  } else if (identical(components, "default")) {
    selected <- available[
      vapply(
        registry,
        function(component_object) {
          component_object[["enabled_by_default"]]
        },
        FUN.VALUE = logical(1)
      )
    ]
  } else {
    unknown <- setdiff(
      components,
      available
    )

    if (length(unknown) > 0L) {
      stop(
        paste0(
          "Unknown extraction components: ",
          paste(unknown, collapse = ", "),
          ".\nAvailable components: ",
          paste(available, collapse = ", "),
          "."
        ),
        call. = FALSE
      )
    }

    selected <- unique(components)
  }

  # Resolve transitive dependencies. For example, requesting `evidence`
  # automatically adds `food`, because evidence is attached to a food
  # mention.
  repeat {
    dependencies <- unique(
      unlist(
        lapply(
          registry[selected],
          function(component_object) {
            component_object[["dependencies"]]
          }
        ),
        use.names = FALSE
      )
    )

    expanded <- union(
      selected,
      dependencies
    )

    if (setequal(expanded, selected)) {
      break
    }

    selected <- expanded
  }

  # Preserve registry order. This produces a stable and understandable field
  # order without using hashes or generated identifiers.
  available[available %in% selected]
}

# Spec constructor -----

# Build a modular food-extraction spec from components to be used
# probably the main front-facing function
# #' Create a modular food-event extraction specification
#'
#' @param components Components to include. Use `"default"` for the
#'   lightweight default, `"all"` for every component, or a character vector
#'   of component names.
#' @param registry Complete extraction component registry.
#' @param specification_id Specification family identifier.
#' @param specification_version Human-readable specification version.
#' @param metadata Optional named list of additional metadata.
#'
#' @return An object of class `food_extraction_spec`.
food_extraction_spec <- function(
  components = "default",
  registry = extraction_component_registry(),
  specification_id = "food_event_extraction",
  specification_version = "1.0.0",
  metadata = list()
) {
  validate_extraction_component_registry(registry)

  if (!is_one_nonempty_string(specification_id)) {
    stop(
      "`specification_id` must be one nonempty character value.",
      call. = FALSE
    )
  }

  if (!is_one_nonempty_string(specification_version)) {
    stop(
      paste0(
        "`specification_version` must be one nonempty character value."
      ),
      call. = FALSE
    )
  }

  if (!is.list(metadata)) {
    stop(
      "`metadata` must be a list.",
      call. = FALSE
    )
  }

  selected_components <- resolve_extraction_components(
    components = components,
    registry = registry
  )

  specification <- list(
    specification_id = specification_id,
    specification_version = specification_version,
    selected_components = selected_components,
    components = registry[selected_components],
    registry = registry,
    metadata = metadata
  )

  class(specification) <- "food_extraction_spec"

  validate_food_extraction_spec(specification)

  specification
}

# Validate complete specs
#' Validate a food-event extraction specification
#'
#' @param specification An extraction specification.
#'
#' @return `TRUE`, invisibly.
validate_food_extraction_spec <- function(specification) {
  if (!inherits(specification, "food_extraction_spec")) {
    stop(
      paste0(
        "`specification` must be created with ",
        "`food_extraction_spec()`."
      ),
      call. = FALSE
    )
  }

  required_elements <- c(
    "specification_id",
    "specification_version",
    "selected_components",
    "components",
    "registry",
    "metadata"
  )

  missing_elements <- setdiff(
    required_elements,
    names(specification)
  )

  if (length(missing_elements) > 0L) {
    stop(
      paste0(
        "The extraction specification is missing: ",
        paste(missing_elements, collapse = ", "),
        "."
      ),
      call. = FALSE
    )
  }

  if (
    !is_one_nonempty_string(
      specification$specification_id
    )
  ) {
    stop(
      "`specification_id` is invalid.",
      call. = FALSE
    )
  }

  if (
    !is_one_nonempty_string(
      specification$specification_version
    )
  ) {
    stop(
      "`specification_version` is invalid.",
      call. = FALSE
    )
  }

  if (
    !is.character(specification$selected_components) ||
      length(specification$selected_components) == 0L ||
      anyNA(specification$selected_components) ||
      anyDuplicated(specification$selected_components)
  ) {
    stop(
      paste0(
        "`selected_components` must contain one or more unique component ",
        "names."
      ),
      call. = FALSE
    )
  }

  validate_extraction_component_registry(
    specification$registry
  )

  unknown_components <- setdiff(
    specification$selected_components,
    names(specification$registry)
  )

  if (length(unknown_components) > 0L) {
    stop(
      paste0(
        "The specification contains unknown selected components: ",
        paste(unknown_components, collapse = ", "),
        "."
      ),
      call. = FALSE
    )
  }

  expected_components <- specification$registry[
    specification$selected_components
  ]

  if (
    !identical(
      names(specification$components),
      names(expected_components)
    )
  ) {
    stop(
      paste0(
        "`components` does not match `selected_components`."
      ),
      call. = FALSE
    )
  }

  unresolved_dependencies <- unique(
    unlist(
      lapply(
        specification[["components"]],
        function(component_object) {
          setdiff(
            component_object[["dependencies"]],
            specification[["selected_components"]]
          )
        }
      ),
      use.names = FALSE
    )
  )

  if (length(unresolved_dependencies) > 0L) {
    stop(
      paste0(
        "Selected components have unresolved dependencies: ",
        paste(unresolved_dependencies, collapse = ", "),
        "."
      ),
      call. = FALSE
    )
  }

  fields <- extraction_spec_fields(
    specification
  )

  if (anyDuplicated(fields$field)) {
    stop(
      "The specification contains duplicate field names.",
      call. = FALSE
    )
  }

  invisible(TRUE)
}

#' Return extraction fields as a tidy table
#'
#' @param specification Food-event extraction specification.
#' @param scope One or more of `"interview"`, `"event"`, or `"food"`.
#'
#' @return A tibble with one row per selected field.
extraction_spec_fields <- function(
  specification,
  scope = c(
    "interview",
    "event",
    "food"
  )
) {
  if (
    !inherits(
      specification,
      "food_extraction_spec"
    )
  ) {
    stop(
      paste0(
        "`specification` must be created with ",
        "`food_extraction_spec()`."
      ),
      call. = FALSE
    )
  }

  valid_scopes <- c(
    "interview",
    "event",
    "food"
  )

  if (
    !is.character(scope) ||
      length(scope) == 0L ||
      anyNA(scope)
  ) {
    stop(
      "`scope` must contain one or more valid scope names.",
      call. = FALSE
    )
  }

  unknown_scopes <- setdiff(
    scope,
    valid_scopes
  )

  if (length(unknown_scopes) > 0L) {
    stop(
      paste0(
        "Unknown scopes: ",
        paste(unknown_scopes, collapse = ", "),
        ". Valid scopes are: ",
        paste(valid_scopes, collapse = ", "),
        "."
      ),
      call. = FALSE
    )
  }

  components <- specification[["components"]]

  if (!is.list(components)) {
    stop(
      paste0(
        "The specification's `components` element must be a list."
      ),
      call. = FALSE
    )
  }

  component_names <- names(components)
  rows <- list()
  row_index <- 0L

  for (component_index in seq_along(components)) {
    component_name <-
      component_names[[component_index]]

    component_object <-
      components[[component_index]]

    if (!is.list(component_object)) {
      stop(
        paste0(
          "Specification component `",
          component_name,
          "` must be a list. Its type is `",
          typeof(component_object),
          "`."
        ),
        call. = FALSE
      )
    }

    fields <- component_object[["fields"]]

    if (!is.list(fields)) {
      stop(
        paste0(
          "The `fields` element of component `",
          component_name,
          "` must be a list. Its type is `",
          typeof(fields),
          "`."
        ),
        call. = FALSE
      )
    }

    field_names <- names(fields)

    for (field_index in seq_along(fields)) {
      field_name <- field_names[[field_index]]
      field_object <- fields[[field_index]]

      if (!is.list(field_object)) {
        stop(
          paste0(
            "Field `",
            field_name,
            "` in component `",
            component_name,
            "` must be a list. Its type is `",
            typeof(field_object),
            "`."
          ),
          call. = FALSE
        )
      }

      field_scope <- field_object[["scope"]]

      if (!field_scope %in% scope) {
        next
      }

      row_index <- row_index + 1L

      rows[[row_index]] <- tibble::tibble(
        component = component_name,
        scope = field_scope,
        field = field_object[["name"]],
        type = field_object[["type"]],
        required = field_object[["required"]],
        nullable = field_object[["nullable"]],
        allowed_values = list(
          field_object[["allowed_values"]]
        ),
        default = list(
          field_object[["default"]]
        ),
        description = field_object[["description"]]
      )
    }
  }

  if (length(rows) == 0L) {
    return(
      tibble::tibble(
        component = character(),
        scope = character(),
        field = character(),
        type = character(),
        required = logical(),
        nullable = logical(),
        allowed_values = list(),
        default = list(),
        description = character()
      )
    )
  }

  dplyr::bind_rows(rows)
}

#' Return extraction field objects for one scope
#'
#' @param specification Food-event extraction specification.
#' @param scope One of `"interview"`, `"event"`, or `"food"`.
#'
#' @return A named list of extraction-field objects.
extraction_fields_by_scope <- function(
  specification,
  scope
) {
  validate_food_extraction_spec(
    specification
  )

  scope <- match.arg(
    scope,
    choices = c(
      "interview",
      "event",
      "food"
    )
  )

  components <- specification[["components"]]
  selected_fields <- list()

  for (component_index in seq_along(components)) {
    component <- components[[component_index]]
    fields <- component[["fields"]]

    for (field_index in seq_along(fields)) {
      field <- fields[[field_index]]
      field_name <- field[["name"]]

      if (
        identical(
          field[["scope"]],
          scope
        )
      ) {
        selected_fields[[field_name]] <- field
      }
    }
  }

  selected_fields
}

# Get input roles
#' Return input roles recommended by selected components
#'
#' @param specification Food-event extraction specification.
#'
#' @return A character vector.
extraction_spec_recommended_inputs <- function(
  specification
) {
  validate_food_extraction_spec(
    specification
  )

  components <- specification[["components"]]
  recommended_inputs <- character()

  for (component_index in seq_along(components)) {
    component <- components[[component_index]]

    recommended_inputs <- c(
      recommended_inputs,
      component[["recommended_inputs"]]
    )
  }

  unique(recommended_inputs)
}

# Functions to modify specs (add/remove components)
#' Add or remove extraction components
#'
#' @param specification Existing food-event extraction specification.
#' @param add Components to add.
#' @param remove Components to remove.
#' @param specification_version Optional replacement version.
#' @param metadata Optional replacement metadata. If `NULL`, current metadata
#'   are retained.
#'
#' @return A modified `food_extraction_spec`.
modify_extraction_spec <- function(
  specification,
  add = character(),
  remove = character(),
  specification_version = NULL,
  metadata = NULL
) {
  validate_food_extraction_spec(specification)

  add <- validate_unique_character_vector(
    add,
    argument_name = "add",
    allow_empty = TRUE
  )

  remove <- validate_unique_character_vector(
    remove,
    argument_name = "remove",
    allow_empty = TRUE
  )

  unknown <- setdiff(
    c(add, remove),
    names(specification$registry)
  )

  if (length(unknown) > 0L) {
    stop(
      paste0(
        "Unknown extraction components: ",
        paste(unique(unknown), collapse = ", "),
        "."
      ),
      call. = FALSE
    )
  }

  selected <- union(
    specification$selected_components,
    add
  )

  selected <- setdiff(
    selected,
    remove
  )

  if (length(selected) == 0L) {
    stop(
      "An extraction specification must contain at least one component.",
      call. = FALSE
    )
  }

  if (is.null(specification_version)) {
    specification_version <-
      specification$specification_version
  }

  if (is.null(metadata)) {
    metadata <- specification$metadata
  }

  food_extraction_spec(
    components = selected,
    registry = specification$registry,
    specification_id = specification$specification_id,
    specification_version = specification_version,
    metadata = metadata
  )
}

# Add a component to a spec
#' Register an additional extraction component
#'
#' This is primarily a development function for testing experimental
#' components.
#'
#' @param registry Complete extraction component registry.
#' @param component Component created with
#'   `define_extraction_component()`.
#' @param overwrite Whether an existing component may be replaced.
#'
#' @return A modified registry.
register_extraction_component <- function(
  registry,
  component,
  overwrite = FALSE
) {
  validate_extraction_component_registry(registry)

  if (!inherits(component, "extraction_component")) {
    stop(
      paste0(
        "`component` must be created with ",
        "`define_extraction_component()`."
      ),
      call. = FALSE
    )
  }

  overwrite <- validate_logical_flag(
    overwrite,
    "overwrite"
  )

  component_name <- component$name

  if (component_name %in% names(registry) && !overwrite) {
    stop(
      paste0(
        "Component `",
        component_name,
        "` already exists. Set `overwrite = TRUE` to replace it."
      ),
      call. = FALSE
    )
  }

  registry[[component_name]] <- component

  validate_extraction_component_registry(registry)

  registry
}

# Make labels that people can actually read
#' Create a readable specification label
#'
#' This is a human-readable organizational label. It is not a hash and is
#' not intended to guarantee global uniqueness.
#'
#' @param specification Food-event extraction specification.
#'
#' @return A character value.
extraction_spec_label <- function(specification) {
  validate_food_extraction_spec(specification)

  paste(
    specification$specification_id,
    specification$specification_version,
    paste(
      specification$selected_components,
      collapse = "-"
    ),
    sep = "__"
  )
}

# Return a full spec manifest
#' Return a complete extraction-specification manifest
#'
#' The manifest records the full readable configuration rather than reducing
#' the specification to a hash.
#'
#' @param specification Food-event extraction specification.
#'
#' @return A list containing specification metadata and field definitions.
extraction_spec_manifest <- function(specification) {
  validate_food_extraction_spec(specification)

  list(
    specification_id = specification$specification_id,
    specification_version = specification$specification_version,
    specification_label = extraction_spec_label(specification),
    selected_components = specification$selected_components,
    recommended_inputs = extraction_spec_recommended_inputs(
      specification
    ),
    fields = extraction_spec_fields(specification),
    metadata = specification$metadata
  )
}

# Print method
#' Print a food-event extraction specification
#'
#' @param x Food-event extraction specification.
#' @param ... Additional arguments, currently unused.
#'
#' @return `x`, invisibly.
print.food_extraction_spec <- function(x, ...) {
  fields <- extraction_spec_fields(x)

  scope_counts <- fields |>
    dplyr::count(
      .data$scope,
      name = "field_count"
    )

  recommended_inputs <-
    extraction_spec_recommended_inputs(x)

  cat("Food-event extraction specification\n")
  cat("===================================\n")
  cat(
    "Specification ID:      ",
    x$specification_id,
    "\n",
    sep = ""
  )
  cat(
    "Specification version: ",
    x$specification_version,
    "\n",
    sep = ""
  )
  cat(
    "Components:            ",
    paste(
      x$selected_components,
      collapse = ", "
    ),
    "\n",
    sep = ""
  )
  cat(
    "Recommended inputs:    ",
    if (length(recommended_inputs) == 0L) {
      "none"
    } else {
      paste(
        recommended_inputs,
        collapse = ", "
      )
    },
    "\n",
    sep = ""
  )

  cat("\nFields by scope:\n")

  for (row in seq_len(nrow(scope_counts))) {
    cat(
      "  ",
      scope_counts$scope[[row]],
      ": ",
      scope_counts$field_count[[row]],
      "\n",
      sep = ""
    )
  }

  invisible(x)
}
