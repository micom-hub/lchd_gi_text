# experiments/phi_followup/run_phi_followup.R
# Source from your project root. This defines functions; no model calls on source.
# All text is synthetic. Review reference_labels.csv before the first model run.
# An answer with zero reference foods is represented by no rows in that CSV.

.phi_followup_dir <- dirname(normalizePath(
  sys.frame(1)$ofile, winslash = '/', mustWork = TRUE
))
source(file.path(.phi_followup_dir, 'evaluation_core.R'))

# Read the frozen, external fixtures and reference labels.
phi_followup_fixtures <- function(directory = .phi_followup_dir) {
  cases <- read.csv(file.path(directory, 'fixtures.csv'),
                    colClasses = 'character', check.names = FALSE)
  labels <- read.csv(file.path(directory, 'reference_labels.csv'),
                     colClasses = 'character', check.names = FALSE)
  stopifnot(nrow(cases) == 32L, !anyNA(cases$id), !anyDuplicated(cases$id),
            all(labels$id %in% cases$id), !anyNA(labels),
            all(labels$relationship %in% c('consumed','other_person_consumed',
                                           'explicitly_not_consumed','unclear')))
  targets <- lapply(seq_len(nrow(cases)), function(i) {
    t <- labels[labels$id == cases$id[i], c('food_text','relationship'), drop = FALSE]
    if (anyDuplicated(gi_food_key(t$food_text))) stop('Repeated reference food: ',cases$id[i])
    if (any(!vapply(t$food_text, function(food) grepl(food,cases$input[i],fixed=TRUE),logical(1))))
      stop('Reference food is not an exact source substring: ',cases$id[i])
    rownames(t) <- NULL
    t
  })
  data.frame(id=cases$id,category=cases$category,input=cases$input,
             target=I(targets),stringsAsFactors=FALSE)
}

# Offline structural checks, plus tests of the existing deterministic scorer.
check_phi_followup <- function() {
  gi_scorer_self_test()
  fixtures <- phi_followup_fixtures()
  for (i in seq_len(nrow(fixtures))) {
    s <- gi_score(fixtures$target[[i]], fixtures$target[[i]])
    stopifnot(s$counts['correct'] == nrow(fixtures$target[[i]]))
  }
  stopifnot('mdss_rules_v2' %in% names(gi_eval_prompts()))
  message('Follow-up checks passed: 32 cases, ',sum(vapply(fixtures$target,nrow,integer(1))),
          ' reference food rows. No model requests made.')
  invisible(TRUE)
}

# Same model, prompt, minimal schema, temperature, seed and output-token limit.
# Copies of inputs, labels and complete configuration are saved with every run.
run_phi_followup <- function(output_dir=file.path('experiments','results'),
                             labels_reviewed=FALSE) {
  if (!isTRUE(labels_reviewed)) stop(
    'Review fixtures.csv and reference_labels.csv first. Then pass labels_reviewed=TRUE. ',
    'This confirms your review, not independent annotation or approval for real data.')
  for (pkg in c('ellmer','jsonlite')) if (!requireNamespace(pkg,quietly=TRUE))
    stop('Missing package: ',pkg)
  check_phi_followup()
  fixtures <- phi_followup_fixtures()
  model <- 'phi4-mini:3.8b'; prompt_id <- 'mdss_rules_v2'
  prompt <- gi_eval_prompts()[[prompt_id]]
  dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
  run_dir <- tempfile(pattern=paste0('phi_followup_',format(Sys.time(),'%Y%m%d_%H%M%S'),'_'),tmpdir=output_dir)
  dir.create(run_dir,recursive=TRUE)
  if (!dir.exists(run_dir)) stop('Could not create results folder.')
  manifest <- list(fixture_version='phi_followup_0.1.0',fixtures=fixtures,
    model=model,prompt_id=prompt_id,prompt=prompt,schema=gi_eval_schema(),
    temperature=0,seed=123,max_tokens=512,base_url='http://127.0.0.1:11434',
    started_at=Sys.time(),session=utils::sessionInfo(),
    note=paste('Synthetic follow-up challenge set designed after prior error analysis.',
               'Draft AI-authored references reviewed by user; not independent clinical validation.',
               'Timing is end-to-end per request; memory is NOT measured by this runner.'))
  # Capture server version and exact installed-model details when httr2 is available.
  # Metadata failure is recorded without changing prompts or preventing the test.
  manifest$ollama_metadata <- if (requireNamespace('httr2',quietly=TRUE)) tryCatch({
    fetch <- function(path) {
      req <- httr2::request(paste0(manifest$base_url,path))
      req <- httr2::req_timeout(req,10)
      req <- httr2::req_options(req,proxy='',followlocation=FALSE)
      httr2::resp_body_json(httr2::req_perform(req),simplifyVector=FALSE)
    }
    tags <- fetch('/api/tags')
    installed <- Filter(function(m) identical(m$name,model) || identical(m$model,model),tags$models)
    list(version=fetch('/api/version'),selected_model=installed)
  },error=function(e) list(error=conditionMessage(e))) else list(error='httr2 unavailable')
  saveRDS(manifest,file.path(run_dir,'manifest.rds'))
  file.copy(file.path(.phi_followup_dir,c('fixtures.csv','reference_labels.csv')),run_dir)
  records <- list()
  for (i in seq_len(nrow(fixtures))) {
    message(i,'/32: ',fixtures$id[i],' [',fixtures$category[i],']')
    start <- Sys.time(); output <- NULL
    r <- tryCatch({
      chat <- ellmer::chat_ollama(base_url=manifest$base_url,model=model,
        system_prompt=prompt,params=ellmer::params(temperature=0,seed=123,max_tokens=512))
      output <- chat$chat_structured(fixtures$input[i],type=gi_eval_schema())
      gi_prediction_table(output)
      turn <- chat$last_turn()
      # Preserve response metadata; do not silently score truncated output as success.
      raw_finish <- tryCatch(turn@json$choices[[1]]$finish_reason,error=function(e) NULL)
      if (identical(raw_finish,'length')) stop('Output token limit reached.')
      list(status='success',output=output,error=NA_character_,turn=turn,tokens=chat$get_tokens())
    },error=function(e) list(status='error',output=output,error=conditionMessage(e)))
    r$model<-model; r$prompt_id<-prompt_id; r$test_id<-fixtures$id[i]; r$input<-fixtures$input[i]
    r$elapsed_seconds<-as.numeric(difftime(Sys.time(),start,units='secs'))
    records[[i]]<-r
    saveRDS(records,file.path(run_dir,'records.rds'))
  }
  scores <- gi_rescore(records,fixtures)
  for (name in names(scores)) write.csv(scores[[name]],file.path(run_dir,paste0(name,'.csv')),row.names=FALSE,na='')
  result <- list(directory=normalizePath(run_dir,winslash='/'),fixtures=fixtures,records=records,scores=scores)
  saveRDS(result,file.path(run_dir,'phi_followup_snapshot.rds'))
  print(scores$summary)
  message('Saved complete run: ',result$directory)
  invisible(result)
}

# R CONSOLE, FROM YOUR PROJECT ROOT:
# source('experiments/phi_followup/run_phi_followup.R')
# check_phi_followup()                            # no model calls
# Review the two CSV files, then:
# phi_followup <- run_phi_followup(labels_reviewed=TRUE) # 32 requests
# phi_followup$scores$summary
# subset(phi_followup$scores$details, outcome != 'correct')
# Offline reload: readRDS('YOUR_RUN_DIRECTORY/phi_followup_snapshot.rds')
