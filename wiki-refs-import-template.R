# Wiki References Import Template
# ================================
#
# Customize the parameters below to extract references from any Wikipedia page
# and import them into Zotero.
#

library(tidyverse)
library(stringi)
library(httr2)
library(c2z)

source("wiki-refs-to-zotero.R")

# =============================================================================
# *** CUSTOMIZE THESE PARAMETERS ***
# =============================================================================

# Wikipedia page title (use underscores for spaces, e.g., "Albert_Einstein")
WIKIPEDIA_PAGE <- "Meiō_incident"

# Wikipedia language edition (default: "en" for English)
WIKIPEDIA_LANG <- "en"

# Name for the Zotero collection (default: WIKIPEDIA_PAGE with spaces)
ZOTERO_COLLECTION <- "Meiō incident"

# =============================================================================
# DO NOT EDIT BELOW THIS LINE
# =============================================================================

ZOTERO_USER_ID <- Sys.getenv("ZOTERO_USER_ID")
ZOTERO_API_KEY <- Sys.getenv("ZOTERO_API_KEY")

if (!nzchar(ZOTERO_USER_ID) || !nzchar(ZOTERO_API_KEY)) {
  stop(
    "Zotero credentials not configured.\n\n",
    "Set these environment variables (in .Renviron or interactively):\n",
    "  ZOTERO_USER_ID = your_user_id\n",
    "  ZOTERO_API_KEY = your_api_key\n\n",
    "Find your user ID at: https://www.zotero.org/settings/keys"
  )
}

# =============================================================================
# Step 1: Extract and parse (dry run)
# =============================================================================

message(sprintf("\n>>> Extracting references from: %s\n", WIKIPEDIA_PAGE))

refs <- wiki_refs_pipeline(
  page_name       = WIKIPEDIA_PAGE,
  language        = WIKIPEDIA_LANG,
  enrich          = TRUE,
  zotero_import   = FALSE,
  check_existing  = FALSE,
  dry_run         = TRUE
)

if (nrow(refs) == 0) {
  stop("No references found. Check the page name and try again.")
}

message(sprintf("\n>>> Extracted %d unique references\n", nrow(refs)))

# =============================================================================
# Step 2: Inspect results
# =============================================================================

message("\n>>> Reference breakdown by type:\n")
print(refs |> count(itemType, sort = TRUE))

message("\n>>> Enrichment summary:\n")
print(refs |> count(.enrich_status))

# Flag anything unusual
issues <- refs |>
  filter(is.na(title) | itemType == "document" | .enrich_status == "failed")

if (nrow(issues) > 0) {
  message(sprintf("\n!!! %d reference(s) may need manual review:\n", nrow(issues)))
  print(
    issues |>
      select(itemType, first_author, year, title, .enrich_status)
  )
}

# =============================================================================
# Step 3: Check library for duplicates
# =============================================================================

message("\n>>> Checking Zotero library for existing items...\n")

refs <- check_library_for_refs(
  refs,
  user_id = ZOTERO_USER_ID,
  api_key = ZOTERO_API_KEY
)

n_new   <- sum(refs$import_action == "create_new")
n_exist <- sum(refs$import_action == "add_to_collection")

message(sprintf(
  "\n>>> Ready to import: %d new + %d existing = %d total\n",
  n_new, n_exist, nrow(refs)
))

# =============================================================================
# Step 4: Import to Zotero (uncomment to proceed)
# =============================================================================

message(sprintf(
  "\n>>> To complete the import, uncomment and run:\n\n",
  "result <- post_refs_to_zotero(\n",
  "  refs,\n",
  "  collection_name = \"", ZOTERO_COLLECTION, "\",\n",
  "  user_id         = \"", ZOTERO_USER_ID, "\",\n",
  "  api_key         = Sys.getenv(\"ZOTERO_API_KEY\")\n",
  ")\n"
))

# Uncomment these lines to post:
# result <- post_refs_to_zotero(
#   refs,
#   collection_name = ZOTERO_COLLECTION,
#   user_id         = ZOTERO_USER_ID,
#   api_key         = ZOTERO_API_KEY
# )
# message("\n>>> Import complete!")

# =============================================================================
# Optional: Export to RIS
# =============================================================================

# Uncomment to export (useful for other reference managers):
# export_ris(refs, paste0(tolower(WIKIPEDIA_PAGE), ".ris"))
