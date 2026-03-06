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
