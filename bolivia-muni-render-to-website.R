# Render Bolivia municipality tools and copy to quarto-website/tools/
#
# Run this script (instead of rendering the .qmd files directly) to keep the
# quarto-website tools directory up to date.
#
# Usage: source("render-to-website.R")

tools_dir <- here::here("../quarto-website/tools")

# 1. Generator (article content) — render first so it writes the
#    output/bolivia-municipality-wikitext/*.txt files used by the infobox page.
quarto::quarto_render("bolivia-muni-generator-en.qmd")
file.copy("bolivia-muni-generator-en.html",
          file.path(tools_dir, "bolivia-muni-generator-en.html"),
          overwrite = TRUE)
message("Copied bolivia-muni-generator-en.html to quarto-website/tools/")

# 2. Infobox — render second so it can read the wikitext files written above.
quarto::quarto_render("bolivia-muni-infobox-en.qmd")
file.copy("bolivia-muni-infobox-en.html",
          file.path(tools_dir, "bolivia-muni-infobox-en.html"),
          overwrite = TRUE)
message("Copied bolivia-muni-infobox-en.html to quarto-website/tools/")
