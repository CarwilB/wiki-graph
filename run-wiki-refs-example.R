# Quick-start example: Extract references from a Wikipedia page
# ===============================================================
#
# This script demonstrates the complete workflow on a well-referenced
# Wikipedia article (Meiō incident). Uncomment the final post_refs_to_zotero()
# call to actually import to Zotero.
#
# Before running, ensure:
#   1. wiki-refs-to-zotero.R is in your working directory
#   2. ZOTERO_USER_ID and ZOTERO_API_KEY are in your .Renviron
#

library(tidyverse)
library(stringi)
library(httr2)
library(c2z)

source("wiki-refs-to-zotero.R")

# =============================================================================
# Parameters
# =============================================================================

PAGE_NAME       <- "Meiō_incident"
WIKIPEDIA_LANG  <- "en"
COLLECTION_NAME <- "Meiō incident"

# Get credentials from environment
ZOTERO_USER_ID <- Sys.getenv("ZOTERO_USER_ID")
ZOTERO_API_KEY <- Sys.getenv("ZOTERO_API_KEY")

# =============================================================================
# Phase 1: Extract, deduplicate, and enrich (dry run, no Zotero writes)
# =============================================================================

message("=== PHASE 1: Parse & Enrich (Dry Run) ===\n")

refs <- wiki_refs_pipeline(
  page_name      = PAGE_NAME,
  language       = WIKIPEDIA_LANG,
  enrich         = TRUE,
  zotero_import  = FALSE,
  dry_run        = TRUE
)

# =============================================================================
# Phase 2: Inspect results
# =============================================================================

message("\n=== PHASE 2: Inspect Results ===\n")

# Reference types
message("Reference types:")
refs |> count(itemType, sort = TRUE) |> print()

# Sample of first 10
message("\nFirst 10 references:")
refs |>
  select(itemType, first_author, year, title) |>
  head(10) |>
  print()

# Enrichment status
message("\nEnrichment status:")
refs |> count(.enrich_status) |> print()

# Flag any problematic rows
problem_rows <- refs |>
  filter(is.na(title) | itemType == "document" | .enrich_status == "failed")

if (nrow(problem_rows) > 0) {
  message("\nPotential issues (review before importing):")
  problem_rows |>
    select(itemType, first_author, year, title, DOI, ISBN, .enrich_status) |>
    print()
} else {
  message("\nNo obvious issues detected.\n")
}

# =============================================================================
# Phase 3: Check library for duplicates (optional, but recommended)
# =============================================================================

if (nzchar(ZOTERO_USER_ID) && nzchar(ZOTERO_API_KEY)) {
  message("\n=== PHASE 3: Check for Existing Items ===\n")

  refs <- check_library_for_refs(
    refs,
    user_id = ZOTERO_USER_ID,
    api_key = ZOTERO_API_KEY
  )

  message("\nImport actions:")
  refs |> count(import_action) |> print()

  new_count   <- sum(refs$import_action == "create_new")
  exist_count <- sum(refs$import_action == "add_to_collection")
  message(
    sprintf(
      "\nReady to import: %d new items + %d existing items = %d total",
      new_count, exist_count, nrow(refs)
    )
  )
}

# =============================================================================
# Phase 4: Post to Zotero (uncomment to actually import)
# =============================================================================

message("\n=== PHASE 4: Ready to Import ===\n")

if (nzchar(ZOTERO_USER_ID) && nzchar(ZOTERO_API_KEY)) {
  message("To import to Zotero, run:\n")
  message(
    sprintf(
      'result <- post_refs_to_zotero(refs, collection_name = "%s", user_id = "%s", api_key = Sys.getenv("ZOTERO_API_KEY"))',
      COLLECTION_NAME, ZOTERO_USER_ID
    )
  )
  message("\n")

  # Uncomment to actually post:
  # result <- post_refs_to_zotero(
  #   refs,
  #   collection_name = COLLECTION_NAME,
  #   user_id         = ZOTERO_USER_ID,
  #   api_key         = ZOTERO_API_KEY
  # )
  # message("\nImport complete!")
} else {
  message("Zotero credentials not found in .Renviron\n")
}

# =============================================================================
# Phase 5: Export to RIS (optional)
# =============================================================================

message("\nTo export to RIS (for other reference managers):\n")
message('export_ris(refs, "meio_incident.ris")\n')

# =============================================================================
# Summary
# =============================================================================

message("\n=== SUMMARY ===\n")
message(sprintf("Page: %s (%s)\n", PAGE_NAME, WIKIPEDIA_LANG))
message(sprintf("Total unique references: %d\n", nrow(refs)))
message(sprintf("Item types: %s\n", paste(unique(refs$itemType), collapse = ", ")))
message("\nReferences stored in: refs (tibble)\n")
