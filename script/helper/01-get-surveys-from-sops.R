library(ClimMobTools)
library(tidyverse)
apiKey = Sys.getenv("CLIMMOB_API_KEY")
user = "bioversity"

sops = getProjectsCM(apiKey, server = "1000farms")

surveys = data.frame()

for(i in seq_along(sops$project_id)){

  s = getSurveyCM(apiKey, project = sops$project_code[i], user, language = "pt")
  
  s$project_name = sops$project_name[i]
  
  s$project_code = sops$project_code[i]
  
  index = c(1, union(ncol(s), 2:ncol(s)))
  
  s = s[index]
  
  surveys = rbind(surveys, s)
    
}


keep = surveys$project_code == "sweetpotat" 

y = surveys[keep, ]

keep = !duplicated(y$question_id)

y = y[keep, ]

write_csv(surveys, 'data/surveys-sops-1000farms.csv')















