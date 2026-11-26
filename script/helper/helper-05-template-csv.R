# The template CSV: one file that describes a ClimMob project template
#
# One row per question, in form order. Rows of the same form and group stay
# together. Columns
#   form                  form name: "Registration" or the data collection moment
#   form_type             registration or assessment
#   ass_days              days after registration (assessments only)
#   ass_final             1 for the final data collection moment, else 0
#   group                 group (section) of the form
#   question_id           ClimMob library id. When set, that library question is
#                         used as it is and the text columns are for reading only
#   question_code         library code, e.g. qst_gender or overallchar
#   question_name         short name
#   question_type         text, decimal, integer, geopoint, select_one,
#                         select_multiple, package, participant, ranking,
#                         comparison, date, time, datetime, image, audio, video,
#                         barcode
#   question_desc         question text (120 characters at most)
#   question_posstm       ranking only, positive statement
#   question_negstm       ranking only, negative statement
#   question_perfstmt     comparison only, statement with {{option}}
#   question_unit, question_notes
#   question_required     1 or 0
#   question_quantitative 1 when the question is asked for each option (A, B, C)
#   question_tied, question_notobserved  ranking only, 1 or 0
#   question_sensitive    1 for personal data (PII), set in the ClimMob platform
#   options               select questions, "code=label | code=label", with
#                         " [other]" or " [na]" after a label to mark it
#
# Used by script/00-export-templates.R, script/03-push-template-to-climmob.R
# and script/04-convert-xlsform-to-template.R

template_columns = c("form", "form_type", "ass_days", "ass_final", "group",
                     "question_id", "question_code", "question_name", "question_type",
                     "question_desc", "question_posstm", "question_negstm",
                     "question_perfstmt", "question_unit", "question_notes",
                     "question_required", "question_quantitative", "question_tied",
                     "question_notobserved", "question_sensitive", "options")

question_types = c(text = 1, decimal = 2, integer = 3, geopoint = 4,
                   select_one = 5, select_multiple = 6, package = 7, participant = 8,
                   ranking = 9, comparison = 10, date = 13, time = 14,
                   datetime = 15, image = 16, audio = 17, video = 18, barcode = 19)

type_name = function(dtype) {
  out = names(question_types)[match(as.integer(dtype), question_types)]
  ifelse(is.na(out), as.character(dtype), out)
}

blank = function(x) is.null(x) || length(x) == 0 || is.na(x) || !nzchar(trimws(x))
or_na = function(x) if (blank(x)) NA_character_ else as.character(x)
as_flag = function(x) if (blank(x)) 0L else as.integer(as.integer(x) == 1)

# ---------------------------------------------------------------------------
# Options as one string
# ---------------------------------------------------------------------------

options_to_string = function(o) {
  if (is.null(o) || nrow(o) == 0) return(NA_character_)
  isother = if (is.null(o$value_isother)) rep(0, nrow(o)) else o$value_isother
  isna = if (is.null(o$value_isna)) rep(0, nrow(o)) else o$value_isna
  lab = paste0(o$value_code, "=", o$value_desc,
               ifelse(as_int(isother) == 1, " [other]", ""),
               ifelse(as_int(isna) == 1, " [na]", ""))
  paste(lab, collapse = " | ")
}

as_int = function(x) {
  x = suppressWarnings(as.integer(x))
  ifelse(is.na(x), 0L, x)
}

string_to_options = function(s) {
  if (blank(s)) return(NULL)
  parts = trimws(strsplit(s, "|", fixed = TRUE)[[1]])
  parts = parts[nzchar(parts)]
  code = sub("=.*$", "", parts)
  desc = sub("^[^=]*=", "", parts)
  isother = as.integer(grepl("\\s*\\[other\\]$", desc))
  desc = sub("\\s*\\[other\\]$", "", desc)
  isna = as.integer(grepl("\\s*\\[na\\]$", desc))
  desc = sub("\\s*\\[na\\]$", "", desc)
  data.frame(value_code = trimws(code), value_desc = trimws(desc),
             value_isother = isother, value_isna = isna, stringsAsFactors = FALSE)
}

# ---------------------------------------------------------------------------
# Question objects and template rows
# ---------------------------------------------------------------------------

# one template row from a question object (as made by parse_xlsform or read_template)
question_to_row = function(q, form, form_type, ass_days = NA, ass_final = NA) {
  data.frame(
    form = form, form_type = form_type,
    ass_days = or_na(ass_days), ass_final = or_na(ass_final),
    group = or_na(q$group),
    question_id = or_na(q$use_id),
    question_code = or_na(if (!blank(q$code_raw)) q$code_raw else q$code),
    question_name = or_na(if (!blank(q$name)) q$name else humanise(q$code)),
    question_type = type_name(q$dtype),
    question_desc = or_na(q$text),
    question_posstm = or_na(q$posstm), question_negstm = or_na(q$negstm),
    question_perfstmt = or_na(q$perfstmt),
    question_unit = or_na(q$unit), question_notes = or_na(q$notes),
    question_required = as_flag(q$required),
    question_quantitative = as_flag(q$quantitative),
    question_tied = as_flag(q$tied), question_notobserved = as_flag(q$notobserved),
    question_sensitive = as_flag(q$sensitive),
    options = options_to_string(q$options),
    stringsAsFactors = FALSE)
}

# a question object from one template row
row_to_question = function(r) {
  dtype = question_types[r$question_type]
  if (is.na(dtype)) dtype = suppressWarnings(as.integer(r$question_type))
  if (is.na(dtype)) stop("Unknown question_type ", r$question_type, " for ", r$question_code)
  list(code = r$question_code, code_raw = r$question_code,
       name = or_na(r$question_name), group = or_na(r$group),
       required = as_flag(r$question_required) == 1, dtype = unname(dtype),
       text = or_na(r$question_desc), posstm = or_na(r$question_posstm),
       negstm = or_na(r$question_negstm), perfstmt = or_na(r$question_perfstmt),
       unit = or_na(r$question_unit), notes = or_na(r$question_notes),
       quantitative = as_flag(r$question_quantitative) == 1,
       tied = as_flag(r$question_tied) == 1,
       notobserved = as_flag(r$question_notobserved) == 1,
       sensitive = as_flag(r$question_sensitive) == 1,
       options = string_to_options(r$options),
       use_id = if (blank(r$question_id)) NA_integer_ else as.integer(r$question_id))
}

write_template = function(tpl, file) {
  dir.create(dirname(file), recursive = TRUE, showWarnings = FALSE)
  write.csv(tpl[, template_columns], file, row.names = FALSE, na = "",
            fileEncoding = "UTF-8")
  invisible(file)
}

# a list of forms, each with its questions in order
read_template = function(file) {
  tpl = read.csv(file, colClasses = "character", na.strings = "",
                 fileEncoding = "UTF-8", check.names = FALSE)
  miss = setdiff(c("form", "form_type", "group", "question_code", "question_type"),
                 names(tpl))
  if (length(miss) > 0) stop("Missing columns in ", file, ": ", paste(miss, collapse = ", "))
  for (col in setdiff(template_columns, names(tpl))) tpl[[col]] = NA_character_
  if (!all(tpl$form_type %in% c("registration", "assessment"))) {
    stop("form_type must be registration or assessment")
  }
  forms = unique(tpl$form)
  lapply(forms, function(f) {
    rows = tpl[tpl$form == f, ]
    list(form = f, form_type = rows$form_type[1],
         ass_days = rows$ass_days[1], ass_final = as_flag(rows$ass_final[1]),
         questions = lapply(seq_len(nrow(rows)), function(i) row_to_question(rows[i, ])))
  })
}

# ---------------------------------------------------------------------------
# Export a project template from ClimMob
# ---------------------------------------------------------------------------

library_fields_full = c("question_id", "question_code", "question_name", "question_desc",
                        "question_dtype", "question_posstm", "question_negstm",
                        "question_perfstmt", "question_unit", "question_notes",
                        "question_requiredvalue", "question_quantitative",
                        "question_tied", "question_notobserved", "question_sensitive",
                        "user_name")

# every record holding a question_id, flattening nested lists, in order
structure_rows = function(x, section = list()) {
  if (!is.list(x)) return(list())
  if (!is.null(x$section_name)) {
    section = list(section_name = x$section_name, section_order = x$section_order)
  }
  out = list()
  if (!is.null(x$question_id) && !is.list(x$question_id)) {
    out = list(c(section, x[setdiff(names(x), names(section))]))
  }
  for (el in x) if (is.list(el)) out = c(out, structure_rows(el, section))
  out
}

structure_table = function(res) {
  rows = structure_rows(res)
  if (length(rows) == 0) return(data.frame())
  pick = function(r, f) if (is.null(r[[f]]) || length(r[[f]]) == 0) NA_character_ else
    as.character(r[[f]][[1]])
  df = data.frame(question_id = vapply(rows, pick, "", "question_id"),
                  group = vapply(rows, pick, "", "section_name"),
                  section_order = as.numeric(vapply(rows, pick, "", "section_order")),
                  question_order = as.numeric(vapply(rows, pick, "", "question_order")),
                  stringsAsFactors = FALSE)
  df$row = seq_len(nrow(df))
  df = df[!duplicated(df$question_id), ]
  df[order(df$section_order, df$question_order, df$row, na.last = TRUE), ]
}

options_of = function(cm, question_id) {
  v = cm_records(cm$get("readQuestionValues", question_id = question_id),
                 c("value_code", "value_desc", "value_isother", "value_isna", "value_order"))
  if (nrow(v) == 0) return(NULL)
  v[order(as.numeric(v$value_order)), ]
}

# template rows for one ClimMob project
export_template = function(cm, project_cod, owner) {
  lib = cm_records(cm$get("readQuestions"), library_fields_full)
  lib = lib[!duplicated(lib$question_id), ]

  forms = list(list(form = "Registration", form_type = "registration",
                    ass_days = NA, ass_final = NA,
                    structure = structure_table(cm$get("readProjectRegistry",
                                                       project_cod = project_cod,
                                                       user_owner = owner))))
  ass = cm_records(cm$get("readProjectAssessments", project_cod = project_cod,
                          user_owner = owner),
                   c("ass_cod", "ass_desc", "ass_days", "ass_final"))
  ass = ass[order(as.numeric(ass$ass_days)), ]
  for (a in seq_len(nrow(ass))) {
    forms[[length(forms) + 1]] = list(
      form = ass$ass_desc[a], form_type = "assessment",
      ass_days = ass$ass_days[a], ass_final = ass$ass_final[a],
      structure = structure_table(cm$get("readProjectAssessmentStructure",
                                         project_cod = project_cod, user_owner = owner,
                                         ass_cod = ass$ass_cod[a])))
  }

  rows = list()
  for (f in forms) {
    for (i in seq_len(nrow(f$structure))) {
      id = f$structure$question_id[i]
      l = lib[lib$question_id == id, ]
      if (nrow(l) == 0) {
        warning("Question ", id, " is not in the library of this API key; ",
                "only its id is exported", call. = FALSE)
        l = as.data.frame(as.list(setNames(rep(NA_character_, length(library_fields_full)),
                                           library_fields_full)))
        l$question_id = id
      }
      dtype = as.integer(l$question_dtype)
      q = list(code = l$question_code, code_raw = l$question_code,
               name = l$question_name, group = f$structure$group[i],
               required = as_flag(l$question_requiredvalue) == 1, dtype = dtype,
               text = l$question_desc, posstm = l$question_posstm,
               negstm = l$question_negstm, perfstmt = l$question_perfstmt,
               unit = l$question_unit, notes = l$question_notes,
               quantitative = as_flag(l$question_quantitative) == 1,
               tied = as_flag(l$question_tied) == 1,
               notobserved = as_flag(l$question_notobserved) == 1,
               sensitive = as_flag(l$question_sensitive) == 1,
               options = if (!is.na(dtype) && dtype %in% c(5, 6)) options_of(cm, id) else NULL,
               use_id = id)
      rows[[length(rows) + 1]] = question_to_row(q, f$form, f$form_type,
                                                 f$ass_days, f$ass_final)
    }
  }
  do.call(rbind, rows)
}
