# Convert the rendered SOPs from docx to pdf
#
# The docx stays the editable source, styled by script/word-template.docx.
# The pdf is the format published on Zenodo. Conversion runs through
# LibreOffice, which keeps the template's header, logos and styles.
#
# Run script/01-render-protocols.R first. This script converts every
# protocols/<protocol_id>/sop/<protocol_id>-sop-<lang>.docx into a pdf in the
# same folder. Set `ids` to convert only some protocols, and `languages` to
# convert only some languages, e.g. languages = c("en", "fr").
#
# Requires LibreOffice (https://www.libreoffice.org). Install it once, no R
# package is needed.

registry = read.csv("protocols.csv", na.strings = "")

ids = NULL # NULL converts every protocol that has rendered SOPs
languages = NULL # NULL converts every language available

# find the LibreOffice executable on Linux, macOS or Windows
find_soffice = function() {
  candidates = c(Sys.which("soffice"),
                 Sys.which("libreoffice"),
                 "/Applications/LibreOffice.app/Contents/MacOS/soffice",
                 "C:/Program Files/LibreOffice/program/soffice.exe",
                 "C:/Program Files (x86)/LibreOffice/program/soffice.exe")
  candidates = candidates[nzchar(candidates) & file.exists(candidates)]
  if (length(candidates) == 0) {
    stop("LibreOffice not found. Install it from https://www.libreoffice.org ",
         "or add soffice to your PATH.")
  }
  candidates[1]
}

soffice = find_soffice()

# quote paths the way the shell of this system expects
quote = function(x) shQuote(x, type = ifelse(.Platform$OS.type == "windows", "cmd", "sh"))

if (is.null(ids)) ids = registry$protocol_id

for (protocol_id in ids) {

  sop_dir = file.path("protocols", protocol_id, "sop")

  docx = list.files(sop_dir, pattern = "\\.docx$", full.names = TRUE)

  # skip Word lock files left open by an editor
  docx = docx[!grepl("^~\\$", basename(docx))]

  if (!is.null(languages)) {
    lang = sub(".*-sop-([a-z]+)\\.docx$", "\\1", basename(docx))
    docx = docx[lang %in% languages]
  }

  if (length(docx) == 0) next

  for (f in docx) {

    # a separate profile directory lets the conversion run while LibreOffice is open
    profile = paste0("-env:UserInstallation=file:///",
                     gsub("\\\\", "/", normalizePath(tempdir(), mustWork = FALSE)),
                     "/lo-profile")

    status = system2(soffice,
                     args = c(profile, "--headless", "--convert-to", "pdf",
                              "--outdir", quote(sop_dir), quote(f)),
                     stdout = FALSE, stderr = FALSE)

    pdf = sub("\\.docx$", ".pdf", f)

    if (status != 0 || !file.exists(pdf)) {
      warning("Conversion failed for ", f)
    } else {
      message("Wrote ", pdf)
    }

  }

}
