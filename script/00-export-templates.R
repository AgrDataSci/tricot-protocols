# Export ClimMob project templates as template CSV files
#
# For every protocol in protocols.csv that is not a placeholder, reads its
# ClimMob template (registration, data collection moments, groups, questions,
# statements and options) and writes
#   protocols/<protocol_id>/template.csv
# The format is described in script/helper/helper-05-template-csv.R. A
# template CSV can be pushed back to ClimMob as a new project with
# script/03-push-template-to-climmob.R.
#
# Only reads from ClimMob. Requires the ClimMob API key in the CLIMMOB_API_KEY
# environment variable, for example in .Renviron. Never write the key here.
#
# Set `ids` to export only some protocols, and `deployments` to also export
# projects that are not in protocols.csv.

source("script/helper/helper-04-climmob-api.R")
source("script/helper/helper-05-template-csv.R")

owner = "bioversity"

registry = read.csv("protocols.csv", na.strings = "", colClasses = "character")

ids = NULL # NULL exports every protocol that is not a placeholder

if (is.null(ids)) {
  registry = registry[registry$status != "placeholder", ]
} else {
  registry = registry[registry$protocol_id %in% ids, ]
}

# projects outside protocols.csv: server, project code and output file
deployments = list(
  list(server = "1000farms", project_cod = "chickpea",
       file = "deployments/chickpea/template.csv")
)

jobs = c(lapply(seq_len(nrow(registry)), function(k) {
  list(server = registry$climmob_server[k],
       project_cod = registry$climmob_project_code[k],
       file = file.path("protocols", registry$protocol_id[k], "template.csv"))
}), deployments)

key = Sys.getenv("CLIMMOB_API_KEY")
clients = list()

for (j in jobs) {
  if (is.null(clients[[j$server]])) {
    clients[[j$server]] = cm_client(key, j$server, dry_run = TRUE)
  }
  cm = clients[[j$server]]
  tpl = tryCatch(export_template(cm, j$project_cod, owner),
                 error = function(e) {
                   message("Skipped ", j$project_cod, ": ", conditionMessage(e))
                   NULL
                 })
  if (is.null(tpl) || nrow(tpl) == 0) next
  write_template(tpl, j$file)
  message("Wrote ", j$file, " (", nrow(tpl), " questions, ",
          length(unique(tpl$form)), " forms)")
}
