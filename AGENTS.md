# wiki-graph project memory

## File system conventions

- **All relevant project files live inside `~/Dropbox (Personal)/R/`**. Never search outside this path without explicit user permission.
- Census data (Bolivia 2024 CPV) lives in `../bolivia-data/` relative to the wiki-graph project root, i.e. `~/Dropbox (Personal)/R/bolivia-data/`.

## Project overview

Bolivia community geography project. The goal is to map INE community codes to
IGM geographic point identifiers, enabling downstream linkage to locations
(coordinates) and Wikidata entities.

A second strand of analysis uses the **Bolivia 2024 Census** (CPV 2024) person-level
microdata to study indigenous identity and language. See `bolivia-censo-2024.qmd`.

## Key data files

### Community geography (INE–IGM crosswalk)

| File | Description |
|------|-------------|
| `data/CLASIF_UB_GEOG_COMUNIDAD.xlsx` | INE community list with 19,418 communities. Columns include `Codigo` (11-digit INE code), `CIUDAD/COMUNIDAD`, `DEPARTAMENTO`, `PROVINCIA`, `MUNICIPIO`, and numeric segment columns `DEP`, `PRO`, `MUN`. |
| `data/localizacion_poblaciones_2016.json` | IGM GeoJSON point dataset: 23,891 settlement points. Key columns: `id_unico` (unique IGM identifier), `nombre_dep` (department), `nombre_c_1` (community name, uppercase), `tipo_area`, `tipo_pobla`. |
| `data/igm_localizacion_2016/poblaciones.shp` | Same IGM data as shapefile (POINT geometry, WGS84). |
| `data/etnicidad_tenencia/usca_final.shp` | USCA community-level multipolygon boundaries (MULTIPOLYGON, WGS84). 14,426 features. Key column: `cod10dig` (10-digit INE code — pad with leading zero to match `Codigo`). Also has `eth_tie_fi` and `usc_agreg` (ethnicity/land tenure classifications). |
| `data/etnicidad_tenencia/usca_final.dbf` | Attribute table of the above (no geometry). |
| `data/igm_localizacion_2016/poblaciones.dbf` | Attribute table of the IGM shapefile. No INE codes — department and settlement name only. |
| `data/gadm41_BOL_3.gpkg` | GADM Bolivia level-3 (municipality) boundaries. Layer: `ADM_ADM_3`. Columns: `NAME_1` (department), `NAME_2` (province), `NAME_3` (municipality). |
| `data/crosswalk_ine_igm.rds` | **Primary output.** Crosswalk from INE `Codigo` to IGM `id_unico`. Load with `readRDS("data/crosswalk_ine_igm.rds")`. |
| `data/crosswalk_ine_igm.csv` | Same crosswalk as CSV for interoperability. |

### Bolivia 2024 Census (CPV 2024)

All files live under `../bolivia-data/Censo 2024/` (relative to the wiki-graph project root).

| File | Description |
|------|-------------|
| `base_datos_csv_2024/Persona_CPV-2024.csv` | Person-level microdata. ~3 GB, semicolon-delimited. **11,365,333 rows × 118 columns.** All columns are integers. Open lazily: `open_dataset(..., format="csv", delimiter=";")`. |
| `base_datos_csv_2024/Vivienda_CPV-2024.csv` | Household-level microdata. |
| `base_datos_csv_2024/Emigracion_CPV-2024.csv` | Emigration module. |
| `base_datos_csv_2024/Mortalidad_CPV-2024.csv` | Mortality module. |
| `base_datos_csv_2024/Persona_CPV-2024_sample10k.rds` | Pre-drawn random 10,000-row sample of person file (`set.seed(8143)`). Load with `readRDS()`. |
| `base_datos_csv_2024/Diccionario de variables CPV 2024.xlsx` | Variable dictionary. Sheets: PERSONA, VIVIENDA, EMIGRA, MORTA. Contains value labels for all coded variables. |
| `BOL-INE-CPV-2024.xml` | DDI codebook (XML). 184 variables with labels, question text, and descriptions. Parse with `xml2`; uses namespace `http://www.icpsr.umich.edu/DDI`. |
| `BOL-INE-CPV-2024.json` | Same codebook in JSON format. |
| `codebook_persona.rds` | Pre-parsed DDI codebook as tibble. Columns: `variable`, `label`, `description`, `question`. Load with `readRDS()`. |
| `codebook_persona.csv` | Same codebook as CSV. |
| `pueblo_cats.rds` | Lookup table for `p32_pueblo_cod`: 145 rows, columns `code` (int) and `label` (chr). Load with `readRDS()`. |
| `pueblo_cats.csv` | Same as CSV. |
| `lang_use.rds` | Pre-collected aggregate: `idioma_mat × idioma_mayor_uso`, all persons with both non-NA. 435 rows. |
| `lang_use_age.rds` | Same, further broken down by `age_group` (5 bins: 0–14, 15–29, 30–44, 45–59, 60+). 1,319 rows. |
| `lang_use_urban.rds` | `idioma_mat × idioma_mayor_uso × urbrur_label` aggregate. `urbrur_label`: "Urban" (urbrur=1) or "Rural" (urbrur=2), joined from Vivienda file on `idep+iprov+imun+i00`. 658 rows. |
| `lang_use_identity.rds` | `idioma_mat × idioma_mayor_uso × identifies` aggregate. `identifies`: "Self-identifies" (p32_pueblo_per=1) or "Does not identify" (p32_pueblo_per=2). 616 rows. |
| `lang_age_urban.rds` | `idioma_mat × idioma_mayor_uso × urbrur_label × age_group`. 1,969 rows. |
| `lang_age_identity.rds` | `idioma_mat × idioma_mayor_uso × identifies × age_group`. 1,829 rows. |
| `albo_vars.rds` | Person-level indicators (11,365,333 rows). Columns: `idep`, `iprov`, `imun`, `urbrur`, `albo_q1`, `albo_q2`, `albo_q3`, `albo_c`, `cel_q2`, `cel`. Load with `readRDS()`. |
| `albo_vars.csv` | Same as CSV. |
| `cel_geo.rds` | CEL geographic summary table (1,214 rows). Columns: `department`, `province`, `municipality` (INE codes, NA when aggregated), `urban_rural` ("Urban"/"Rural"/NA), `n_total`, `cel_0` … `cel_7` (% at each level, incl. 1.5 and 4.5), `cel_2plus`, `cel_4plus`, `cel_5plus` (% with CEL ≥ threshold). Covers: national, dept, prov, mun, and all four × urban/rural. Load with `readRDS()`. |
| `cel_geo.csv` | Same as CSV. |

#### Key person-level variables

| Variable | Description |
|---|---|
| `idep` | Department code (1–9) |
| `iprov` | Province code |
| `imun` | Municipality code |
| `p25_sexo` | Sex: 1 = Mujer, 2 = Hombre |
| `p26_edad` | Age in years |
| `p32_pueblo_per` | Indigenous self-identification (yes/no): 1 = Sí, 2 = No, 9 = Sin respuesta |
| `p32_pueblo_cod` | Raw group code (145 categories incl. 9xx generic terms, 5xx foreign groups). Lookup: `pueblo_cats.rds` |
| `p32_pueblos` | Derived CTAI-reconciled identity (58 categories, 98 = No se autoidentifica, 99 = Sin respuesta). Category labels in `pueblos_cats` tribble in Qmd. |
| `idioma_mat` | Mother tongue code (83 categories). Key: 2=Aymara, 6=Castellano, 12=Guaraní, 27=Quechua, 998=No habla. Full labels in `idioma_cats` tribble in Qmd. |
| `idioma_mayor_uso` | Language of greatest daily use (same coding as `idioma_mat`) |
| `nivel_edu` | Educational attainment (derived, 19+ year olds) |
| `condact_19` | Labour force status per 19th ICLS definition |

#### Important coding notes

- `p32_pueblo_cod` uses a different numbering scheme from `p32_pueblos`. Do not join them directly.
- **`urbrur` is in the Vivienda file, not the Persona file.** Join on `idep + iprov + imun + i00` (dwelling number). All 11.4M persona rows match exactly (0 NAs).
- **Afroboliviano language (code 94 in `idioma_mat`) is excluded from all linguistic retention analysis.** The census records it as a language category, but it refers to a Spanish variety spoken in the La Paz Yungas, not a structurally distinct language. Only ~450 people report it as a mother tongue (92.7% in La Paz). Afroboliviano as an *ethnic identity* (`p32_pueblos == 1`) is retained — 25,168 self-identifiers, 86% Castellano-speaking.
- **Kabineña** (code 7 in `idioma_mat`) = **Cavineño** (code 7 in `p32_pueblos`): same people, different spelling conventions.
- **Zamuco** (code 37 in `idioma_mat`) = **Ayoreo** (code 4 in `p32_pueblos`): Zamuco is the ISO language name; Ayoreo is the ethnonym.
- NAs in `p32_pueblo_cod` are not missing data — they indicate respondents who answered "No" or gave no response to `p32_pueblo_per`.

#### albo_vars variable definitions

The four boolean variables in `albo_vars.rds` implement Xavier Albó's conceptual framework for indigenous identity and language:

| Variable | Question | Logic |
|---|---|---|
| `albo_q1` | Self-identifies with an indigenous or Afrobolivian group? | `p32_pueblo_per == 1` |
| `albo_q2` | Does their spoken language match their declared identity? | Any of `p331/p332/p333` is in the set of idioma codes expected for `p32_pueblos`. Generic identities (Otras declaraciones = 57, Quechua-Aymara = 55, Más de una = 56) **and** groups with no census language equivalent (Afroboliviano = 1, Chuwi = 13, Paunaca = 37, Toromona = 47, foreign groups = 58) all count as YES if any indigenous language (codes 1–5, 7–37) is spoken. Always FALSE if `albo_q1` is FALSE. |
| `albo_q3` | Learned an indigenous language as a child? | `p341_idiomat_cod` is not NA, not 6 (Castellano), and not 999 |
| `albo_c` | Speaks Castellano? | Any of `p331/p332/p333` equals 6 |

`cel_q2` differs from `albo_q2` only for non-identifiers (Q1=FALSE): `albo_q2` is always FALSE for non-identifiers, while `cel_q2` is TRUE if the person speaks any Bolivian indigenous language (codes 1–5 or 7–37 in p331/p332/p333). This allows non-identifiers to populate CEL levels 1, 2, and 3.

`cel` — Condición Étnico-Lingüística (Albó & Romero): ordinal 0–7 with half-steps 1.5 and 4.5 for two combinations not in the original scale. See albo-restudy-2024.qmd for full definition.

`p32_pueblos`-to-idioma mapping highlights: Chiquitano (12) → Bésiro (4); Ayoreo (4) → Zamuco (37); Andean sub-groups (Charka Qhara Qhara, Chichas, Jalq'a, Yampara, Lípez, Raqaypampa, Qullas, Killacas, Jach'a Carangas, Lupaca, Pakajaqi, Sora, Qhapaq Uma Suyu) → Quechua or Aymara as appropriate; Mojeño (29) → Mojeño Ignaciano or Trinitario; Joaquiniano (21) → Maropa (19). Afroboliviano (1), Chuwi (13), Paunaca (37), Toromona (47), foreign groups (58) → use "any indigenous language" rule (same as generic groups).

#### Census analysis findings (as of Feb 2026)

- **37.5%** of the population self-identifies as indigenous or afro-bolivian (`p32_pueblo_per == 1`).
- Among self-identifiers, Quechua (39%) and Aymara (37%) dominate; 12.6% used generic terms (Campesino, Indígena, etc.) reclassified to "Otras declaraciones" in `p32_pueblos`.
- **Language shift is pronounced and age-graded**: 76% of 60+ indigenous self-identifiers speak an indigenous mother tongue vs only 22% of 0–14 year olds.
- **Self-identification rate declines with youth**: 49% of 60+ identify as indigenous vs 28% of 0–14 year olds.
- **1.98M Castellano mother-tongue speakers** (23% of 8.5M) self-identify as indigenous — predominantly Aymara (11%) and Quechua (8%).
- ~57,000 Quechua speakers identify with Andean sub-ethnic groups (Charka Qhara Qhara, Kallawaya, Chichas, Jalq'a, Yampara) rather than the pan-ethnic "Quechua" label.

### Bolivia 2025 General Election (EG2025)

Raw file lives in `data-raw/`. Cleaned outputs in `data/`. See `data/import-eg2025.yml` for full provenance.

| File | Description |
|------|-------------|
| `data-raw/EG2025_20250824_235619_5976286028509320003.csv` | Raw mesa-level results from OEP computo portal. 69,279 rows × 38 columns. All three races: Presidente, Diputado Uninominal (63 circunscripciones), Diputado Circunscripción Especial (7 indigenous seats). Party votes in Voto1–Voto12. Downloaded 2025-08-24. |
| `data/eg2025_presidente_mesa.rds` | Cleaned presidential results. 35,253 mesas × 27 columns. Party columns renamed. Load with `readRDS()`. |
| `data/eg2025_presidente_mesa.csv` | Same as CSV. |
| `data/import-eg2025.yml` | YAML sidecar with provenance, ballot slot mapping, and summary statistics. |
| `import-eg2025.R` | Import script. |
| `eg2025-resultados.qmd` | Quarto document producing department/province/municipality aggregations and choropleths for all three races. |

#### Ballot slot → party mapping

| Slot | Party | National presidential votes | % |
|------|-------|---------------------------:|---:|
| Voto1 | AP | 456,002 | 8.51 |
| Voto2 | LyP ADN | 77,576 | 1.45 |
| Voto3 | APB SÚMATE | 361,640 | 6.75 |
| Voto4 | *(vacant, 0 votes)* | 0 | 0.00 |
| Voto5 | LIBRE | 1,430,176 | 26.70 |
| Voto6 | FP | 89,253 | 1.67 |
| Voto7 | MAS-IPSP | 169,887 | 3.17 |
| Voto8 | MORENA *(0 votes)* | 0 | 0.00 |
| Voto9 | UNIDAD | 1,054,568 | 19.69 |
| Voto10 | PDC | 1,717,432 | 32.06 |
| Voto11 | *(especial race only)* | 412 | — |
| Voto12 | *(especial race only)* | 2,266 | — |

Voto11 and Voto12 have nonzero totals only in the Diputado Circunscripción Especial race. Voto4 and Voto8 (MORENA) are zero across all races (disqualified/withdrawn).

#### OEP geographic codes

The election data uses OEP internal codes, **not INE codes**. Department codes 1–9 match INE ordering. Province (`CodigoProvincia`) and municipality (`CodigoSeccion`) are sequential within their parent. Join to spatial data by name matching against GADM (`data/gadm41_BOL_3.gpkg`). ~13 municipalities are TIOC/AIOC indigenous autonomies created after the GADM vintage and will not match.

#### Key election statistics

- **Turnout**: 86.95% (6,900,418 of 7,936,515 registered)
- **Null votes**: 19.87% of votes cast (1,371,049) — Cochabamba exceptionally high at 33.3%
- **Winner**: PDC (32.06%) — dominates altiplano (La Paz 47%, Oruro 48%, Potosí 43%)
- **LIBRE** (26.70%) — strongest in Santa Cruz (38%) and lowlands
- **UNIDAD** (19.69%) — strongest in Beni (38%) and Tarija (38%)
- **MAS-IPSP** (3.17%) — historic low

## INE code structure

11-digit string (stored as character, with leading zero):
```
0 | DD | PP | MM | C | SSS
  dept  prov  mun  canton  seq
```
- Positions 2–3: department (2 digits)
- Positions 4–5: province (2 digits)
- Positions 6–7: municipality (2 digits)
- Position 8: canton (1 digit)
- Positions 9–11: community sequence number (3 digits)

The USCA file uses a 10-digit form (no leading zero). Pad with `paste0("0", cod10dig)` to match `Codigo`.

## Crosswalk schema

Columns: `Codigo`, `department`, `municipality`, `com_name`, `id_unico`, `match_status`, `n_geo`, `canton_split_group`

### match_status values

| Status | Meaning |
|--------|---------|
| `unique` | Direct 1-to-1 name match within department (13,998) |
| `unique_via_spatial` | Ambiguous name resolved by GADM municipality boundary (4,077) |
| `unique_via_name` | Ambiguous name resolved by proximity to municipality centroid (23) |
| `unique_via_usca` | Ambiguous name resolved by USCA community polygon containment (142) |
| `ambiguous_canton_split` | Same community listed under multiple canton codes due to administrative reorganisation; all sibling codes share the same IGM candidate pool (1,518 rows / 344 groups) |
| `ambiguous_dispersed` | All IGM candidates are `tipo_area == "dis"` (dispersed settlement); the IGM dataset recorded multiple points for the same dispersed community. Treat all candidates as a valid coordinate pool rather than selecting one (967) |
| `ambiguous` | Genuinely repeated name within same municipality; correct point cannot be determined automatically (64) |
| `ambiguous_no_spatial` | Name recurs across municipalities; no spatial disambiguation succeeded (170) |
| `unmatched` | No IGM point with matching name found (5) |

### canton_split_group

For `ambiguous_canton_split` rows, this column holds the lowest `Codigo` among all sibling codes in the group. All siblings resolve to the same IGM candidate pool — this many-to-one mapping is expected and correct.

To build a deduplicated community key (one per physical place):
```r
community_key = coalesce(canton_split_group, Codigo)
```

## Primary pipeline script

`ine_community_mapping.R` — runs the full pipeline from raw data to crosswalk:
1. Load INE Excel and IGM GeoJSON
2. Normalize names (strip non-ASCII, uppercase, collapse punctuation)
3. Join on department + name → `crosswalk_raw`
4. Spatial join with GADM municipality boundaries → resolves most ambiguous cases
5. Name-proximity fallback for points outside GADM polygons
6. Spatial join with USCA community polygons → `unique_via_usca`
7. Canton-split detection → `ambiguous_canton_split` + `canton_split_group`
8. Dispersed-settlement reclassification → `ambiguous_dispersed` (all candidates `tipo_area == "dis"`)
9. Export to `data/crosswalk_ine_igm.rds` and `.csv`
10. Defines `ine_match_status(codigo)` lookup function (tolerates 10- or 11-digit codes)

## Key relationships

- `ine_geog_2013$Codigo` ↔ `crosswalk$Codigo` (join key: INE → crosswalk)
- `crosswalk$id_unico` ↔ `igm_sf$id_unico` (join key: crosswalk → IGM point/coordinates)
- `usca_sf$cod10dig` ↔ `Codigo` after `paste0("0", cod10dig)` (INE code in USCA)
- GADM `NAME_1`/`NAME_3` → INE `department`/`municipality` via manual name crosswalk in script (many spelling differences)

## Canton splits

344 groups of INE codes point to the same physical community because Bolivia's canton boundaries were reorganised after the 2001 census. 141 municipalities affected; Potosí has the most (36 municipalities). Within a group, the community sequence number (last 3 digits of `Codigo`) is usually preserved — only the canton digit changes.

## Shared census infrastructure: `cel_helpers.R`

`cel_helpers.R` (project root) provides reusable functions and lookup tables for working with the Bolivia 2024 Census and the CEL (Condición Étnico-Lingüística) scale. Source it with `source("cel_helpers.R")`.

### What it loads

- **Lookup tables**: `muni_lookup` (from `data/muni_id_lookup_table.rds`), `prov_id_lookup_table` (from `data/prov_id_lookup_table.rds`), `idioma_cats` (from `data/idioma_cats.rds`).
- **`cel_colors`**: Named character vector mapping CEL levels (0, 1, 1.5, 2, 3, 4, 4.5, 5, 6, 7) to a diverging colour palette for ggplot.
- **`.valid_match_q2`**: Internal 99×38 logical matrix encoding the pueblos-to-idioma mapping for Q2 matching.

### Key functions

| Function | Purpose |
|----------|---------|
| `compute_cel(df)` | Vectorised CEL computation from raw persona columns. Input df must have `p32_pueblo_per`, `p32_pueblos`, `p331_idiohab1_cod`, `p332_idiohab2_cod`, `p333_idiohab3_cod`, `p341_idiomat_cod`. Returns numeric vector (0–7 with half-steps 1.5, 4.5). |
| `read_census_geo(geo_codes, urban_rural, extra_cols)` | Load and filter census persona data by geography. `geo_codes`: character vector of 2-digit (dept), 4-digit (prov), or 6-digit (mun) INE codes. Automatically joins `urbrur` from Vivienda, computes CEL, adds `cel_chr` factor, `age_group`, `idioma_label`, and `dwelling_key`. Returns a list with `$data` (tibble), `$geo_label`, `$ur_label`. Optional `urban_rural = "urban"` or `"rural"` to filter. |

### Usage pattern

```r
source("cel_helpers.R")
result <- read_census_geo("0201")          # Province of Murillo (La Paz)
result <- read_census_geo("020101", urban_rural = "urban")  # La Paz city, urban
df <- result$data
```

## Wikipedia reference extraction pipeline

Two parallel tools extract bibliographic references from Wikipedia citation templates and export them to Zotero:

### Files

| File | Description |
|------|-------------|
| `wiki-to-ris.html` | Browser-based JS/HTML tool. Fetches wikitext, extracts citation templates, outputs RIS format. No server required. |
| `wiki-refs-to-zotero.R` | R pipeline. Same extraction logic plus c2z enrichment (DOI/ISBN lookups), deduplication, direct Zotero API posting, and graceful error handling (`safe_stage`). |
| `wiki-refs-to-zotero-examples.R` | Usage examples for the R pipeline. |

### Supported citation templates (English Wikipedia)

Both tools handle: `cite book`, `cite journal`, `cite web`, `cite news`, `cite encyclopedia`, `cite odnb`, `cite magazine`, `cite thesis`, `cite conference`, `cite report`, `cite press release`, `cite av media`, `cite podcast`, `cite speech`, `harvc`.

The **R version only** additionally handles:
- `{{Citation}}` — generic template; item type inferred from parameters (`chapter=` → bookSection, `journal=` → journalArticle, default → book).
- `{{Cite EB1911}}` — Encyclopædia Britannica 11th ed.; maps to encyclopediaArticle with fixed bookTitle.

### Template → Zotero item type mapping

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

### Brooklyn test case (6 Mar 2026)

Tested all three import methods against the Brooklyn Wikipedia article:

| Source | Items | Unique items |
|--------|------:|------:|
| Pipeline (R) | 189 | 54 (mostly `document` from URL-less templates) |
| CoiNS (Zotero translator) | 153 | 9 (web sources CoiNS scraped from page metadata) |
| RIS (Zotero translator) | 131 | 1 (whitespace variant) |
| Shared (all three) | 127 | — |

CoiNS misclassifies most items as `book` or `journalArticle`. RIS preserves types faithfully but captures fewer items. The pipeline captures the most references but produces `document` for non-templated `<ref>` content.

### Known issues & next steps

1. **JS version needs `{{Citation}}` and `{{Cite EB1911}}`** — currently only in R. All templated citation types should be brought into the JS version.
2. **R version should stop extracting bare (non-templated) `<ref>` content** — these are as often actual footnotes as they are bibliographic references. The `extract_bare_refs()` function should be removed or made opt-in.
3. **French and Spanish citation templates** need to be mapped and added for multilingual support. See `data/wiki-citation-templates-multilingual.md` for the cross-language template mapping.
4. **Zotero library index**: `check_library_for_refs()` downloads the entire library (~16k items, ~160 API requests) for duplicate checking. Should be replaced with a cached local index using version-based incremental sync, or per-item search.
5. **`zotero_access_key` env var** lacks read permission on the personal library. Use `zotero_access_key_write` for all API calls.

---

## wiki-language-diversity-v2.qmd: Macrolanguage Mappings (7 Mar 2026)

### Complete mapping set (added 3 new in Mar 2026)

All zero-article languages now mapped via `wp_to_bcp47_extra` (lines 84–123):

**Chinese macrolanguage (zho):**
- `cmn` → `zh` (Mandarin Chinese, 1.29B speakers)
- `cjy` → `zh` (Jinyu Chinese, 63M)
- `hsn` → `zh` (Xiang Chinese, 40M)

**Arabic macrolanguage (ara):**
- `arz` → `ar` (Egyptian Arabic, 78M)
- `arq` → `ar` (Algerian Arabic, 36M)
- `apd` → `ar` (Sudanese Arabic, 37M)
- `aec` → `ar` (Saidi Arabic, 25M)
- `acm`, `acw`, `acx`, `ayp`, `ayh`, `ayl`, `ayn`, `abh`, `acy` → `ar` (other dialects, ~50M combined)

**Other languages:**
- `azj` → `az` (North Azerbaijani, 24M)
- `kpv` → `ku` (Southern Kurdish)
- `xmv` → `mg` (Antankarana Malagasy, 25M) — **NEW (7 Mar 2026)**
- `tts` → `th` (Northeastern Thai, 17M) — **NEW (7 Mar 2026)**
- `lah` → `pnb` (Lahnda, 93M, maps to Western Punjabi) — **NEW (7 Mar 2026)**

### Impact (7 Mar 2026 additions)

| Language | Speakers | Wikipedia | Articles |
|----------|----------|-----------|----------|
| Antankarana Malagasy | 25M | Malagasy (mg) | 102,259 |
| Northeastern Thai | 17M | Thai (th) | 180,368 |
| Lahnda | 93M | Western Punjabi (pnb) | 75,213 |
| **Total** | **135M** | — | **357,840** |

### Documentation files

- `documentation/ZERO_ARTICLES_REFERENCE.md` — Updated with three new languages
- `documentation/WIKI_LANGUAGE_DIVERSITY_LATEST_ADDITIONS.md` — **NEW (7 Mar 2026)** — detailed notes on the three additions
- `documentation/JOIN_LOGIC_CORRECTION_7MAR2026.md` — **NEW (7 Mar 2026)** — critical fix: map direction was reversed

### Critical Fix: Join Logic (7 Mar 2026)

**The Problem**: The join was backwards. `wp_to_bcp47_extra` was being applied to Wikipedia codes instead of linguameta codes.

**Original (broken)**:
```r
wiki_joined <- wiki |> mutate(bcp47_lookup = coalesce(wp_to_bcp47_extra[wp_code_clean], wp_code_clean))
linguameta_with_wiki <- linguameta |> left_join(wiki_joined, by = c("bcp_47_code" = "bcp47_lookup"))
```
Result: cmn tried to match to cmn (not zh) → 0 articles

**Fixed**:
```r
linguameta_with_wiki <- linguameta |>
  mutate(bcp47_wiki_lookup = coalesce(wp_to_bcp47_extra[bcp_47_code], bcp_47_code)) |>
  left_join(wiki_joined, by = c("bcp47_wiki_lookup" = "wp_code_clean"))
```
Result: cmn→zh, lah→pnb, etc. Now correctly matches to Wikipedia

**Impact**: All five languages (cmn, lah, xmv, tts, arz) now appear with proper article counts:
- Mandarin Chinese: 1.5M articles
- Egyptian Arabic: 1.3M articles
- Lahnda: 75K articles
- Northeastern Thai: 180K articles
- Antankarana Malagasy: 102K articles

### Comprehensive Mappings (7 Mar 2026 - Extended, two rounds)

After systematic search of zero-article languages against available Wikipedia editions, **added 22 additional mappings** (282.8M speakers, 6.35M+ articles):

**New mappings cover:**
- **Uzbek**: Northern (28M) & Southern (4.2M) → Uzbek Wikipedia (334K articles)
- **Persian/Pashto**: Iranian Persian (12M), Southern Pashto (14.9M), Central Pashto (6.5M) → Persian & Pashto Wikipedias
- **Arabic**: Ta'Izzi-Adeni (12M) → Arabic Wikipedia (1.3M articles)
- **Javanese**: Caribbean Javanese (82M) → Javanese Wikipedia (75K articles)
- **Thai**: Northern (6.6M) & Southern (5.5M) → Thai Wikipedia (180K articles)
- **Odia**: Odia (35M) → Odia Wikipedia (20.5K articles)
- **And others**: Nepali, Swahili, German, Malay, Oromo, Mongolian, Dinka, Albanian

**Impact**: Reduced zero-article languages from 87 to 65 (22 covered). Total speakers now with Wikipedia coverage increased by 283M.

**Files created**: `documentation/COMPREHENSIVE_LANGUAGE_MAPPINGS_7MAR2026.md`

### Second-round additions (7 Mar 2026 - continued)

After deeper research into reversed identity mappings, Norwegian/Belarusian orthographic variants, and remaining dialect/macro mismatches, added 17 more:

**Reversed identity mappings** (WP uses non-standard codes; these were previously broken):
- `yue` → `zh-yue` (Yue Chinese/Cantonese, 79M → 149K articles)
- `nan` → `zh-min-nan` (Min Nan Chinese, 42M → 434K articles)

**Norwegian**: `nb` → `no` (Norwegian Bokmål, 10.5M → 679K articles). Belarusian `be` was already matched directly; `be-tarask` has no separate linguameta entry.

**New dialect/macro mappings**: `fil`→`tl` (Filipino/Tagalog), `bho`→`bh` (Bhojpuri), `prs`→`fa` (Dari/Persian), `fuv`+`fuc`→`ff` (Fulfulde), `kng`→`kg` (Koongo), `gug`→`gn` (Guaraní), `sdh`→`ku` (Southern Kurdish), `hno`→`pnb` (N. Hindko), `czh`→`zh` (Huizhou Chinese), `bik`→`bcl` (Bikol), `mui`→`ms` (Musi)

**Code fixes**: `kr`→`knc` (Kanuri — WP uses knc not kr); `kpv`→`kv` (Komi-Zyrian — was wrongly mapped to `ku`/Kurdish)

**Additional**: `kok`→`gom` (Konkani → Goan Konkani), `tzm`→`zgh` (Tamazight → Standard Moroccan Amazigh)

**Status after all rounds**: 87 → **47 zero-article languages** (46% reduction)

## Metadata convention for imported data tables

When data is manually transcribed from a published source (e.g. scanning a table from a book or PDF), the project uses a three-file convention:

1. **Import script** (e.g. `molina-albo-2006.R`): Contains only the data and transformation code. Points to the metadata files via comments at the top.
2. **YAML sidecar** (e.g. `data/molina-albo-2006.yml`): Structured provenance metadata including bibliographic citation, import handling notes (how the raw image was transcribed), published notes (footnotes, formatting conventions from the original), and a list of output files.
3. **Frictionless Data package descriptor** (`data/datapackage.json`): Column-level schemas for the CSV outputs, following the [Frictionless Data](https://frictionlessdata.io/) `datapackage.json` spec. Includes source citation and license info.

### Naming conventions

- YAML sidecar: `data/<script-basename>.yml`
- CSV/RDS outputs: `data/<descriptive_name>.csv` / `.rds`
- Import script: `<author>-<year>.R` (project root)

### Current instances

| Source | Script | YAML | Outputs |
|--------|--------|------|---------|
| Molina Barrios & Albó (2006), Cuadro 8.1 | `molina-albo-2006.R` | `data/molina-albo-2006.yml` | `molina_albo_8_1_es.*`, `molina_albo_8_1_en.*` |
| OEP Elecciones Generales 2025 | `import-eg2025.R` | `data/import-eg2025.yml` | `eg2025_presidente_mesa.*` |
