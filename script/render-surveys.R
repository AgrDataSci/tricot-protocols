library("ClimMobTools")
library("tidyverse")
library("readxl")

apiKey = "20abbf14-841a-4ae2-bc4f-5c0c051b2d8e"
user = "bioversity"
sop = "sweetpotat"
crop = "sweetpotato"
languages = c("en", "pt")

title = read_excel(paste0("data/", crop, "-", "heading.xlsx"), sheet = "title")

crop_info = read_excel(paste0("data/", crop, "-", "heading.xlsx"), sheet = "crop")

authors = read_excel(paste0("data/", crop, "-", "heading.xlsx"), sheet = "authors")

centers = paste(sort(unique(c(authors$affiliation_1, authors$affiliation_2))), collapse = ", ")

authors = paste0(authors$given_name, " ",  authors$family_name, " (", authors$role, ")")

authors = paste(authors, collapse = ", ")


# get surveys from ClimMob
survey = getSurveyCM(apiKey, project = sop, user, language = languages[2])

survey$question_desc = ifelse(survey$question_desc == "-", 
                              paste(survey$question_posstm, survey$question_negstm, sep = "; "),
                              survey$question_desc)


survey$question_desc = ifelse(!is.na(survey$question_perfstmt), 
                              survey$question_perfstmt,
                              survey$question_desc)

survey$question_desc = gsub("\\{\\{option\\}\\}", "A, B, C", survey$question_desc)

survey = survey[, c(1, 2, 3, 5)]

rmv = grep(163, survey$question_id)

survey = survey[-rmv, ]

ord = union(c(2290, 162, 199, 206, 2296, 2297, 2298), survey$question_id)

ord = match(ord, survey$question_id)

survey = survey[ord, ]

survey = split(survey, survey$form)



