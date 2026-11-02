# JSON pipeline explained

The MDSS structured data contains tons and tons of columns for food group exposures that, for our purposes, we will consider partially-structured. This will prove a bit of a challenge, as different outbreak investigations might have different food group exposure columns, so we will try to keep it general. These are also very sparse. The current idea is:

1) Take the MDSS file, look for positive exposures (explicit Yes statements) 
2) For yes statements, create a JSON with the food consumed, source text, etc. 
3) Somehow jam this JSON into an llm in an effective way

This pipeline aims to remove irrelevant, missing, negative, and id fields, then translate ssource-specific cols into a stable structure, and preserve enough of the original source to be able to validate LLM produced events

MDSS has silly column names like:
Food_Consumed000, Brand_s__005, Place_s__purchased001
We want to feed this to the LLM as something like:
food_text, source_name, purchase_location, ...

The json produced by `build_exposure_json()`(from partially_structured_json.R) looks like this:

```{text}

Call the function:

mdss_json <- build_exposure_json(
  data = df,
  id = InvestigationID,
  onset_date = Onset_Date,
  interview_date = Date_of_interview,
  format = "mdss",
  output = "json",
  pretty = T
)

Each input row (representing an interview), becomes a nested structure like this:

{
  "record_id": "EXAMPLE-001",
  "input_format": "MDSS",
  "date_context": {
    "onset_date_text": "07/10/2026",
    "onset_date": "2026-07-10",
    "interview_date_text": "08/07/2026",
    "interview_date": "2026-08-07"
  },
  "known_exposures": {
    "explicit_events": [],
    "affirmative_food_questionnaire": []
  },
  "deterministic_summary": {
    "explicit_event_count": 0,
    "affirmative_food_count": 0,
    "has_known_exposure": false
  }
}
```

The function argument id becomes "record_id"
Input format is the explicit text input 

**date_context** gives the date of the interview, and the symptom onset date (if available) - NOT EXPOSURE DATES
- These are used to parse any kind of statement like "within two weeks of onset", etc. 
- Potentially, for unknown dates not provided in interview, we could input a date interval preceding onset

Food info is stored in two arrays: explicit events and affirmative_food_questionnaire

## **known_exposures**
- explicit_events
- affirmative_food_questionnaire

**explicit_events**
Explicit events are derived from the set of source fields describing a food event (restaurant meal, food purchase, or private group event)
In MDSS these are provided in list-column looking cols where looks vaguely like: [0]Taco Bell[1]Panera Bread[2]...etc
These are then further elaborated in individual columns that correspond with one another by number
```{text}
{
  "source_group": "restaurant_or_other_event",
  "source_index": 0,
  "event_type": "food_consumption",
  "date_text": "07/04/2026",
  "resolved_date": "2026-07-04",
  "source_name": "Example Restaurant",
  "location_text": "Example City",
  "food_text": "chicken tacos with lettuce and cilantro",
  "source_references": [
    {
      "column": "Date000",
      "parsed_value": "07/04/2026",
      "source_index": 0,
      "role": "date_text"
    },
    {
      "column": "Name000",
      "parsed_value": "Example Restaurant",
      "source_index": 0,
      "role": "source_name"
    },
    {
      "column": "Food_Consumed",
      "parsed_value": "chicken tacos with lettuce and cilantro",
      "source_index": 0,
      "role": "food_text"
    }
  ]
}
```

Fields:
source_group - one of purchased_food, restaurant_or_other_event, private_group_event
source_index - preserves the bracketed index value from MDSS 
event_type - food_consumption, food_purchase, private_group_event 
date_text / resolved_date - provided date / parsed date in standard format
source_name - name of organization, restaurant, store, event, or source name
location_text - location entered, could be a street address, city, restaurant, household location, event location, etc. 
food_text - source's event-level food description, could describe one food, several foods, meal, etc., and notes from interviewer
source_references - provenance records that provide the source column from which data was partially parsed

**affirmative_food_questionnaire**
- This section contains only questionnaire food items from the MDSS sheet (for example, with cyclo investigation sheet there are lots of questions about fresh produce, with a column like: "fresh_cilantro_01", with responses (No/Yes/Unk))

These jsons look like:
```{text}
{
  "item_id": "fresh_cilantro",
  "food_label": "Fresh cilantro",
  "response": "yes",
  "details": {
    "type": "typical",
    "brand": "Example Brand",
    "purchase_location": "Example Store",
    "establishment": "Example Restaurant"
  },
  "source_references": [
    {
      "role": "response",
      "column": "Fresh_cilantro_",
      "raw_value": "Y"
    }
  ]
}
```

fields:
item_id - stable identifier that corresponds with what the column is extracting - machine readable
food_label - prettier human readable version of item_id
response - right now, we are only tracking "yes" responses, so that we have explicit hits from interviews in the json
details - contains additional values relating to the food event (derived from questionnaire), including brand, location, establishment, etc.
source_reference - provenance data to correspond the entry back to the MDSS data structure

Note that this extraction is slightly limited, but allows for parallel use of the MDSS binary columns with the less structured food event columns, these are better used for simple stuff like attack rates of food consumption, but are limited on their info of dates, locations, etc. 

## **deterministic_summary**

This section is generated to and intended to be used for diagnostics and double checking LLM results. 
It contains the event count per interview, the affirmative food counts from the questionnaire, and "has_known_exposure" for filtering purposes

# Source column interpretation

Because the columns often have silly names and formats, the code looks at an mdss_exposure_config. Right now this corresponds with the MDSS cyclospora investigation sheet, but as we have more data, we will look to make it more openly compatible, maybe eventually allowing for custom column configs.

The following bits need to be observed and reproduced for compatibility with more survey sources:
- mdss_event_sources
- define_food_item (for each food)
- mdss_exposure_config

# TLDR
1) use preset mdss_exposure_config() (eventually expand compatibility) to define how the spreadsheet becomes a JSON
- partially_structured_config() is the general interface for this


# Todo
- Give each "fact" a reference ID to let the model cite them without relying on column names
