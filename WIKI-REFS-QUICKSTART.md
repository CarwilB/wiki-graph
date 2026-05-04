# Wiki References to Zotero — Quick Start Guide

This guide walks you through extracting references from any Wikipedia article and importing them into your Zotero library.

## Prerequisites

1. **R packages** (should already be loaded):
   ```r
   library(tidyverse)
   library(stringi)
   library(httr2)
   library(c2z)
   ```

2. **Source the main script**:
   ```r
   source("wiki-refs-to-zotero.R")
   ```

3. **Zotero API credentials** in your `.Renviron`:
   ```
   ZOTERO_USER_ID = 1234567
   ZOTERO_API_KEY = aBcDeFgHiJkLmNoPqRsTuVwX
   ```
   Find your user ID and generate a key at: https://www.zotero.org/settings/keys

## Quick Workflow

### Option 1: Use the Template (Easiest)

Edit `wiki-refs-import-template.R` with your Wikipedia page name, then run it:

```r
source("wiki-refs-import-template.R")
```

### Option 2: Step-by-Step Manual

1. **Dry run** (inspect before importing):
   ```r
   refs <- wiki_refs_pipeline(
     page_name      = "Elizabeth_Lyon_(criminal)",
     enrich         = TRUE,
     zotero_import  = FALSE,
     dry_run        = TRUE
   )
   ```

2. **Inspect results**:
   ```r
   # See what was extracted
   refs |> count(itemType, sort = TRUE)
   
   # View first few
   refs |> select(itemType, first_author, year, title) |> head(10)
   
   # Check enrichment status
   refs |> count(.enrich_status)
   
   # Flag issues
   refs |> filter(is.na(title) | itemType == "document") |> select(everything())
   ```

3. **Edit if needed** (optional):
   ```r
   refs <- refs |>
     mutate(title = if_else(
       first_author == "Smith" & year == "2003",
       "The corrected title",
       title
     ))
   ```

4. **Check library for duplicates**:
   ```r
   refs <- check_library_for_refs(
     refs,
     user_id = Sys.getenv("ZOTERO_USER_ID"),
     api_key = Sys.getenv("ZOTERO_API_KEY")
   )
   ```

5. **Post to Zotero**:
   ```r
   result <- post_refs_to_zotero(
     refs,
     collection_name = "Elizabeth Lyon (criminal)",
     user_id         = Sys.getenv("ZOTERO_USER_ID"),
     api_key         = Sys.getenv("ZOTERO_API_KEY")
   )
   ```

6. **Retrieve Zotero keys** (optional, for citations):
   ```r
   refs_with_keys <- fetch_zotero_keys(
     refs,
     user_id        = Sys.getenv("ZOTERO_USER_ID"),
     api_key        = Sys.getenv("ZOTERO_API_KEY"),
     collection_key = "XXXXXXXX"  # 8-char key from your Zotero collection
   )
   ```

## Finding Your Zotero Collection Key

After importing, find the 8-character collection key:

```r
request("https://api.zotero.org") |>
  req_url_path_append("users", Sys.getenv("ZOTERO_USER_ID"), "collections") |>
  req_headers(
    `Zotero-API-Version` = "3",
    Authorization = paste("Bearer", Sys.getenv("ZOTERO_API_KEY"))
  ) |>
  req_perform() |>
  resp_body_json(simplifyVector = TRUE) |>
  (\(x) tibble(key = x$key, name = x$data$name))() |>
  filter(name == "Your Collection Name")
```

## Export to RIS

To export parsed references for use in other reference managers:

```r
export_ris(refs, "my_references.ris")
```

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| `No citation templates found` | Page uses `{{sfn}}` author-date style without a "References" section | Check raw wikitext; article must have `{{Cite ...}}` templates |
| Many `itemType == "document"` | Unusual template names not recognized | Check `.template_name` column; edit `cite_patterns` in script if needed |
| `enrich_status == "failed"` | DOI/ISBN present but not in CrossRef | Edit row manually before importing |
| Zotero API 403 error | API key lacks write permission | Generate new key with "Allow write access" enabled |

## Key Functions

- **`wiki_refs_pipeline()`** — Main entry point. Fetches Wikipedia, parses citations, optionally enriches and imports.
- **`extract_refs_from_wikitext()`** — Just parse citations from wikitext string.
- **`deduplicate_refs()`** — Remove duplicates by last name + year + title.
- **`enrich_refs()`** — Look up DOIs and ISBNs via Crossref to fill in missing metadata.
- **`check_library_for_refs()`** — Find existing items in your library; prevent duplicates.
- **`post_refs_to_zotero()`** — Create new collection and import items.
- **`export_ris()`** — Export to RIS format.
- **`fetch_zotero_keys()`** — Retrieve Zotero keys for imported items (for citations).

## Examples

### Extract from Brooklyn Wikipedia article

```r
refs <- wiki_refs_pipeline("Brooklyn", enrich = TRUE, dry_run = TRUE)
```

### Extract from non-English Wikipedia

```r
refs <- wiki_refs_pipeline(
  page_name = "Jorge Luis Borges",
  language  = "es",  # Spanish Wikipedia
  dry_run   = TRUE
)
```

### One-step import (no manual review)

```r
refs <- wiki_refs_pipeline(
  page_name       = "Meiō_incident",
  enrich          = TRUE,
  zotero_import   = TRUE,
  check_existing  = TRUE,
  collection_name = "Meiō incident",
  user_id         = Sys.getenv("ZOTERO_USER_ID"),
  api_key         = Sys.getenv("ZOTERO_API_KEY"),
  dry_run         = FALSE
)
```

## Next Steps

- **Read the full vignette** (`wiki-refs-to-zotero-vignette.qmd`) for detailed explanations.
- **Examine the source code** (`wiki-refs-to-zotero.R`) to understand the parser and API interaction.
- **Check existing items** before importing to avoid duplicates.
- **Enrich metadata** by enabling DOI/ISBN lookups (enabled by default).
