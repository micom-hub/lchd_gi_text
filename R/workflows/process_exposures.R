# R/workflows/process_exposures.R
#
# Start-to-finish workflows for partially-structured data, (right now just MDSS)

#' Reconcile prepared exposure records
#'
#' @param prepared A tibble returned by `prepare_mdss_exposures()` or an
#'   equivalent source adapter.
#' @param model Exact installed Ollama model tag.
#' @param ollama Local Ollama configuration.
#' @param max_attempts Maximum attempts per record.
#' @param checkpoint_path Optional checkpoint path.
#' @param checkpoint_every Number of records between checkpoints.
#' @param progress Whether to print progress.
#'
#' @return A `food_exposure_result`.
reconcile_prepared_exposures <- function(
  prepared,
  model,
  ollama = ollama_config(),
  max_attempts = 2L,
  checkpoint_path = NULL,
  checkpoint_every = 5L,
  progress = interactive()
) {
  required_columns <- c(
    "record_id",
    "audit_record",
    "llm_payload"
  )

  missing_columns <- setdiff(
    required_columns,
    names(prepared)
  )

  if (length(missing_columns) > 0L) {
    stop(
      paste0(
        "`prepared` is missing: ",
        paste(missing_columns, collapse = ", "),
        "."
      ),
      call. = FALSE
    )
  }

  batch <- reconcile_exposure_records(
    data = prepared,
    record = llm_payload,
    model = model,
    ollama = ollama,
    max_attempts = max_attempts,
    checkpoint_path = checkpoint_path,
    checkpoint_every = checkpoint_every,
    progress = progress
  )

  tidy_reconciliation_batch(batch)
}


#' Process MDSS food-exposure data
#'
#' This is the main convenience wrapper for MDSS users.
#'
#' @param data MDSS-compatible data frame.
#' @param id Unique record ID column.
#' @param onset_date Optional onset-date column.
#' @param interview_date Optional interview-date column.
#' @param model Exact installed Ollama model tag.
#' @param mdss_config MDSS source configuration.
#' @param ollama Local Ollama configuration.
#' @param drop_without_exposure Whether to skip records without known
#'   exposures.
#' @param strict_columns Whether all configured MDSS columns must exist.
#' @param max_attempts Maximum model attempts per record.
#' @param checkpoint_path Optional checkpoint path.
#' @param progress Whether to print progress.
#'
#' @return A `food_exposure_result`.
process_mdss_exposures <- function(
  data,
  id,
  onset_date = NULL,
  interview_date = NULL,
  model,
  mdss_config = mdss_exposure_config(),
  ollama = ollama_config(),
  drop_without_exposure = TRUE,
  strict_columns = FALSE,
  max_attempts = 2L,
  checkpoint_path = NULL,
  progress = interactive()
) {
  id_quo <- rlang::enquo(id)
  onset_quo <- rlang::enquo(onset_date)
  interview_quo <- rlang::enquo(
    interview_date
  )

  prepared <- prepare_mdss_exposures(
    data = data,
    id = !!id_quo,
    onset_date = !!onset_quo,
    interview_date = !!interview_quo,
    config = mdss_config,
    drop_without_exposure = drop_without_exposure,
    strict_columns = strict_columns
  )

  reconcile_prepared_exposures(
    prepared = prepared,
    model = model,
    ollama = ollama,
    max_attempts = max_attempts,
    checkpoint_path = checkpoint_path,
    progress = progress
  )
}


#' Process custom partially structured exposure data
#'
#' @param data Input data frame.
#' @param id Unique record ID column.
#' @param onset_date Optional onset-date column.
#' @param interview_date Optional interview-date column.
#' @param source_config Configuration made with
#'   `partially_structured_config()`.
#' @param model Exact installed Ollama model tag.
#' @param ollama Local Ollama configuration.
#' @param drop_without_exposure Whether to skip records without known
#'   exposures.
#' @param strict_columns Whether all mapped columns must exist.
#' @param max_attempts Maximum attempts per record.
#' @param checkpoint_path Optional checkpoint path.
#' @param progress Whether to print progress.
#'
#' @return A `food_exposure_result`.
process_partially_structured_exposures <- function(
  data,
  id,
  onset_date = NULL,
  interview_date = NULL,
  source_config,
  model,
  ollama = ollama_config(),
  drop_without_exposure = TRUE,
  strict_columns = FALSE,
  max_attempts = 2L,
  checkpoint_path = NULL,
  progress = interactive()
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
    config = source_config,
    output = "tibble",
    drop_records_without_exposure = drop_without_exposure,
    strict_columns = strict_columns
  )

  prepared <- prepare_exposure_payloads(
    exposure_data
  )

  reconcile_prepared_exposures(
    prepared = prepared,
    model = model,
    ollama = ollama,
    max_attempts = max_attempts,
    checkpoint_path = checkpoint_path,
    progress = progress
  )
}
