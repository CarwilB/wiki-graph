# Wikipedia Reference Extraction Pipeline

Extract bibliographic references from Wikipedia citation templates and export to Zotero.

## Tools

| Tool | Type | Location | Purpose |
|------|------|----------|---------|
| `wiki-to-ris.html` | Browser-based JS/HTML | Project root | Fetch wikitext, extract citation templates, output RIS format. No server required. |
| `wiki-refs-to-zotero.R` | R pipeline | Project root | Same extraction + c2z enrichment (DOI/ISBN lookups), deduplication, direct Zotero API posting, graceful error handling. |
| `wiki-refs-to-zotero-examples.R` | Usage examples | Project root | Example workflows. |

## Supported Citation Templates (English Wikipedia)

Both tools handle: `cite book`, `cite journal`, `cite web`, `cite news`, `cite encyclopedia`, `cite odnb`, `cite magazine`, `cite thesis`, `cite conference`, `cite report`, `cite press release`, `cite av media`, `cite podcast`, `cite speech`, `harvc`.

**R version only** additionally handles:
- `{{Citation}}` — generic template; item type inferred from parameters (`chapter=` → bookSection, `journal=` → journalArticle, default → book).
- `{{Cite EB1911}}` — Encyclopædia Britannica 11th ed.; maps to encyclopediaArticle with fixed bookTitle.

## Template → Zotero Item Type Mapping

| Template | Zotero itemType | RIS code |
|----------|----------------|----------|
| cite book | book | BOOK |
| cite journal | journalArticle | JOUR |
| cite web | webpage | ELEC |
| cite news, cite press release | newspaperArticle | NEWS |
| cite encyclopedia, cite odnb, cite eb1911 | encyclopediaArticle | ENCYC |
| cite magazine | magazineArticle | MGZN |
| cite thesis | thesis | THES |
| cite conference | conferencePaper | CONF |
| cite report | report | RPRT |
| cite av media | videoRecording | VIDEO |
| harvc, Citation+chapter | bookSection | CHAP |
| Citation (no chapter) | book | BOOK |
| fallback | document | GEN |

## Test Case: Brooklyn Wikipedia Article (6 Mar 2026)

Compared three import methods:

| Source | Items | Unique |
|--------|------:|-------:|
| Pipeline (R) | 189 | 54 (mostly `document` from URL-less templates) |
| CoiNS (Zotero translator) | 153 | 9 |
| RIS (Zotero translator) | 131 | 1 |
| Shared (all three) | 127 | — |

CoiNS misclassifies most items as `book` or `journalArticle`. RIS preserves types faithfully but captures fewer items. Pipeline captures the most but produces `document` for non-templated `<ref>` content.

## Known Issues & Next Steps

1. **JS version needs `{{Citation}}` and `{{Cite EB1911}}`** — currently only in R. All templated citation types should be added to JS.
2. **R version should stop extracting bare (non-templated) `<ref>` content** — these are often actual footnotes, not bibliographic references. Remove or make `extract_bare_refs()` opt-in.
3. **French and Spanish citation templates** need mapping and support for multilingual Wikipedia. See `data/wiki-citation-templates-multilingual.md`.
4. **Zotero library index**: `check_library_for_refs()` downloads entire library (~16k items, ~160 API requests) for duplicate checking. Should use cached local index with version-based incremental sync or per-item search.
5. **`zotero_access_key` env var** lacks read permission on personal library. Use `zotero_access_key_write` for all API calls.
