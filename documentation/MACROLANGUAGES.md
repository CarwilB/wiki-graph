# Macrolanguages: SIL-linguameta Merged Dataset

## Overview

This document describes the merged macrolanguages dataset combining:
- **ISO 639-3 SIL Macrolanguage Mappings** (https://iso639-3.sil.org/code_tables/macrolanguage_mappings/read)
- **linguameta_metadata** (7,511 language records with speaker counts and endangerment status)

**Result**: A unified table of 459 macrolanguage-member relationships across 63 macrolanguages, with full ISO 639 codes, names, speaker estimates, and metadata.

---

## Key Statistics

### Coverage

| Metric | Count | Percentage |
|--------|-------|-----------|
| Total Macrolanguages | 63 | — |
| Total Member Languages | 459 | — |
| Members in linguameta | 431 | 93.9% |
| Members missing from linguameta | 28 | 6.1% |

### Name Source Preference

- **All 459 members** have English names
- **431 use linguameta names** (from linguameta_metadata)
- **28 use SIL names only** (not in linguameta)
- **SIL "(individual language)" suffix removed** from all names for consistency

### Name Consistency

For the 431 members present in both sources:
- **Names match exactly**: 411 (95.4%)
- **Names differ**: 20 (4.6%)

---

## Name Discrepancies (20 cases)

### Classification

#### 1. Capitalization Differences (6 cases)
Minor case/punctuation variations in proper nouns or compound names.

| Member Code | Linguameta | SIL |
|-------------|-----------|-----|
| acq | Ta'Izzi-Adeni Arabic | Ta'izzi-Adeni Arabic |
| ubl | Buhi'Non Bikol | Buhi'non Bikol |
| qus | Santiago Del Estero Quichua | Santiago del Estero Quichua |
| qvh | Huamalíes-Dos De Mayo Huánuco Quechua | Huamalíes-Dos de Mayo Huánuco Quechua |
| qxt | Santa Ana De Tusi Pasco Quechua | Santa Ana de Tusi Pasco Quechua |
| zaa | Sierra De Juárez Zapotec | Sierra de Juárez Zapotec |

#### 2. SIL Clarification Additions (9 cases)
SIL's original names included "(individual language)" suffix to distinguish from the macrolanguage code. This suffix was **suppressed in the merged table**. Affected languages:

| Member Code | Original SIL Name (suppressed) | Final Name |
|-------------|-------------------------------|-----------|
| dgo | Dogri (individual language) | Dogri |
| knn | Konkani (individual language) | Konkani |
| msa/zlm | Malay (individual language) | Malay |
| npi | Nepali (individual language) | Nepali |
| swh | Swahili (individual language) | Swahili |
| zza (×2) | Dimli/Kirmanjki (individual language) | Dimli/Kirmanjki |

#### 3. Substantive Name Differences (5 cases)
Meaningful naming divergence between sources—linguameta uses different terminology than SIL.

| Member Code | Linguameta | SIL |
|-------------|-----------|-----|
| apc | North Levantine Arabic | Levantine Arabic |
| gom | Konkani | Goan Konkani |
| ckb | Sorani Kurdish | Central Kurdish |
| cnp | Northern Pinghua | Northern Ping Chinese |
| csp | Southern Pinghua | Southern Ping Chinese |

---

## Incomplete Linguameta Coverage

12 macrolanguages have members not represented in linguameta:

| Macrolanguage | Code | Total Members | In linguameta | Missing | % Missing |
|----------------|------|--------------|--------------|---------|-----------|
| Chinese | zho | 19 | 15 | 4 | 21.1% |
| Mandingo | man | 7 | 6 | 1 | 14.3% |
| Gbaya (CAR) | gba | 7 | 6 | 1 | 14.3% |
| Lahnda | lah | 8 | 7 | 1 | 12.5% |
| Zhuang | zha | 18 | 16 | 2 | 11.1% |
| Bikol | bik | 9 | 8 | 1 | 11.1% |
| Malagasy | mlg | 12 | 11 | 1 | 8.3% |
| Malay | msa | 37 | 35 | 2 | 5.4% |
| Quechua | que | 44 | 42 | 2 | 4.5% |
| Hmong | hmn | 26 | 25 | 1 | 3.8% |
| Arabic | ara | 30 | 29 | 1 | 3.3% |
| Zapotec | zap | 59 | 58 | 1 | 1.7% |

---

## Table Schema

### Main Merged Table: `macrolanguages_final`

**Dimensions**: 459 rows × 17 columns

| Column | Type | Description |
|--------|------|-------------|
| `macro_code` | chr | ISO 639-3 macrolanguage code (3 letters) |
| `macro_name` | chr | SIL reference name for macrolanguage |
| `member_code` | chr | ISO 639-3 member language code (3 letters) |
| `member_status` | chr | Active / Deprecated / Retired |
| `english_name` | chr | **Preferred English name (SIL priority, falls back to linguameta)** |
| `endonym` | chr | Self-designation in the language (if known) |
| `iso_639_3_code` | chr | ISO 639-3 code (same as member_code) |
| `iso_639_2b_code` | chr | ISO 639-2/B code (if applicable) |
| `glottocode` | chr | Glottocode identifier |
| `wikidata_id` | chr | Wikidata QID |
| `wikidata_description` | chr | Wikidata description |
| `n_speakers` | dbl | Estimated number of speakers |
| `endangerment` | chr | Endangerment status (UNESCO scale) |
| `writing_systems` | chr | Writing system codes (ISO 15924) |
| `locales` | chr | ISO 3166 locale codes |
| `cldr_official_status` | chr | CLDR official status |
| `in_linguameta` | lgl | TRUE if member has metadata in linguameta |

### Key Relationships

- **One macrolanguage → many members**: `macro_code` groups multiple `member_code` rows
- **Unique identifier**: `(macro_code, member_code)` pair
- **Metadata source**: Row has data from linguameta if `in_linguameta == TRUE`

---

## Data Preparation Notes

### Name Standardization

1. All SIL reference names had " (individual language)" suffix **stripped** for consistency
2. For members in both sources, SIL names take priority via `coalesce()`:
   ```r
   english_name = coalesce(member_reference_name_sil, english_name)
   ```
3. All 459 members now have non-null `english_name` values

### Coverage Logic

- `in_linguameta` is TRUE if the member appears in linguameta_metadata
- Members can have non-null speaker counts, endangerment status, etc. only if `in_linguameta == TRUE`
- 28 members appear only in SIL; they have SIL names but no speaker/endangerment data

### Quality Assurance

- All 459 SIL macrolanguage-member mappings successfully merged
- 431 members (93.9%) cross-referenced with linguameta metadata
- Name discrepancies (4.6% of matched pairs) documented and classified
- No data loss in join operations (many-to-one, no NAs introduced unexpectedly)

---

## Usage Examples

### Filter to a single macrolanguage
```r
macrolanguages_final |> filter(macro_code == "ara")
```

### Members with speaker data only
```r
macrolanguages_final |> filter(in_linguameta, !is.na(n_speakers))
```

### Endangered languages in a macrolanguage
```r
macrolanguages_final |> 
  filter(macro_code == "zho") |>
  filter(endangerment %in% c("Endangered", "Severely endangered", "Critically endangered"))
```

### Count members by endangerment status
```r
macrolanguages_final |>
  filter(in_linguameta) |>
  group_by(macro_code, endangerment) |>
  summarise(n = n(), .groups = "drop")
```

---

## Sources & Attribution

- **SIL Macrolanguage Mappings**: International organization for the study of language (SIL)
  - URL: https://iso639-3.sil.org/code_tables/macrolanguage_mappings/read
  - Last accessed: 2026-03-07
  
- **linguameta**: Language metadata derived from multiple authoritative sources
  - Includes speaker counts, endangerment status, writing systems, and Wikidata links

---

## Files Generated

- `macrolanguages_final.rds` — Serialized R object (for fast loading)
- `macrolanguages_enhanced_sil.csv` — CSV export (prior version, kept for reference)

---

**Generated**: 2026-03-07  
**Merge Source**: linguameta.R merge_with_sil_macrolanguages()
