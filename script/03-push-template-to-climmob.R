# Build a ClimMob project from a template CSV through the ClimMob API
#
# Reads a template CSV (format in script/helper/helper-05-template-csv.R), and
#   1. matches every question against the account's question library, by
#      question_id, then by code and type, then by text, type and options
#   2. creates the questions that do not exist yet, with their options and
#      statements
#   3. builds the forms of the project: registration groups and data collection
#      moments, with the groups and questions of each form
#
# Start from a protocol's protocols/<protocol_id>/template.csv, or from
# deployments/<deployment>/template.csv made by
# script/04-convert-xlsform-to-template.R. Everything is in English.
# Translations, question order and the final curation are done in the platform.
#
# Run with dry_run = TRUE first. It reads the library and writes the match plan
# to <output>/plan.csv without changing anything in ClimMob. Review the plan,
# set question_id in the CSV where a question should be reused, then run with
# dry_run = FALSE.
#
# Requires the ClimMob API key in the CLIMMOB_API_KEY environment variable,
# for example in .Renviron. Never write the key in this script.
#
# What the ClimMob API does not do (tested on 1000farms, November 2026)
#   createProject rejects every documented field set, so create the project in
#   the platform first and keep create_project = FALSE
#   question_sensitive and question_anonymity cannot be set; the plan lists
#   personal data questions to mark as confidential in the platform

source("script/helper/helper-04-climmob-api.R")
source("script/helper/helper-05-template-csv.R")

# ---------------------------------------------------------------------------
# Deployment
# ---------------------------------------------------------------------------

deployment = list(
  server = "1000farms",          # testing, climmob3 or 1000farms
  owner = "bioversity",          # account that owns the API key
  dry_run = TRUE,
  template = "deployments/chickpea/template.csv",
  output = "deployments/chickpea",
  category = "tricot protocols", # library category for new questions
  lang = "en",                   # language of the new questions
  # FALSE to use a project already created in the platform with project_cod
  create_project = FALSE,
  project = list(
    project_cod = "chickpea",    # 10 characters at most
    project_name = "Chickpea Template",
    project_abstract = "Template to deploy on-farm trials with chickpea",
    project_tags = "chickpea;tricot;India",
    project_pi = "Kauê de Sousa",
    project_piemail = "k.desousa@cgiar.org",
    project_numobs = "100000",
    project_cnty = "FR",
    project_registration_and_analysis = 0,
    project_label_a = "A",
    project_label_b = "B",
    project_label_c = "C"
  )
)

# ---------------------------------------------------------------------------
# Read the template
# ---------------------------------------------------------------------------

dir.create(deployment$output, recursive = TRUE, showWarnings = FALSE)

cm = cm_client(Sys.getenv("CLIMMOB_API_KEY"), deployment$server, deployment$dry_run)

forms = read_template(deployment$template)

if (!cm$dry_run) {
  days = vapply(forms, function(f) if (f$form_type == "assessment") f$ass_days else "0",
                character(1))
  if (any(vapply(days, blank, logical(1)) | days %in% "TODO")) {
    stop("Set ass_days for every data collection moment")
  }
}

placements = list()   # where each question goes: form, group, signature
questions = list()    # one entry per library question, keyed by signature

for (f in seq_along(forms)) {
  for (q in forms[[f]]$questions) {
    if (is.na(q$group)) q$group = forms[[f]]$form
    sig = if (!is.na(q$use_id)) paste0("id#", q$use_id) else question_signature(q)
    if (is.null(questions[[sig]])) {
      q$forms = forms[[f]]$form
      questions[[sig]] = q
    } else {
      questions[[sig]]$forms = paste(questions[[sig]]$forms, forms[[f]]$form, sep = "; ")
      questions[[sig]]$required = questions[[sig]]$required || q$required
    }
    placements[[length(placements) + 1]] = list(form = f, group = q$group, sig = sig)
  }
}

# ---------------------------------------------------------------------------
# Match against the library
# ---------------------------------------------------------------------------

lib = read_library(cm)
plan = match_questions(cm, unname(questions), lib, deployment$owner)
plan$signature = names(questions)

# package and participant questions are added by ClimMob to every form
auto = vapply(questions, function(q) q$dtype %in% c(7, 8), logical(1))
plan$status[auto] = "automatic in ClimMob"

plan = pii_flag(plan, lib)
write.csv(plan, file.path(deployment$output, "plan.csv"), row.names = FALSE)

message(sum(grepl("^matched", plan$status)), " questions matched, ",
        sum(plan$status == "new"), " to create, ",
        sum(!is.na(plan$suggested_id)), " with a close library question to review")

if (any(plan$status == "fixed id not in library")) {
  bad = plan$code[plan$status == "fixed id not in library"]
  msg = paste("These question_id values are not in the library:", paste(bad, collapse = ", "))
  if (cm$dry_run) warning(msg, call. = FALSE) else stop(msg)
}

# ClimMob rejects long question texts ("The question is very long"). The
# longest text in the library is 116 characters, so 120 is taken as the limit.
# Check before writing anything, so a run does not stop halfway
max_chars = 120
long_text = vapply(plan$signature, function(sig) {
  q = questions[[sig]]
  max(nchar(c(q$text, q$posstm, q$negstm, q$perfstmt)), 0, na.rm = TRUE)
}, numeric(1))
too_long = plan$status == "new" & long_text > max_chars
if (any(too_long)) {
  msg = paste0("Shorten these question texts to ", max_chars,
               " characters or less: ",
               paste0(plan$code[too_long], " (", long_text[too_long], ")", collapse = ", "))
  if (cm$dry_run) warning(msg, call. = FALSE) else stop(msg)
}

log_env = new.env()
log_env$rows = list()
log_action = function(action, target, result) {
  log_env$rows[[length(log_env$rows) + 1]] = data.frame(time = format(Sys.time()),
                                                        action = action, target = target,
                                                        result = result,
                                                        stringsAsFactors = FALSE)
}

# ---------------------------------------------------------------------------
# Create the missing questions
# ---------------------------------------------------------------------------

cats = cm_records(cm$get("readCategoriesOfQuestions"), c("qstgroups_id", "qstgroups_name"))
category_id = cats$qstgroups_id[cats$qstgroups_name == deployment$category][1]
if (is.na(category_id)) {
  res = cm$post("createCategoryOfQuestions", list(qstgroups_name = deployment$category))
  category_id = if (cm$dry_run) "dry-run" else
    cm_records(res, c("qstgroups_id", "qstgroups_name"))$qstgroups_id[1]
  log_action("createCategoryOfQuestions", deployment$category, category_id)
}

taken = tolower(lib$question_code)

for (i in which(plan$status == "new")) {
  q = questions[[plan$signature[i]]]
  code = unique_code(q$code, taken)
  taken = c(taken, code)

  # question_lang is required although the 2021 API docs leave it out. The
  # flags apply to some types only, and ClimMob rejects them elsewhere
  body = list(question_code = code,
              question_name = substr(if (!blank(q$name)) q$name else humanise(q$code), 1, 120),
              question_desc = if (blank(q$text)) "-" else q$text,
              question_dtype = q$dtype,
              qstgroups_id = category_id,
              question_requiredvalue = as.integer(q$required),
              question_lang = deployment$lang)
  if (q$dtype == 9) {
    body$question_tied = as.integer(isTRUE(q$tied))
    body$question_notobserved = as.integer(q$notobserved)
  }
  if (!q$dtype %in% c(9, 10) && q$quantitative) body$question_quantitative = 1
  res = cm$post("createQuestion", body)

  if (cm$dry_run) {
    id = paste0("new:", code)
  } else {
    made = cm_records(res, c("question_id", "question_code"))
    id = made$question_id[made$question_code == code][1]
    if (is.na(id)) {
      lib_now = read_library(cm)
      id = lib_now$question_id[lib_now$question_code == code][1]
    }
    if (is.na(id)) stop("Created question ", code, " but cannot find its id")
  }
  plan$question_id[i] = id
  plan$user_name[i] = deployment$owner
  log_action("createQuestion", code, id)

  if (!is.null(q$options)) {
    for (j in seq_len(nrow(q$options))) {
      cm$post("addQuestionValues", list(question_id = id,
                                        value_code = q$options$value_code[j],
                                        value_desc = q$options$value_desc[j],
                                        value_isna = q$options$value_isna[j],
                                        value_isother = q$options$value_isother[j]))
    }
    log_action("addQuestionValues", code, paste(nrow(q$options), "options"))
  }
  if (q$dtype == 9) {
    cm$post("updateQuestionCharacteristics", list(question_id = id,
                                                  question_posstm = q$posstm,
                                                  question_negstm = q$negstm))
    log_action("updateQuestionCharacteristics", code, "statements set")
  }
  if (q$dtype == 10) {
    cm$post("updateQuestionPerformance", list(question_id = id,
                                              question_perfstmt = q$perfstmt))
    log_action("updateQuestionPerformance", code, "statement set")
  }
}

write.csv(plan, file.path(deployment$output, "plan.csv"), row.names = FALSE)

# ---------------------------------------------------------------------------
# Create the project and its forms
# ---------------------------------------------------------------------------

p = deployment$project
owner = deployment$owner

projects = cm_records(cm$get("readProjects"), c("project_cod", "owner"))
exists = p$project_cod %in% projects$project_cod

if (isTRUE(deployment$create_project)) {
  if (exists) stop("Project ", p$project_cod, " already exists, choose another project_cod")
  countries = cm_records(cm$get("readListOfCountries"), c("code", "name"))
  if (!p$project_cnty %in% countries$code) stop("Unknown country code ", p$project_cnty)
  cm$post("createProject", p)
  log_action("createProject", p$project_cod, "created")
} else {
  if (!exists && !cm$dry_run) {
    stop("Create project ", p$project_cod, " in ClimMob first, or set create_project = TRUE")
  }
  log_action("useProject", p$project_cod, if (exists) "found" else "not found yet")
}

# the question ids already in a form, so automatic ClimMob questions are not added twice
form_ids = function(f) {
  if (cm$dry_run) return(character(0))
  if (forms[[f]]$form_type == "registration") {
    cm_find_ids(cm$get("readProjectRegistry", project_cod = p$project_cod, user_owner = owner))
  } else {
    cm_find_ids(cm$get("readProjectAssessmentStructure", project_cod = p$project_cod,
                       user_owner = owner, ass_cod = forms[[f]]$ass_cod))
  }
}

possible_ids = function(f) {
  if (cm$dry_run) return(character(0))
  res = if (forms[[f]]$form_type == "registration") {
    cm$get("readPossibleQuestionsForRegistryGroup", project_cod = p$project_cod,
           user_owner = owner)
  } else {
    cm$get("readPossibleQuestionForAssessmentGroup", project_cod = p$project_cod,
           user_owner = owner, ass_cod = forms[[f]]$ass_cod)
  }
  if (is.list(res)) cm_find_ids(res$Questions) else character(0)
}

for (f in seq_along(forms)) {
  form = forms[[f]]
  is_reg = form$form_type == "registration"

  if (!is_reg) {
    res = cm$post("createAssessment", list(project_cod = p$project_cod, user_owner = owner,
                                           ass_desc = form$form,
                                           ass_days = form$ass_days,
                                           ass_final = form$ass_final))
    ass_cod = if (cm$dry_run) paste0("dry-", f) else if (is.list(res)) res$ass_cod else NULL
    if (!cm$dry_run && is.null(ass_cod)) {
      ass = cm_records(cm$get("readProjectAssessments", project_cod = p$project_cod,
                              user_owner = owner), c("ass_cod", "ass_desc"))
      ass_cod = ass$ass_cod[ass$ass_desc == form$form][1]
    }
    forms[[f]]$ass_cod = ass_cod
    form$ass_cod = ass_cod
    log_action("createAssessment", form$form, ass_cod)
  }

  here = Filter(function(x) x$form == f, placements)
  groups = unique(vapply(here, `[[`, character(1), "group"))
  present = form_ids(f)
  allowed = possible_ids(f)

  for (g in groups) {
    body = list(project_cod = p$project_cod, user_owner = owner,
                section_name = g, section_content = g)
    if (!is_reg) body$ass_cod = form$ass_cod
    res = cm$post(if (is_reg) "createRegistryGroup" else "createAssessmentGroup", body)
    group_cod = if (cm$dry_run) paste0("dry-", g) else if (is.list(res)) res$section_id else NULL
    if (is.null(group_cod)) stop("ClimMob did not return a group code for ", g)
    log_action(if (is_reg) "createRegistryGroup" else "createAssessmentGroup", g, group_cod)

    for (x in Filter(function(x) x$group == g, here)) {
      row = plan[plan$signature == x$sig, ]
      if (row$status == "automatic in ClimMob") {
        log_action("skip", row$code, "added by ClimMob")
        next
      }
      if (row$question_id %in% present) {
        log_action("skip", row$code, "already in the form")
        next
      }
      if (length(allowed) > 0 && !row$question_id %in% allowed) {
        log_action("skip", row$code, "ClimMob does not allow it in this form")
        next
      }
      body = list(project_cod = p$project_cod, user_owner = owner, group_cod = group_cod,
                  question_id = row$question_id, question_user_name = row$user_name)
      if (!is_reg) body$ass_cod = form$ass_cod
      ok = tryCatch({
        cm$post(if (is_reg) "addQuestionToGroupRegistry" else "addQuestionToGroupAssessment", body)
        "added"
      }, error = function(e) conditionMessage(e))
      present = c(present, row$question_id)
      log_action(if (is_reg) "addQuestionToGroupRegistry" else "addQuestionToGroupAssessment",
                 row$code, ok)
    }
  }
}

log = do.call(rbind, log_env$rows)
write.csv(log, file.path(deployment$output,
                         if (cm$dry_run) "log-dry-run.csv" else "log.csv"),
          row.names = FALSE)

failed = log$action %in% c("addQuestionToGroupRegistry", "addQuestionToGroupAssessment") &
  log$result != "added"
if (any(failed)) {
  warning(sum(failed), " questions could not be added, see the log: ",
          paste(log$target[failed], collapse = ", "), call. = FALSE)
}

message("Done. Review ", file.path(deployment$output, "plan.csv"), " and the log, ",
        "then curate the forms in ClimMob.")

to_mark = plan$code[plan$pii == "mark as confidential in ClimMob"]
if (length(to_mark) > 0) {
  message("Mark as confidential (PII) in the ClimMob library: ",
          paste(to_mark, collapse = ", "))
}
