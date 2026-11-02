# R/structured_input/partially_structured_json.R
#
# Deterministic preprocessing of sparse, partially structured food-exposure
# data, including an MDSS-compatible preset.
#
# Main user-facing wrapper:
#
#   build_exposure_json()
#
# The pipeline:
#
# 1. Maps source columns to known roles.
# 2. Normalizes affirmative questionnaire responses.
# 3. Parses indexed values such as:
#      [0]Taco Bell[1]Jimmy John's
# 4. Aligns parallel indexed fields by index.
# 5. Retains known affirmative food exposures and populated event records.
# 6. Preserves source-column provenance.
# 7. Returns nested R objects or JSON.
#
# It does not:
#
# - infer causal foods;
# - infer missing dates, locations, or ingredients;
# - treat unknown values as affirmative;
# - send data to an LLM;
# - use hashes.

# =========================================================================
# Small validation and missing-value helpers
# =========================================================================

is_one_string <- function(x, allow_empty = FALSE) {
  valid <- is.character(x) &&
    length(x) == 1L &&
    !is.na(x)

  if (!allow_empty) {
    valid <- valid && nzchar(trimws(x))
  }

  valid
}


validate_data_frame <- function(data) {
  if (!is.data.frame(data)) {
    stop(
      "`data` must be a data frame or tibble.",
      call. = FALSE
    )
  }

  invisible(TRUE)
}


validate_named_character <- function(x, argument_name) {
  valid <- is.character(x) &&
    !is.null(names(x)) &&
    length(x) > 0L &&
    !anyNA(x) &&
    !anyNA(names(x)) &&
    all(nzchar(names(x))) &&
    all(nzchar(x)) &&
    !anyDuplicated(names(x))

  if (!valid) {
    stop(
      "`",
      argument_name,
      "` must be a named character vector with unique names.",
      call. = FALSE
    )
  }

  x
}


default_missing_codes <- function() {
  c(
    "",
    "NA",
    "N/A",
    "NULL",
    "NONE",
    "NOT PROVIDED",
    "NO INFO PROVIDED"
  )
}


default_unknown_codes <- function() {
  c(
    "U",
    "UNK",
    "UNKNOWN",
    "UNABLE TO RECALL",
    "DOESN'T REMEMBER",
    "DOES NOT REMEMBER"
  )
}


default_yes_codes <- function() {
  c(
    "Y",
    "YES",
    "TRUE",
    "T",
    "1",
    "CHECKED"
  )
}


default_no_codes <- function() {
  c(
    "N",
    "NO",
    "FALSE",
    "F",
    "0",
    "NOTTRAVEL"
  )
}

is_missing_text_scalar <- function(x) {
  if (is.null(x) || length(x) == 0L) {
    return(TRUE)
  }

  if (length(x) != 1L) {
    stop(
      paste0(
        "Expected one text value but received ",
        length(x),
        " values."
      ),
      call. = FALSE
    )
  }

  x <- as.character(x)

  if (is.na(x)) {
    return(TRUE)
  }

  !nzchar(trimws(x))
}


normalize_text_value <- function(
  value,
  missing_codes = default_missing_codes()
) {
  if (length(value) == 0L || is.null(value) || is.na(value[[1]])) {
    return(NA_character_)
  }

  value <- trimws(as.character(value[[1]]))

  if (!nzchar(value)) {
    return(NA_character_)
  }

  if (toupper(value) %in% toupper(missing_codes)) {
    return(NA_character_)
  }

  value
}


normalize_yes_no_unknown <- function(
  value,
  yes_codes = default_yes_codes(),
  no_codes = default_no_codes(),
  unknown_codes = default_unknown_codes(),
  missing_codes = default_missing_codes()
) {
  value <- normalize_text_value(
    value,
    missing_codes = missing_codes
  )

  if (is.na(value)) {
    return("missing")
  }

  normalized <- toupper(trimws(value))

  if (normalized %in% toupper(yes_codes)) {
    return("yes")
  }

  if (normalized %in% toupper(no_codes)) {
    return("no")
  }

  if (normalized %in% toupper(unknown_codes)) {
    return("unknown")
  }

  "unrecognized"
}


# =========================================================================
# Date parsing
# =========================================================================
parse_source_date <- function(value) {
  value <- normalize_text_value(value)

  if (is.na(value)) {
    return(NA_character_)
  }

  date_formats <- c(
    "%m/%d/%Y",
    "%Y-%m-%d",
    "%m/%d/%y"
  )

  for (date_format in date_formats) {
    parsed_date <- suppressWarnings(
      as.Date(
        value,
        format = date_format
      )
    )

    if (!is.na(parsed_date)) {
      return(
        base::format(
          parsed_date,
          format = "%Y-%m-%d"
        )
      )
    }
  }

  # The original date text remains available elsewhere. This function
  # returns only a confidently normalized date.
  NA_character_
}


# =========================================================================
# Indexed multi-value parsing
# =========================================================================

# MDSS cells may contain:
#
#   [0]Taco Bell[1]Jimmy John's
#
# or:
#
#   [1]07/01/2026[2]07/03/2026
#
# Sometimes they don't start at 0 and sometimes they skip vals
parse_indexed_values <- function(
  value,
  missing_codes = default_missing_codes()
) {
  empty_result <- tibble::tibble(
    source_index = integer(),
    value = character(),
    was_indexed = logical()
  )

  value <- normalize_text_value(
    value,
    missing_codes = missing_codes
  )

  if (is.na(value)) {
    return(empty_result)
  }

  # Match numeric MDSS index markers such as [0], [1], and [12].
  marker_locations <- gregexpr(
    pattern = "\\[[0-9]+\\]",
    text = value,
    perl = TRUE
  )[[1]]

  # gregexpr() returns -1 when there are no matching markers.
  has_markers <- !(length(marker_locations) == 1L &&
    identical(marker_locations[[1]], -1L))

  if (!has_markers) {
    return(
      tibble::tibble(
        source_index = 0L,
        value = value,
        was_indexed = FALSE
      )
    )
  }

  marker_lengths <- attr(
    marker_locations,
    "match.length"
  )

  marker_text <- regmatches(
    value,
    list(marker_locations)
  )[[1]]

  # Extract only the digits captured between the brackets.
  #
  # This is safer than deleting bracket characters with gsub() and then
  # coercing whatever remains.
  index_text <- sub(
    pattern = "^\\[([0-9]+)\\]$",
    replacement = "\\1",
    x = marker_text,
    perl = TRUE
  )

  source_indices <- suppressWarnings(
    as.integer(index_text)
  )

  if (anyNA(source_indices)) {
    invalid_markers <- marker_text[
      is.na(source_indices)
    ]

    stop(
      paste0(
        "An indexed MDSS cell contains markers that could not be parsed ",
        "as integers.\n",
        "Cell value: ",
        value,
        "\n",
        "Invalid markers: ",
        paste(
          invalid_markers,
          collapse = ", "
        )
      ),
      call. = FALSE
    )
  }

  if (anyDuplicated(source_indices)) {
    duplicated_indices <- unique(
      source_indices[
        duplicated(source_indices)
      ]
    )

    stop(
      paste0(
        "An indexed MDSS cell contains duplicated source indexes.\n",
        "Cell value: ",
        value,
        "\n",
        "Duplicated indexes: ",
        paste(
          duplicated_indices,
          collapse = ", "
        )
      ),
      call. = FALSE
    )
  }

  # Values begin immediately after each marker.
  value_starts <- marker_locations +
    marker_lengths

  # Each value ends immediately before the next marker. The final value ends
  # at the end of the source string.
  value_ends <- c(
    marker_locations[-1L] - 1L,
    nchar(value)
  )

  parsed_values <- mapply(
    FUN = function(start, end) {
      substr(
        value,
        start = start,
        stop = end
      )
    },
    start = value_starts,
    end = value_ends,
    USE.NAMES = FALSE
  )

  parsed_values <- trimws(
    parsed_values
  )

  keep <- !is.na(parsed_values) &
    nzchar(parsed_values) &
    !toupper(parsed_values) %in%
      toupper(missing_codes)

  tibble::tibble(
    source_index = source_indices[keep],
    value = parsed_values[keep],
    was_indexed = rep(
      TRUE,
      sum(keep)
    )
  )
}


#' Parse a scalar or indexed multi-value source cell
#'
#' @param value One source-cell value.
#'
#' @return A named character vector. Names are source indexes.
parse_multivalue_cell <- function(value) {
  parsed <- parse_indexed_values(value)

  if (nrow(parsed) == 0L) {
    return(
      stats::setNames(
        character(),
        character()
      )
    )
  }

  if (anyNA(parsed$source_index)) {
    stop(
      "Parsed source indexes must not contain missing values.",
      call. = FALSE
    )
  }

  if (anyDuplicated(parsed$source_index)) {
    stop(
      "Parsed source indexes must be unique within a cell.",
      call. = FALSE
    )
  }

  stats::setNames(
    parsed$value,
    as.character(parsed$source_index)
  )
}


align_indexed_fields <- function(values_by_role) {
  if (
    !is.list(values_by_role) ||
      is.null(names(values_by_role)) ||
      anyNA(names(values_by_role)) ||
      any(!nzchar(names(values_by_role))) ||
      anyDuplicated(names(values_by_role))
  ) {
    stop(
      paste0(
        "`values_by_role` must be a named list with unique, ",
        "nonempty names."
      ),
      call. = FALSE
    )
  }

  role_names <- names(values_by_role)

  parsed_by_role <- vector(
    mode = "list",
    length = length(values_by_role)
  )

  names(parsed_by_role) <- role_names

  for (role_index in seq_along(values_by_role)) {
    role_name <- role_names[[role_index]]

    parsed <- parse_indexed_values(
      values_by_role[[role_index]]
    )

    if (anyNA(parsed$source_index)) {
      stop(
        paste0(
          "Role `",
          role_name,
          "` produced a missing source index."
        ),
        call. = FALSE
      )
    }

    if (anyDuplicated(parsed$source_index)) {
      duplicated_indices <- unique(
        parsed$source_index[
          duplicated(parsed$source_index)
        ]
      )

      stop(
        paste0(
          "Role `",
          role_name,
          "` contains duplicated source indexes: ",
          paste(
            duplicated_indices,
            collapse = ", "
          ),
          "."
        ),
        call. = FALSE
      )
    }

    parsed_by_role[[role_index]] <- parsed
  }

  all_indices <- unique(
    unlist(
      lapply(
        parsed_by_role,
        function(parsed) {
          parsed$source_index
        }
      ),
      use.names = FALSE
    )
  )

  if (length(all_indices) == 0L) {
    return(list())
  }

  # source_index is already an integer, so no additional coercion is needed.
  all_indices <- sort(
    all_indices,
    na.last = NA
  )

  aligned_records <- vector(
    mode = "list",
    length = length(all_indices)
  )

  for (index_position in seq_along(all_indices)) {
    current_index <- all_indices[[index_position]]

    aligned_record <- list(
      source_index = current_index
    )

    for (role_name in role_names) {
      parsed_role <- parsed_by_role[[role_name]]

      matches <- which(
        parsed_role$source_index == current_index
      )

      if (length(matches) == 0L) {
        aligned_record[[role_name]] <- NULL
        next
      }

      if (length(matches) > 1L) {
        stop(
          paste0(
            "Role `",
            role_name,
            "` contains more than one value at source index ",
            current_index,
            "."
          ),
          call. = FALSE
        )
      }

      aligned_record[[role_name]] <-
        parsed_role$value[[matches[[1]]]]
    }

    aligned_records[[index_position]] <-
      aligned_record
  }

  aligned_records
}


# =========================================================================
# Configuration constructors
# =========================================================================

# A general-event map identifies sets of parallel fields. This allows the
# same parser to work with MDSS and other wide-format systems.

define_event_source <- function(
  event_type,
  date_column = NULL,
  name_column = NULL,
  food_column,
  location_column = NULL
) {
  if (!is_one_string(event_type)) {
    stop(
      "`event_type` must be one nonempty character value.",
      call. = FALSE
    )
  }

  if (!is_one_string(food_column)) {
    stop(
      "`food_column` must be one nonempty character value.",
      call. = FALSE
    )
  }

  optional_columns <- list(
    date_column = date_column,
    name_column = name_column,
    location_column = location_column
  )

  for (argument_name in names(optional_columns)) {
    value <- optional_columns[[argument_name]]

    if (
      !is.null(value) &&
        !is_one_string(value)
    ) {
      stop(
        "`",
        argument_name,
        "` must be NULL or one nonempty character value.",
        call. = FALSE
      )
    }
  }

  list(
    event_type = event_type,
    date_column = date_column,
    name_column = name_column,
    food_column = food_column,
    location_column = location_column
  )
}


# A food-item map identifies questionnaire response columns and optional
# detail columns. Only response == yes is retained.

define_food_item <- function(
  item_id,
  food_label,
  response_column,
  type_column = NULL,
  other_column = NULL,
  brand_column = NULL,
  purchase_location_column = NULL,
  establishment_column = NULL
) {
  required <- c(
    item_id = item_id,
    food_label = food_label,
    response_column = response_column
  )

  for (argument_name in names(required)) {
    if (!is_one_string(required[[argument_name]])) {
      stop(
        "`",
        argument_name,
        "` must be one nonempty character value.",
        call. = FALSE
      )
    }
  }

  optional <- list(
    type_column = type_column,
    other_column = other_column,
    brand_column = brand_column,
    purchase_location_column = purchase_location_column,
    establishment_column = establishment_column
  )

  for (argument_name in names(optional)) {
    value <- optional[[argument_name]]

    if (
      !is.null(value) &&
        !is_one_string(value)
    ) {
      stop(
        "`",
        argument_name,
        "` must be NULL or one nonempty character value.",
        call. = FALSE
      )
    }
  }

  list(
    item_id = item_id,
    food_label = food_label,
    response_column = response_column,
    type_column = type_column,
    other_column = other_column,
    brand_column = brand_column,
    purchase_location_column = purchase_location_column,
    establishment_column = establishment_column
  )
}


# =========================================================================
# MDSS preset: explicit event sources
# =========================================================================

mdss_event_sources <- function() {
  list(
    purchased_food = define_event_source(
      event_type = "food_purchase",
      date_column = "Date",
      name_column = "Name",
      food_column = "Food_Purchased",
      location_column = "Location"
    ),

    restaurant_or_other_event = define_event_source(
      event_type = "food_consumption",
      date_column = "Date000",
      name_column = "Name000",
      food_column = "Food_Consumed",
      location_column = "Location_Event"
    ),

    private_group_event = define_event_source(
      event_type = "private_group_event",
      date_column = "Date001",
      name_column = "Private_Group_Event",
      food_column = "Food_Consumed000",
      location_column = "Location000"
    )
  )
}


# =========================================================================
# MDSS preset: food questionnaire items
# =========================================================================

# This map intentionally includes response fields for which the column name
# clearly identifies a food. Detail columns are attached only where the
# supplied export structure gives a reasonably explicit adjacent block.
#
# The map should be reviewed against the original MDSS form/data dictionary
# before production use.

mdss_food_items <- function() {
  items <- list(
    define_food_item(
      "fresh_basil",
      "Fresh basil",
      "Fresh_basil_",
      type_column = "Type_s__",
      other_column = "Other__specify_000",
      brand_column = "Brand_s__",
      purchase_location_column = "Place_s__purchased__names__lo",
      establishment_column = "List_name_s__of_establishment"
    ),

    define_food_item(
      "fresh_cilantro",
      "Fresh cilantro",
      "Fresh_cilantro_",
      brand_column = "Brand_s__000",
      purchase_location_column = "Place_s__purchased__names__lo000",
      establishment_column = "List_name_s__of_establishment000"
    ),

    define_food_item(
      "fresh_parsley",
      "Fresh parsley",
      "Fresh_parsley_"
    ),

    define_food_item(
      "fresh_oregano",
      "Fresh oregano",
      "Fresh_oregano_"
    ),

    define_food_item(
      "fresh_thyme",
      "Fresh thyme",
      "Fresh_thyme_"
    ),

    define_food_item(
      "fresh_mint",
      "Fresh mint",
      "Fresh_mint_"
    ),

    define_food_item(
      "fresh_dill",
      "Fresh dill",
      "Fresh_dill_"
    ),

    define_food_item(
      "fresh_sage",
      "Fresh sage",
      "Fresh_sage_"
    ),

    define_food_item(
      "fresh_rosemary",
      "Fresh rosemary",
      "Fresh_rosemary_"
    ),

    define_food_item(
      "other_fresh_herbs",
      "Other fresh herbs",
      "Other_fresh_herbs_",
      type_column = "Type_s__000"
    ),

    define_food_item(
      "fresh_red_raspberries",
      "Fresh red raspberries",
      "resh_red_raspberries_",
      brand_column = "Brand_s__001",
      purchase_location_column = "Place_s__purchased__names__lo001",
      establishment_column = "List_name_s__of_establishment001"
    ),

    define_food_item(
      "fresh_blackberries",
      "Fresh blackberries",
      "Fresh_blackberries_",
      brand_column = "Brand_s__002",
      purchase_location_column = "Place_s__purchased__names__lo002",
      establishment_column = "List_name_s__of_establishment002"
    ),

    define_food_item(
      "fresh_black_raspberries",
      "Fresh black raspberries",
      "Fresh_black_raspberries_"
    ),

    define_food_item(
      "fresh_golden_raspberries",
      "Fresh golden raspberries",
      "Fresh_golden_raspberries_"
    ),

    define_food_item(
      "fresh_strawberries",
      "Fresh strawberries",
      "Fresh_strawberries_"
    ),

    define_food_item(
      "fresh_blueberries",
      "Fresh blueberries",
      "Fresh_blueberries_"
    ),

    define_food_item(
      "fresh_boysenberries",
      "Fresh boysenberries",
      "Fresh_boysenberries_"
    ),

    define_food_item(
      "other_fresh_berries",
      "Other fresh berries",
      "Other_fresh_berries_",
      type_column = "Type_s__001"
    ),

    define_food_item("apples", "Apples", "Apples_"),
    define_food_item("grapes", "Grapes", "Grapes_"),
    define_food_item("pears", "Pears", "Pears_"),
    define_food_item("peaches", "Peaches", "Peaches_"),
    define_food_item("nectarines", "Nectarines", "Nectarines_"),
    define_food_item("plums", "Plums", "Plums_"),
    define_food_item("oranges", "Oranges", "Oranges_"),
    define_food_item("grapefruit", "Grapefruit", "Grapefruit_"),
    define_food_item("tangerines", "Tangerines", "Tangerines_"),

    define_food_item(
      "fresh_lemon_or_lime",
      "Fresh lemon or lime",
      "Fresh_lemon_or_lime__This_cou"
    ),

    define_food_item("cherries", "Cherries", "Cherries_"),
    define_food_item("cantaloupe", "Cantaloupe", "Cantaloupe_"),
    define_food_item(
      "honeydew_melon",
      "Honeydew melon",
      "Honeydew_melon_"
    ),
    define_food_item(
      "watermelon",
      "Watermelon",
      "Watermelon_"
    ),
    define_food_item(
      "precut_melon_or_melon_salad",
      "Precut melon or melon salad",
      "Precut_melon_or_melon_salad_"
    ),
    define_food_item(
      "other_melon",
      "Other melon",
      "Other_melon_"
    ),
    define_food_item("pineapple", "Pineapple", "Pineapple_"),
    define_food_item("mango", "Mango", "Mango_"),
    define_food_item(
      "coconut",
      "Coconut",
      "Coconut__whole_or_shredded___"
    ),
    define_food_item(
      "other_fruit",
      "Other fruit",
      "Other_fruit__",
      type_column = "Type_s__002",
      other_column = "Other__specify_001"
    ),

    define_food_item(
      "premade_single_serving_salad",
      "Premade single-serving salad",
      "Pre_made__single_serving_sala",
      other_column = "Ingredients",
      brand_column = "Brand_s__003",
      purchase_location_column = "Place_s__purchased"
    ),

    define_food_item(
      "iceberg_lettuce",
      "Iceberg lettuce",
      "Iceberg_lettuce_",
      type_column = "Type_s__003",
      brand_column = "Brand_s__004",
      purchase_location_column = "Place_s__purchased000",
      establishment_column = "List_name_s__of_establishment003"
    ),

    define_food_item(
      "romaine_lettuce",
      "Romaine lettuce",
      "Romaine_lettuce_",
      type_column = "Type_s__004",
      brand_column = "Brand_s__005",
      purchase_location_column = "Place_s__purchased001",
      establishment_column = "List_name_s__of_establishment004"
    ),

    define_food_item(
      "mesclun_lettuce",
      "Mesclun lettuce",
      "Mesclun_lettuce_",
      type_column = "Type_s__005",
      brand_column = "Brand_s__006",
      purchase_location_column = "Place_s__purchased002",
      establishment_column = "List_name_s__of_establishment005"
    ),

    define_food_item(
      "fresh_cabbage",
      "Fresh cabbage",
      "Fresh_cabbage_",
      type_column = "Type_s__006",
      other_column = "Other__specify_002",
      brand_column = "Brand_s__007",
      purchase_location_column = "Place_s__purchased003",
      establishment_column = "List_name_s__of_establishment006"
    ),

    define_food_item(
      "fresh_spinach",
      "Fresh spinach",
      "Fresh_spinach_",
      type_column = "Type_s__007",
      brand_column = "Brand_s__008",
      purchase_location_column = "Place_s__purchased004",
      establishment_column = "List_name_s__of_establishment007"
    ),

    define_food_item(
      "other_leafy_greens",
      "Other lettuce or leafy greens",
      "Other_lettuce_or_leafy_greens",
      type_column = "Type_s__008",
      other_column = "Other__specify_003"
    ),

    define_food_item(
      "other_prepackaged_salad_mix",
      "Other prepackaged salad mix",
      "Other_prepackaged_salad_mix__",
      other_column = "Ingredients__lettuce__cabbage",
      brand_column = "Brand_s__009",
      purchase_location_column = "Place_s__purchased005"
    ),

    define_food_item("cucumbers", "Cucumbers", "Cucumbers_"),
    define_food_item("zucchini", "Zucchini", "Zucchini_"),
    define_food_item("squash", "Squash", "Squash_"),

    define_food_item(
      "bell_peppers",
      "Bell peppers",
      "Bell_peppers_",
      type_column = "Type_s__009"
    ),

    define_food_item(
      "hot_chili_peppers",
      "Hot chili peppers",
      "Hot_chili_chili_peppers__e_g_"
    ),

    define_food_item("celery", "Celery", "Celery_"),
    define_food_item(
      "mini_carrots",
      "Mini carrots",
      "Mini_carrots_"
    ),
    define_food_item(
      "other_fresh_carrots",
      "Other fresh carrots",
      "Other_fresh_carrots_"
    ),
    define_food_item(
      "other_raw_root_vegetables",
      "Other raw root vegetables",
      "Other_raw_root_vegetables_",
      type_column = "Type_s__010",
      other_column = "Other__specify_004"
    ),

    define_food_item(
      "fresh_raw_peas",
      "Fresh raw peas",
      "Fresh__raw_peas___May_be_shel",
      type_column = "Type_s__011",
      other_column = "Other__specify_005",
      brand_column = "Brand_s__010",
      purchase_location_column = "Place_s__purchased006",
      establishment_column = "List_name_s__of_establishment008"
    ),

    define_food_item("broccoli", "Broccoli", "Broccoli_"),
    define_food_item(
      "cauliflower",
      "Cauliflower",
      "Cauliflower_"
    ),
    define_food_item("sprouts", "Sprouts", "Sprouts_"),

    define_food_item(
      "raw_onions",
      "Raw onions",
      "Raw_onions_",
      type_column = "Type_s__012",
      other_column = "Other__specify_006"
    ),

    define_food_item(
      "raw_green_onions",
      "Raw green onions or scallions",
      "Raw_green_onions_scallions_"
    ),

    define_food_item(
      "fresh_tomatoes",
      "Fresh tomatoes",
      "Fresh_tomatoes_",
      type_column = "Type_s__013",
      other_column = "Other__specify_007"
    ),

    define_food_item(
      "fresh_salsa_or_pico",
      "Fresh salsa or pico de gallo",
      "Salsa_or_pico_de_gallo__not_f",
      brand_column = "Brand_s__011",
      purchase_location_column = "Place_s__purchased007",
      establishment_column = "List_name_s__of_establishment009"
    ),

    define_food_item(
      "fresh_guacamole",
      "Fresh guacamole",
      "Fresh_guacamole__not_from_a_j",
      brand_column = "Brand_s__012",
      purchase_location_column = "Place_s__purchased008",
      establishment_column = "List_name_s__of_establishment010"
    )
  )

  names(items) <- vapply(
    items,
    function(item) item[["item_id"]],
    FUN.VALUE = character(1)
  )

  items
}


# =========================================================================
# Generic configuration
# =========================================================================

#' Create a partially structured input configuration
#'
#' @param format_name Human-readable source format.
#' @param event_sources Named event-source definitions.
#' @param food_items Named food-item definitions.
#'
#' @return A configuration list.
partially_structured_config <- function(
  format_name = "custom",
  event_sources = list(),
  food_items = list()
) {
  if (!is_one_string(format_name)) {
    stop(
      "`format_name` must be one nonempty character value.",
      call. = FALSE
    )
  }

  if (!is.list(event_sources)) {
    stop(
      "`event_sources` must be a list.",
      call. = FALSE
    )
  }

  if (!is.list(food_items)) {
    stop(
      "`food_items` must be a list.",
      call. = FALSE
    )
  }

  list(
    format_name = format_name,
    event_sources = event_sources,
    food_items = food_items
  )
}


mdss_exposure_config <- function() {
  partially_structured_config(
    format_name = "MDSS",
    event_sources = mdss_event_sources(),
    food_items = mdss_food_items()
  )
}


# =========================================================================
# Configuration validation against input data
# =========================================================================

event_source_columns <- function(source) {
  columns <- unlist(
    source[
      c(
        "date_column",
        "name_column",
        "food_column",
        "location_column"
      )
    ],
    use.names = FALSE
  )

  columns[
    !is.na(columns) &
      nzchar(columns)
  ]
}


food_item_columns <- function(item) {
  columns <- unlist(
    item[
      c(
        "response_column",
        "type_column",
        "other_column",
        "brand_column",
        "purchase_location_column",
        "establishment_column"
      )
    ],
    use.names = FALSE
  )

  columns[
    !is.na(columns) &
      nzchar(columns)
  ]
}


validate_exposure_config <- function(
  data,
  config,
  strict = FALSE
) {
  validate_data_frame(data)

  if (!is.list(config)) {
    stop(
      "`config` must be a partially structured configuration.",
      call. = FALSE
    )
  }

  mapped_columns <- c(
    unlist(
      lapply(
        config[["event_sources"]],
        event_source_columns
      ),
      use.names = FALSE
    ),
    unlist(
      lapply(
        config[["food_items"]],
        food_item_columns
      ),
      use.names = FALSE
    )
  )

  mapped_columns <- unique(mapped_columns)

  missing_columns <- setdiff(
    mapped_columns,
    names(data)
  )

  if (
    isTRUE(strict) &&
      length(missing_columns) > 0L
  ) {
    stop(
      paste0(
        "The input is missing mapped columns:\n  ",
        paste(
          missing_columns,
          collapse = "\n  "
        )
      ),
      call. = FALSE
    )
  }

  tibble::tibble(
    source_format = config[["format_name"]],
    mapped_column_count = length(mapped_columns),
    available_column_count = sum(
      mapped_columns %in% names(data)
    ),
    missing_column_count = length(missing_columns),
    missing_columns = list(missing_columns)
  )
}


# =========================================================================
# Safe row-value access
# =========================================================================

row_value <- function(row, column_name) {
  if (
    is.null(column_name) ||
      !column_name %in% names(row)
  ) {
    return(NA_character_)
  }

  normalize_text_value(
    row[[column_name]]
  )
}


source_reference <- function(
  column,
  parsed_value,
  source_cell_value = NULL,
  source_index = NULL,
  role = NULL
) {
  if (is_missing_text_scalar(column)) {
    return(NULL)
  }

  if (is_missing_text_scalar(parsed_value)) {
    return(NULL)
  }

  reference <- list(
    column = as.character(column),
    parsed_value = as.character(parsed_value)
  )

  # Preserve the complete original cell. For an indexed MDSS field, this
  # may be something such as:
  #
  #   [0]Taco Bell[1]Jimmy Johns
  #
  # while parsed_value is only the value associated with this event.
  if (!is_missing_text_scalar(source_cell_value)) {
    reference[["source_cell_value"]] <-
      as.character(source_cell_value)
  }

  if (
    !is.null(source_index) &&
      length(source_index) == 1L &&
      !is.na(source_index)
  ) {
    reference[["source_index"]] <-
      as.integer(source_index)
  }

  if (!is_missing_text_scalar(role)) {
    reference[["role"]] <-
      as.character(role)
  }

  reference
}

# return compact null list but also emptiness could be valid "no-exposure" data
compact_nulls <- function(x) {
  if (!is.list(x)) {
    return(x)
  }

  cleaned <- lapply(
    x,
    compact_nulls
  )

  keep <- vapply(
    cleaned,
    function(value) {
      if (is.null(value)) {
        return(FALSE)
      }

      # Preserve empty lists and vectors. In JSON, these may represent valid
      # empty collections such as no explicit events or no affirmative foods.
      if (length(value) == 0L) {
        return(TRUE)
      }

      if (
        is.character(value) &&
          length(value) == 1L &&
          is.na(value)
      ) {
        return(FALSE)
      }

      TRUE
    },
    FUN.VALUE = logical(1)
  )

  cleaned[keep]
}


# =========================================================================
# Parse explicit event records
# =========================================================================
parse_event_source_row <- function(
  row,
  source_name,
  source_definition
) {
  if (!is.data.frame(row) || nrow(row) != 1L) {
    stop(
      "`row` must be a one-row data frame.",
      call. = FALSE
    )
  }

  if (!is_one_string(source_name)) {
    stop(
      "`source_name` must be one nonempty character value.",
      call. = FALSE
    )
  }

  if (!is.list(source_definition)) {
    stop(
      "`source_definition` must be an event-source definition.",
      call. = FALSE
    )
  }

  required_definition_elements <- c(
    "event_type",
    "food_column"
  )

  missing_definition_elements <- setdiff(
    required_definition_elements,
    names(source_definition)
  )

  if (length(missing_definition_elements) > 0L) {
    stop(
      paste0(
        "Event-source definition `",
        source_name,
        "` is missing: ",
        paste(
          missing_definition_elements,
          collapse = ", "
        ),
        "."
      ),
      call. = FALSE
    )
  }

  value_columns <- c(
    date_text = source_definition[["date_column"]],
    source_name = source_definition[["name_column"]],
    food_text = source_definition[["food_column"]],
    location_text = source_definition[["location_column"]]
  )

  # c() normally drops NULL values, but explicitly filter invalid mappings
  # so custom configurations are handled safely.
  keep_columns <- !is.na(value_columns) &
    nzchar(value_columns)

  value_columns <- value_columns[
    keep_columns
  ]

  if (!"food_text" %in% names(value_columns)) {
    stop(
      paste0(
        "Event source `",
        source_name,
        "` does not define a usable food column."
      ),
      call. = FALSE
    )
  }

  # Preserve the complete original value of each source cell. Individual
  # cells may contain several indexed values.
  source_values <- lapply(
    value_columns,
    function(column_name) {
      row_value(
        row = row,
        column_name = column_name
      )
    }
  )

  aligned_records <- tryCatch(
    {
      align_indexed_fields(
        source_values
      )
    },
    error = function(error) {
      stop(
        paste0(
          "Could not align indexed values for event source `",
          source_name,
          "`.\n",
          conditionMessage(error)
        ),
        call. = FALSE
      )
    }
  )

  if (length(aligned_records) == 0L) {
    return(list())
  }

  parsed_events <- vector(
    mode = "list",
    length = length(aligned_records)
  )

  output_index <- 0L

  for (aligned_index in seq_along(aligned_records)) {
    aligned_record <-
      aligned_records[[aligned_index]]

    if (!is.list(aligned_record)) {
      stop(
        paste0(
          "Aligned record ",
          aligned_index,
          " for event source `",
          source_name,
          "` must be a list."
        ),
        call. = FALSE
      )
    }

    source_index <-
      aligned_record[["source_index"]]

    food_text <-
      aligned_record[["food_text"]]

    # A date or restaurant without a food is not sufficient for this
    # known-exposure pipeline.
    if (is_missing_text_scalar(food_text)) {
      next
    }

    date_text <-
      aligned_record[["date_text"]]

    event_source_name <-
      aligned_record[["source_name"]]

    location_text <-
      aligned_record[["location_text"]]

    source_references <- list()

    for (role in names(value_columns)) {
      source_column <-
        value_columns[[role]]

      parsed_value <-
        aligned_record[[role]]

      source_cell_value <-
        source_values[[role]]

      reference <- source_reference(
        column = source_column,
        parsed_value = parsed_value,
        source_cell_value = source_cell_value,
        source_index = source_index,
        role = role
      )

      if (!is.null(reference)) {
        source_references[[
          length(source_references) + 1L
        ]] <- reference
      }
    }

    output_index <- output_index + 1L

    parsed_events[[output_index]] <- compact_nulls(
      list(
        source_group = source_name,
        source_index = source_index,
        event_type = source_definition[["event_type"]],
        date_text = date_text,
        resolved_date = parse_source_date(
          date_text
        ),
        source_name = event_source_name,
        location_text = location_text,
        food_text = food_text,
        source_references = source_references
      )
    )
  }

  if (output_index == 0L) {
    return(list())
  }

  parsed_events[
    seq_len(output_index)
  ]
}

parse_all_event_sources <- function(
  row,
  event_sources
) {
  if (!is.list(event_sources)) {
    stop(
      "`event_sources` must be a list.",
      call. = FALSE
    )
  }

  if (length(event_sources) == 0L) {
    return(list())
  }

  if (
    is.null(names(event_sources)) ||
      anyNA(names(event_sources)) ||
      any(!nzchar(names(event_sources))) ||
      anyDuplicated(names(event_sources))
  ) {
    stop(
      paste0(
        "`event_sources` must be a named list with unique, ",
        "nonempty names."
      ),
      call. = FALSE
    )
  }

  output <- list()

  for (source_name in names(event_sources)) {
    events <- tryCatch(
      {
        parse_event_source_row(
          row = row,
          source_name = source_name,
          source_definition = event_sources[[source_name]]
        )
      },
      error = function(error) {
        stop(
          paste0(
            "Failed while parsing event source `",
            source_name,
            "`.\n",
            conditionMessage(error)
          ),
          call. = FALSE
        )
      }
    )

    if (length(events) > 0L) {
      output <- c(
        output,
        events
      )
    }
  }

  output
}

# Add "fact references ids" to correspond to source data
add_exposure_input_references <- function(record) {
  explicit_events <- record[["known_exposures"]][["explicit_events"]]

  affirmative_foods <- record[["known_exposures"]][["affirmative_food_questionnaire"]]

  if (length(explicit_events) > 0L) {
    for (index in seq_along(explicit_events)) {
      explicit_events[[index]][["input_ref"]] <-
        sprintf(
          "explicit_event_%03d",
          index
        )
    }
  }

  if (length(affirmative_foods) > 0L) {
    for (index in seq_along(affirmative_foods)) {
      affirmative_foods[[index]][["input_ref"]] <-
        sprintf(
          "affirmative_food_%03d",
          index
        )
    }
  }

  record[["known_exposures"]][["explicit_events"]] <- explicit_events

  record[["known_exposures"]][["affirmative_food_questionnaire"]] <- affirmative_foods

  record
}
# =========================================================================
# Parse known affirmative questionnaire food exposures
# =========================================================================

parse_affirmative_food_item <- function(
  row,
  item,
  yes_codes = default_yes_codes(),
  no_codes = default_no_codes(),
  unknown_codes = default_unknown_codes()
) {
  response_column <- item[["response_column"]]

  if (!response_column %in% names(row)) {
    return(NULL)
  }

  raw_response <- row_value(
    row,
    response_column
  )

  response_status <- normalize_yes_no_unknown(
    raw_response,
    yes_codes = yes_codes,
    no_codes = no_codes,
    unknown_codes = unknown_codes
  )

  # Only explicit affirmative responses are retained.
  if (!identical(response_status, "yes")) {
    return(NULL)
  }

  detail_roles <- c(
    type = "type_column",
    other_specify = "other_column",
    brand = "brand_column",
    purchase_location = "purchase_location_column",
    establishment = "establishment_column"
  )

  details <- list()
  source_refs <- list(
    list(
      role = "response",
      column = response_column,
      raw_value = raw_response
    )
  )

  for (role in names(detail_roles)) {
    mapping_name <- detail_roles[[role]]
    column_name <- item[[mapping_name]]

    if (
      is.null(column_name) ||
        !column_name %in% names(row)
    ) {
      next
    }

    raw_value <- row_value(
      row,
      column_name
    )

    if (is.na(raw_value)) {
      next
    }

    parsed_values <- parse_multivalue_cell(
      raw_value
    )

    details[[role]] <- if (length(parsed_values) <= 1L) {
      if (length(parsed_values) == 0L) {
        raw_value
      } else {
        unname(parsed_values[[1]])
      }
    } else {
      unname(parsed_values)
    }

    source_refs[[length(source_refs) + 1L]] <-
      list(
        role = role,
        column = column_name,
        raw_value = raw_value
      )
  }

  compact_nulls(
    list(
      item_id = item[["item_id"]],
      food_label = item[["food_label"]],
      response = "yes",
      details = details,
      source_references = source_refs
    )
  )
}


parse_affirmative_food_items <- function(
  row,
  food_items,
  yes_codes = default_yes_codes(),
  no_codes = default_no_codes(),
  unknown_codes = default_unknown_codes()
) {
  output <- list()

  for (item_name in names(food_items)) {
    parsed <- parse_affirmative_food_item(
      row = row,
      item = food_items[[item_name]],
      yes_codes = yes_codes,
      no_codes = no_codes,
      unknown_codes = unknown_codes
    )

    if (!is.null(parsed)) {
      output[[length(output) + 1L]] <- parsed
    }
  }

  output
}


# =========================================================================
# Record-level JSON-ready object
# =========================================================================

build_exposure_record <- function(
  row,
  record_id,
  config,
  onset_date_column = NULL,
  interview_date_column = NULL,
  yes_codes = default_yes_codes(),
  no_codes = default_no_codes(),
  unknown_codes = default_unknown_codes()
) {
  record_id <- normalize_text_value(record_id)

  if (is.na(record_id)) {
    stop(
      "A record ID is missing or empty.",
      call. = FALSE
    )
  }

  onset_date_text <- row_value(
    row,
    onset_date_column
  )

  interview_date_text <- row_value(
    row,
    interview_date_column
  )

  explicit_events <- parse_all_event_sources(
    row = row,
    event_sources = config[["event_sources"]]
  )

  affirmative_foods <- parse_affirmative_food_items(
    row = row,
    food_items = config[["food_items"]],
    yes_codes = yes_codes,
    no_codes = no_codes,
    unknown_codes = unknown_codes
  )

  compact_nulls(
    list(
      record_id = record_id,
      input_format = config[["format_name"]],

      date_context = compact_nulls(
        list(
          onset_date_text = onset_date_text,
          onset_date = parse_source_date(
            onset_date_text
          ),
          interview_date_text = interview_date_text,
          interview_date = parse_source_date(
            interview_date_text
          )
        )
      ),

      known_exposures = list(
        explicit_events = explicit_events,
        affirmative_food_questionnaire = affirmative_foods
      ),

      deterministic_summary = list(
        explicit_event_count = length(explicit_events),
        affirmative_food_count = length(affirmative_foods),
        has_known_exposure = length(explicit_events) > 0L ||
          length(affirmative_foods) > 0L
      )
    )
  )
}


# =========================================================================
# Tidy-selection helpers
# =========================================================================

resolve_one_column <- function(
  data,
  column_quo,
  argument_name,
  optional = FALSE
) {
  if (rlang::quo_is_null(column_quo)) {
    if (isTRUE(optional)) {
      return(NULL)
    }

    stop(
      "`",
      argument_name,
      "` must identify one column.",
      call. = FALSE
    )
  }

  selected <- tidyselect::eval_select(
    expr = column_quo,
    data = data,
    error_call = rlang::caller_env()
  )

  if (length(selected) != 1L) {
    stop(
      "`",
      argument_name,
      "` must identify exactly one column.",
      call. = FALSE
    )
  }

  names(selected)[[1]]
}


# =========================================================================
# Main wrapper
# =========================================================================

#' Build deterministic JSON from partially structured food-exposure data
#'
#' Creates one nested record per input row. Only explicit event records with
#' populated food text and questionnaire items explicitly coded as yes are
#' retained.
#'
#' Column arguments use tidyverse-style selection.
#'
#' @param data A data frame containing one source record per row.
#' @param id Column uniquely identifying each source record.
#' @param onset_date Optional illness-onset date column.
#' @param interview_date Optional interview-date column.
#' @param format Input format. Currently `"mdss"` or `"custom"`.
#' @param config Custom configuration when `format = "custom"`. For MDSS,
#'   the default is `mdss_exposure_config()`.
#' @param output One of `"json"`, `"list"`, or `"tibble"`.
#' @param path Optional output JSON path. Used only when `output = "json"`.
#' @param pretty Whether JSON should be indented.
#' @param drop_records_without_exposure Whether records with no known
#'   affirmative exposure should be omitted.
#' @param strict_columns Whether all mapped columns must exist.
#'
#' @return JSON text, a list of nested records, or a tibble containing a
#'   list-column named `exposure_record`.
build_exposure_json <- function(
  data,
  id,
  onset_date = NULL,
  interview_date = NULL,
  format = c("mdss", "custom"),
  config = NULL,
  output = c("json", "list", "tibble"),
  path = NULL,
  pretty = TRUE,
  drop_records_without_exposure = FALSE,
  strict_columns = FALSE
) {
  validate_data_frame(data)

  format <- match.arg(format)
  output <- match.arg(output)

  id_quo <- rlang::enquo(id)
  onset_date_quo <- rlang::enquo(onset_date)
  interview_date_quo <- rlang::enquo(
    interview_date
  )

  id_column <- resolve_one_column(
    data,
    id_quo,
    argument_name = "id",
    optional = FALSE
  )

  onset_date_column <- resolve_one_column(
    data,
    onset_date_quo,
    argument_name = "onset_date",
    optional = TRUE
  )

  interview_date_column <- resolve_one_column(
    data,
    interview_date_quo,
    argument_name = "interview_date",
    optional = TRUE
  )

  if (is.null(config)) {
    config <- switch(
      format,
      mdss = mdss_exposure_config(),
      custom = stop(
        paste0(
          "`config` must be supplied when ",
          "`format = \"custom\"`."
        ),
        call. = FALSE
      )
    )
  }

  validation <- validate_exposure_config(
    data = data,
    config = config,
    strict = strict_columns
  )

  record_ids <- as.character(
    data[[id_column]]
  )

  if (
    anyNA(record_ids) ||
      any(!nzchar(trimws(record_ids)))
  ) {
    stop(
      "The selected ID column contains missing or empty values.",
      call. = FALSE
    )
  }

  if (anyDuplicated(record_ids)) {
    stop(
      paste0(
        "The selected ID column must uniquely identify source rows. ",
        "Duplicate values were found."
      ),
      call. = FALSE
    )
  }

  records <- vector(
    mode = "list",
    length = nrow(data)
  )

  for (row_index in seq_len(nrow(data))) {
    row <- data[
      row_index,
      ,
      drop = FALSE
    ]

    current_record_id <- record_ids[[row_index]]

    records[[row_index]] <- tryCatch(
      {
        build_exposure_record(
          row = row,
          record_id = current_record_id,
          config = config,
          onset_date_column = onset_date_column,
          interview_date_column = interview_date_column
        )
      },
      error = function(error) {
        stop(
          paste0(
            "Failed to process source row ",
            row_index,
            " with record ID `",
            current_record_id,
            "`.\n",
            conditionMessage(error)
          ),
          call. = FALSE
        )
      }
    )
  }

  if (isTRUE(drop_records_without_exposure)) {
    keep <- vapply(
      records,
      function(record) {
        isTRUE(
          record[["deterministic_summary"]][["has_known_exposure"]]
        )
      },
      FUN.VALUE = logical(1)
    )

    records <- records[keep]
  }

  if (identical(output, "list")) {
    attr(records, "configuration_validation") <-
      validation

    return(records)
  }

  if (identical(output, "tibble")) {
    return(
      tibble::tibble(
        record_id = vapply(
          records,
          function(record) {
            record[["record_id"]]
          },
          FUN.VALUE = character(1)
        ),
        exposure_record = records
      )
    )
  }

  json <- jsonlite::toJSON(
    records,
    auto_unbox = TRUE,
    pretty = pretty,
    null = "null",
    na = "null",
    dataframe = "rows",
    POSIXt = "ISO8601"
  )

  if (!is.null(path)) {
    if (!is_one_string(path)) {
      stop(
        "`path` must be NULL or one nonempty character value.",
        call. = FALSE
      )
    }

    output_directory <- dirname(path)

    if (
      !identical(output_directory, ".") &&
        !dir.exists(output_directory)
    ) {
      dir.create(
        output_directory,
        recursive = TRUE,
        showWarnings = FALSE
      )
    }

    writeLines(
      json,
      con = path,
      useBytes = TRUE
    )
  }

  json
}
