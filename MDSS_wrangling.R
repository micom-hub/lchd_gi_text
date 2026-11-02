library(tidyverse)
library(janitor)

path_to_cyclo <- '/Users/cameron/Library/CloudStorage/Dropbox-UniversityofMichigan/SPH-MICOM/PROJECTS/MISUPPORT/Livingston County/20261027_livingston_cyclo.csv'

raw <- read_csv(path_to_cyclo)

# Create stable keys from the data
interview_base <- raw %>%
  mutate(
    case_id = coalesce(
      na_if(as.character(InvestigationID), ""),
      na_if(as.character(Patient_ID), ""),
      na_if(as.character(NETSSID), ""),
      paste0("row_", row_number())
    ),
    interview_id = paste0(case_id, "_", row_number())
  )

suffix_pattern <- "(\\d{3})$"

column_dictionary <- tibble(
  column_position = seq_along(raw),
  raw_name = names(raw),
  data_type = map_chr(raw, ~ paste(class(.x), collapse = "/")),
  n_nonmissing = map_int(
    raw,
    ~ sum(!is.na(.x) & trimws(as.character(.x)) != "")
  ),
  n_unique_nonmissing = map_int(
    raw,
    ~ n_distinct(.x[!is.na(.x) & trimws(as.character(.x)) != ""])
  ),
  example_values = map_chr(
    raw,
    ~ .x %>%
      as.character() %>%
      str_squish() %>%
      discard(~ is.na(.x) || .x == "") %>%
      unique() %>%
      head(5) %>%
      str_c(collapse = " | ")
  )
) %>%
  mutate(
    export_suffix = str_extract(raw_name, suffix_pattern),
    base_name = str_remove(raw_name, suffix_pattern)
  )

column_dictionary %>%
  select(
    column_position,
    raw_name,
    base_name,
    export_suffix,
    data_type,
    n_nonmissing,
    n_unique_nonmissing,
    example_values
  ) %>%
  print(n = Inf)
