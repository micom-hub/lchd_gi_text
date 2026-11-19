# Phi synthetic follow-up evaluation

Extract this folder to `experiments/phi_followup/` in lchd_gi_text.
Do not add it to R/load_project.R. The supplied evaluation_core.R is a frozen copy
of the earlier evaluator, not a replacement for your package functions.

## Contents

- fixtures.csv: 32 new fictional Food_Consumed answers, categories and annotation notes.
- reference_labels.csv: 47 expected food/relationship rows. Cases with no named foods have zero label rows.
- run_phi_followup.R: manual runner; uses fresh conversations, the unchanged mdss_rules_v2 prompt and minimal schema.
- evaluation_core.R: frozen prompts/schema/scorer used by the runner.

All names and records are synthetic. No real case records are included.

## Review first

Read each fixture alongside its reference labels and annotation note. Resolve disagreements
before running the model. A second human reviewer would strengthen the labels.
The labels were drafted by an AI assistant, not independently adjudicated.

Grouping convention: independently listed foods are separate; a conventional dish name
(e.g. macaroni and cheese) stays together. Explicit ingredients attached to a dish do not
become separate food rows. This is a measurement convention that needs team agreement.
The minimal schema does NOT score ingredient extraction itself.

The reduced categories are consumed, other_person_consumed, explicitly_not_consumed,
and unclear. Purchase with unknown consumption maps to unclear; purchase with an explicit
denial maps to explicitly_not_consumed in this reduced evaluation.
No source statement that names no specific food should create an invented food name.

This follow-up set was designed after examining earlier errors. It is a synthetic challenge
set for generalization checks, not a representative or independently held-out deployment
benchmark. Once you inspect its results or tune to them, treat it as development data.
Do not send labels or annotation notes to the model; the runner sends only the input column.

## Run from the R console at your project root

```r
source('experiments/phi_followup/run_phi_followup.R')
check_phi_followup()

# After reviewing the reference labels:
phi_followup <- run_phi_followup(labels_reviewed=TRUE)
phi_followup$scores$summary
subset(phi_followup$scores$details, outcome != 'correct')
```

Requires installed ellmer/jsonlite, a running local Ollama service and installed
phi4-mini:3.8b. No downloads/installations are triggered. There are 32 sequential
requests with no retries. Ctrl+C interrupts a run; completed records are saved after
each request. Automatic resume and request-level timeouts are not implemented.

Keep previous evaluation_v2 and phi_evaluation results. These are different fixtures,
so a new score cannot be interpreted as a direct improvement over the old score.

## What is scored

Case/whitespace-normalized one-to-one food matching; mention precision/recall/F1;
relationship accuracy on matched foods; correct-pair recall/F1; whole-record correctness;
request failures; elapsed request time. Capitalization differences are retained in the
details but do not lower normalized matching accuracy. Output order is not scored.
Aliases, repeated mentions, ingredient/evidence extraction and real-record accuracy
are outside this evaluator. Failures remain in record counts and recall denominators.

Raw outputs, reference snapshots, configuration, session info, scores and a complete RDS
snapshot are saved to a unique experiments/results/phi_followup_* folder.
The runner attempts to record Ollama version and model digest using the local API.
Memory usage is not measured automatically.

## 8 GB hardware check (separate from accuracy)

Use an actual approved 8 GB Windows machine, CPU-only if that is the deployment target.
Record installed RAM, CPU, Ollama and R versions, and whether other models are loaded.
In a separate PowerShell terminal, `ollama ps` shows active model CPU/GPU allocation.
Use Task Manager > Performance > Memory and Details to observe total system memory,
R and Ollama processes during the run. Record baseline and observed peak memory,
CPU/GPU allocation and slowdowns in your lab notes. Task Manager observations are
approximate, not a precise automated peak-memory measurement. Do not infer runtime RAM
from model download size. Report the first model-loading request separately from later
requests using per_record.csv. Existing timing includes model load when it occurs.
