# Convert ODK XLSForms into a template CSV
#
# For deployments that start from ODK forms. Reads one registration form and
# one or more data collection forms (English labels), collapses ODK rows into
# ClimMob questions (rankings, questions asked for each option, comparisons
# with the farmer's variety, "other" options) and writes one template CSV.
# Review and edit the CSV, then push it with
# script/03-push-template-to-climmob.R.
#
# Does not need the ClimMob API.

source("script/helper/helper-04-climmob-api.R")
source("script/helper/helper-05-template-csv.R")

conversion = list(
  forms_dir = "deployments/chickpea/forms",
  output = "deployments/chickpea/template.csv",
  forms = list(
    list(file = "registration_tumkur_chickpea_2025.xlsx", type = "registration"),
    list(file = "afterrep_tumkur_chickpea_v1.xlsx", type = "assessment",
         ass_desc = "After reproduction", ass_days = "1", ass_final = 0),
    list(file = "postharv_tumkur_chickpea_v1.xlsx", type = "assessment",
         ass_desc = "Post harvest", ass_days = "2", ass_final = 1)
  ),
  # XLSForm names to leave out
  skip = c("chickpea_tumkur_2025_reg", "chickpea_tumkur_2025_afterrep",
           "chickpea_tumkur_2025_posthar"),
  # question code -> library question_id, to force a match
  use_id = c(package_code = 162)
)

rows = list()
for (form in conversion$forms) {
  is_reg = form$type == "registration"
  label = if (is_reg) "Registration" else form$ass_desc
  qs = parse_xlsform(file.path(conversion$forms_dir, form$file),
                     skip = conversion$skip, use_id = conversion$use_id)
  for (q in qs) {
    # ClimMob's own package and participant questions
    if (!is.na(q$use_id) && q$use_id %in% c(162, 163)) {
      q$dtype = if (q$use_id == 162) 7 else 8
    }
    rows[[length(rows) + 1]] = question_to_row(
      q, label, if (is_reg) "registration" else "assessment",
      if (is_reg) NA else form$ass_days, if (is_reg) NA else form$ass_final)
  }
}

tpl = do.call(rbind, rows)
write_template(tpl, conversion$output)
message("Wrote ", conversion$output, " (", nrow(tpl), " questions)")
