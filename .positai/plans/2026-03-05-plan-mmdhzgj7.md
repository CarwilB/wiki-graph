# Plan: Ingest Wikipedia References → RIS → Zotero

## Goal

Build an R script that takes a Wikipedia article title, extracts all cited references, deduplicates them into a tidy data frame, exports to RIS format, and imports into a new collection in a local Zotero library via `c2z`.

## Key challenges

Wikipedia articles use two distinct citation patterns (and often mix them):

1. **Inline `<ref>` tags** containing `{{Cite book|...}}`, `{{Cite journal|...}}`, `{{Cite web|...}}`, etc. (e.g., Meiō incident)
2. **Author-date / `{{sfn}}` style** where short footnotes (`{{sfn|Author|Year|p=...}}`) point to full entries in a Sources / Works Cited section using the same `{{cite *}}` templates (e.g., Elizabeth Lyon)

Both patterns ultimately resolve to `{{cite *}}` templates with well-defined parameter names. The strategy is to extract **all** `{{cite *}}` templates from the wikitext regardless of where they appear, then deduplicate.

## Pipeline steps

### 1. Fetch wikitext via WikipediR

```r
library(WikipediR)
page <- page_content("en", "wikipedia", page_name = "...", as_wikitext = TRUE)
```

This returns the raw wikitext, which we parse in R.

### 2. Parse all `{{cite *}}` templates from wikitext

Write a recursive-descent or regex-based parser that handles nested braces (Wikipedia templates can contain nested templates like `{{Google books|...|...}}`).

Extract every `{{Cite book|...}}`, `{{Cite journal|...}}`, `{{Cite web|...}}`, `{{Cite ODNB|...}}`, `{{Cite encyclopedia|...}}`, `{{harvc|...}}` template. Parse each into a named list of key-value pairs.

Also handle:
- `{{sfnRef|...}}` custom ref anchors (used for non-standard short-citation keys)
- `{{harvc|...}}` (book chapters citing a parent book)
- Bare `<ref>` tags that contain free text instead of templates (flag these for manual review)

### 3. Map template types to Zotero/RIS item types

| Wikipedia template | RIS type | Zotero itemType |
|---|---|---|
| `Cite book` / `harvc` | `BOOK` / `CHAP` | `book` / `bookSection` |
| `Cite journal` | `JOUR` | `journalArticle` |
| `Cite web` | `ELEC` | `webpage` |
| `Cite news` | `NEWS` | `newspaperArticle` |
| `Cite ODNB` | `ELEC` | `encyclopediaArticle` |
| `Cite encyclopedia` | `ENCYC` | `encyclopediaArticle` |

Map Wikipedia template parameters to RIS fields:

| Wiki param | RIS tag | Notes |
|---|---|---|
| `last` / `last1`, `first` / `first1` | `AU` | Repeat for `last2`/`first2`, etc. |
| `title` | `TI` | |
| `date` / `year` | `PY` | |
| `publisher` | `PB` | |
| `location` | `CY` | |
| `isbn` | `SN` | |
| `doi` | `DO` | |
| `url` | `UR` | |
| `journal` | `JO` / `T2` | |
| `volume` | `VL` | |
| `issue` | `IS` | |
| `pages` / `page` | `SP`/`EP` | Parse range |
| `series` | `T3` | |
| `edition` | `ET` | |
| `language` | `LA` | |
| `access-date` | `Y2` | |

### 4. Build a reference data frame and deduplicate

Create a tibble with one row per unique source. Deduplication key: normalize `(last1, title, year)` — lowercase, strip punctuation/diacritics. For `{{sfn}}` references, the author-year key naturally groups multiple page citations to the same source.

Flag any remaining near-duplicates using string distance on titles.

### 5. Export to RIS

Write a function `refs_to_ris(df, file)` that produces a valid `.ris` file. Each record is delimited by `ER  -`.

### 6. Create Zotero collection and import

Using the `c2z` package (already in use in the project):

```r
library(c2z)
zotero <- Zotero(user = TRUE, id = user_id, api = api_key)
```

- Create a new collection named after the Wikipedia article
- Post items via `ZoteroPost()` (c2z can accept a data frame of items)
- Before posting, query the target library for existing items matching the dedup key to avoid duplicates against items already in Zotero

### 7. Reporting

Return the reference data frame to the user with columns:
- `ref_key` (dedup key)
- `item_type`, `authors`, `title`, `year`, `publisher`, `doi`, `url`
- `n_citations` (how many times cited in the article)
- `zotero_status` ("imported" / "already_exists" / "failed")

## File structure

Single script: `wiki-refs-to-zotero.R` (or `.qmd` if we want rendered output). Helper functions at top, pipeline at bottom.

## Dependencies

- `WikipediR` — fetch wikitext
- `c2z` — Zotero API
- `stringr`, `purrr`, `dplyr`, `tidyr` — wrangling
- `stringi` — Unicode normalization for dedup

## Open questions

1. **Zotero target**: Import to personal library or a group library? (The existing code uses both.) I'll default to personal library.
2. **Non-template refs**: Some articles have bare `<ref>` tags with free text (e.g., `<ref>Temple records of Sumiyoshi-taisha.</ref>`). Plan: include these in the df as `itemType = "document"` with just a `title` field, flagged for manual review.
3. **Primary source templates**: Templates like `{{Cite book |author=Jinson |title=Daijō'in Jisha Zōjiki ...}}` in the Works Cited section that are referenced by `{{sfn|Jinson|...}}` — these are already `{{Cite book}}` and will be parsed normally.
4. **`harvc` (book chapters)**: These reference a parent book. Plan: create both a `bookSection` item and link it to the parent book entry.
