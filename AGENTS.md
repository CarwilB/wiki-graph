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

**Last updated**: April 2026  
**To work on a project**, see its documentation file above (e.g., `PROJECTS-CENSUS.md` for census details).
