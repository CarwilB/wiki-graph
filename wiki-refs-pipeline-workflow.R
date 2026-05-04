# Wiki References to Zotero Workflow
# ====================================
# An interactive script implementing the vignette workflow:
# 1. Dry run (fetch, parse, enrich)
# 2. Inspect results
# 3. Check library for existing items
# 4. Post to Zotero
# 5. Retrieve Zotero keys

library(tidyverse)
library(stringi)
library(httr2)
library(c2z)

source("wiki-refs-to-zotero.R")

# =============================================================================
# STEP 1: Configure your environment
# =============================================================================

# Check for Zotero credentials in environment
ZOTERO_USER_ID <- Sys.getenv("ZOTERO_USER_ID")
ZOTERO_API_KEY <- Sys.getenv("ZOTERO_API_KEY")

if (!nzchar(ZOTERO_USER_ID) || !nzchar(ZOTERO_API_KEY)) {
  warning(
    "Zotero credentials not found in environment.\n",
    "Set ZOTERO_USER_ID and ZOTERO_API_KEY in .Renviron to use this workflow.\n",
    "Your Zotero user ID is in your profile URL: https://www.zotero.org/yourname"
  )
}

# =============================================================================
# STEP 2: Specify the Wikipedia page to extract references from
# =============================================================================

# EDIT THESE PARAMETERS:
page_name <- "Meiō_incident"           # Wikipedia page title (underscores for spaces)
language  <- "en"                      # Wikipedia language code
collection_name <- "Meiō incident"     # Name for new Zotero collection (default: page_name with spaces)

cat("\n--- Wikipedia Page Configuration ---\n")
cat("Page:", page_name, "\n")
cat("Language:", language, "\n")
cat("Target collection:", collection_name, "\n\n")

# =============================================================================
# STEP 3: DRY RUN — Fetch, parse, and enrich without touching Zotero
# =============================================================================

cat("--- STEP 1: Dry Run (Parse & Enrich) ---\n")
cat("This fetches Wikipedia and parses citations without writing to Zotero.\n\n")

refs <- wiki_refs_pipeline(
  page_name      = page_name,
  language       = language,
  enrich         = TRUE,          # Enrich metadata via DOI/ISBN
  zotero_import  = FALSE,         # Don't touch Zotero yet
  dry_run        = TRUE           # Nothing is written
)

# =============================================================================
# STEP 4: Inspect the parsed references
# =============================================================================

cat("\n--- STEP 2: Inspect Results ---\n")

# Overview of reference types
cat("\nReference types found:\n")
print(refs |> count(itemType, sort = TRUE))

# Quick look at first few rows
cat("\nFirst 10 references:\n")
print(
  refs |>
    select(itemType, first_author, year, title) |>
    head(10)
)

# Check enrichment outcomes
cat("\nEnrichment status:\n")
print(refs |> count(.enrich_status))

# Identify any problematic rows
problem_rows <- refs |>
  filter(is.na(title) | itemType == "document" | .enrich_status == "failed")

if (nrow(problem_rows) > 0) {
  cat("\nPotential issues found:\n")
  print(
    problem_rows |>
      select(itemType, first_author, year, title, DOI, ISBN, .enrich_status)
  )
} else {
  cat("\nNo obvious issues detected.\n")
}

# =============================================================================
# STEP 5: (OPTIONAL) Edit refs before importing
# =============================================================================

cat("\n--- STEP 3: Edit References (if needed) ---\n")
cat("The `refs` tibble is now in memory. You can modify it with dplyr:\n")
cat("  refs <- refs |> filter(...) |> mutate(...)\n\n")

# Example: fix a known title
# refs <- refs |>
#   mutate(title = if_else(
#     first_author == "Smith" & year == "2003",
#     "The corrected title",
#     title
#   ))

# =============================================================================
# STEP 6: Check for existing items in Zotero library
# =============================================================================

cat("--- STEP 4: Check Library for Duplicates ---\n")
cat("This scans your Zotero library for existing items matching these references.\n\n")

if (nzchar(ZOTERO_USER_ID) && nzchar(ZOTERO_API_KEY)) {
  refs <- check_library_for_refs(
    refs,
    user_id = ZOTERO_USER_ID,
    api_key = ZOTERO_API_KEY
  )

  cat("\nDuplicate check complete.\n")
  cat("import_action value counts:\n")
  print(refs |> count(import_action))

  if (any(refs$import_action == "add_to_collection")) {
    cat("\nExisting items to be added to collection:\n")
    print(
      refs |>
        filter(import_action == "add_to_collection") |>
        select(first_author, year, title, duplicate_how)
    )
  }
} else {
  cat("Skipping duplicate check (Zotero credentials not configured).\n")
}

# =============================================================================
# STEP 7: Post to Zotero
# =============================================================================

cat("\n--- STEP 5: Post to Zotero ---\n")
cat("When ready, run:\n\n")
cat("  result <- post_refs_to_zotero(\n")
cat("    refs,\n")
cat("    collection_name = \"", collection_name, "\",\n", sep = "")
cat("    user_id         = Sys.getenv(\"ZOTERO_USER_ID\"),\n")
cat("    api_key         = Sys.getenv(\"ZOTERO_API_KEY\")\n")
cat("  )\n\n")

# Example (commented out):
# if (nzchar(ZOTERO_USER_ID) && nzchar(ZOTERO_API_KEY)) {
#   result <- post_refs_to_zotero(
#     refs,
#     collection_name = collection_name,
#     user_id         = ZOTERO_USER_ID,
#     api_key         = ZOTERO_API_KEY
#   )
# }

# =============================================================================
# STEP 8: (OPTIONAL) Fetch Zotero keys after import
# =============================================================================

cat("\nTo retrieve Zotero keys after import, you'll need the collection key.\n")
cat("Find it via:\n\n")
cat("  request(\"https://api.zotero.org\") |>\n")
cat("    req_url_path_append(\"users\", Sys.getenv(\"ZOTERO_USER_ID\"), \"collections\") |>\n")
cat("    req_headers(\n")
cat("      `Zotero-API-Version` = \"3\",\n")
cat("      Authorization = paste(\"Bearer\", Sys.getenv(\"ZOTERO_API_KEY\"))\n")
cat("    ) |>\n")
cat("    req_perform() |>\n")
cat("    resp_body_json(simplifyVector = TRUE) |>\n")
cat("    (\\(x) tibble(key = x$key, name = x$data$name))() |>\n")
cat("    filter(name == \"", collection_name, "\")\n\n", sep = "")

# Then:
cat("  refs_with_keys <- fetch_zotero_keys(\n")
cat("    refs,\n")
cat("    user_id        = Sys.getenv(\"ZOTERO_USER_ID\"),\n")
cat("    api_key        = Sys.getenv(\"ZOTERO_API_KEY\"),\n")
cat("    collection_key = \"XXXXXXXX\"   # 8-char key from above\n")
cat("  )\n\n")

# =============================================================================
# STEP 9: (OPTIONAL) Export to RIS
# =============================================================================

cat("\n--- Optional: Export to RIS ---\n")
cat("To export for import into other reference managers:\n\n")
cat("  export_ris(refs, \"my_references.ris\")\n\n")

# =============================================================================
# Summary
# =============================================================================

cat("\n=== WORKFLOW SUMMARY ===\n")
cat(sprintf("Page extracted: %s (%s)\n", page_name, language))
cat(sprintf("Total references (after dedup): %d\n", nrow(refs)))
cat(sprintf("Reference types: %s\n",
            paste(unique(refs$itemType), collapse = ", ")))

if ("import_action" %in% names(refs)) {
  n_new <- sum(refs$import_action == "create_new")
  n_exist <- sum(refs$import_action == "add_to_collection")
  cat(sprintf("Ready to import: %d new + %d existing = %d total\n",
              n_new, n_exist, nrow(refs)))
}

cat("\nReferences are stored in: refs (tibble in memory)\n")
cat("Status attributes: attr(refs, '.pipeline_status')\n\n")
