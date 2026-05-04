# Bolivia 2024 Census (CPV 2024) Analysis

Person-level microdata analysis focused on indigenous identity and language. Infrastructure: `cel_helpers.R` computes the CEL (Condición Étnico-Lingüística) scale.

## Data Location

All files: `~/Dropbox (Personal)/R/bolivia-data/Censo 2024/`

## Key Files

### Person-level data

| File | Description |
|------|-------------|
| `base_datos_csv_2024/Persona_CPV-2024.csv` | Person-level microdata: 11,365,333 rows × 118 columns. All integers. ~3 GB, semicolon-delimited. Open lazily: `open_dataset(..., format="csv", delimiter=";")`. |
| `base_datos_csv_2024/Persona_CPV-2024_sample10k.rds` | 10,000-row sample (`set.seed(8143)`). Fast for testing. |
| `base_datos_csv_2024/Vivienda_CPV-2024.csv` | Household-level data. Join to Persona on `idep+iprov+imun+i00`. |

### Lookups & codebooks

| File | Description |
|------|-------------|
| `Diccionario de variables CPV 2024.xlsx` | Variable dictionary with value labels. Sheets: PERSONA, VIVIENDA, EMIGRA, MORTA. |
| `BOL-INE-CPV-2024.xml` | DDI codebook. Parse with `xml2`; namespace: `http://www.icpsr.umich.edu/DDI`. |
| `codebook_persona.rds` | Pre-parsed codebook tibble: `variable`, `label`, `description`, `question`. |
| `pueblo_cats.rds` | Lookup: `p32_pueblo_cod` (145 rows) → labels. |
| `idioma_cats.rds` | Lookup: language codes (83 categories) → labels. Loaded by `cel_helpers.R`. |

### Aggregated datasets

| File | Description |
|------|-------------|
| `albo_vars.rds` | Person-level indicators (11,365,333 rows): `idep`, `iprov`, `imun`, `urbrur`, `albo_q1`, `albo_q2`, `albo_q3`, `albo_c`, `cel_q2`, `cel`. |
| `lang_use.rds` | `idioma_mat × idioma_mayor_uso` (435 rows). |
| `lang_use_age.rds` | Same × `age_group` (5 bins: 0–14, 15–29, 30–44, 45–59, 60+) (1,319 rows). |
| `lang_use_urban.rds` | `idioma_mat × idioma_mayor_uso × urbrur_label` (658 rows). |
| `cel_geo.rds` | CEL geographic summary (1,214 rows): national, dept, prov, mun, + all × urban/rural. Columns: `cel_0`…`cel_7` (%), `cel_2plus`, `cel_4plus`, `cel_5plus`. |

## Key Person-level Variables

| Variable | Description |
|---|---|
| `idep` | Department code (1–9) |
| `iprov` | Province code |
| `imun` | Municipality code |
| `p25_sexo` | Sex: 1 = Mujer, 2 = Hombre |
| `p26_edad` | Age in years |
| `p32_pueblo_per` | Indigenous self-identification: 1 = Sí, 2 = No, 9 = Sin respuesta |
| `p32_pueblo_cod` | Raw group code (145 categories, 9xx generic, 5xx foreign). Lookup: `pueblo_cats.rds` |
| `p32_pueblos` | Derived CTAI-reconciled identity (58 categories, 98 = No identif., 99 = No respuesta). Labels in Qmd tribbles. |
| `idioma_mat` | Mother tongue code (83 categories). Key: 2=Aymara, 6=Castellano, 12=Guaraní, 27=Quechua, 998=No habla. |
| `idioma_mayor_uso` | Language of greatest daily use (same coding). |
| `p331_idiohab1_cod`, `p332_idiohab2_cod`, `p333_idiohab3_cod` | Three habitual languages (for CEL computation). |
| `p341_idiomat_cod` | Mother tongue (for CEL Q3: learned as child?) |
| `nivel_edu` | Educational attainment (19+ year olds) |
| `condact_19` | Labour force status (19th ICLS) |

## Important Coding Notes

- **`urbrur` is in Vivienda, not Persona.** Join on `idep+iprov+imun+i00`. All 11.4M rows match exactly (0 NAs).
- **`p32_pueblo_cod` ≠ `p32_pueblos`.** Do not join directly; both are needed for different analyses.
- **Afroboliviano language (code 94 in `idioma_mat`) is excluded** from linguistic analysis (Spanish variety, ~450 speakers, 92.7% in La Paz). Afroboliviano as ethnic identity is retained (25,168 identifiers, 86% Castellano-speaking).
- **Kabineña (7 idioma) = Cavineño (7 pueblos)**: same people, different spellings.
- **Zamuco (37 idioma) = Ayoreo (4 pueblos)**: Zamuco is ISO name, Ayoreo is ethnonym.
- **NAs in `p32_pueblo_cod`** are not missing data; they indicate "No" or no response to `p32_pueblo_per`.

## CEL Scale: Condición Étnico-Lingüística

Ordinal scale (0–7 with half-steps 1.5, 4.5) encoding Xavier Albó's framework. See `albo-restudy-2024.qmd` for full definition.

### Core Questions

| Variable | Question | Logic |
|---|---|---|
| `albo_q1` | Self-identifies indigenous? | `p32_pueblo_per == 1` |
| `albo_q2` | Spoken language matches identity? | Any of `p331/p332/p333` matches expected idioma codes for `p32_pueblos`. Generic identities and groups w/o census language equivalent default to "any indigenous language" rule (codes 1–5, 7–37). FALSE if Q1=FALSE. |
| `albo_q3` | Learned indigenous language as child? | `p341_idiomat_cod` ∉ {NA, 6, 999} |
| `albo_c` | Speaks Castellano? | Any of `p331/p332/p333` = 6 |

**`cel_q2` differs from `albo_q2`**: For non-identifiers (Q1=FALSE), `albo_q2` is always FALSE while `cel_q2` is TRUE if any Bolivian indigenous language is spoken (codes 1–5, 7–37). This allows non-identifiers to populate CEL 1–3.

## Using `cel_helpers.R`

Source with `source("cel_helpers.R")`:

```r
# Load census data for a geographic unit
result <- read_census_geo("0201")  # Province: Murillo (La Paz)
result <- read_census_geo("020101", urban_rural = "urban")  # Municipality: La Paz city, urban only
df <- result$data

# Compute CEL (if raw columns already in df)
df$cel <- compute_cel(df)
```

Function returns list: `$data` (tibble with CEL, `cel_chr` factor, `age_group`, `idioma_label`, `dwelling_key`), `$geo_label`, `$ur_label`.

## Census Analysis Findings (Feb 2026)

- **37.5%** self-identify as indigenous or afro-bolivian (`p32_pueblo_per == 1`).
- Self-identifiers: Quechua 39%, Aymara 37%, generic terms 12.6%.
- **Language shift is pronounced & age-graded**: 76% of 60+ speak indigenous mother tongue vs 22% of 0–14 year olds.
- **Self-identification declines with youth**: 49% of 60+ vs 28% of 0–14.
- **1.98M Castellano mother-tongue speakers** self-identify as indigenous (23% of 8.5M indigenous identifiers): Aymara 11%, Quechua 8%.
- **~57,000 Quechua speakers** identify with Andean sub-ethnic groups rather than pan-ethnic "Quechua" label.

## Key Documents

- `bolivia-censo-2024.qmd` — Main census analysis
- `albo-restudy-2024.qmd` — CEL scale study
- `albo-cel-grid-dept.qmd` — CEL visualizations by department
