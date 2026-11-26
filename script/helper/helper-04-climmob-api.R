# Helpers to talk to the ClimMob API and to build ClimMob forms
#
# Used by script/00-export-templates.R, script/03-push-template-to-climmob.R
# and script/04-convert-xlsform-to-template.R. Three parts
#   1. a small API client (GET retries, POST never retries, key never printed)
#   2. an XLSForm parser that collapses ODK rows into ClimMob library questions
#   3. matching against the account's question library
#
# Endpoints and fields follow the ClimMob Postman collection
# https://documenter.getpostman.com/view/13253300/TVYGcxau

library("httr")
library("jsonlite")
library("readxl")

# ---------------------------------------------------------------------------
# 1. API client
# ---------------------------------------------------------------------------

cm_base_url = function(server) {
  switch(server,
         climmob3 = "https://climmob.net/climmob3/api/",
         testing = "https://testing.climmob.net/climmob3/api/",
         "1000farms" = "https://1000farms.climmob.net/api/",
         paste0("https://", server, ".climmob.net/api/"))
}

cm_parse_response = function(r, endpoint) {
  txt = content(r, as = "text", encoding = "UTF-8")
  if (status_code(r) != 200) {
    stop("ClimMob ", endpoint, " returned HTTP ", status_code(r), ": ",
         substr(txt, 1, 300), call. = FALSE)
  }
  tryCatch(fromJSON(txt, simplifyVector = FALSE), error = function(e) txt)
}

# returns a list with get() and post(); post() only logs when dry_run = TRUE
cm_client = function(key, server = "testing", dry_run = TRUE) {
  if (!nzchar(key)) stop("Set the CLIMMOB_API_KEY environment variable")
  base = cm_base_url(server)
  ua = user_agent("tricot-protocols (https://github.com/AgrDataSci/tricot-protocols)")

  # As in the ClimMob Postman examples, reads send their parameters in the
  # query and writes send one form field per parameter. Leave out fields
  # that do not apply: ClimMob rejects unexpected keys
  get = function(endpoint, ...) {
    r = RETRY("GET", paste0(base, endpoint),
              query = c(list(Apikey = key), list(...)),
              ua, timeout(60), times = 3, quiet = TRUE)
    cm_parse_response(r, endpoint)
  }

  post = function(endpoint, body) {
    body = Filter(function(x) length(x) > 0 && !is.na(x), body)
    body = lapply(body, as.character)
    if (dry_run) {
      message("[dry run] POST ", endpoint, " ",
              paste(names(body), body, sep = "=", collapse = "; "))
      return(NULL)
    }
    r = POST(paste0(base, endpoint), query = list(Apikey = key),
             body = body, encode = "multipart", ua, timeout(60))
    cm_parse_response(r, endpoint)
  }

  list(get = get, post = post, dry_run = dry_run, server = server)
}

# list of records (JSON array of objects) to a data.frame of character columns
cm_records = function(x, fields) {
  # a single JSON object comes back as a named list: treat it as one record
  if (is.list(x) && !is.null(names(x)) && any(fields %in% names(x))) x = list(x)
  if (is.list(x)) x = Filter(is.list, x)
  if (!is.list(x) || length(x) == 0) {
    return(as.data.frame(setNames(replicate(length(fields), character(0),
                                            simplify = FALSE), fields),
                         stringsAsFactors = FALSE))
  }
  cols = lapply(fields, function(f) {
    vapply(x, function(r) {
      v = r[[f]]
      if (is.null(v) || length(v) == 0) NA_character_ else as.character(v[[1]])
    }, character(1))
  })
  as.data.frame(setNames(cols, fields), stringsAsFactors = FALSE)
}

# every question_id found anywhere in a nested API response
cm_find_ids = function(x) {
  if (!is.list(x)) return(character(0))
  ids = if (!is.null(x[["question_id"]])) as.character(x[["question_id"]]) else character(0)
  unique(c(ids, unlist(lapply(x, cm_find_ids), use.names = FALSE)))
}

# ---------------------------------------------------------------------------
# 2. XLSForm parser
# ---------------------------------------------------------------------------

xls_skip_types = c("start", "end", "today", "phonenumber", "start-geopoint",
                   "calculate", "username", "deviceid", "note", "end_group",
                   "end group", "end_repeat", "end repeat")

xls_dtype = c(text = 1, decimal = 2, integer = 3, geopoint = 4,
              select_one = 5, select_multiple = 6, date = 13, time = 14,
              datetime = 15, image = 16, audio = 17, video = 18, barcode = 19)

norm_text = function(x) {
  x = tolower(ifelse(is.na(x), "", x))
  trimws(gsub("[^a-z0-9]+", " ", x))
}

# "Number of rows in Option A", "Yield - Option B", "crop in  - Option C"
strip_option = function(x) {
  trimws(gsub("\\s*(\\bin\\s*)?(-\\s*)?Option [ABC]\\b", "", x, perl = TRUE))
}

# "FarmSize" or "date_sowing" to "Farm size" and "Date sowing"
humanise = function(x) {
  x = gsub("([a-z])([A-Z])", "\\1 \\2", x)
  x = tolower(gsub("[_.]+", " ", x))
  paste0(toupper(substr(x, 1, 1)), substr(x, 2, nchar(x)))
}

label_column = function(df) {
  cols = names(df)
  hit = grep("^label::english", cols, ignore.case = TRUE, value = TRUE)
  if (length(hit) == 0) hit = grep("^label$", cols, value = TRUE)
  if (length(hit) == 0) stop("No English label column in the XLSForm")
  hit[1]
}

# One element per ClimMob library question, in form order.
# skip   XLSForm names to leave out
# use_id named vector, question code -> library question_id
parse_xlsform = function(file, skip = character(0), use_id = integer(0)) {
  survey = read_excel(file, sheet = "survey", col_types = "text")
  choices = read_excel(file, sheet = "choices", col_types = "text")
  lab_s = label_column(survey)
  lab_c = label_column(choices)
  survey = survey[!is.na(survey$type), ]

  out = list()
  group = NA_character_
  first_group = NA_character_

  for (i in seq_len(nrow(survey))) {
    type = trimws(survey$type[i])
    name = survey$name[i]
    label = survey[[lab_s]][i]
    required = "required" %in% names(survey) &&
      isTRUE(tolower(survey$required[i]) %in% c("yes", "true"))

    if (grepl("^begin[_ ]group", type)) {
      group = label
      if (is.na(first_group)) first_group = label
      next
    }
    if (type %in% xls_skip_types || name %in% skip) next

    base = sub(" .*$", "", type)
    list_name = if (grepl(" ", type)) sub("^\\S+\\s+", "", type) else NA_character_
    if (!base %in% names(xls_dtype)) {
      warning("Skipped ", name, ", unsupported type ", type, call. = FALSE)
      next
    }

    raw = sub("^g\\d+_", "", name)
    code = sub("^(qst_|char_|perf_)", "", raw, ignore.case = TRUE)

    opts = choices[!is.na(choices$list_name) & choices$list_name == list_name, ]
    opts = data.frame(value_code = opts$name, value_desc = opts[[lab_c]],
                      stringsAsFactors = FALSE)
    is_option_list = nrow(opts) > 0 && any(grepl("^Option [ABC]$", opts$value_desc))

    q = list(code = code, group = group, required = required,
             dtype = unname(xls_dtype[base]), text = label, posstm = NA,
             negstm = NA, perfstmt = NA, quantitative = FALSE,
             notobserved = FALSE, options = NULL, use_id = NA_integer_,
             code_raw = raw)

    # ranking pair, e.g. char_maturity_pos and char_maturity_neg
    if (base == "select_one" && is_option_list && grepl("_(pos|neg)$", code)) {
      key = sub("_(pos|neg)$", "", code)
      if (is.null(out[[key]])) {
        q$code = key
        q$code_raw = sub("_(pos|neg)$", "", raw)
        q$dtype = 9
        q$text = "-"
        q$notobserved = any(norm_text(opts$value_desc) == "not observed")
        out[[key]] = q
      }
      slot = if (grepl("_pos$", code)) "posstm" else "negstm"
      out[[key]][[slot]] = label
      next
    }

    # comparison with the farmer's variety, e.g. perf_overallper_1 .. _3
    if (base == "select_one" && grepl("_\\d$", code) && !is_option_list &&
        grepl("Option [ABC]", label)) {
      key = sub("_\\d$", "", code)
      if (is.null(out[[key]])) {
        q$code = key
        q$code_raw = sub("_\\d$", "", raw)
        q$dtype = 10
        q$text = "-"
        q$perfstmt = gsub("Option [ABC]", "this option", label)
        out[[key]] = q
      }
      next
    }

    # one question asked for each option, e.g. qst_yield05_a .. _c
    if (grepl("_[abc]$", code) && !base %in% c("select_one", "select_multiple")) {
      key = sub("_[abc]$", "", code)
      if (is.null(out[[key]])) {
        q$code = key
        q$code_raw = sub("_[abc]$", "", raw)
        q$quantitative = TRUE
        q$text = strip_option(label)
        out[[key]] = q
      }
      next
    }

    # free text behind an "Other" option becomes ClimMob's value_isother
    if (base == "text" && grepl("_oth$", code)) {
      parent = sub("_oth$", "", code)
      if (!is.null(out[[parent]]$options)) {
        o = out[[parent]]$options
        o$value_isother[norm_text(o$value_desc) == "other"] = 1
        out[[parent]]$options = o
      }
      next
    }

    if (base %in% c("select_one", "select_multiple")) {
      opts$value_isother = rep(0, nrow(opts))
      q$options = opts
    }
    if (grepl("^QST\\d+$", code, ignore.case = TRUE)) {
      q$use_id = as.integer(sub("^QST", "", code, ignore.case = TRUE))
    }
    if (code %in% names(use_id)) q$use_id = as.integer(use_id[[code]])
    out[[code]] = q
  }

  # questions before the first group go into the first group
  for (k in names(out)) if (is.na(out[[k]]$group)) out[[k]]$group = first_group
  unname(out)
}

# the text that identifies a question, by type
question_text = function(q) {
  switch(as.character(q$dtype),
         "9" = paste(q$posstm, q$negstm),
         "10" = q$perfstmt,
         q$text)
}

# identifies the same question across forms
question_signature = function(q) {
  opt = if (is.null(q$options)) "" else
    paste(sort(norm_text(q$options$value_desc)), collapse = "|")
  paste(q$dtype, norm_text(question_text(q)), as.integer(q$quantitative), opt,
        sep = "#")
}

# ---------------------------------------------------------------------------
# 3. Library matching
# ---------------------------------------------------------------------------

library_fields = c("question_id", "question_code", "question_name", "question_desc",
                   "question_dtype", "question_posstm", "question_negstm",
                   "question_perfstmt", "user_name", "question_sensitive")

read_library = function(cm) {
  lib = cm_records(cm$get("readQuestions"), library_fields)
  lib$text = ifelse(lib$question_dtype == "9",
                    paste(lib$question_posstm, lib$question_negstm),
                    ifelse(lib$question_dtype == "10", lib$question_perfstmt,
                           lib$question_desc))
  lib$text_norm = norm_text(lib$text)
  lib[!duplicated(lib$question_id), ]
}

# the library codes a form question can carry. ClimMob exports use the library
# code as the XLSForm name, with char_ for rankings and perf_ for comparisons
code_candidates = function(q) {
  raw = q$code_raw
  unique(tolower(c(raw, sub("^(char_|perf_)", "", raw), q$code, paste0("qst_", q$code))))
}

option_set = function(cm, question_id) {
  v = cm_records(cm$get("readQuestionValues", question_id = question_id),
                 "value_desc")
  sort(norm_text(v$value_desc))
}

# Form codes that mean an administrative level, matched to ClimMob's
# standard qst_ADM1 to qst_ADM3 questions whatever their type in the form
admin_levels = c(state = "qst_adm1", province = "qst_adm1", region = "qst_adm1",
                 adm1 = "qst_adm1",
                 district = "qst_adm2", county = "qst_adm2", municipality = "qst_adm2",
                 adm2 = "qst_adm2",
                 village = "qst_adm3", community = "qst_adm3", locality = "qst_adm3",
                 adm3 = "qst_adm3")

# one row per question, matched to the library or marked new
match_questions = function(cm, questions, lib, owner) {
  rows = lapply(questions, function(q) {
    txt = question_text(q)
    res = data.frame(code = q$code, dtype = q$dtype, text = txt,
                     quantitative = q$quantitative, forms = q$forms,
                     status = "new", question_id = NA_character_,
                     user_name = NA_character_, suggested_id = NA_character_,
                     suggested_text = NA_character_, library_text = NA_character_,
                     stringsAsFactors = FALSE)

    if (!is.na(q$use_id)) {
      hit = lib[lib$question_id == as.character(q$use_id), ]
      if (nrow(hit) == 0) {
        res$status = "fixed id not in library"
      } else {
        # 7 package and 8 participant are added by ClimMob to every form
        res$status = if (hit$question_dtype[1] %in% c("7", "8")) "automatic in ClimMob" else
          "matched by id"
        res$question_id = hit$question_id[1]
        res$user_name = hit$user_name[1]
        res$library_text = hit$text[1]
      }
      return(res)
    }

    # administrative levels go to the standard ADM questions
    adm = admin_levels[sub("^qst_", "", tolower(q$code))]
    if (!is.na(adm)) {
      hit = lib[tolower(lib$question_code) == adm, ]
      if (nrow(hit) > 0) {
        res$question_id = hit$question_id[1]
        res$user_name = hit$user_name[1]
        res$library_text = hit$text[1]
        res$status = paste0("matched as ", toupper(sub("qst_", "", adm)),
                            if (hit$question_dtype[1] != as.character(q$dtype))
                              ", type differs" else "")
        return(res)
      }
    }

    # same code and type as a library question: the form came from ClimMob
    cand = lib[tolower(lib$question_code) %in% code_candidates(q) &
                 lib$question_dtype == as.character(q$dtype), ]
    if (nrow(cand) > 0) {
      cand = cand[order(cand$user_name != owner, as.integer(cand$question_id)), ]
      res$question_id = cand$question_id[1]
      res$user_name = cand$user_name[1]
      res$library_text = cand$text[1]
      notes = "matched by code"
      if (norm_text(txt) != cand$text_norm[1]) notes = c(notes, "text differs")
      if (!is.null(q$options) &&
          !identical(option_set(cm, cand$question_id[1]),
                     sort(norm_text(q$options$value_desc)))) {
        notes = c(notes, "options differ")
      }
      res$status = paste(notes, collapse = ", ")
      return(res)
    }

    cand = lib[lib$question_dtype == as.character(q$dtype) &
                 lib$text_norm == norm_text(txt), ]

    if (nrow(cand) > 0 && !is.null(q$options)) {
      want = sort(norm_text(q$options$value_desc))
      keep = vapply(cand$question_id,
                    function(id) identical(option_set(cm, id), want), logical(1))
      cand = cand[keep, ]
    }

    if (nrow(cand) > 0) {
      cand = cand[order(cand$user_name != owner,
                        tolower(cand$question_code) != tolower(q$code),
                        as.integer(cand$question_id)), ]
      res$status = if (nrow(cand) > 1) "matched, several candidates" else "matched"
      res$question_id = cand$question_id[1]
      res$user_name = cand$user_name[1]
      res$library_text = cand$text[1]
      return(res)
    }

    # nothing exact, suggest the closest question of the same type for curation
    same = lib[lib$question_dtype == as.character(q$dtype) & nzchar(lib$text_norm), ]
    if (nrow(same) > 0 && nzchar(norm_text(txt))) {
      d = adist(norm_text(txt), same$text_norm)[1, ]
      sim = 1 - d / pmax(nchar(norm_text(txt)), nchar(same$text_norm))
      best = which.max(sim)
      if (sim[best] >= 0.8) {
        res$suggested_id = same$question_id[best]
        res$suggested_text = same$text[best]
      }
    }
    res
  })
  do.call(rbind, rows)
}

# Personal data the platform should mark as confidential (PII). ClimMob's API
# cannot set question_sensitive or question_anonymity, so the plan flags them
# for curation in the platform
pii_pattern = paste0("\\b(names?|father|husband|mother|wife|spouse|phone|mobile|",
                     "telephone|e ?mail|address|gps|geopoint|coordinates?|",
                     "national id|id number|aadhaar|signature)\\b")

pii_flag = function(plan, lib) {
  txt = norm_text(paste(plan$code, plan$text))
  looks = grepl(pii_pattern, txt, perl = TRUE) | plan$dtype == 4
  marked = lib$question_sensitive[match(plan$question_id, lib$question_id)] %in% "1"
  plan$pii = ifelse(marked, "marked in library",
                    ifelse(looks, "mark as confidential in ClimMob", ""))
  plan
}

# a question_code not taken in the library
unique_code = function(code, taken) {
  code = tolower(gsub("[^A-Za-z0-9]", "", code))
  if (!code %in% taken) return(code)
  i = 2
  while (paste0(code, i) %in% taken) i = i + 1
  paste0(code, i)
}
