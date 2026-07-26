# wiki-graph project memory

**File system convention**: All project files live in `~/Dropbox (Personal)/R/wiki-graph/` unless noted. Census data (`../bolivia-data/`) is external to the project root.

## Active Projects

| Project | Description | Documentation |
|---------|-------------|---------------|
| **Community Geography** | Map INE community codes (11-digit) to IGM geographic points (id_unico) for Bolivia. Primary pipeline: `ine_community_mapping.R` → `data/crosswalk_ine_igm.rds`. 19,418 communities, ~344 canton splits. | [`PROJECTS-GEOGRAPHY.md`](PROJECTS-GEOGRAPHY.md) |
| **Bolivia 2024 Census (CPV)** | Person-level microdata analysis (11.4M rows). Focus: indigenous identity & language. Shared infrastructure: `cel_helpers.R` computes CEL (Condición Étnico-Lingüística) scale. Key documents: `bolivia-censo-2024.qmd`, `albo-restudy-2024.qmd`. | [`PROJECTS-CENSUS.md`](PROJECTS-CENSUS.md) |
| **Election Results (EG2025)** | Bolivia's August 2025 general election. Raw data: `data-raw/EG2025_*.csv` (69,279 mesas). Cleaned: `data/eg2025_presidente_mesa.rds`. See `eg2025-resultados.qmd` for visualizations. | [`PROJECTS-ELECTION.md`](PROJECTS-ELECTION.md) |
| **Wikipedia Reference Extraction** | Extract citation templates from Wikipedia and import to Zotero. Full pipeline in `wiki-refs-to-zotero.R`; three new helper scripts (template, example, workflow); comprehensive guide in `WIKI-REFS-WORKFLOW.md`. | [`PROJECTS-WIKI-REFS.md`](PROJECTS-WIKI-REFS.md) |
| **Language Diversity** | Map linguameta language codes to Wikipedia editions. 47 zero-article languages covered (Mar 2026). Main document: `wiki-language-diversity-v2.qmd`. | [`PROJECTS-LANGUAGE-DIVERSITY.md`](PROJECTS-LANGUAGE-DIVERSITY.md) |

## Multilingual Municipality Generator (Jul 2026)

Bilingual (en/es) Wikipedia article generator. Both qmds are thin wrappers over
a shared, `lang`-aware engine.

**Entry points**: `bolivia-muni-generator-en.qmd` (`lang="en"`),
`bolivia-muni-generator-es.qmd` (`lang="es"`). Each loads data + derived lookups,
then calls `render_muni_blocks(muni_lookup, concejo_data, lang=...)`. Full-page
wikitext is written to `output/bolivia-municipality-wikitext/<lang>/[id].txt`.

**Shared engine (src/)**:
- `muni-article-functions.R` — all `compose_*` / `build_*` / `muni_block` /
  `render_muni_blocks`, every function `lang`-aware. Sources the three files below.
- `bolivia-builders.R` — council/language/autoident wikitable + kable builders;
  `_en`/`_es` wrappers over `.build_*(..., lang)` internals.
- `muni-i18n.R` — `label(key, lang)` + `translate_values(x, variable, lang)`,
  backed by transcats; registers the translation tables on source.
- `muni-phrases.R` — `phrases[[lang]]` prose dictionary (ordinals, gender,
  glue templates). Spanish mayor sentence is gendered from `alcaldes$autoridad`
  ("ALCALDESA" → feminine).
- `muni-references.R` — `refs[[lang]]` citation registry + `ref_with_page()`.
  **es citations are UNVERIFIED mechanical {{Cita}} conversions** ([[TODO:es]]).

**Translation assets** (`data/translations/`, see the `transcats` skill):
`muni_data_values.csv` (ethnic_group, language; source col `raw`),
`muni_var_labels.csv` (wide label table), `muni_translations.rds` (parsed).

**Other data**: `data/prov_link_lookup.rds` — id_prov → es.wikipedia province
article title (built from `bo_province_wiki_presence.rds`; 10 manual overrides).

**Known gaps**: poverty table (`generate-muni-poverty-tables.R`) is English-only;
table cell numbers use comma thousands separators in both languages.

## Multilingual Municipality Infobox Generator (Jul 2026)

Bilingual infobox generator. **EN targets `{{Infobox settlement}}`; ES targets a
different template, `{{Ficha de entidad subnacional}}`** — a field-schema remap,
not just value/label translation. Every ES field was verified against the live
template parameter list.

**Entry points**: `bolivia-muni-infobox-en.qmd` (`lang="en"`),
`bolivia-muni-infobox-es.qmd` (`lang="es"`). Each loads data into globals and
calls `render_new_blocks()` / `render_existing_blocks()`.

**Shared engine**: `src/muni-infobox-functions.R` — `compute_infobox_data(id)`
returns language-neutral facts; `infobox_specs[[lang]]` holds the per-template
spec (template name, field order, section headers, force-blank/excluded sets,
and a `build` mapper: `build_infobox_fields_en/_es`); `render_infobox_wikitext()`
and `render_infobox_merge_lines()` are generic. Sources
`src/muni-article-functions.R` for `prov_link_target()`/`spanish_title_case()`
and (transitively) `phrases`, `refs`, `label()`. Reads the same global lookups
as the article engine plus `pop_muni_ur`, `commons_log`, `munis_with_p402`,
`wd_images`, `wd_ine`, and (for merges) `existing_infobox_blocks`.

- Uses `library(wikitools)` for `extract_infobox`/`clean_infobox_value`; the
  verbatim-block merge helpers (`extract_infobox_wikitext`,
  `split_on_top_level_pipes`, `parse_infobox_blocks`, `has_real_content`) are
  **inlined** into the engine (not exported by wikitools).
- Citations come from the shared `refs[[lang]]` registry (EN too). ES numbers
  are emitted raw (no thousands separators) since the template formats them.
- ES ethnic-group wikilinks come from es.wikipedia "Grupos étnicos de Bolivia";
  **Uru & Chipaya both point to `[[Etnias urus]]`** for now.
- ES design decisions: rural population → `campo1` ("Población rural");
  ethnicities → `campo2`; single shield slot → coat of arms preferred over seal.
- Merge (`existing_infobox_blocks`) reads es wikitext from
  `sa_article_quality` (lang=="es"); falls back to a fresh scaffold for stubs.

**EN parity**: byte-identical to the pre-refactor output except the identity
citation in `population_blank1`, which now comes from the shared registry (same
fields, `url`/`date` reordered).

**EN parity**: verified byte-identical to the pre-refactor output except a fixed
`== References ==/n...` typo (now real newlines).

## Skills

| Skill | Description |
|-------|-------------|
| **wikitext-preview-block** | Pattern for rendering a side-by-side HTML kable preview + copyable wikitext block in Quarto. Covers `wikitext_block()`, `process_for_display()`, `refs_footnotes()`, `include_table_assets()`, and the `tagList(lapply(...))` rendering pattern. Requires sourcing `src/muni-article-functions.R`. See `skills/wikitext-preview-block/SKILL.md`. |

## Core Infrastructure

### `cel_helpers.R`
Reusable functions for census work. Source with `source("cel_helpers.R")`:
- `read_census_geo(geo_codes, urban_rural, extra_cols)` — Load census data by geography (dept/prov/mun codes)
- `compute_cel(df)` — Vectorized CEL computation
- Lookup tables: `muni_lookup`, `prov_id_lookup_table`, `idioma_cats`
- Diverging color palette: `cel_colors`

### INE Code Structure
11-digit string: `0|DD|PP|MM|C|SSS` (dept, prov, mun, canton, sequence). USCA uses 10-digit; pad with `paste0("0", cod10dig)`.

### Data Import Convention
For manually transcribed published tables:
1. Import script: `<author>-<year>.R` (project root)
2. YAML sidecar: `data/<script-basename>.yml` (provenance)
3. CSV/RDS outputs: `data/<descriptive_name>.*`

---

## Wikipedia References to Zotero Workflow (Apr 2026)

**Files**:
- `wiki-refs-to-zotero.R` — Main library (1857 lines; all functions documented)
- `wiki-refs-to-zotero-vignette.qmd` — Full walkthrough from vignette
- `wiki-refs-pipeline-workflow.R` — Interactive script with detailed comments
- `run-wiki-refs-example.R` — Ready-to-run example (Meiō incident article)
- `wiki-refs-import-template.R` — **Start here**: Customizable for any Wikipedia page
- `WIKI-REFS-QUICKSTART.md` — Quick reference guide (functions, troubleshooting)
- `WIKI-REFS-WORKFLOW.md` — Complete workflow with diagrams and examples

**Workflow**: Fetch Wikipedia page → Extract citations → Deduplicate → Optionally enrich via DOI/ISBN → Check Zotero library for duplicates → Import to new collection

**Key functions**:
- `wiki_refs_pipeline()` — Main entry point (all-in-one or dry run)
- `fetch_wikitext()` — Download raw Wikipedia source
- `extract_refs_from_wikitext()` — Parse citation templates
- `check_library_for_refs()` — Identify duplicates in Zotero
- `post_refs_to_zotero()` — Create collection and import items
- `export_ris()` — Export to RIS for other reference managers

**Setup**: Requires ZOTERO_USER_ID and ZOTERO_API_KEY in `.Renviron`

**Test status**: ✓ Tested on Meiō incident (32 unique refs extracted)

---

## Chat Archiving

**Archive every chat session** to `.positai/chats/` in the project root as a markdown file.

**When to archive**:
- Whenever `/compact` is called
- Whenever a new chat is opened (archive the outgoing session before context resets)

**File naming**: `.positai/chats/YYYY-MM-DD_HH-MM_<short-slug>.md` (e.g., `2026-05-08_16-14_ine-municipality-matching.md`)

**File format**:
```markdown
# Chat: <title>
**Date**: YYYY-MM-DD  
**Project**: wiki-graph  

## Summary
<2–4 sentence summary of what was accomplished or decided>

## Transcript
<full or condensed conversation>
```

---

## Coding Conventions

- **Function style**: Build multi-row tables with `bind_rows()` and `left_join()`, not by indexing individual rows into a `tibble()` constructor (e.g., avoid `tibble(col = c(df$col[1], df$col[2], ...))`). Pre-compute derived columns (e.g., percentages, changes) once when building a shared dataset, and extract repeated formatting logic into named helper functions rather than inlining it in every call site.
- **Intermediate data tables**: Save nationwide/shared processed tables as `.rds` files rather than regenerating them each time. (e.g., `poverty_water_sanitation_dept.rds`, `poverty_water_sanitation_muni.rds`). Build functions are kept as a last-resort fallback only.
- **Verify before asserting**: Do not assume a file does or does not exist based on whether a `saveRDS()` call is commented out. Use `file.exists()` or `ls()` to check.

---

**Last updated**: July 2026  
**To work on a project**, see its documentation file above (e.g., `PROJECTS-CENSUS.md` for census details).
