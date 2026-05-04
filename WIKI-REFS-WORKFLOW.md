# Wiki References to Zotero — Complete Workflow

This document outlines the complete workflow for extracting references from Wikipedia and importing them into Zotero. Three new files have been created to support this:

1. **`wiki-refs-pipeline-workflow.R`** — Interactive script with detailed comments
2. **`run-wiki-refs-example.R`** — Ready-to-run example (Meiō incident)
3. **`wiki-refs-import-template.R`** — Customizable template for any Wikipedia page
4. **`WIKI-REFS-QUICKSTART.md`** — Quick reference guide

## Workflow Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE 1: EXTRACT & PARSE (No Zotero writes yet)                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ 1. Fetch wikitext from Wikipedia                                        │
│    └─> wiki_refs_pipeline(..., dry_run = TRUE)                         │
│                                                                          │
│ 2. Extract citation templates ({{Cite book}}, {{harvc}}, etc.)          │
│    └─> Finds 48+ templates, deduplicates to ~44 unique refs            │
│                                                                          │
│ 3. Enrich metadata via DOI/ISBN lookups (optional)                      │
│    └─> c2z::ZoteroDoi() and c2z::ZoteroIsbn()                          │
│    └─> Fills in publisher, date, authors from CrossRef/ISBN APIs       │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
                                ↓
                    `refs` tibble in memory
                  (inspect, filter, edit here)
                                ↓
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE 2: CHECK LIBRARY (Optional but recommended)                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ check_library_for_refs(refs, user_id, api_key)                         │
│   ├─> Match by DOI                                                      │
│   ├─> Match by ISBN                                                     │
│   └─> Match by normalized (title + year)                               │
│                                                                          │
│ Result: refs now have columns:                                          │
│   ├─ import_action: "create_new" or "add_to_collection"                │
│   ├─ existing_key: Zotero item key (if match found)                    │
│   └─ duplicate_how: "DOI", "ISBN", "title + year", or NA               │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
                                ↓
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE 3: IMPORT TO ZOTERO                                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ post_refs_to_zotero(refs, collection_name, user_id, api_key)          │
│                                                                          │
│ 1. Creates a new Zotero collection (named per collection_name)         │
│ 2. Posts new refs (import_action == "create_new")                      │
│ 3. Adds existing refs to collection (import_action == "add...")        │
│                                                                          │
│ Result: All refs are in Zotero, organized in the new collection        │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
                                ↓
         (Optional: Retrieve Zotero keys for citations)
                fetch_zotero_keys(refs, ...)
```

## Quick Start

### Minimal Example (5 lines)

```r
source("wiki-refs-to-zotero.R")

refs <- wiki_refs_pipeline("Elizabeth_Lyon_(criminal)", dry_run = TRUE)
refs |> select(itemType, first_author, year, title) |> head(10)
# ... inspect, then ...
post_refs_to_zotero(refs, collection_name = "Elizabeth Lyon", 
                     user_id = Sys.getenv("ZOTERO_USER_ID"),
                     api_key = Sys.getenv("ZOTERO_API_KEY"))
```

### Complete Example (with checks)

```r
source("wiki-refs-to-zotero.R")

# Step 1: Extract & enrich (dry run)
refs <- wiki_refs_pipeline(
  page_name      = "Elizabeth_Lyon_(criminal)",
  enrich         = TRUE,
  dry_run        = TRUE
)

# Step 2: Inspect
refs |> count(itemType, sort = TRUE)
refs |> filter(is.na(title) | .enrich_status == "failed")

# Step 3: Check for duplicates
refs <- check_library_for_refs(
  refs,
  user_id = Sys.getenv("ZOTERO_USER_ID"),
  api_key = Sys.getenv("ZOTERO_API_KEY")
)
refs |> count(import_action)

# Step 4: Import
result <- post_refs_to_zotero(
  refs,
  collection_name = "Elizabeth Lyon (criminal)",
  user_id         = Sys.getenv("ZOTERO_USER_ID"),
  api_key         = Sys.getenv("ZOTERO_API_KEY")
)
```

## Key Functions

| Function | Purpose | Dry Run | Zotero Write |
|----------|---------|---------|--------------|
| `wiki_refs_pipeline()` | Main entry point; orchestrates all steps | ✓ | ✓ |
| `fetch_wikitext()` | Download raw Wikipedia source | — | — |
| `extract_refs_from_wikitext()` | Parse citation templates | — | — |
| `deduplicate_refs()` | Remove duplicate citations | — | — |
| `enrich_refs()` | Enrich via DOI/ISBN lookups | — | — |
| `check_library_for_refs()` | Query Zotero for existing items | — | — |
| `import_to_zotero()` | Create collection & post items | ✓ | ✓ |
| `post_refs_to_zotero()` | Quick post after dry run | — | ✓ |
| `fetch_zotero_keys()` | Retrieve Zotero keys after import | — | — |
| `export_ris()` | Export to RIS format | — | — |

## Data Flow

```
Wikipedia page title
    ↓
fetch_wikitext()
    ↓
Raw wikitext (e.g., 50,000+ characters)
    ↓
extract_refs_from_wikitext()
    ├─> extract_all_citations()
    ├─> parse_template_params()
    └─> template_to_ref()
    ↓
Raw refs tibble (one row per template, ~48 refs)
    ├─ itemType (book, journalArticle, etc.)
    ├─ title, creators, date, year
    ├─ DOI, ISBN, publisher, volume, issue, pages, etc.
    ├─ .template_name, .raw_template
    └─ first_author (display column)
    ↓
deduplicate_refs()
    ├─> dedup_key() — normalize by last name + year + title
    └─> Remove exact duplicates (keep first, count citations)
    ↓
Unique refs tibble (~44 refs)
    ├─ All columns from above
    ├─ .dedup_key (normalized)
    ├─ n_citations (how many times this ref appeared)
    └─ .enrich_status (skipped, doi, isbn, or failed) [if enriched]
    ↓
(Optional: enrich_refs())
    ├─> For each DOI/ISBN: call c2z::ZoteroDoi() or c2z::ZoteroIsbn()
    └─> Overlay richer metadata (authors, publisher, pages, etc.)
    ↓
(Optional: check_library_for_refs())
    ├─> Fetch all items from Zotero library
    ├─> Match each ref by DOI → ISBN → (title + year)
    └─> Add columns: existing_key, import_action, duplicate_how
    ↓
(Optional: export_ris())
    └─> Write refs to RIS file (for other reference managers)
    ↓
(If zotero_import = TRUE: import_to_zotero())
    ├─> refs_to_zotero_items()
    │   └─> Convert each row to Zotero API item format
    ├─> Create new collection
    ├─> POST new items
    └─> (If existing items) add them to the new collection
    ↓
Updated refs tibble with columns:
    ├─ zotero_key (if fetch_keys = TRUE)
    └─ zotero_match ("doi", "isbn", "title_year", or "unmatched")
```

## Inspect & Edit Pattern

Before importing, use dplyr to inspect and optionally edit:

```r
# View structure
refs
str(refs)

# Count by type
refs |> count(itemType)

# Find issues
refs |> filter(is.na(title))
refs |> filter(itemType == "document")  # catch-all, often needs manual review
refs |> filter(.enrich_status == "failed")

# Edit if needed
refs <- refs |>
  filter(itemType != "document" | !is.na(title)) |>  # Remove bad ones
  mutate(
    title = if_else(
      first_author == "Smith" & year == "2003",
      "Corrected Title",
      title
    )
  )

# Check enrichment
refs |> count(.enrich_status)
refs |> filter(.enrich_status == "skipped") |>
  select(first_author, year, title, DOI, ISBN)
```

## Dealing with Duplicates

### No Duplicate Check
```r
refs <- wiki_refs_pipeline(..., check_existing = FALSE, dry_run = FALSE)
# All refs imported as new items (may create duplicates if already in library)
```

### With Duplicate Check (Recommended)
```r
refs <- wiki_refs_pipeline(..., check_existing = TRUE, dry_run = FALSE)
# Matches found are added to collection instead of re-created
# Shows side-by-side comparison for each match
```

### Manual Check After Parsing
```r
refs <- wiki_refs_pipeline(..., dry_run = TRUE)
refs <- check_library_for_refs(refs, user_id, api_key)
refs |> filter(import_action == "add_to_collection")  # See matches
# ... or edit refs ...
post_refs_to_zotero(refs, ...)
```

## RIS Export

Export parsed references for import into other reference managers:

```r
refs <- wiki_refs_pipeline("My_Page", enrich = TRUE, dry_run = TRUE)
export_ris(refs, "my_page_references.ris")
# File can now be imported into Mendeley, EndNote, Zotero, etc.
```

## Non-English Wikipedia

The pipeline works with any Wikipedia language edition:

```r
# Spanish Wikipedia
refs <- wiki_refs_pipeline(
  page_name = "Jorge Luis Borges",
  language  = "es",
  dry_run   = TRUE
)

# German Wikipedia
refs <- wiki_refs_pipeline(
  page_name = "Albert_Einstein",
  language  = "de",
  dry_run   = TRUE
)
```

## Troubleshooting

### No references found
**Symptom**: "No citation templates found"
**Cause**: Page uses {{sfn}} author-date style without a "References" section
**Fix**: Check the raw wikitext (`fetch_wikitext(page)` directly); article needs {{Cite ...}} templates in a References/Sources section

### Many "document" items
**Symptom**: High count of `itemType == "document"`
**Cause**: Template names not recognized by the parser
**Fix**: Check `.template_name` column; edit `cite_patterns` in `wiki-refs-to-zotero.R` if needed

### Enrichment failures
**Symptom**: `.enrich_status == "failed"`
**Cause**: DOI/ISBN is not in CrossRef database
**Fix**: No automated fix; manually edit the row before importing

### Zotero API 403 error
**Symptom**: "API key lacks write permission"
**Cause**: API key doesn't have write access enabled
**Fix**: Generate a new key at https://www.zotero.org/settings/keys with "Allow write access" enabled

### Duplicate items created
**Symptom**: Same reference appears twice in Zotero
**Cause**: `check_existing = FALSE` or a match was declined
**Fix**: Delete duplicates manually; re-import with `check_existing = TRUE` for future runs

## Files in This Workflow

| File | Purpose |
|------|---------|
| `wiki-refs-to-zotero.R` | Main library (source this first) |
| `wiki-refs-to-zotero-vignette.qmd` | Full walkthrough with explanations |
| `wiki-refs-pipeline-workflow.R` | Interactive script with detailed comments |
| `run-wiki-refs-example.R` | Ready-to-run example (Meiō incident) |
| `wiki-refs-import-template.R` | **Start here**: Customizable for any page |
| `WIKI-REFS-QUICKSTART.md` | Quick reference guide |
| `WIKI-REFS-WORKFLOW.md` | This file |

## Next Steps

1. **Set up credentials** — Add ZOTERO_USER_ID and ZOTERO_API_KEY to `.Renviron`
2. **Test with example** — Run `source("run-wiki-refs-example.R")`
3. **Try your page** — Edit and run `wiki-refs-import-template.R`
4. **Read vignette** — See `wiki-refs-to-zotero-vignette.qmd` for detailed explanations
5. **Explore source** — Examine `wiki-refs-to-zotero.R` to understand the parser

## API & Dependencies

- **WikipediR / MediaWiki API** — Fetch wikitext via httr2
- **c2z package** — ZoteroDoi(), ZoteroIsbn(), ZoteroPost(), ZoteroKey()
- **httr2** — HTTP requests with retry logic and rate-limit handling
- **tidyverse** — Data manipulation (dplyr, tidyr, purrr, stringr)
- **stringi** — Unicode normalization for deduplication
