# Render tricot SOPs from their ClimMob templates
#
# The registry protocols.csv drives the run. Each row links a protocol folder
# in protocols/<protocol_id>/ to its ClimMob template. The script reads the
# protocol metadata, pulls the survey from ClimMob in every language listed in
# the crop sheet, and writes
#   protocols/<protocol_id>/sop/<protocol_id>-sop-<lang>.docx
#   protocols/<protocol_id>/questions-<lang>.csv  clean questions, read by agents
#   protocols/<protocol_id>/logs/<version>/  raw survey, clean questions,
#                                            run metadata and session info
#
# Requires the ClimMob API key in the CLIMMOB_API_KEY environment variable.
# Set `ids` to render only some protocols, e.g. ids = "sorghum-variety-testing".

library("ClimMobTools")
library("tidyverse")
library("readxl")
library("rmarkdown")

apiKey = Sys.getenv("CLIMMOB_API_KEY")
user = "bioversity"

registry = read.csv("protocols.csv", na.strings = "")

ids = NULL # NULL renders every protocol that is not a placeholder

if (is.null(ids)) {
  registry = registry[registry$status != "placeholder", ]
} else {
  registry = registry[registry$protocol_id %in% ids, ]
}

version = paste0("v", Sys.Date())

# shared text in every language
text = read_excel("data/base-text-sop.xlsx", sheet = "text")
other_resources = read_excel("data/base-text-sop.xlsx", sheet = "other_resources")
title = read_excel("data/base-text-sop.xlsx", sheet = "title")

for (k in seq_len(nrow(registry))) {

  protocol_id = registry$protocol_id[k]
  sop = registry$climmob_project_code[k]
  server = registry$climmob_server[k]
  doi = registry$concept_doi[k]
  doi = ifelse(is.na(doi), "[to be completed]", paste0("https://doi.org/", doi))

  protocol_dir = file.path("protocols", protocol_id)
  meta_file = file.path(protocol_dir, "protocol-metadata.xlsx")

  # template name as shown in ClimMob, used inside the SOP text
  template_name = registry$climmob_project_name[k]

  crop_info = read_excel(meta_file, sheet = "crop")

  # languages available for this protocol
  languages = names(crop_info)[-1]
  languages = languages[!is.na(unlist(crop_info[1, languages]))]

  taxa = crop_info$en[crop_info$key == "taxa"]
  autority = crop_info$en[crop_info$key == "autority"]

  plot = read_excel(meta_file, sheet = "plotsize")

  authors = read_excel(meta_file, sheet = "authors")

  # list of centers producing the SOP
  centers = paste(na.omit(unique(c(authors$affiliation_1, authors$affiliation_2))),
                  collapse = ", ")

  authors = paste0(authors$given_name, " ", authors$family_name, " (", authors$role,  ")")
  authors = paste(authors, collapse = ", ")

  output_dir = file.path(protocol_dir, "sop")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  log_dir = file.path(protocol_dir, "logs", version)
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

  for (l in seq_along(languages)) {

    crop_name_i = crop_info[[1, languages[l]]]

    text_i = text[, c(1, which(names(text) %in% languages[l]))]
    names(text_i) = c("section", "text")

    title_i = unlist(title[which(names(title) %in% languages[l])])

    plot_i = unlist(plot[, which(names(plot) %in% languages[l])])

    text_i$text = gsub("`r templatename`", template_name, text_i$text)
    text_i$text = gsub("`r cropname`", crop_name_i, text_i$text)
    text_i$text = gsub("`r plotdimension`", plot_i[1], text_i$text)
    text_i$text = gsub("`r numberplants`", plot_i[2], text_i$text)

    other_resources_i = other_resources[, c(1, which(names(other_resources) %in% languages[l]))]
    other_resources_i = other_resources_i[, c(2, 1)]
    names(other_resources_i) = c("text", "link")

    # survey in the ClimMob template
    survey = getSurvey(apiKey,
                       project = sop,
                       user = user,
                       language = languages[l])

    write.csv(survey,
              file = file.path(log_dir, paste0(protocol_id, "-survey-raw-", languages[l], ".csv")),
              row.names = FALSE)

    # traits assessed in this SOP, the questions farmers answer by ranking
    is_trait = survey$question_desc == "-" | !is.na(survey$question_perfstmt)
    traits = unique(survey$question_name[is_trait])
    survey$question_type = ifelse(is_trait, "ranked trait", "question")

    # data collection moments in the SOP
    collection_moments = unique(survey$form)

    # ranked traits carry a positive and a negative statement, drop the missing one
    statements = ifelse(is.na(survey$question_negstm),
                        survey$question_posstm,
                        paste(survey$question_posstm, survey$question_negstm, sep = "; "))

    survey$question_desc = ifelse(survey$question_desc == "-",
                                  statements,
                                  survey$question_desc)

    survey$question_desc = ifelse(!is.na(survey$question_perfstmt),
                                  survey$question_perfstmt,
                                  survey$question_desc)

    survey$question_desc = gsub("\\{\\{option\\}\\}", "A, B, C", survey$question_desc)

    # drop the package code questions, guarded so an empty match keeps all rows
    rmv = which(survey$question_id %in% c(162, 163))
    if (length(rmv) > 0) survey = survey[-rmv, ]

    # consent and registration questions first, keeping every row so a
    # question asked in several forms stays in each of them
    first = match(c(2290, 199, 206, 2296, 2297, 2298), survey$question_id)
    first = first[!is.na(first)]
    survey = survey[c(first, setdiff(seq_len(nrow(survey)), first)), ]

    survey = survey[, c("form", "question_id", "question_name", "question_type", "question_desc")]

    # clean question list, the machine-readable version of the SOP tables.
    # The copy in the protocol folder is the one agents read, the log keeps history
    for (path in c(protocol_dir, log_dir)) {
      write.csv(survey,
                file = file.path(path, paste0(ifelse(path == log_dir, paste0(protocol_id, "-"), ""),
                                              "questions-", languages[l], ".csv")),
                row.names = FALSE)
    }

    forms = unique(survey$form)
    survey = split(survey, survey$form)
    survey = survey[forms]

    rmarkdown::render(
      input = "script/render-sop.rmd",
      output_dir = output_dir,
      output_format = "word_document",
      output_file = paste0(protocol_id, "-sop-", languages[l], ".docx"),
      params = list(
        languages = toupper(languages[-l]),
        traits = traits,
        crop_name = crop_name_i,
        collection_moments = collection_moments,
        text = text_i,
        other_resources = other_resources_i,
        title = title_i,
        taxa = taxa,
        autority = autority,
        authors = authors,
        centers = centers,
        survey = survey,
        version = version,
        doi = doi),
      envir = new.env())

  }

  run_metadata = tibble(protocol_id = protocol_id,
                        crop = registry$crop[k],
                        sop = sop,
                        template_name = template_name,
                        version = version,
                        date = as.character(Sys.Date()),
                        user = user,
                        server = server,
                        languages = paste(languages, collapse = ", "),
                        r_version = R.version.string,
                        climmobtools_version = as.character(packageVersion("ClimMobTools")))

  write.csv(run_metadata,
            file = file.path(log_dir, paste0(protocol_id, "-run-metadata.csv")),
            row.names = FALSE)

  session = sessioninfo::session_info()

  writeLines(capture.output(session),
             con = file.path(log_dir, paste0(protocol_id, "-run-sessioninfo.txt")))

}
