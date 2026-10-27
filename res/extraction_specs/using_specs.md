# Description of how to build extraction specifications

We bundle information in 3 layers through our extractions, fields, components, and scopes.


## Extraction units - Fields
We configure our LLMs to extract structured fields, where each desired output field is configured with:
- A name (human readable)
- A scope (does it pertain to the interview, event, or food)
- A type (structured variable type for ellmer)
- Description (a brief, descriptive prompt for the LLM to know what it is extracting)
- optionally, allowed values (for factor answers)

Specifications are constructed using the functions in ./R/extraction/extraction_spec.R

A field is defined like this:
```{r}
define_extraction_field(
  name = "meal_type",
  scope = "event",
  type = "enum",
  description = "Meal or eating occasion.",
  allowed_values = c(
    "breakfast",
    "lunch",
    "dinner",
    "unknown"
  )
)
```

And it becomes a named list in R. Later, an ellmer helper function inspects these lists and interacts with ellmer type constructors

## Information units - Components
Components are groups of fields that should generally travel together, and can be requested as part of an extraction specification by a user

Something like:

```{r}
# Build a component for info on source
source = define_extraction_component(
  name = "source",
  fields = list(
    source_name = ...,
    source_type = ...,
    source_text = ...
  )
)
```

## Interpretation units - Scopes
Every field is interpreted in one of three scopes_

1) Interview - information that corresponds to each interview as a complete observation
2) Event - information that corresponds to an instance of a food-event within an interview
3) food - information that corresponds to an occurrance of a food within a food-event

This later allows for construction of nested objects with a manifest of interviews and their nested event manifest, which itself contains a nested food manifest (think tidymodels)


# Some functions to interact with

We configure a default extraction registry as defined in extraction_v1.md, with `extraction_component_registry()`
```{r}

# registry as a named list for further processing
registry <- extraction_component_registry()


#view as a tidy table - human readable
available_extraction_components(registry)
```