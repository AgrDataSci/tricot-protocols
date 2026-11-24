# Build a ClimMob project from XLSForms through the ClimMob API
#
# Reads one registration form and one or more data collection forms (ODK
# XLSForms, English labels), and
#   1. collapses each form into ClimMob library questions (rankings, per-option
#      questions, comparisons with the farmer's variety, "other" options)
#   2. matches every question against the account's question library and
#      reuses it when the text, type and options are the same
#   3. creates the questions that do not exist yet, with their options and
#      statements
#   4. creates the project, its registration form and its data collection
#      moments, with the groups and questions of each form
#
# Everything is in English. Translations, ordering and the final curation are
# done in the ClimMob platform.
#
# Run with dry_run = TRUE first. It reads the library and writes the match plan
# to <output>/plan.csv without changing anything in ClimMob. Review the plan,
# add use_id overrides where a suggested question should be reused, then run
# with dry_run = FALSE. Start on the testing server.
#
# Requires the ClimMob API key in the CLIMMOB_API_KEY environment variable.
# Never write the key in this script.

source("script/helper/helper-04-climmob-api.R")

# ---------------------------------------------------------------------------
# Deployment
# ---------------------------------------------------------------------------

deployment = list(
  server = "testing",          # testing, climmob3 or 1000farms
  owner = "bioversity",        # account that owns the API key
  dry_run = TRUE,
  category = "tricot protocols",  # library category for new questions
  output = "deployments/india-tumkur-chickpea-2025",
  project = list(
    project_cod = "tmkcp25",   # 10 characters at most
    project_name = "Tumkur chickpea 2025",
    project_abstract = "tricot variety evaluation of chickpea in Tumkur, Karnataka",
    project_tags = "chickpea;tricot;India",
    project_pi = "TODO",
    project_piemail = "TODO",
    project_numobs = "TODO",
    project_cnty = "IN",
    project_registration_and_analysis = 0,
    project_label_a = "Option A",
    project_label_b = "Option B",
    project_label_c = "Option C"
  ),
  forms = list(
    list(file = "registration_tumkur_chickpea_2025.xlsx", type = "registration"),
    list(file = "afterrep_tumkur_chickpea_v1.xlsx", type = "assessment",
         ass_desc = "After reproduction", ass_days = "TODO", ass_final = 0),
    list(file = "postharv_tumkur_chickpea_v1.xlsx", type = "assessment",
         ass_desc = "Post harvest", ass_days = "TODO", ass_final = 1)
  ),
  # XLSForm names to leave out
  skip = c("chickpea_tumkur_2025_reg", "chickpea_tumkur_2025_afterrep",
           "chickpea_tumkur_2025_posthar"),
  # question code -> library question_id, to force a match
  use_id = c(package_code = 162)
)

# ---------------------------------------------------------------------------
# Parse the forms
# ---------------------------------------------------------------------------

dir.create(deployment$output, recursive = TRUE, showWarnings = FALSE)
forms_dir = file.path(deployment$output, "forms")

cm = cm_client(Sys.getenv("CLIMMOB_API_KEY"), deployment$server, deployment$dry_run)

if (!cm$dry_run) {
  todo = c(unlist(deployment$project), unlist(lapply(deployment$forms, `[[`, "ass_days")))
  if (any(todo == "TODO")) stop("Fill every TODO in the deployment before a live run")
}

placements = list()   # where each question goes: form, group, signature
questions = list()    # one entry per library question, keyed by signature

for (f in seq_along(deployment$forms)) {
  form = deployment$forms[[f]]
  form_label = if (form$type == "registration") "Registration" else form$ass_desc
  qs = parse_xlsform(file.path(forms_dir, form$file),
                     skip = deployment$skip, use_id = deployment$use_id)
  for (q in qs) {
    if (is.na(q$group)) q$group = form_label
    sig = if (!is.na(q$use_id)) paste0("id#", q$use_id) else question_signature(q)
    if (is.null(questions[[sig]])) {
      q$forms = form_label
      questions[[sig]] = q
    } else {
      questions[[sig]]$forms = paste(questions[[sig]]$forms, form_label, sep = "; ")
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
write.csv(plan, file.path(deployment$output, "plan.csv"), row.names = FALSE)

message(sum(grepl("^matched", plan$status)), " questions matched, ",
        sum(plan$status == "new"), " to create, ",
        sum(!is.na(plan$suggested_id)), " with a close library question to review")

if (any(plan$status == "fixed id not in library")) {
  bad = plan$code[plan$status == "fixed id not in library"]
  msg = paste("These use_id values are not in the library:", paste(bad, collapse = ", "))
  if (cm$dry_run) warning(msg, call. = FALSE) else stop(msg)
}

log_env = new.env()
log_env$rows = list()
log_action = function(action, target, result) {
  log_env$rows[[length(log_env$rows) + 1]] = data.frame(time = format(Sys.time()), action = action,
                                        target = target, result = result,
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

  res = cm$post("createQuestion", list(
    question_code = code,
    question_name = substr(humanise(q$code), 1, 120),
    question_desc = q$text,
    question_dtype = q$dtype,
    qstgroups_id = category_id,
    question_requiredvalue = as.integer(q$required),
    question_tied = 0,
    question_notobserved = as.integer(q$notobserved),
    question_quantitative = as.integer(q$quantitative)
  ))

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
                                        value_isna = 0,
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
if (p$project_cod %in% projects$project_cod) {
  stop("Project ", p$project_cod, " already exists, choose another project_cod")
}

countries = cm_records(cm$get("readListOfCountries"), c("code", "name"))
if (!p$project_cnty %in% countries$code) stop("Unknown country code ", p$project_cnty)

cm$post("createProject", c(p, list(project_template = "")))
log_action("createProject", p$project_cod, "created")

# the question ids already in a form, so automatic ClimMob questions are not added twice
form_ids = function(f) {
  if (cm$dry_run) return(character(0))
  form = deployment$forms[[f]]
  if (form$type == "registration") {
    cm_find_ids(cm$get("readProjectRegistry", project_cod = p$project_cod, user_owner = owner))
  } else {
    cm_find_ids(cm$get("readProjectAssessmentStructure", project_cod = p$project_cod,
                       user_owner = owner, ass_cod = form$ass_cod))
  }
}

possible_ids = function(f) {
  if (cm$dry_run) return(character(0))
  form = deployment$forms[[f]]
  res = if (form$type == "registration") {
    cm$get("readPossibleQuestionsForRegistryGroup", project_cod = p$project_cod,
           user_owner = owner)
  } else {
    cm$get("readPossibleQuestionForAssessmentGroup", project_cod = p$project_cod,
           user_owner = owner, ass_cod = form$ass_cod)
  }
  if (is.list(res)) cm_find_ids(res$Questions) else character(0)
}

for (f in seq_along(deployment$forms)) {
  form = deployment$forms[[f]]
  is_reg = form$type == "registration"

  if (!is_reg) {
    res = cm$post("createAssessment", list(project_cod = p$project_cod, user_owner = owner,
                                           ass_desc = form$ass_desc,
                                           ass_days = form$ass_days,
                                           ass_final = form$ass_final))
    ass_cod = if (cm$dry_run) paste0("dry-", f) else if (is.list(res)) res$ass_cod else NULL
    if (!cm$dry_run && is.null(ass_cod)) {
      ass = cm_records(cm$get("readProjectAssessments", project_cod = p$project_cod,
                              user_owner = owner), c("ass_cod", "ass_desc"))
      ass_cod = ass$ass_cod[ass$ass_desc == form$ass_desc][1]
    }
    deployment$forms[[f]]$ass_cod = ass_cod
    form$ass_cod = ass_cod
    log_action("createAssessment", form$ass_desc, ass_cod)
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

message("Done. Review ", file.path(deployment$output, "plan.csv"), " and the log, ",
        "then curate the forms in ClimMob.")
