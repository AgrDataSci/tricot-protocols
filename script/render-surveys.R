library("ClimMobTools")
library("tidyverse")
library("readxl")
library("rmarkdown")

apiKey = Sys.getenv("CLIMMOB_API_KEY")
user = "bioversity"

templates = getProjectsCM(apiKey, server = "1000farms")

crop = "sweetpotato"
sop = "sweetpotat"
template_name = templates$project_name[grep(sop, templates$project_code)]
version = paste0("v", Sys.Date())

languages = c("en", "pt", "fr", "sw", "es")

# read base text table with all the languages available 
text = read_excel("data/base-text-sop.xlsx", sheet = "text")

other_resources = read_excel("data/base-text-sop.xlsx", sheet = "other_resources")

title = read_excel("data/base-text-sop.xlsx", sheet = "title")

# read table with crop information
crop_info = read_excel(paste0("data/", crop, "-heading.xlsx"),
                       sheet = "crop")

taxa = crop_info$en[crop_info$key == "taxa"]

autority = crop_info$en[crop_info$key == "autority"]

# read table with authors and centers information 
authors = read_excel(paste0("data/", crop, "-heading.xlsx"),
                     sheet = "authors")

# list of centers producing the SOPs
centers = paste(na.omit(unique(c(authors$affiliation_1, authors$affiliation_2))),
                collapse = ", ")

authors = paste0(authors$given_name, " ", authors$family_name, " (", authors$role,  ")")

authors = paste(authors, collapse = ", ")

# for (language in languages) {
#   
#   
# }

l = 1


# select crop nome of the respective language
crop_name_i = crop_info[[1, languages[l]]]

# select the text for the respective language
text_index = which(names(text) %in% languages[l])

text_i = text[, c(1, text_index)]

names(text_i) = c("section", "text")

title_index = which(text_i$section %in% "title")

# select the title info for the respective language
title_index = which(names(title) %in% languages[l])

title_i = unlist(title[title_index])

text_i$text = gsub("`r templatename`", template_name, text_i$text)

# select the table with other resources for the respective language
or_index = which(names(other_resources) %in% languages[l])

other_resources_i = other_resources[, c(1, or_index)]

other_resources_i = other_resources_i[,c(2, 1)]

names(other_resources_i) = c("text", "link")

# get list of surveys in the ClimMob template
survey = getSurveyCM(apiKey,
                     project = sop,
                     user = user,
                     language = languages[l])

# identify the traits assessed in this SOP
traits = which(survey$question_desc == "-" | !is.na(survey$question_perfstmt))

traits = unique(survey$question_name[traits])

# identify the data collection moments in the SOP
collection_moments = unique(survey$form)

survey$question_desc = ifelse(survey$question_desc == "-",
                              paste(survey$question_posstm,
                                    survey$question_negstm,
                                    sep = "; "),
                              survey$question_desc)

survey$question_desc = ifelse(!is.na(survey$question_perfstmt),
                              survey$question_perfstmt,
                              survey$question_desc)


survey$question_desc = gsub("\\{\\{option\\}\\}",
                            "A, B, C",
                            survey$question_desc)

rmv = which(survey$question_id %in% c(162, 163))
survey = survey[-rmv, ]

ord = union(c(2290, 199, 206, 2296, 2297, 2298),
            survey$question_id)

ord = match(ord, survey$question_id)

survey = survey[ord, ]

survey = survey[, c(2, 3, 5)]

forms = unique(survey$form)

survey = split(survey, survey$form)

survey = survey[forms]

output_dir = file.path("docs", crop)

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

rmarkdown::render(
  input = "script/render-sop.rmd",
  output_dir = output_dir,
  output_format = "word_document",
  output_file = paste0(crop, "-sop-", languages[l], ".docx"),
  params = list(
    crop = crop,
    language = languages[l],
    languages = toupper(languages[-l]),
    traits = traits,
    collection_moments = collection_moments, 
    text = text_i,
    other_resources = other_resources_i,
    title = title_i,
    crop_name = crop_name_i,
    taxa = taxa,
    autority = autority,
    authors = authors,
    centers = centers,
    survey = survey,
    version = version),
  envir = new.env())


