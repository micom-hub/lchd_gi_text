# R/MDSS/mdss_wrappers.R
#
# User-friendly MDSS preprocessing wrappers for reconciliation pipeline.

#' Prepare MDSS food-exposure records
#'
#' @param data MDSS-compatible data frame.
#' @param id Unique record ID column.
#' @param onset_date Optional onset-date column.
#' @param interview_date Optional interview-date column.
#' @param config MDSS source configuration.
#' @param drop_without_exposure Whether to remove records without known
#'   affirmative exposure information.
#' @param strict_columns Whether every configured column must exist.
#'
#' @return A tibble containing audit records and LLM payloads.
prepare_mdss_exposures <- function(
  data,
  id,
  onset_date = NULL,
  interview_date = NULL,
  config = mdss_exposure_config(),
  drop_without_exposure = FALSE,
  strict_columns = FALSE
) {
  id_quo <- rlang::enquo(id)
  onset_quo <- rlang::enquo(onset_date)
  interview_quo <- rlang::enquo(
    interview_date
  )

  exposure_data <- build_exposure_json(
    data = data,
    id = !!id_quo,
    onset_date = !!onset_quo,
    interview_date = !!interview_quo,
    format = "custom",
    config = config,
    output = "tibble",
    drop_records_without_exposure = drop_without_exposure,
    strict_columns = strict_columns
  )

  prepared <- prepare_exposure_payloads(
    exposure_data
  )

  class(prepared) <- c(
    "prepared_exposure_data",
    class(prepared)
  )

  prepared
}


print.prepared_exposure_data <- function(x, ...) {
  cat("Prepared partially structured exposure data\n")
  cat("===========================================\n")
  cat("Records:              ", nrow(x), "\n", sep = "")
  cat(
    "Explicit events:      ",
    sum(x$explicit_event_count),
    "\n",
    sep = ""
  )
  cat(
    "Affirmative foods:    ",
    sum(x$affirmative_food_count),
    "\n",
    sep = ""
  )

  NextMethod("print")
}
