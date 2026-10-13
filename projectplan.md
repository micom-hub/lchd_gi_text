# projectplan.md


## Project Overview:

Writing an R suite (eventually package) that will use Ollama and Ellmer to manage and prompt an entirely local LLM that takes narrative free-text data from a foodborne illness investigation interview, and structures it into insights that might prove valuable to the outbreak investigation.

Some considerations - This must be local and secure for PHI - This package will need to be run by LHDs, meaning friendly to interface with and lightweight models (with options for heavier ones) - The user will have to install OLLAMA from the web, but shouldn't have to interface with their terminal after that fact - Once text extraction is implemented, some complimentary features can ship with it

## Generalized Architecture:

The user will have interview narrative data, presumably with metadata attached. Our package will have code to:
- Pre-process and segment narrative data
- Prepare, pull, and instantiate a local Ollama model
- Prompt the local model with structured extraction (ellmer)
- Some validation and repair functions in R
- Normalization of output data as reasonable (food/place/date/other...)
- Possibly some built in common analyses, or some uncertainty metrics for the dataset
- Export 

### Additional considerations

R can detect, configure, start, and query ollama, but installing it **WILL LIKELY REQUIRE IT PERMS**

For typical work laptops, we should aim for 1B-4B parameter models with 4-bit quantization


# Task 1: Define extraction 

We must define what the LLM will extract, which depends on the general format of the input

**A few outputs to consider:**
- Event_id (for every event recorded)
- Food as stated
- Standardized food categories
- Establishment or location name
- Location type (restaurant, grocery store, home, event, school, etc.)
- Any relevant location info provided (street, city, other)
- Date or date range
- Approximate meal time
- Negation flag (did the user say "I *didn't* eat this")
- Recall certainty (categorical/subjective)
- Evidence text (a chunk lifted, unmodified, from the narrative)
- needs_review (t/f)


# Task 2: Technical Architecture

There are a few layers we will want to include:

### Env / Install layer

This will help the user through installing and handling models via ollama, this could include example functions like:

| Example function | Intended purpose |
| -----------------| ---------------- |
| ollama_status | check if ollama is installed |
| ollama_install_instructions | print some text for how to install (also in readme) |
| model_start | start up a model |
| model_stop | stop a model |
| model_list | list all available models |
| model_pull | install a model from ollama |
| model_remove | remove an installed model |
| system_check | something that checks what is available and prints a big diagnostic |

The function should maintain a model registry of the models we are "supporting" use of, with a readable name, ollama correspondence tag, model family/version (brief about to instill confidence), parameter size, expected RAM range, any benchmark data we end up collecting, and **Validation for multilingual support**

### Extraction layer

Here our interface will use ellmer to talk to explicitly configured Ollama endpoint

| Example function | Intended purpose |
| -----------------| ---------------- |
| extract_exposures | kinda self explanatory for these |
| extract_foods | |
| extract_locations | |
| extract_dates | |
| extract_batch | |

Extractions should preserve
- corresponding record
- model ID, ollama version, package version, prompt used
- extraction schema
- processing timestamp
- model params (as feasible)
- any validation warnings
- set up a binary for human review/modification of result

### Validation + Normalization

We shouldn't rely on llms for all of the output, and should have deterministic R checks that look over model outputs. Something like:
| Example function | Intended purpose |
| -----------------| ---------------- |
| validate_extraction | Run a bunch of checks, driver function type beat | 
| normalize_food | Somehow grab generalized foodgroups |
| normalize_location | Somehow handle locations, especially if its like "Ann Arbor Dunkin" with multiple possibilities |
| resolve_relative_dates | Figure stuff out like "last friday", etc. |
| duplicate_exposure | Somehow determine if this exposure is just a replicate |
| flag_for_review | if some checks fail, flag it for manual review (use sparingly) |

### Analytic stuff

This might be completely useless to EPIs, and they might find it more valuable to just do their own analyses. However, some basic ones could be useful for validating extractions, and at least useful to us in the dev process

Some stuff like: 
- summarizing food mentions (name / normalized)
- summarizing establishments / locations
- comparing cases (take two interviews or rows)
- find common exposures (between individuals, df subset, etc.)
- export_line_list

## Output structuring

Look into how ellmer's structured data api, but basically for each model response we will want to:
- confirm that it is a valid structure (likely JSON)
- check required fields present
- reject unexpected fields for schema, (maybe queue for re-running once or twice)
- verify presented "evidence text" is present in the narrative
- check that extracted dates are relevant in relation to interview / exposure
- Check positive exposures not extracted from statements that are negated
- Identify any conflicting entries (perhaps a negated and non-negated are put back-to-back)
- Apply controls as relevant

## Model Selection process

We will aim to pare down the OLLAMA model library into ~3ish models that we can implement, with a default "recommended" model (2-4b), then a very lightweight option for old laptops or speed, and a higher accuracy, slightly heavier model. We will benchmark them against eachother by (some metric, maybe just human review)
- For optics, we will aim to stick to Llama, Gemma, Phi families, but this isn't a hard requirement
- Note that eventually we should ship a multi-lingual model

We will need to do some tidymodel benchmarking for model sizes and quantization

**Context length**
As context settings grow for llms, memory consumption will grow quickly. There are a few ways we can handle this:
- Measure distributions of narrative lengths
- Use smallest possible context window that covers all records (or almost all...)
- Segment long interviews logically (question, response, exposure period (?))
- Chunk narratives and preserve limited overlap between them

We will probably want semantic segmentation instead of arbitrary rolling token windows, on the off chance that we cut off something like:
"... My husband ate chicken fingers, but I did not" // " eat chicken fingers..."


### Building a data annotation set 
In order to benchmark models, we need to have a sense for what they "should be finding" when we run them. To do this, we will take a subset of narrative interview data and manually tag it with what we hope the LLM will extract. This might be readily available from past investigations.

We should have two independent annotators and compare any disagreements for validity

Split data for cross-validation, with a held-out testing set

### Possible metrics for models

**Extraction metrics**
For the mention of establishments and foods (percision, recall, F1), negation sens/specificity, how often the evidence is good/true (inverse hallucination rate), rate of producing invalid structured-output

**Operational**
- Median / 95%ile for time-per-interview (or per word)
- tokens processed per second
- Peak / Avg ram consumed
- model load time
-
Ensure we're checking these on CPU only as possible

**Some model "risk measures" that people will want to know**
- Write a way to flag false positive establishment extraction, whenever negations are wrong, when an exposure is assigned to the wrong person, when dates or addresses are fabricated, etc. 

We will use this review pipeline both for comparing models, and for comparing prompt performance


# Development Guidelines

As a note, while we aren't doing the whole devtools and roxygen shabang yet, this project could eventually be useful as a shippable package, so for that reason, each file should contain relateed function definitions, nothing should run on file sourcing, no reliance on global variables, etc. 