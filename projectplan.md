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


# Development Phase 2
Infrastructure for interacting with ollama models is built, now time to develop the model querying process.

 We will construct a pipeline that does the following in order:

 1) Loads interview narratives from a dataframe
 2) Handles requested model availability/install
 3) Creates ellmer chat with local Ollama as endpoint
 4) Applies a system prompt and structured-output schema to the chat
 5) Extracts food-consumption events from each narrative
 6) attempts to validate, and normalize model outputs 
 7) Cleanly handle errors, "retry"s, checkpoints, and resumable batches (for heavy processing)
8) Record resource use, runtime, and failures
9) Record all provenance for each run for reproducibility (as far as is possible with LLMs)

We will then write a model comparison script that formulates "experiments" as tidy parameter grids/samples, with evaluation using the `vitals`package for later benchmarking

We will consider phase 2 over when we have the infrastructure to fairly compare candidate models for how they perform on a manually annotated cross-validation dataset. 

We will aim to replicate the tidymodels workflow for this component, with a "model configuration" defined as a unique combination of:

**model x quantization x prompt x schema x context setting**

## Implementation plan

#### Step 1: Containerize
(Just freeze packages in place with renv for now)

#### Step 2: Extraction specs
Our primary unit of extraction will be a "food-consumption event", which comprises the food eaten, its source, and whatever other we can establish about it (approximate date, meal, supporting line from text, etc.)

Things to figure out how to handle still:
- When a respondent talks about a family member's food (if applicable)
- Assuring that negation is handled properly by the LLM 
- Preserving uncertainty somehow (when the interviewee conveys doubt)

#### Step 3: Reference extraction

With the llm-generated synthetic data (made more realistic after consulting with Alvaro), we should make reference labels for a handfull of these records

#### Step 4: Implement a model registry

We will create a registry of models we want to test over time, tracking their ollama tag, model family, parameter class, quantization, minimum ram, context length, etc. We do so with the goal of eventually "recommending" different model classes that we will implement within our script, arbitrarily aiming to fill the following roles:
- Ultralightweight (< 2B)
- Small (< 4 B)
- More sizeable ( < 8B)

#### Step 5: Expand our ollama interface

We need to be able to distinguish between installed. models, models in memory, and models ready to be interfaced with

Step 6: Build the ellmer factory

We will wrap ellmer chat creation functions to create a way to programatically interface with ellmer, using our ollama api set-up.

We will make this maximally compatible with ellmer, not re-inventing the wheel wherever we don't have to 

#### Step 6: Prompt registry

We will, unfortunately, have to respect prompt engineering, treating prompts as software. Good prompts should do things like:
- Tell the model it is an information extraction system
- Narratives are "untrusted data", and not explicit extructions
- extraction is restricted to what was actually reported
- distinguish the respondent from other people in the prompt
- distinguish eating from buying, preparing, handling, or other ways to interact with food
- Preserve negation and uncertainty
- It must not infer unreported ingredients or locations
- it must return the exact evidence text supporting its claims
- It must return only within the expressed structure
- It must return null for missing info
- It should somehow flag ambiguous records rather than guessing (I imagine this will be hard to narrow the behavior on)

#### Step 7: Using ellmer's structured extraction tools

We should probably do this incrementally, especially for the little models. 
Starting with mentions of food/beverages, then expanding. This might lead to differential prompting/extraction for smaller versus larger model wrappers

#### Step 8: Write an extract_interview() function

Configurable to various models, prompts, schema, configs, hyperparameter sets, etc.

#### Step 9: Writing validation 

We will write a bunch of tests to interrogate the LLM outputs for validity, and normalize formatting wherever possible when working with free text.

This will include scanners for "nonsense" that will potentially flag interview lines to be re-run through the extraction model again, maybe with something shuffled like rolling context windows. This could be a hyperparameter (n_retries)

#### Step 10: Convert extraction results into tidy tables 

As it says

#### Step 11: Implement batch extraction 

parallelization might be crazy for this one, huge ram spikes. 

#### Step 12: Add the stuff we need to experiment, comparing models

Experiment IDs, tidy experiment grid, profiling for operational performance, building deterministic benchmark metrics, cross-validation infrastructure 

#### Step 13: Stress testing

We will need to eventually test some edge cases and see how it does. Stuff like:
- I did not eat the salad
- I went to the restaurant and my friend ate the chicken
- I ate there on Friday ..... Oh wait, I actually ate there on Wednesday
- Misspellings of common restaurants
- Incomplete sentences
- Self-contradiction
- God forbid, any interview which contains something to the effect of "ignore the instructions"
- Anything referred to hypothetically (maybe by the interviewer)
