# MDSS rules v2 — frozen development experiment

## Configuration

- Model: `llama3.2:3b` (local Ollama).
- Prompt: `mdss_rules_v2`, defined in `evaluate_relationships.R`.
- Schema: `minimal_relationship_v1` (food text and respondent relationship).
- Temperature: 0; seed: 123; maximum output tokens: 512.
- Dataset: 16 synthetic development fixtures, version 0.1.0; 26 reference foods.
- Source: evaluation summary and error tables supplied by Alvaro in this conversation.
- No new model calls were made to create this record.

## Results

| Metric                                 | baseline_v1 | mdss_context_v1 | mdss_rules_v2 |
| -------------------------------------- | ----------- | --------------- | ------------- |
| Records                                | 16          | 16              | 16            |
| Execution failures                     | 0           | 0               | 0             |
| Mention precision                      | 0.9230769   | 0.8846154       | 0.9285714     |
| Mention recall                         | 0.9230769   | 0.8846154       | 1.0000000     |
| Mention F1                             | 0.9230769   | 0.8846154       | 0.9629630     |
| Relationship accuracy on matched foods | 0.7083333   | 0.6956522       | 0.7307692     |
| Correct-pair recall                    | 0.6538462   | 0.6153846       | 0.7307692     |
| Correct-pair F1                        | 0.6538462   | 0.6153846       | 0.7037037     |
| Exact-record rate                      | 0.3750      | 0.3125          | 0.5000        |
| Median seconds per record              | 2.777439    | 3.221866        | 3.576253      |

V2 recovered all 26 reference foods, generated 28 predictions, classified 19 matched relationships correctly, and produced 8 completely correct records out of 16.

## Remaining v2 errors

| Test        | Food     | Expected relationship   | Predicted relationship | Error              |
| ----------- | -------- | ----------------------- | ---------------------- | ------------------ |
| explicit_02 | pizza    | other_person_consumed   | consumed               | Wrong relationship |
| mdss_03     | soup     | other_person_consumed   | consumed               | Wrong relationship |
| mdss_03     | bread    | explicitly_not_consumed | unclear                | Wrong relationship |
| mdss_04     | apple    | unclear                 | consumed               | Wrong relationship |
| mdss_07     | pancakes | unclear                 | consumed               | Wrong relationship |
| mdss_08     | coleslaw | explicitly_not_consumed | unclear                | Wrong relationship |
| mdss_09     | tomato   | No separate food row    | consumed               | Extra food         |
| mdss_10     | cereal   | other_person_consumed   | consumed               | Wrong relationship |
| mdss_13     | orders   | No food row             | unclear                | Extra food         |

## Decision

Freeze v2 as a development comparison configuration. Preserve its prompt text, schema, fixture targets, model settings and saved results. Do not silently edit this prompt under the same version ID.

Next: compare another small local model using the same v2 prompt, schema and fixtures. Runtime memory and CPU performance must be measured on representative 8 GB hardware before making compatibility claims. Do not describe this system as validated or analysis-ready.

## Limits

These fixtures have informed prompt revisions; they are not held-out validation data. Scores use case/whitespace-normalized exact one-to-one food matching. Repeated-mention alignment, aliases, evidence support, ingredients, ordering and the full MDSS workflow are not assessed by these minimal-schema scores.

This document preserves the posted summary and error table. It does not contain the complete raw model responses or the exact run directory/model digest.

## Preserve the full run on your computer

The evaluation runner already saves each run under `experiments/results/`, including `manifest.rds`, `records.rds`, and score CSVs. In the same R session, `evaluation_v2$directory` shows that folder.

For an additional snapshot in that existing run directory:

```r
saveRDS(
  evaluation_v2,
  file.path(evaluation_v2$directory, "evaluation_v2_snapshot.rds")
)
evaluation_v2$directory
```

This uses the existing run directory and does not alter package functions.