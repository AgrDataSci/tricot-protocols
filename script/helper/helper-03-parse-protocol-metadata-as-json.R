# Build the DataCite metadata of each protocol as a standalone Zenodo record
#
# Reads protocols/<protocol_id>/protocol-metadata.xlsx and writes
# protocols/<protocol_id>/zenodo-metadata.json. Each record points to the
# collection with IsPartOf, so the standalone SOP and the collection stay linked.
# Placeholders are skipped until their metadata sheet has a version.

library("readxl")
library("jsonlite")

registry = read.csv("protocols.csv", na.strings = "")

licenses = list(
  "mit" = c("MIT License", "https://opensource.org/licenses/MIT"),
  "cc0-1.0" = c("Creative Commons Zero v1.0 Universal", "https://creativecommons.org/publicdomain/zero/1.0/"),
  "cc-by-4.0" = c("Creative Commons Attribution 4.0 International", "https://creativecommons.org/licenses/by/4.0/")
)

base_title = read_excel("data/base-text-sop.xlsx", sheet = "title")$en[1]

for (k in seq_len(nrow(registry))) {

  protocol_id = registry$protocol_id[k]
  file = file.path("protocols", protocol_id, "protocol-metadata.xlsx")

  metadata = read_excel(file, sheet = "metadata")
  authors = read_excel(file, sheet = "authors")
  funders = read_excel(file, sheet = "funders")
  crop = read_excel(file, sheet = "crop")

  get_meta = function(key) {
    val = metadata$value[metadata$key == key]
    if (length(val) == 0 || is.na(val)) return(NULL)
    as.character(val)
  }

  if (is.null(get_meta("version"))) {
    message("Skipping ", protocol_id, ", no version in the metadata sheet")
    next
  }

  # default title follows the Zenodo record of the published SOP
  title = get_meta("title")
  if (is.null(title)) {
    crop_name = crop$en[crop$key == "crop"]
    title = paste0(base_title, ": ", ifelse(length(crop_name) == 0 || is.na(crop_name),
                                            "all crops", crop_name))
  }

  license_id = tolower(get_meta("license"))
  license_info = licenses[[license_id]]
  if (is.null(license_info)) stop("Unknown license in ", file)

  related = list(
    list(relatedIdentifier = get_meta("is_part_of"),
         relatedIdentifierType = "DOI",
         relationType = "IsPartOf"),
    list(relatedIdentifier = get_meta("github_repo"),
         relatedIdentifierType = "URL",
         relationType = "IsSupplementTo")
  )

  datacite = list(
    titles = list(list(title = title)),
    publisher = get_meta("publisher"),
    publicationYear = substr(get_meta("publication_date"), 1, 4),
    resourceType = list(resourceTypeGeneral = get_meta("resource_type_general"),
                        resourceType = "Standard operating procedure"),
    descriptions = list(list(description = get_meta("description"),
                             descriptionType = "Abstract")),
    version = get_meta("version"),
    language = "eng",
    rightsList = list(list(rights = license_info[1],
                           rightsUri = license_info[2],
                           rightsIdentifier = license_id,
                           rightsIdentifierScheme = "SPDX")),
    subjects = lapply(strsplit(get_meta("subjects"), ";\\s*")[[1]],
                      function(s) list(subject = s)),
    relatedIdentifiers = related,
    creators = lapply(seq_len(nrow(authors)), function(i) {
      row = authors[i, ]
      affils = unname(na.omit(unlist(row[, grepl("^affiliation_", names(row))])))
      x = list(name = paste(row$family_name, row$given_name, sep = ", "),
               nameType = "Personal",
               givenName = row$given_name,
               familyName = row$family_name,
               affiliation = as.list(affils))
      if (!is.na(row$orcid)) {
        x$nameIdentifiers = list(list(nameIdentifier = paste0("https://orcid.org/", row$orcid),
                                      nameIdentifierScheme = "ORCID",
                                      schemeUri = "https://orcid.org"))
      }
      x
    })
  )

  if (nrow(funders) > 0) {
    datacite$fundingReferences = lapply(seq_len(nrow(funders)), function(i) {
      row = funders[i, ]
      list(funderName = row$funder_name,
           funderIdentifier = row$funder_identifier,
           awardTitle = row$grant_title,
           awardNumber = row$grant_number)
    })
  }

  write(toJSON(datacite, pretty = TRUE, auto_unbox = TRUE, null = "null"),
        file.path("protocols", protocol_id, "zenodo-metadata.json"))

}
